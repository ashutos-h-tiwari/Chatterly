// lib/group_page.dart
import 'package:flutter/material.dart';

/// GroupPage UI for Sutra – Threads
/// - Gradient background matching your app
/// - Search bar
/// - List of group cards (sample data)
/// - Create group FAB -> opens dialog
/// - Tapping a group tries to open '/chat' with name & id arguments
///
/// This file is UI-only. Replace sample data / hooks with real backend calls.

class GroupPage extends StatefulWidget {
  const GroupPage({super.key});

  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage> {
  final TextEditingController _searchController = TextEditingController();
  List<GroupModel> _groups = List.generate(
    8,
        (i) => GroupModel(
      id: 'g$i',
      name: 'Study Group ${i + 1}',
      members: 3 + (i % 6),
      lastMessage: i % 2 == 0 ? 'Shared a file' : 'Let’s meet at 7pm',
      avatarUrl: 'https://i.pravatar.cc/150?img=${(i * 7) % 70 + 1}',
      unread: i % 3 == 0 ? (i + 1) : 0,
    ),
  );

  List<GroupModel> get _filteredGroups {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _groups;
    return _groups.where((g) => g.name.toLowerCase().contains(q)).toList();
  }

  Future<void> _onRefresh() async {
    // keep this pure UI — if you have backend, call it here
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) setState(() {
      // optionally shuffle for demo
      _groups = List.from(_groups)..shuffle();
    });
  }

  void _openCreateGroupDialog() {
    final nameCtrl = TextEditingController();
    final membersCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Group name')),
            const SizedBox(height: 8),
            TextField(controller: membersCtrl, decoration: const InputDecoration(labelText: 'Members count (optional)'), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final members = int.tryParse(membersCtrl.text.trim()) ?? 3;
              if (name.isNotEmpty) {
                final newGroup = GroupModel(
                  id: 'g${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  members: members,
                  lastMessage: 'Group created',
                  avatarUrl: 'https://i.pravatar.cc/150?img=${DateTime.now().millisecondsSinceEpoch % 70 + 1}',
                  unread: 0,
                );
                setState(() => _groups.insert(0, newGroup));
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF120A2A),
        Color(0xFF311B6B),
        Color(0xFFBFA2FF),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Groups', style: TextStyle(letterSpacing: -0.5)),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _openCreateGroupDialog,
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(gradient: gradient),
        child: SafeArea(
          child: Column(
            children: [
              // Search & filter row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(12)),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search, color: Colors.white70),
                            hintText: 'Search groups...',
                            hintStyle: const TextStyle(color: Colors.white54),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(12)),
                      child: IconButton(
                        icon: const Icon(Icons.settings, color: Colors.white),
                        onPressed: () {
                          // optionally navigate to group settings
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group settings (TODO)')));
                        },
                      ),
                    )
                  ],
                ),
              ),

              // List / grid toggle placeholder (keaving as list by default)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text('${_filteredGroups.length} groups', style: TextStyle(color: Colors.white.withOpacity(0.8))),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.grid_view, color: Colors.white70),
                      onPressed: () {
                        // optionally toggle layout
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Grid view coming soon')));
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 6),

              // Groups list
              Expanded(
                child: RefreshIndicator(
                  color: const Color(0xff0f766e),
                  onRefresh: _onRefresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: _filteredGroups.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, idx) {
                      final g = _filteredGroups[idx];
                      return _GroupCard(
                        group: g,
                        onTap: () {
                          // route to chat (preserves your existing '/chat' usage)
                          Navigator.pushNamed(context, '/chat', arguments: {
                            'name': g.name,
                            'id': g.id,
                            'subtitle': g.lastMessage,
                            'imageUrl': g.avatarUrl,
                            'online': false,
                          });
                        },
                        onMore: () {
                          showModalBottomSheet(
                            context: context,
                            backgroundColor: Colors.white,
                            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
                            builder: (_) => Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(leading: const Icon(Icons.person_add), title: const Text('Add members'), onTap: () => Navigator.pop(context)),
                                ListTile(leading: const Icon(Icons.exit_to_app), title: const Text('Leave group'), onTap: () => Navigator.pop(context)),
                                ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Delete group'), onTap: () => Navigator.pop(context)),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreateGroupDialog,
        backgroundColor: Colors.white,
        child: const Icon(Icons.group_add, color: Color(0xff0f766e)),
      ),
    );
  }
}

/// Simple model used by this UI — adapt to your real model
class GroupModel {
  final String id;
  final String name;
  final int members;
  final String lastMessage;
  final String avatarUrl;
  final int unread;

  GroupModel({
    required this.id,
    required this.name,
    required this.members,
    required this.lastMessage,
    required this.avatarUrl,
    this.unread = 0,
  });
}

/// Group card widget
class _GroupCard extends StatelessWidget {
  final GroupModel group;
  final VoidCallback onTap;
  final VoidCallback onMore;

  const _GroupCard({required this.group, required this.onTap, required this.onMore});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.03),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 84,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // avatar
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 10, spreadRadius: 0)],
                ),
                child: CircleAvatar(radius: 26, backgroundImage: NetworkImage(group.avatarUrl)),
              ),
              const SizedBox(width: 12),
              // details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(group.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Text(group.lastMessage, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              // right column
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${group.members} members', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (group.unread > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(color: const Color(0xFF0f766e), borderRadius: BorderRadius.circular(20)),
                          child: Text('${group.unread}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      IconButton(
                        icon: const Icon(Icons.more_vert, color: Colors.white70),
                        onPressed: onMore,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
