// lib/FrontEnd/ChatPage/models/chat_message.dart
import 'package:flutter/material.dart';
import '../models/message_status.dart';
import '../models/reply_ref.dart';
import '../utils/json_utils.dart';

class ChatMessage {
  final String id;
  final String? senderId;    // needed for E2EE decrypt
  final String? cipherText;  // raw Signal ciphertext from server
  final String? contentType; // 'signal:prekey' | 'signal:whisper' | 'signal:attachment'
  final String text;         // decrypted plaintext (empty until decrypted)
  final bool isSentByMe;
  final DateTime timestamp;
  final MessageStatus status;
  final String? attachmentUrl;
  final String? attachmentType;
  final double? uploadProgress;
  final String? reaction;
  final ReplyRef? replyTo;

  const ChatMessage({
    this.senderId,
    this.cipherText,
    this.contentType,
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

  // ── copyWith ─────────────────────────────────────────────────────────────
  // ALL fields included so E2EE fields survive status/timestamp updates
  ChatMessage copyWith({
    String? id,
    String? senderId,
    String? cipherText,
    String? contentType,
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
      id:             id             ?? this.id,
      senderId:       senderId       ?? this.senderId,
      cipherText:     cipherText     ?? this.cipherText,
      contentType:    contentType    ?? this.contentType,
      text:           text           ?? this.text,
      isSentByMe:     isSentByMe     ?? this.isSentByMe,
      timestamp:      timestamp      ?? this.timestamp,
      status:         status         ?? this.status,
      attachmentUrl:  attachmentUrl  ?? this.attachmentUrl,
      attachmentType: attachmentType ?? this.attachmentType,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      reaction:       reaction       ?? this.reaction,
      replyTo:        replyTo        ?? this.replyTo,
    );
  }

  // ── Cache (SharedPreferences) ─────────────────────────────────────────────
  // Store decrypted text only — never persist cipherText to cache
  Map<String, dynamic> toCache() => {
    'id':             id,
    'senderId':       senderId,
    'text':           text,
    'isSentByMe':     isSentByMe,
    'timestamp':      timestamp.toIso8601String(),
    'status':         status.index,
    'attachmentUrl':  attachmentUrl,
    'attachmentType': attachmentType,
    'uploadProgress': uploadProgress,
    'reaction':       reaction,
    'replyTo': replyTo == null
        ? null
        : {'id': replyTo!.id, 'preview': replyTo!.preview},
  };

  factory ChatMessage.fromCache(Map<String, dynamic> json) {
    return ChatMessage(
      id:         json['id']?.toString() ?? UniqueKey().toString(),
      senderId:   json['senderId']?.toString(),
      // cipherText intentionally not cached — text is already decrypted
      text:       json['text']?.toString() ?? '',
      isSentByMe: json['isSentByMe'] == true,
      timestamp:  DateTime.tryParse(json['timestamp']?.toString() ?? '')
          ?.toLocal() ?? DateTime.now(),
      status: MessageStatus.values[
      (json['status'] ?? 1).clamp(0, MessageStatus.values.length - 1)
      ],
      attachmentUrl:  json['attachmentUrl']?.toString(),
      attachmentType: json['attachmentType']?.toString(),
      uploadProgress: (json['uploadProgress'] as num?)?.toDouble(),
      reaction:       json['reaction']?.toString(),
      replyTo: json['replyTo'] is Map
          ? ReplyRef.fromMap(asStringKeyMap(json['replyTo']))
          : null,
    );
  }

  // ── fromJson (from server API / socket) ──────────────────────────────────
  factory ChatMessage.fromJson(Map<String, dynamic> json, {String? myUserId}) {

    // ── 1. E2EE fields — parsed ONCE, used throughout ──
    final String? rawCipherText  = json['cipherText']?.toString();
    final String? rawContentType = json['contentType']?.toString();

    // ── 2. Sender ID ──
    String? senderId;
    final senderRaw = json['sender'];
    if (senderRaw is Map) {
      senderId = senderRaw['_id']?.toString() ?? senderRaw['id']?.toString();
    } else {
      senderId = json['senderId']?.toString()
          ?? json['sender']?.toString()
          ?? (json['from'] is Map
              ? (json['from']['_id'] ?? json['from']['id'])?.toString()
              : json['from']?.toString());
    }

    // ── 3. Timestamp → always local ──
    final createdAtStr = json['createdAt']?.toString()
        ?? json['time']?.toString()
        ?? json['sentAt']?.toString();
    final ts = createdAtStr != null
        ? (DateTime.tryParse(createdAtStr) ?? DateTime.now()).toLocal()
        : DateTime.now();

    // ── 4. Text — single authoritative parse ──
    // If cipherText exists, text will be empty here and filled in later
    // by E2EService.decrypt() in ChatPage._loadMessages / chat_socket onIncoming.
    // If server already returned plaintext (own messages, legacy), use it.
    final String plainText = (json['text']?.toString() ?? '').isNotEmpty
        ? json['text'].toString()
        : (json['content']?.toString() ?? json['message']?.toString() ?? '');

    // ── 5. Attachments ──
    String? firstAttachment;
    String? firstAttachmentType;

    if (json['attachments'] is List && (json['attachments'] as List).isNotEmpty) {
      final att = (json['attachments'] as List).first;
      if (att is Map) {
        firstAttachment     = (att['url'] ?? att['path'] ?? att['file'])?.toString();
        firstAttachmentType = (att['mime'] ?? att['type'])?.toString();
      } else {
        firstAttachment = att?.toString();
      }
    } else if (json['attachment'] != null) {
      if (json['attachment'] is Map) {
        final att = json['attachment'] as Map;
        firstAttachment     = (att['url'] ?? att['path'] ?? att['file'])?.toString();
        firstAttachmentType = (att['mime'] ?? att['type'])?.toString();
      } else {
        firstAttachment = json['attachment']?.toString();
      }
    } else if (json['attachmentUrl'] != null) {
      firstAttachment     = json['attachmentUrl'].toString();
      firstAttachmentType = json['mime']?.toString();
    } else if (json['fileUrl'] != null) {
      firstAttachment     = json['fileUrl'].toString();
      firstAttachmentType = json['mime']?.toString();
    }

    // ── 6. Reply ──
    ReplyRef? reply;
    if (json['replyTo'] != null) {
      reply = ReplyRef.fromMap(asStringKeyMap(json['replyTo']));
    }

    // ── 7. Build model ──
    return ChatMessage(
      id: json['_id']?.toString()
          ?? json['id']?.toString()
          ?? json['messageId']?.toString()
          ?? json['clientId']?.toString()
          ?? UniqueKey().toString(),
      senderId:    senderId,
      cipherText:  rawCipherText,   // preserved for decrypt step
      contentType: rawContentType,  // preserved for decrypt step
      text:        plainText,       // empty for encrypted msgs until decrypted
      isSentByMe:  myUserId != null && senderId == myUserId,
      timestamp:   ts,
      status:      MessageStatus.sent,
      attachmentUrl:  firstAttachment,
      attachmentType: firstAttachmentType,
      uploadProgress: null,
      reaction:       null,
      replyTo:        reply,
    );
  }
}