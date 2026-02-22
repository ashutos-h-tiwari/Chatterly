import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'socket_service.dart';

class WebRTCService {
  // ─── Singleton ───────────────────────────────────────────────────────────
  static final WebRTCService _instance = WebRTCService._internal();
  factory WebRTCService() => _instance;
  WebRTCService._internal();

  // ─── WebRTC objects ──────────────────────────────────────────────────────
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  // ─── ICE Servers (matches your backend) ──────────────────────────────────
  final Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  // ─── Callbacks (set these from CallProvider) ─────────────────────────────
  Function(RTCIceCandidate)? onIceCandidate;
  Function(MediaStream)? onRemoteStream;
  Function()? onCallEnded;

  // ─── Get local audio stream ───────────────────────────────────────────────
  Future<MediaStream> getLocalStream() async {
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false, // audio only for now
    });
    _localStream = stream;
    return stream;
  }

  // ─── Create Peer Connection ───────────────────────────────────────────────
  Future<void> createPeerConnection() async {
    _peerConnection = await createPeerConnectionWithConfig(_iceConfig);

    // When we get an ICE candidate, send it to the other peer via socket
    _peerConnection!.onIceCandidate = (candidate) {
      if (onIceCandidate != null) {
        onIceCandidate!(candidate);
      }
    };

    // When remote stream arrives, notify the UI
    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty && onRemoteStream != null) {
        onRemoteStream!(event.streams[0]);
      }
    };

    // Connection state changes
    _peerConnection!.onConnectionState = (state) {
      print('🔗 Connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        if (onCallEnded != null) onCallEnded!();
      }
    };
  }

  // ─── Add local stream tracks to peer connection ───────────────────────────
  Future<void> addLocalStream() async {
    if (_localStream == null || _peerConnection == null) return;
    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }
  }

  // ─── CALLER: Create SDP Offer ─────────────────────────────────────────────
  Future<RTCSessionDescription> createOffer() async {
    final offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': false,
    });
    await _peerConnection!.setLocalDescription(offer);
    return offer;
  }

  // ─── CALLEE: Set remote offer + Create Answer ─────────────────────────────
  Future<RTCSessionDescription> createAnswer(Map<String, dynamic> offerMap) async {
    final offer = RTCSessionDescription(offerMap['sdp'], offerMap['type']);
    await _peerConnection!.setRemoteDescription(offer);

    final answer = await _peerConnection!.createAnswer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': false,
    });
    await _peerConnection!.setLocalDescription(answer);
    return answer;
  }

  // ─── CALLER: Set remote answer ────────────────────────────────────────────
  Future<void> setRemoteAnswer(Map<String, dynamic> answerMap) async {
    final answer = RTCSessionDescription(answerMap['sdp'], answerMap['type']);
    await _peerConnection!.setRemoteDescription(answer);
  }

  // ─── Add ICE candidate from remote peer ──────────────────────────────────
  Future<void> addIceCandidate(Map<String, dynamic> candidateMap) async {
    try {
      if (candidateMap['candidate'] == null) return;
      final candidate = RTCIceCandidate(
        candidateMap['candidate'],
        candidateMap['sdpMid'],
        candidateMap['sdpMLineIndex'],
      );
      await _peerConnection?.addCandidate(candidate);
    } catch (e) {
      print('⚠️ addIceCandidate error: $e');
    }
  }

  // ─── Mute / Unmute microphone ─────────────────────────────────────────────
  void toggleMute(bool isMuted) {
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = !isMuted;
    });
  }

  // ─── Speaker / Earpiece toggle ────────────────────────────────────────────
  void toggleSpeaker(bool speakerOn) {
    Helper.setSpeakerphoneOn(speakerOn);
  }

  // ─── Cleanup everything ───────────────────────────────────────────────────
  Future<void> dispose() async {
    onIceCandidate = null;
    onRemoteStream = null;
    onCallEnded = null;

    _localStream?.getTracks().forEach((track) => track.stop());
    await _localStream?.dispose();
    _localStream = null;

    await _peerConnection?.close();
    _peerConnection = null;

    print('🧹 WebRTC disposed');
  }
}

// ─── Helper to create peer connection with config ────────────────────────────
Future<RTCPeerConnection> createPeerConnectionWithConfig(
    Map<String, dynamic> config) async {
  return await createPeerConnection(config);
}
