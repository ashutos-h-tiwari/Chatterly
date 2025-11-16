// lib/FrontEnd/ChatPage/controllers/recorder_controller.dart
import 'dart:io';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

class RecorderController {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();

  Future<void> init() async {
    await _recorder.openRecorder();
  }

  Future<void> dispose() async {
    await _recorder.closeRecorder();
  }

  Future<String?> startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) return null;
    final tmp = await getTemporaryDirectory();
    final path = '${tmp.path}/rec_${DateTime.now().millisecondsSinceEpoch}.aac';
    await _recorder.startRecorder(toFile: path, codec: Codec.aacADTS);
    return path;
  }

  Future<String?> stopRecording() async {
    final path = await _recorder.stopRecorder();
    return path;
  }

  Future<void> cancel() async {
    try { if (_recorder.isRecording) await _recorder.stopRecorder(); } catch (_) {}
  }
}
