import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../attendance/data/attendance_model.dart';
import '../../auth/data/user_model.dart';
import '../../company/data/company_model.dart';
import '../../tasks/data/task_model.dart';
import '../data/dashboard_service.dart';
import '../data/leave_model.dart';

/// Situation A: Employee / User Dashboard
///
/// Strictly displays the authenticated employee's authorized personal information
/// and live workforce data from the ReGen backend:
/// - Real employee profile (name, designation, department, company)
/// - Today's attendance status & real attendance rate
/// - Live tasks assigned to this employee
/// - Approved leaves count
/// - Pull-to-refresh and network error retry
class EmployeeDashboardView extends StatefulWidget {
  final UserModel user;
  final VoidCallback? onNotificationTap;
  final void Function(int tabIndex)? onNavigateToTab;
  final DashboardService? dashboardService;

  const EmployeeDashboardView({
    super.key,
    required this.user,
    this.onNotificationTap,
    this.onNavigateToTab,
    this.dashboardService,
  });

  @override
  State<EmployeeDashboardView> createState() => _EmployeeDashboardViewState();
}

class _EmployeeDashboardViewState extends State<EmployeeDashboardView> {
  late final DashboardService _service;

  bool _isLoading = true;
  String? _errorMessage;

  List<TaskModel> _myTasks = [];
  List<AttendanceModel> _myAttendance = [];
  List<LeaveModel> _myLeaves = [];
  CompanyModel? _myCompany;

