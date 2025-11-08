import 'dart:io';

import 'package:flutter/material.dart';

/// WhatsApp-like Profile viewer for the current user (read-only layout).
/// - Large header with avatar (tap to view full screen)
/// - Name row
/// - About/Status row
/// - Phone row
/// - QR entry point
/// - Edit button in AppBar (navigates to your ProfileUpdatePage)
/// - Optional counts (Media, Links, Docs)
///
/// You can supply a local avatar (File) or a network URL. If both are missing, a placeholder icon is shown.
class ProfileViewPage extends StatelessWidget {
  const ProfileViewPage({
    super.key,
    required this.name,
    required this.about,
    required this.phoneNumber,
    this.photoUrl,
    this.localPhoto,
    this.onEditProfile,
    this.onChangeNumber,
    this.onOpenQR,
    this.onOpenMedia,
  });

  final String name;
  final String about;
  final String phoneNumber; // e.g. +91 98765 43210
  final String? photoUrl; // existing avatar url
  final File? localPhoto; // if recently updated but not uploaded yet

  /// Navigate to your ProfileUpdatePage
  final VoidCallback? onEditProfile;
  /// Navigate to Change Number flow
  final VoidCallback? onChangeNumber;
  /// Navigate to QR page
  final VoidCallback? onOpenQR;
  /// Navigate to Media/Links/Docs
  final VoidCallback? onOpenMedia;

  ImageProvider? _avatarProvider() {
    if (localPhoto != null) return FileImage(localPhoto!);
    if (photoUrl != null && photoUrl!.isNotEmpty) return NetworkImage(photoUrl!);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'Edit',
            onPressed: onEditProfile,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: ListView(
        children: [
          const SizedBox(height: 16),

          // Header avatar
          Center(
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                GestureDetector(
                  onTap: () => _openPhotoViewer(context),
                  child: CircleAvatar(
                    radius: 64,
                    backgroundColor: theme.colorScheme.primary.withOpacity(.1),
                    backgroundImage: _avatarProvider(),
                    child: _avatarProvider() == null
                        ? const Icon(Icons.person, size: 72)
                        : null,
                  ),
                ),
                // Small QR affordance (WhatsApp shows QR near name, we place near avatar for simplicity)
                Material(
                  color: theme.colorScheme.primary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onOpenQR,
                    child: const Padding(
                      padding: EdgeInsets.all(10.0),
                      child: Icon(Icons.qr_code_2, color: Colors.white, size: 22),
                    ),
                  ),
                )
              ],
            ),
          ),

          const SizedBox(height: 18),

          // Name
          _SectionHeader(label: 'Name'),
          ListTile(
            title: Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            subtitle: const Text(
              'This is not your username or PIN. This name will be visible to your contacts.',
              style: TextStyle(fontSize: 12),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEditProfile,
              tooltip: 'Edit name',
            ),
          ),

          const Divider(height: 0),

          // About
          _SectionHeader(label: 'About'),
          ListTile(
            title: Text(about),
            trailing: IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEditProfile,
              tooltip: 'Edit about',
            ),
          ),

          const Divider(height: 0),

          // Phone
          _SectionHeader(label: 'Phone'),
          ListTile(
            leading: const Icon(Icons.phone_outlined),
            title: Text(phoneNumber, style: const TextStyle(fontSize: 16)),
            subtitle: const Text('Phone number'),
            trailing: TextButton(
              onPressed: onChangeNumber,
              child: const Text('Change number'),
            ),
          ),

          const Divider(height: 0),

          // // Media, Links, Docs (count row like WhatsApp profile)
          // Padding(
          //   padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
          //   child: Row(
          //     mainAxisAlignment: MainAxisAlignment.spaceBetween,
          //     children: [
          //       _StatPill(label: 'Media', onTap: onOpenMedia),
          //       _StatPill(label: 'Links', onTap: onOpenMedia),
          //       _StatPill(label: 'Docs', onTap: onOpenMedia),
          //     ],
          //   ),
          // ),

          const Divider(height: 0),

          // QR entry (alt location like WhatsApp > Profile)
          ListTile(
            leading: const Icon(Icons.qr_code_2_outlined),
            title: const Text('QR code'),
            subtitle: const Text('Share your contact via QR'),
            onTap: onOpenQR,
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _openPhotoViewer(BuildContext context) {
    final provider = _avatarProvider();
    if (provider == null) return;
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
            child: Image(image: provider),
          ),
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

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: theme.dividerColor.withOpacity(.2)),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
      ),
    );
  }
}
