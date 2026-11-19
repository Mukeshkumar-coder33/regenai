import 'package:flutter/material.dart';
import '../../../core/navigation/role_menu_registry.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../auth/data/user_model.dart';
import '../../dashboard/presentation/employee_payroll_view.dart';
import '../../messenger/presentation/messenger_view.dart';
import 'leave_request_view.dart';
import 'settings_view.dart';

/// App-wide Executive Navigation Drawer
///
/// Matches the Company Role Drawer design pixel-for-pixel:
/// - ReGen brand logo with close (X) button
/// - Glass executive user profile card with avatar and company/role chip
/// - WORKSPACE OPERATIONS section header with emerald indicator
/// - Dynamic role-based menu items with rounded icons and chevron indicators
/// - Solid bright red Sign Out button
/// - Synchronized with RoleMenuRegistry (Team and Support removed)
class AppDrawer extends StatelessWidget {
  final UserModel user;
  final VoidCallback onLogout;
  final void Function(int tabIndex)? onNavigateToTab;
  final void Function(String pageId)? onNavigateToPage;
  final VoidCallback? onOpenAttendance;
  final int? currentTabIndex;
  final String? currentPageId;

  const AppDrawer({
    super.key,
    required this.user,
    required this.onLogout,
    this.onNavigateToTab,
    this.onNavigateToPage,
    this.onOpenAttendance,
    this.currentTabIndex,
    this.currentPageId,
  });

  void _routeById(BuildContext context, String pageId) {
    switch (pageId) {
      case 'profile':
        onNavigateToTab?.call(3);
        break;
      case 'attendance':
        if (onOpenAttendance != null) {
          onOpenAttendance!();
        } else {
          onNavigateToTab?.call(2);
        }
        break;
      case 'tasks':
        onNavigateToTab?.call(1);
        break;
      case 'calendar':
        onNavigateToTab?.call(2);
        break;
      case 'messenger':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MessengerView(
              user: user,
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
        );
        break;
      case 'leave':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LeaveRequestView(
              user: user,
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
        );
        break;
      case 'payroll':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EmployeePayrollView(
              user: user,
              embedded: false,
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
        );
        break;
      case 'settings':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SettingsView(
              user: user,
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
        );
        break;
      default:
        onNavigateToTab?.call(0);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final companyName = user.companyName ?? user.company ?? 'ReGen Workspace';
    final displayName = user.name.isNotEmpty
        ? user.name
        : (user.username.isNotEmpty ? user.username : 'Employee');
    final roleName = user.roleDisplayName;

    final drawerWidth = (MediaQuery.of(context).size.width * 0.85).clamp(290.0, 360.0);

    // Dynamically retrieve menu pages for this role from the single source of truth
    final menuItems = RoleMenuRegistry.getMenuItemsForRole(user);
    final operations = menuItems.where((p) => p.id != 'home' && p.id != 'profile').toList();

    return SizedBox(
      width: drawerWidth,
      child: Drawer(
        backgroundColor: CeladonColors.cardBackground,
        elevation: 0,
        child: Container(
          decoration: const BoxDecoration(
            color: CeladonColors.cardBackground,
            border: Border(
              right: BorderSide(color: CeladonColors.border, width: 1.0),
            ),
          ),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Drawer Top Bar: Brand + Close (X)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                  child: Row(
                    children: [
                      const BrandLogo(size: 26, borderRadius: 8),
                      const SizedBox(width: 10),
                      const Text(
                        'ReGen',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: CeladonColors.textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: CeladonColors.textPrimary,
                          size: 24,
                        ),
                        tooltip: 'Close drawer',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),

                // 2. User Profile & Company Banner (Matching Company Drawer Card)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: CeladonColors.border, width: 1.0),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x06000000),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: CeladonColors.primaryLight,
                            border: Border.all(
                              color: CeladonColors.primary,
                              width: 2,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              displayName.isNotEmpty ? displayName[0].toUpperCase() : 'E',
                              style: const TextStyle(
                                color: CeladonColors.primary,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: CeladonColors.textPrimary,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: CeladonColors.primaryLight,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: CeladonColors.primary,
                                    width: 1.0,
                                  ),
                                ),
                                child: Text(
                                  '$companyName • $roleName',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: CeladonColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 6),

                // 3. Section Label matching Company Drawer
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: CeladonColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'WORKSPACE OPERATIONS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: CeladonColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),

                // 4. Dynamic Operations List driven by RoleMenuRegistry
                Expanded(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: operations.map((item) {
                        final bool isSelected = currentPageId != null
                            ? currentPageId == item.id
                            : (item.id == 'tasks' && currentTabIndex == 1) ||
                              (item.id == 'calendar' && currentTabIndex == 2);

                        return _buildDrawerMenuItem(
                          icon: item.icon,
                          title: item.label,
                          subtitle: item.subtitle,
                          isSelected: isSelected,
                          onTap: () {
                            Navigator.of(context).pop();
                            if (onNavigateToPage != null) {
                              onNavigateToPage!(item.id);
                            } else {
                              _routeById(context, item.id);
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ),

                // 5. Bottom Sign Out Button (Solid Bright Red matching Company Drawer)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        onLogout();
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC4C4C), // Solid Bright Red
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFEF4444),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFDC4C4C).withValues(alpha: 0.55),
                              blurRadius: 12,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(
                              Icons.logout_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Sign Out',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerMenuItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool isSelected = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: CeladonColors.primary.withValues(alpha: 0.08),
        highlightColor: CeladonColors.primary.withValues(alpha: 0.04),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: isSelected
              ? BoxDecoration(
                  color: CeladonColors.primaryLight.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                )
              : null,
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isSelected ? CeladonColors.primary : CeladonColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: isSelected ? Colors.white : CeladonColors.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                        color: isSelected ? CeladonColors.primary : CeladonColors.textPrimary,
                        letterSpacing: -0.1,
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: CeladonColors.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF94A3B8),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
