import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../auth/data/user_model.dart';

/// Screen 3: Employee Dashboard
///
/// Reproduces Screen 3 from the "8. Premium Celadon" design specification:
/// - Header with circular avatar, "Good Morning, `Name`", and notification bell with red badge
/// - Date display pill ("Mon, 20 Oct 2026")
/// - Total Employees card with green icon badge
/// - 2x2 grid of metric cards: Present (3), On Leave (2), Tasks (5), Departments (12)
/// - "Today's Tasks" list with color-coded status badges and schedule times
class EmployeeDashboardView extends StatelessWidget {
  final UserModel user;
  final VoidCallback? onNotificationTap;
  final void Function(int tabIndex)? onNavigateToTab;

  const EmployeeDashboardView({
    super.key,
    required this.user,
    this.onNotificationTap,
    this.onNavigateToTab,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = user.name.isNotEmpty ? user.name : 'Alex Johnson';

    return Scaffold(
      backgroundColor: CeladonColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header Bar: Avatar, Greeting, Bell
              Row(
                children: [
                  // User Avatar
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: CeladonColors.border, width: 2),
                      color: CeladonColors.primaryContainer,
                    ),
                    child: ClipOval(
                      child: Center(
                        child: Text(
                          displayName.substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: CeladonColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Greeting & Name
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Good Morning,',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: CeladonColors.textSecondary,
                          ),
                        ),
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: CeladonColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Bell Notification with Badge
                  Stack(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: CeladonColors.borderLight),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x0A2D6A4F),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: const Icon(
                            Icons.notifications_none_rounded,
                            size: 22,
                            color: CeladonColors.textPrimary,
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
                        top: 2,
                        right: 2,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            '1',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // 2. Date Pill: "Mon, 20 Oct 2026"
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: CeladonColors.borderLight),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(
                          Icons.calendar_today_rounded,
                          size: 13,
                          color: CeladonColors.primary,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Mon, 20 Oct 2026',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: CeladonColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 3. Primary Card: "128 Total Employees"
              _buildWhiteCard(
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: CeladonColors.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.groups_rounded,
                        color: CeladonColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          '128',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: CeladonColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Total Employees',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: CeladonColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 4. 2x2 Metric Cards Grid (Present, On Leave, Tasks, Departments)
              Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      icon: Icons.work_outline_rounded,
                      iconBg: CeladonColors.primaryContainer,
                      iconColor: CeladonColors.primary,
                      count: '3',
                      label: 'Present',
                      valueColor: CeladonColors.textPrimary,
                      onTap: () => onNavigateToTab?.call(2), // go to Attendance
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildMetricTile(
                      icon: Icons.favorite_border_rounded,
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
                      icon: Icons.checklist_rounded,
                      iconBg: CeladonColors.primaryContainer,
                      iconColor: CeladonColors.primary,
                      count: '5',
                      label: 'Tasks',
                      valueColor: CeladonColors.textPrimary,
                      onTap: () => onNavigateToTab?.call(1), // go to Tasks
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildMetricTile(
                      icon: Icons.apartment_rounded,
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

              // 5. Section Header: "Today's Tasks"
              const Text(
                "Today's Tasks",
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: CeladonColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),

              // Tasks List matching Screen 3:
              // - UI Design Review (10:00 AM - 11:00 AM)
              // - Team Meeting (01:00 PM - 02:00 PM)
              // - Update Documentation (03:00 PM - 04:30 PM)
              _buildTaskRow(
                icon: Icons.design_services_outlined,
                iconColor: const Color(0xFF0284C7),
                iconBg: const Color(0xFFE0F2FE),
                title: 'UI Design Review',
                time: '10:00 AM - 11:00 AM',
                onTap: () => onNavigateToTab?.call(1),
              ),
              const SizedBox(height: 10),
              _buildTaskRow(
                icon: Icons.groups_outlined,
                iconColor: const Color(0xFFD97706),
                iconBg: const Color(0xFFFEF3C7),
                title: 'Team Meeting',
                time: '01:00 PM - 02:00 PM',
                onTap: () => onNavigateToTab?.call(1),
              ),
              const SizedBox(height: 10),
              _buildTaskRow(
                icon: Icons.article_outlined,
                iconColor: const Color(0xFF8B5CF6),
                iconBg: const Color(0xFFEDE9FE),
                title: 'Update Documentation',
                time: '03:00 PM - 04:30 PM',
                onTap: () => onNavigateToTab?.call(1),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWhiteCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
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
      child: child,
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
            const SizedBox(height: 12),
            Text(
              count,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: valueColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: CeladonColors.textSecondary,
              ),
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
              color: Color(0x052D6A4F),
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
                  const SizedBox(height: 3),
                  Text(
                    time,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: CeladonColors.textMuted,
                    ),
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
