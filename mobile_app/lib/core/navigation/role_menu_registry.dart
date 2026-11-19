import 'package:flutter/material.dart';
import '../../core/navigation/bottom_nav_customizer.dart';
import '../../features/auth/data/user_model.dart';

/// Single item in the role menu and navigation system
class RoleMenuItem {
  final String id;
  final String label;
  final String? subtitle;
  final IconData icon;
  final IconData activeIcon;
  final bool isDefaultBottomNav;

  const RoleMenuItem({
    required this.id,
    required this.label,
    this.subtitle,
    required this.icon,
    required this.activeIcon,
    this.isDefaultBottomNav = false,
  });

  NavShortcutItem toNavShortcutItem() => NavShortcutItem(
        id: id,
        label: label,
        icon: icon,
        activeIcon: activeIcon,
      );
}

/// Central single source of truth for Role Menus (Drawer) and Navigation Bar (Bottom Dock)
///
/// If a page is added or removed from [companyPages] or [employeePages],
/// it dynamically reflects across BOTH the Drawer Menu and the Navigation Bar customizer.
class RoleMenuRegistry {
  /// Company Owner / Admin Pages
  static const List<RoleMenuItem> companyPages = [
    RoleMenuItem(
      id: 'home',
      label: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      isDefaultBottomNav: true,
    ),
    RoleMenuItem(
      id: 'employees',
      label: 'Employees',
      subtitle: 'Manage team members',
      icon: Icons.assignment_ind_outlined,
      activeIcon: Icons.groups_rounded,
      isDefaultBottomNav: true,
    ),
    RoleMenuItem(
      id: 'calender',
      label: 'Calender',
      subtitle: 'Attendance & calendar records',
      icon: Icons.calendar_month_outlined,
      activeIcon: Icons.calendar_month_rounded,
      isDefaultBottomNav: true,
    ),
    RoleMenuItem(
      id: 'leave',
      label: 'Leave',
      subtitle: 'Review approvals & holidays',
      icon: Icons.beach_access_outlined,
      activeIcon: Icons.beach_access_rounded,
      isDefaultBottomNav: true,
    ),
    RoleMenuItem(
      id: 'profile',
      label: 'Profile',
      subtitle: 'Company info & workspace',
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      isDefaultBottomNav: true,
    ),
    RoleMenuItem(
      id: 'tasks',
      label: 'Tasks',
      subtitle: 'Assigned tasks & milestones',
      icon: Icons.assignment_outlined,
      activeIcon: Icons.assignment_rounded,
    ),
    RoleMenuItem(
      id: 'messenger',
      label: 'Messenger',
      subtitle: 'Team chat & direct messages',
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_bubble_rounded,
    ),
    RoleMenuItem(
      id: 'payroll',
      label: 'Payroll',
      subtitle: 'Automated payroll processing',
      icon: Icons.payments_outlined,
      activeIcon: Icons.payments_rounded,
    ),
    RoleMenuItem(
      id: 'reports',
      label: 'Reports',
      subtitle: 'Workforce analytics & summaries',
      icon: Icons.bar_chart_rounded,
      activeIcon: Icons.bar_chart_rounded,
    ),
    RoleMenuItem(
      id: 'settings',
      label: 'Settings',
      subtitle: 'Preferences & configurations',
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
    ),
  ];

