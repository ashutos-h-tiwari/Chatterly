// lib/FrontEnd/ChatPage/widgets/message_list.dart
import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import 'message_bubble.dart';

/// MessageList widget
/// - displays messages in reverse order (newest at bottom)
/// - expects callbacks from parent (ChatPage)
///
/// Required arguments:
///  - messages: list of ChatMessage
///  - onTap: called when item tapped (ChatPage can decide open image / play audio)
///  - onSave: called when user requests save/download for a message
///  - onLongPress: called when user long-presses a message (reactions/reply)
///  - onPlay: called when user presses play on an audio message (toggle play/pause)
///  - isAudioMessage: predicate to detect audio messages
///  - maxBubbleWidth: width bound used by MessageBubble
///  - playingMessageId: id of currently playing message (or null)
///  - audioDuration & audioPosition: used to compute playbackProgress for the currently playing audio
class MessageList extends StatelessWidget {
  final List<ChatMessage> messages;
  final void Function(ChatMessage) onTap;
  final void Function(ChatMessage) onSave;
  final void Function(ChatMessage) onLongPress;
  final void Function(ChatMessage) onPlay;

  /// predicate which returns true if a message should be treated as audio
  final bool Function(ChatMessage) isAudioMessage;

  final double maxBubbleWidth;

  /// id of message currently playing (or null)
  final String? playingMessageId;

  /// the overall audio duration and position (used to compute playback progress for currently playing message)
  final Duration audioDuration;
  final Duration audioPosition;

  const MessageList({
    Key? key,
    required this.messages,
    required this.onTap,
    required this.onSave,
    required this.onLongPress,
    required this.onPlay,
    required this.isAudioMessage,
    required this.maxBubbleWidth,
    required this.playingMessageId,
    required this.audioDuration,
    required this.audioPosition,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Reverse: newest messages at bottom (ListView scrolls from bottom)
    return ListView.builder(
      controller: ScrollController(),
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        // display messages in reverse order
        final msg = messages[messages.length - 1 - index];

        // compute playback progress for this message (only meaningful for the currently playing message)
        double playbackProgress = 0.0;
        if (playingMessageId != null && playingMessageId == msg.id && audioDuration.inMilliseconds > 0) {
          playbackProgress = (audioPosition.inMilliseconds / audioDuration.inMilliseconds).clamp(0.0, 1.0);
        }

        final bool isAudio = isAudioMessage(msg);

        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 10 * (1 - value)),
                child: child,
              ),
            );
          },
          child: Align(
            alignment: msg.isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(msg),
              onLongPress: () => onLongPress(msg),
              child: MessageBubble(
                message: msg,
                maxBubbleWidth: maxBubbleWidth,
                // onLongPress: () => onLongPress(msg),
                onSave: () => onSave(msg),

                // audio-related props
                isAudio: isAudio,
                isPlaying: playingMessageId == msg.id,
                onPlay: () => onPlay(msg),
                playbackProgress: playbackProgress,
                uploadProgress: msg.uploadProgress ?? 0.0, onLongPress: (ChatMessage p1) {  },
              ),
            ),
          ),
        );
      },
    );
  }
}
