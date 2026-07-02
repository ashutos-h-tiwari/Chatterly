import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class FcmService {
  static const String _baseUrl = 'https://chatterly-backend-f9j0.onrender.com';

  static Future<void> init() async {
    final messaging = FirebaseMessaging.instance;

    // Request permission
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Get token and save to backend
    final token = await messaging.getToken();
    if (token != null) await _saveTokenToBackend(token);

    // Refresh token listener
    messaging.onTokenRefresh.listen((newToken) {
      _saveTokenToBackend(newToken);
    });

    // Foreground notification handler
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print("📩 Foreground notification: ${message.notification?.title}");
      // You can show a local notification here if needed
    });
  }

  static Future<void> _saveTokenToBackend(String fcmToken) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final authToken = prefs.getString('token');
      if (authToken == null) return;

      final response = await http.post(
        Uri.parse('$_baseUrl/api/notifications/fcm-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({'fcmToken': fcmToken}),
      );
      print("✅ FCM token saved: ${response.statusCode}");
    } catch (e) {
      print("❌ Failed to save FCM token: $e");
    }
  }
}