import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;

/// CallSocket — dedicated socket for WebRTC call signalling.
/// ChatPage creates one instance and passes it to CallScreen.
class CallSocket {
  final String serverUrl;
  final String token;

  IO.Socket? _socket;

  // ─── Stream controllers (ChatPage listens to these) ──────────────────────
  final _incomingCallCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _callAnsweredCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _callDeclinedCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _callEndedCtrl    = StreamController<Map<String, dynamic>>.broadcast();
  final _iceCandidateCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _callErrorCtrl    = StreamController<Map<String, dynamic>>.broadcast();
  final _callBusyCtrl     = StreamController<Map<String, dynamic>>.broadcast();
  final _calleeOfflineCtrl= StreamController<Map<String, dynamic>>.broadcast();

  // ─── Public streams (ChatPage & CallScreen use these) ────────────────────
  Stream<Map<String, dynamic>> get onIncomingCall  => _incomingCallCtrl.stream;
  Stream<Map<String, dynamic>> get onCallAnswered  => _callAnsweredCtrl.stream;
  Stream<Map<String, dynamic>> get onCallDeclined  => _callDeclinedCtrl.stream;
  Stream<Map<String, dynamic>> get onCallEnded     => _callEndedCtrl.stream;
  Stream<Map<String, dynamic>> get onIceCandidate  => _iceCandidateCtrl.stream;
  Stream<Map<String, dynamic>> get onCallError     => _callErrorCtrl.stream;
  Stream<Map<String, dynamic>> get onCallBusy      => _callBusyCtrl.stream;
  Stream<Map<String, dynamic>> get onCalleeOffline => _calleeOfflineCtrl.stream;

  CallSocket({required this.serverUrl, required this.token});

  // ─── Connect & join personal room ────────────────────────────────────────
  void connect({required String? userId}) {
    if (_socket != null && _socket!.connected) {
      print('✅ CallSocket already connected');
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
      print('✅ CallSocket connected: ${_socket!.id}');
      // Join personal room so backend can route calls to this user
      if (userId != null) {
        _socket!.emit('user:connect', {'userId': userId});
      }
    });

    _socket!.onDisconnect((_) => print('❌ CallSocket disconnected'));
    _socket!.onConnectError((e) => print('⚠️ CallSocket error: $e'));

    _registerListeners();
  }

  // ─── Register all incoming socket events ─────────────────────────────────
  void _registerListeners() {
    _socket!.on('incoming-call', (data) {
      print('📲 incoming-call: $data');
      _incomingCallCtrl.add(_toMap(data));
    });

    _socket!.on('call-answered', (data) {
      print('✅ call-answered: $data');
      _callAnsweredCtrl.add(_toMap(data));
    });

    _socket!.on('call-declined', (data) {
      print('📵 call-declined: $data');
      _callDeclinedCtrl.add(_toMap(data));
    });

    _socket!.on('call-ended', (data) {
      print('📴 call-ended: $data');
      _callEndedCtrl.add(_toMap(data));
    });

    _socket!.on('ice-candidate', (data) {
      print('🧊 ice-candidate received');
      _iceCandidateCtrl.add(_toMap(data));
    });

    _socket!.on('call:error', (data) {
      print('❌ call:error: $data');
      _callErrorCtrl.add(_toMap(data));
    });

    _socket!.on('call:busy', (data) {
      print('📵 call:busy: $data');
      _callBusyCtrl.add(_toMap(data));
    });

    _socket!.on('callee-offline', (data) {
      print('📴 callee-offline: $data');
      _calleeOfflineCtrl.add(_toMap(data));
    });
  }

  // ─── EMIT: call-initiate (ringing — no offer yet) ────────────────────────
  void emitCallInitiate({
    required String to,
    required String conversationId,
    String callType = 'voice',
  }) {
    _socket?.emit('call-initiate', {
      'to': to,
      'conversationId': conversationId,
      'callType': callType,
    });
    print('📞 Emitted call-initiate to $to');
  }

  // ─── EMIT: call-user (with WebRTC offer) ─────────────────────────────────
  void emitCallUser({
    required String to,
    required String conversationId,
    required Map<String, dynamic> offer,
  }) {
    _socket?.emit('call-user', {
      'to': to,
      'conversationId': conversationId,
      'offer': offer,
    });
    print('📡 Emitted call-user (offer) to $to');
  }

  // ─── EMIT: answer-call (with WebRTC answer) ───────────────────────────────
  void emitAnswer({
    required String to,
    required String conversationId,
    required Map<String, dynamic> answer,
  }) {
    _socket?.emit('answer-call', {
      'to': to,
      'conversationId': conversationId,
      'answer': answer,
    });
    print('✅ Emitted answer-call to $to');
  }

  // ─── EMIT: ice-candidate ──────────────────────────────────────────────────
  void emitIceCandidate({
    required String to,
    required String conversationId,
    required Map<String, dynamic> candidate,
  }) {
    _socket?.emit('ice-candidate', {
      'to': to,
      'conversationId': conversationId,
      'candidate': candidate,
    });
  }

  // ─── EMIT: end-call ───────────────────────────────────────────────────────
  void emitEndCall({
    required String to,
    required String conversationId,
  }) {
    _socket?.emit('end-call', {
      'to': to,
      'conversationId': conversationId,
    });
    print('📴 Emitted end-call to $to');
  }

  // ─── EMIT: decline call ───────────────────────────────────────────────────
  void emitDecline({
    required String to,
    required String conversationId,
    String reason = 'declined',
  }) {
    _socket?.emit('call-decline', {
      'to': to,
      'conversationId': conversationId,
      'reason': reason,
    });
    print('📵 Emitted call-decline to $to');
  }

  // ─── Helper: convert dynamic socket data to Map ──────────────────────────
  Map<String, dynamic> _toMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  // ─── Cleanup ──────────────────────────────────────────────────────────────
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;

    _incomingCallCtrl.close();
    _callAnsweredCtrl.close();
    _callDeclinedCtrl.close();
    _callEndedCtrl.close();
    _iceCandidateCtrl.close();
    _callErrorCtrl.close();
    _callBusyCtrl.close();
    _calleeOfflineCtrl.close();

    print('🧹 CallSocket disposed');
  }
}
