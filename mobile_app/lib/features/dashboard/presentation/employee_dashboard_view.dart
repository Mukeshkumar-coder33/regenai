import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../auth/data/user_model.dart';

/// Screen 3: Home Dashboard (Premium Modern Office Theme)
///
/// Features:
/// - Premium dark-green header with subtle AI-generated office workstation background & overlay
/// - Employee greeting and date pill
/// - Attractive statistics cards: Total Employees, Present, On Leave, Tasks, Departments
/// - Refined Today's Tasks section with polished white cards, soft shadows, and clean typography
class EmployeeDashboardView extends StatelessWidget {
  final UserModel user;
  final VoidCallback? onNotificationTap;
  final void Function(int tabIndex)? onNavigateToTab;
  final VoidCallback? onOpenDrawer;
  final dynamic dashboardService;

  const EmployeeDashboardView({
    super.key,
    required this.user,
    this.onNotificationTap,
    this.onNavigateToTab,
    this.onOpenDrawer,
    this.dashboardService,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = user.name.isNotEmpty
        ? user.name
        : (user.username.isNotEmpty ? user.username : 'Alex Johnson');

    return Scaffold(
      backgroundColor: CeladonColors.background,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Premium Dark-Green Office Header
            _buildOfficeHeader(context, displayName),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 2. Primary Statistic Card: "128 Total Employees"
                  _buildTotalEmployeesCard(),
                  const SizedBox(height: 14),

                  // 3. 2x2 Metric Cards Grid (Present, On Leave, Tasks, Departments)
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricTile(
                          icon: Icons.badge_outlined,
                          iconBg: CeladonColors.primaryContainer,
                          iconColor: CeladonColors.primary,
                          count: '3',
                          label: 'Present',
                          valueColor: CeladonColors.textPrimary,
                          onTap: () => onNavigateToTab?.call(2), // Attendance
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _buildMetricTile(
                          icon: Icons.beach_access_outlined,
                          iconBg: const Color(0xFFFEE2E2),
                          iconColor: const Color(0xFFEF4444),
                          count: '2',
                          label: 'On Leave',
                          valueColor: const Color(0xFFEF4444),
                          onTap: () {},
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricTile(
                          icon: Icons.assignment_outlined,
                          iconBg: CeladonColors.primaryContainer,
                          iconColor: CeladonColors.primary,
                          count: '5',
                          label: 'Tasks',
                          valueColor: CeladonColors.textPrimary,
                          onTap: () => onNavigateToTab?.call(1), // Tasks
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _buildMetricTile(
                          icon: Icons.corporate_fare_rounded,
                          iconBg: CeladonColors.primaryContainer,
                          iconColor: CeladonColors.primary,
                          count: '12',
                          label: 'Departments',
                          valueColor: CeladonColors.textPrimary,
                          onTap: () {},
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // 4. Section Header: "Today's Tasks"
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Today's Tasks",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: CeladonColors.textPrimary,
                        ),
                      ),
                      InkWell(
                        onTap: () => onNavigateToTab?.call(1),
                        borderRadius: BorderRadius.circular(12),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Text(
                            'View All',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: CeladonColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 5. Tasks List
                  _buildTaskRow(
                    icon: Icons.design_services_outlined,
                    iconColor: const Color(0xFF0284C7),
                    iconBg: const Color(0xFFE0F2FE),
                    title: 'UI Design Review',
                    time: '10:00 AM - 11:00 AM',
                    priority: 'High',
                    priorityColor: const Color(0xFFEF4444),
                    priorityBg: const Color(0xFFFEE2E2),
                    onTap: () => onNavigateToTab?.call(1),
                  ),
                  const SizedBox(height: 10),
                  _buildTaskRow(
                    icon: Icons.meeting_room_outlined,
                    iconColor: const Color(0xFFD97706),
                    iconBg: const Color(0xFFFEF3C7),
                    title: 'Team Meeting',
                    time: '01:00 PM - 02:00 PM',
                    priority: 'Low',
                    priorityColor: const Color(0xFF0284C7),
                    priorityBg: const Color(0xFFE0F2FE),
                    onTap: () => onNavigateToTab?.call(1),
                  ),
                  const SizedBox(height: 10),
                  _buildTaskRow(
                    icon: Icons.edit_document,
                    iconColor: const Color(0xFF8B5CF6),
                    iconBg: const Color(0xFFEDE9FE),
                    title: 'Update Documentation',
                    time: '03:00 PM - 04:30 PM',
                    priority: 'Medium',
                    priorityColor: const Color(0xFFD97706),
                    priorityBg: const Color(0xFFFEF3C7),
                    onTap: () => onNavigateToTab?.call(1),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Premium Office Header matching the Reference Image:
  /// - Realistic modern office desk background with desktop computer & warm natural window lighting
  /// - Deep forest-green translucent brand overlay
  /// - Top Bar: Hamburger menu on left, Notification icon on right
  /// - Employee Greeting: Circular Initial Avatar, "Good Morning," subtitle, bold Employee Name, Role
  /// - Rounded Date Container on the right ("Mon, 20 Oct 2026")
  Widget _buildOfficeHeader(BuildContext context, String displayName) {
    final roleName = user.roleDisplayName.isNotEmpty ? user.roleDisplayName : 'Employee';

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
            // Realistic AI-generated office workstation background with computer, keyboard, desk plants
            Positioned.fill(
              child: Image.asset(
                'assets/images/office_dashboard_header.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
              ),
            ),

            // Subtle, translucent Emerald/Forest Green Brand Tint
            // Keeps the bright office desk, monitor, keyboard, plants, and window daylight clearly visible
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF0F3A2E).withValues(alpha: 0.54),
                      const Color(0xFF1B4332).withValues(alpha: 0.35),
                      const Color(0xFF0F3A2E).withValues(alpha: 0.58),
                    ],
                  ),
                ),
              ),
            ),

            // Header Content
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Bar: Hamburger Menu (Left) and Notification Bell (Right)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            icon: const Icon(
                              Icons.menu_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                            tooltip: 'Menu',
                            onPressed: () {
                              if (onOpenDrawer != null) {
                                onOpenDrawer!();
                              } else {
                                Scaffold.maybeOf(context)?.openDrawer();
                              }
                            },
                          ),
                        ),
                        Stack(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                icon: const Icon(
                                  Icons.notifications_none_rounded,
                                  size: 22,
                                  color: Colors.white,
                                ),
                                onPressed: () {
                                  if (onNotificationTap != null) {
                                    onNotificationTap!();
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('You have 1 new announcement from HR'),
                                        backgroundColor: CeladonColors.primary,
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFEF4444),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Greeting Row: Circular Avatar + Name/Role on left, Date Pill on right
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // User Avatar Initial or Photo
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            color: CeladonColors.primaryContainer,
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x28000000),
                                blurRadius: 10,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: user.avatar != null && user.avatar!.isNotEmpty
                                ? _buildAvatarImage(user.avatar!, displayName)
                                : Center(
                                    child: Text(
                                      displayName.isNotEmpty ? displayName.substring(0, 1).toUpperCase() : 'A',
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        color: CeladonColors.primaryDark,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Greeting and Name
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Good Morning,',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFD8F3DC),
                                  shadows: [
                                    Shadow(
                                      offset: Offset(0, 1),
                                      blurRadius: 3,
                                      color: Color(0x66000000),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 19.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(
                                      offset: Offset(0, 1.2),
                                      blurRadius: 4,
                                      color: Color(0x77000000),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                roleName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFE8F3ED),
                                  shadows: [
                                    Shadow(
                                      offset: Offset(0, 1),
                                      blurRadius: 3,
                                      color: Color(0x66000000),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Rounded Date Container matching the reference design
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.28), width: 1.2),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(
                                Icons.calendar_today_rounded,
                                size: 13,
                                color: Colors.white,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Mon, 20 Oct 2026',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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

  Widget _buildAvatarImage(String avatarUrl, String displayName) {
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
          displayName.isNotEmpty ? displayName.substring(0, 1).toUpperCase() : 'A',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: CeladonColors.primaryDark,
          ),
        ),
      ),
    );
  }

  Widget _buildTotalEmployeesCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: CeladonColors.primaryDark,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x180F3A2E),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.groups_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                '128',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              Text(
                'Total Employees',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFB5D6C3),
                ),
              ),
            ],
          ),
          const Spacer(),
          const Icon(
            Icons.bar_chart_rounded,
            color: Color(0xFF52B788),
            size: 32,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String count,
    required String label,
    required Color valueColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: CeladonColors.borderLight),
          boxShadow: const [
            BoxShadow(
              color: Color(0x062D6A4F),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  count,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: valueColor,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: CeladonColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskRow({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String time,
    required String priority,
    required Color priorityColor,
    required Color priorityBg,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: CeladonColors.borderLight),
          boxShadow: const [
            BoxShadow(
              color: Color(0x062D6A4F),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: CeladonColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        time,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: CeladonColors.textMuted,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: priorityBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          priority,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: priorityColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: CeladonColors.textMuted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
