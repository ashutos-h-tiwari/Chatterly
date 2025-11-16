// lib/FrontEnd/ChatPage/controllers/message_controller.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';
import '../services/chat_api.dart';
import '../services/chat_socket.dart';

class MessageController {
  final ChatApi api;
  final ChatSocket socket;
  final String myUserId;

  MessageController({ required this.api, required this.socket, required this.myUserId });

  Future<List<ChatMessage>> loadMessages(String roomId, {String? before, int limit = 30}) {
    return api.loadMessages(roomId, before: before, limit: limit, myUserId: myUserId);
  }

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