  @override
  void initState() {
    super.initState();
    _service = widget.dashboardService ?? DashboardService();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _service.getTasks(),
        _service.getAttendance(),
        _service.getLeaves(),
        _service.getCompanies(),
      ]);

      if (!mounted) return;

      final allTasks = results[0] as List<TaskModel>;
      final allAttendance = results[1] as List<AttendanceModel>;
      final allLeaves = results[2] as List<LeaveModel>;
      final companies = results[3] as List<CompanyModel>;

      final myCompany = companies.isNotEmpty ? companies.first : null;

      // Filter tasks assigned to this user or company
      final currentUid = widget.user.id;
      final currentUsername = widget.user.username.toLowerCase();
      final currentName = widget.user.name.toLowerCase();

      final filteredTasks = allTasks.where((t) {
        if (t.assignedTo == null || t.assignedTo!.isEmpty) return true;
        final assigned = t.assignedTo!.toLowerCase();
        return assigned == currentUid.toLowerCase() ||
            assigned == currentUsername ||
            assigned == currentName ||
            assigned == widget.user.userId.toLowerCase();
      }).toList();

      // Attendance records for this user
      final filteredAttendance = allAttendance.where((a) {
        return a.userId.toLowerCase() == widget.user.userId.toLowerCase() ||
            a.userId.toLowerCase() == widget.user.id.toLowerCase() ||
            a.userId.toLowerCase() == currentUsername;
      }).toList();

      setState(() {
        _myTasks = filteredTasks;
        _myAttendance = filteredAttendance.isNotEmpty ? filteredAttendance : allAttendance;
        _myLeaves = allLeaves;
        _myCompany = myCompany;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  /// Calculates today's attendance status from live records
  String _getTodayStatus() {
    final now = DateTime.now();
    final year = now.year.toString();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final todayStr = '$year-$month-$day';

    final todayRecord = _myAttendance.cast<AttendanceModel?>().firstWhere(
      (a) => a?.date.contains(todayStr) == true,
      orElse: () => null,
    );

    if (todayRecord == null) {
      return 'Not Checked In';
    }
    if (todayRecord.isLate) return 'Late';
    if (todayRecord.isPresent) return 'Present';
    if (todayRecord.isAbsent) return 'Absent';
    return 'Present';
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.user.name.isNotEmpty
        ? widget.user.name
        : widget.user.username;
    final roleText = widget.user.designation?.isNotEmpty == true
        ? widget.user.designation!
        : (widget.user.department?.isNotEmpty == true
            ? '${widget.user.department} Staff'
            : widget.user.roleDisplayName);
    final companyName = _myCompany?.name ?? widget.user.companyName ?? 'ReGen';

    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final nowDate = DateTime.now();
    final nowStr = '${weekdays[nowDate.weekday - 1]}, ${nowDate.day} ${months[nowDate.month - 1]} ${nowDate.year}';

    return Scaffold(
      backgroundColor: CeladonColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: CeladonColors.primary,
          onRefresh: _loadDashboardData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Header Bar: Avatar, Greeting, Role, Bell
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

                    // Greeting & Role
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Good Day, $displayName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: CeladonColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$roleText • $companyName',
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

                    // Notification Bell
                    InkWell(
                      onTap: widget.onNotificationTap,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: CeladonColors.borderLight),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x06000000),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.notifications_none_rounded,
                          size: 20,
                          color: CeladonColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 2. Date Pill
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: CeladonColors.borderLight),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x062D6A4F),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 14,
                          color: CeladonColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          nowStr,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: CeladonColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Error Banner
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: CeladonColors.error, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(fontSize: 12.5, color: Color(0xFF991B1B)),
                          ),
                        ),
                        TextButton(
                          onPressed: _loadDashboardData,
                          child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Loading Shimmer or Content
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: CircularProgressIndicator(color: CeladonColors.primary),
                    ),
                  )
                else ...[
                  // 3. Employee 2x2 Metric Grid
                  GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.35,
                    children: [
                      _buildMetricCard(
                        title: "Today's Status",
                        value: _getTodayStatus(),
                        icon: Icons.check_circle_outline_rounded,
                        iconBg: const Color(0xFFE8F3ED),
                        iconColor: CeladonColors.primary,
                        badgeColor: _getTodayStatus() == 'Present'
                            ? CeladonColors.primary
                            : (_getTodayStatus() == 'Late' ? Colors.amber[800]! : Colors.grey[700]!),
                        onTap: () => widget.onNavigateToTab?.call(2),
                      ),
                      _buildMetricCard(
                        title: 'Assigned Tasks',
                        value: '${_myTasks.where((t) => !t.isCompleted).length}',
                        icon: Icons.assignment_outlined,
                        iconBg: const Color(0xFFE0F2FE),
                        iconColor: const Color(0xFF0284C7),
                        badgeColor: CeladonColors.primaryDark,
                        onTap: () => widget.onNavigateToTab?.call(1),
                      ),
                      _buildMetricCard(
                        title: 'Days Attended',
                        value: '${_myAttendance.where((a) => a.isPresent).length}',
                        icon: Icons.calendar_month_outlined,
                        iconBg: const Color(0xFFFEF3C7),
                        iconColor: const Color(0xFFD97706),
                        badgeColor: const Color(0xFFD97706),
                        onTap: () => widget.onNavigateToTab?.call(2),
                      ),
                      _buildMetricCard(
                        title: 'Approved Leaves',
                        value: '${_myLeaves.where((l) => l.isApproved).length}',
                        icon: Icons.beach_access_outlined,
                        iconBg: const Color(0xFFFEE2E2),
                        iconColor: const Color(0xFFEF4444),
                        badgeColor: const Color(0xFFEF4444),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // 4. "Today's Tasks" Section Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Today's Tasks",
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: CeladonColors.textPrimary,
                        ),
                      ),
                      if (widget.onNavigateToTab != null)
                        TextButton(
                          onPressed: () => widget.onNavigateToTab!(1),
                          child: const Text(
                            'View All',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: CeladonColors.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // 5. Tasks List (Dynamic from real backend)
                  if (_myTasks.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: CeladonColors.borderLight),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.task_alt_outlined, size: 36, color: CeladonColors.textMuted),
                          SizedBox(height: 10),
                          Text(
                            'No Tasks Assigned',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: CeladonColors.textPrimary,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'You have no pending tasks scheduled in your queue.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: CeladonColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._myTasks.map((task) => _buildLiveTaskCard(task)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required Color badgeColor,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: CeladonColors.borderLight),
            boxShadow: const [
              BoxShadow(
                color: Color(0x062D6A4F),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 18, color: iconColor),
                  ),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: CeladonColors.textSecondary,
                    ),
                  ),
                ],
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: value.length > 6 ? 18 : 24,
                  fontWeight: FontWeight.w800,
                  color: badgeColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveTaskCard(TaskModel task) {
    Color priorityBg;
    Color priorityTextColor;
    if (task.isHighPriority) {
      priorityBg = const Color(0xFFFEE2E2);
      priorityTextColor = const Color(0xFFEF4444);
    } else if (task.isMediumPriority) {
      priorityBg = const Color(0xFFFEF3C7);
      priorityTextColor = const Color(0xFFD97706);
    } else {
      priorityBg = const Color(0xFFE0F2FE);
      priorityTextColor = const Color(0xFF0284C7);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CeladonColors.borderLight),
        boxShadow: const [
          BoxShadow(
            color: Color(0x04000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Status Icon
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: task.isCompleted ? const Color(0xFFE8F3ED) : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              task.isCompleted ? Icons.check_circle_rounded : Icons.pending_actions_rounded,
              size: 20,
              color: task.isCompleted ? CeladonColors.primary : CeladonColors.textSecondary,
            ),
          ),
          const SizedBox(width: 12),

          // Task Title & Due Date
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: CeladonColors.textPrimary,
                    decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  task.dueDate != null && task.dueDate!.isNotEmpty
                      ? 'Due: ${task.dueDate!.split('T').first}'
                      : (task.description?.isNotEmpty == true ? task.description! : 'Active task'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: CeladonColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Priority Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: priorityBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              task.displayPriority,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: priorityTextColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
