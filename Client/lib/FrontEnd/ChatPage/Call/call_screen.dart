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

  final Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
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
  StreamSubscription? _subIncoming; // ✅ to catch offer from call-user event

  final List<RTCIceCandidate> _iceCandidateQueue = [];
  bool _remoteDescSet = false;

  // ✅ Flag: are we waiting for offer (notifyOnly case)
  bool _waitingForOffer = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    await _createPeerConnection();
    await _getLocalStream();
    _listenSocketEvents();

    if (widget.isCaller) {
      await _startCallAsCaller();
    } else {
      await _startCallAsCallee();
    }
  }

  Future<void> _createPeerConnection() async {
    _pc = await createPeerConnection(_iceConfig);

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
    };

    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty && mounted) {
        setState(() => _remoteRenderer.srcObject = event.streams[0]);
      }
    };

    _pc!.onConnectionState = (state) {
      print('🔗 PeerConnection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        if (mounted) setState(() => _isConnected = true);
        _startTimer();
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        // ✅ Only end if we were actually connected — not while waiting for offer
        if (!_waitingForOffer) {
          _endCall(reason: 'connection-failed');
        }
      }
    };
  }

  Future<void> _getLocalStream() async {
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': widget.video ? {'facingMode': 'user'} : false,
      });

      if (widget.video) _localRenderer.srcObject = _localStream;

      for (final track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }
    } catch (e) {
      print('❌ getLocalStream error: $e');
      _showSnack('Could not access microphone/camera');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CALLER SIDE
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _startCallAsCaller() async {
    final offer = await _pc!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': widget.video,
    });
    await _pc!.setLocalDescription(offer);

    widget.socket.emitCallUser(
      to: widget.remoteUserId,
      conversationId: widget.conversationId,
      offer: {'sdp': offer.sdp, 'type': offer.type},
    );
    print('📡 Offer sent to ${widget.remoteUserId}');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CALLEE SIDE
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _startCallAsCallee() async {
    final offer = widget.initialOffer;

    // ✅ KEY FIX: Check if offer has actual SDP
    // If notifyOnly=true, offer will be null or empty — just wait
    if (offer != null && offer['sdp'] != null && offer['sdp'].toString().isNotEmpty) {
      print('📨 Offer already available — handling immediately');
      await _handleOffer(offer);
    } else {
      // ✅ notifyOnly case — wait for actual offer via call-user socket event
      print('⏳ No offer yet (notifyOnly) — waiting for call-user event...');
      _waitingForOffer = true;
      if (mounted) setState(() {}); // show "Connecting..." UI
    }
  }

  Future<void> _handleOffer(dynamic offerData) async {
    try {
      _waitingForOffer = false;

      final sdp  = offerData['sdp']?.toString()  ?? '';
      final type = offerData['type']?.toString() ?? 'offer';

      if (sdp.isEmpty) {
        print('⚠️ SDP is empty — still waiting');
        _waitingForOffer = true;
        return;
      }

      print('📨 Setting remote description (offer)...');
      await _pc!.setRemoteDescription(RTCSessionDescription(sdp, type));
      _remoteDescSet = true;

      // Flush queued ICE candidates
      print('🧊 Flushing ${_iceCandidateQueue.length} queued ICE candidates');
      for (final c in _iceCandidateQueue) {
        await _pc!.addCandidate(c);
      }
      _iceCandidateQueue.clear();

      // Create and send answer
      final answer = await _pc!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': widget.video,
      });
      await _pc!.setLocalDescription(answer);

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
  // SOCKET LISTENERS
  // ══════════════════════════════════════════════════════════════════════════
  void _listenSocketEvents() {

    // ✅ KEY FIX: Callee listens for the ACTUAL offer from call-user event
    // This fires after call-initiate (notifyOnly) when caller sends real offer
    _subIncoming = widget.socket.onIncomingCall.listen((data) async {
      if (!widget.isCaller) {
        final offer = data['offer'];
        final isNotifyOnly = data['notifyOnly'] == true;

        if (!isNotifyOnly && offer != null) {
          // This is the real offer from call-user event
          print('📨 Received actual offer via incoming-call (call-user)');
          await _handleOffer(offer);
        }
      }
    });

    // CALLER: receives answer from callee
    _subAnswered = widget.socket.onCallAnswered.listen((data) async {
      try {
        final answer = data['answer'];
        if (answer == null) return;
        final sdp  = answer['sdp']?.toString()  ?? '';
        final type = answer['type']?.toString() ?? 'answer';
        if (sdp.isEmpty) return;

        print('✅ Received answer — setting remote description');
        await _pc!.setRemoteDescription(RTCSessionDescription(sdp, type));
        _remoteDescSet = true;

        // Flush queued ICE candidates
        for (final c in _iceCandidateQueue) {
          await _pc!.addCandidate(c);
        }
        _iceCandidateQueue.clear();

        print('✅ Remote answer set successfully');
      } catch (e) {
        print('❌ onCallAnswered error: $e');
      }
    });

    // BOTH: ICE candidates — queue if remote desc not set yet
    _subIce = widget.socket.onIceCandidate.listen((data) async {
      try {
        final c = data['candidate'];
        if (c == null) return;

        final candidate = RTCIceCandidate(
          c['candidate']?.toString() ?? '',
          c['sdpMid']?.toString(),
          c['sdpMLineIndex'] as int? ?? 0,
        );

        if (_remoteDescSet) {
          await _pc!.addCandidate(candidate);
          print('🧊 ICE candidate added directly');
        } else {
          // ✅ Queue until remote description is ready
          _iceCandidateQueue.add(candidate);
          print('🧊 ICE candidate queued (${_iceCandidateQueue.length} total)');
        }
      } catch (e) {
        print('❌ ice-candidate error: $e');
      }
    });

    // Call ended by remote
    _subEnded = widget.socket.onCallEnded.listen((data) {
      print('📴 Remote ended call — reason: ${data['reason']}');
      _endCall(reason: 'remote-ended', navigate: true);
    });

    // Call declined
    _subDeclined = widget.socket.onCallDeclined.listen((data) {
      _showSnack('Call declined');
      _endCall(reason: 'declined', navigate: true);
    });

    // Callee busy
    _subBusy = widget.socket.onCallBusy.listen((data) {
      _showSnack('User is busy');
      _endCall(reason: 'busy', navigate: true);
    });

    // Callee offline
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
    _localStream?.getAudioTracks().forEach((t) => t.enabled = _isMuted);
    setState(() => _isMuted = !_isMuted);
  }

  void _toggleSpeaker() {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    Helper.setSpeakerphoneOn(_isSpeakerOn);
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
    _timer?.cancel();
    _cleanup();
    if (navigate && mounted) Navigator.of(context).pop();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
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
        Positioned.fill(
          child: RTCVideoView(
            _remoteRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
        ),
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
        Positioned(
          top: 20,
          left: 0,
          right: 130,
          child: Center(child: _buildStatusText()),
        ),
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
    return _PulsingText(text: widget.isCaller ? 'Calling...' : 'Connecting...');
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
