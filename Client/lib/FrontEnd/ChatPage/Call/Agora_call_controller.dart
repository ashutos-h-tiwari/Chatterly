// // lib/call/agora_call_controller.dart
// import 'package:agora_rtc_engine/agora_rtc_engine.dart';
// import 'package:permission_handler/permission_handler.dart';
//
// class AgoraCallController {
//   final String appId;
//   final String channelName;
//   final String token;
//   final int uid;
//   final bool video;
//
//   late RtcEngine _engine;
//   int? remoteUid;
//   bool _muted = false;
//   bool _initialized = false;
//
//   AgoraCallController({
//     required this.appId,
//     required this.channelName,
//     required this.token,
//     required this.uid,
//     required this.video,
//   });
//
//   RtcEngine get engine => _engine;
//
//   Future<void> init() async {
//     // Request permissions
//     final statuses = await [
//       Permission.microphone,
//       if (video) Permission.camera,
//     ].request();
//
//     if (statuses.values.any((s) => !s.isGranted)) {
//       throw Exception('Required permissions not granted');
//     }
//
//     _engine = createAgoraRtcEngine();
//     await _engine.initialize(
//       RtcEngineContext(appId: appId),
//     );
//
//     await _engine.enableAudio();
//     if (video) {
//       await _engine.enableVideo();
//     }
//
//     _engine.registerEventHandler(
//       RtcEngineEventHandler(
//         onJoinChannelSuccess: (connection, elapsed) {
//           print('Agora: local joined ${connection.channelId}');
//         },
//         onUserJoined: (connection, rUid, elapsed) {
//           print('Agora: remote joined $rUid');
//           remoteUid = rUid;
//         },
//         onUserOffline: (connection, rUid, reason) {
//           print('Agora: remote left $rUid');
//           remoteUid = null;
//         },
//       ),
//     );
//
//     await _engine.joinChannel(
//       token: token,
//       channelId: channelName,
//       uid: uid,
//       options: const ChannelMediaOptions(
//         channelProfile: ChannelProfileType.channelProfileCommunication,
//         clientRoleType: ClientRoleType.clientRoleBroadcaster,
//       ),
//     );
//
//     _initialized = true;
//   }
//
//   Future<void> toggleMute() async {
//     if (!_initialized) return;
//     _muted = !_muted;
//     await _engine.muteLocalAudioStream(_muted);
//   }
//
//   Future<void> switchCamera() async {
//     if (!_initialized || !video) return;
//     await _engine.switchCamera();
//   }
//
//   Future<void> leave() async {
//     if (!_initialized) return;
//     await _engine.leaveChannel();
//     await _engine.release();
//     _initialized = false;
//   }
// }
