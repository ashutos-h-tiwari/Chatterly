import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'call_socket.dart';

class CallScreen extends StatefulWidget {
  final String localUserId;
  final String remoteUserId;
  final String conversationId;
  final CallSocket socket;
  final bool isCaller;
  final bool video;
  final dynamic initialOffer;

  const CallScreen({
    super.key,
    required this.localUserId,
    required this.remoteUserId,
    required this.conversationId,
    required this.socket,
    required this.isCaller,
    required this.video,
    this.initialOffer,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  final RTCVideoRenderer _localRenderer  = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  // final Map<String, dynamic> _iceConfig = {
  //   'iceServers': [
  //     {'urls': 'stun:stun.l.google.com:19302'},
  //     {'urls': 'stun:stun1.l.google.com:19302'},
  //   ],
  //   'sdpSemantics': 'unified-plan',
  // };
  final Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {
        'urls': [
          'turn:openrelay.metered.ca:80',
          'turn:openrelay.metered.ca:443',
          'turn:openrelay.metered.ca:443?transport=tcp',
        ],
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
    'sdpSemantics': 'unified-plan',
  };

  bool _isMuted      = false;
  bool _isSpeakerOn  = false;
  bool _isConnected  = false;
  bool _isEnded      = false;
  int  _seconds      = 0;
  Timer? _timer;

  StreamSubscription? _subAnswered;
  StreamSubscription? _subIce;
  StreamSubscription? _subEnded;
  StreamSubscription? _subDeclined;
  StreamSubscription? _subBusy;
  StreamSubscription? _subOffline;
  StreamSubscription? _subError;
  StreamSubscription? _subIncoming;

  final List<RTCIceCandidate> _iceCandidateQueue = [];
  bool _remoteDescSet = false;
  bool _waitingForOffer = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    _listenSocketEvents(); // ✅ Listen FIRST before any async work
    await _createPeerConnection();
    await _getLocalStream();

    if (widget.isCaller) {
      await _startCallAsCaller();
    } else {
      await _startCallAsCallee();
    }
  }

  Future<void> _createPeerConnection() async {
    _pc = await createPeerConnection(_iceConfig);

    // Send ICE candidates to remote
    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      widget.socket.emitIceCandidate(
        to: widget.remoteUserId,
        conversationId: widget.conversationId,
        candidate: {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      );
      print('🧊 Sent ICE candidate to remote');
    };

    // Remote stream arrived
    _pc!.onTrack = (event) {
      print('🎵 Remote track received: ${event.track.kind}');
      if (event.streams.isNotEmpty && mounted) {
        setState(() {
          _remoteRenderer.srcObject = event.streams[0];
          // ✅ Mark connected when remote track arrives (more reliable than connectionState)
          if (!_isConnected) {
            _isConnected = true;
            _startTimer();
          }
        });
      }
    };

    // ✅ Use onIceConnectionState — more reliable than onConnectionState
    _pc!.onIceConnectionState = (state) {
      print('🧊 ICE Connection state: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        if (mounted && !_isConnected) {
          setState(() => _isConnected = true);
          _startTimer();
        }
      }
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        if (!_waitingForOffer) {
          _endCall(reason: 'ice-failed');
        }
      }
    };

