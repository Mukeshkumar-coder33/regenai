import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../auth/data/user_model.dart';
import 'help_support_view.dart';
import 'leave_request_view.dart';
import 'settings_view.dart';
import 'team_directory_view.dart';

/// App-wide Navigation Drawer
///
/// Features:
/// - Exact ReGen green office header with user avatar, name, designation, and close icon
/// - 9 standard employee navigation items matching the Premium Office design
/// - Dismisses via close (X) button, tapping item, or tapping barrier
class AppDrawer extends StatelessWidget {
  final UserModel user;
  final VoidCallback onLogout;
  final void Function(int tabIndex)? onNavigateToTab;
  final VoidCallback? onOpenAttendance;
  final int? currentTabIndex;

  const AppDrawer({
    super.key,
    required this.user,
    required this.onLogout,
    this.onNavigateToTab,
    this.onOpenAttendance,
    this.currentTabIndex,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = user.name.isNotEmpty
        ? user.name
        : (user.username.isNotEmpty ? user.username : 'Alex Johnson');
    final roleName = user.roleDisplayName;

    final screenWidth = MediaQuery.of(context).size.width;
    final drawerWidth = (screenWidth * 0.78).clamp(260.0, 310.0);

    return SizedBox(
      width: drawerWidth,
      child: Drawer(
        backgroundColor: CeladonColors.background,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Drawer Header with office backdrop texture, avatar, name, and close (X) button
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: CeladonColors.primaryDark,
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Opacity(
                        opacity: 0.22,
                        child: Image.asset(
                          'assets/images/office_workspace.png',
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const SizedBox.shrink(),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              CeladonColors.primaryDark.withValues(alpha: 0.94),
                              CeladonColors.primary.withValues(alpha: 0.88),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(
                        top: MediaQuery.of(context).padding.top + 20,
                        bottom: 20,
                        left: 20,
                        right: 14,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              color: CeladonColors.primaryContainer,
                            ),
                            child: ClipOval(
                              child: Center(
                                child: Text(
                                  displayName.substring(0, 1).toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: CeladonColors.primaryDark,
                                  ),
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
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  roleName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFFB5D6C3),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white70,
                              size: 24,
                            ),
                            tooltip: 'Close drawer',
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Drawer Navigation Options
            Expanded(
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                children: [
                  // 1. My Profile
                  _buildDrawerItem(
                    context: context,
                    icon: Icons.person_outline_rounded,
                    title: 'My Profile',
                    isSelected: currentTabIndex == 3,
                    onTap: () {
                      Navigator.of(context).pop();
                      onNavigateToTab?.call(3);
                    },
                  ),

                  // 2. Attendance
                  _buildDrawerItem(
                    context: context,
                    icon: Icons.event_available_outlined,
                    title: 'Attendance',
                    onTap: () {
                      Navigator.of(context).pop();
                      if (onOpenAttendance != null) {
                        onOpenAttendance!();
                      } else {
                        onNavigateToTab?.call(2);
                      }
                    },
                  ),

                  // 3. Tasks
                  _buildDrawerItem(
                    context: context,
                    icon: Icons.assignment_outlined,
                    title: 'Tasks',
                    isSelected: currentTabIndex == 1,
                    onTap: () {
                      Navigator.of(context).pop();
                      onNavigateToTab?.call(1);
                    },
                  ),

                  // 4. Calendar
                  _buildDrawerItem(
                    context: context,
                    icon: Icons.calendar_month_outlined,
                    title: 'Calendar',
                    isSelected: currentTabIndex == 2,
                    onTap: () {
                      Navigator.of(context).pop();
                      onNavigateToTab?.call(2);
                    },
                  ),

                  // 5. Team
                  _buildDrawerItem(
                    context: context,
                    icon: Icons.groups_outlined,
                    title: 'Team',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TeamDirectoryView(
                            onBack: () => Navigator.of(context).pop(),
                          ),
                        ),
                      );
                    },
                  ),

                  // 6. Leave Request
                  _buildDrawerItem(
                    context: context,
                    icon: Icons.flight_takeoff_outlined,
                    title: 'Leave Request',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => LeaveRequestView(
                            onBack: () => Navigator.of(context).pop(),
                          ),
                        ),
                      );
                    },
                  ),

                  // 7. Settings
                  _buildDrawerItem(
                    context: context,
                    icon: Icons.settings_outlined,
                    title: 'Settings',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => SettingsView(
                            onBack: () => Navigator.of(context).pop(),
                          ),
                        ),
                      );
                    },
                  ),

                  // 8. Help & Support
                  _buildDrawerItem(
                    context: context,
                    icon: Icons.help_outline_rounded,
                    title: 'Help & Support',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => HelpSupportView(
                            onBack: () => Navigator.of(context).pop(),
                          ),
                        ),
                      );
                    },
                  ),

                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(color: CeladonColors.divider, height: 1),
                  ),

                  // 9. Logout
                  _buildDrawerItem(
                    context: context,
                    icon: Icons.logout_rounded,
                    title: 'Logout',
                    isDestructive: true,
                    onTap: () {
                      Navigator.of(context).pop();
                      onLogout();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isSelected = false,
    bool isDestructive = false,
  }) {
    final textColor = isDestructive
        ? const Color(0xFFEF4444)
        : (isSelected ? CeladonColors.primary : const Color(0xFF334155));
    final bgColor = isDestructive
        ? const Color(0xFFFEF2F2)
        : (isSelected ? CeladonColors.primaryContainer : Colors.transparent);
    final iconColor =
        isDestructive ? const Color(0xFFEF4444) : CeladonColors.primary;
    final borderSide = isSelected
        ? BorderSide(
            color: CeladonColors.primaryLight.withValues(alpha: 0.5), width: 1.2)
        : (isDestructive
            ? const BorderSide(color: Color(0xFFFECACA), width: 1)
            : BorderSide.none);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: bgColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: borderSide,
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          dense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
          visualDensity: const VisualDensity(horizontal: 0, vertical: -1.5),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          leading: Icon(icon, color: iconColor, size: 21),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight:
                  isSelected || isDestructive ? FontWeight.w700 : FontWeight.w600,
              color: textColor,
            ),
          ),
          trailing: isDestructive
              ? null
              : Icon(
                  Icons.chevron_right_rounded,
                  color:
                      isSelected ? CeladonColors.primary : const Color(0xFF94A3B8),
                  size: 18,
                ),
        ),
      ),
    );
  }
}

