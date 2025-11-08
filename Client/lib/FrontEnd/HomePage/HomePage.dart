import 'package:flutter/material.dart';
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
          return ChatPage(chatUserName: userName);
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
  final List<ThreadItem> threads = [
    ThreadItem('Yash', 'Hey, how’s your day?', 'https://i.pravatar.cc/150?img=1', true),
    ThreadItem('Abhishek', 'Let’s meet tomorrow.', 'https://i.pravatar.cc/150?img=2', false),
    ThreadItem('Ashutosh', 'Just saw your message!', 'https://i.pravatar.cc/150?img=3', true),
    ThreadItem('Abhay', 'Typing...', 'https://i.pravatar.cc/150?img=4', false),
    ThreadItem('Aagman', 'Let’s start the project!', 'https://i.pravatar.cc/150?img=5', false),
  ];

  bool showPopup = false;

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
                MaterialPageRoute(
                  builder: (_) => const ProfileViewPage(
                    name: 'Ashutosh Tiwari',
                    about: 'Available',
                    phoneNumber: '+9555548746',
                    // initialPhotoUrl: 'https://i.pravatar.cc/150?img=8',
                  ),
                ),
              );
              // Navigator.push(
              //   context,
              //   MaterialPageRoute(builder: (context) => ProfileViewPage(name: '',, about: '',, phoneNumber: '',)),
              // );
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
              // Header
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
              //   child: const Center(
              //     child: Text(
              //       'Welcome back 👋',
              //       style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              //     ),
              //   ),
              ),

              // Threads list
              Expanded(child: _buildThreadsList()),

              // Bottom nav
              _BottomNav(onAdd: () => setState(() => showPopup = !showPopup)),
            ],
          ),

          // Popup menu
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
                      _PopupButton(label: 'New Thread', onTap: () => setState(() => showPopup = false)),
                      _PopupButton(label: 'New Group', onTap: () => setState(() => showPopup = false)),
                      _PopupButton(label: 'New Diary Entry', onTap: () => setState(() => showPopup = false)),
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
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: threads.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final t = threads[index];
        return GestureDetector(
          onTap: () {
            // Pass data as a Map that ChatPage can read from ModalRoute.settings.arguments
            Navigator.pushNamed(
              context,
              '/chat',
              arguments: {
                'name': t.name,
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

class ThreadItem {
  final String name;
  final String subtitle;
  final String imageUrl;
  final bool online;

  ThreadItem(this.name, this.subtitle, this.imageUrl, this.online);
}