  /// Employee / Staff Pages
  static const List<RoleMenuItem> employeePages = [
    RoleMenuItem(
      id: 'home',
      label: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      isDefaultBottomNav: true,
    ),
    RoleMenuItem(
      id: 'tasks',
      label: 'Tasks',
      subtitle: 'Daily tasks & assignments',
      icon: Icons.assignment_outlined,
      activeIcon: Icons.assignment_rounded,
      isDefaultBottomNav: true,
    ),
    RoleMenuItem(
      id: 'calendar',
      label: 'Calendar',
      subtitle: 'Attendance, events & holidays',
      icon: Icons.calendar_today_outlined,
      activeIcon: Icons.calendar_today_rounded,
      isDefaultBottomNav: true,
    ),
    RoleMenuItem(
      id: 'profile',
      label: 'Profile',
      subtitle: 'Personal profile & details',
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      isDefaultBottomNav: true,
    ),
    RoleMenuItem(
      id: 'messenger',
      label: 'Messenger',
      subtitle: 'Chat & team calls',
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_bubble_rounded,
    ),
    RoleMenuItem(
      id: 'attendance',
      label: 'Attendance',
      subtitle: 'Geofenced check-in & work logs',
      icon: Icons.event_available_outlined,
      activeIcon: Icons.event_available_rounded,
    ),
    RoleMenuItem(
      id: 'team',
      label: 'Team',
      subtitle: 'Colleagues & directory',
      icon: Icons.groups_outlined,
      activeIcon: Icons.groups_rounded,
    ),
    RoleMenuItem(
      id: 'leave',
      label: 'Leave',
      subtitle: 'Apply for leave & time off',
      icon: Icons.beach_access_outlined,
      activeIcon: Icons.beach_access_rounded,
    ),
    RoleMenuItem(
      id: 'payroll',
      label: 'Payroll',
      subtitle: 'Personal earnings & salary slips',
      icon: Icons.payments_outlined,
      activeIcon: Icons.payments_rounded,
    ),
    RoleMenuItem(
      id: 'settings',
      label: 'Settings',
      subtitle: 'Appearance & app settings',
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
    ),
    RoleMenuItem(
      id: 'help',
      label: 'Support',
      subtitle: 'FAQs & contact support',
      icon: Icons.help_outline_rounded,
      activeIcon: Icons.help_rounded,
    ),
  ];

  /// Super Admin Pages
  static const List<RoleMenuItem> superAdminPages = [
    RoleMenuItem(
      id: 'home',
      label: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      isDefaultBottomNav: true,
    ),
    RoleMenuItem(
      id: 'tasks',
      label: 'Tasks',
      subtitle: 'System tasks & milestones',
      icon: Icons.assignment_outlined,
      activeIcon: Icons.assignment_rounded,
      isDefaultBottomNav: true,
    ),
    RoleMenuItem(
      id: 'calendar',
      label: 'Calendar',
      subtitle: 'System calendar & events',
      icon: Icons.calendar_today_outlined,
      activeIcon: Icons.calendar_today_rounded,
      isDefaultBottomNav: true,
    ),
    RoleMenuItem(
      id: 'profile',
      label: 'Profile',
      subtitle: 'SuperAdmin profile',
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      isDefaultBottomNav: true,
    ),
    RoleMenuItem(
      id: 'messenger',
      label: 'Messenger',
      subtitle: 'Executive direct messaging',
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_bubble_rounded,
    ),
    RoleMenuItem(
      id: 'attendance',
      label: 'Attendance',
      subtitle: 'Platform attendance records',
      icon: Icons.event_available_outlined,
      activeIcon: Icons.event_available_rounded,
    ),
    RoleMenuItem(
      id: 'team',
      label: 'Team',
      subtitle: 'Platform directory',
      icon: Icons.groups_outlined,
      activeIcon: Icons.groups_rounded,
    ),
    RoleMenuItem(
      id: 'settings',
      label: 'Settings',
      subtitle: 'Platform preferences',
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
    ),
    RoleMenuItem(
      id: 'help',
      label: 'Support',
      subtitle: 'Support console',
      icon: Icons.help_outline_rounded,
      activeIcon: Icons.help_rounded,
    ),
  ];

  /// Returns the menu items for the given user role
  static List<RoleMenuItem> getMenuItemsForRole(UserModel? user) {
    if (user == null) return employeePages;
    if (user.isCompanyAdmin) return companyPages;
    if (user.isSuperAdmin) return superAdminPages;
    return employeePages;
  }

  /// Returns the nav shortcuts catalog for the given user role
  static List<NavShortcutItem> getNavCatalogForRole(UserModel? user) {
    return getMenuItemsForRole(user).map((m) => m.toNavShortcutItem()).toList();
  }

  /// Returns the default bottom nav slot IDs for the given user role
  static List<String> getDefaultSlotsForRole(UserModel? user) {
    final pages = getMenuItemsForRole(user);
    final defaults = pages.where((p) => p.isDefaultBottomNav).map((p) => p.id).toList();
    if (defaults.isNotEmpty) return defaults;
    return pages.take(4).map((p) => p.id).toList();
  }

  /// Returns the storage role key used by [BottomNavCustomizer]
  static String getRoleStorageKey(UserModel? user) {
    if (user == null) return 'employee';
    if (user.isCompanyAdmin) return 'company';
    if (user.isSuperAdmin) return 'superadmin';
    return 'employee';
  }
}
