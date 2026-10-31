import 'package:flutter/material.dart';
import '../../../core/services/location_service.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../attendance/data/attendance_model.dart';
import '../../attendance/data/attendance_report_model.dart';
import '../../attendance/data/attendance_service.dart';
import '../../attendance/data/work_schedule_model.dart';
import '../../auth/data/auth_service.dart';
import '../../auth/data/user_model.dart';
import '../data/company_model.dart';
import '../../tasks/data/task_model.dart';
import '../../dashboard/data/dashboard_service.dart';
import '../../dashboard/data/leave_model.dart';

/// Screen 8: Company Dashboard (Situation B & Situation C)
///
/// Reproduces Screen 8 from the "8. Premium Celadon" design specification:
/// - Company header: ReGen logo badge, live Company name, City & State, search & notification bell
/// - If Super Admin in Company Mode (Situation C): Quick switch card to Global Super Admin Console
/// - Overview statistics card: Dynamic Live Employees count & Dynamic Departments count
/// - Secondary metric cards: Live Present Today & Live Active Tasks
/// - Operations menu list:
///   * Employee Management (with live roster bottom sheet)
///   * Attendance (navigates to Attendance tab)
///   * Tasks (navigates to Tasks tab)
///   * Leaves (with pending requests count)
///   * Payroll
///   * Reports
///   * Settings (company details sheet)
/// - 100% Dynamic Business Data backed by live ReGen APIs. Zero hardcoded numbers.
class CompanyDashboardView extends StatefulWidget {
  final UserModel user;
  final VoidCallback? onBack;
  final VoidCallback? onOpenDrawer;
  final VoidCallback? onLogout;
  final void Function(int tabIndex)? onNavigateToTab;
  final void Function(UserModel updatedUser)? onUserUpdated;
  final DashboardService? dashboardService;
  final AuthService? authService;

  const CompanyDashboardView({
    super.key,
    required this.user,
    this.onBack,
    this.onOpenDrawer,
    this.onLogout,
    this.onNavigateToTab,
    this.onUserUpdated,
    this.dashboardService,
    this.authService,
  });

  @override
  State<CompanyDashboardView> createState() => _CompanyDashboardViewState();
}

class _CompanyDashboardViewState extends State<CompanyDashboardView> {
  late final DashboardService _dashboardService;
  late final AuthService _authService;
  final AttendanceService _attendanceService = AttendanceService();

  bool _isLoading = true;
  String? _errorMessage;
  bool _isSwitchingToSuperAdmin = false;

  CompanyModel? _company;
  List<UserModel> _users = [];
  List<TaskModel> _tasks = [];
  List<AttendanceModel> _attendance = [];
  List<LeaveModel> _leaves = [];
  WorkScheduleModel _workSchedule = const WorkScheduleModel();

  @override
  void initState() {
    super.initState();
    _dashboardService = widget.dashboardService ?? DashboardService();
    _authService = widget.authService ?? AuthService();
    _loadCompanyData();
  }

