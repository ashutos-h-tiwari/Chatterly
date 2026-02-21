import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ConnectionProfilePage extends StatefulWidget {
  final String userId;
  final String name;
  final String email;
  final String phone;
  final String bio;
  final String imageUrl;

  const ConnectionProfilePage({
    super.key,
    required this.userId,
    required this.name,
    required this.email,
    required this.phone,
    required this.bio,
    required this.imageUrl,
  });

  @override
  State<ConnectionProfilePage> createState() => _ConnectionProfilePageState();
}

class _ConnectionProfilePageState extends State<ConnectionProfilePage> {
  String? customName;

  @override
  void initState() {
    super.initState();
    _loadCustomName();
  }

  Future<void> _loadCustomName() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      customName = prefs.getString('nick_${widget.userId}');
    });
  }

  Future<void> _editName() async {
    final controller =
    TextEditingController(text: customName ?? widget.name);

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Edit Name"),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: "Enter custom name",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final newName = controller.text.trim();

                if (newName.isEmpty) return;

                final prefs = await SharedPreferences.getInstance();
                await prefs.setString(
                    'nick_${widget.userId}', newName);

                Navigator.pop(dialogContext); // 🔥 use dialogContext

                setState(() {
                  customName = newName; // 🔥 instant UI update
                });
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayName = customName ?? widget.name;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Profile"),
        backgroundColor: const Color(0xff0f766e),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 30),

            // Profile Image
            CircleAvatar(
              radius: 60,
              backgroundImage: NetworkImage(widget.imageUrl),
            ),

            const SizedBox(height: 20),

            // Name + Edit Icon
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _editName,
                  child: const Icon(Icons.edit,
                      size: 20, color: Colors.grey),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Original Name (optional small text)
            if (customName != null)
              Text(
                "Original: ${widget.name}",
                style: const TextStyle(color: Colors.grey),
              ),

            const SizedBox(height: 30),

            _infoTile(Icons.email, "Email", widget.email),
            _infoTile(Icons.phone, "Phone", widget.phone),
            _infoTile(Icons.info_outline, "Bio", widget.bio),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _infoTile(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xff0f766e)),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text(value,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}