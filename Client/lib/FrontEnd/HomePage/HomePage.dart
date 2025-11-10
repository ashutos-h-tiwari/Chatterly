import 'dart:convert';

import 'package:chatterly/FrontEnd/Allchat/AllChat.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../ChatPage/ChatPage.dart';
import '../profile/profile.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sutra – Threads',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F1A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFB8A6FF),
          secondary: Color(0xFFB8A6FF),
          surface: Color(0xFF16162A),
          onSurface: Color(0xFFF8F8F8),
        ),
        useMaterial3: true,
      ),
      home: const ThreadsPage(),
      routes: {
        '/chat': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
          final userName = args?['name'] as String? ?? 'Chat';
          final userId   = args?['id'] as String? ?? '';
          return ChatPage(chatUserName: userName, chatUserId: userId);
        },
      },
    );
  }
}

class ThreadsPage extends StatefulWidget {
  const ThreadsPage({super.key});

  @override
  State<ThreadsPage> createState() => _ThreadsPageState();
}

class _ThreadsPageState extends State<ThreadsPage> {
  // 🔗 backend list endpoint (adjust if your route differs)
  static const String kBase = 'https://chatterly-backend-f9j0.onrender.com';
  static const String kListConversations = '$kBase/api/chat/conversations';

  // 🔒 auth
  String? _token;
  String? _myId;

  // ✅ threads for UI
  final List<ThreadItem> threads = [];

  // state
  bool _loading = true;
  String? _error;

  bool showPopup = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('token');
      _myId  = prefs.getString('userId');

