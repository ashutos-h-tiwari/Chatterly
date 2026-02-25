import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'FrontEnd/SplashScreen/SplashScreen.dart';
import 'FrontEnd/ChatPage/ChatPage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // ✅ correct
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chatterly',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: SplashScreen(),

      // 🔥 ADD THIS
      routes: {
        '/chat': (context) {
          final args =
          ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;

          return ChatPage(
            chatUserName: args['name'],
            chatUserId: args['id'],
          );
        },
      },
    );
  }
}