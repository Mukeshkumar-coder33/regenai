import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../auth/data/user_model.dart';

/// Screen 8: Company Dashboard (Premium Modern Office Theme)
///
/// Applied unified ReGen design language:
/// - Reuses exact Dashboard background image (`assets/images/office_dashboard_header.png`)
/// - Authenticated Company Admin/Owner profile avatar or brand logo badge
/// - Company header: Company name, location, search and notification icons
/// - 2x2 Overview statistics grid (Employees, Departments, Active Shifts, On Leave)
/// - Polished white management operation tiles with soft rounded icons:
///   * Employee Management
///   * Attendance
///   * Leaves
///   * Payroll
///   * Reports
///   * Settings
class CompanyDashboardView extends StatelessWidget {
  final UserModel user;
  final VoidCallback? onBack;
  final void Function(int tabIndex)? onNavigateToTab;

  const CompanyDashboardView({
    super.key,
    required this.user,
    this.onBack,
    this.onNavigateToTab,
  });

  @override
  Widget build(BuildContext context) {
    final companyName = user.companyName ?? 'ReGen Technologies';
    final roleName = user.roleDisplayName;
    final displayName = user.name.isNotEmpty
        ? user.name
        : (user.username.isNotEmpty ? user.username : 'Company Admin');

    return Scaffold(
      backgroundColor: CeladonColors.background,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Executive Corporate Header matching ReGen Theme
            _buildCompanyHeader(context, companyName, roleName, displayName),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 2. Summary Stats Card: 128 Employees & 12 Departments
                  _buildStatsSummaryCard(),
                  const SizedBox(height: 14),

                  // 3. 2x2 Operation Metric Cards
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricTile(
                          icon: Icons.event_available_rounded,
                          iconBg: CeladonColors.primaryContainer,
                          iconColor: CeladonColors.primary,
                          count: '118',
                          label: 'Checked In',
                          onTap: () => onNavigateToTab?.call(2),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _buildMetricTile(
                          icon: Icons.beach_access_rounded,
                          iconBg: const Color(0xFFFEE2E2),
                          iconColor: const Color(0xFFEF4444),
                          count: '6',
                          label: 'On Leave',
                          onTap: () => _showModuleInfo(context, 'Leave Approvals'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 4. Section Title: "Management & Operations"
                  const Text(
                    'Management & Operations',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: CeladonColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 5. Management Menu Rows
                  _buildCompanyMenuItem(
                    context: context,
                    icon: Icons.badge_outlined,
                    iconBg: const Color(0xFFE0F2FE),
                    iconColor: const Color(0xFF0284C7),
                    title: 'Employee Management',
                    subtitle: 'Manage 128 staff, departments, and roles',
                    onTap: () => _showModuleInfo(context, 'Employee Management'),
                  ),
                  _buildCompanyMenuItem(
                    context: context,
                    icon: Icons.event_available_outlined,
                    iconBg: CeladonColors.primaryContainer,
                    iconColor: CeladonColors.primary,
                    title: 'Attendance Monitoring',
                    subtitle: 'Live check-in times and geofencing logs',
                    onTap: () => onNavigateToTab?.call(2),
                  ),
                  _buildCompanyMenuItem(
                    context: context,
                    icon: Icons.event_busy_outlined,
                    iconBg: const Color(0xFFFEF3C7),
                    iconColor: const Color(0xFFD97706),
                    title: 'Leave Approvals',
                    subtitle: '3 pending requests awaiting sign-off',
                    onTap: () => _showModuleInfo(context, 'Leave Approvals'),
                  ),
                  _buildCompanyMenuItem(
                    context: context,
                    icon: Icons.payments_outlined,
                    iconBg: const Color(0xFFDCFCE7),
                    iconColor: const Color(0xFF15803D),
                    title: 'Payroll & Compensation',
                    subtitle: 'Monthly salary disbursements and tax receipts',
                    onTap: () => _showModuleInfo(context, 'Payroll Processing'),
                  ),
                  _buildCompanyMenuItem(
                    context: context,
                    icon: Icons.analytics_outlined,
                    iconBg: const Color(0xFFF3E8FF),
                    iconColor: const Color(0xFFA855F7),
                    title: 'Workforce Analytics',
                    subtitle: 'Departmental efficiency and attendance trends',
                    onTap: () => _showModuleInfo(context, 'Workforce Analytics'),
                  ),
                  _buildCompanyMenuItem(
                    context: context,
                    icon: Icons.settings_outlined,
                    iconBg: const Color(0xFFF1F5F9),
                    iconColor: const Color(0xFF475569),
                    title: 'Company Settings',
                    subtitle: 'Shift hours, company holidays, and policies',
                    onTap: () => _showModuleInfo(context, 'Company Configuration'),
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

  /// Unified Executive Corporate Header
  Widget _buildCompanyHeader(
    BuildContext context,
    String companyName,
    String roleName,
    String displayName,
  ) {
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

            // Subtle emerald overlay gradient
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF0F3A2E).withValues(alpha: 0.58),
                      const Color(0xFF1B4332).withValues(alpha: 0.40),
                      const Color(0xFF0F3A2E).withValues(alpha: 0.65),
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
                    // Top Bar: Back/Menu icon & Action icons
                    Row(
                      children: [
                        if (onBack != null)
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
                                Icons.arrow_back_ios_new_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                              onPressed: onBack,
                            ),
                          )
                        else
                          const BrandLogo(
                            size: 40,
                            borderRadius: 12,
                          ),
                        const SizedBox(width: 12),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                companyName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 17.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                roleName,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFB5D6C3),
                                ),
                              ),
                            ],
                          ),
                        ),

                        IconButton(
                          icon: const Icon(
                            Icons.notifications_none_rounded,
                            size: 22,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('No new company alerts.'),
                                backgroundColor: CeladonColors.primary,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Admin User Greeting & Avatar Row
                    Row(
                      children: [
                        // Authenticated Admin Avatar
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
                                      displayName.isNotEmpty
                                          ? displayName.substring(0, 1).toUpperCase()
                                          : 'C',
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

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Workspace Admin',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFD8F3DC),
                                ),
                              ),
                              Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Active Enterprise Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.verified_rounded, size: 14, color: Color(0xFF34D399)),
                              SizedBox(width: 5),
                              Text(
                                'Active EMS',
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
          displayName.isNotEmpty ? displayName.substring(0, 1).toUpperCase() : 'C',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: CeladonColors.primaryDark,
          ),
        ),
      ),
    );
  }

  /// Primary Summary Card matching the UI design language
  Widget _buildStatsSummaryCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  '128',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: CeladonColors.textPrimary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Employees',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: CeladonColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: CeladonColors.divider,
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  '12',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: CeladonColors.textPrimary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Departments',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: CeladonColors.textSecondary,
                  ),
                ),
              ],
            ),
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
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    count,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: CeladonColors.textPrimary,
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompanyMenuItem({
    required BuildContext context,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: CeladonColors.borderLight),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
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
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: CeladonColors.textSecondary,
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
        ),
      ),
    );
  }

  void _showModuleInfo(BuildContext context, String moduleName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$moduleName module is active in the ReGen Enterprise cloud.'),
        backgroundColor: CeladonColors.primary,
      ),
    );
  }
}
