// lib/FrontEnd/ChatPage/services/recorder_service.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

/// RecorderService: a small wrapper around FlutterSoundRecorder
/// - call init() once (e.g. in ChatPage.initState)
/// - call startRecording() to begin; returns true if recording started
/// - call stopRecordingAndMoveToAppDir() to stop and move file to app documents (returns new path)
/// - call cancelRecording() to stop and delete temp if needed
/// - call dispose() when done (e.g. in ChatPage.dispose)
class RecorderService {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _initialized = false;

  /// Temporary file path while recording
  String? _currentTempPath;

  /// Call in initState
  Future<void> init() async {
    try {
      await _recorder.openRecorder();
      // On iOS you typically need to set the audio category — flutter_sound handles defaults
      _initialized = true;
    } catch (e) {
      debugPrint('RecorderService.init failed: $e');
      _initialized = false;
    }
  }

  bool get isInitialized => _initialized;
  bool get isRecording => _recorder.isRecording;

  /// Request microphone permission and start recording to a temporary file.
  /// Returns true if recording started successfully.
  Future<bool> startRecording({String fileExt = 'aac'}) async {
    if (!_initialized) {
      debugPrint('RecorderService.startRecording: recorder not initialized');
      return false;
    }

    // Request microphone permission
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      debugPrint('RecorderService.startRecording: microphone permission denied');
      return false;
    }

    try {
      final tmpDir = await getTemporaryDirectory();
      final fileName = 'rec_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final tmpPath = '${tmpDir.path}/$fileName';
      _currentTempPath = tmpPath;

      await _recorder.startRecorder(
        toFile: tmpPath,
        codec: Codec.aacADTS,
        bitRate: 128000,
        sampleRate: 44100,
      );

      return true;
    } catch (e) {
      debugPrint('RecorderService.startRecording error: $e');
      _currentTempPath = null;
      return false;
    }
  }

  /// Stop recording, move the recorded temp file into app documents (persistent) and return the new path.
  /// Returns null on failure.
  Future<String?> stopRecordingAndMoveToAppDir({String? preferredExtension}) async {
    if (!_initialized || !_recorder.isRecording) {
      debugPrint('RecorderService.stopRecordingAndMoveToAppDir: not recording');
      return null;
    }

    try {
      final recordedPath = await _recorder.stopRecorder();
      // recordedPath can be null or the tmp path
      if (recordedPath == null) {
        debugPrint('RecorderService: stopRecorder returned null');
        return null;
      }

      final src = File(recordedPath);
      if (!await src.exists()) {
        debugPrint('RecorderService: recorded file not found at $recordedPath');
        return null;
      }

      final ext = preferredExtension ?? recordedPath.split('.').last;
      final millis = DateTime.now().millisecondsSinceEpoch;
      final newName = 'voice_$millis.$ext';

      // Destination: application documents (persistent)
      final appDoc = await getApplicationDocumentsDirectory();
      final destDir = Directory('${appDoc.path}/SutraAudio'); // keep in app docs under SutraAudio
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }
      final newPath = '${destDir.path}/$newName';

      await src.copy(newPath);

      // Optionally delete temp file (safe to keep)
      try {
        if (await src.exists()) {
          await src.delete();
        }
      } catch (_) {}

      _currentTempPath = null;
      return newPath;
    } catch (e) {
      debugPrint('RecorderService.stopRecordingAndMoveToAppDir error: $e');
      _currentTempPath = null;
      return null;
    }
  }

  /// Stop recording and discard temp file (if any)
  Future<void> cancelRecording() async {
    try {
      if (_recorder.isRecording) {
        await _recorder.stopRecorder();
      }
    } catch (e) {
      debugPrint('RecorderService.cancelRecording stop error: $e');
    }

    if (_currentTempPath != null) {
      try {
        final f = File(_currentTempPath!);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (e) {
        debugPrint('RecorderService.cancelRecording delete temp error: $e');
      } finally {
        _currentTempPath = null;
      }
    }
  }

  /// Close the recorder
  Future<void> dispose() async {
    try {
      await _recorder.closeRecorder();
    } catch (e) {
      debugPrint('RecorderService.dispose error: $e');
    } finally {
      _initialized = false;
    }
  }
}
