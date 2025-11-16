import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/chat_message.dart';
import '../models/message_status.dart';
import '../utils/mime_utils.dart';
import '../utils/time_utils.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final double maxBubbleWidth;
  final bool isAudio;
  final bool isPlaying;
  final double playbackProgress;
  final double uploadProgress;
  final VoidCallback? onPlay;
  final VoidCallback? onSave; // NEW: callback to save/download attachment
  final void Function(ChatMessage) onLongPress;

  const MessageBubble({
    super.key,
    required this.message,
    required this.maxBubbleWidth,
    required this.onLongPress,
    required this.isAudio,
    required this.isPlaying,
    required this.playbackProgress,
    required this.uploadProgress,
    this.onPlay,
    this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final body = _buildBody(context);
    final replyStrip = message.replyTo == null
        ? const SizedBox.shrink()
        : Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: message.isSentByMe ? Colors.white24 : Colors.black12,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message.replyTo!.preview,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontStyle: FontStyle.italic,
          color: message.isSentByMe ? Colors.white : Colors.black87,
        ),
      ),
    );

    final progressBar = (message.uploadProgress != null &&
        (message.uploadProgress ?? 1) < 1.0)
        ? Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SizedBox(
        width: 160,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            LinearProgressIndicator(
                value: message.uploadProgress!.clamp(0.0, 1.0)),
            const SizedBox(height: 2),
            Text(
              '${((message.uploadProgress ?? 0) * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 11,
                color: message.isSentByMe ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    )
        : const SizedBox.shrink();

    final bubble = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxBubbleWidth),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: message.isSentByMe ? Colors.teal.shade400 : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: message.isSentByMe ? const Radius.circular(12) : Radius.zero,
            bottomRight: message.isSentByMe ? Radius.zero : const Radius.circular(12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment:
          message.isSentByMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            replyStrip,
            body,
            progressBar,
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatTimestampLocal(message.timestamp),
                  style: TextStyle(
                    color: message.isSentByMe ? Colors.white70 : Colors.black54,
                    fontSize: 12,
                  ),
                ),
                if (message.isSentByMe) ...[
                  const SizedBox(width: 4),
                  _statusIcon(message.status),
                ],
                if (message.reaction != null && message.reaction!.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(message.reaction!, style: const TextStyle(fontSize: 14)),
                ]
              ],
            )
          ],
        ),
      ),
    );

    return GestureDetector(
      onLongPress: () => onLongPress(message),
      child: bubble,
    );
  }

  Widget _buildBody(BuildContext context) {
    final effectiveIsAudio = isAudio || _looksLikeAudio(message);

    // AUDIO takes precedence
    if (effectiveIsAudio) {
      final bool uploading = (uploadProgress > 0 && uploadProgress < 1.0);
      final double barValue = uploading
          ? uploadProgress.clamp(0.0, 1.0)
          : playbackProgress.clamp(0.0, 1.0);

      final iconColor = message.isSentByMe ? Colors.white : const Color(0xff0f766e);
      final textColor = message.isSentByMe ? Colors.white : Colors.black87;

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play / Pause button
          GestureDetector(
            onTap: onPlay,
            child: Icon(
              isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
              size: 34,
              color: iconColor,
            ),
          ),
          const SizedBox(width: 10),
          // Progress + label + optional save icon
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 160,
                height: 8,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: barValue,
                    backgroundColor:
                    message.isSentByMe ? Colors.white24 : Colors.grey.shade200,
                    minHeight: 8,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      uploading
                          ? 'Uploading ${((uploadProgress) * 100).toStringAsFixed(0)}%'
                          : (message.text.isNotEmpty ? message.text : 'Voice message'),
                      style: TextStyle(fontSize: 13, color: textColor.withOpacity(0.95)),
                    ),
                  ),
                  if (onSave != null) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: onSave,
                      child: Icon(
                        Icons.download_rounded,
                        size: 20,
                        color: textColor,
                      ),
                    )
                  ]
                ],
              ),
            ],
          ),
        ],
      );
    }

    // IMAGE
    if (message.attachmentUrl != null && isImage(message.attachmentUrl)) {
      return Column(
        crossAxisAlignment:
        message.isSentByMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              message.attachmentUrl!,
              width: 220,
              height: 220,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 80),
            ),
          ),
          if (message.text.isNotEmpty) const SizedBox(height: 6),
          if (message.text.isNotEmpty)
            Text(
              message.text,
              style: TextStyle(
                color: message.isSentByMe ? Colors.white : Colors.black87,
                fontSize: 16,
              ),
            ),
        ],
      );
    }

    // FILE / OTHER ATTACHMENT
    if (message.attachmentUrl != null) {
      final fileName = message.attachmentUrl!.split('/').last;
      return InkWell(
        onTap: () async {
          final url = Uri.parse(message.attachmentUrl!);
          if (await canLaunchUrl(url)) {
            await launchUrl(url, mode: LaunchMode.externalApplication);
          }
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file, size: 20),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                fileName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: message.isSentByMe ? Colors.white : Colors.black87,
                  fontSize: 15,
                ),
              ),
            ),
            if (onSave != null) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.download_rounded, size: 20),
                splashRadius: 18,
                onPressed: onSave,
              ),
            ]
          ],
        ),
      );
    }

    // PLAIN TEXT
    return Text(
      message.text,
      style: TextStyle(
        color: message.isSentByMe ? Colors.white : Colors.black87,
        fontSize: 16,
      ),
    );
  }

  Widget _statusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return const Icon(Icons.access_time, size: 16, color: Colors.grey);
      case MessageStatus.sent:
        return const Icon(Icons.check, size: 16, color: Colors.grey);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 16, color: Colors.grey);
      case MessageStatus.read:
        return const Icon(Icons.done_all, size: 16, color: Colors.blue);
    }
  }

  // Defensive audio detection (fallback) in case isAudio wasn't passed correctly
  bool _looksLikeAudio(ChatMessage m) {
    final at = (m.attachmentType ?? '').toLowerCase();
    if (at.startsWith('audio/')) return true;

    final urlRaw = (m.attachmentUrl ?? '').toLowerCase().trim();
    if (urlRaw.isEmpty) return false;

    // strip query params & fragments
    var url = urlRaw;
    final qIdx = url.indexOf('?');
    if (qIdx != -1) url = url.substring(0, qIdx);
    final hIdx = url.indexOf('#');
    if (hIdx != -1) url = url.substring(0, hIdx);

    const exts = ['.aac', '.m4a', '.mp3', '.wav', '.ogg', '.oga', '.flac', '.amr'];
    for (final e in exts) {
      if (url.endsWith(e)) return true;
    }

    // heuristic keywords
    if (url.contains('/audio/') ||
        url.contains('voice') ||
        url.contains('voicemsg') ||
        url.contains('voice_message')) {
      return true;
    }

    // fallback: file name tokens
    final fileName = urlRaw.split('/').last;
    for (final e in exts) {
      if (fileName.contains(e.replaceFirst('.', ''))) return true;
    }

    return false;
  }
}
