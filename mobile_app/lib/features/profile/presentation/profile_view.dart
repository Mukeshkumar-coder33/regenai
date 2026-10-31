import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../auth/data/auth_service.dart';
import '../../auth/data/user_model.dart';
import '../data/profile_service.dart';
import 'app_drawer.dart';

/// Screen 7: Profile Screen (Premium Modern Office Theme)
///
/// Features:
/// - Reuses exact Dashboard background image (`assets/images/office_dashboard_header.png`)
///   with subtle emerald-green overlay and rounded corners.
/// - Circular profile photo with white border and bottom-right edit icon.
/// - Gallery photo picker (`image_picker`) with preview dialog before saving.
/// - Editable personal information form (Full Name, Phone, Email) via modal bottom sheet.
/// - Clean white cards with subtle dividers:
///     1. Employee Information Card (ID, Company, Username, Account Status - protected read-only)
///     2. Personal Information Card (Full Name, Email, Phone - with Edit Profile action)
/// - Backend synchronization via `PUT /api/users/:id`.
class ProfileView extends StatefulWidget {
  final UserModel user;
  final VoidCallback onLogout;
  final void Function(int tabIndex)? onNavigateToTab;
  final VoidCallback? onOpenAttendance;
  final void Function(UserModel updatedUser)? onUserUpdated;

  const ProfileView({
    super.key,
    required this.user,
    required this.onLogout,
    this.onNavigateToTab,
    this.onOpenAttendance,
    this.onUserUpdated,
  });

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late UserModel _currentUser;
  bool _isSwitching = false;
  bool _isLoadingProfile = false;

