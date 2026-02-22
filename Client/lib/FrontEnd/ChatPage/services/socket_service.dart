import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  // ─── Singleton ───────────────────────────────────────────────────────────
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  // ─── Socket instance ─────────────────────────────────────────────────────
  IO.Socket? _socket;
  IO.Socket? get socket => _socket;

  bool get isConnected => _socket?.connected ?? false;

  // ─── Connect ─────────────────────────────────────────────────────────────
  /// Call this right after login. Pass the JWT token and your server URL.
  void connect(String token, {String serverUrl =  'https://chatterly-backend-f9j0.onrender.com'}) {
    if (_socket != null && _socket!.connected) {
      print('✅ Socket already connected');
      return;
    }

    _socket = IO.io(
      serverUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'token': token})
          .setTimeout(10000)
          .setReconnectionAttempts(5)
          .build(),
    );

    _socket!.connect();

    _socket!.onConnect((_) {
      print('✅ Socket connected: ${_socket!.id}');
    });

    _socket!.onDisconnect((_) {
      print('❌ Socket disconnected');
    });

    _socket!.onConnectError((err) {
      print('⚠️ Socket connect error: $err');
    });
  }

  // ─── Join a conversation room ─────────────────────────────────────────────
  void joinConversation(String conversationId) {
    _socket?.emit('join:conversation', {'conversationId': conversationId});
  }

  // ─── Emit any event ──────────────────────────────────────────────────────
  void emit(String event, dynamic data) {
    if (_socket == null || !_socket!.connected) {
      print('⚠️ Cannot emit "$event" — socket not connected');
      return;
    }
    _socket!.emit(event, data);
  }

  // ─── Listen to any event ─────────────────────────────────────────────────
  void on(String event, Function(dynamic) handler) {
    _socket?.on(event, handler);
  }

  // ─── Remove a listener ───────────────────────────────────────────────────
  void off(String event) {
    _socket?.off(event);
  }

  // ─── Disconnect ──────────────────────────────────────────────────────────
  void disconnect() {
    _socket?.disconnect();
    _socket = null;
    print('🔌 Socket manually disconnected');
  }
}
