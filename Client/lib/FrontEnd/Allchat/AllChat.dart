// ✅ AllChatsPage.dart - Rich Interactive UI
// Modern design with animations, gradient effects, and smooth interactions
// Removed bottom navigation bar
// Enhanced visual hierarchy and micro-interactions

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../ChatPage/ChatPage.dart';

class AllChatsPage extends StatefulWidget {
  const AllChatsPage({super.key});

  @override
  State<AllChatsPage> createState() => _AllChatsPageState();
}

class _AllChatsPageState extends State<AllChatsPage> with TickerProviderStateMixin {
  static const String kUsersUrl =
      'https://chatterly-backend-f9j0.onrender.com/api/users';

  final _search = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _isSearchFocused = false;

  List<_UserLite> _users = [];
  List<_UserLite> _filtered = [];

  late AnimationController _headerController;
  late AnimationController _fabController;

  final FocusNode _searchFocus = FocusNode();

  final List<Map<String, dynamic>> stories = const [
    {'name': 'My Story', 'image': 'assets/story1.png', 'hasNew': true},
    {'name': 'Eleanor P', 'image': 'assets/story2.png', 'hasNew': true},
    {'name': 'Dianne R', 'image': 'assets/story3.png', 'hasNew': false},
    {'name': 'Duy H', 'image': 'assets/story4.png', 'hasNew': true},
  ];

  @override
  void initState() {
    super.initState();
    _fetchUsers();
    _search.addListener(_onSearchChanged);
    _searchFocus.addListener(_onSearchFocusChanged);

    _headerController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..forward();

    _fabController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _headerController.dispose();
    _fabController.dispose();
    super.dispose();
  }

  void _onSearchFocusChanged() {
    setState(() {
      _isSearchFocused = _searchFocus.hasFocus;
    });
  }

  void _onSearchChanged() {
    final q = _search.text.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _users
          : _users.where((u) => u.name.toLowerCase().contains(q)).toList();
    });
  }

  Future<void> _fetchUsers() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      final res = await http.get(
        Uri.parse(kUsersUrl),
        headers: {
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final body = jsonDecode(res.body);
        List raw = [];
        if (body is List) {
          raw = body;
        } else if (body is Map && body['users'] is List) {
          raw = body['users'] as List;
        } else if (body is Map && body['data'] is List) {
          raw = body['data'] as List;
        } else {
          throw const FormatException('Unexpected users payload');
        }

        final parsed = raw.map((e) => _parseUser(e)).whereType<_UserLite>().toList();
        setState(() {
          _users = parsed;
          _filtered = parsed;
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

  _UserLite? _parseUser(dynamic e) {
    if (e is Map) {
      final id = (e['_id'] ?? e['id'])?.toString();
      final name = (e['name'] ?? e['username'] ?? e['email'])?.toString();
      if (id == null || name == null || name.trim().isEmpty) return null;
      return _UserLite(id: id, name: name.trim());
    }
    if (e is String) {
      final name = e.trim();
      if (name.isEmpty) return null;
      return _UserLite(id: name, name: name);
    }
    return null;
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xff0f766e),
              Color(0xff14b8a6),
              Color(0xff2dd4bf),
            ],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _fetchUsers,
            color: Colors.white,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // Animated Header
                SliverToBoxAdapter(
                  child: FadeTransition(
                    opacity: _headerController,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, -0.3),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: _headerController,
                        curve: Curves.easeOutCubic,
                      )),
                      child: _buildHeader(),
                    ),
                  ),
                ),

                // Search Bar
                SliverToBoxAdapter(
                  child: _buildSearchBar(),
                ),

                // Stories Section
                SliverToBoxAdapter(
                  child: _buildStories(),
                ),

                // Section Header
                SliverToBoxAdapter(
                  child: _buildSectionHeader(),
                ),

                // Chat List
                _buildChatList(),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: ScaleTransition(
        scale: Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _headerController,
            curve: const Interval(0.5, 1.0, curve: Curves.elasticOut),
          ),
        ),
        child: FloatingActionButton.extended(
          onPressed: () {},
          backgroundColor: Colors.white,
          elevation: 8,
          icon: const Icon(Icons.edit, color: Color(0xff0f766e)),
          label: const Text(
            'New Chat',
            style: TextStyle(
              color: Color(0xff0f766e),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'All Chats',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_filtered.length} conversations',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.8),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {},
                child: const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Icon(
                    Icons.settings_outlined,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: _isSearchFocused
              ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ]
              : [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TextField(
          controller: _search,
          focusNode: _searchFocus,
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(
            border: InputBorder.none,
            prefixIcon: Icon(
              Icons.search_rounded,
              color: _isSearchFocused
                  ? const Color(0xff0f766e)
                  : Colors.grey[400],
              size: 24,
            ),
            suffixIcon: _search.text.isNotEmpty
                ? IconButton(
              icon: const Icon(Icons.clear, size: 20),
              onPressed: () {
                _search.clear();
                _searchFocus.unfocus();
              },
              color: Colors.grey[400],
            )
                : null,
            hintText: "Search messages...",
            hintStyle: TextStyle(color: Colors.grey[400]),
            contentPadding: const EdgeInsets.symmetric(
              vertical: 18,
              horizontal: 8,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStories() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 24),
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: stories.length,
        itemBuilder: (context, i) {
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: Duration(milliseconds: 400 + (i * 100)),
            curve: Curves.easeOutBack,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: child,
              );
            },
            child: _StoryItem(
              name: stories[i]['name'],
              imagePath: stories[i]['image'],
              hasNew: stories[i]['hasNew'],
              isFirst: i == 0,
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            "Recent Chats",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: const [
                Icon(Icons.filter_list, color: Colors.white, size: 18),
                SizedBox(width: 4),
                Text(
                  'Filter',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatList() {
    if (_loading && _users.isEmpty) {
      return const SliverFillRemaining(
        child: Center(
          child: CircularProgressIndicator(
            color: Colors.white,
          ),
        ),
      );
    }

    if (_error != null && _users.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.white70),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_filtered.isEmpty) {
      return const SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chat_bubble_outline, size: 64, color: Colors.white70),
              SizedBox(height: 16),
              Text(
                "No conversations found",
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
              (context, i) {
            final user = _filtered[i];
            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: Duration(milliseconds: 300 + (i * 50)),
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
              child: _ChatTile(
                user: user,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatPage(
                        chatUserId: user.id,
                        chatUserName: user.name,
                      ),
                    ),
                  );
                },
              ),
            );
          },
          childCount: _filtered.length,
        ),
      ),
    );
  }
}

