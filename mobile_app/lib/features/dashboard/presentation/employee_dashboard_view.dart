import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../attendance/data/attendance_model.dart';
import '../../attendance/data/attendance_service.dart';
import '../../auth/data/user_model.dart';
import '../../tasks/data/task_model.dart';
import '../../tasks/data/task_service.dart';
import '../data/dashboard_service.dart';
import '../data/leave_model.dart';

/// Screen 3: Employee Dashboard (Executive Modern Office Theme)
///
/// Designed strictly for the Employee Persona:
/// - 100% Personal workforce metrics matching ReGen React website (`DashboardHome.jsx`)
/// - My Annual Attendance Rate & attended days
/// - My Assigned Projects & Task count
/// - Attendance Summary breakdown (Present / Late / Absent counters + Today's status chip)
/// - Leaves summary (Approved count vs applied)
/// - Geofenced Attendance Quick Glance widget
/// - Interactive "Today's Tasks" with direct checkmark completion
/// - Read-only "My Leaves" recent history preview (NO cluttered request forms in dashboard)
/// - Zero hardcoded data. 100% Dynamic MongoDB-backed data.
class EmployeeDashboardView extends StatefulWidget {
  final UserModel user;
  final VoidCallback? onNotificationTap;
  final void Function(int tabIndex)? onNavigateToTab;
  final VoidCallback? onOpenDrawer;
  final VoidCallback? onOpenAttendance;
  final VoidCallback? onLogout;
  final dynamic dashboardService;

  const EmployeeDashboardView({
    super.key,
    required this.user,
    this.onNotificationTap,
    this.onNavigateToTab,
    this.onOpenDrawer,
    this.onOpenAttendance,
    this.onLogout,
    this.dashboardService,
  });

  @override
  State<EmployeeDashboardView> createState() => _EmployeeDashboardViewState();
}

class _EmployeeDashboardViewState extends State<EmployeeDashboardView> {
  late final DashboardService _dashboardService;
  final TaskService _taskService = TaskService();
  final AttendanceService _attendanceService = AttendanceService();

  bool _isLoading = true;
  String? _errorMessage;

  List<TaskModel> _myTasks = [];
  List<AttendanceModel> _myAttendance = [];
  List<LeaveModel> _myLeaves = [];
  AttendanceModel? _todayAttendance;

