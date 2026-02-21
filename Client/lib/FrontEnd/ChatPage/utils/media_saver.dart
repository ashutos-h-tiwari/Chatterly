// lib/FrontEnd/ChatPage/utils/media_saver.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'files_utils.dart'; // correct single import (file in same folder)

/// MediaSaver: tries MediaStore (via MethodChannel) first (Android Q+),
/// otherwise writes to public folders, then falls back to app-specific external dir.
class MediaSaver {
  static const MethodChannel _mediaChannel = MethodChannel('app.channel.media_save');

  /// Save bytes via Android MediaStore (returns true on success).
  static Future<bool> saveBytesToMediaStore({
    required Uint8List bytes,
    required String displayName,
    required String mimeType,
    required String relativePath, // e.g. "Pictures/Sutra"
  }) async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _mediaChannel.invokeMethod<bool>('saveMedia', {
        'bytes': bytes,
        'displayName': displayName,
        'mimeType': mimeType,
        'relativePath': relativePath,
      });
      return result == true;
    } on PlatformException catch (e) {
      debugPrint('MediaSaver.saveBytesToMediaStore PlatformException: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('MediaSaver.saveBytesToMediaStore error: $e');
      return false;
    }
  }

  /// Save incoming file (http URL or local path). Returns saved path or null.
  static Future<String?> saveIncoming({
    required String source,
    required String mimeType,
    String? suggestedFileName,
    Function(int received, int total)? onProgress,
  }) async {
    final fileName = suggestedFileName ?? FileUtils.extractFileName(source);
    final relativeFolder = mimeType.startsWith('image')
        ? 'Pictures/Sutra'
        : mimeType.startsWith('video')
        ? 'Movies/Sutra'
        : mimeType.startsWith('audio')
        ? 'Music/Sutra'
        : 'Documents/Sutra';

    try {
      // 1) Try MediaStore (Android) - needs native MethodChannel implementation
      if (Platform.isAndroid) {
        try {
          if (source.startsWith('http')) {
            final Uint8List? resp = await FileUtils.downloadToBytes(source, onProgress: onProgress);
            if (resp != null) {
              final ok = await saveBytesToMediaStore(
                bytes: resp,
                displayName: fileName,
                mimeType: mimeType,
                relativePath: relativeFolder,
              );
              if (ok) return '$relativeFolder/$fileName';
            }
          } else {
            final f = File(source);
            if (await f.exists()) {
              final bytes = await f.readAsBytes();
              final ok = await saveBytesToMediaStore(
                bytes: bytes,
                displayName: fileName,
                mimeType: mimeType,
                relativePath: relativeFolder,
              );
              if (ok) return '$relativeFolder/$fileName';
            }
          }
        } catch (e) {
          debugPrint('MediaStore attempt failed: $e');
          // fallthrough to public folder
        }
      }

      // 2) Try public folder (best-effort)
      final publicDir = FileUtils.publicDirForMime(mimeType);
      if (publicDir != null && publicDir.isNotEmpty) {
        final created = await FileUtils.ensureDir(publicDir);
        if (created) {
          final targetPath = '$publicDir/$fileName';
          if (source.startsWith('http')) {
            final success = await FileUtils.downloadFile(source, targetPath, onProgress: onProgress);
            if (success) return targetPath;
          } else {
            final copied = await FileUtils.copyFile(source, targetPath);
            if (copied) return targetPath;
          }
        }
      }

      // 3) fallback to app-specific external dir
      final fallback = await FileUtils.saveToAppExternal(
        source: source,
        mimeType: mimeType,
        fileName: fileName,
        onProgress: onProgress,
      );
      return fallback;
    } catch (e) {
      debugPrint('MediaSaver.saveIncoming overall error: $e');
      return null;
    }
  }
}
