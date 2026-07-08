import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:socket_io_client/socket_io_client.dart' as IO;

import '../utils/json_utils.dart';
import 'e2e/e2e_service.dart';

typedef VoidData = void Function(dynamic data);

class ChatSocket {
  ChatSocket({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  IO.Socket? _socket;

  bool get isConnected => _socket?.connected ?? false;
  // ADD these helpers at top-level in the file
  bool _payloadSaysTypingOn(dynamic data) {
    // accepts: {isTyping:true} OR {typing:true} OR "start"/"stop"
    final m = (data is Map) ? data : {};
    final s = (m['state'] ?? m['type'] ?? m['event'] ?? '').toString().toLowerCase();
    if (m['isTyping'] == true || m['typing'] == true) return true;
    if (s.contains('start')) return true;
    return false;
  }

  String? _payloadConversationId(dynamic data) {
    final m = (data is Map) ? data : {};
    return (m['conversationId'] ?? m['roomId'] ?? m['cid'] ?? m['conv'] ?? m['id'])?.toString();
  }

  String? _payloadUserId(dynamic data) {
    final m = (data is Map) ? data : {};
    final u = m['user'] ?? m['sender'] ?? m['from'] ?? m['userId'];
    if (u is Map) return (u['_id'] ?? u['id'])?.toString();
    return u?.toString();
  }

  void connect({
    required String? roomId,
    VoidData? onIncoming,
    VoidData? onStatus,
    VoidData? onTypingStart,
    VoidData? onTypingStop,
  }) {
    _socket = IO.io(
      baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(0)
          .setReconnectionDelay(500)
          .setReconnectionDelayMax(4000)
          .setTimeout(8000)
          .setQuery({'token': token})
          .build(),
    );
    void join() {
      if (roomId != null) {
        _socket!.emit('join:conversation', {'conversationId': roomId});
        _socket!.emit('messages:markRead', {'conversationId': roomId});
      }
    }
    // _socket!.onConnect((_) {
    //   if (roomId != null) _socket!.emit('join:conversation', {'conversationId': roomId});
    //   if (roomId != null) _socket!.emit('messages:markRead', {'conversationId': roomId});
    // });
    _socket!.onConnect((_) => join());
    _socket!.on('reconnect', (_) => join());

    if (onIncoming != null) {
      // _socket!.on('message:new', (data) async {
      //   try {
      //     final map = data as Map;
      //     if (map['isEncrypted'] == true) {
      //       final senderPubKey = await _fetchPubKey(map['senderId']); // see below
      //       final plain = await E2EService.decrypt(map['text'], senderPubKey);
      //       onIncoming({...map, 'text': plain});
      //     } else {
      //       onIncoming(data);
      //     }
      //   } catch (_) {
      //     onIncoming(data); // fallback
      //   }
      // });
      _socket!.on('message:new', (data) async {
        try {
          final map = asStringKeyMap(data as Map);
          final cipherText = map['cipherText']?.toString();
          final contentType = map['contentType']?.toString() ?? 'signal:whisper';
          final senderId = (map['sender'] is Map)
              ? (map['sender']['_id'] ?? map['sender']['id'])?.toString()
              : map['senderId']?.toString();

          if (cipherText != null && cipherText.isNotEmpty && senderId != null) {
            // Ensure a Signal/X3DH session exists with the sender before decrypting.
            // Non-forced: reuse an existing session/ratchet if we have one.
            // E2EService.decrypt already retries internally with a forced
            // session rebuild if it hits an untrusted-identity or bad-MAC
            // error, so we don't burn a one-time prekey on every message here.
            try {
              await E2EService.buildSession(senderId, token);
            } catch (e) {
              try { debugPrint('E2EService.buildSession failed for $senderId: ${e.toString()}'); } catch (_) {}
            }

            try {
              // pass token so decrypt can attempt session rebuild+retry on Bad Mac
              final plain = await E2EService.decrypt(senderId, cipherText, contentType, token: token);
              onIncoming({...map, 'text': plain, 'cipherText': null});
            } catch (e, st) {
              try { debugPrint('E2EService.decrypt failed (socket) for $senderId: ${e.toString()}'); } catch (_) {}
              try { debugPrint(st.toString()); } catch (_) {}
              // Deliver a clear fallback so UI shows decryption failure instead of raw cipher.
              onIncoming({...map, 'text': '[Could not decrypt]'});
            }
          } else {
            onIncoming(data);
          }
        } catch (_) {
          onIncoming(data); // fallback to raw
        }
      });
    }

    if (onStatus != null) {
      _socket!.on('message:status', onStatus);
    }

    void handleTyping(dynamic data, {required bool started}) {
      // Filter to current conversation here; ChatPage also filters again with userId
      final cid = _payloadConversationId(data);
      if (roomId != null && cid != null && cid != roomId) return;
      if (started) {
        if (onTypingStart != null) onTypingStart(data);
      } else {
        if (onTypingStop != null) onTypingStop(data);
      }
    }

    // common names
    _socket!.on('typing:start', (d) => handleTyping(d, started: true));
    _socket!.on('typing:stop', (d) => handleTyping(d, started: false));

    // other popular variants
    _socket!.on('typing', (d) {
      final on = _payloadSaysTypingOn(d);
      handleTyping(d, started: on);
    });
    _socket!.on('user:typing', (d) {
      final on = _payloadSaysTypingOn(d);
      handleTyping(d, started: on);
    });
    _socket!.on('typingStart', (d) => handleTyping(d, started: true));
    _socket!.on('typingStop', (d) => handleTyping(d, started: false));

    _socket!.connect();
  }
  // final Map<String, String> _pubKeyCache = {};
  // Future<String> _fetchPubKey(String userId) async {
  //   if (_pubKeyCache.containsKey(userId)) return _pubKeyCache[userId]!;
  //   final res = await http.get(Uri.parse(
  //       'https://chatterly-backend-f9j0.onrender.com/api/keys/$userId'),
  //       headers: {'Authorization': 'Bearer $token'});
  //   final key = jsonDecode(res.body)['publicKey'] as String;
  //   _pubKeyCache[userId] = key;
  //   return key;
  // }

  void emitTypingStart(String? roomId) {
    if (roomId == null) return;
    final payload = {'conversationId': roomId, 'isTyping': true, 'state': 'start'};
    _socket?.emit('typing:start', payload);
    // also emit a generic fallback event name some servers expect:
    _socket?.emit('typing', payload);
  }

  void emitTypingStop(String? roomId) {
    if (roomId == null) return;
    final payload = {'conversationId': roomId, 'isTyping': false, 'state': 'stop'};
    _socket?.emit('typing:stop', payload);
    _socket?.emit('typing', payload);
  }


  void emitDeliveredRead(String? roomId, String messageId) {
    if (roomId == null) return;
    _socket?.emit('message:delivered', {'conversationId': roomId, 'messageId': messageId});
    _socket?.emit('message:read', {'conversationId': roomId, 'messageId': messageId});
  }

  void markAllRead(String? roomId) {
    if (roomId == null) return;
    _socket?.emit('messages:markRead', {'conversationId': roomId});
  }

  void leave(String? roomId) {
    if (roomId != null) {
      _socket?.emit('leave:conversation', {'conversationId': roomId});
    }
    _socket?.disconnect();
  }

  void dispose() {
    _socket?.dispose();
  }
//changes
  void rejoin(String roomId) {
    _socket?.emit('join:conversation', {'conversationId': roomId});
    _socket?.emit('messages:markRead', {'conversationId': roomId});
  }

}