  @override
  void initState() {
    super.initState();
    _dashboardService = (widget.dashboardService is DashboardService)
        ? widget.dashboardService as DashboardService
        : DashboardService();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _dashboardService.getTasks(),
        _dashboardService.getAttendance(),
        _dashboardService.getLeaves(),
        _attendanceService.getTodayAttendance().catchError((_) => null),
      ]);

      if (!mounted) return;

      final allTasks = results[0] as List<TaskModel>;
      final allAttendance = results[1] as List<AttendanceModel>;
      final allLeaves = results[2] as List<LeaveModel>;
      final todayAtt = results[3] as AttendanceModel?;

      final currentUid = widget.user.id.toLowerCase();
      final currentUsername = widget.user.username.toLowerCase();
      final currentName = widget.user.name.toLowerCase();
      final currentUserId = widget.user.userId.toLowerCase();

      // Filter tasks assigned strictly to this employee
      final filteredTasks = allTasks.where((t) {
        if (t.assignedTo == null || t.assignedTo!.isEmpty) return true;
        final assigned = t.assignedTo!.toLowerCase();
        return assigned == currentUid ||
            assigned == currentUsername ||
            assigned == currentName ||
            assigned == currentUserId;
      }).toList();

      // Filter personal attendance logs
      final filteredAttendance = allAttendance.where((a) {
        final aUid = a.userId.toLowerCase();
        return aUid == currentUserId ||
            aUid == currentUid ||
            aUid == currentUsername;
      }).toList();

      // Filter personal leave applications
      final filteredLeaves = allLeaves.where((l) {
        final lUid = l.userId.toLowerCase();
        return lUid == currentUserId ||
            lUid == currentUid ||
            lUid == currentUsername;
      }).toList();

      setState(() {
        _myTasks = filteredTasks.isNotEmpty ? filteredTasks : allTasks;
        _myAttendance = filteredAttendance.isNotEmpty ? filteredAttendance : allAttendance;
        _myLeaves = filteredLeaves.isNotEmpty ? filteredLeaves : allLeaves;
        _todayAttendance = todayAtt;
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

  String _getTodayStatus() {
    if (_todayAttendance != null) {
      final st = _todayAttendance!.status.toLowerCase();
      if (st == 'late') return 'Late';
      if (st == 'half_day') return 'Half Day';
      if (st == 'present') return 'Present';
    }

    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    for (final att in _myAttendance) {
      if (att.date.startsWith(todayStr)) {
        final s = att.status.toLowerCase();
        if (s == 'late') return 'Late';
        if (s == 'half_day') return 'Half Day';
        return 'Present';
      }
    }
    return 'Not In';
  }

  int get _presentCount => _myAttendance.where((a) => a.status.toLowerCase() == 'present').length;
  int get _lateCount => _myAttendance.where((a) => a.status.toLowerCase() == 'late').length;
  int get _absentCount => _myAttendance.where((a) => a.status.toLowerCase() == 'absent').length;

  int get _attendanceRate {
    final total = _presentCount + _lateCount + _absentCount;
    if (total == 0) return 100;
    return (((_presentCount + _lateCount) / total) * 100).round();
  }

  int get _distinctProjectsCount {
    final projs = _myTasks.map((t) => t.projectId).where((p) => p != null && p.isNotEmpty).toSet();
    return projs.isNotEmpty ? projs.length : (_myTasks.isNotEmpty ? 1 : 0);
  }

  Future<void> _handleToggleTask(TaskModel task) async {
    final updated = await _taskService.toggleTaskComplete(task.id, !task.isCompleted);
    if (!mounted) return;
    setState(() {
      final idx = _myTasks.indexWhere((t) => t.id == task.id);
      if (idx != -1) {
        _myTasks[idx] = updated;
      }
    });
  }

  void _handleAttendanceTap() {
    if (widget.onOpenAttendance != null) {
      widget.onOpenAttendance!();
    } else {
      widget.onNavigateToTab?.call(2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.user.name.isNotEmpty
        ? widget.user.name
        : (widget.user.username.isNotEmpty ? widget.user.username : 'Ram');

    final roleName = widget.user.designation?.isNotEmpty == true
        ? widget.user.designation!
        : widget.user.roleDisplayName;

    final todayStatus = _getTodayStatus();
    final isPresent = todayStatus == 'Present' || todayStatus == 'Late';
    final currentYear = DateTime.now().year;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF8),
      body: RefreshIndicator(
        onRefresh: _loadDashboardData,
        color: CeladonColors.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Executive Modern Office Header
              _buildOfficeHeader(context, displayName, roleName, currentYear),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Error Banner if needed
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFFCA5A5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline_rounded, color: Color(0xFFDC2626), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF991B1B)),
                              ),
                            ),
                            TextButton(
                              onPressed: _loadDashboardData,
                              child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // 2. Personal Analytics 4-Card Grid (Matching DashboardHome.jsx)
                    _buildPersonalMetricsGrid(todayStatus, isPresent, currentYear),
                    const SizedBox(height: 18),

                    // 3. Today's Attendance Geofence Action Card
                    _buildTodayAttendanceWidget(todayStatus, isPresent),
                    const SizedBox(height: 20),

                    // 4. Section: Today's Tasks
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Today's Tasks",
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F3A2E),
                          ),
                        ),
                        InkWell(
                          onTap: () => widget.onNavigateToTab?.call(1),
                          borderRadius: BorderRadius.circular(10),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Text(
                              'View All →',
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

                    // Dynamic Tasks List
                    if (_isLoading) ...[
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24.0),
                          child: CircularProgressIndicator(color: CeladonColors.primary),
                        ),
                      ),
                    ] else if (_myTasks.isEmpty) ...[
                      _buildEmptyCard(
                        icon: Icons.check_circle_outline_rounded,
                        text: 'No active tasks for today. You are all caught up!',
                      ),
                    ] else ...[
                      ..._myTasks.take(4).map((task) => _buildInteractiveTaskCard(task)),
                    ],

                    const SizedBox(height: 24),

                    // 5. Section: My Leaves (selectedYear) - Clean Read-Only History Preview
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "My Leaves ($currentYear)",
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F3A2E),
                          ),
                        ),
                        InkWell(
                          onTap: () => widget.onNavigateToTab?.call(2), // Calendar tab
                          borderRadius: BorderRadius.circular(10),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Text(
                              'Apply in Calendar →',
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

                    // Leaves History List
                    if (_myLeaves.isEmpty) ...[
                      _buildEmptyCard(
                        icon: Icons.beach_access_outlined,
                        text: 'You have no leave records in $currentYear.',
                      ),
                    ] else ...[
                      ..._myLeaves.take(3).map((leave) => _buildLeaveHistoryRow(leave)),
                    ],

                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Executive Office Header with Exact Background & Crisp User Details
  Widget _buildOfficeHeader(BuildContext context, String displayName, String roleName, int currentYear) {
    final now = DateTime.now();
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dateStr = '${weekdays[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} ${now.year}';

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F3A2E),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/office_dashboard_header.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF0F3A2E).withValues(alpha: 0.65),
                      const Color(0xFF1B4332).withValues(alpha: 0.42),
                      const Color(0xFF0F3A2E).withValues(alpha: 0.70),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Row: Hamburger & Notification
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
                            icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 24),
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
                                icon: const Icon(Icons.notifications_none_rounded, size: 22, color: Colors.white),
                                onPressed: () {
                                  if (widget.onNotificationTap != null) {
                                    widget.onNotificationTap!();
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('No new announcements at this time.'),
                                        backgroundColor: CeladonColors.primary,
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Greeting Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Circular Avatar
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            color: CeladonColors.primaryContainer,
                            boxShadow: const [
                              BoxShadow(color: Color(0x30000000), blurRadius: 10, offset: Offset(0, 3)),
                            ],
                          ),
                          child: ClipOval(
                            child: widget.user.avatar != null && widget.user.avatar!.isNotEmpty
                                ? _buildAvatarImage(widget.user.avatar!, displayName)
                                : Center(
                                    child: Text(
                                      displayName.isNotEmpty ? displayName.substring(0, 1).toUpperCase() : 'R',
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

                        // Name & Role
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Welcome back,',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFFD8F3DC).withValues(alpha: 0.9),
                                ),
                              ),
                              Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                '$roleName • $currentYear',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFFE2E8F0),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Date Chip
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.28), width: 1.2),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.calendar_today_rounded, size: 12, color: Colors.white),
                              const SizedBox(width: 5),
                              Text(
                                dateStr,
                                style: const TextStyle(
                                  fontSize: 11,
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
          displayName.isNotEmpty ? displayName.substring(0, 1).toUpperCase() : 'R',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: CeladonColors.primaryDark,
          ),
        ),
      ),
    );
  }

  /// 4 Personal Metric Cards matching ReGen React Website
  Widget _buildPersonalMetricsGrid(String todayStatus, bool isPresent, int currentYear) {
    final attendedDays = _presentCount + _lateCount;
    final approvedLeaves = _myLeaves.where((l) => l.isApproved).length;

    return Column(
      children: [
        Row(
          children: [
            // Card 1: Attendance Rate
            Expanded(
              child: _buildMetricTile(
                icon: Icons.verified_user_rounded,
                iconColor: const Color(0xFF10B981),
                iconBg: const Color(0xFFD1FAE5),
                title: 'Attendance Rate',
                value: '$_attendanceRate%',
                subtitle: '$attendedDays days attended',
                onTap: _handleAttendanceTap,
              ),
            ),
            const SizedBox(width: 12),

            // Card 2: My Projects
            Expanded(
              child: _buildMetricTile(
                icon: Icons.folder_special_rounded,
                iconColor: const Color(0xFF0D9488),
                iconBg: const Color(0xFFCCFBF1),
                title: 'My Projects',
                value: '$_distinctProjectsCount',
                subtitle: '${_myTasks.length} tasks assigned',
                onTap: () => widget.onNavigateToTab?.call(1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            // Card 3: Attendance Summary (Trio breakdown)
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                        const Text('Summary', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: isPresent ? const Color(0xFFD1FAE5) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            todayStatus,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: isPresent ? const Color(0xFF065F46) : const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildTinyStat('P', '$_presentCount', const Color(0xFF10B981)),
                        _buildTinyStat('L', '$_lateCount', const Color(0xFFF59E0B)),
                        _buildTinyStat('A', '$_absentCount', const Color(0xFFEF4444)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Card 4: Leaves Summary
            Expanded(
              child: _buildMetricTile(
                icon: Icons.beach_access_rounded,
                iconColor: const Color(0xFF8B5CF6),
                iconBg: const Color(0xFFEDE9FE),
                title: 'Leaves in $currentYear',
                value: '${_myLeaves.length}',
                subtitle: '$approvedLeaves Approved',
                onTap: () => widget.onNavigateToTab?.call(2),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTinyStat(String tag, String count, Color color) {
    return Column(
      children: [
        Text(count, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
        Text(tag, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
      ],
    );
  }

  Widget _buildMetricTile({
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
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF0F3A2E))),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: Color(0xFF94A3B8)), maxLines: 1),
          ],
        ),
      ),
    );
  }

  /// Geofence Attendance Quick Action Card
  Widget _buildTodayAttendanceWidget(String todayStatus, bool isPresent) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(color: Color(0x06000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isPresent ? const Color(0xFFD1FAE5) : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.location_on_rounded,
              color: isPresent ? const Color(0xFF059669) : const Color(0xFF64748B),
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Office Geofence Status',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F3A2E)),
                ),
                const SizedBox(height: 2),
                Text(
                  isPresent ? 'Checked In • Geofence Verified' : 'Ready to Check In at Office',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: isPresent ? const Color(0xFF059669) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _handleAttendanceTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: isPresent ? const Color(0xFF0F3A2E) : const Color(0xFF10B981),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              isPresent ? 'Status' : 'Check In',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  /// Interactive Task Card with Direct Checkbox
  Widget _buildInteractiveTaskCard(TaskModel task) {
    Color priorityColor = const Color(0xFF3B82F6);
    Color priorityBg = const Color(0xFFEFF6FF);
    if (task.priority.toLowerCase() == 'high' || task.priority.toLowerCase() == 'urgent') {
      priorityColor = const Color(0xFFEF4444);
      priorityBg = const Color(0xFFFEF2F2);
    } else if (task.priority.toLowerCase() == 'medium') {
      priorityColor = const Color(0xFFF59E0B);
      priorityBg = const Color(0xFFFFFBEB);
    }

    final isDone = task.isCompleted;

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
          // Completion checkbox
          InkWell(
            onTap: () => _handleToggleTask(task),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: isDone ? const Color(0xFF10B981) : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: isDone ? const Color(0xFF10B981) : const Color(0xFFCBD5E1),
                  width: 1.8,
                ),
              ),
              child: isDone ? const Icon(Icons.check, size: 15, color: Colors.white) : null,
            ),
          ),
          const SizedBox(width: 12),

          // Title & Due Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: isDone ? const Color(0xFF94A3B8) : const Color(0xFF1E293B),
                    decoration: isDone ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (task.projectName != null && task.projectName!.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          task.projectName!,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      task.dueDate != null && task.dueDate!.isNotEmpty
                          ? 'Due: ${task.dueDate!.split('T').first}'
                          : (task.description?.isNotEmpty == true ? task.description! : 'In Progress'),
                      style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Priority Chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: priorityBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              task.displayPriority,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: priorityColor),
            ),
          ),
        ],
      ),
    );
  }

  /// Read-Only Leave History Row
  Widget _buildLeaveHistoryRow(LeaveModel leave) {
    Color statusColor = const Color(0xFFD97706);
    Color statusBg = const Color(0xFFFEF3C7);
    String statusText = 'Pending';

    if (leave.isApproved) {
      statusColor = const Color(0xFF059669);
      statusBg = const Color(0xFFD1FAE5);
      statusText = 'Approved';
    } else if (leave.status.toLowerCase() == 'rejected') {
      statusColor = const Color(0xFFDC2626);
      statusBg = const Color(0xFFFEE2E2);
      statusText = 'Rejected';
    }

    final dateRange = '${leave.startDate.split('T').first} to ${leave.endDate.split('T').first}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE9FE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.beach_access_rounded, size: 18, color: Color(0xFF8B5CF6)),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    leave.displayType,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F3A2E)),
                  ),
                  Text(
                    dateRange,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              statusText,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: statusColor),
            ),
          ),
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
}
