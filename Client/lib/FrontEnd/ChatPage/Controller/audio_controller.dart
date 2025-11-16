// lib/FrontEnd/ChatPage/controllers/audio_controller.dart
import 'dart:async';
import 'package:just_audio/just_audio.dart';
import '../models/chat_message.dart';

class AudioController {
  final AudioPlayer _player = AudioPlayer();

  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  String? _playingMessageId;
  String? get playingMessageId => _playingMessageId;

  Future<void> dispose() => _player.dispose();

  Future<void> playMessage(ChatMessage m) async {
    final src = m.attachmentUrl ?? '';
    if (src.isEmpty) throw Exception('No source');
    if (_playingMessageId != null && _playingMessageId != m.id) {
      await _player.stop();
      _playingMessageId = null;
    }
    if (src.startsWith('http')) {
      await _player.setUrl(src);
    } else {
      await _player.setFilePath(src);
    }
    _playingMessageId = m.id;
    await _player.play();
  }

  Future<void> togglePause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> stop() async {
    await _player.stop();
    _playingMessageId = null;
  }
}
