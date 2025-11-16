// lib/FrontEnd/ChatPage/models/chat_message.dart
import 'package:flutter/material.dart';
import '../models/message_status.dart';
import '../models/reply_ref.dart';
import '../utils/json_utils.dart';

class ChatMessage {
  final String id;
  final String text;
  final bool isSentByMe;
  final DateTime timestamp; // ALWAYS local
  final MessageStatus status;
  final String? attachmentUrl;   // remote URL OR local file path
  final String? attachmentType;  // MIME type (e.g. audio/aac, audio/m4a)
  final double? uploadProgress;  // 0..1 (null => none/finished)
  final String? reaction; // client-side
  final ReplyRef? replyTo;

  const ChatMessage({
    required this.id,
    required this.text,
    required this.isSentByMe,
    required this.timestamp,
    this.status = MessageStatus.sent,
    this.attachmentUrl,
    this.attachmentType,
    this.uploadProgress,
    this.reaction,
    this.replyTo,
  });

  ChatMessage copyWith({
    String? id,
    String? text,
    bool? isSentByMe,
    DateTime? timestamp,
    MessageStatus? status,
    String? attachmentUrl,
    String? attachmentType,
    double? uploadProgress,
    String? reaction,
    ReplyRef? replyTo,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      text: text ?? this.text,
      isSentByMe: isSentByMe ?? this.isSentByMe,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      attachmentUrl: attachmentUrl ?? this.attachmentUrl,
      attachmentType: attachmentType ?? this.attachmentType,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      reaction: reaction ?? this.reaction,
      replyTo: replyTo ?? this.replyTo,
    );
  }

  Map<String, dynamic> toCache() => {
    'id': id,
    'text': text,
    'isSentByMe': isSentByMe,
    'timestamp': timestamp.toIso8601String(),
    'status': status.index,
    'attachmentUrl': attachmentUrl,
    'attachmentType': attachmentType,
    'uploadProgress': uploadProgress,
    'reaction': reaction,
    'replyTo': replyTo == null ? null : {'id': replyTo!.id, 'preview': replyTo!.preview},
  };

  factory ChatMessage.fromCache(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id']?.toString() ?? UniqueKey().toString(),
      text: json['text']?.toString() ?? '',
      isSentByMe: json['isSentByMe'] == true,
      timestamp:
      DateTime.tryParse(json['timestamp']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      status: MessageStatus.values[(json['status'] ?? 1).clamp(0, MessageStatus.values.length - 1)],
      attachmentUrl: json['attachmentUrl']?.toString(),
      attachmentType: json['attachmentType']?.toString(),
      uploadProgress: (json['uploadProgress'] as num?)?.toDouble(),
      reaction: json['reaction']?.toString(),
      replyTo: json['replyTo'] is Map ? ReplyRef.fromMap(asStringKeyMap(json['replyTo'])) : null,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json, {String? myUserId}) {
    String? senderId;
    final senderRaw = json['sender'];
    if (senderRaw is Map) {
      senderId = senderRaw['_id']?.toString() ?? senderRaw['id']?.toString();
    } else {
      senderId = json['senderId']?.toString() ??
          json['sender']?.toString() ??
          (json['from'] is Map ? json['from']['_id']?.toString() : json['from']?.toString());
    }

    // Convert any server ISO to LOCAL
    final createdAtStr =
        json['createdAt']?.toString() ?? json['time']?.toString() ?? json['sentAt']?.toString();
    DateTime ts;
    if (createdAtStr != null) {
      final parsed = DateTime.tryParse(createdAtStr);
      ts = (parsed ?? DateTime.now()).toLocal();
    } else {
      ts = DateTime.now();
    }

    final text = json['text']?.toString() ??
        json['content']?.toString() ??
        json['message']?.toString() ??
        '';

    String? firstAttachment;
    String? firstAttachmentType;
    if (json['attachments'] is List && (json['attachments'] as List).isNotEmpty) {
      final att = (json['attachments'] as List).first;
      if (att is Map) {
        firstAttachment = (att['url'] ?? att['path'] ?? att['file'])?.toString();
        firstAttachmentType = (att['mime'] ?? att['type'])?.toString();
      } else {
        firstAttachment = att?.toString();
      }
    } else if (json['attachment'] != null) {
      if (json['attachment'] is Map) {
        final att = json['attachment'] as Map;
        firstAttachment = (att['url'] ?? att['path'] ?? att['file'])?.toString();
        firstAttachmentType = (att['mime'] ?? att['type'])?.toString();
      } else {
        firstAttachment = json['attachment']?.toString();
      }
    } else if (json['fileUrl'] != null) {
      firstAttachment = json['fileUrl']?.toString();
      firstAttachmentType = json['mime']?.toString();
    }

    ReplyRef? reply;
    if (json['replyTo'] != null) {
      final r = asStringKeyMap(json['replyTo']);
      reply = ReplyRef.fromMap(r);
    }

    return ChatMessage(
      id: json['_id']?.toString() ??
          json['id']?.toString() ??
          json['messageId']?.toString() ??
          json['clientId']?.toString() ??
          UniqueKey().toString(),
      text: text,
      isSentByMe: (myUserId != null && senderId == myUserId),
      timestamp: ts,
      status: MessageStatus.sent,
      attachmentUrl: firstAttachment,
      attachmentType: firstAttachmentType,
      uploadProgress: null,
      reaction: null,
      replyTo: reply,
    );
  }
}
