// lib/FrontEnd/ChatPage/utils/files_utils.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';

/// Utility class for all file/storage operations in ChatPage.
class FileUtils {
  static final Dio _dio = Dio();

  /// Extract the last part of a path or URL (e.g., "abc.png")
  static String extractFileName(String raw) {
    try {
      final uri = Uri.tryParse(raw);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.last;
      }
    } catch (_) {}
    return raw.split('/').last;
  }

  /// Extract file extension without dot — "png"
  static String extensionOf(String name) {
    final idx = name.lastIndexOf('.');
    if (idx == -1) return '';
    return name.substring(idx + 1).toLowerCase();
  }

  /// Guess MIME type from URL or file name
  static String guessMime(String raw) {
    final mime = lookupMimeType(raw);
    return mime ?? 'application/octet-stream';
  }

  /// Return correct public folder for given mime type
  /// Examples:
  ///   image/jpeg -> /storage/emulated/0/Pictures/Sutra
  ///   audio/mpeg -> /storage/emulated/0/Music/Sutra
  ///   application/pdf -> /storage/emulated/0/Documents/Sutra
  static String publicDirForMime(String mime) {
    if (mime.startsWith('image')) {
      return '/storage/emulated/0/Pictures/Sutra';
    }
    if (mime.startsWith('audio')) {
      return '/storage/emulated/0/Music/Sutra';
    }
    if (mime.startsWith('video')) {
      return '/storage/emulated/0/Movies/Sutra';
    }
    return '/storage/emulated/0/Documents/Sutra';
  }

  /// Ensure directory exists
  static Future<bool> ensureDir(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return true;
    } catch (e) {
      debugPrint("FileUtils.ensureDir error: $e");
      return false;
    }
  }

  /// Download remote file into given path
  static Future<bool> downloadFile(String url, String savePath,
      {Function(int, int)? onProgress}) async {
    try {
      await _dio.download(
        url,
        savePath,
        onReceiveProgress: (received, total) {
          if (onProgress != null) onProgress(received, total);
        },
        options: Options(followRedirects: true, receiveTimeout: Duration.zero),
      );
      return true;
    } catch (e) {
      debugPrint("FileUtils.downloadFile error: $e");
      return false;
    }
  }

  /// Download remote URL into bytes (useful for MediaStore)
  static Future<Uint8List?> downloadToBytes(String url, {Function(int, int)? onProgress}) async {
    try {
      final response = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes, followRedirects: true, receiveTimeout: Duration.zero),
        onReceiveProgress: (received, total) {
          if (onProgress != null) onProgress(received, total);
        },
      );
      if (response.data != null) {
        return Uint8List.fromList(response.data!);
      }
      return null;
    } catch (e) {
      debugPrint("FileUtils.downloadToBytes error: $e");
      return null;
    }
  }

  /// Copy local file from src to dest
  static Future<bool> copyFile(String srcPath, String destPath) async {
    try {
      final f = File(srcPath);
      if (!await f.exists()) return false;
      await f.copy(destPath);
      return true;
    } catch (e) {
      debugPrint("FileUtils.copyFile error: $e");
      return false;
    }
  }

  /// Save to app-specific external directory (fallback if public write/MediaStore fails)
  /// Returns saved path or null.
  static Future<String?> saveToAppExternal({
    required String source,
    required String mimeType,
    required String fileName,
    Function(int, int)? onProgress,
  }) async {
    try {
      Directory? baseDir;
      try {
        baseDir = await getExternalStorageDirectory(); // Android app-specific external
      } catch (_) {
        baseDir = null;
      }
      // fallback to documents if external is not available (e.g., iOS simulator)
      if (baseDir == null) {
        baseDir = await getApplicationDocumentsDirectory();
      }

      final saveDir = Directory('${baseDir.path}/Sutra');
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }
      final savePath = '${saveDir.path}/$fileName';

      if (source.startsWith('http')) {
        final ok = await downloadFile(source, savePath, onProgress: onProgress);
        return ok ? savePath : null;
      } else {
        final copied = await copyFile(source, savePath);
        return copied ? savePath : null;
      }
    } catch (e) {
      debugPrint("FileUtils.saveToAppExternal error: $e");
      return null;
    }
  }

  /// Unified save handler (optional) - keeps older name compatibility
  static Future<String?> saveIncomingFile({
    required String source,
    required String mime,
    String? customName,
    Function(int, int)? onProgress,
  }) async {
    final fileName = customName ?? extractFileName(source.isNotEmpty ? source : "file");
    final publicDir = publicDirForMime(mime);
    final ok = await ensureDir(publicDir);
    if (!ok) {
      // fallback to app external
      return await saveToAppExternal(source: source, mimeType: mime, fileName: fileName, onProgress: onProgress);
    }

    final savePath = '$publicDir/$fileName';
    if (source.startsWith('http')) {
      final success = await downloadFile(source, savePath, onProgress: onProgress);
      return success ? savePath : null;
    }
    final success = await copyFile(source, savePath);
    return success ? savePath : null;
  }
}
