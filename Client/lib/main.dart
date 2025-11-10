import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
// import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'FrontEnd/SplashScreen/SplashScreen.dart';

void main(){
  // WidgetsFlutterBinding.ensureInitialized();
  // await dotenv.load(fileName:".env");

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chatterly',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(), // your dark theme here or customize
      home: SplashScreen(),
    );
  }
}
