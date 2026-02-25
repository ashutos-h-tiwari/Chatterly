import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart' as dio;
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

// local imports (adjust paths if your folder structure differs)
import 'package:chatterly/FrontEnd/ChatPage/Call/call_socket.dart';
import 'services/chat_api.dart';
import 'package:chatterly/FrontEnd/ChatPage/services/chat_socket.dart';

import 'models/chat_message.dart';
import 'models/message_status.dart';
import 'models/reply_ref.dart';

import 'utils/json_utils.dart';
import 'utils/mime_utils.dart';
import 'utils/time_utils.dart';
import 'utils/media_saver.dart';
import 'utils/files_utils.dart';

import 'services/recorder_services.dart';
import 'services/audio_services.dart';

import 'widgets/message_bubble.dart';
import 'widgets/typing_dots.dart';
import 'widgets/reply_banner.dart';
import 'widgets/message_list.dart';

import 'viewer/fullscreen_viewer.dart';
import 'package:chatterly/FrontEnd/ChatPage/Call/call_screen.dart';

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

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver, TickerProviderStateMixin {
  static const String _base = 'https://chatterly-backend-f9j0.onrender.com';

  final _dio = dio.Dio();
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _composerFocus = FocusNode();

  late ChatApi _api;
  late ChatSocket _socketSvc;
  late CallSocket _callSocket; // call signalling socket

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

  bool _showEmojiPicker = false;

  late AnimationController _headerController;
  late AnimationController _inputController;

  String get _cacheKey => 'chat_cache_${_roomId ?? 'unknown'}';
  String _avatarUrl = '';

  // recorder & audio services
  final RecorderService _recorder = RecorderService();
  final AudioService _audioService = AudioService();

  bool _recorderReady = false;
  bool _isRecording = false;

  // audio playback state
  String? _playingMessageId;
  Duration _audioDuration = Duration.zero;
  Duration _audioPosition = Duration.zero;

  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _playerStateSub;

  // Call UI state
  // bool _incomingDialogVisible = false;
  bool _incomingDialogVisible = false;
  Map<String, dynamic>? _pendingOffer; // buffers SDP offer while ringing dialog is shown
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

    // init recorder/audio first (they don't block UI)
    _initRecorderAndAudio();

    // bootstrap chat (auth, load messages, connect socket)
    _bootstrap();
  }

  Future<void> _initRecorderAndAudio() async {
    try {
      // CHECK PERMISSIONS BEFORE INIT
      final status = await Permission.microphone.status;
      if (status.isGranted) {
        await _recorder.init();
        _recorderReady = _recorder.isInitialized;
      } else {
        print("⚠️ Recorder skipped: Mic permission not granted yet.");
      }
    } catch (e) {
      debugPrint('Recorder init error: $e'); // Catch the crash here
      _recorderReady = false;
    }

    // ... rest of audio service init ...
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

    try {
      _callSocket.dispose();
    } catch (_) {}

    _composer.dispose();
    _scroll.dispose();
    _composerFocus.dispose();
    _typingDebounce?.cancel();
    _typingSendStopTimer?.cancel();
    _headerController.dispose();
    _inputController.dispose();

    try {
      _recorder.dispose();
    } catch (_) {}

    try {
      _durationSub?.cancel();
    } catch (_) {}
    try {
      _positionSub?.cancel();
    } catch (_) {}
    try {
      _playerStateSub?.cancel();
    } catch (_) {}

    try {
      _audioService.dispose();
    } catch (_) {}

    super.dispose();
  }

  @override
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _roomId != null) {
      try {
        _socketSvc.rejoin(_roomId!);   // ✅ force unwrap
        _socketSvc.markAllRead(_roomId);
      } catch (_) {}
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

      // init call socket
      _callSocket = CallSocket(serverUrl: _base, token: _token!);

      // IMPORTANT: connect call socket with userId so server joins personal room
      _callSocket.connect(userId: _myUserId!);
      _registerCallSocketHandlers();

      final conv = await _api.createOrGetConversation(widget.chatUserId);
      _roomId = (conv['_id'] ?? conv['id'] ?? conv['roomId'] ?? conv['conversationId'])?.toString();
      if (_roomId == null || _roomId!.isEmpty) {
        _snack('Unable to create/find conversation');
        if (mounted) Navigator.of(context).pop();
        return;
      }
      _connectSocket();
      await _loadCached();
      await _loadMessages();

    } catch (e) {
      debugPrint('Bootstrap failed: $e');
      _snack('Setup failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
  // ================== Socket (chat) ==================
  void _connectSocket() {
    if (_socketSvc.isConnected) return; // 👈 guard

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
      debugPrint('Send failed: $e');
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
      debugPrint('Upload failed: $e');
      _snack('Upload failed');
    } finally {
      setState(() => _replyTo = null);
    }
  }

  // ================== Recording ==================
  String _generateFileName(String ext) {
    final millis = DateTime.now().millisecondsSinceEpoch;
    return 'voice_$millis.$ext';
  }

  Future<void> _startRecording() async {
    if (!_recorderReady) {
      _snack('Recorder not ready');
      return;
    }
    final ok = await _recorder.startRecording();
    if (!ok) {
      _snack('Microphone permission denied or recorder failed');
      return;
    }
    setState(() => _isRecording = true);
  }

  Future<void> _stopRecordingAndSend() async {
    if (!_recorder.isRecording) return;
    final newPath = await _recorder.stopRecordingAndMoveToAppDir();
    setState(() => _isRecording = false);
    if (newPath == null) {
      _snack('Recording failed');
      return;
    }

    final tempId = UniqueKey().toString();
    final mime = 'audio/aac';
    setState(() {
      _messages.add(ChatMessage(
        id: tempId,
        text: '🎤 Voice message',
        isSentByMe: true,
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
        uploadProgress: 0.0,
        attachmentUrl: newPath,
        attachmentType: mime,
      ));
    });
    _scrollToBottom();
    _persistCache();

    try {
      final saved = await _api.sendAttachment(
        _roomId!,
        dioClient: _dio,
        clientId: tempId,
        fileName: newPath.split('/').last,
        mime: mime,
        bytes: null,
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
      debugPrint('Voice upload failed: $e');
      _snack('Voice upload failed');
    } finally {
      setState(() => _replyTo = null);
    }
  }

  Future<void> _cancelRecording() async {
    await _recorder.cancelRecording();
    setState(() => _isRecording = false);
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
      if (_playingMessageId == m.id && _audioService.playing) {
        await _audioService.pause();
        if (mounted) setState(() {});
        return;
      }

      if (_playingMessageId != null && _playingMessageId != m.id) {
        try {
          await _audioService.stop();
        } catch (_) {}
        _playingMessageId = null;
        _audioPosition = Duration.zero;
      }

      final source = m.attachmentUrl ?? '';
      if (source.isEmpty) {
        _snack('No audio source');
        return;
      }

      await _audioService.setSource(source);
      _playingMessageId = m.id;
      await _audioService.play();

      setState(() {});
    } catch (e) {
      debugPrint('Playback error: $e');
      _snack('Cannot play audio');
    }
  }

  // ================== Save / Download attachments ==================
  Future<void> _saveAttachment(ChatMessage m) async {
    final raw = m.attachmentUrl;
    if (raw == null || raw.isEmpty) {
      _snack('No attachment to save.');
      return;
    }

    try {
      final mime = m.attachmentType ?? guessMime(_deriveFileName(raw));
      final fileName = _deriveFileName(raw);

      if (Platform.isAndroid) {
        // request permission (best-effort); MediaStore APIs used in MediaSaver might not need WRITE_EXTERNAL_STORAGE on Q+
        await Permission.storage.request();
      }

      final saved = await MediaSaver.saveIncoming(
        source: raw,
        mimeType: mime,
        suggestedFileName: fileName,
        onProgress: (received, total) {
          final pct = (total > 0) ? (received / total * 100).toStringAsFixed(0) : '';
          if (pct.isNotEmpty) _snack('Downloading $fileName — $pct%');
        },
      );

      if (saved != null) {
        _snack('Saved: $saved');
      } else {
        _snack('Save failed');
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
      if (_autoSaved.contains(id)) return;
      _autoSaved.add(id);

      final raw = m.attachmentUrl;
      if (raw == null || raw.isEmpty) return;

      final mime = m.attachmentType ?? guessMime(_deriveFileName(raw));
      final fileName = _deriveFileName(raw);
      final saved = await MediaSaver.saveIncoming(source: raw, mimeType: mime, suggestedFileName: fileName);
      if (saved != null && mounted) _snack('Attachment saved: $fileName');
    } catch (e) {
      debugPrint('Auto-save failed: $e');
    }
  }

  // ================== Helpers ==================
  String _deriveFileName(String raw) {
    try {
      final uri = Uri.parse(raw);
      final name = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
      if (name.isNotEmpty) return name;
    } catch (_) {}
    return 'file_${DateTime.now().millisecondsSinceEpoch}';
  }

  String _getPublicDirForMime(String mime) => FileUtils.publicDirForMime(mime);

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

  // ================== CALL: helpers & UI ==================

  Future<bool> _ensurePermissions({required bool video}) async {
    // 1. Request Microphone
    var micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      micStatus = await Permission.microphone.request();
    }
    if (!micStatus.isGranted) {
      _snack('Microphone permission is required.');
      return false;
    }

    // 2. Request Camera (if video call)
    if (video) {
      var camStatus = await Permission.camera.status;
      if (!camStatus.isGranted) {
        camStatus = await Permission.camera.request();
      }
      if (!camStatus.isGranted) {
        _snack('Camera permission is required.');
        return false;
      }
    }
    return true;
  }

  Future<bool> _validateCallPrereqs({required bool video}) async {
    if (_loading) {
      _snack('Still setting up chat — please wait a moment.');
      return false;
    }
    if (_token == null || _token!.isEmpty || _myUserId == null || _myUserId!.isEmpty || _roomId == null || _roomId!.isEmpty) {
      _snack('Cannot start call: missing auth or conversation info.');
      return false;
    }
    return true;
  }

  Future<void> _startVoiceCall() async {
    if (!await _validateCallPrereqs(video: false)) return;
    final ok = await _ensurePermissions(video: false);
    if (!ok) {
      _snack('Microphone permission required for voice calls.');
      return;
    }

    // Signal server
    _callSocket.emitCallInitiate(to: widget.chatUserId, conversationId: _roomId!, callType: 'voice');

    // Navigate with SHARED socket
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CallScreen(
        localUserId: _myUserId!,
        remoteUserId: widget.chatUserId,
        conversationId: _roomId!,
        socket: _callSocket, // <--- THIS IS THE CRITICAL FIX
        isCaller: true,
        video: false,
      ),
    ));
  }

  Future<void> _startVideoCall() async {
    if (!await _validateCallPrereqs(video: true)) return;
    final ok = await _ensurePermissions(video: true);
    if (!ok) {
      _snack('Camera permissions required.');
      return;
    }

    _callSocket.emitCallInitiate(to: widget.chatUserId, conversationId: _roomId!, callType: 'video');

    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CallScreen(
        localUserId: _myUserId!,
        remoteUserId: widget.chatUserId,
        conversationId: _roomId!,
        socket: _callSocket, // <--- THIS IS THE CRITICAL FIX
        isCaller: true,
        video: true,
      ),
    ));
  }

  void _registerCallSocketHandlers() {
    _callSocket.onIncomingCall.listen((payload) {
      final map = payload;
      debugPrint('CALL: incoming-call -> $map');

      // ignore if it's for other conversation
      final convId = (map['conversationId'] ?? map['roomId'] ?? map['conversation'])?.toString();
      if (convId != null && _roomId != null && convId != _roomId) {
        debugPrint('CALL: incoming-call for different conversation ($convId) — ignoring');
        return;
      }

      // if (_incomingDialogVisible) {
      //   debugPrint('CALL: incoming dialog already visible — ignoring duplicate event');
      //   return;
      // }
      if (_incomingDialogVisible) {
        final isNotifyOnly = map['notifyOnly'] == true;
        final hasOffer = map['offer'] != null;
        if (!isNotifyOnly && hasOffer) {
          debugPrint('CALL: offer updated while dialog visible — buffering');
          _pendingOffer = Map<String, dynamic>.from(map['offer'] as Map);
        } else {
          debugPrint('CALL: incoming dialog already visible — ignoring duplicate notifyOnly');
        }
        return;
      }
      final from = (map['from'] ?? map['fromUserId'] ?? map['callerId'])?.toString() ?? '';
      final fromName = (map['fromName'] ?? map['callerName'] ?? 'Caller').toString();
      final callType = (map['callType'] ?? 'voice').toString();
      final callId = (map['callId'] ?? '').toString();
      _pendingOffer = map['offer'] != null
          ? Map<String, dynamic>.from(map['offer'] as Map)
          : null;
      _showIncomingCallDialog(
        callerId: from,
        callerName: fromName,
        callType: callType,
        callId: callId.isEmpty ? null : callId,
        payload: map,
      );
    });

    _callSocket.onCallAnswered.listen((payload) {
      debugPrint('CALL: call-answered -> $payload');
      // CallScreen (caller) should listen too and progress to WebRTC established state.
    });

    _callSocket.onCallDeclined.listen((payload) {
      debugPrint('CALL: call-declined -> $payload');
      _snack('Call declined');
    });

    _callSocket.onCallEnded.listen((payload) {
      debugPrint('CALL: call-ended -> $payload');
      _snack('Call ended');
    });
  }

  // ==========================================================
  // Incoming-call popup
  // ==========================================================
  void _showIncomingCallDialog({
    required String callerId,
    required String callerName,
    required String callType,
    String? callId,
    Map<String, dynamic>? payload,
  }) {
    _incomingDialogVisible = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          title: Text('Incoming ${callType == 'video' ? 'Video' : 'Voice'} call'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$callerName is calling'),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      _incomingDialogVisible = false;
                      _acceptCall(callerId: callerId, callId: callId, callType: callType, payload: payload);
                    },
                    icon: const Icon(Icons.call),
                    label: const Text('Accept'),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      _incomingDialogVisible = false;
                      _declineCall(callerId: callerId, callId: callId);
                    },
                    icon: const Icon(Icons.call_end),
                    label: const Text('Decline'),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  void _declineCall({required String callerId, String? callId}) {
    debugPrint('CALL: decline -> to=$callerId callId=$callId');
    _callSocket.emitDecline(to: callerId, conversationId: _roomId!, reason: 'declined');
  }

  Future<void> _acceptCall({required String callerId, String? callId, required String callType, Map<String, dynamic>? payload}) async {
    final ok = await _ensurePermissions(video: callType == 'video');
    if (!ok) {
      _callSocket.emitDecline(to: callerId, conversationId: _roomId!, reason: 'permissions-denied');
      return;
    }

    // Extract offer if it arrived with the call
    // final offerSdp = payload?['offer'];
// Use buffered offer — it's the most up-to-date one received while dialog was showing
//     final offerSdp = _pendingOffer ?? payload?['offer'];
//     _pendingOffer = null; // clear after consuming
    // Unwrap offer safely — ensure we pass {sdp: "...", type: "offer"} not the raw payload
    dynamic rawOffer = _pendingOffer ?? payload?['offer'];

// If rawOffer is already the correct map shape, use it
// If it's nested (offer inside offer), unwrap
    if (rawOffer is Map && rawOffer['offer'] != null) {
      rawOffer = rawOffer['offer'];
    }

    final offerSdp = rawOffer != null
        ? Map<String, dynamic>.from(rawOffer as Map)
        : null;

    _pendingOffer = null;
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CallScreen(
        localUserId: _myUserId!,
        remoteUserId: callerId,
        conversationId: _roomId!,
        socket: _callSocket, // <--- THIS IS THE CRITICAL FIX
        isCaller: false,
        video: callType == 'video',
        initialOffer: offerSdp, // <--- Pass the offer to avoid "Waiting..." forever
      ),
    ));
  }
  // ---- Build helpers (header, messages, input) ----
  Widget _buildHeader() {
    final callEnabled = !_loading && _roomId != null && _myUserId != null;
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
                  onPressed: callEnabled ? _startVideoCall : null,
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
                  onPressed: callEnabled ? _startVoiceCall : null,
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
              : MessageList(
            messages: _messages,
            onTap: (m) {
              if (_isImageMessage(m)) {
                _openImageViewer(m);
              } else if (_isAudioMessage(m)) {
                _playOrPauseAudioForMessage(m);
              }
            },
            onSave: _saveAttachment,
            onLongPress: _onMessageLongPress,
            onPlay: _playOrPauseAudioForMessage,
            isAudioMessage: _isAudioMessage,
            maxBubbleWidth: maxBubbleWidth,
            playingMessageId: _playingMessageId,
            audioDuration: _audioDuration,
            audioPosition: _audioPosition,
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
                        color: _composerFocus.hasFocus ? const Color(0xff0f766e).withOpacity(0.3) : Colors.transparent,
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
                      color: _isRecording ? Colors.red[300] : const Color(0xff0f766e).withOpacity(0.1),
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
              children: ['👍', '❤️', '😂', '😮', '😢', '🙏']
                  .map((e) => Padding(
                padding: const EdgeInsets.all(8.0),
                child: InkWell(onTap: () => Navigator.pop(context, e), child: Text(e, style: const TextStyle(fontSize: 24))),
              ))
                  .toList(),
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
      _composerFocus.requestFocus();
      return;
    }

    final i = _messages.indexWhere((x) => x.id == m.id);
    if (i != -1) {
      setState(() => _messages[i] = _messages[i].copyWith(reaction: emoji));
      _persistCache();
    }
  }

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
}
