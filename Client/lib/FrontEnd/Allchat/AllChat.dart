// ✅ AllChatsPage.dart
// - Fetches users from backend with Bearer token
// - Displays random avatars (no CORS issues)
// - Fully scrollable layout (no overflow)
// - Real-time search
// - On tap → opens ChatPage with that user's id & name

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../ChatPage/ChatPage.dart'; // ← adjust import path

const double kBottomBarHeight = 72.0;

class AllChatsPage extends StatefulWidget {
  const AllChatsPage({super.key});

  @override
  State<AllChatsPage> createState() => _AllChatsPageState();
}

class _AllChatsPageState extends State<AllChatsPage> {
  static const String kUsersUrl =
      'https://chatterly-backend-f9j0.onrender.com/api/users';

  final _search = TextEditingController();
  bool _loading = false;
  String? _error;

  List<_UserLite> _users = [];
  List<_UserLite> _filtered = [];

  final List<Map<String, dynamic>> stories = const [
    {'name': 'My Story', 'image': 'assets/story1.png'},
    {'name': 'Eleanor P', 'image': 'assets/story2.png'},
    {'name': 'Dianne R', 'image': 'assets/story3.png'},
    {'name': 'Duy H', 'image': 'assets/story4.png'},
  ];

  @override
  void initState() {
    super.initState();
    _fetchUsers();
    _search.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
      return _UserLite(id: name, name: name); // fallback (unlikely)
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
    const greenDark = Color(0xff197d6e);
    const green = Color(0xff36a38d);

    return Scaffold(
      backgroundColor: const Color(0xffe6f3ee),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _fetchUsers,
          child: Padding(
            padding: const EdgeInsets.only(bottom: kBottomBarHeight + 12),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text('Sutra',
                            style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: greenDark)),
                        Icon(Icons.menu, size: 32, color: greenDark),
                      ],
                    ),
                  ),

                  // Search
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xff69b29d).withOpacity(0.18),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: TextField(
                        controller: _search,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          prefixIcon: Icon(Icons.search, color: green),
                          hintText: "Search chat or contact",
                          contentPadding: EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ),

                  // Stories
                  SizedBox(
                    height: 88,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                      itemCount: stories.length,
                      itemBuilder: (context, i) => Column(
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: const Color(0xffc1f2e2),
                            backgroundImage: AssetImage(stories[i]['image']),
                            child: stories[i]['name'] == 'My Story'
                                ? Align(
                              alignment: Alignment.bottomRight,
                              child: CircleAvatar(
                                radius: 10,
                                backgroundColor: Colors.white,
                                child: const Icon(Icons.add, size: 16, color: green),
                              ),
                            )
                                : null,
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            width: 70,
                            child: Text(
                              stories[i]['name'],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 11, color: green),
                            ),
                          ),
                        ],
                      ),
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                    ),
                  ),

                  // Section title
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text("All Chats",
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: greenDark)),
                        Icon(Icons.filter_alt_outlined, color: greenDark),
                      ],
                    ),
                  ),

                  // Users
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: _loading && _users.isEmpty
                        ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: CircularProgressIndicator(),
                      ),
                    )
                        : _error != null && _users.isEmpty
                        ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    )
                        : _filtered.isEmpty
                        ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: Text("No users found")),
                    )
                        : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) =>
                      const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final user = _filtered[i];
                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              radius: 22,
                              backgroundColor:
                              const Color(0xffc1f2e2),
                              foregroundImage:
                              NetworkImage(user.avatarUrl),
                              child: Text(
                                _initials(user.name),
                                style: const TextStyle(
                                  color: greenDark,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            title: Text(
                              user.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: greenDark,
                              ),
                            ),
                            subtitle: const Text(
                              'Tap to open chat',
                              style: TextStyle(
                                  color: Colors.black54),
                            ),
                            trailing: const Icon(
                              Icons.chevron_right,
                              color: greenDark,
                            ),
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
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),

      // Bottom nav
      bottomNavigationBar: Container(
        height: kBottomBarHeight,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        decoration: const BoxDecoration(
          color: Color(0xffffffff),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black12)],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: const [
            _NavItem(icon: Icons.chat_bubble, label: "Chats", selected: true),
            _CenterFAB(),
            _NavItem(icon: Icons.call, label: "Calls"),
          ],
        ),
      ),
    );
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

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  const _NavItem({required this.icon, required this.label, this.selected = false});
  @override
  Widget build(BuildContext context) {
    const green = Color(0xff36a38d);
    const greenDark = Color(0xff197d6e);
    final color = selected ? green : greenDark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color),
        Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

class _CenterFAB extends StatelessWidget {
  const _CenterFAB();
  @override
  Widget build(BuildContext context) {
    const green = Color(0xff36a38d);
    return SizedBox(
      height: 48,
      width: 48,
      child: FloatingActionButton(
        onPressed: () {},
        backgroundColor: green,
        elevation: 1,
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }
}
