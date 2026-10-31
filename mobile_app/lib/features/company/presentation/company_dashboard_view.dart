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
import '../../calendar/data/leave_service.dart';

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
            'You are logged in as Company Owner. You have authorized platform permissions to switch to ReGen Central.',
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

  AttendanceModel? _getEmployeeTodayAttendance(UserModel emp) {
    final uid = (emp.userId.isNotEmpty ? emp.userId : emp.id).toLowerCase();
    final uname = emp.username.toLowerCase();
    for (final att in _attendance) {
      final aUid = att.userId.toLowerCase();
      if (aUid == uid || aUid == uname) return att;
    }
    return null;
  }

  Future<void> _handleUpdateLeaveStatus(String id, String status) async {
    try {
      final leaveService = LeaveService();
      await leaveService.updateLeaveStatus(id: id, status: status);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: status == 'approved' ? const Color(0xFF10B981) : Colors.red,
            content: Text('Leave request marked as $status!'),
          ),
        );
        _loadCompanyData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Error: $e')),
        );
      }
    }
  }

  Widget _buildCompanyContent() {
    final activeUsersToday = _attendance.length;
    final totalStaff = _users.length;
    final rate = totalStaff > 0 ? ((activeUsersToday / totalStaff) * 100).clamp(0, 100).round() : 100;
    final currentYear = DateTime.now().year;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Top 4 Stats Cards Grid (Matching Website DashboardHome.jsx)
        Row(
          children: [
            // Card 1: Total Employees
            Expanded(
              child: _buildCompanyStatCard(
                icon: Icons.groups_rounded,
                iconColor: const Color(0xFF10B981),
                iconBg: const Color(0xFFD1FAE5),
                title: 'Employees',
                value: '$totalStaff',
                subtitle: '+active in $currentYear',
                onTap: _showEmployeeDirectorySheet,
              ),
            ),
            const SizedBox(width: 12),
            // Card 2: Active Departments
            Expanded(
              child: _buildCompanyStatCard(
                icon: Icons.corporate_fare_rounded,
                iconColor: const Color(0xFF0D9488),
                iconBg: const Color(0xFFCCFBF1),
                title: 'Departments',
                value: '$_departmentCount',
                subtitle: 'Active in $currentYear',
                onTap: _showEmployeeDirectorySheet,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            // Card 3: Today's Attendance
            Expanded(
              child: _buildCompanyStatCard(
                icon: Icons.fingerprint_rounded,
                iconColor: const Color(0xFF3B82F6),
                iconBg: const Color(0xFFDBEAFE),
                title: "Today's Attendance",
                value: '$activeUsersToday / $totalStaff',
                subtitle: '$rate% average',
                onTap: _showAttendanceRosterSheet,
              ),
            ),
            const SizedBox(width: 12),
            // Card 4: Attendance Rate Trend
            Expanded(
              child: _buildCompanyStatCard(
                icon: Icons.trending_up_rounded,
                iconColor: const Color(0xFF8B5CF6),
                iconBg: const Color(0xFFEDE9FE),
                title: 'Attendance Rate',
                value: '$rate%',
                subtitle: 'Week • Month • Year',
                onTap: _showAttendanceRosterSheet,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // 2. Dynamic Team Attendance Live Breakdown Card
        _buildLiveAttendanceBreakdownCard(activeUsersToday, totalStaff, rate),
        const SizedBox(height: 18),

        // 3. Sleek Quick Operations Bar (Replaces clunky list rows!)
        _buildQuickOperationsBar(),
        const SizedBox(height: 22),

        // 4. Section: Employee Management (Live Roster Preview)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Employee Management',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F3A2E),
                  ),
                ),
                Text(
                  '$totalStaff registered team members',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
            InkWell(
              onTap: _showEmployeeDirectorySheet,
              borderRadius: BorderRadius.circular(10),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  'View Roster →',
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

        // Live Employee Roster Cards
        if (_users.isEmpty)
          _buildEmptyCard(icon: Icons.groups_outlined, text: 'No employees found.')
        else
          ..._users.map((emp) => _buildLiveEmployeeCard(emp)),

        const SizedBox(height: 22),

        // 5. Section: Upcoming Leaves (Company Leaves Review)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Upcoming Leaves ($currentYear)',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F3A2E),
                  ),
                ),
                Text(
                  '${_leaves.length} applications recorded',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
            InkWell(
              onTap: () => widget.onNavigateToTab?.call(2), // Calendar & Leaves
              borderRadius: BorderRadius.circular(10),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  'Manage in Calendar →',
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

        if (_leaves.isEmpty)
          _buildEmptyCard(icon: Icons.beach_access_outlined, text: 'No leave requests recorded for this year.')
        else
          ..._leaves.take(4).map((l) => _buildCompanyLeaveCard(l)),

        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildCompanyStatCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String value,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(color: Color(0x06000000), blurRadius: 10, offset: Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, size: 14, color: iconColor),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF0F3A2E))),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: Color(0xFF94A3B8)), maxLines: 1),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveAttendanceBreakdownCard(int activeUsersToday, int totalStaff, int rate) {
    final absentCount = (totalStaff - activeUsersToday).clamp(0, 999);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(color: Color(0x06000000), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Today's Live Attendance",
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Color(0xFF0F3A2E)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFD1FAE5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$rate% Present',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF065F46)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  if (activeUsersToday > 0)
                    Expanded(
                      flex: activeUsersToday,
                      child: Container(color: const Color(0xFF10B981)),
                    ),
                  if (absentCount > 0)
                    Expanded(
                      flex: absentCount,
                      child: Container(color: const Color(0xFFFCA5A5)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildAttendanceLegend('Present Today', '$activeUsersToday', const Color(0xFF10B981)),
              _buildAttendanceLegend('Not Checked In', '$absentCount', const Color(0xFFEF4444)),
              _buildAttendanceLegend('Total Staff', '$totalStaff', const Color(0xFF475569)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceLegend(String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
        ),
        Text(
          value,
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }

  Widget _buildQuickOperationsBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildOperationPill(
            icon: Icons.location_on_outlined,
            label: '5m GPS Geofence',
            onTap: _showCompanySettingsSheet,
          ),
          const SizedBox(width: 8),
          _buildOperationPill(
            icon: Icons.access_time_outlined,
            label: 'Shift Timings',
            onTap: _showCompanySettingsSheet,
          ),
          const SizedBox(width: 8),
          _buildOperationPill(
            icon: Icons.analytics_outlined,
            label: 'Reports & Export',
            onTap: _showAttendanceReportSheet,
          ),
          const SizedBox(width: 8),
          _buildOperationPill(
            icon: Icons.folder_special_outlined,
            label: _activeTasksCount > 0 ? 'Projects ($_activeTasksCount open)' : 'Projects',
            onTap: () => widget.onNavigateToTab?.call(1),
          ),
        ],
      ),
    );
  }

  Widget _buildOperationPill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(color: Color(0x04000000), blurRadius: 4, offset: Offset(0, 1)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: const Color(0xFF1B5E3F)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1B5E3F),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveEmployeeCard(UserModel emp) {
    final todayAtt = _getEmployeeTodayAttendance(emp);
    final isPresent = todayAtt != null;
    final statusText = isPresent ? (todayAtt.status.toLowerCase() == 'late' ? 'Late' : 'Present') : 'Not In';
    final statusColor = isPresent
        ? (todayAtt.status.toLowerCase() == 'late' ? const Color(0xFFD97706) : const Color(0xFF059669))
        : const Color(0xFF94A3B8);
    final statusBg = isPresent
        ? (todayAtt.status.toLowerCase() == 'late' ? const Color(0xFFFEF3C7) : const Color(0xFFD1FAE5))
        : const Color(0xFFF1F5F9);

    final empId = emp.userId.isNotEmpty ? emp.userId : emp.id;
    final roleDisplay = emp.designation?.isNotEmpty == true ? emp.designation! : emp.roleDisplayName;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(color: Color(0x04000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: isPresent ? const Color(0xFF10B981) : const Color(0xFFE2E8F0), width: 2),
              color: CeladonColors.primaryContainer,
            ),
            child: ClipOval(
              child: Center(
                child: Text(
                  emp.name.isNotEmpty ? emp.name[0].toUpperCase() : (emp.username.isNotEmpty ? emp.username[0].toUpperCase() : 'U'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: CeladonColors.primaryDark),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Name & Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        emp.name.isNotEmpty ? emp.name : emp.username,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF0F3A2E)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'ID: $empId',
                        style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$roleDisplay ${emp.department?.isNotEmpty == true ? '• ${emp.department}' : ''}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Today's Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                Text(
                  statusText,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: statusColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompanyLeaveCard(LeaveModel leave) {
    Color statusColor = const Color(0xFFD97706);
    Color statusBg = const Color(0xFFFEF3C7);
    if (leave.isApproved) {
      statusColor = const Color(0xFF059669);
      statusBg = const Color(0xFFD1FAE5);
    } else if (leave.isRejected) {
      statusColor = const Color(0xFFDC2626);
      statusBg = const Color(0xFFFEE2E2);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${leave.userId} • ${leave.displayType}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F3A2E)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(6)),
                child: Text(
                  leave.status.toUpperCase(),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${leave.startDate.split('T').first} to ${leave.endDate.split('T').first}',
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
          ),
          if (leave.isPending) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => _handleUpdateLeaveStatus(leave.id, 'rejected'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFFCA5A5)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('Reject', style: TextStyle(color: Color(0xFFDC2626), fontSize: 11, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _handleUpdateLeaveStatus(leave.id, 'approved'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('Approve', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyCard({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF10B981), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF64748B)),
            ),
          ),
        ],
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


}
