// merged_threads_page.dart
import 'dart:convert';
import 'package:chatterly/FrontEnd/Allchat/AllChat.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../ChatPage/ChatPage.dart';
import '../Status page/status.dart';
import '../profile/profile.dart';
import '../profile/profileupdate.dart';
// import ''; // <-- UPDATE this import to your actual path

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

/// NOTE: This file focuses on ThreadsPage UI + logic. The HomePage here is
/// preserved from your original file to keep routing as-is.
class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sutra – Threads',
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
      ),
      home: const ThreadsPage(),
      routes: {
        '/chat': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
          final userName = args?['name'] as String? ?? 'Chat';
          final userId = args?['id'] as String? ?? '';
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

class _ThreadsPageState extends State<ThreadsPage> with TickerProviderStateMixin {
  static const String kBase = 'https://chatterly-backend-f9j0.onrender.com';
  static const String kListConversations = '$kBase/api/chat/conversations';

  String? _token;
  String? _myId;

  final List<ThreadItem> threads = [];

  bool _loading = true;
  String? _error;
  bool showPopup = false;

  late AnimationController _headerController;
  late AnimationController _fabController;

  @override
  void initState() {
    super.initState();
    _headerController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..forward();

    _fabController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _bootstrap();
  }

  @override
  void dispose() {
    _headerController.dispose();
    _fabController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('token');
      _myId = prefs.getString('userId');

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
              true,
              id: conv.otherUserId,
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

  _ConvLite? _parseConversation(dynamic json) {
    if (json is! Map) return null;

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

    if (otherId == null && json['otherUser'] is Map) {
      final ou = json['otherUser'] as Map;
      otherId = (ou['_id'] ?? ou['id'])?.toString();
      otherName = (ou['name'] ?? ou['username'] ?? ou['email'])?.toString();
    }

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
    final positive = (name.hashCode & 0x7fffffff);
    final seed = (positive % 70) + 1;
    return 'https://i.pravatar.cc/150?img=$seed';
  }

  void _onNewThread() async {
    setState(() => showPopup = false);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AllChatsPage()),
    );
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

  void _togglePopup() {
    setState(() {
      showPopup = !showPopup;
    });
    if (showPopup) {
      _fabController.forward();
    } else {
      _fabController.reverse();
    }
  }

  // ---------------------------
  // UI (glowing style) below
  // ---------------------------

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFFBFA2FF);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF120A2A),
              Color(0xFF311B6B),
              Color(0xFFBFA2FF),
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  // Header (glowing)
                  FadeTransition(
                    opacity: _headerController,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, -0.3),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: _headerController,
                        curve: Curves.easeOutCubic,
                      )),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Threads',
                                  style: TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: -1,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${threads.length} active conversations',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white.withOpacity(0.8),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                _HeaderButton(
                                  icon: Icons.group_add,
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const AllChatsPage()),
                                    );
                                  },
                                ),
                                const SizedBox(width: 12),
                                _HeaderButton(
                                  icon: Icons.person_outline,
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const ProfileUpdatePage(initialName: 'Ashutosh', initialAbout: 'ram', phoneNumber: '9555548746',)),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Quick actions (kept your existing widget but styled)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.deepPurpleAccent.withOpacity(1.0),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _QuickActionButton(
                            label: 'All',
                            icon: Icons.chat_bubble,
                            selected: true,
                            onTap: () {},
                          ),
                        ),
                        Expanded(
                          child: _QuickActionButton(
                            label: 'story',
                            icon: Icons.mark_chat_unread,
                            badge: '3',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const StoryPage(),
                                ),
                              );
                            },
                          ),
                        ),
                        Expanded(
                          child: _QuickActionButton(
                            label: 'Groups',
                            icon: Icons.groups,
                            onTap: () {},
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Threads list area
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: _buildThreadsListBody(),
                    ),
                  ),
                ],
              ),

              // Popup overlay
              if (showPopup) _buildPopupMenuOverlay(),

            ],
          ),
        ),
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  Widget _buildThreadsListBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.white70),
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.indigo), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    if (threads.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.chat_bubble_outline, size: 64, color: Colors.white70),
            const SizedBox(height: 16),
            const Text('No conversations yet', style: TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _onNewThread,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Start a new thread', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadConversations,
      color: const Color(0xff0f766e),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 100),
        itemCount: threads.length,
        itemBuilder: (context, index) {
          final thread = threads[index];
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: Duration(milliseconds: 300 + (index * 40)),
            curve: Curves.easeOut,
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 20 * (1 - value)),
                  child: child,
                ),
              );
            },
            child: _CompactThreadTile(
              thread: thread,
              onTap: () {
                Navigator.pushNamed(
                  context,
                  '/chat',
                  arguments: {
                    'name': thread.name,
                    'id': thread.id,
                    'subtitle': thread.subtitle,
                    'imageUrl': thread.imageUrl,
                    'online': thread.online,
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildPopupMenuOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: _togglePopup,
        child: Container(
          color: Colors.black.withOpacity(0.5),
          child: Center(
            child: ScaleTransition(
              scale: CurvedAnimation(parent: _fabController, curve: Curves.easeOutBack),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Create New', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xff0f766e))),
                    const SizedBox(height: 20),
                    _PopupMenuItem(icon: Icons.chat_bubble, label: 'New Thread', color: const Color(0xff0f766e), onTap: _onNewThread),
                    const SizedBox(height: 12),
                    _PopupMenuItem(icon: Icons.group, label: 'New Group', color: const Color(0xff14b8a6), onTap: _onNewGroup),
                    const SizedBox(height: 12),
                    _PopupMenuItem(icon: Icons.book, label: 'New Diary Entry', color: const Color(0xff2dd4bf), onTap: _onNewDiaryEntry),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFAB() {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _headerController, curve: const Interval(0.5, 1.0, curve: Curves.elasticOut))),
      child: FloatingActionButton(
        onPressed: _togglePopup,
        backgroundColor: Colors.white,
        elevation: 8,
        child: AnimatedRotation(
          turns: showPopup ? 0.125 : 0,
          duration: const Duration(milliseconds: 300),
          child: const Icon(Icons.add, color: Color(0xff0f766e), size: 32),
        ),
      ),
    );
  }
}

// -----------------------------
// Reused helper widgets (kept from your original file)
// -----------------------------
class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(10.0), child: Icon(icon, color: Colors.white, size: 22)),
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final String? badge;
  final VoidCallback onTap;

  const _QuickActionButton({required this.label, required this.icon, this.selected = false, this.badge, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Stack(clipBehavior: Clip.none, children: [
              Icon(icon, color: selected ? const Color(0xff0f766e) : Colors.white, size: 20),
              if (badge != null)
                Positioned(
                  right: -8,
                  top: -8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Color(0xffef4444), shape: BoxShape.circle),
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    child: Text(badge!, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  ),
                ),
            ]),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: selected ? const Color(0xff0f766e) : Colors.white, fontSize: 12, fontWeight: selected ? FontWeight.bold : FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}

class _CompactThreadTile extends StatefulWidget {
  final ThreadItem thread;
  final VoidCallback onTap;

  const _CompactThreadTile({required this.thread, required this.onTap});

  @override
  State<_CompactThreadTile> createState() => _CompactThreadTileState();
}

class _CompactThreadTileState extends State<_CompactThreadTile> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    // match glowing look: white card with subtle shadow, avatar glow if online
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Material(
          color: Colors.white.withOpacity(0.02),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: widget.onTap,
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) => setState(() => _isPressed = false),
            onTapCancel: () => setState(() => _isPressed = false),
            child: Container(
              height: 80,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                Container(
                  decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                    BoxShadow(color: widget.thread.online ? const Color(0xFFBFA2FF).withOpacity(0.9) : const Color(0xFFBFA2FF).withOpacity(0.35), blurRadius: widget.thread.online ? 16 : 6, spreadRadius: widget.thread.online ? 2 : 0)
                  ]),
                  padding: const EdgeInsets.all(2),
                  child: CircleAvatar(radius: 28, backgroundImage: NetworkImage(widget.thread.imageUrl)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(widget.thread.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 6),
                    Text(widget.thread.subtitle, style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
                Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('now', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.6))),
                  const SizedBox(height: 8),
                  Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: const Color(0xFF0f766e), shape: BoxShape.circle), child: const Text('2', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _PopupMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _PopupMenuItem({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: Colors.white, size: 18)),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w600))),
            Icon(Icons.arrow_forward_ios, size: 14, color: color),
          ]),
        ),
      ),
    );
  }
}

// -----------------------------
// Models kept as in your original file
// -----------------------------
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
  final String id;
  final String name;
  final String subtitle;
  final String imageUrl;
  final bool online;

  ThreadItem(this.name, this.subtitle, this.imageUrl, this.online, {this.id = ''});
}