  final AuthService _authService = AuthService();
  final ProfileService _profileService = ProfileService();
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
    _refreshProfileData();
  }

  @override
  void didUpdateWidget(covariant ProfileView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.user != oldWidget.user) {
      _currentUser = widget.user;
    }
  }

  Future<void> _refreshProfileData() async {
    if (_currentUser.userId.isEmpty && _currentUser.id.isEmpty) return;
    try {
      final user = await _profileService.fetchUserProfile(
        _currentUser.userId.isNotEmpty ? _currentUser.userId : _currentUser.id,
        _currentUser.token,
      );
      if (mounted) {
        setState(() {
          _currentUser = user;
        });
        widget.onUserUpdated?.call(user);
      }
    } catch (_) {
      // Graceful fallback to initial user state
    }
  }

  /// Select profile picture from gallery with preview before save
  Future<void> _handlePickProfileImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 720,
        maxHeight: 720,
        imageQuality: 85,
      );

      if (pickedFile == null || !mounted) return;

      final bytes = await pickedFile.readAsBytes();
      final base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}';

      if (!mounted) return;

      // Show preview dialog before confirming
      final shouldSave = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          backgroundColor: Colors.white,
          title: const Text(
            'Confirm Profile Picture',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: CeladonColors.textPrimary,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: CeladonColors.primary, width: 3),
                  image: DecorationImage(
                    image: MemoryImage(bytes),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Would you like to set this photo as your employee profile avatar?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: CeladonColors.textSecondary),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel', style: TextStyle(color: CeladonColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: CeladonColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Save Photo'),
            ),
          ],
        ),
      );

      if (shouldSave == true) {
        await _saveProfileImage(base64Image);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: CeladonColors.error,
            content: Text('Could not select image: $e'),
          ),
        );
      }
    }
  }

  Future<void> _saveProfileImage(String base64Image) async {
    setState(() => _isLoadingProfile = true);
    try {
      final updated = await _profileService.updatePersonalDetails(
        userId: _currentUser.userId.isNotEmpty ? _currentUser.userId : _currentUser.id,
        token: _currentUser.token,
        name: _currentUser.name,
        avatarBase64: base64Image,
      );

      if (mounted) {
        setState(() {
          _currentUser = updated;
          _isLoadingProfile = false;
        });
        widget.onUserUpdated?.call(updated);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: CeladonColors.primary,
            content: Text('Profile photo updated successfully!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingProfile = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: CeladonColors.error,
            content: Text('Failed to update profile photo: $e'),
          ),
        );
      }
    }
  }

  /// Opens dedicated professional Edit Profile bottom sheet
  void _openEditProfileSheet() {
    final nameController = TextEditingController(text: _currentUser.name);
    final phoneController = TextEditingController(text: _currentUser.phone ?? '');
    final emailController = TextEditingController(text: _currentUser.email ?? '');
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              padding: EdgeInsets.only(
                top: 20,
                left: 24,
                right: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Drag Handle
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Edit Personal Information',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: CeladonColors.textPrimary,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: CeladonColors.textSecondary),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                      const Text(
                        'Update your personal contact information. Company and administrative details remain locked.',
                        style: TextStyle(fontSize: 12.5, color: CeladonColors.textSecondary),
                      ),
                      const SizedBox(height: 20),

                      // Full Name Field
                      const Text(
                        'Full Name *',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: CeladonColors.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: nameController,
                        style: const TextStyle(fontSize: 14, color: CeladonColors.textPrimary, fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.person_outline_rounded, color: CeladonColors.primary),
                          hintText: 'Enter full name',
                          fillColor: CeladonColors.background,
                          filled: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: CeladonColors.borderLight),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) return 'Name cannot be empty';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Phone Field
                      const Text(
                        'Personal Phone',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: CeladonColors.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(fontSize: 14, color: CeladonColors.textPrimary, fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.phone_outlined, color: CeladonColors.primary),
                          hintText: '+91 98765 43210',
                          fillColor: CeladonColors.background,
                          filled: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: CeladonColors.borderLight),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Personal Email Field
                      const Text(
                        'Personal Email',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: CeladonColors.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(fontSize: 14, color: CeladonColors.textPrimary, fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.email_outlined, color: CeladonColors.primary),
                          hintText: 'user@example.com',
                          fillColor: CeladonColors.background,
                          filled: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: CeladonColors.borderLight),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSaving ? null : () => Navigator.of(ctx).pop(),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: CeladonColors.border),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              child: const Text('Cancel', style: TextStyle(color: CeladonColors.textSecondary, fontWeight: FontWeight.w700)),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      if (!formKey.currentState!.validate()) return;
                                      setSheetState(() => isSaving = true);
                                      try {
                                        final updated = await _profileService.updatePersonalDetails(
                                          userId: _currentUser.userId.isNotEmpty ? _currentUser.userId : _currentUser.id,
                                          token: _currentUser.token,
                                          name: nameController.text.trim(),
                                          phone: phoneController.text.trim(),
                                          email: emailController.text.trim(),
                                        );

                                        if (!mounted) return;
                                        setState(() => _currentUser = updated);
                                        widget.onUserUpdated?.call(updated);
                                        if (sheetContext.mounted) {
                                          Navigator.of(sheetContext).pop();
                                        }
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            backgroundColor: CeladonColors.primary,
                                            content: Text('Personal profile updated successfully!'),
                                          ),
                                        );
                                      } catch (err) {
                                        setSheetState(() => isSaving = false);
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            backgroundColor: CeladonColors.error,
                                            content: Text('Update failed: $err'),
                                          ),
                                        );
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: CeladonColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              child: isSaving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: CeladonColors.error),
            SizedBox(width: 10),
            Text('Confirm Logout', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          ],
        ),
        content: const Text(
          'Are you sure you want to log out of your ReGen account?',
          style: TextStyle(color: CeladonColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: CeladonColors.textSecondary, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: CeladonColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.onLogout();
            },
            child: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSwitchMode() async {
    setState(() => _isSwitching = true);

    try {
      final UserModel updatedUser;
      if (_currentUser.isSuperAdmin) {
        updatedUser = await _authService.switchToEms();
      } else {
        updatedUser = await _authService.switchToSuperAdmin();
      }

      if (mounted) {
        setState(() {
          _currentUser = updatedUser;
          _isSwitching = false;
        });

        widget.onUserUpdated?.call(updatedUser);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: CeladonColors.primary,
            content: Text('Switched to ${updatedUser.roleDisplayName} mode'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSwitching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: CeladonColors.error,
            content: Text('Failed to switch mode: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _currentUser.name.isNotEmpty
        ? _currentUser.name
        : (_currentUser.username.isNotEmpty ? _currentUser.username : 'Alex Johnson');
    final roleName = _currentUser.roleDisplayName;
    final canSwitchMode = _currentUser.isSuperAdmin || _currentUser.role == 'owner';

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: CeladonColors.background,
      drawer: AppDrawer(
        user: _currentUser,
        onLogout: widget.onLogout,
        onNavigateToTab: widget.onNavigateToTab,
        onOpenAttendance: widget.onOpenAttendance,
        currentTabIndex: 3,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 1. Executive Office Profile Header reusing exact Dashboard background
            _buildProfileHeader(displayName, roleName),

            // 2. Profile Details & Settings Body
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Column(
                children: [
                  // Employee Information Card (Protected & Read-Only)
                  _buildEmployeeInformationCard(),
                  const SizedBox(height: 18),

                  // Personal Information Card (Editable)
                  _buildPersonalInformationCard(displayName),

                  // Workspace Switcher Card (for SuperAdmin / Company Owner)
                  if (canSwitchMode) ...[
                    const SizedBox(height: 18),
                    _buildWorkspaceModeCard(),
                  ],

                  const SizedBox(height: 24),

                  // Prominent Log Out Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmLogout(context),
                      icon: const Icon(Icons.logout_rounded, color: CeladonColors.error, size: 20),
                      label: const Text(
                        'Log Out of Account',
                        style: TextStyle(
                          color: CeladonColors.error,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFFCA5A5), width: 1.5),
                        backgroundColor: const Color(0xFFFEF2F2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Executive Office Header with Exact Dashboard Background & Subtle Overlay
  Widget _buildProfileHeader(String displayName, String roleName) {
    return Container(
      decoration: const BoxDecoration(
        color: CeladonColors.primaryDark,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
        child: Stack(
          children: [
            // Reusing exact Dashboard background image
            Positioned.fill(
              child: Image.asset(
                'assets/images/office_dashboard_header.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
              ),
            ),

            // Bright, translucent emerald-green overlay matching dashboard visibility
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF0F3A2E).withValues(alpha: 0.58),
                      const Color(0xFF1B4332).withValues(alpha: 0.38),
                      const Color(0xFF0F3A2E).withValues(alpha: 0.62),
                    ],
                  ),
                ),
              ),
            ),

            // Header Content
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 26),
                child: Column(
                  children: [
                    // Top App Bar Row with Hamburger Icon
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.menu_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                          tooltip: 'Open navigation menu',
                          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                        ),
                        const Expanded(
                          child: Text(
                            'Profile',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.logout_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                          tooltip: 'Log Out',
                          onPressed: () => _confirmLogout(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Profile Avatar with Edit Badge
                    Center(
                      child: Stack(
                        children: [
                          Container(
                            width: 104,
                            height: 104,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3.5),
                              color: CeladonColors.primaryContainer,
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x30000000),
                                  blurRadius: 18,
                                  offset: Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: _isLoadingProfile
                                  ? const Center(
                                      child: SizedBox(
                                        width: 28,
                                        height: 28,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: CeladonColors.primary,
                                        ),
                                      ),
                                    )
                                  : (_currentUser.avatar != null &&
                                          _currentUser.avatar!.isNotEmpty)
                                      ? _buildAvatarImage(_currentUser.avatar!)
                                      : Center(
                                          child: Text(
                                            displayName
                                                .substring(0, 1)
                                                .toUpperCase(),
                                            style: const TextStyle(
                                              fontSize: 40,
                                              fontWeight: FontWeight.w800,
                                              color: CeladonColors.primaryDark,
                                            ),
                                          ),
                                        ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: InkWell(
                              onTap: _handlePickProfileImage,
                              borderRadius: BorderRadius.circular(18),
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: CeladonColors.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2.2),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x30000000),
                                      blurRadius: 6,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.camera_alt_rounded,
                                  size: 17,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Employee Name
                    Text(
                      displayName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.2,
                        shadows: [
                          Shadow(offset: Offset(0, 1), blurRadius: 4, color: Color(0x70000000)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Employee Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                      ),
                      child: Text(
                        roleName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarImage(String avatarUrl) {
    if (avatarUrl.startsWith('data:image')) {
      try {
        final base64Str = avatarUrl.split(',').last;
        return Image.memory(base64Decode(base64Str), fit: BoxFit.cover);
      } catch (_) {}
    }
    return Image.network(
      avatarUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Center(
        child: Text(
          _currentUser.name.isNotEmpty ? _currentUser.name.substring(0, 1).toUpperCase() : 'U',
          style: const TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w800,
            color: CeladonColors.primaryDark,
          ),
        ),
      ),
    );
  }

  /// 1. Employee Information Card (Protected & Read-Only)
  Widget _buildEmployeeInformationCard() {
    final employeeId = _currentUser.userId.isNotEmpty
        ? _currentUser.userId
        : 'EMP-${_currentUser.id.isNotEmpty ? _currentUser.id.substring(0, 4).toUpperCase() : '2026'}';
    final companyName = _currentUser.company ?? 'ReGen Enterprise';
    final username = _currentUser.username;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: CeladonColors.borderLight),
        boxShadow: const [
          BoxShadow(
            color: Color(0x082D6A4F),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: CeladonColors.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.badge_outlined,
                  color: CeladonColors.primary,
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Employee Information',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: CeladonColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildDetailRow(
            icon: Icons.fingerprint_rounded,
            label: 'Employee ID',
            value: employeeId,
          ),
          _buildDivider(),
          _buildDetailRow(
            icon: Icons.business_outlined,
            label: 'Company',
            value: companyName,
          ),
          _buildDivider(),
          _buildDetailRow(
            icon: Icons.alternate_email_rounded,
            label: 'Username',
            value: username,
          ),
          _buildDivider(),
          _buildDetailRow(
            icon: Icons.verified_user_outlined,
            label: 'Account Status',
            value: 'Active',
            valueColor: CeladonColors.success,
          ),
        ],
      ),
    );
  }

  /// 2. Personal Information Card (Separate Section with Edit Profile Button)
  Widget _buildPersonalInformationCard(String displayName) {
    final phoneDisplay = (_currentUser.phone != null && _currentUser.phone!.isNotEmpty)
        ? _currentUser.phone!
        : 'Not provided';
    final emailDisplay = (_currentUser.email != null && _currentUser.email!.isNotEmpty)
        ? _currentUser.email!
        : '${_currentUser.username}@regen.com';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: CeladonColors.borderLight),
        boxShadow: const [
          BoxShadow(
            color: Color(0x082D6A4F),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: CeladonColors.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.person_pin_outlined,
                      color: CeladonColors.primary,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Personal Information',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: CeladonColors.textPrimary,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: _openEditProfileSheet,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: CeladonColors.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.edit_outlined, size: 14, color: CeladonColors.primary),
                      SizedBox(width: 4),
                      Text(
                        'Edit',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: CeladonColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildDetailRow(
            icon: Icons.person_outline_rounded,
            label: 'Name',
            value: '$displayName ',
          ),
          _buildDivider(),
          _buildDetailRow(
            icon: Icons.email_outlined,
            label: 'Email',
            value: emailDisplay,
          ),
          _buildDivider(),
          _buildDetailRow(
            icon: Icons.phone_outlined,
            label: 'Phone',
            value: phoneDisplay,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openEditProfileSheet,
              icon: const Icon(Icons.edit_note_rounded, size: 18),
              label: const Text('Edit Personal Profile'),
              style: OutlinedButton.styleFrom(
                foregroundColor: CeladonColors.primary,
                side: const BorderSide(color: CeladonColors.primaryLight, width: 1.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Icon(icon, size: 18, color: CeladonColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: CeladonColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: valueColor ?? CeladonColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(
      color: CeladonColors.borderLight,
      height: 1,
      thickness: 0.8,
    );
  }

  /// SuperAdmin / Owner Workspace Mode Card
  Widget _buildWorkspaceModeCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: CeladonColors.primaryLight.withValues(alpha: 0.5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x082D6A4F),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                _currentUser.isSuperAdmin
                    ? Icons.admin_panel_settings_rounded
                    : Icons.corporate_fare_rounded,
                color: CeladonColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _currentUser.isSuperAdmin
                    ? 'Super Admin Workspace'
                    : 'Company Workspace',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: CeladonColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _currentUser.isSuperAdmin
                ? 'Switch to Company Owner mode to access company operations, attendance, and payroll.'
                : 'Switch to Super Admin mode to manage tenants, platform settings, and system logs.',
            style: const TextStyle(
              fontSize: 12,
              color: CeladonColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _isSwitching ? null : _handleSwitchMode,
            style: ElevatedButton.styleFrom(
              backgroundColor: CeladonColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _isSwitching
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _currentUser.isSuperAdmin
                        ? 'Switch to Company EMS'
                        : 'Switch to SuperAdmin Console',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
          ),
        ],
      ),
    );
  }
}
