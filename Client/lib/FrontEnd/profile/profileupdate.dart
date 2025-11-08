import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// A WhatsApp-like profile update page for a chat app.
/// Features:
/// - Change profile photo (Camera / Gallery / Remove / View)
/// - Edit Name (with validation & char counter)
/// - Edit About/Status (choose from presets or custom)
/// - Show phone number (read-only) + Change Number CTA (navigates)
/// - View QR (optional) CTA placeholder
/// - Save button with loading state
/// - Graceful error handling + snackbars
///
/// Integrate with your backend by updating [_updateProfile] and the upload URL.
class ProfileUpdatePage extends StatefulWidget {
  const ProfileUpdatePage({
    super.key,
    required this.initialName,
    required this.initialAbout,
    required this.phoneNumber,
    this.initialPhotoUrl,
    this.token,
    this.onChangedNumber, // Navigate to your Change Number flow
  });

  final String initialName;
  final String initialAbout;
  final String phoneNumber; // e.g. +91 98765 43210
  final String? initialPhotoUrl; // existing URL if any
  final String? token; // bearer token for auth
  final VoidCallback? onChangedNumber;

  @override
  State<ProfileUpdatePage> createState() => _ProfileUpdatePageState();
}

class _ProfileUpdatePageState extends State<ProfileUpdatePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _aboutCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  bool _isSaving = false;
  File? _localPhoto; // newly picked image (takes precedence over url)
  String? _photoUrl; // existing photo url

  static const int _nameMaxLen = 25; // WhatsApp-like limit

  // WhatsApp-like About presets
  static const List<String> _aboutPresets = [
    'Available',
    'Busy',
    'At school',
    'At the movies',
    'At work',
    'Battery about to die',
    "Can't talk, WhatsApp only",
    'In a meeting',
    'At the gym',
    'Sleeping',
    'Urgent calls only',
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.initialName;
    _aboutCtrl.text = widget.initialAbout;
    _photoUrl = widget.initialPhotoUrl;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _aboutCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 90);
    if (picked != null) {
      setState(() => _localPhoto = File(picked.path));
    }
  }

  void _removePhoto() {
    setState(() {
      _localPhoto = null;
      _photoUrl = null;
    });
  }

  void _openPhotoViewer() {
    if (_localPhoto == null && (_photoUrl == null || _photoUrl!.isEmpty)) return;
    final imageProvider = _localPhoto != null
        ? FileImage(_localPhoto!) as ImageProvider
        : NetworkImage(_photoUrl!);
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: InteractiveViewer(
            clipBehavior: Clip.none,
            child: Image(image: imageProvider),
          ),
        ),
      ),
    );
  }

  void _openPhotoSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () async {
                Navigator.pop(context);
                await _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('Choose from gallery'),
              onTap: () async {
                Navigator.pop(context);
                await _pickPhoto(ImageSource.gallery);
              },
            ),
            if (_localPhoto != null || (_photoUrl != null && _photoUrl!.isNotEmpty))
              ListTile(
                leading: const Icon(Icons.remove_circle_outline),
                title: const Text('Remove photo'),
                onTap: () {
                  Navigator.pop(context);
                  _removePhoto();
                },
              ),
            if (_localPhoto != null || (_photoUrl != null && _photoUrl!.isNotEmpty))
              ListTile(
                leading: const Icon(Icons.fullscreen),
                title: const Text('View photo'),
                onTap: () {
                  Navigator.pop(context);
                  _openPhotoViewer();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectAboutPreset() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: _aboutPresets.length,
          separatorBuilder: (_, __) => const Divider(height: 0),
          itemBuilder: (context, i) {
            final text = _aboutPresets[i];
            return ListTile(
              title: Text(text),
              trailing: _aboutCtrl.text == text
                  ? const Icon(Icons.check, size: 20)
                  : null,
              onTap: () => Navigator.pop(context, text),
            );
          },
        ),
      ),
    );
    if (result != null) {
      setState(() => _aboutCtrl.text = result);
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      // Example: Multipart PATCH to your API
      // Adjust baseUrl & headers for your backend.
      final uri = Uri.parse('https://your-api.example.com/api/user/profile');

      final req = http.MultipartRequest('PATCH', uri);
      if (widget.token != null) {
        req.headers['Authorization'] = 'Bearer ${widget.token}';
      }
      req.fields['name'] = _nameCtrl.text.trim();
      req.fields['about'] = _aboutCtrl.text.trim();

      if (_localPhoto != null) {
        final filename = 'avatar_${DateTime.now().millisecondsSinceEpoch}${p.extension(_localPhoto!.path)}';
        req.files.add(await http.MultipartFile.fromPath('avatar', _localPhoto!.path, filename: filename));
      } else if (_photoUrl == null) {
        // Signal removal if needed by backend
        req.fields['removeAvatar'] = 'true';
      }

      final streamed = await req.send();
      final res = await http.Response.fromStream(streamed);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated')),
        );
        Navigator.pop(context, true); // return true to indicate success
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed (${res.statusCode})')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'Save',
            onPressed: _isSaving ? null : _updateProfile,
            icon: _isSaving
                ? const SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          children: [
            const SizedBox(height: 12),

            // Header avatar
            Center(
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  GestureDetector(
                    onTap: _openPhotoViewer,
                    child: CircleAvatar(
                      radius: 52,
                      backgroundColor: theme.colorScheme.primary.withOpacity(.1),
                      backgroundImage: _localPhoto != null
                          ? FileImage(_localPhoto!)
                          : (_photoUrl != null && _photoUrl!.isNotEmpty)
                          ? NetworkImage(_photoUrl!)
                          : null,
                      child: (_localPhoto == null && (_photoUrl == null || _photoUrl!.isEmpty))
                          ? const Icon(Icons.person, size: 56)
                          : null,
                    ),
                  ),
                  Material(
                    color: theme.colorScheme.primary,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _openPhotoSheet,
                      child: const Padding(
                        padding: EdgeInsets.all(10.0),
                        child: Icon(Icons.photo_camera, color: Colors.white, size: 22),
                      ),
                    ),
                  )
                ],
              ),
            ),

            const SizedBox(height: 18),

            // Name
            _SectionHeader(label: 'Name'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: TextFormField(
                controller: _nameCtrl,
                maxLength: _nameMaxLen,
                decoration: const InputDecoration(
                  hintText: 'Enter your name',
                  counterText: '',
                ),
                validator: (v) {
                  final val = v?.trim() ?? '';
                  if (val.isEmpty) return 'Name cannot be empty';
                  if (val.length > _nameMaxLen) return 'Max $_nameMaxLen characters';
                  return null;
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
              child: Text(
                'This is not your username or PIN. This name will be visible to your WhatsApp contacts.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),

            const Divider(height: 0),

            // About/Status
            _SectionHeader(label: 'About'),
            ListTile(
              title: TextFormField(
                controller: _aboutCtrl,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Say something about yourself',
                ),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: _selectAboutPreset,
                tooltip: 'Choose a preset',
              ),
            ),

            const Divider(height: 0),

            // Phone
            _SectionHeader(label: 'Phone'),
            ListTile(
              leading: const Icon(Icons.phone_outlined),
              title: Text(widget.phoneNumber, style: const TextStyle(fontSize: 16)),
              subtitle: const Text('Phone number'),
              trailing: TextButton(
                onPressed: widget.onChangedNumber,
                child: const Text('Change number'),
              ),
            ),

            const Divider(height: 0),

            // QR & more (placeholders to mirror WhatsApp affordances)
            ListTile(
              leading: const Icon(Icons.qr_code_2_outlined),
              title: const Text('QR code'),
              subtitle: const Text('Share your contact via QR'),
              onTap: () {
                // Navigate to your QR screen (e.g., using qr_flutter package)
              },
            ),

            const SizedBox(height: 24),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _updateProfile,
                icon: _isSaving
                    ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: const Text('Save'),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.teal.shade700,
          letterSpacing: .6,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
