import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../auth/data/auth_service.dart';
import '../../auth/data/user_model.dart';

/// Screen 7: Sidebar / Profile Screen
///
/// Reproduces Screen 7 from the "8. Premium Celadon" design specification:
/// - User profile photo with edit badge
/// - Name ("Priya Sharma" or user name) and Role subtitle ("Employee" / "Company Owner" / "Super Administrator")
/// - Interactive menu list with chevron chevrons:
///   * My Profile
///   * Attendance
///   * Tasks
///   * Calendar
///   * Team
///   * Leave Request
///   * Settings
///   * Help & Support
/// - Dual-mode switching card for authorized Super Administrators
/// - Soft peach/red "> Logout" button
class ProfileView extends StatefulWidget {
  final UserModel user;
  final VoidCallback onLogout;
  final void Function(int tabIndex)? onNavigateToTab;
  final void Function(UserModel updatedUser)? onUserUpdated;

  const ProfileView({
    super.key,
    required this.user,
    required this.onLogout,
    this.onNavigateToTab,
    this.onUserUpdated,
  });

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  late UserModel _currentUser;
  bool _isSwitching = false;
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
  }

  Future<void> _handleSwitchMode() async {
    setState(() => _isSwitching = true);

    try {
      final UserModel updatedUser;
      if (_currentUser.isSuperAdmin) {
        // Switch to Company Owner (EMS) Mode
        updatedUser = await _authService.switchToEms();
      } else {
        // Switch to Super Admin Console
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
    final displayName = _currentUser.name.isNotEmpty ? _currentUser.name : (_currentUser.username.isNotEmpty ? _currentUser.username : 'User');
    final roleName = _currentUser.roleDisplayName;
    final canSwitchMode = _currentUser.isSuperAdmin || _currentUser.canSwitchToSuperAdmin;

    return Scaffold(
      backgroundColor: CeladonColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              const SizedBox(height: 10),

              // 1. Profile Avatar with Edit Badge
              Center(
                child: Stack(
                  children: [
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: CeladonColors.primaryLight, width: 3),
                        color: CeladonColors.primaryContainer,
                      ),
                      child: ClipOval(
                        child: Center(
                          child: Text(
                            displayName.substring(0, 1).toUpperCase(),
                            style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              color: CeladonColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: CeladonColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.edit_outlined,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // User Name & Role Subtitle
              Text(
                displayName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: CeladonColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                roleName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: CeladonColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),

              // SuperAdmin Mode Switch Card (if authorized)
              if (canSwitchMode) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: CeladonColors.primaryLight.withValues(alpha: 0.5)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0C2D6A4F),
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
                ),
                const SizedBox(height: 16),
              ],

              // 2. Navigation Menu Rows List
              _buildMenuItem(
                icon: Icons.person_outline_rounded,
                title: 'My Profile',
                onTap: () => _showComingSoon('My Profile'),
              ),
              _buildMenuItem(
                icon: Icons.event_available_outlined,
                title: 'Attendance',
                onTap: () => widget.onNavigateToTab?.call(2), // go to attendance
              ),
              _buildMenuItem(
                icon: Icons.assignment_outlined,
                title: 'Tasks',
                onTap: () => widget.onNavigateToTab?.call(1), // go to tasks
              ),
              _buildMenuItem(
                icon: Icons.calendar_month_outlined,
                title: 'Calendar',
                onTap: () => widget.onNavigateToTab?.call(2), // go to calendar
              ),
              _buildMenuItem(
                icon: Icons.groups_outlined,
                title: 'Team',
                onTap: () => _showComingSoon('Team Directory'),
              ),
              _buildMenuItem(
                icon: Icons.flight_takeoff_outlined,
                title: 'Leave Request',
                onTap: () => _showComingSoon('Leave Request Form'),
              ),
              _buildMenuItem(
                icon: Icons.settings_outlined,
                title: 'Settings',
                onTap: () => _showComingSoon('App Settings'),
              ),
              _buildMenuItem(
                icon: Icons.help_outline_rounded,
                title: 'Help & Support',
                onTap: () => _showComingSoon('Help Center'),
              ),
              const SizedBox(height: 16),

              // 3. Peach / Red Soft Logout Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: TextButton(
                  onPressed: widget.onLogout,
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFFFFECEB),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                      side: const BorderSide(color: Color(0xFFFCA5A5), width: 1),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFFEF4444),
                        size: 20,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Logout',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: CeladonColors.borderLight),
        ),
        elevation: 0,
        child: ListTile(
          onTap: onTap,
          dense: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          leading: Icon(icon, color: CeladonColors.primary, size: 21),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: CeladonColors.textPrimary,
            ),
          ),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: CeladonColors.textMuted,
            size: 19,
          ),
        ),
      ),
    );
  }

  void _showComingSoon(String module) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$module module is active in the ReGen Enterprise cloud.'),
        backgroundColor: CeladonColors.primary,
      ),
    );
  }
}
