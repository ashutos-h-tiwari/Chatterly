// // lib/call/agora_call_screen.dart
// import 'package:flutter/material.dart';
// import 'package:agora_rtc_engine/agora_rtc_engine.dart';
//
// import 'agora_call_controller.dart';
//
// class AgoraCallScreen extends StatefulWidget {
//   final String appId;
//   final String token;
//   final String channelName;
//   final int localUid;
//   final bool video;
//
//   const AgoraCallScreen({
//     super.key,
//     required this.appId,
//     required this.token,
//     required this.channelName,
//     required this.localUid,
//     this.video = true,
//   });
//
//   @override
//   State<AgoraCallScreen> createState() => _AgoraCallScreenState();
// }
//
// class _AgoraCallScreenState extends State<AgoraCallScreen> {
//   late AgoraCallController _controller;
//
//   @override
//   void initState() {
//     super.initState();
//     _controller = AgoraCallController(
//       appId: widget.appId,
//       channelName: widget.channelName,
//       token: widget.token,
//       uid: widget.localUid,
//       video: widget.video,
//     );
//     _init();
//   }
//
//   Future<void> _init() async {
//     await _controller.init();
//     setState(() {});
//   }
//
//   @override
//   void dispose() {
//     _controller.leave();
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.black,
//       body: Stack(
//         children: [
//           // remote
//           Center(
//             child: widget.video
//                 ? AgoraVideoView(
//               controller: VideoViewController.remote(
//                 rtcEngine: _controller.engine,
//                 canvas: const VideoCanvas(uid: 0),
//                 connection: RtcConnection(
//                   channelId: widget.channelName,
//                 ),
//               ),
//             )
//                 : const Icon(Icons.call, size: 80, color: Colors.white),
//           ),
//           // local
//           if (widget.video)
//             Positioned(
//               top: 40,
//               right: 16,
//               width: 120,
//               height: 180,
//               child: AgoraVideoView(
//                 controller: VideoViewController(
//                   rtcEngine: _controller.engine,
//                   canvas: VideoCanvas(uid: widget.localUid),
//                 ),
//               ),
//             ),
//           // controls
//           Align(
//             alignment: Alignment.bottomCenter,
//             child: Padding(
//               padding: const EdgeInsets.only(bottom: 40),
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 children: [
//                   IconButton(
//                     icon: const Icon(Icons.mic_off, color: Colors.white),
//                     onPressed: _controller.toggleMute,
//                   ),
//                   const SizedBox(width: 32),
//                   FloatingActionButton(
//                     backgroundColor: Colors.red,
//                     child: const Icon(Icons.call_end),
//                     onPressed: () {
//                       _controller.leave();
//                       Navigator.pop(context);
//                     },
//                   ),
//                   const SizedBox(width: 32),
//                   if (widget.video)
//                     IconButton(
//                       icon: const Icon(Icons.cameraswitch, color: Colors.white),
//                       onPressed: _controller.switchCamera,
//                     ),
//                 ],
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
