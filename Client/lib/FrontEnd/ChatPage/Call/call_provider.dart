import 'package:flutter/material.dart';
import '../services/socket_service.dart';
import '../services/webrtc_service.dart';

// ─── Call State Enum ─────────────────────────────────────────────────────────
enum CallState {
  idle,        // No call
  ringing,     // Incoming call — show accept/decline
  calling,     // Outgoing call — waiting for answer
  connected,   // Call in progress
  ended,       // Call ended
}

// ─── Call Provider ───────────────────────────────────────────────────────────
class CallProvider extends ChangeNotifier {
  final SocketService _socket = SocketService();
  final WebRTCService _webrtc = WebRTCService();

  // ─── State ────────────────────────────────────────────────────────────────
  CallState _callState = CallState.idle;
  CallState get callState => _callState;

  String? _remoteUserId;     // The other person's userId
  String? _remoteUserName;   // The other person's name
  String? _conversationId;   // Current conversation
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;
  String? get remoteUserId => _remoteUserId;
  String? get remoteUserName => _remoteUserName;
  String? get conversationId => _conversationId;

  // Pending offer from incoming call (before user accepts)
  Map<String, dynamic>? _pendingOffer;

  // ─── Initialize: listen to all call socket events ─────────────────────────
  void initialize() {
    _listenForIncomingCall();
    _listenForCallAnswered();
    _listenForIceCandidate();
    _listenForCallEnded();
    _listenForCallDeclined();
    _listenForCalleeBusy();
    _listenForCalleeOffline();
    _listenForCallError();

    // WebRTC callbacks
    _webrtc.onIceCandidate = (candidate) {
      if (_remoteUserId == null || _conversationId == null) return;
      _socket.emit('ice-candidate', {
        'to': _remoteUserId,
        'conversationId': _conversationId,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    _webrtc.onCallEnded = () {
      _endCallCleanup();
    };

    print('✅ CallProvider initialized');
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  OUTGOING CALL — Caller side
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> startCall({
    required String toUserId,
    required String toUserName,
    required String conversationId,
  }) async {
    try {
      _remoteUserId = toUserId;
      _remoteUserName = toUserName;
      _conversationId = conversationId;

      // Step 1: Notify callee (ringing) — no offer yet
      _socket.emit('call-initiate', {
        'to': toUserId,
        'conversationId': conversationId,
        'callType': 'voice',
      });

      _updateState(CallState.calling);

      // Step 2: Setup WebRTC
      await _webrtc.getLocalStream();
      await _webrtc.createPeerConnection();
      await _webrtc.addLocalStream();

      // Step 3: Create offer
      final offer = await _webrtc.createOffer();

      // Step 4: Send offer to callee
      _socket.emit('call-user', {
        'to': toUserId,
        'conversationId': conversationId,
        'offer': {
          'sdp': offer.sdp,
          'type': offer.type,
        },
      });

      print('📞 Call started to $toUserName ($toUserId)');
    } catch (e) {
      print('❌ startCall error: $e');
      _endCallCleanup();
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  INCOMING CALL — Callee side
  // ══════════════════════════════════════════════════════════════════════════

  void _listenForIncomingCall() {
    _socket.on('incoming-call', (data) async {
      try {
        print('📲 Incoming call from ${data['from']}');

        _remoteUserId = data['from']?.toString();
        _remoteUserName = data['fromName']?.toString() ?? 'Unknown';
        _conversationId = data['conversationId']?.toString();
        _pendingOffer = data['offer'] != null
            ? Map<String, dynamic>.from(data['offer'])
            : null;

        _updateState(CallState.ringing);
      } catch (e) {
        print('❌ incoming-call error: $e');
      }
    });
  }

  // User taps ACCEPT
  Future<void> acceptCall() async {
    try {
      await _webrtc.getLocalStream();
      await _webrtc.createPeerConnection();
      await _webrtc.addLocalStream();

      RTCSessionDescriptionWrapper? answer;

      if (_pendingOffer != null) {
        // Offer already received — create answer immediately
        final ans = await _webrtc.createAnswer(_pendingOffer!);
        answer = RTCSessionDescriptionWrapper(sdp: ans.sdp!, type: ans.type!);
      } else {
        // Wait for offer to arrive (call-user event might come after incoming-call)
        answer = await _waitForOfferAndAnswer();
      }

      if (answer == null) {
        print('❌ No offer received — cannot answer');
        return;
      }

      _socket.emit('answer-call', {
        'to': _remoteUserId,
        'conversationId': _conversationId,
        'answer': {
          'sdp': answer.sdp,
          'type': answer.type,
        },
      });

      _updateState(CallState.connected);
      print('✅ Call accepted');
    } catch (e) {
      print('❌ acceptCall error: $e');
      _endCallCleanup();
    }
  }

  // Wait for offer if it hasn't arrived yet (max 10 seconds)
  Future<RTCSessionDescriptionWrapper?> _waitForOfferAndAnswer() async {
    for (int i = 0; i < 20; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (_pendingOffer != null) {
        final ans = await _webrtc.createAnswer(_pendingOffer!);
        return RTCSessionDescriptionWrapper(sdp: ans.sdp!, type: ans.type!);
      }
    }
    return null;
  }

  // User taps DECLINE
  void declineCall() {
    _socket.emit('call-decline', {
      'to': _remoteUserId,
      'conversationId': _conversationId,
      'reason': 'declined',
    });
    _endCallCleanup();
    print('📵 Call declined');
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  SOCKET LISTENERS
  // ══════════════════════════════════════════════════════════════════════════

  // Caller receives answer from callee
  void _listenForCallAnswered() {
    _socket.on('call-answered', (data) async {
      try {
        print('✅ Call answered by ${data['from']}');
        final answerMap = Map<String, dynamic>.from(data['answer']);
        await _webrtc.setRemoteAnswer(answerMap);
        _updateState(CallState.connected);
      } catch (e) {
        print('❌ call-answered error: $e');
      }
    });
  }

  // ICE candidates from remote peer
  void _listenForIceCandidate() {
    _socket.on('ice-candidate', (data) async {
      try {
        if (data['candidate'] != null) {
          final candidateMap = Map<String, dynamic>.from(data['candidate']);
          await _webrtc.addIceCandidate(candidateMap);
        }
      } catch (e) {
        print('❌ ice-candidate error: $e');
      }
    });
  }

  // Other side ended the call
  void _listenForCallEnded() {
    _socket.on('call-ended', (data) {
      print('📴 Call ended by ${data['from']} — reason: ${data['reason']}');
      _endCallCleanup();
    });
  }

  // Other side declined
  void _listenForCallDeclined() {
    _socket.on('call-declined', (data) {
      print('📵 Call declined by ${data['from']}');
      _endCallCleanup();
    });
  }

  // Callee is busy
  void _listenForCalleeBusy() {
    _socket.on('call:busy', (data) {
      print('📵 Callee is busy');
      _endCallCleanup();
    });
  }

  // Callee is offline
  void _listenForCalleeOffline() {
    _socket.on('callee-offline', (data) {
      print('📴 Callee is offline');
      _endCallCleanup();
    });
  }

  // Error
  void _listenForCallError() {
    _socket.on('call:error', (data) {
      print('❌ Call error: ${data['message']}');
      _endCallCleanup();
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  CONTROLS (during active call)
  // ══════════════════════════════════════════════════════════════════════════

  void toggleMute() {
    _isMuted = !_isMuted;
    _webrtc.toggleMute(_isMuted);
    notifyListeners();
  }

  void toggleSpeaker() {
    _isSpeakerOn = !_isSpeakerOn;
    _webrtc.toggleSpeaker(_isSpeakerOn);
    notifyListeners();
  }

  // End call (local user hangs up)
  void endCall() {
    _socket.emit('end-call', {
      'to': _remoteUserId,
      'conversationId': _conversationId,
    });
    _endCallCleanup();
    print('📴 Call ended by local user');
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  CLEANUP
  // ══════════════════════════════════════════════════════════════════════════

  void _endCallCleanup() async {
    await _webrtc.dispose();
    _remoteUserId = null;
    _remoteUserName = null;
    _conversationId = null;
    _pendingOffer = null;
    _isMuted = false;
    _isSpeakerOn = false;
    _updateState(CallState.ended);

    // Reset to idle after short delay
    await Future.delayed(const Duration(seconds: 1));
    _updateState(CallState.idle);
  }

  void _updateState(CallState state) {
    _callState = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _socket.off('incoming-call');
    _socket.off('call-answered');
    _socket.off('ice-candidate');
    _socket.off('call-ended');
    _socket.off('call-declined');
    _socket.off('call:busy');
    _socket.off('callee-offline');
    _socket.off('call:error');
    _webrtc.dispose();
    super.dispose();
  }
}

// ─── Small helper wrapper ────────────────────────────────────────────────────
class RTCSessionDescriptionWrapper {
  final String sdp;
  final String type;
  RTCSessionDescriptionWrapper({required this.sdp, required this.type});
}
