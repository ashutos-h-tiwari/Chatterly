// lib/FrontEnd/ChatPage/services/audio_service.dart
import 'dart:async';
import 'package:just_audio/just_audio.dart';

/// AudioService: small wrapper around just_audio's AudioPlayer.
/// Exposes streams for UI and simple API: setSource/play/pause/stop.
class AudioService {
  final AudioPlayer _player = AudioPlayer();

  // Streams for UI to subscribe
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  String? _currentSource;

  /// Set source — accepts network URL or local file path.
  Future<void> setSource(String src) async {
    _currentSource = src;
    if (src.startsWith('http') || src.startsWith('https')) {
      await _player.setUrl(src);
    } else {
      await _player.setFilePath(src);
    }
  }

  /// Play (assumes source set)
  Future<void> play() async {
    await _player.play();
  }

  /// Pause
  Future<void> pause() async {
    await _player.pause();
  }

  /// Toggle play/pause convenience
  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  /// Stop and clear
  Future<void> stop() async {
    await _player.stop();
  }

  /// Dispose the player when done
  Future<void> dispose() async {
    await _player.dispose();
  }

  /// Returns whether currently playing
  bool get playing => _player.playing;

  /// Returns last set source
  String? get currentSource => _currentSource;
}
