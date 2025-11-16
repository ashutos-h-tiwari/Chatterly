import 'package:flutter/material.dart';
import '../models/chat_message.dart';

class ReplyBanner extends StatelessWidget {
  final ChatMessage replyTo;
  final VoidCallback onCancel;
  const ReplyBanner({super.key, required this.replyTo, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black12,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.reply, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              replyTo.text.isNotEmpty ? replyTo.text : (replyTo.attachmentUrl ?? 'Attachment'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(icon: const Icon(Icons.close), onPressed: onCancel)
        ],
      ),
    );
  }
}
