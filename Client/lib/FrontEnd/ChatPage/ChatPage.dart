import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

enum MessageStatus { sending, sent, delivered, read }

class ChatPage extends StatefulWidget {
  final String chatUserId;    // other user’s ID
  final String chatUserName;  // other user’s display name

  const ChatPage({
    super.key,
    required this.chatUserId,
    required this.chatUserName,
  });

  @override
  _ChatPageState createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  static const String kBackendBase = 'https://chatterly-backend-f9j0.onrender.com';

  // ✅ endpoints (singular removed)
  static const String kCreateConversationPlural = '$kBackendBase/api/chat/conversations';

  static String kConvMessages(String roomId) =>
      '$kBackendBase/api/chat/conversations/$roomId/messages';
  static String kConvOne(String roomId) =>
      '$kBackendBase/api/chat/conversations/$roomId';
  static String kConvSend(String roomId) =>
      '$kBackendBase/api/chat/conversations/$roomId/messages';

  final TextEditingController _controller = TextEditingController();
  final List<ChatMessage> _messages = [];

  IO.Socket? _socket;
  String? _token;
  String? _myUserId;
  String? _roomId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    try {
      if (_roomId != null) {
        // ✅ canonical leave event
        _socket?.emit('leave:conversation', {'conversationId': _roomId});
      }
      _socket?.disconnect();
      _socket?.dispose();
    } catch (_) {}
    _controller.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('token');
      _myUserId = prefs.getString('userId');

      if (_token == null || _token!.isEmpty || _myUserId == null || _myUserId!.isEmpty) {
        _snack('Please login again.');
        if (mounted) Navigator.pop(context);
        return;
      }

      if (widget.chatUserId.isEmpty) {
        _snack('Cannot open chat: participantId missing');
        if (mounted) Navigator.pop(context);
        return;
      }

      // 1) Create or fetch 1-1 conversation
      final conv = await _createOrGetConversation(widget.chatUserId);
      _roomId = _extractRoomId(conv);

      if (_roomId == null || _roomId!.isEmpty) {
        _snack('Unable to create/find conversation');
        if (mounted) Navigator.pop(context);
        return;
      }

      // 2) Load previous messages
      await _loadMessages(_roomId!);

