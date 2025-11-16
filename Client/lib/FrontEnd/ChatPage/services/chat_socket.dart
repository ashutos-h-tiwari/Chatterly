import 'package:socket_io_client/socket_io_client.dart' as IO;

typedef VoidData = void Function(dynamic data);

class ChatSocket {
  ChatSocket({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  IO.Socket? _socket;
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
    _socket!.onConnect((_) {
      if (roomId != null) _socket!.emit('join:conversation', {'conversationId': roomId});
      if (roomId != null) _socket!.emit('messages:markRead', {'conversationId': roomId});
    });
    _socket!.onConnect((_) => join());
    _socket!.on('reconnect', (_) => join());

    if (onIncoming != null) {
      _socket!.on('message:new', onIncoming);
      _socket!.on('message', onIncoming);
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
}