    // Backup: also watch connectionState
    _pc!.onConnectionState = (state) {
      print('🔗 Connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        if (mounted && !_isConnected) {
          setState(() => _isConnected = true);
          _startTimer();
        }
      }
    };
  }

  Future<void> _getLocalStream() async {
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': widget.video ? {'facingMode': 'user'} : false,
      });

      print('🎤 Local stream obtained — tracks: ${_localStream!.getTracks().length}');

      if (widget.video) _localRenderer.srcObject = _localStream;

      // Add all tracks to peer connection
      for (final track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
        print('➕ Added track: ${track.kind}');
      }
    } catch (e) {
      print('❌ getLocalStream error: $e');
      _showSnack('Could not access microphone/camera: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CALLER SIDE
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _startCallAsCaller() async {
    try {
      final offer = await _pc!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': widget.video,
      });
      await _pc!.setLocalDescription(offer);
      print('📋 Local description (offer) set');

      widget.socket.emitCallUser(
        to: widget.remoteUserId,
        conversationId: widget.conversationId,
        offer: {'sdp': offer.sdp, 'type': offer.type},
      );
      print('📡 Offer sent to ${widget.remoteUserId}');
    } catch (e) {
      print('❌ _startCallAsCaller error: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CALLEE SIDE
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _startCallAsCallee() async {
    final offer = widget.initialOffer;
    final hasRealOffer = offer != null &&
        offer['sdp'] != null &&
        offer['sdp'].toString().trim().isNotEmpty &&
        offer['sdp'].toString().contains('v=0');

    if (hasRealOffer) {
      print('📨 Real offer in initialOffer — handling immediately');
      await _handleOffer(offer);
    } else {
      print('⏳ notifyOnly — waiting for real offer via call-user event');
      _waitingForOffer = true;
      if (mounted) setState(() {});
    }
  }

  Future<void> _handleOffer(dynamic offerData) async {
    try {
      if (_remoteDescSet) {
        print('⚠️ Remote desc already set — skipping duplicate offer');
        return;
      }

      final sdp  = offerData['sdp']?.toString().trim() ?? '';
      final type = offerData['type']?.toString() ?? 'offer';

      if (sdp.isEmpty || !sdp.contains('v=0')) {
        print('⚠️ Invalid SDP — waiting');
        _waitingForOffer = true;
        return;
      }

      print('📨 Setting remote description...');
      await _pc!.setRemoteDescription(RTCSessionDescription(sdp, type));
      _remoteDescSet = true;
      _waitingForOffer = false;

      // Flush queued ICE candidates
      print('🧊 Flushing ${_iceCandidateQueue.length} queued candidates');
      for (final c in _iceCandidateQueue) {
        try {
          await _pc!.addCandidate(c);
        } catch (e) {
          print('⚠️ addCandidate error: $e');
        }
      }
      _iceCandidateQueue.clear();

      // Create answer
      final answer = await _pc!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': widget.video,
      });
      await _pc!.setLocalDescription(answer);
      print('📋 Local description (answer) set');

      widget.socket.emitAnswer(
        to: widget.remoteUserId,
        conversationId: widget.conversationId,
        answer: {'sdp': answer.sdp, 'type': answer.type},
      );
      print('✅ Answer sent to ${widget.remoteUserId}');
    } catch (e) {
      print('❌ _handleOffer error: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SOCKET LISTENERS — registered FIRST before peer connection
  // ══════════════════════════════════════════════════════════════════════════
  void _listenSocketEvents() {

    // ✅ Callee: real offer arrives via call-user (emitted as incoming-call)
    _subIncoming = widget.socket.onIncomingCall.listen((data) async {
      if (widget.isCaller) return; // Caller doesn't need this

      final offer = data['offer'];
      final isNotifyOnly = data['notifyOnly'] == true;

      print('📲 onIncomingCall in CallScreen — notifyOnly: $isNotifyOnly, hasOffer: ${offer != null}');

      if (!isNotifyOnly && offer != null) {
        print('📨 Real offer received via socket — handling');
        await _handleOffer(offer);
      }
    });

    // ✅ Caller: callee's answer arrives
    _subAnswered = widget.socket.onCallAnswered.listen((data) async {
      if (!widget.isCaller) return; // Only caller needs this

      try {
        final answer = data['answer'];
        if (answer == null) {
          print('⚠️ No answer in call-answered event');
          return;
        }

        final sdp  = answer['sdp']?.toString().trim() ?? '';
        final type = answer['type']?.toString() ?? 'answer';

        if (sdp.isEmpty) {
          print('⚠️ Empty SDP in answer');
          return;
        }

        print('✅ Setting remote answer...');
        await _pc!.setRemoteDescription(RTCSessionDescription(sdp, type));
        _remoteDescSet = true;

        // Flush queued ICE candidates
        print('🧊 Flushing ${_iceCandidateQueue.length} queued candidates after answer');
        for (final c in _iceCandidateQueue) {
          try {
            await _pc!.addCandidate(c);
          } catch (e) {
            print('⚠️ addCandidate error: $e');
          }
        }
        _iceCandidateQueue.clear();
        print('✅ Remote answer set — WebRTC negotiation complete');
      } catch (e) {
        print('❌ onCallAnswered error: $e');
      }
    });

    // ICE candidates from remote peer
    _subIce = widget.socket.onIceCandidate.listen((data) async {
      try {
        final c = data['candidate'];
        if (c == null) return;

        final candidateStr = c['candidate']?.toString() ?? '';
        if (candidateStr.isEmpty) return;

        final candidate = RTCIceCandidate(
          candidateStr,
          c['sdpMid']?.toString(),
          c['sdpMLineIndex'] as int? ?? 0,
        );

        if (_remoteDescSet && _pc != null) {
          await _pc!.addCandidate(candidate);
          print('🧊 ICE candidate added');
        } else {
          _iceCandidateQueue.add(candidate);
          print('🧊 ICE candidate queued (${_iceCandidateQueue.length})');
        }
      } catch (e) {
        print('❌ ice-candidate error: $e');
      }
    });

    // Remote ended call
    _subEnded = widget.socket.onCallEnded.listen((data) {
      print('📴 Remote ended call — reason: ${data['reason']}');
      _endCall(reason: 'remote-ended', navigate: true);
    });

    // Call declined
    _subDeclined = widget.socket.onCallDeclined.listen((data) {
      _showSnack('Call declined');
      _endCall(reason: 'declined', navigate: true);
    });

    // Busy
    _subBusy = widget.socket.onCallBusy.listen((data) {
      _showSnack('User is busy');
      _endCall(reason: 'busy', navigate: true);
    });

    // Offline
    _subOffline = widget.socket.onCalleeOffline.listen((data) {
      _showSnack('User is offline');
      _endCall(reason: 'offline', navigate: true);
    });

    // Error
    _subError = widget.socket.onCallError.listen((data) {
      _showSnack('Call error: ${data['message'] ?? 'unknown'}');
      _endCall(reason: 'error', navigate: true);
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CONTROLS
  // ══════════════════════════════════════════════════════════════════════════
  void _toggleMute() {
    _localStream?.getAudioTracks().forEach((t) {
      t.enabled = _isMuted; // toggle: if muted, enable; if enabled, mute
    });
    setState(() => _isMuted = !_isMuted);
    print('🎤 Mute: $_isMuted');
  }

  void _toggleSpeaker() {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    Helper.setSpeakerphoneOn(_isSpeakerOn);
    print('🔊 Speaker: $_isSpeakerOn');
  }

  void _hangUp() {
    widget.socket.emitEndCall(
      to: widget.remoteUserId,
      conversationId: widget.conversationId,
    );
    _endCall(reason: 'local-ended', navigate: true);
  }

  void _endCall({String reason = '', bool navigate = false}) {
    if (_isEnded) return;
    _isEnded = true;
    print('📴 Ending call — reason: $reason');
    _timer?.cancel();
    _cleanup();
    if (navigate && mounted) Navigator.of(context).pop();
  }

  void _startTimer() {
    if (_timer != null) return; // Already started
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
    print('⏱️ Call timer started');
  }

  String _formatDuration(int s) {
    final m   = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  Future<void> _cleanup() async {
    _subAnswered?.cancel();
    _subIce?.cancel();
    _subEnded?.cancel();
    _subDeclined?.cancel();
    _subBusy?.cancel();
    _subOffline?.cancel();
    _subError?.cancel();
    _subIncoming?.cancel();

    _localStream?.getTracks().forEach((t) => t.stop());
    await _localStream?.dispose();
    await _pc?.close();
    _pc = null;

    _localRenderer.dispose();
    _remoteRenderer.dispose();
    print('🧹 CallScreen cleaned up');
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _endCall();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD UI
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: widget.video ? _buildVideoCallUI() : _buildAudioCallUI(),
      ),
    );
  }

  Widget _buildAudioCallUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Top: caller info
        Padding(
          padding: const EdgeInsets.only(top: 60),
          child: Column(
            children: [
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.teal.shade400,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.teal.withOpacity(0.5),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(Icons.person, size: 60, color: Colors.white),
              ),
              const SizedBox(height: 24),
              Text(
                widget.remoteUserId,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              _buildStatusText(),
            ],
          ),
        ),

        // Middle: controls
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _controlBtn(
              icon: _isMuted ? Icons.mic_off : Icons.mic,
              label: _isMuted ? 'Unmute' : 'Mute',
              color: _isMuted ? Colors.red.shade400 : Colors.white24,
              onTap: _toggleMute,
            ),
            _controlBtn(
              icon: _isSpeakerOn ? Icons.volume_up : Icons.hearing,
              label: _isSpeakerOn ? 'Speaker' : 'Earpiece',
              color: _isSpeakerOn ? Colors.blue.shade400 : Colors.white24,
              onTap: _toggleSpeaker,
            ),
          ],
        ),

        // Bottom: end call
        Padding(
          padding: const EdgeInsets.only(bottom: 60),
          child: Column(
            children: [
              GestureDetector(
                onTap: _hangUp,
                child: Container(
                  width: 75,
                  height: 75,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.red,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.5),
                        blurRadius: 20,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.call_end, color: Colors.white, size: 35),
                ),
              ),
              const SizedBox(height: 10),
              const Text('End Call', style: TextStyle(color: Colors.white60)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVideoCallUI() {
    return Stack(
      children: [
        // Remote video fullscreen
        Positioned.fill(
          child: RTCVideoView(
            _remoteRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
        ),
        // Local video pip
        Positioned(
          top: 20,
          right: 16,
          width: 110,
          height: 160,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: RTCVideoView(
              _localRenderer,
              mirror: true,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),
        ),
        // Status
        Positioned(
          top: 20,
          left: 0,
          right: 130,
          child: Center(child: _buildStatusText()),
        ),
        // Controls
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _controlBtn(
                icon: _isMuted ? Icons.mic_off : Icons.mic,
                label: _isMuted ? 'Unmute' : 'Mute',
                color: _isMuted ? Colors.red.shade400 : Colors.white54,
                onTap: _toggleMute,
              ),
              _controlBtn(
                icon: Icons.call_end,
                label: 'End',
                color: Colors.red,
                onTap: _hangUp,
                size: 70,
              ),
              _controlBtn(
                icon: _isSpeakerOn ? Icons.volume_up : Icons.hearing,
                label: _isSpeakerOn ? 'Speaker' : 'Earpiece',
                color: _isSpeakerOn ? Colors.blue.shade400 : Colors.white54,
                onTap: _toggleSpeaker,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusText() {
    if (_isConnected) {
      return Text(
        _formatDuration(_seconds),
        style: const TextStyle(
          color: Colors.greenAccent,
          fontSize: 18,
          fontWeight: FontWeight.w500,
        ),
      );
    }
    if (_waitingForOffer) {
      return const _PulsingText(text: 'Ringing...');
    }
    return _PulsingText(
      text: widget.isCaller ? 'Calling...' : 'Connecting...',
    );
  }

  Widget _controlBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    double size = 60,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            child: Icon(icon, color: Colors.white, size: size * 0.45),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ],
      ),
    );
  }
}

// ─── Pulsing text widget ──────────────────────────────────────────────────────
class _PulsingText extends StatefulWidget {
  final String text;
  const _PulsingText({required this.text});
  @override
  State<_PulsingText> createState() => _PulsingTextState();
}

class _PulsingTextState extends State<_PulsingText>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Text(
        widget.text,
        style: const TextStyle(color: Colors.white60, fontSize: 16),
      ),
    );
  }
}
