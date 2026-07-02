// lib/FrontEnd/ChatPage/controllers/message_controller.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';
import '../services/chat_api.dart';
import '../services/chat_socket.dart';
import '../services/e2e/e2e_service.dart';
import '../services/chat_api.dart';
class MessageController {
  final ChatApi api;
  final ChatSocket socket;
  final String myUserId;

  MessageController({ required this.api, required this.socket, required this.myUserId });


  Future<List<ChatMessage>> loadMessages(
      String roomId,
      String senderUserId,
      {String? before, int limit = 30}) async {
    final messages = await api.loadMessages(
        roomId, before: before, limit: limit, myUserId: myUserId);

    // Build session first (needed to decrypt)
    await E2EService.buildSession(senderUserId, api.token);

    return Future.wait(messages.map((msg) async {
      final cipher = msg.cipherText;
      final contentType = msg.contentType ?? 'signal:whisper';
      if (cipher != null && cipher.isNotEmpty && msg.senderId != myUserId) {
        try {
          final decrypted = await E2EService.decrypt(senderUserId, cipher, contentType);
          return msg.copyWith(text: decrypted);
        } catch (_) {
          return msg.copyWith(text: '[Could not decrypt]');
        }
      }
      return msg;
    }));
  }
  // Future<List<ChatMessage>> loadMessages(
  //     String roomId,
  //     String senderUserId, // ADD: need their pub key to decrypt
  //         {String? before, int limit = 30}
  //     ) async {
  //   final messages = await api.loadMessages(
  //       roomId, before: before, limit: limit, myUserId: myUserId);
  //
  //   // Fetch sender's public key once for the whole batch
  //   final senderPubKey = await api.fetchPublicKey(senderUserId);
  //
  //   return Future.wait(messages.map((msg) async {
  //     if (msg.isEncrypted == true && msg.senderId != myUserId) {
  //       try {
  //         final decrypted = await E2EService.decrypt(msg.text, senderPubKey);
  //         return msg.copyWith(text: decrypted);
  //       } catch (_) {
  //         return msg.copyWith(text: '[Could not decrypt]');
  //       }
  //     }
  //     return msg;
  //   }));
  // }

  Future<void> saveCache(String cacheKey, List<ChatMessage> messages) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(cacheKey, jsonEncode(messages.map((m) => m.toCache()).toList()));
  }

  Future<List<ChatMessage>> loadCache(String cacheKey) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(cacheKey);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String,dynamic>>();
    return list.map((m) => ChatMessage.fromCache(m)).toList();
  }

// add sendText/sendAttachment wrappers which call api and return ChatMessage
}
