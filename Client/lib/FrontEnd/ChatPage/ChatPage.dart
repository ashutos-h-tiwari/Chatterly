// lib/FrontEnd/ChatPage/ChatPage.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart' as dio;
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:just_audio/just_audio.dart' as ja;

import 'models/chat_message.dart';
import 'models/message_status.dart';
import 'models/reply_ref.dart';
import 'services/chat_api.dart';
import 'services/chat_socket.dart';
import 'utils/json_utils.dart';
import 'utils/mime_utils.dart';
import 'utils/time_utils.dart';
import 'widgets/message_bubble.dart';
import 'widgets/typing_dots.dart';
import 'widgets/reply_banner.dart';

class ChatPage extends StatefulWidget {
  final String chatUserId;
  final String chatUserName;

  const ChatPage({
    super.key,
    required this.chatUserId,
    required this.chatUserName,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

// NOTE: added TickerProviderStateMixin for animations
class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver, TickerProviderStateMixin {
  static const String _base = 'https://chatterly-backend-f9j0.onrender.com';

  final _dio = dio.Dio();
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _composerFocus = FocusNode();

  late ChatApi _api;
  late ChatSocket _socketSvc;

  String? _token;
  String? _myUserId;
  String? _roomId;

  bool _loading = true;
  final List<ChatMessage> _messages = <ChatMessage>[];

  // receipts de-dupe
  final Set<String> _receiptSent = <String>{};

  // To avoid saving same incoming attachment multiple times
  final Set<String> _autoSaved = <String>{};

  // typing UI
  bool _peerTyping = false;
  Timer? _typingDebounce;
  Timer? _typingSendStopTimer;

  // pagination
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _olderCursor;

  // reply
  ChatMessage? _replyTo;

  // emoji picker toggle (kept but not implemented visual picker)
  bool _showEmojiPicker = false;

  // animation controllers used by header & input area
  late AnimationController _headerController;
  late AnimationController _inputController;

  // cache key
  String get _cacheKey => 'chat_cache_${_roomId ?? 'unknown'}';

  String _avatarUrl = '';

  // --- Recording & playback
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _recorderInitialized = false;
  bool _isRecording = false;
  String? _currentRecordingTempPath; // temp path produced by recorder
  final ja.AudioPlayer _audioPlayer = ja.AudioPlayer();
  String? _playingMessageId;

  // Playback streams
  Duration _audioDuration = Duration.zero;
  Duration _audioPosition = Duration.zero;

  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<ja.PlayerState>? _playerStateSub; // <-- use just_audio PlayerState via alias 'ja'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _composer.addListener(_onComposerChanged);
    _scroll.addListener(_onScroll);
    _composerFocus.addListener(_onFocusChanged);

    _headerController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..forward();

    _inputController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    )..forward();

    _avatarUrl = _getAvatarUrl(widget.chatUserName);
    _initRecorder();
    _setupAudioListeners();
    _bootstrap();
  }

  Future<void> _initRecorder() async {
    try {
      await _recorder.openRecorder();
      _recorderInitialized = true;
    } catch (e) {
      debugPrint('Recorder init failed: $e');
      _recorderInitialized = false;
    }
    setState(() {});
  }

  void _setupAudioListeners() {
    // listen to duration changes
    _durationSub = _audioPlayer.durationStream.listen((d) {
      if (mounted) setState(() => _audioDuration = d ?? Duration.zero);
    });

    // listen to position updates
    _positionSub = _audioPlayer.positionStream.listen((p) {
      if (mounted) setState(() => _audioPosition = p);
    });

    // listen to completion / state changes (use ja.PlayerState and ja.ProcessingState)
    _playerStateSub = _audioPlayer.playerStateStream.listen((ja.PlayerState state) {
      if (state.processingState == ja.ProcessingState.completed) {
        _playingMessageId = null;
        _audioPosition = Duration.zero;
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _composer.removeListener(_onComposerChanged);
    _scroll.removeListener(_onScroll);
    _composerFocus.removeListener(_onFocusChanged);

    try {
      _socketSvc.emitTypingStop(_roomId);
      _socketSvc.leave(_roomId);
      _socketSvc.dispose();
    } catch (_) {}

    _composer.dispose();
    _scroll.dispose();
    _composerFocus.dispose();
    _typingDebounce?.cancel();
    _typingSendStopTimer?.cancel();
    _headerController.dispose();
    _inputController.dispose();
    try {
      _recorder.closeRecorder();
    } catch (_) {}

    // cancel audio stream subs
    try { _durationSub?.cancel(); } catch (_) {}
    try { _positionSub?.cancel(); } catch (_) {}
    try { _playerStateSub?.cancel(); } catch (_) {}

    _audioPlayer.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _roomId != null) {
      _socketSvc.markAllRead(_roomId);
    }
  }

  void _onFocusChanged() {
    setState(() {});
  }

  String _getAvatarUrl(String name) {
    final positive = (name.hashCode & 0x7fffffff);
    final seed = (positive % 70) + 1;
    return 'https://i.pravatar.cc/150?img=$seed';
  }

  // ================== Bootstrap ==================
  Future<void> _bootstrap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('token');
      _myUserId = prefs.getString('userId');

      if ((_token == null || _token!.isEmpty) || (_myUserId == null || _myUserId!.isEmpty)) {
        _snack('Please login again.');
        if (mounted) Navigator.of(context).pop();
        return;
      }
      if (widget.chatUserId.isEmpty) {
        _snack('Cannot open chat: participantId missing');
        if (mounted) Navigator.of(context).pop();
        return;
      }

      _api = ChatApi(_token!);
      _socketSvc = ChatSocket(baseUrl: _base, token: _token!);

      final conv = await _api.createOrGetConversation(widget.chatUserId);
      _roomId = (conv['_id'] ?? conv['id'] ?? conv['roomId'] ?? conv['conversationId'])?.toString();
      if (_roomId == null || _roomId!.isEmpty) {
        _snack('Unable to create/find conversation');
        if (mounted) Navigator.of(context).pop();
        return;
      }

      await _loadCached();

      await _loadMessages();
      _connectSocket();
    } catch (e) {
      _snack('Setup failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadCached() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      final msgs = list.map((m) => ChatMessage.fromCache(m)).toList();
      if (!mounted) return;
      setState(() {
        _messages..clear()..addAll(msgs);
      });
    } catch (_) {}
  }

  Future<void> _persistCache() async {
    final prefs = await SharedPreferences.getInstance();
    final enc = jsonEncode(_messages.map((m) => m.toCache()).toList());
    await prefs.setString(_cacheKey, enc);
  }

  Future<void> _loadMessages({String? before}) async {
    if (_roomId == null) return;
    if (_loadingMore) return;
    final msgs = await _api.loadMessages(_roomId!, before: before, limit: 30, myUserId: _myUserId);
    setState(() {
      if (before == null) {
        _messages..clear()..addAll(msgs);
      } else {
        _messages.insertAll(0, msgs);
      }
      _hasMore = msgs.isNotEmpty;
      _olderCursor = _messages.isNotEmpty ? _messages.first.id : null;
    });
    _persistCache();
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore || _roomId == null || _messages.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      await _loadMessages(before: _olderCursor);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 100) {
      _loadMore();
    }
  }

  // ================== Socket ==================
  void _connectSocket() {
    _socketSvc.connect(
      roomId: _roomId,
      onIncoming: (data) {
        final map = asStringKeyMap(data);
        final incoming = ChatMessage.fromJson(map, myUserId: _myUserId);
        final incomingId = incoming.id;

        if (!incoming.isSentByMe && incomingId.isNotEmpty) {
          if (!_receiptSent.contains(incomingId)) {
            _receiptSent.add(incomingId);
            _socketSvc.emitDeliveredRead(_roomId, incomingId);
          }
        }

        final existingIdx = _messages.indexWhere((m) => m.id == incomingId);
        if (existingIdx != -1) {
          if (!mounted) return;
          setState(() => _messages[existingIdx] = incoming);
          _persistCache();
          return;
        }

        final clientId = map['clientId']?.toString();
        if (clientId != null) {
          final pendIdx = _messages.indexWhere((m) => m.id == clientId);
          if (pendIdx != -1) {
            final serverLocal = incoming.timestamp;
            final pendingLocal = _messages[pendIdx].timestamp;
            final fixedTs = resolveSendTimestamp(serverLocal, pendingLocal);
            final updated = _messages[pendIdx].copyWith(
              id: incoming.id,
              status: MessageStatus.sent,
              timestamp: fixedTs,
            );
            if (!mounted) return;
            setState(() => _messages[pendIdx] = updated);
            _persistCache();
            return;
          }
        }

        if (!mounted) return;
        setState(() => _messages.add(incoming));
        _persistCache();

        // AUTO-SAVE incoming attachments (only for messages from peer)
        if (!incoming.isSentByMe && (incoming.attachmentUrl ?? '').isNotEmpty) {
          _autoSaveIncomingAttachment(incoming);
        }

        if (incoming.isSentByMe) _scrollToBottom();
      },
      onStatus: (data) {
        final map = asStringKeyMap(data);
        final id = map['_id']?.toString() ?? map['messageId']?.toString();
        final statusStr = map['status']?.toString();
        if (id == null || statusStr == null) return;
        final status = _parseStatus(statusStr);
        final idx = _messages.indexWhere((m) => m.id == id);
        if (idx != -1 && mounted) {
          setState(() => _messages[idx] = _messages[idx].copyWith(status: status));
          _persistCache();
        }
      },

      // ------- TYPING (filtered by room & not self) -------
      onTypingStart: (data) {
        final m = (data is Map) ? data : {};
        final cid = (m['conversationId'] ?? m['roomId'] ?? m['cid'])?.toString();
        if (_roomId != null && cid != null && cid != _roomId) return;

        final senderRaw = m['user'] ?? m['sender'] ?? m['from'] ?? m['userId'];
        String? senderId;
        if (senderRaw is Map) {
          senderId = (senderRaw['_id'] ?? senderRaw['id'])?.toString();
        } else {
          senderId = senderRaw?.toString();
        }
        if (senderId != null && senderId == _myUserId) return; // ignore self

        if (mounted) setState(() => _peerTyping = true);
      },
      onTypingStop: (data) {
        final m = (data is Map) ? data : {};
        final cid = (m['conversationId'] ?? m['roomId'] ?? m['cid'])?.toString();
        if (_roomId != null && cid != null && cid != _roomId) return;
        if (mounted) setState(() => _peerTyping = false);
      },
    );
  }

  MessageStatus _parseStatus(String s) {
    switch (s) {
      case 'sent':
        return MessageStatus.sent;
      case 'delivered':
        return MessageStatus.delivered;
      case 'read':
        return MessageStatus.read;
      default:
        return MessageStatus.sending;
    }
  }

  // ================== Typing ==================
  void _onComposerChanged() {
    final hasText = _composer.text.trim().isNotEmpty;

    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 150), () {
      if (hasText) {
        _socketSvc.emitTypingStart(_roomId);
        _typingSendStopTimer?.cancel();
        _typingSendStopTimer = Timer(const Duration(seconds: 2), () {
          _socketSvc.emitTypingStop(_roomId);
        });
      } else {
        _socketSvc.emitTypingStop(_roomId); // immediate stop when cleared
      }
      setState(() {}); // update send/mic UI
    });
  }

  // ================== Sending ==================
  Future<void> _sendText() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _roomId == null) return;

    final tempId = UniqueKey().toString();
    final pending = ChatMessage(
      id: tempId,
      text: text,
      isSentByMe: true,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
      replyTo: _replyTo == null
          ? null
          : ReplyRef(
        id: _replyTo!.id,
        preview: _replyTo!.text.isNotEmpty ? _replyTo!.text : (_replyTo!.attachmentUrl ?? 'Attachment'),
      ),
    );

    setState(() {
      _messages.add(pending);
      _composer.clear();
      _replyTo = null;
    });
    _scrollToBottom();
    _persistCache();

    // ensure peer typing hides when you send
    _socketSvc.emitTypingStop(_roomId);

    try {
      final saved = await _api.sendText(
        _roomId!,
        text: text,
        clientId: tempId,
        replyTo: pending.replyTo?.id,
        myUserId: _myUserId,
      );

      final i = _messages.indexWhere((m) => m.id == tempId);
      if (i != -1 && mounted) {
        final fixedTs = resolveSendTimestamp(saved.timestamp, _messages[i].timestamp);
        setState(() => _messages[i] = _messages[i].copyWith(
          id: saved.id,
          status: MessageStatus.sent,
          timestamp: fixedTs,
        ));
        _persistCache();
      }
    } catch (e) {
      _snack('Send failed');
    }
  }

  Future<void> _pickAndSendAttachment() async {
    if (_roomId == null) return;

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final mime = guessMime(file.name);
    final tempId = UniqueKey().toString();

    setState(() {
      _messages.add(ChatMessage(
        id: tempId,
        text: '📎 ${file.name}',
        isSentByMe: true,
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
        uploadProgress: 0.0,
      ));
    });
    _scrollToBottom();
    _persistCache();

    try {
      final saved = await _api.sendAttachment(
        _roomId!,
        dioClient: _dio,
        clientId: tempId,
        fileName: file.name,
        mime: mime,
        bytes: file.bytes,
        filePath: file.path,
        replyTo: _replyTo?.id,
        myUserId: _myUserId,
        onProgress: (sent, total) {
          if (total > 0) {
            final p = sent / total;
            final i = _messages.indexWhere((m) => m.id == tempId);
            if (i != -1 && mounted) {
              setState(() => _messages[i] = _messages[i].copyWith(uploadProgress: p));
            }
          }
        },
      );

      final i = _messages.indexWhere((m) => m.id == tempId);
      if (i != -1 && mounted) {
        setState(() => _messages[i] = saved.copyWith(status: MessageStatus.sent, uploadProgress: 1.0));
        _persistCache();
      }
    } catch (e) {
      _snack('Upload failed');
    } finally {
      setState(() => _replyTo = null);
    }
  }

  // ================== Recording flow ==================
  Future<String> _appDocumentsPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  String _generateFileName(String ext) {
    final millis = DateTime.now().millisecondsSinceEpoch;
    return 'voice_$millis.$ext';
  }

  Future<void> _startRecording() async {
    if (!_recorderInitialized) {
      _snack('Recorder not initialized');
      return;
    }

    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      _snack('Microphone permission is required to record audio.');
      return;
    }

    try {
      final tmpDir = await getTemporaryDirectory();
      final tmpPath = '${tmpDir.path}/${_generateFileName('aac')}';
      _currentRecordingTempPath = tmpPath;

      await _recorder.startRecorder(
        toFile: tmpPath,
        codec: Codec.aacADTS,
        bitRate: 128000,
        sampleRate: 44100,
      );

      setState(() => _isRecording = true);
    } catch (e) {
      debugPrint('Start recording error: $e');
      _snack('Could not start recording');
    }
  }

  Future<void> _stopRecordingAndSend() async {
    if (!_recorderInitialized || !_isRecording) return;

    try {
      final recordedPath = await _recorder.stopRecorder();
      setState(() => _isRecording = false);

      if (recordedPath == null) return;

      // move to app documents (persistent)
      final ext = recordedPath.split('.').last;
      final newName = _generateFileName(ext);
      final appPath = await _appDocumentsPath();
      final newPath = '$appPath/$newName';
      final recordedFile = File(recordedPath);
      await recordedFile.copy(newPath);

      // create a pending ChatMessage for the voice note
      final tempId = UniqueKey().toString();
      final displayName = '🎤 Voice message';
      final mime = 'audio/aac';
      setState(() {
        _messages.add(ChatMessage(
          id: tempId,
          text: displayName,
          isSentByMe: true,
          timestamp: DateTime.now(),
          status: MessageStatus.sending,
          uploadProgress: 0.0,
          attachmentUrl: newPath, // local path while uploading
          attachmentType: mime,
        ));
      });
      _scrollToBottom();
      _persistCache();

      // Upload using existing API (sendAttachment) - prefer filePath-based upload
      try {
        final saved = await _api.sendAttachment(
          _roomId!,
          dioClient: _dio,
          clientId: tempId,
          fileName: newName,
          mime: mime,
          bytes: null, // let API use filePath
          filePath: newPath,
          replyTo: _replyTo?.id,
          myUserId: _myUserId,
          onProgress: (sent, total) {
            if (total > 0) {
              final p = sent / total;
              final i = _messages.indexWhere((m) => m.id == tempId);
              if (i != -1 && mounted) {
                setState(() => _messages[i] = _messages[i].copyWith(uploadProgress: p));
              }
            }
          },
        );

        final i = _messages.indexWhere((m) => m.id == tempId);
        if (i != -1 && mounted) {
          setState(() => _messages[i] = saved.copyWith(status: MessageStatus.sent, uploadProgress: 1.0));
          _persistCache();
        }
      } catch (e) {
        debugPrint('Voice upload error: $e');
        _snack('Voice upload failed');
        // keep local file and mark as sending/failure per your UX choice
      } finally {
        setState(() => _replyTo = null);
      }
    } catch (e) {
      debugPrint('Stop recording error: $e');
      setState(() => _isRecording = false);
      _snack('Recording failed');
    }
  }

  Future<void> _cancelRecording() async {
    try {
      if (_recorder.isRecording) {
        await _recorder.stopRecorder();
      }
    } catch (_) {}
    setState(() {
      _isRecording = false;
      _currentRecordingTempPath = null;
    });
  }

  // ================== Playback ==================
  bool _isAudioMessage(ChatMessage m) {
    final url = m.attachmentUrl ?? '';
    if (url.isEmpty) return false;
    final lower = url.toLowerCase();
    if (lower.endsWith('.aac') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.mp3') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.ogg')) {
      return true;
    }
    final at = m.attachmentType ?? '';
    if (at.startsWith('audio/')) return true;
    return false;
  }

  // NEW: detect image message
  bool _isImageMessage(ChatMessage m) {
    final url = (m.attachmentUrl ?? '').toLowerCase();
    if (url.isEmpty) return false;
    if (url.endsWith('.jpg') || url.endsWith('.jpeg') || url.endsWith('.png') || url.endsWith('.webp') || url.endsWith('.gif')) {
      return true;
    }
    final at = (m.attachmentType ?? '').toLowerCase();
    if (at.startsWith('image/')) return true;
    return false;
  }

  Future<void> _playOrPauseAudioForMessage(ChatMessage m) async {
    try {
      // if same message currently playing -> toggle pause
      if (_playingMessageId == m.id && _audioPlayer.playing) {
        await _audioPlayer.pause();
        if (mounted) setState(() {});
        return;
      }

      // if different message playing -> stop previous
      if (_playingMessageId != null && _playingMessageId != m.id) {
        try {
          await _audioPlayer.stop();
        } catch (_) {}
        _playingMessageId = null;
        _audioPosition = Duration.zero;
      }

      String source = m.attachmentUrl ?? '';

      if (source.isEmpty) {
        _snack('No audio source');
        return;
      }

      if (source.startsWith('http')) {
        await _audioPlayer.setUrl(source);
      } else {
        await _audioPlayer.setFilePath(source);
      }

      _playingMessageId = m.id;
      await _audioPlayer.play();

      // playerStateStream already listened in _setupAudioListeners, don't add duplicate listeners here.

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Playback error: $e');
      _snack('Cannot play audio');
    }
  }

  // NEW: open fullscreen image viewer
  void _openImageViewer(ChatMessage m) {
    final src = m.attachmentUrl ?? '';
    if (src.isEmpty) {
      _snack('No image to show');
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullScreenImagePage(
          tag: 'image_${m.id}',
          imageSource: src,
          isNetwork: src.startsWith('http') || src.startsWith('https'),
        ),
      ),
    );
  }

  // ================== Save / Download attachments ==================
  // Helper: derive filename from URL or path
  String _deriveFileName(String raw) {
    try {
      final uri = Uri.parse(raw);
      final name = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
      if (name.isNotEmpty) return name;
    } catch (_) {}
    return 'file_${DateTime.now().millisecondsSinceEpoch}';
  }

  // Helper: get public folder path for given mime
  String _publicFolderForMime(String mime) {
    if (mime.startsWith('image')) return '/storage/emulated/0/Pictures/Sutra';
    if (mime.startsWith('audio')) return '/storage/emulated/0/Music/Sutra';
    // documents & others
    return '/storage/emulated/0/Documents/Sutra';
  }

  Future<bool> _ensureDirExists(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return true;
    } catch (e) {
      debugPrint('Failed to create dir $path: $e');
      return false;
    }
  }

  Future<void> _saveAttachment(ChatMessage m) async {
    final raw = m.attachmentUrl;
    if (raw == null || raw.isEmpty) {
      _snack('No attachment to save.');
      return;
    }

    try {
      final mime = (m.attachmentType ?? '').isNotEmpty ? m.attachmentType! : guessMime(_deriveFileName(raw));
      final fileName = _deriveFileName(raw);
      final publicDir = Platform.isAndroid ? _publicFolderForMime(mime) : null;

      // On Android: request legacy storage permission only (best-effort)
      if (Platform.isAndroid) {
        try {
          final status = await Permission.storage.request();
          // We continue even if denied because writing to app-specific dir may still work.
          debugPrint('Storage permission status: $status');
        } catch (_) {}
      }

      if (Platform.isAndroid && publicDir != null) {
        final ok = await _ensureDirExists(publicDir);
        if (!ok) {
          _snack('Could not create folder. Saving to app documents instead.');
        } else {
          final savePath = '$publicDir/$fileName';

          // If remote -> download, else copy
          if (raw.startsWith('http') || raw.startsWith('https')) {
            ScaffoldMessenger.of(context).removeCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Downloading...')));

            await _dio.download(
              raw,
              savePath,
              onReceiveProgress: (received, total) {
                if (total > 0) {
                  final pct = (received / total * 100).toStringAsFixed(0);
                  ScaffoldMessenger.of(context).removeCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Downloading $fileName — $pct%')),
                  );
                }
              },
              options: dio.Options(followRedirects: true, receiveTimeout: Duration.zero),
            );

            ScaffoldMessenger.of(context).removeCurrentSnackBar();
            _snack('Saved to $savePath');

            return;
          } else {
            final src = File(raw);
            if (!await src.exists()) {
              _snack('Source file not found.');
              return;
            }
            await src.copy(savePath);
            _snack('Saved to $savePath');
            return;
          }
        }
      }

      // Fallback: save into app-specific external directory
      Directory? baseDir;
      if (Platform.isAndroid) {
        baseDir = await getExternalStorageDirectory();
      } else {
        baseDir = await getApplicationDocumentsDirectory();
      }

      if (baseDir == null) {
        _snack('Unable to determine storage directory.');
        return;
      }

      final saveDir = Directory('${baseDir.path}/ChatterlyDownloads');
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }

      final savePath = '${saveDir.path}/$fileName';

      if (raw.startsWith('http') || raw.startsWith('https')) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Downloading...')));

        await _dio.download(
          raw,
          savePath,
          onReceiveProgress: (received, total) {
            if (total > 0) {
              final pct = (received / total * 100).toStringAsFixed(0);
              ScaffoldMessenger.of(context).removeCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Downloading $fileName — $pct%')),
              );
            }
          },
          options: dio.Options(followRedirects: true, receiveTimeout: Duration.zero),
        );

        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        _snack('Saved to $savePath');
      } else {
        final src = File(raw);
        if (!await src.exists()) {
          _snack('Source file not found.');
          return;
        }
        await src.copy(savePath);
        _snack('Saved to $savePath');
      }
    } catch (e) {
      debugPrint('Save error: $e');
      _snack('Failed to save file.');
    }
  }

  // ================== AUTO-SAVE incoming attachments ==================
  Future<void> _autoSaveIncomingAttachment(ChatMessage m) async {
    try {
      final id = m.id;
      if (id.isEmpty) return;
      if (_autoSaved.contains(id)) return; // already saved

      final raw = m.attachmentUrl;
      if (raw == null || raw.isEmpty) return;

      _autoSaved.add(id); // mark to avoid duplicates

      final mime = (m.attachmentType ?? '').isNotEmpty ? m.attachmentType! : guessMime(_deriveFileName(raw));
      final fileName = _deriveFileName(raw);
      final publicDir = Platform.isAndroid ? _publicFolderForMime(mime) : null;

      // Try to save silently to public folder first (best-effort)
      if (Platform.isAndroid && publicDir != null) {
        final ok = await _ensureDirExists(publicDir);
        if (ok) {
          final savePath = '$publicDir/$fileName';
          if (!(raw.startsWith('http') || raw.startsWith('https'))) {
            final src = File(raw);
            if (await src.exists()) {
              await src.copy(savePath);
              debugPrint('Auto-saved local file to $savePath');
              if (mounted) _snack('Attachment saved: $fileName');
              return;
            } else {
              debugPrint('Auto-save: source not found $raw');
            }
          } else {
            try {
              await _dio.download(
                raw,
                savePath,
                options: dio.Options(followRedirects: true, receiveTimeout: Duration.zero),
                onReceiveProgress: (a, b) {},
              );
              debugPrint('Auto-saved remote file to $savePath');
              if (mounted) _snack('Attachment saved: $fileName');
              return;
            } catch (e) {
              debugPrint('Auto-save remote->public failed: $e');
              // fallthrough to app-specific save
            }
          }
        } else {
          debugPrint('Auto-save: could not create public dir $publicDir');
        }
      }

      // fallback to app-specific external
      Directory? baseDir;
      if (Platform.isAndroid) {
        baseDir = await getExternalStorageDirectory();
      } else {
        baseDir = await getApplicationDocumentsDirectory();
      }

      if (baseDir == null) {
        debugPrint('Auto-save: cannot determine base dir');
        return;
      }

      final saveDir = Directory('${baseDir.path}/ChatterlyDownloads');
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }

      final savePath = '${saveDir.path}/$fileName';

      if (!(raw.startsWith('http') || raw.startsWith('https'))) {
        final src = File(raw);
        if (await src.exists()) {
          await src.copy(savePath);
          debugPrint('Auto-saved local file to $savePath');
          if (mounted) _snack('Attachment saved: $fileName');
        } else {
          debugPrint('Auto-save: source not found $raw');
        }
        return;
      }

      await _dio.download(
        raw,
        savePath,
        options: dio.Options(followRedirects: true, receiveTimeout: Duration.zero),
        onReceiveProgress: (a, b) {},
      );

      debugPrint('Auto-saved remote file to $savePath');
      if (mounted) _snack('Attachment saved: $fileName');
    } catch (e) {
      debugPrint('Auto-save failed: $e');
    } finally {
      // keep id in set to avoid repeated attempts; if you want retry on failure remove it here
    }
  }

  // ================== UI ==================
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  // ---- Build helpers (header, messages, input) ----
  Widget _buildHeader() {
    return FadeTransition(
      opacity: _headerController,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -1),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: _headerController,
          curve: Curves.easeOutCubic,
        )),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xff0f766e).withOpacity(0.2),
                    width: 2,
                  ),
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Color(0xff0f766e)),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(width: 12),
              Hero(
                tag: 'avatar_${widget.chatUserId}',
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xff0f766e).withOpacity(0.3),
                            const Color(0xff14b8a6).withOpacity(0.3),
                          ],
                        ),
                      ),
                      padding: const EdgeInsets.all(2),
                      child: CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.white,
                        foregroundImage: NetworkImage(_avatarUrl),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: const Color(0xff10b981),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.chatUserName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xff0f172a),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _peerTyping ? 'typing...' : 'online',
                      style: TextStyle(
                        fontSize: 12,
                        color: _peerTyping ? const Color(0xff0f766e) : const Color(0xff64748b),
                        fontWeight: _peerTyping ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xff0f766e).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: const Icon(Icons.videocam, color: Color(0xff0f766e)),
                  onPressed: () {},
                  padding: const EdgeInsets.all(8),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xff0f766e).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: const Icon(Icons.call, color: Color(0xff0f766e)),
                  onPressed: () {},
                  padding: const EdgeInsets.all(8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesList(double maxBubbleWidth) {
    return Column(
      children: [
        if (_loadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xff0f766e),
              ),
            ),
          ),
        Expanded(
          child: _messages.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xff0f766e).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.chat_bubble_outline,
                    size: 48,
                    color: Color(0xff0f766e),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No messages yet',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xff64748b),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Start the conversation!',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xff94a3b8),
                  ),
                ),
              ],
            ),
          )
              : ListView.builder(
            controller: _scroll,
            reverse: true,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            itemCount: _messages.length,
            itemBuilder: (_, index) {
              final message = _messages[_messages.length - 1 - index];

              // compute playback progress for this message
              final playbackProgress = (_playingMessageId == message.id && _audioDuration.inMilliseconds > 0)
                  ? (_audioPosition.inMilliseconds / _audioDuration.inMilliseconds).clamp(0.0, 1.0)
                  : 0.0;

              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 10 * (1 - value)),
                      child: child,
                    ),
                  );
                },
                child: Align(
                  alignment:
                  message.isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      // If image -> open full-screen viewer
                      if (_isImageMessage(message)) {
                        _openImageViewer(message);
                        return;
                      }
                      // If audio -> play/pause
                      if (_isAudioMessage(message)) {
                        _playOrPauseAudioForMessage(message);
                        return;
                      }
                      // else: keep original behaviour or future actions
                    },
                    child: MessageBubble(
                      message: message,
                      maxBubbleWidth: maxBubbleWidth,
                      onLongPress: _onMessageLongPress,

                      // NEW: audio wiring props
                      isAudio: _isAudioMessage(message),
                      onPlay: () => _playOrPauseAudioForMessage(message),
                      isPlaying: _playingMessageId == message.id,
                      uploadProgress: message.uploadProgress ?? 0.0,
                      playbackProgress: playbackProgress,

                      // NEW: save/download callback
                      onSave: () => _saveAttachment(message),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (_peerTyping)
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const TypingDots(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInputArea() {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _inputController,
        curve: Curves.easeOutCubic,
      )),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyTo != null)
            ReplyBanner(
              replyTo: _replyTo!,
              onCancel: () => setState(() => _replyTo = null),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xff0f766e).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.add, color: Color(0xff0f766e)),
                    onPressed: _pickAndSendAttachment,
                    tooltip: 'Attach file',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    decoration: BoxDecoration(
                      color: const Color(0xfff0fdf4),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _composerFocus.hasFocus
                            ? const Color(0xff0f766e).withOpacity(0.3)
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: TextField(
                      controller: _composer,
                      focusNode: _composerFocus,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(
                        color: Color(0xff0f172a),
                        fontSize: 15,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 15,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        suffixIcon: _composer.text.isNotEmpty
                            ? null
                            : IconButton(
                          icon: const Icon(
                            Icons.emoji_emotions_outlined,
                            color: Color(0xff64748b),
                          ),
                          onPressed: () {
                            setState(() => _showEmojiPicker = !_showEmojiPicker);
                          },
                        ),
                      ),
                      onSubmitted: (_) => _sendText(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  child: _composer.text.trim().isEmpty
                      ? Container(
                    decoration: BoxDecoration(
                      color: _isRecording
                          ? Colors.red[300]
                          : const Color(0xff0f766e).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: GestureDetector(
                      onLongPressStart: (_) => _startRecording(),
                      onLongPressEnd: (_) => _stopRecordingAndSend(),
                      onLongPressCancel: () => _cancelRecording(),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Icon(
                          _isRecording ? Icons.mic : Icons.mic_none,
                          color: const Color(0xff0f766e),
                        ),
                      ),
                    ),
                  )
                      : Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xff0f766e), Color(0xff14b8a6)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.white),
                      onPressed: _sendText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.72;

    return Scaffold(
      backgroundColor: const Color(0xfff0fdf4),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xff0f766e).withOpacity(0.05),
              const Color(0xfff0fdf4),
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: _loading
                    ? const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xff0f766e),
                  ),
                )
                    : _buildMessagesList(maxBubbleWidth),
              ),
              _buildInputArea(),
            ],
          ),
        ),
      ),
    );
  }

  // Long-press actions (kept original emoji + reply sheet)
  void _onMessageLongPress(ChatMessage m) async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              children: ['👍','❤️','😂','😮','😢','🙏'].map((e) => Padding(
                padding: const EdgeInsets.all(8.0),
                child: InkWell(onTap: () => Navigator.pop(context, e), child: Text(e, style: const TextStyle(fontSize: 24))),
              )).toList(),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () => Navigator.pop(context, '::reply::'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted || emoji == null) return;

    if (emoji == '::reply::') {
      setState(() => _replyTo = m);
      // focus input so user knows they're replying
      _composerFocus.requestFocus();
      return;
    }

    final i = _messages.indexWhere((x) => x.id == m.id);
    if (i != -1) {
      setState(() => _messages[i] = _messages[i].copyWith(reaction: emoji));
      _persistCache();
    }
  }
}

/// Fullscreen image viewer (uses InteractiveViewer for pinch/zoom)
class FullScreenImagePage extends StatelessWidget {
  final String tag;
  final String imageSource;
  final bool isNetwork;

  const FullScreenImagePage({
    Key? key,
    required this.tag,
    required this.imageSource,
    required this.isNetwork,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;
    if (isNetwork) {
      imageWidget = Image.network(imageSource, fit: BoxFit.contain);
    } else {
      imageWidget = Image.file(File(imageSource), fit: BoxFit.contain);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
      ),
      body: Center(
        child: Hero(
          tag: tag,
          child: InteractiveViewer(
            minScale: 1.0,
            maxScale: 5.0,
            child: imageWidget,
          ),
        ),
      ),
    );
  }
}