class _StoryItem extends StatelessWidget {
  final String name;
  final String imagePath;
  final bool hasNew;
  final bool isFirst;

  const _StoryItem({
    required this.name,
    required this.imagePath,
    required this.hasNew,
    this.isFirst = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16.0),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: hasNew
                      ? const LinearGradient(
                    colors: [Color(0xfffbbf24), Color(0xffef4444)],
                  )
                      : null,
                  border: hasNew
                      ? null
                      : Border.all(color: Colors.white, width: 2),
                ),
                padding: const EdgeInsets.all(3),
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.white,
                  backgroundImage: AssetImage(imagePath),
                ),
              ),
              if (isFirst)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xff0f766e),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: const Icon(
                      Icons.add,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 70,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatTile extends StatefulWidget {
  final _UserLite user;
  final VoidCallback onTap;

  const _ChatTile({required this.user, required this.onTap});

  @override
  State<_ChatTile> createState() => _ChatTileState();
}

class _ChatTileState extends State<_ChatTile> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: AnimatedScale(
        scale: _isPressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: widget.onTap,
              onTapDown: (_) => setState(() => _isPressed = true),
              onTapUp: (_) => setState(() => _isPressed = false),
              onTapCancel: () => setState(() => _isPressed = false),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        Hero(
                          tag: 'avatar_${widget.user.id}',
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  Color(0xff0f766e).withOpacity(0.3),
                                  Color(0xff14b8a6).withOpacity(0.3),
                                ],
                              ),
                            ),
                            padding: const EdgeInsets.all(2),
                            child: CircleAvatar(
                              radius: 28,
                              backgroundColor: Colors.white,
                              foregroundImage: NetworkImage(widget.user.avatarUrl),
                              child: Text(
                                _initials(widget.user.name),
                                style: const TextStyle(
                                  color: Color(0xff0f766e),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: const Color(0xff10b981),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.user.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xff0f172a),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Tap to start conversation',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xff64748b),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios,
                      color: Color(0xff94a3b8),
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class _UserLite {
  final String id;
  final String name;
  _UserLite({required this.id, required this.name});

  String get avatarUrl {
    final seed = name.hashCode.abs() % 70;
    return 'https://i.pravatar.cc/150?img=$seed';
  }
}