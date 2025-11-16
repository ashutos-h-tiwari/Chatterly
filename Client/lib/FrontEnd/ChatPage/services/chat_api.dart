import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart' as dio;
import 'package:http_parser/http_parser.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/chat_message.dart';
import '../utils/json_utils.dart';

class ChatApi {
  ChatApi(this.token);

  final String token;

  static const String _base = 'https://chatterly-backend-f9j0.onrender.com';
  static const String _convPlural = '$_base/api/chat/conversations';

  static String _convMessages(String roomId) =>
      '$_base/api/chat/conversations/$roomId/messages';
  static String _convOne(String roomId) =>
      '$_base/api/chat/conversations/$roomId';
  static String _convSend(String roomId) =>
      '$_base/api/chat/conversations/$roomId/messages';

  Future<Map<String, dynamic>> createOrGetConversation(String participantId) async {
    final uri = Uri.parse(_convPlural);

    Future<http.Response> _post() => http.post(
      uri,
      headers: _headersJson,
      body: jsonEncode({'participantId': participantId}),
    );

    var resp = await _post();
    if (resp.statusCode == 409 || resp.statusCode == 429) {
      await Future.delayed(const Duration(milliseconds: 300));
      resp = await _post();
    }
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return _unwrap(jsonDecode(resp.body));
    }
    throw Exception('Conversation error: ${resp.statusCode} ${resp.body}');
  }

  Future<List<ChatMessage>> loadMessages(String roomId,
      {String? before, int limit = 30, String? myUserId}) async {
    final uri = Uri.parse(_convMessages(roomId)).replace(queryParameters: {
      if (before != null) 'before': before,
      'limit': '$limit',
    });

    http.Response res = await http.get(uri, headers: _headersJsonAccept);
    if (res.statusCode == 404) {
      res = await http.get(Uri.parse(_convOne(roomId)), headers: _headersJsonAccept);
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final body = jsonDecode(res.body);
      List list;
      if (body is Map && body['messages'] is List) {
        list = body['messages'] as List;
      } else if (body is Map && body['data'] is Map && body['data']['messages'] is List) {
        list = body['data']['messages'] as List;
      } else if (body is Map && body['data'] is List) {
        list = body['data'] as List;
      } else if (body is List) {
        list = body;
      } else {
        list = const [];
      }
      return list
          .map((m) => ChatMessage.fromJson(asStringKeyMap(m), myUserId: myUserId))
          .toList();
    }
    throw Exception('Load messages failed: ${res.statusCode}');
  }

  Future<ChatMessage> sendText(String roomId,
      {required String text, required String clientId, String? replyTo, String? myUserId}) async {
    final resp = await http.post(
      Uri.parse(_convSend(roomId)),
      headers: _headersJson,
      body: jsonEncode({
        'text': text,
        'clientId': clientId,
        if (replyTo != null) 'replyTo': replyTo,
      }),
    );

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final raw = jsonDecode(resp.body);
      final obj = (raw is Map && raw['data'] is Map) ? raw['data'] : raw;
      return ChatMessage.fromJson(asStringKeyMap(obj), myUserId: myUserId);
    }
    throw Exception('Send text failed: ${resp.statusCode}');
  }

  Future<ChatMessage> sendAttachment(String roomId,
      {required dio.Dio dioClient,
        required String clientId,
        required String fileName,
        required String mime,
        List<int>? bytes,
        String? filePath,
        String? replyTo,
        String? myUserId,
        void Function(int sent, int total)? onProgress}) async {
    final formMap = {
      'clientId': clientId,
      if (replyTo != null) 'replyTo': replyTo,
    };

    final media = MediaType.parse(mime);
    dio.MultipartFile mf;
    if (!kIsWeb && filePath != null) {
      mf = await dio.MultipartFile.fromFile(filePath,
          filename: fileName, contentType: media);
    } else if (bytes != null) {
      mf = dio.MultipartFile.fromBytes(bytes,
          filename: fileName, contentType: media);
    } else {
      throw Exception('No attachment data');
    }

    final form = dio.FormData.fromMap({...formMap, 'attachment': mf});
    final res = await dioClient.post(
      _convSend(roomId),
      data: form,
      options: dio.Options(
        headers: {'Authorization': 'Bearer $token'},
        contentType: 'multipart/form-data',
      ),
      onSendProgress: onProgress,
    );

    if (res.statusCode != null && res.statusCode! >= 200 && res.statusCode! < 300) {
      final raw = res.data is String ? jsonDecode(res.data) : res.data;
      final obj = (raw is Map && raw['data'] is Map) ? raw['data'] : raw;
      return ChatMessage.fromJson(asStringKeyMap(obj), myUserId: myUserId);
    }
    throw Exception('Upload failed: ${res.statusCode}');
  }

  Map<String, String> get _headersJson => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  Map<String, String> get _headersJsonAccept => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/json',
  };

  Map<String, dynamic> _unwrap(dynamic body) {
    if (body is Map) {
      if (body['conversation'] is Map) {
        return (body['conversation'] as Map).map((k, v) => MapEntry(k.toString(), v));
      }
      if (body['data'] is Map) {
        return (body['data'] as Map).map((k, v) => MapEntry(k.toString(), v));
      }
      return body.map((k, v) => MapEntry(k.toString(), v));
    }
    throw const FormatException('Unexpected conversation response');
  }
}
