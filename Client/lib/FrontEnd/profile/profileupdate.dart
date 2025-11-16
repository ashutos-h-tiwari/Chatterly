import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Enhanced profile page with theme selection and rich animations
class ProfileUpdatePage extends StatefulWidget {
  const ProfileUpdatePage({
    super.key,
    required this.initialName,
    required this.initialAbout,
    required this.phoneNumber,
    this.initialPhotoUrl,
    this.token,
    this.onChangedNumber,
  });

  final String initialName;
  final String initialAbout;
  final String phoneNumber;
  final String? initialPhotoUrl;
  final String? token;
  final VoidCallback? onChangedNumber;

  @override
  State<ProfileUpdatePage> createState() => _ProfileUpdatePageState();
}

class _ProfileUpdatePageState extends State<ProfileUpdatePage> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _aboutCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  bool _isSaving = false;
  File? _localPhoto;
  String? _photoUrl;

  static const int _nameMaxLen = 25;

  // Theme selection
  int _selectedTheme = 0;
  final List<ProfileTheme> _themes = [
  // final List<ProfileTheme> _themes = [
    ProfileTheme(
      name: 'Ocean',
      // deep / night teal
      primaryColor: Color(0xFF063737),
      secondaryColor: Color(0xFF0B5F59),
      accentColor: Color(0xFF1A8F85),
      gradient: [Color(0xFF042D2D), Color(0xFF0B4F4B), Color(0xFF107A73)],
    ),
    ProfileTheme(
      name: 'Sunset',
      // deep / ember sunset
      primaryColor: Color(0xFF3E0B0B),
      secondaryColor: Color(0xFF7A2F04),
      accentColor: Color(0xFFA86A07),
      gradient: [Color(0xFF260505), Color(0xFF5A1F06), Color(0xFF8F4F0A)],
    ),
    ProfileTheme(
      name: 'Purple',
      // deep / indigo-purple night
      primaryColor: Color(0xFF2E0A4F),
      secondaryColor: Color(0xFF53107F),
      accentColor: Color(0xFF6F3FBF),
      gradient: [Color(0xFF1B0536), Color(0xFF3B1A62), Color(0xFF5E3AA0)],
    ),
    ProfileTheme(
      name: 'Forest',
      // deep / shadowy forest
      primaryColor: Color(0xFF082814),
      secondaryColor: Color(0xFF0F4E2B),
      accentColor: Color(0xFF2B7A4F),
      gradient: [Color(0xFF061F14), Color(0xFF0B3D24), Color(0xFF246038)],
    ),
  ];


  late AnimationController _headerController;
  late AnimationController _contentController;
  late AnimationController _avatarController;

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

    _headerController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..forward();

    _contentController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..forward();

    _avatarController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..forward();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _aboutCtrl.dispose();
    _headerController.dispose();
    _contentController.dispose();
    _avatarController.dispose();
    super.dispose();
  }

  ProfileTheme get _currentTheme => _themes[_selectedTheme];

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 90);
    if (picked != null) {
      setState(() => _localPhoto = File(picked.path));
      _avatarController.reset();
      _avatarController.forward();
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
            child: Hero(
              tag: 'profile_avatar',
              child: Image(image: imageProvider),
            ),
          ),
        ),
      ),
    );
  }

  void _openPhotoSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              _PhotoSheetOption(
                icon: Icons.photo_camera_rounded,
                label: 'Take photo',
                color: _currentTheme.primaryColor,
                onTap: () async {
                  Navigator.pop(context);
                  await _pickPhoto(ImageSource.camera);
                },
              ),
              _PhotoSheetOption(
                icon: Icons.photo_library_rounded,
                label: 'Choose from gallery',
                color: _currentTheme.secondaryColor,
                onTap: () async {
                  Navigator.pop(context);
                  await _pickPhoto(ImageSource.gallery);
                },
              ),
              if (_localPhoto != null || (_photoUrl != null && _photoUrl!.isNotEmpty))
                _PhotoSheetOption(
                  icon: Icons.delete_outline_rounded,
                  label: 'Remove photo',
                  color: Colors.red,
                  onTap: () {
                    Navigator.pop(context);
                    _removePhoto();
                  },
                ),
              if (_localPhoto != null || (_photoUrl != null && _photoUrl!.isNotEmpty))
                _PhotoSheetOption(
                  icon: Icons.fullscreen_rounded,
                  label: 'View photo',
                  color: _currentTheme.accentColor,
                  onTap: () {
                    Navigator.pop(context);
                    _openPhotoViewer();
                  },
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectAboutPreset() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(20.0),
                child: Text(
                  'Select Status',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _aboutPresets.length,
                  itemBuilder: (context, i) {
                    final text = _aboutPresets[i];
                    final isSelected = _aboutCtrl.text == text;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.pop(context, text),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? _currentTheme.primaryColor.withOpacity(0.1)
                                      : Colors.grey[100],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  _getStatusIcon(text),
                                  color: isSelected ? _currentTheme.primaryColor : Colors.grey[600],
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  text,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                    color: isSelected ? _currentTheme.primaryColor : Colors.black87,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(Icons.check_circle, color: _currentTheme.primaryColor, size: 22),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (result != null) {
      setState(() => _aboutCtrl.text = result);
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'Available':
        return Icons.check_circle;
      case 'Busy':
        return Icons.do_not_disturb;
      case 'At school':
        return Icons.school;
      case 'At the movies':
        return Icons.movie;
      case 'At work':
        return Icons.work;
      case 'Battery about to die':
        return Icons.battery_alert;
      case "Can't talk, WhatsApp only":
        return Icons.message;
      case 'In a meeting':
        return Icons.groups;
      case 'At the gym':
        return Icons.fitness_center;
      case 'Sleeping':
        return Icons.bedtime;
      case 'Urgent calls only':
        return Icons.phone_in_talk;
      default:
        return Icons.info;
    }
  }

  void _showThemeSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Choose Theme',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _themes.length,
                  itemBuilder: (context, i) {
                    final theme = _themes[i];
                    final isSelected = _selectedTheme == i;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _selectedTheme = i);
                        Navigator.pop(context);
                      },
                      child: Container(
                        width: 80,
                        margin: const EdgeInsets.only(right: 16),
                        child: Column(
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: theme.gradient,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? theme.primaryColor : Colors.transparent,
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: theme.primaryColor.withOpacity(0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              theme.name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? theme.primaryColor : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
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
        req.fields['removeAvatar'] = 'true';
      }

      final streamed = await req.send();
      final res = await http.Response.fromStream(streamed);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Profile updated successfully'),
            backgroundColor: _currentTheme.primaryColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        Navigator.pop(context, true);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update failed (${res.statusCode})'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Update failed: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _currentTheme.primaryColor,
              _currentTheme.secondaryColor.withOpacity(0.3),
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: CustomScrollView(
              slivers: [
                _buildAppBar(),
                SliverToBoxAdapter(child: _buildHeader()),
                SliverToBoxAdapter(child: _buildContent()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 0,
      floating: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: Icon(Icons.arrow_back, color: _currentTheme.primaryColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      actions: [
        Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(Icons.palette_outlined, color: _currentTheme.primaryColor),
            onPressed: _showThemeSelector,
            tooltip: 'Change theme',
          ),
        ),
        Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            tooltip: 'Save',
            onPressed: _isSaving ? null : _updateProfile,
            icon: _isSaving
                ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _currentTheme.primaryColor,
              ),
            )
                : Icon(Icons.check, color: _currentTheme.primaryColor),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return FadeTransition(
      opacity: _headerController,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.3),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: _headerController,
          curve: Curves.easeOutCubic,
        )),
        child: Column(
          children: [
            const SizedBox(height: 20),
            ScaleTransition(
              scale: CurvedAnimation(
                parent: _avatarController,
                curve: Curves.elasticOut,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: _currentTheme.gradient,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _openPhotoViewer,
                    child: Hero(
                      tag: 'profile_avatar',
                      child: Container(
                        width: 130,
                        height: 130,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black,
                          boxShadow: [
                            BoxShadow(
                              color: _currentTheme.primaryColor.withOpacity(0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 65,
                          backgroundColor: Colors.grey[100],
                          backgroundImage: _localPhoto != null
                              ? FileImage(_localPhoto!)
                              : (_photoUrl != null && _photoUrl!.isNotEmpty)
                              ? NetworkImage(_photoUrl!)
                              : null,
                          child: (_localPhoto == null && (_photoUrl == null || _photoUrl!.isEmpty))
                              ? Icon(Icons.person, size: 60, color: Colors.grey[400])
                              : null,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [_currentTheme.primaryColor, _currentTheme.secondaryColor],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _currentTheme.primaryColor.withOpacity(0.5),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _openPhotoSheet,
                          child: const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: Icon(Icons.photo_camera_rounded, color: Colors.white, size: 24),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Customize Your Profile',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Make it uniquely yours',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return FadeTransition(
      opacity: _contentController,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 24),
            _buildNameSection(),
            const SizedBox(height: 24),
            _buildAboutSection(),
            const SizedBox(height: 24),
            _buildPhoneSection(),
            const SizedBox(height: 24),
            _buildQRSection(),
            const SizedBox(height: 32),
            _buildSaveButton(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildNameSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _currentTheme.primaryColor.withOpacity(0.2),
                      _currentTheme.secondaryColor.withOpacity(0.2),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.person_outline, color: _currentTheme.primaryColor, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                'NAME',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  // color: _currentTheme.primaryColor,
                  color: Colors.black,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: TextFormField(
              controller: _nameCtrl,
              maxLength: _nameMaxLen,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'Enter your name',
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(20),
                counterStyle: TextStyle(color: _currentTheme.primaryColor),
                suffixIcon: ValueListenableBuilder(
                  valueListenable: _nameCtrl,
                  builder: (context, value, child) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 12.0),
                      child: Center(
                        child: Text(
                          '${_nameCtrl.text.length}/$_nameMaxLen',
                          style: TextStyle(
                            color: _nameCtrl.text.length > _nameMaxLen * 0.8
                                ? Colors.orange
                                : _currentTheme.primaryColor,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              validator: (v) {
                final val = v?.trim() ?? '';
                if (val.isEmpty) return 'Name cannot be empty';
                if (val.length > _nameMaxLen) return 'Max $_nameMaxLen characters';
                return null;
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This name will be visible to your contacts',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _currentTheme.secondaryColor.withOpacity(0.2),
                      _currentTheme.accentColor.withOpacity(0.2),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.info_outline, color: _currentTheme.secondaryColor, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                'ABOUT',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _currentTheme.primaryColor,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _aboutCtrl,
                    style: const TextStyle(fontSize: 16),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Say something about yourself',
                      contentPadding: EdgeInsets.all(20),
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_currentTheme.primaryColor, _currentTheme.secondaryColor],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _selectAboutPreset,
                      child: const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: Icon(Icons.edit_outlined, color: Colors.white, size: 20),
                      ),
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

  Widget _buildPhoneSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _currentTheme.primaryColor.withOpacity(0.1),
            _currentTheme.secondaryColor.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.phone_outlined, color: _currentTheme.primaryColor, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Phone number',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.phoneNumber,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.onChangedNumber != null)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_currentTheme.primaryColor, _currentTheme.secondaryColor],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: widget.onChangedNumber,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Text(
                        'Change',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQRSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _currentTheme.accentColor.withOpacity(0.15),
            _currentTheme.secondaryColor.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _currentTheme.accentColor.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            // Navigate to QR screen
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('QR code feature coming soon'),
                backgroundColor: _currentTheme.primaryColor,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.qr_code_2_rounded, color: _currentTheme.accentColor, size: 24),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'QR Code',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Share your contact via QR',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 56,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _isSaving
                ? [Colors.grey, Colors.grey.shade400]
                : [_currentTheme.primaryColor, _currentTheme.secondaryColor],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: _isSaving
                  ? Colors.grey.withOpacity(0.3)
                  : _currentTheme.primaryColor.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _isSaving ? null : _updateProfile,
            child: Center(
              child: _isSaving
                  ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.white,
                ),
              )
                  : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.white, size: 24),
                  SizedBox(width: 12),
                  Text(
                    'Save Changes',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileTheme {
  final String name;
  final Color primaryColor;
  final Color secondaryColor;
  final Color accentColor;
  final List<Color> gradient;

  ProfileTheme({
    required this.name,
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentColor,
    required this.gradient,
  });
}

class _PhotoSheetOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _PhotoSheetOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

/// Simple demo app that opens the ProfileUpdatePage
void main() {
  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Profile Update Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(),
      home: const Scaffold(
        body: SafeArea(
          child: Center(
            child: _OpenProfileButton(),
          ),
        ),
      ),
    );
  }
}

class _OpenProfileButton extends StatelessWidget {
  const _OpenProfileButton();

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      child: const Text('Open Profile Update Page'),
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const ProfileUpdatePage(
              initialName: 'You',
              initialAbout: 'Available',
              phoneNumber: '+91 98765 43210',
              initialPhotoUrl: null,
              token: null,
            ),
          ),
        );
      },
    );
  }
}
