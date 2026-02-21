// lib/FrontEnd/ChatPage/viewers/fullscreen_image.dart
import 'dart:io';
import 'package:flutter/material.dart';

class FullScreenImagePage extends StatelessWidget {
  final String imageSource;
  final bool isNetwork;
  const FullScreenImagePage({required this.imageSource, required this.isNetwork, Key? key, required String tag}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final widget = isNetwork ? Image.network(imageSource, fit: BoxFit.contain) : Image.file(File(imageSource), fit: BoxFit.contain);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black),
      body: Center(child: InteractiveViewer(child: widget)),
    );
  }
}
