import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:async';

typedef Json = Map<String, dynamic>;

class CallSocket {
  final String serverUrl;
  final String? token;
  IO.Socket? _socket;

  // Broadcast streams allow multiple listeners (ChatPage AND CallScreen)
  final StreamController<Json> _incomingCall = StreamController.broadcast();
  final StreamController<Json> _callAnswered = StreamController.broadcast();
  final StreamController<Json> _iceCandidate = StreamController.broadcast();
  final StreamController<Json> _callEnded = StreamController.broadcast();
  final StreamController<Json> _callDeclined = StreamController.broadcast();

  CallSocket({required this.serverUrl, this.token});

  Stream<Json> get onIncomingCall => _incomingCall.stream;
  Stream<Json> get onCallAnswered => _callAnswered.stream;
  Stream<Json> get onIceCandidate => _iceCandidate.stream;
  Stream<Json> get onCallEnded => _callEnded.stream;
  Stream<Json> get onCallDeclined => _callDeclined.stream;

  void connect({required String userId}) {
    if (_socket != null && _socket!.connected) return;

    _socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'auth': {'token': token},
      'query': {'token': token},
    });

    _socket!.on('connect', (_) {
      print('✅ CallSocket connected: ${_socket!.id}');
      // Ensure we join the user's personal room for signaling
      _socket!.emit('user:connect', {'userId': userId});
    });

    _socket!.on('connect_error', (err) => print('❌ CallSocket connect_error: $err'));
    _socket!.on('disconnect', (_) => print('❌ CallSocket disconnected'));

    _socket!.on('incoming-call', (data) => _safeAdd(_incomingCall, data));
    _socket!.on('call-answered', (data) => _safeAdd(_callAnswered, data));
    _socket!.on('ice-candidate', (data) => _safeAdd(_iceCandidate, data));
    _socket!.on('call-ended', (data) => _safeAdd(_callEnded, data));
    _socket!.on('call-declined', (data) => _safeAdd(_callDeclined, data));

    _socket!.connect();
  }

  void _safeAdd(StreamController<Json> controller, dynamic data) {
    try {
      if (!controller.isClosed) {
        controller.add(Map<String, dynamic>.from(data ?? {}));
      }
    } catch (e) {
      print('Socket parse error: $e');
    }
  }

  // Don't dispose the socket if ChatPage is keeping it alive.
  // Use this when logging out.
  void dispose() {
    _socket?.disconnect();
    _socket = null;
    _incomingCall.close();
    _callAnswered.close();
    _iceCandidate.close();
    _callEnded.close();
    _callDeclined.close();
  }

  // Emitters
  void emitCallInitiate({required String to, required String conversationId, String? callType, String? fromName}) {
    _socket?.emit('call-initiate', {'to': to, 'conversationId': conversationId, 'callType': callType ?? 'voice', 'fromName': fromName});
  }

  void emitCallUser({required String to, required String conversationId, required String offer, String? callId}) {
    _socket?.emit('call-user', {'to': to, 'conversationId': conversationId, 'offer': offer, 'callId': callId});
  }

  void emitAnswerCall({required String to, required String conversationId, required String answer}) {
    _socket?.emit('answer-call', {'to': to, 'conversationId': conversationId, 'answer': answer});
  }

  void emitIceCandidate({required String to, required String conversationId, required Map<String, dynamic> candidate}) {
    _socket?.emit('ice-candidate', {'to': to, 'conversationId': conversationId, 'candidate': candidate});
  }

  void emitEndCall({required String to, required String conversationId, String? reason}) {
    _socket?.emit('end-call', {'to': to, 'conversationId': conversationId, 'reason': reason});
  }

  void emitDecline({required String to, required String conversationId, String? reason}) {
    _socket?.emit('call-decline', {'to': to, 'conversationId': conversationId, 'reason': reason});
  }
}