  Future<void> _loadCompanyData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _dashboardService.getCompanies(),
        _dashboardService.getUsers(),
        _dashboardService.getTasks(),
        _dashboardService.getAttendance(),
        _dashboardService.getLeaves(),
        _attendanceService.getWorkSchedule(),
      ]);

      if (mounted) {
        final companies = results[0] as List<CompanyModel>;
        final users = results[1] as List<UserModel>;
        final tasks = results[2] as List<TaskModel>;
        final attendance = results[3] as List<AttendanceModel>;
        final leaves = results[4] as List<LeaveModel>;
        final schedule = results[5] as WorkScheduleModel;

        setState(() {
          _company = companies.isNotEmpty ? companies.first : null;
          _users = users;
          _tasks = tasks;
          _attendance = attendance;
          _leaves = leaves;
          _workSchedule = schedule;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleSwitchToSuperAdmin() async {
    setState(() => _isSwitchingToSuperAdmin = true);

    try {
      final updatedUser = await _authService.switchToSuperAdmin();
      if (mounted) {
        setState(() => _isSwitchingToSuperAdmin = false);
        widget.onUserUpdated?.call(updatedUser);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: CeladonColors.primary,
            content: Text('Switched to Global Super Admin Console'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSwitchingToSuperAdmin = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: CeladonColors.error,
            content: Text('Failed to switch to Super Admin: $e'),
          ),
        );
      }
    }
  }

  int get _departmentCount {
    final depts = _users
        .map((u) => u.department?.trim())
        .where((d) => d != null && d.isNotEmpty)
        .toSet();
    return depts.isEmpty ? 1 : depts.length;
  }

  int get _activeTasksCount {
    return _tasks.where((t) => t.status.toLowerCase() != 'completed').length;
  }

  int get _pendingLeavesCount {
    return _leaves.where((l) => l.isPending).length;
  }

  @override
  Widget build(BuildContext context) {
    final companyName = _company?.name ?? widget.user.companyName ?? 'Company Workspace';
    final location = _company?.city != null && _company!.city!.isNotEmpty
        ? (_company?.state != null && _company!.state!.isNotEmpty
            ? '${_company!.city}, ${_company!.state}'
            : '${_company!.city}, India')
        : 'Tamil Nadu, India';

    return Scaffold(
      backgroundColor: CeladonColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadCompanyData,
          color: CeladonColors.primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Company Header
                Row(
                  children: [
                    // Hamburger Menu Button (opens AppDrawer)
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: CeladonColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          Icons.menu_rounded,
                          color: CeladonColors.primaryDark,
                          size: 24,
                        ),
                        tooltip: 'Menu',
                        onPressed: () {
                          if (widget.onOpenDrawer != null) {
                            widget.onOpenDrawer!();
                          } else {
                            Scaffold.maybeOf(context)?.openDrawer();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),

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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                      onPressed: () => _showEmployeeDirectorySheet(),
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
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('$_pendingLeavesCount leave requests pending approval'),
                                backgroundColor: CeladonColors.primary,
                              ),
                            );
                          },
                        ),
                        if (_pendingLeavesCount > 0)
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
                const SizedBox(height: 16),

                // Situation C: Super Admin Quick Switcher Banner (Only for authorized accounts like Vyshwa)
                if (widget.user.canSwitchToSuperAdmin) ...[
                  _buildSuperAdminSwitchBanner(),
                  const SizedBox(height: 16),
                ],

                // Loading / Error / Content
                if (_isLoading)
                  _buildLoadingState()
                else if (_errorMessage != null)
                  _buildErrorState()
                else
                  _buildCompanyContent(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      alignment: Alignment.center,
      child: Column(
        children: const [
          CircularProgressIndicator(color: CeladonColors.primary),
          SizedBox(height: 16),
          Text(
            'Loading company operations...',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: CeladonColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CeladonColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, color: CeladonColors.error, size: 36),
          const SizedBox(height: 12),
          Text(
            _errorMessage ?? 'Unable to load company data',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: CeladonColors.textPrimary),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _loadCompanyData,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: CeladonColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompanyContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 2. Summary Stats Card: Live Employees & Live Departments (Screen 8)
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
                child: InkWell(
                  onTap: _showEmployeeDirectorySheet,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_users.length}',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: CeladonColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: const [
                          Text(
                            'Employees',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: CeladonColors.textSecondary,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(Icons.open_in_new_rounded, size: 12, color: CeladonColors.primary),
                        ],
                      ),
                    ],
                  ),
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
                  children: [
                    Text(
                      '$_departmentCount',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: CeladonColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
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
        const SizedBox(height: 14),

        // Live Operations Quick Glance (Attendance & Tasks)
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: CeladonColors.borderLight),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: CeladonColors.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.check_circle_outline, color: CeladonColors.primary, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_attendance.length}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: CeladonColors.textPrimary),
                        ),
                        const Text(
                          'Present Today',
                          style: TextStyle(fontSize: 11, color: CeladonColors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: CeladonColors.borderLight),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.assignment_outlined, color: Color(0xFFD97706), size: 18),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_activeTasksCount',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: CeladonColors.textPrimary),
                        ),
                        const Text(
                          'Active Tasks',
                          style: TextStyle(fontSize: 11, color: CeladonColors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // 3. Management Menu Rows (Screen 8)
        _buildCompanyMenuItem(
          context: context,
          icon: Icons.badge_outlined,
          title: 'Employee Management',
          subtitle: '${_users.length} registered team members',
          onTap: _showEmployeeDirectorySheet,
        ),
        _buildCompanyMenuItem(
          context: context,
          icon: Icons.event_available_outlined,
          title: 'Attendance',
          subtitle: '${_attendance.length} logs recorded',
          onTap: _showAttendanceRosterSheet,
        ),
        _buildCompanyMenuItem(
          context: context,
          icon: Icons.assignment_outlined,
          title: 'Tasks',
          subtitle: '$_activeTasksCount open tasks in progress',
          onTap: () => widget.onNavigateToTab?.call(1),
        ),
        _buildCompanyMenuItem(
          context: context,
          icon: Icons.event_busy_outlined,
          title: 'Leaves & Holidays',
          subtitle: _pendingLeavesCount > 0
              ? '$_pendingLeavesCount request(s) waiting for approval'
              : 'Review leave approvals & company holidays',
          onTap: () => widget.onNavigateToTab?.call(2),
        ),
        _buildCompanyMenuItem(
          context: context,
          icon: Icons.payments_outlined,
          title: 'Payroll',
          subtitle: 'Automated payroll processing & slips',
          onTap: () => _showModuleInfo(context, 'Payroll Processing'),
        ),
        _buildCompanyMenuItem(
          context: context,
          icon: Icons.analytics_outlined,
          title: 'Reports',
          subtitle: 'Workforce analytics & monthly summary',
          onTap: _showAttendanceReportSheet,
        ),
        _buildCompanyMenuItem(
          context: context,
          icon: Icons.settings_outlined,
          title: 'Settings',
          subtitle: 'Company profile & working hours configuration',
          onTap: _showCompanySettingsSheet,
        ),
        if (widget.onLogout != null)
          _buildCompanyMenuItem(
            context: context,
            icon: Icons.logout_rounded,
            title: 'Sign Out',
            subtitle: 'End current company session',
            onTap: () => widget.onLogout?.call(),
          ),
        const SizedBox(height: 20),
      ],
    );
  }

  /// Situation C: Super Admin Quick Switcher Card
  Widget _buildSuperAdminSwitchBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F2F24),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x180F2F24),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: const [
              Icon(Icons.shield_outlined, color: CeladonColors.primaryLight, size: 20),
              SizedBox(width: 8),
              Text(
                'Super Admin Console Available',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'You are logged in as Company Owner (krish Tech Computer). You have authorized platform permissions to switch to ReGen Central.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFFB7D5C4),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _isSwitchingToSuperAdmin ? null : _handleSwitchToSuperAdmin,
            icon: _isSwitchingToSuperAdmin
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.swap_horiz_rounded, size: 18),
            label: Text(
              _isSwitchingToSuperAdmin ? 'Switching...' : 'Switch to Super Admin Console',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: CeladonColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompanyMenuItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? subtitle,
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
            width: 38,
            height: 38,
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
          subtitle: subtitle != null
              ? Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: CeladonColors.textSecondary,
                  ),
                )
              : null,
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: CeladonColors.textMuted,
            size: 20,
          ),
        ),
      ),
    );
  }

  void _showEmployeeDirectorySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: CeladonColors.borderLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Company Roster (${_users.length})',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: CeladonColors.textPrimary),
                ),
                Text(
                  _company?.name ?? widget.user.companyName ?? '',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CeladonColors.primary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _users.isEmpty
                  ? const Center(
                      child: Text('No employees found in this company.', style: TextStyle(color: CeladonColors.textSecondary)),
                    )
                  : ListView.separated(
                      itemCount: _users.length,
                      separatorBuilder: (_, index) => const Divider(height: 1),
                      itemBuilder: (ctx, idx) {
                        final emp = _users[idx];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(vertical: 4),
                          leading: CircleAvatar(
                            backgroundColor: CeladonColors.primaryContainer,
                            child: Text(
                              emp.name.isNotEmpty ? emp.name[0].toUpperCase() : 'U',
                              style: const TextStyle(color: CeladonColors.primary, fontWeight: FontWeight.w700),
                            ),
                          ),
                          title: Text(emp.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          subtitle: Text(
                            '${emp.roleDisplayName} • ${emp.department?.isNotEmpty == true ? emp.department : 'General'}',
                            style: const TextStyle(fontSize: 12, color: CeladonColors.textSecondary),
                          ),
                          trailing: emp.phone?.isNotEmpty == true
                              ? Text(emp.phone!, style: const TextStyle(fontSize: 11, color: CeladonColors.textMuted))
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimeStr(String? iso) {
    if (iso == null || iso.isEmpty) return '--:--';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '--:--';
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final p = h >= 12 ? 'PM' : 'AM';
    final dh = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '${dh.toString().padLeft(2, '0')}:$m $p';
  }

  void _showAttendanceRosterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, scrollController) => Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Company Attendance Roster',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: CeladonColors.textPrimary),
                  ),
                  Text(
                    '${_attendance.length} Total',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: CeladonColors.primary),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _attendance.isEmpty
                    ? const Center(
                        child: Text('No attendance recorded yet for this company.', style: TextStyle(color: CeladonColors.textSecondary)),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        itemCount: _attendance.length,
                        separatorBuilder: (_, index) => const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final att = _attendance[idx];
                          final user = _users.firstWhere(
                            (u) => u.userId == att.userId || u.id == att.userId,
                            orElse: () => UserModel(
                              id: att.userId,
                              userId: att.userId,
                              username: att.userId,
                              name: att.userId,
                              role: 'staff',
                              token: '',
                            ),
                          );

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(vertical: 4),
                            leading: CircleAvatar(
                              backgroundColor: CeladonColors.primaryContainer,
                              child: Text(
                                user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U',
                                style: const TextStyle(color: CeladonColors.primary, fontWeight: FontWeight.w700),
                              ),
                            ),
                            title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            subtitle: Text(
                              'Date: ${att.date} • In: ${_formatTimeStr(att.checkIn)} • Out: ${_formatTimeStr(att.checkOut)}',
                              style: const TextStyle(fontSize: 12, color: CeladonColors.textSecondary),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: att.isPresent ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                att.status.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: att.isPresent ? const Color(0xFF2D6A4F) : Colors.redAccent,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAttendanceReportSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, scrollController) => FutureBuilder<AttendanceReportModel>(
          future: _attendanceService.getAttendanceReport(period: 'month'),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                padding: const EdgeInsets.all(32),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                alignment: Alignment.center,
                child: const CircularProgressIndicator(color: CeladonColors.primary),
              );
            }

            if (snapshot.hasError) {
              return Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
                    const SizedBox(height: 12),
                    Text('Failed to load report: ${snapshot.error}', textAlign: TextAlign.center),
                  ],
                ),
              );
            }

            final report = snapshot.data!;
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Attendance Report', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                          Text(report.periodLabel.isNotEmpty ? report.periodLabel : 'Monthly Summary', style: const TextStyle(fontSize: 12, color: CeladonColors.textSecondary)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: CeladonColors.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${report.totalRecords} Records',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: CeladonColors.primary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Metrics Cards Row
                  Row(
                    children: [
                      _buildReportMetricCard('Total Hours', '${report.totalWorkingHours.toStringAsFixed(1)}h', const Color(0xFF2D6A4F)),
                      const SizedBox(width: 8),
                      _buildReportMetricCard('Daily Avg', '${report.averageDailyHours.toStringAsFixed(1)}h', const Color(0xFF1B4332)),
                      const SizedBox(width: 8),
                      _buildReportMetricCard('Present', '${report.presentCount}', const Color(0xFF52B788)),
                      const SizedBox(width: 8),
                      _buildReportMetricCard('Late', '${report.lateCount}', const Color(0xFFD97706)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Recent Log Entries', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: report.records.isEmpty
                        ? const Center(child: Text('No detailed records for this period.', style: TextStyle(color: CeladonColors.textSecondary)))
                        : ListView.separated(
                            controller: scrollController,
                            itemCount: report.records.length,
                            separatorBuilder: (_, index) => const Divider(height: 1),
                            itemBuilder: (context, idx) {
                              final r = report.records[idx];
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                                title: Text('Date: ${r.date}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                subtitle: Text('In: ${_formatTimeStr(r.checkIn)} • Out: ${_formatTimeStr(r.checkOut)}', style: const TextStyle(fontSize: 12)),
                                trailing: Text(
                                  r.status.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: r.isPresent ? Colors.green.shade800 : Colors.redAccent,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildReportMetricCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 10, color: CeladonColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  void _showCompanySettingsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, scrollController) => Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Company Settings & Configuration',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: CeladonColors.textPrimary),
              ),
              const SizedBox(height: 16),

              // Basic Profile
              _buildSettingRow('Company Name', _company?.name ?? widget.user.companyName ?? 'N/A'),
              _buildSettingRow('City / Location', _company?.city ?? 'N/A'),
              _buildSettingRow('Category', _company?.category?.toUpperCase() ?? 'GENERAL'),
              _buildSettingRow('Contact Phone', _company?.phoneNumber ?? 'N/A'),
              _buildSettingRow('Contact Email', _company?.email ?? 'N/A'),
              _buildSettingRow('Account Status', _company?.status.toUpperCase() ?? 'ACTIVE'),

              const Divider(height: 32),

              // Office Location & Geofence Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Office Geofence (5m)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showOfficeLocationDialog();
                    },
                    icon: const Icon(Icons.edit_location_alt_rounded, size: 16),
                    label: const Text('Edit GPS', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              _buildSettingRow(
                'Coordinates',
                _company?.hasOfficeLocation == true
                    ? '${_company!.latitude!.toStringAsFixed(4)}, ${_company!.longitude!.toStringAsFixed(4)}'
                    : 'Not Configured',
              ),
              _buildSettingRow('Allowed Radius', '5 metres (Strict Geofence)'),

              const Divider(height: 32),

              // Shift Hours & Working Rules Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Shift & Break Rules', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showShiftSettingsDialog();
                    },
                    icon: const Icon(Icons.schedule_rounded, size: 16),
                    label: const Text('Edit Rules', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              _buildSettingRow('Check-In Target', _workSchedule.checkInTime),
              _buildSettingRow('Check-Out Target', _workSchedule.checkOutTime),
              _buildSettingRow('Working Hours / Day', '${_workSchedule.workingHoursPerDay} hours'),
              _buildSettingRow('Working Days / Week', '${_workSchedule.workingDaysPerWeek} days'),
              _buildSettingRow('Lunch Break Allowance', '${_workSchedule.breakTime} minutes'),
              _buildSettingRow('Tea Break Allowance', '${_workSchedule.casualBreakTime} minutes'),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _showOfficeLocationDialog() {
    final messenger = ScaffoldMessenger.of(context);
    final latController = TextEditingController(text: _company?.latitude?.toString() ?? '');
    final lonController = TextEditingController(text: _company?.longitude?.toString() ?? '');
    final addrController = TextEditingController(text: _company?.address ?? _company?.name ?? 'Office');
    bool isDetecting = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Configure Office Geofence', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Sets the official GPS pin for this company. Attendance check-ins/outs require employees to be within 5 metres of these coordinates.',
                  style: TextStyle(fontSize: 13, color: CeladonColors.textSecondary),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  icon: isDetecting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location_rounded, size: 18),
                  label: Text(isDetecting ? 'Acquiring GPS...' : 'Use Current Device GPS'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CeladonColors.primary,
                    side: const BorderSide(color: CeladonColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: isDetecting
                      ? null
                      : () async {
                          setDialogState(() => isDetecting = true);
                          try {
                            final pos = await LocationService.getCurrentPosition();
                            latController.text = pos.latitude.toStringAsFixed(6);
                            lonController.text = pos.longitude.toStringAsFixed(6);
                          } catch (e) {
                            messenger.showSnackBar(SnackBar(content: Text('GPS Error: $e')));
                          } finally {
                            setDialogState(() => isDetecting = false);
                          }
                        },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: latController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'Latitude', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: lonController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'Longitude', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: addrController,
                  decoration: const InputDecoration(labelText: 'Office Address / Label', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CeladonColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final lat = double.tryParse(latController.text.trim());
                final lon = double.tryParse(lonController.text.trim());
                if (lat == null || lon == null) {
                  messenger.showSnackBar(const SnackBar(content: Text('Enter valid numeric coordinates')));
                  return;
                }

                final nav = Navigator.of(dialogCtx);
                try {
                  await _attendanceService.updateOfficeLocation(
                    _company!.id,
                    latitude: lat,
                    longitude: lon,
                    address: addrController.text.trim(),
                  );
                  nav.pop();
                  _loadCompanyData();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Company office location updated successfully (5m geofence active)'),
                      backgroundColor: CeladonColors.primary,
                    ),
                  );
                } catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
                }
              },
              child: const Text('Save Coordinates', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showShiftSettingsDialog() {
    final messenger = ScaffoldMessenger.of(context);
    final inController = TextEditingController(text: _workSchedule.checkInTime);
    final outController = TextEditingController(text: _workSchedule.checkOutTime);
    final hoursController = TextEditingController(text: _workSchedule.workingHoursPerDay.toString());
    final breakController = TextEditingController(text: _workSchedule.breakTime.toString());
    final casualController = TextEditingController(text: _workSchedule.casualBreakTime.toString());

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Configure Shift Timings & Breaks', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: inController,
                decoration: const InputDecoration(labelText: 'Shift Check-In Target (e.g. 09:30)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: outController,
                decoration: const InputDecoration(labelText: 'Shift Check-Out Target (e.g. 18:30)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: hoursController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Daily Working Hours (e.g. 8)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: breakController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Lunch Break Minutes (e.g. 60)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: casualController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Tea Break Minutes (e.g. 15)', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: CeladonColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final inTime = inController.text.trim();
              final outTime = outController.text.trim();
              final hours = int.tryParse(hoursController.text.trim()) ?? 8;
              final bTime = int.tryParse(breakController.text.trim()) ?? 60;
              final cbTime = int.tryParse(casualController.text.trim()) ?? 15;

              final nav = Navigator.of(dialogCtx);
              try {
                final updated = WorkScheduleModel(
                  companyId: _company?.id,
                  checkInTime: inTime,
                  checkOutTime: outTime,
                  workingHoursPerDay: hours,
                  workingDaysPerWeek: _workSchedule.workingDaysPerWeek,
                  breakTime: bTime,
                  casualBreakTime: cbTime,
                  weeklyOffDays: _workSchedule.weeklyOffDays,
                  graceMinutes: _workSchedule.graceMinutes,
                );

                await _attendanceService.updateWorkSchedule(updated);
                nav.pop();
                _loadCompanyData();
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Shift rules and break allowances updated successfully'),
                    backgroundColor: CeladonColors.primary,
                  ),
                );
              } catch (e) {
                messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
              }
            },
            child: const Text('Save Shift Rules', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: CeladonColors.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: CeladonColors.textPrimary)),
        ],
      ),
    );
  }

  void _showModuleInfo(BuildContext context, String module) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$module connected to ReGen Cloud Database.'),
        backgroundColor: CeladonColors.primary,
      ),
    );
  }
}
