// call_controller.dart
import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:uuid/uuid.dart';

import 'rtc_helper.dart';
import 'call_socket.dart';

class CallController {
  final String localUserId;
  final String remoteUserId;
  final String conversationId;
  final CallSocket socket;

  rtc.RTCPeerConnection? _pc;
  rtc.MediaStream? localStream;
  final rtc.RTCVideoRenderer localRenderer = rtc.RTCVideoRenderer();
  final rtc.RTCVideoRenderer remoteRenderer = rtc.RTCVideoRenderer();
  String? callId;
  bool isCaller = false;

  // Buffer for remote candidates that arrive before pc / remoteDescription is ready.
  final List<Map<String, dynamic>> _pendingCandidates = [];

  // For protecting candidate processing
  bool _remoteDescriptionSet = false;

  CallController({
    required this.localUserId,
    required this.remoteUserId,
    required this.conversationId,
    required this.socket,
  });

  Future<void> init() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    // socket.onIncomingCall.listen(_onIncomingCall);

    socket.onCallAnswered.listen(_onCallAnswered);
    socket.onIceCandidate.listen(_onIceCandidate);
    socket.onCallEnded.listen((_) => _onCallEnded());
    socket.onCallDeclined.listen((_) => _onCallDeclined());
  }

  Future<void> dispose() async {
    try {
      await localRenderer.dispose();
      await remoteRenderer.dispose();
    } catch (_) {}
    try {
      localStream?.getTracks().forEach((t) => t.stop());
    } catch (_) {}
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    localStream = null;
    _pendingCandidates.clear();
    _remoteDescriptionSet = false;
  }

  Future<void> _createPeerConnection() async {
    if (_pc != null) return;
    print('PC[$conversationId] creating peer connection...');
    // _pc = await rtc.createPeerConnection(defaultIceServers); backup
    _pc = await rtc.createPeerConnection(
      {
        ...defaultIceServers,
        'sdpSemantics': 'unified-plan',
      },
      {
        'mandatory': {},
        'optional': [
          {'DtlsSrtpKeyAgreement': true},
        ],
      },
    );


    // connection / signaling / ice state logs
    _pc!.onConnectionState = (state) {
      print('PC[$conversationId] connectionState -> $state');
    };
    _pc!.onSignalingState = (state) {
      print('PC[$conversationId] signalingState -> $state');
    };
    _pc!.onIceConnectionState = (state) {
      print('PC[$conversationId] iceConnectionState -> $state');
    };

    // ICE candidate handler - send to signaling server
    _pc!.onIceCandidate = (rtc.RTCIceCandidate? candidate) {
      if (candidate != null && candidate.candidate != null) {
        print('PC[$conversationId] local onIceCandidate -> ${candidate.candidate}');
        socket.emitIceCandidate(
          to: remoteUserId,
          conversationId: conversationId,
          candidate: {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        );
      }
    };

    _pc!.onTrack = (rtc.RTCTrackEvent event) async {
      print('🔵 onTrack fired, track kind: ${event.track?.kind}, streams: ${event.streams.length}');
      // ✅ STEP 5: FORCE ENABLE REMOTE TRACK (VERY IMPORTANT)
      event.track?.enabled = true;
      if (event.streams.isNotEmpty) {
        print('🔵 using event.streams[0] as remote stream');
        remoteRenderer.srcObject = event.streams[0];
      } else if (event.track != null) {
        print('🔵 creating new remote stream and adding track');
        final ms = await rtc.createLocalMediaStream(
          'remote-${DateTime.now().millisecondsSinceEpoch}',
        );
        ms.addTrack(event.track!);
        remoteRenderer.srcObject = ms;
      } else {
        print('⚠️ onTrack without track/streams');
      }
    };


    // Optional: onAddStream fallback for older APIs / compatibility
    _pc!.onAddStream = (rtc.MediaStream stream) {
      print('PC[$conversationId] onAddStream -> ${stream.id} tracks:${stream.getTracks().length}');
      remoteRenderer.srcObject = stream;
    };

    // After creating pc, if there are pending candidates, try to add them
    if (_pendingCandidates.isNotEmpty) {
      print('PC[$conversationId] adding buffered ${_pendingCandidates.length} candidate(s) after pc creation');
      for (final cand in List<Map<String, dynamic>>.from(_pendingCandidates)) {
        try {
          final rtcCand = rtc.RTCIceCandidate(
            cand['candidate'],
            cand['sdpMid'],
            cand['sdpMLineIndex'],
          );
          _pc?.addCandidate(rtcCand);
          print('PC[$conversationId] added buffered candidate: ${cand['candidate']}');
        } catch (e) {
          print('PC[$conversationId] failed to add buffered candidate: $e');
        }
      }
      _pendingCandidates.clear();
    }
  }

  Future<void> startLocalStream({bool video = false}) async {
    try {
      final Map<String, dynamic> constraints = {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': video
            ? {
          'facingMode': 'user',
          'width': {'ideal': 640},
          'height': {'ideal': 480},
          'frameRate': {'ideal': 24},
        }: false,
      };

      localStream = await rtc.navigator.mediaDevices.getUserMedia(constraints);

      localRenderer.srcObject = localStream;
      print(
        'PC[$conversationId] acquired localStream: '
            'audio:${localStream?.getAudioTracks().length} '
            'video:${localStream?.getVideoTracks().length}',
      );
    } catch (e) {
      print('PC[$conversationId] getUserMedia ERROR: $e');
      rethrow;
    }
  }

  /// Caller initiates call: creates offer and emits call-user
  Future<void> startCall({bool video = true}) async {
    isCaller = true;
    callId = const Uuid().v4();
    print('PC[$conversationId] startCall - isCaller=true callId=$callId video=$video');

    await _createPeerConnection();
    await startLocalStream(video: video);

    // add local tracks
    localStream?.getTracks().forEach((track) {
      _pc?.addTrack(track, localStream!);
      print('PC[$conversationId] added local track kind=${track.kind}');
    });

    // create offer
    // In startCall(), before creating offer:
    socket.emitCallInitiate(
      to: remoteUserId,
      conversationId: conversationId,
      callType: video ? 'video' : 'voice',
    );
// Then create and send the offer...
    final offer = await _pc!.createOffer();
    print('PC[$conversationId] created offer sdp length=${offer.sdp?.length ?? 0}');
    await _pc!.setLocalDescription(offer);
    print('PC[$conversationId] setLocalDescription(offer)');

    // emit offer via signaling server
    socket.emitCallUser(
      to: remoteUserId,
      conversationId: conversationId,
      offer: offer.sdp ?? offer.toMap().toString(),
      callId: callId,
    );

    print('PC[$conversationId] emitted call-user (offer) to $remoteUserId');
  }

  /// Handle an incoming offer (callee answering)
  Future<void> answerIncomingOffer({
    required String offerSdp,
    bool video = true,
  }) async {
    print('PC[$conversationId] answerIncomingOffer called, offerSdp length=${offerSdp.length}, video=$video');
    await _createPeerConnection();
    await startLocalStream(video: video);

    // add local tracks
    localStream?.getTracks().forEach((track) {
      _pc?.addTrack(track, localStream!);
      print('PC[$conversationId] added local track(kind=${track.kind}) for answer');
    });

    // set remote (offer)
    try {
      await _pc!.setRemoteDescription(
        rtc.RTCSessionDescription(offerSdp, 'offer'),
      );
      _remoteDescriptionSet = true;
      print('PC[$conversationId] setRemoteDescription(offer)');
    } catch (e) {
      print('PC[$conversationId] setRemoteDescription ERROR: $e');
      rethrow;
    }

    // add any buffered candidates that arrived before remote desc
    if (_pendingCandidates.isNotEmpty) {
      print('PC[$conversationId] adding buffered ${_pendingCandidates.length} candidate(s) after setRemoteDescription');
      for (final cand in List<Map<String, dynamic>>.from(_pendingCandidates)) {
        try {
          final rtcCand = rtc.RTCIceCandidate(
            cand['candidate'],
            cand['sdpMid'],
            cand['sdpMLineIndex'],
          );
          await _pc?.addCandidate(rtcCand);
          print('PC[$conversationId] added buffered candidate after remoteDesc: ${cand['candidate']}');
        } catch (e) {
          print('PC[$conversationId] failed to add buffered candidate after remoteDesc: $e');
        }
      }
      _pendingCandidates.clear();
    }

    // create answer
    final answer = await _pc!.createAnswer();
    print('PC[$conversationId] created answer sdp length=${answer.sdp?.length ?? 0}');
    await _pc!.setLocalDescription(answer);
    print('PC[$conversationId] setLocalDescription(answer)');

    socket.emitAnswerCall(
      to: remoteUserId,
      conversationId: conversationId,
      answer: answer.sdp ?? answer.toMap().toString(),
    );

    print('PC[$conversationId] emitted answer-call (answer) to $remoteUserId');
  }

  Future<void> _onCallAnswered(dynamic data) async {
    try {
      final Map<String, dynamic> payload = Map<String, dynamic>.from(data ?? {});
      if (!isCaller) return;
      if ((payload['conversationId'] ?? '').toString() != conversationId) return;

      final answerSdp = payload['answer'] as String?;
      if (answerSdp != null && _pc != null) {
        print('PC[$conversationId] received answer sdp length=${answerSdp.length}');
        await _pc!.setRemoteDescription(
          rtc.RTCSessionDescription(answerSdp, 'answer'),
        );
        _remoteDescriptionSet = true;
        print('PC[$conversationId] setRemoteDescription(answer)');

        // Process any pending candidates after remote description
        if (_pendingCandidates.isNotEmpty) {
          print('PC[$conversationId] adding buffered ${_pendingCandidates.length} candidate(s) after answer');
          for (final cand in List<Map<String, dynamic>>.from(_pendingCandidates)) {
            try {
              final rtcCand = rtc.RTCIceCandidate(
                cand['candidate'],
                cand['sdpMid'],
                cand['sdpMLineIndex'],
              );
              await _pc?.addCandidate(rtcCand);
              print('PC[$conversationId] added buffered candidate after answer: ${cand['candidate']}');
            } catch (e) {
              print('PC[$conversationId] failed to add buffered candidate after answer: $e');
            }
          }
          _pendingCandidates.clear();
        }
      }
    } catch (e) {
      print('PC[$conversationId] _onCallAnswered ERROR: $e');
    }
  }

  Future<void> _onIceCandidate(dynamic data) async {
    try {
      final Map<String, dynamic> payload = Map<String, dynamic>.from(data ?? {});
      if ((payload['conversationId'] ?? '').toString() != conversationId) {
        // not for this conversation
        return;
      }
      final candidate = payload['candidate'];
      if (candidate == null) return;

      final candMap = {
        'candidate': candidate['candidate'],
        'sdpMid': candidate['sdpMid'],
        'sdpMLineIndex': candidate['sdpMLineIndex'],
      };

      // If pc not created yet or remote description not set, buffer the candidate
      if (_pc == null || !_remoteDescriptionSet) {
        _pendingCandidates.add(candMap);
        print('PC[$conversationId] buffered candidate (count=${_pendingCandidates.length}) -> ${candMap['candidate']}');
        return;
      }

      final c = rtc.RTCIceCandidate(
        candMap['candidate'],
        candMap['sdpMid'],
        candMap['sdpMLineIndex'],
      );
      try {
        await _pc?.addCandidate(c);
        print('PC[$conversationId] addCandidate success: ${c.candidate}');
      } catch (e) {
        print('PC[$conversationId] addCandidate error: $e');
      }
    } catch (e) {
      print('PC[$conversationId] _onIceCandidate ERROR: $e');
    }
  }

  Future<void> endCall({String? reason}) async {
    try {
      socket.emitEndCall(
        to: remoteUserId,
        conversationId: conversationId,
        reason: reason,
      );
    } catch (e) {
      print('PC[$conversationId] emitEndCall ERROR: $e');
    }

    try {
      await _pc?.close();
    } catch (e) {
      print('PC[$conversationId] close ERROR: $e');
    }
    _pc = null;

    try {
      localStream?.getTracks().forEach((t) => t.stop());
      localStream = null;
    } catch (e) {
      print('PC[$conversationId] stop tracks ERROR: $e');
    }

    _pendingCandidates.clear();
    _remoteDescriptionSet = false;
    print('PC[$conversationId] call ended locally');
  }

  void _onCallEnded() {
    print('PC[$conversationId] Call ended by remote');
    // Clean local resources
    try {
      _pc?.close();
    } catch (_) {}
    _pc = null;
    try {
      localStream?.getTracks().forEach((t) => t.stop());
    } catch (_) {}
    localStream = null;
    _pendingCandidates.clear();
    _remoteDescriptionSet = false;
  }

  void _onCallDeclined() {
    print('PC[$conversationId] Call declined by remote');
  }

  void toggleMute() {
    final audioTracks = localStream?.getAudioTracks() ?? [];
    for (var t in audioTracks) {
      t.enabled = !t.enabled;
    }
    print('PC[$conversationId] toggleMute -> ${audioTracks.map((t) => t.enabled)}');
  }

  Future<void> switchCamera() async {
    final videoTrack = (localStream?.getVideoTracks().isNotEmpty == true)
        ? localStream!.getVideoTracks()[0]
        : null;
    if (videoTrack != null) {
      try {
        await rtc.Helper.switchCamera(videoTrack);
        print('PC[$conversationId] switchCamera success');
      } catch (e) {
        print('PC[$conversationId] switchCamera ERROR: $e');
      }
    } else {
      print('PC[$conversationId] switchCamera: no video track available');
    }
  }
}