      if (_token == null || _myId == null || _token!.isEmpty || _myId!.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Please login again.';
        });
        return;
      }

      await _loadConversations();
    } catch (e) {
      setState(() => _error = 'Setup failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadConversations() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await http.get(
        Uri.parse(kListConversations),
        headers: {
          'Authorization': 'Bearer $_token',
          'Accept': 'application/json',
        },
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final body = jsonDecode(res.body);

        // Accept shapes:
        // 1) [ {...}, ... ]
        // 2) { conversations: [ ... ] }
        // 3) { data: [ ... ] }
        List list = [];
        if (body is List) {
          list = body;
        } else if (body is Map && body['conversations'] is List) {
          list = body['conversations'];
        } else if (body is Map && body['data'] is List) {
          list = body['data'];
        } else {
          throw const FormatException('Unexpected conversations payload');
        }

        // Map conversations → ThreadItem
        final mapped = <ThreadItem>[];
        for (final raw in list) {
          final conv = _parseConversation(raw);
          if (conv == null) continue;

          final img = _avatarFor(conv.otherUserName);
          mapped.add(
            ThreadItem(
              conv.otherUserName,
              conv.lastText ?? 'Say hi 👋',
              img,
              true, // online: not provided → keep UI consistent
              id: conv.otherUserId, // ✅ important for ChatPage
            ),
          );
        }

        setState(() {
          threads
            ..clear()
            ..addAll(mapped);
        });
      } else {
        String msg = 'Server error: ${res.statusCode}';
        try {
          final err = jsonDecode(res.body);
          msg = err['message']?.toString() ?? msg;
        } catch (_) {}
        setState(() => _error = msg);
      }
    } catch (e) {
      setState(() => _error = 'Network error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Conversation parser → minimal info
  _ConvLite? _parseConversation(dynamic json) {
    if (json is! Map) return null;

    // room id (unused here)
    final _ = (json['_id'] ?? json['id'])?.toString();

    // find the OTHER participant (not me)
    String? otherId;
    String? otherName;

    final parts = json['participants'];
    if (parts is List) {
      for (final p in parts) {
        if (p is String) {
          if (p != _myId) otherId = p;
        } else if (p is Map) {
          final pid = (p['_id'] ?? p['id'])?.toString();
          if (pid != null && pid != _myId) {
            otherId = pid;
            otherName = (p['name'] ?? p['username'] ?? p['email'])?.toString();
          }
        }
      }
    }

    // fallback if server gives a direct 'otherUser'
    if (otherId == null && json['otherUser'] is Map) {
      final ou = json['otherUser'] as Map;
      otherId = (ou['_id'] ?? ou['id'])?.toString();
      otherName = (ou['name'] ?? ou['username'] ?? ou['email'])?.toString();
    }

    // last message preview
    String? lastText;
    final lm = json['lastMessage'];
    if (lm is Map) {
      lastText = lm['text']?.toString();
    } else if (json['lastText'] != null) {
      lastText = json['lastText'].toString();
    }

    if (otherId == null || (otherName == null || otherName.trim().isEmpty)) return null;

    return _ConvLite(
      otherUserId: otherId,
      otherUserName: otherName.trim(),
      lastText: lastText,
    );
  }

  String _avatarFor(String name) {
    // stable positive seed in 1..70
    final positive = (name.hashCode & 0x7fffffff);
    final seed = (positive % 70) + 1;
    return 'https://i.pravatar.cc/150?img=$seed';
  }

  // ---------- Popup actions (logic only; UI same) ----------
  void _onNewThread() async {
    setState(() => showPopup = false);
    // open your contacts/all-chats screen to pick a user to start a new thread
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AllChatsPage()),
    );
    // on return you can optionally refresh
    if (mounted) _loadConversations();
  }

  void _onNewGroup() {
    setState(() => showPopup = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('New Group: coming soon')),
    );
  }

  void _onNewDiaryEntry() {
    setState(() => showPopup = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('New Diary Entry: coming soon')),
    );
  }
  // ---------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white.withOpacity(0.05),
        elevation: 4,
        shadowColor: const Color(0xFFB8A6FF).withOpacity(0.4),
        title: const Text(
          'Sutra',
          style: TextStyle(
            color: Color(0xFFB8A6FF),
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline, color: Color(0xFFB8A6FF), size: 26),
            tooltip: 'Profile',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AllChatsPage()),
              );
            },
          ),
          const Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: Center(
              child: Text(
                'Threads',
                style: TextStyle(
                  color: Color(0xFFF8F8F8),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Header (kept)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFB8A6FF).withOpacity(0.3),
                      blurRadius: 12,
                    )
                  ],
                ),
              ),

              // Threads list (UI unchanged)
              Expanded(child: _buildThreadsList()),

              // Bottom nav (unchanged)
              _BottomNav(onAdd: () => setState(() => showPopup = !showPopup)),
            ],
          ),

          // Popup (unchanged visually; actions wired)
          if (showPopup)
            Positioned(
              left: 0,
              right: 0,
              bottom: 90,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(20, 20, 35, 0.95),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFB8A6FF).withOpacity(0.6),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PopupButton(label: 'New Thread', onTap: _onNewThread),
                      _PopupButton(label: 'New Group', onTap: _onNewGroup),
                      _PopupButton(label: 'New Diary Entry', onTap: _onNewDiaryEntry),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildThreadsList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
        ),
      );
    }
    if (threads.isEmpty) {
      return const Center(
        child: Text(
          'No conversations yet',
          style: TextStyle(color: Color(0xFFBFBFBF)),
        ),
      );
    }

    // 👇 UI the same; using fetched `threads`
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: threads.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final t = threads[index];
        return GestureDetector(
          onTap: () {
            Navigator.pushNamed(
              context,
              '/chat',
              arguments: {
                'name': t.name,
                'id': t.id, // ✅ pass user id to chat
                'subtitle': t.subtitle,
                'imageUrl': t.imageUrl,
                'online': t.online,
              },
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: t.online
                            ? const Color(0xFFB8A6FF)
                            : const Color(0xFFB8A6FF).withOpacity(0.6),
                        blurRadius: t.online ? 14 : 6,
                      ),
                    ],
                    image: DecorationImage(
                      image: NetworkImage(t.imageUrl),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.name,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t.subtitle,
                        style: TextStyle(
                          color: const Color(0xFFBFBFBF).withOpacity(0.9),
                          fontSize: 13.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        border: const Border(top: BorderSide(color: Color.fromRGBO(255, 255, 255, 0.1))),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB8A6FF).withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: const [
          _NavButton(label: 'Threads', onTap: _noop),
          _NavButton(label: 'Moments', onTap: _noop),
          _AddButton(),
          _NavButton(label: 'Diary', onTap: _noop),
          _NavButton(label: 'Calls', onTap: _noop),
        ],
      ),
    );
  }

  static void _noop() {}
}

class _AddButton extends StatelessWidget {
  const _AddButton({super.key});

  @override
  Widget build(BuildContext context) {
    final parent = context.findAncestorWidgetOfExactType<_BottomNav>()!;
    return SizedBox(
      width: 50,
      height: 50,
      child: ElevatedButton(
        onPressed: parent.onAdd,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFB8A6FF),
          shape: const CircleBorder(),
          elevation: 8,
        ),
        child: const Text(
          '+',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: Color(0xFF0F0F1A)),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.label, required this.onTap, super.key});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFFF8F8F8))),
    );
  }
}

class _PopupButton extends StatelessWidget {
  const _PopupButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFFF8F8F8),
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.centerLeft,
      ),
      child: Text(label, style: const TextStyle(fontSize: 14)),
    );
  }
}

// --- models (no UI impact) ---

class _ConvLite {
  final String otherUserId;
  final String otherUserName;
  final String? lastText;

  _ConvLite({
    required this.otherUserId,
    required this.otherUserName,
    this.lastText,
  });
}

class ThreadItem {
  // added `id` (the other user's id) for navigation. UI reads only name/subtitle/image/online.
  final String id;
  final String name;
  final String subtitle;
  final String imageUrl;
  final bool online;

  ThreadItem(this.name, this.subtitle, this.imageUrl, this.online, {this.id = ''});
}
