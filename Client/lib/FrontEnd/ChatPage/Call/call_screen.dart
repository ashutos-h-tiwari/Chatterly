import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'CallController.dart';
import 'call_socket.dart';
import 'dart:async';

class CallScreen extends StatefulWidget {
  final String localUserId;
  final String remoteUserId;
  final String conversationId;
  // PASS THE EXISTING SOCKET
  final CallSocket socket;
  final bool isCaller;
  final bool video;

  // If callee, we might already have the offer from the ChatPage
  final String? initialOffer;

  const CallScreen({
    Key? key,
    required this.localUserId,
    required this.remoteUserId,
    required this.conversationId,
    required this.socket,
    this.isCaller = false,
    this.video = true,
    this.initialOffer,
  }) : super(key: key);

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  CallController? _controller;
  bool inCall = false;
  StreamSubscription? _incomingSub;
  StreamSubscription? _endedSub;

  @override
  void initState() {
    super.initState();
    _initCall();
  }

  Future<void> _initCall() async {
    _controller = CallController(
      localUserId: widget.localUserId,
      remoteUserId: widget.remoteUserId,
      conversationId: widget.conversationId,
      socket: widget.socket,
    );

    await _controller!.init();

    if (widget.isCaller) {
      // 1. WE ARE CALLING
      await _controller!.startCall(video: widget.video);
      setState(() => inCall = true);
    } else {
      // 2. WE ARE ANSWERING
      if (widget.initialOffer != null) {
        // We already have the offer from ChatPage
        await _controller!.answerIncomingOffer(
          offerSdp: widget.initialOffer!,
          video: widget.video,
        );
        setState(() => inCall = true);
      } else {
        // We accepted the "ring" but the "offer" packet hasn't arrived/processed yet.
        // Listen for the offer specifically here.
        _incomingSub = widget.socket.onIncomingCall.listen((data) {
          final convId = (data['conversationId'] ?? data['roomId'] ?? '').toString();
          if (convId != widget.conversationId) return;

          final offer = data['offer'];
          // Ensure it's an offer, not just a pure notify
          if (offer != null && !inCall) {
            _controller!.answerIncomingOffer(
              offerSdp: offer,
              video: widget.video,
            );
            setState(() => inCall = true);
          }
        });
      }
    }

    // Listen for End Call event to close screen
    _endedSub = widget.socket.onCallEnded.listen((data) {
      final convId = (data['conversationId'] ?? data['roomId'] ?? '').toString();
      if (convId != widget.conversationId) return;
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    // Do NOT dispose widget.socket here, it belongs to ChatPage!
    _incomingSub?.cancel();
    _endedSub?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _endCall() {
    _controller?.endCall(reason: 'local_hangup');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final local = _controller?.localRenderer;
    final remote = _controller?.remoteRenderer;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Remote Video (Full Screen)
          Positioned.fill(
            child: remote != null && remote.srcObject != null
                ? RTCVideoView(
              remote,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
                : const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),

          // Local Video (Floating PIP)
          if (widget.video)
            Positioned(
              right: 16,
              top: 48,
              width: 120,
              height: 160,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white54),
                  color: Colors.black87,
                ),
                child: (local != null)
                    ? RTCVideoView(
                  local,
                  mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
                    : null,
              ),
            ),

          // Controls
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 40.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  FloatingActionButton(
                    heroTag: "mute",
                    backgroundColor: Colors.white24,
                    onPressed: () => _controller?.toggleMute(),
                    child: const Icon(Icons.mic_off),
                  ),
                  FloatingActionButton(
                    heroTag: "hangup",
                    backgroundColor: Colors.red,
                    onPressed: _endCall,
                    child: const Icon(Icons.call_end),
                  ),
                  if (widget.video)
                    FloatingActionButton(
                      heroTag: "switch_cam",
                      backgroundColor: Colors.white24,
                      onPressed: () => _controller?.switchCamera(),
                      child: const Icon(Icons.switch_camera),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