      // 3) Connect socket
      _connectSocket();
    } catch (e) {
      _snack('Setup failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---- Conversation creation: single POST + light retry ----
  Future<Map<String, dynamic>> _createOrGetConversation(String otherUserId) async {
    final uri = Uri.parse(kCreateConversationPlural);

    Future<http.Response> _post() => http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $_token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'participantId': otherUserId}),
    );

    var resp = await _post();

    // Rare race/limit → small retry
    if (resp.statusCode == 409 || resp.statusCode == 429) {
      await Future.delayed(const Duration(milliseconds: 300));
      resp = await _post();
    }

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return _unwrapConv(jsonDecode(resp.body));
    }
    throw Exception('Conversation error: ${resp.statusCode} ${resp.body}');
  }

  Map<String, dynamic> _unwrapConv(dynamic body) {
    if (body is Map) {
      if (body['conversation'] is Map) {
        return (body['conversation'] as Map).map((k, v) => MapEntry(k.toString(), v));
      }
      if (body['data'] is Map) {
        return (body['data'] as Map).map((k, v) => MapEntry(k.toString(), v));
      }
      return body.map((k, v) => MapEntry(k.toString(), v));
    }
    throw const FormatException('Unexpected conversation response');
  }

  String? _extractRoomId(Map<String, dynamic> conv) {
    return (conv['_id'] ??
        conv['id'] ??
        conv['roomId'] ??
        conv['conversationId'])
        ?.toString();
  }

  // ---- Load messages ----
  Future<void> _loadMessages(String roomId) async {
    http.Response res;

    res = await http.get(
      Uri.parse(kConvMessages(roomId)),
      headers: {
        'Authorization': 'Bearer $_token',
        'Accept': 'application/json',
      },
    );

    if (res.statusCode == 404) {
      res = await http.get(
        Uri.parse(kConvOne(roomId)),
        headers: {
          'Authorization': 'Bearer $_token',
          'Accept': 'application/json',
        },
      );
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final body = jsonDecode(res.body);

      List list;
      if (body is Map && body['messages'] is List) {
        list = body['messages'] as List;
      } else if (body is Map && body['data'] is Map && body['data']['messages'] is List) {
        list = body['data']['messages'] as List;
      } else if (body is Map && body['data'] is List) {
        list = body['data'] as List;
      } else if (body is List) {
        list = body;
      } else {
        list = const [];
      }

      final msgs = list
          .map((m) => ChatMessage.fromJson(_asStringKeyMap(m), myUserId: _myUserId))
          .toList();

      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(msgs);
      });
    } else {
      _snack('Failed to load messages: ${res.statusCode}');
    }
  }

  // ---- Socket ----
  void _connectSocket() {
    _socket = IO.io(
      kBackendBase,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()                     // ✅ auto-reconnect
          .setReconnectionAttempts(0)               // unlimited
          .setReconnectionDelay(500)
          .setReconnectionDelayMax(4000)
          .setTimeout(8000)
          .setQuery({'token': _token})              // ✅ server reads query OR auth
          .build(),
    );

    _socket!.onConnect((_) {
      if (_roomId != null) {
        // ✅ canonical join event + field name
        _socket!.emit('join:conversation', {'conversationId': _roomId});
      }
    });

    // ✅ on reconnect, re-join the room
    _socket!.on('reconnect', (_) {
      if (_roomId != null) {
        _socket!.emit('join:conversation', {'conversationId': _roomId});
      }
    });

    // ✅ robust incoming handler: de-dup by _id then by clientId (optimistic)
    void onIncoming(dynamic data) {
      final map = _asStringKeyMap(data);
      final incoming = ChatMessage.fromJson(map, myUserId: _myUserId);
      final incomingId = incoming.id;

      // 1) de-dup by server _id
      final idIdx = _messages.indexWhere((m) => m.id == incomingId);
      if (idIdx != -1) {
        if (!mounted) return;
        setState(() => _messages[idIdx] = incoming);
        return;
      }

      // 2) optimistic replace by clientId (if server echoed it)
      final clientId = map['clientId']?.toString();
      if (clientId != null) {
        final pendIdx = _messages.indexWhere((m) => m.id == clientId);
        if (pendIdx != -1) {
          if (!mounted) return;
          setState(() => _messages[pendIdx] = incoming);
          return;
        }
      }

      // 3) append
      if (!mounted) return;
      setState(() => _messages.add(incoming));
    }

    _socket!.on('message:new', onIncoming);
    _socket!.on('message', onIncoming); // fallback

    _socket!.on('message:status', (data) {
      final map = _asStringKeyMap(data);
      final id = map['_id']?.toString();
      final statusStr = map['status']?.toString();
      if (id == null || statusStr == null) return;
      final status = _parseStatus(statusStr);
      final idx = _messages.indexWhere((m) => m.id == id);
      if (idx != -1 && mounted) {
        setState(() => _messages[idx] = _messages[idx].copyWith(status: status));
      }
    });

    _socket!.connect();
  }

  MessageStatus _parseStatus(String s) {
    switch (s) {
      case 'sent':
        return MessageStatus.sent;
      case 'delivered':
        return MessageStatus.delivered;
      case 'read':
        return MessageStatus.read;
      default:
        return MessageStatus.sending;
    }
  }

  // ---- Send ----
  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _roomId == null) return;

    final tempId = UniqueKey().toString(); // ✅ clientId
    final pending = ChatMessage(
      id: tempId,
      text: text,
      isSentByMe: true,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
    );

    setState(() {
      _messages.add(pending);
      _controller.clear();
    });

    try {
      final url = kConvSend(_roomId!);
      final resp = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $_token',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'text': text,
          'clientId': tempId, // ✅ so server echoes it & socket replace works
        }),
      );

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final raw = jsonDecode(resp.body);
        final obj = (raw is Map && raw['data'] is Map) ? raw['data'] : raw;
        final saved = ChatMessage.fromJson(_asStringKeyMap(obj), myUserId: _myUserId);

        final i = _messages.indexWhere((m) => m.id == tempId);
        if (i != -1 && mounted) {
          setState(() => _messages[i] = saved.copyWith(status: MessageStatus.sent));
        }
      } else {
        _snack('Send failed: ${resp.statusCode}');
        // optional: mark failed state if you want UI indicator
        // final i = _messages.indexWhere((m) => m.id == tempId);
        // if (i != -1 && mounted) {
        //   setState(() => _messages[i] = _messages[i].copyWith(status: MessageStatus.sending));
        // }
      }
    } catch (_) {
      _snack('Network error while sending');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _buildStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return const Icon(Icons.access_time, size: 16, color: Colors.grey);
      case MessageStatus.sent:
        return const Icon(Icons.check, size: 16, color: Colors.grey);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 16, color: Colors.grey);
      case MessageStatus.read:
        return const Icon(Icons.done_all, size: 16, color: Colors.blue);
    }
  }

  String _formatTimestamp(DateTime ts) {
    final now = DateTime.now();
    if (now.difference(ts).inDays == 0) {
      final hh = ts.hour.toString().padLeft(2, '0');
      final mm = ts.minute.toString().padLeft(2, '0');
      return "$hh:$mm";
    }
    return "${ts.day}/${ts.month}/${ts.year}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chatUserName),
        backgroundColor: Colors.teal.shade600,
      ),
      backgroundColor: const Color(0xFFE5DDD5),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
              reverse: true,
              padding: const EdgeInsets.all(8),
              itemCount: _messages.length,
              itemBuilder: (_, index) {
                final message = _messages[_messages.length - 1 - index];
                return Align(
                  alignment: message.isSentByMe
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 14),
                    decoration: BoxDecoration(
                      color: message.isSentByMe
                          ? Colors.teal.shade400
                          : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(12),
                        topRight: const Radius.circular(12),
                        bottomLeft: message.isSentByMe
                            ? const Radius.circular(12)
                            : Radius.zero,
                        bottomRight: message.isSentByMe
                            ? Radius.zero
                            : const Radius.circular(12),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: message.isSentByMe
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          message.text,
                          style: TextStyle(
                            color: message.isSentByMe
                                ? Colors.white
                                : Colors.black87,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatTimestamp(message.timestamp),
                              style: TextStyle(
                                color: message.isSentByMe
                                    ? Colors.white70
                                    : Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                            if (message.isSentByMe) ...[
                              const SizedBox(width: 4),
                              _buildStatusIcon(message.status),
                            ],
                          ],
                        )
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(color: Colors.black),
                      decoration: InputDecoration(
                        hintText: 'Type a message',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        fillColor: Colors.blueGrey[200],
                        filled: true,
                        contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: Colors.teal.shade600,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- helpers ----
Map<String, dynamic> _asStringKeyMap(dynamic x) {
  if (x is Map<String, dynamic>) return x;
  if (x is Map) return x.map((k, v) => MapEntry(k.toString(), v));
  return <String, dynamic>{};
}

// ---- DATA MODEL ----
class ChatMessage {
  final String id;
  final String text;
  final bool isSentByMe;
  final DateTime timestamp;
  final MessageStatus status;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isSentByMe,
    required this.timestamp,
    this.status = MessageStatus.sent,
  });

  ChatMessage copyWith({
    String? id,
    String? text,
    bool? isSentByMe,
    DateTime? timestamp,
    MessageStatus? status,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      text: text ?? this.text,
      isSentByMe: isSentByMe ?? this.isSentByMe,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json, {String? myUserId}) {
    String? senderId;
    final senderRaw = json['sender'];
    if (senderRaw is Map) {
      senderId = senderRaw['_id']?.toString() ?? senderRaw['id']?.toString();
    } else {
      senderId = json['senderId']?.toString() ??
          json['sender']?.toString() ??
          (json['from'] is Map ? json['from']['_id']?.toString() : json['from']?.toString());
    }

    final createdAt = json['createdAt']?.toString() ??
        json['time']?.toString() ??
        json['sentAt']?.toString();

    final text = json['text']?.toString() ??
        json['content']?.toString() ??
        json['message']?.toString() ??
        '';

    return ChatMessage(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? UniqueKey().toString(),
      text: text,
      isSentByMe: (myUserId != null && senderId == myUserId),
      timestamp: createdAt != null
          ? (DateTime.tryParse(createdAt) ?? DateTime.now())
          : DateTime.now(),
      status: MessageStatus.sent,
    );
  }
}
