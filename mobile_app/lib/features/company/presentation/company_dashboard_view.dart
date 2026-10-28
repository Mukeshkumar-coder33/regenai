import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../auth/data/user_model.dart';

/// Screen 8: Company Dashboard
///
/// Reproduces Screen 8 from the "8. Premium Celadon" design specification:
/// - Company header: ReGen logo badge, "ReGen Technologies", "Chennai, India", search & notification bell
/// - Overview statistics card: "128 Employees" & "12 Departments"
/// - Operations menu list:
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
    final location = 'Chennai, India';

    return Scaffold(
      backgroundColor: CeladonColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Company Header
              Row(
                children: [
                  if (onBack != null)
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 20,
                        color: CeladonColors.textPrimary,
                      ),
                      onPressed: onBack,
                    )
                  else
                    const SizedBox(width: 4),

                  // Company Logo Badge
                  const BrandLogo(
                    size: 42,
                    borderRadius: 12,
                    backgroundColor: CeladonColors.primaryDark,
                  ),
                  const SizedBox(width: 12),

                  // Company Title & Location
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          companyName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: CeladonColors.textPrimary,
                          ),
                        ),
                        Text(
                          location,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: CeladonColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Search Action
                  IconButton(
                    icon: const Icon(
                      Icons.search_rounded,
                      size: 22,
                      color: CeladonColors.textPrimary,
                    ),
                    onPressed: () {},
                  ),

                  // Bell Notification with Dot
                  Stack(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.notifications_none_rounded,
                          size: 22,
                          color: CeladonColors.textPrimary,
                        ),
                        onPressed: () {},
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
              const SizedBox(height: 20),

              // 2. Summary Stats Card: "128 Employees" & "12 Departments"
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
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
              ),
              const SizedBox(height: 22),

              // 3. Management Menu Rows
              _buildCompanyMenuItem(
                context: context,
                icon: Icons.badge_outlined,
                title: 'Employee Management',
                onTap: () => _showModuleInfo(context, 'Employee Management'),
              ),
              _buildCompanyMenuItem(
                context: context,
                icon: Icons.event_available_outlined,
                title: 'Attendance',
                onTap: () => onNavigateToTab?.call(2),
              ),
              _buildCompanyMenuItem(
                context: context,
                icon: Icons.event_busy_outlined,
                title: 'Leaves',
                onTap: () => _showModuleInfo(context, 'Leave Approvals'),
              ),
              _buildCompanyMenuItem(
                context: context,
                icon: Icons.payments_outlined,
                title: 'Payroll',
                onTap: () => _showModuleInfo(context, 'Payroll Processing'),
              ),
              _buildCompanyMenuItem(
                context: context,
                icon: Icons.analytics_outlined,
                title: 'Reports',
                onTap: () => _showModuleInfo(context, 'Workforce Analytics'),
              ),
              _buildCompanyMenuItem(
                context: context,
                icon: Icons.settings_outlined,
                title: 'Settings',
                onTap: () => _showModuleInfo(context, 'Company Configuration'),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompanyMenuItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: CeladonColors.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: CeladonColors.primary, size: 20),
          ),
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
            size: 20,
          ),
        ),
      ),
    );
  }

  void _showModuleInfo(BuildContext context, String module) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$module connected to ReGen Cloud Engine.'),
        backgroundColor: CeladonColors.primary,
      ),
    );
  }
}
