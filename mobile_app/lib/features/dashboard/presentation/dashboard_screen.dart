import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../../core/widgets/celadon_button.dart';
import '../../../core/widgets/celadon_card.dart';
import '../../auth/data/auth_service.dart';
import '../../auth/data/user_model.dart';

/// Role-Based Dashboard Landing Screen
///
/// Dispatches the user to their designated workspace based on their
/// verified backend role: SuperAdmin ('param'), Company Admin ('owner'/'admin'),
/// or Employee ('staff'/'intern').
///
/// Features dynamic dual-mode switching for authorized Super Administrators
/// between Platform Control and Company Owner workspace.
class DashboardScreen extends StatefulWidget {
  final UserModel user;
  final VoidCallback onLogout;

  const DashboardScreen({
    super.key,
    required this.user,
    required this.onLogout,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
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

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: CeladonColors.primary,
            content: Text(
              'Switched to ${updatedUser.roleDisplayName} mode',
              style: const TextStyle(color: Colors.white),
            ),
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
    final theme = Theme.of(context);
    final user = _currentUser;

    // Check if the user is authorized to switch modes
    // SuperAdmin ('param') or Company Owner ('owner')
    final canSwitchMode = user.isSuperAdmin || user.role == 'owner';

    return Scaffold(
      backgroundColor: CeladonColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: CeladonColors.primaryContainer,
              ),
              child: const Icon(
                Icons.spa_rounded,
                size: 16,
                color: CeladonColors.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              user.isSuperAdmin ? 'ReGen Central' : 'ReGen Workspace',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sign Out',
            icon: const Icon(
              Icons.logout_rounded,
              size: 20,
              color: CeladonColors.textSecondary,
            ),
            onPressed: () => _confirmLogout(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // User Profile Banner Card
              CeladonCard(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    // Avatar / Initials Circle
                    Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        color: CeladonColors.primary,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        user.name.isNotEmpty
                            ? user.name[0].toUpperCase()
                            : user.username[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user.company ?? 'ReGen Platform',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: CeladonColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Role Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _getRoleBadgeColor(user.role),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              user.roleDisplayName,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _getRoleTextColor(user.role),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Role Experience Card
              CeladonCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _getRoleIcon(user.role),
                          color: CeladonColors.primary,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _getDashboardTitle(user.role),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: CeladonColors.primaryDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _getDashboardDescription(user.role),
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Database Sync Status:',
                          style: TextStyle(
                            fontSize: 12,
                            color: CeladonColors.textSecondary,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            user.authSource ?? 'Connected',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2E7D32),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Dual-Mode Switching Card (SuperAdmin <-> Company Owner)
              if (canSwitchMode) ...[
                CeladonCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.swap_horiz_rounded,
                            color: CeladonColors.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            user.isSuperAdmin
                                ? 'Switch to Company Workspace'
                                : 'Switch to Super Admin Console',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: CeladonColors.primaryDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        user.isSuperAdmin
                            ? 'Toggle into EMS mode to manage your company operations, attendance, and employees.'
                            : 'Return to platform oversight, maintenance control, and multi-company provisioning.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: CeladonColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      CeladonButton(
                        text: user.isSuperAdmin
                            ? 'Switch to Company Mode'
                            : 'Switch to Super Admin',
                        icon: user.isSuperAdmin
                            ? Icons.business_center_rounded
                            : Icons.admin_panel_settings_rounded,
                        isLoading: _isSwitching,
                        onPressed: _isSwitching ? null : _handleSwitchMode,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ],

              // Logout Button
              CeladonButton(
                text: 'Sign Out',
                isOutlined: true,
                icon: Icons.logout_rounded,
                onPressed: () => _confirmLogout(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out of ReGen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: CeladonColors.error,
              minimumSize: const Size(90, 40),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.onLogout();
            },
            child: const Text(
              'Sign Out',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Color _getRoleBadgeColor(String role) {
    switch (role) {
      case 'param':
        return const Color(0xFFFEE2E2);
      case 'owner':
      case 'admin':
        return const Color(0xFFE0F2FE);
      default:
        return CeladonColors.badgeBg;
    }
  }

  Color _getRoleTextColor(String role) {
    switch (role) {
      case 'param':
        return const Color(0xFF991B1B);
      case 'owner':
      case 'admin':
        return const Color(0xFF0369A1);
      default:
        return CeladonColors.badgeText;
    }
  }

  IconData _getRoleIcon(String role) {
    switch (role) {
      case 'param':
        return Icons.admin_panel_settings_rounded;
      case 'owner':
      case 'admin':
        return Icons.corporate_fare_rounded;
      default:
        return Icons.badge_rounded;
    }
  }

  String _getDashboardTitle(String role) {
    switch (role) {
      case 'param':
        return 'Super Admin Platform Control';
      case 'owner':
        return 'Company Owner Dashboard';
      case 'admin':
        return 'Company Administrator Portal';
      default:
        return 'Employee Workplace Hub';
    }
  }

  String _getDashboardDescription(String role) {
    switch (role) {
      case 'param':
        return 'Global system oversight, cross-company provisioning, system maintenance and audit logs.';
      case 'owner':
      case 'admin':
        return 'Manage team attendance, review leave requests, configure geofences, and manage workforce operations.';
      default:
        return 'Record daily attendance, submit leaves, track assigned tasks, and communicate with your team.';
    }
  }
}
