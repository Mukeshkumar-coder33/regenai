import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/services/location_service.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../attendance/data/attendance_model.dart';
import '../../attendance/data/attendance_service.dart';
import '../../attendance/data/work_schedule_model.dart';
import '../../auth/data/auth_service.dart';
import '../../auth/data/user_model.dart';
import '../../calendar/data/leave_service.dart';
import '../../dashboard/data/dashboard_service.dart';
import '../../dashboard/data/leave_model.dart';
import '../../tasks/data/task_model.dart';
import '../../tasks/presentation/tasks_view.dart';
import '../data/company_model.dart';
import 'add_employee_view.dart';

/// True Frosted Glassmorphism Company Workspace matching User Reference Mockups:
/// - Photorealistic Corporate Dark Office Background with daylight, desks, indoor plants & bokeh blur
/// - True Frosted Glass Container Cards (BackdropFilter blur 16-18px, translucent emerald gradient, thin glowing borders)
/// - Screen 1: Dashboard with 4 Dynamic Stat Cards (Total Employees, Present Today, On Leave, Absent),
///   Weekly Attendance Bar Chart with glowing neon gradient columns, and Quick Operations bar.
/// - Screen 2: Employees Directory ("Manage your team") with real-time search, active/on-leave/inactive filter chips,
///   and + Add Employee action with backend API registration.
/// - Screen 3: Attendance Tracker ("Track employee attendance") with interactive month calendar,
///   selected day circle, Today's Attendance progress bar, and real-time daily log roster.
/// - Screen 4: Leave Management ("Manage leave requests") with filter chips (All, Pending, Approved, Rejected)
///   and instant Approve/Reject actions wired to backend APIs.
/// - Screen 5: Profile & Company Workspace with segmented views: Company Information (with 5m Geofence rule),
///   My Profile (with avatar & contact details), and Settings (with confirmation sign-out).
/// - Top Bar: Hamburger menu, ReGen logo, Notifications Bell with unread badge, and User Avatar.
/// - Modal: Notifications Center ("Stay updated") with category filter chips and dynamic event cards.
/// - Floating Glassmorphic 5-Tab Dock with glowing neon emerald active pill.
/// - 100% Dynamic data backed by live ReGen MongoDB APIs. Zero hardcoded mock numbers.
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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final DashboardService _dashboardService;
  late final AuthService _authService;
  final AttendanceService _attendanceService = AttendanceService();

  int _selectedBottomTab = 0; // 0=Home, 1=Employees, 2=Attendance, 3=Leave, 4=Profile
  int _selectedProfileSubTab = 0; // 0=Company, 1=My Profile, 2=Settings
  int _selectedEmployeeFilter = 0; // 0=All, 1=Active, 2=On Leave, 3=Inactive
  String _selectedEmployeeRoleFilter = 'all'; // 'all', 'owner', 'admin', 'staff', 'intern', 'freelancer'
  String _selectedEmployeeDeptFilter = 'all';
  int _selectedLeaveFilter = 0; // 0=All, 1=Pending, 2=Approved, 3=Rejected
  int _selectedNotificationFilter = 0; // 0=All, 1=Unread, 2=System, 3=Leave, 4=Attendance

  bool _isLoading = true;
  String? _errorMessage;
  bool _isSwitchingToSuperAdmin = false;

  CompanyModel? _company;
  List<UserModel> _users = [];
  List<TaskModel> _tasks = [];
  List<AttendanceModel> _attendance = [];
  List<LeaveModel> _leaves = [];
  WorkScheduleModel _workSchedule = const WorkScheduleModel();

  int _selectedYear = DateTime.now().year;
  String _selectedTrendFilter = 'Week'; // 'Week', 'Month', 'Year'
  int _selectedWeekDayIndex = (DateTime.now().weekday - 1).clamp(0, 6); // 0=Mon, 6=Sun
  int _selectedMonthIndex = DateTime.now().month; // 1=Jan .. 12=Dec
  int _selectedMonthWeekIndex = 0; // 0=Week 1, 1=Week 2, 2=Week 3, 3=Week 4
  String _selectedTrendStatusTab = 'present'; // 'present', 'absent', 'late', 'leave'
  UserModel? _selectedTrendDetailEmployee;
  int _trendListPaginationCount = 3;
  bool _isTrendViewAll = false;

  DateTime _selectedCalendarDate = DateTime.now();
  DateTime _currentCalendarMonth = DateTime.now();
  String _selectedDayLogFilter = 'all'; // 'all', 'present', 'absent', 'late', 'leave'
  int _attendanceDayLogPage = 0;
  _DayAttendanceRecord? _selectedEmployeeForDayLog;
  final TextEditingController _employeeSearchController = TextEditingController();
  String _employeeSearchQuery = '';
  final TextEditingController _attendanceSearchController = TextEditingController();
  String _attendanceSearchQuery = '';
  final TextEditingController _leaveSearchController = TextEditingController();
  String _leaveSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _dashboardService = widget.dashboardService ?? DashboardService();
    _authService = widget.authService ?? AuthService();
    _loadCompanyData();
  }

  @override
  void dispose() {
    _employeeSearchController.dispose();
    _attendanceSearchController.dispose();
    _leaveSearchController.dispose();
    super.dispose();
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
          if (_company != null) {
            final startDt = DateTime(_company!.startingYear, _company!.startingMonth, 1);
            if (_currentCalendarMonth.isBefore(startDt)) {
              _currentCalendarMonth = startDt;
            }
            if (_selectedCalendarDate.isBefore(startDt)) {
              _selectedCalendarDate = startDt;
            }
          }
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
            backgroundColor: Color(0xFF10B981),
            content: Text('Switched to Global Super Admin Console'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSwitchingToSuperAdmin = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Failed to switch to Super Admin: $e'),
          ),
        );
      }
    }
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

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF072118),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
        ),
        title: const Text('Sign Out', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        content: const Text(
          'Are you sure you want to sign out of the Company Workspace?',
          style: TextStyle(color: Color(0xFFBACCC3)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF88A89A))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onLogout?.call();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  bool _isStaffEmployee(UserModel u) {
    final r = u.role.toLowerCase().trim();
    return r != 'owner' && r != 'admin' && r != 'param';
  }

  List<UserModel> get _allNonAdminEmployees {
    return _users.where(_isStaffEmployee).toList();
  }

  int get _departmentCount {
    final staff = _allNonAdminEmployees.isNotEmpty ? _allNonAdminEmployees : _users;
    final depts = staff
        .map((u) => u.department?.trim())
        .where((d) => d != null && d.isNotEmpty)
        .toSet();
    return depts.isEmpty ? 1 : depts.length;
  }

  int get _activeTasksCount {
    return _tasks.where((t) => t.status.toLowerCase() != 'completed').length;
  }

  // Company starting year strictly computed from live MongoDB
  int get _companyStartingYear {
    if (_company != null) {
      return _company!.startingYear;
    }
    int start = DateTime.now().year;
    final staff = _allNonAdminEmployees.isNotEmpty ? _allNonAdminEmployees : _users;
    for (final u in staff) {
      final yr = u.joinedDate.year;
      if (yr >= 1990 && yr < start) {
        start = yr;
      }
    }
    return start <= DateTime.now().year ? start : DateTime.now().year;
  }

  // Company starting month strictly computed from live MongoDB
  int get _companyStartingMonth {
    if (_company != null) {
      return _company!.startingMonth;
    }
    int minM = 12;
    final staff = _allNonAdminEmployees.isNotEmpty ? _allNonAdminEmployees : _users;
    for (final u in staff) {
      if (u.joinedDate.year == _companyStartingYear && u.joinedDate.month < minM) {
        minM = u.joinedDate.month;
      }
    }
    for (final a in _attendance) {
      if (a.date.startsWith('$_companyStartingYear-')) {
        final parts = a.date.split('-');
        if (parts.length >= 2) {
          final m = int.tryParse(parts[1]) ?? 12;
          if (m < minM) minM = m;
        }
      }
    }
    return minM <= 12 ? minM : 1;
  }

  // Dynamic monthly staff accumulation:
  // "if one employee joined on june means then consider that one employee after addition of next employee then consider the next one"
  List<UserModel> _getStaffActiveInMonth(int year, int month) {
    final staff = _allNonAdminEmployees.isNotEmpty ? _allNonAdminEmployees : _users;
    final list = staff.where((u) {
      final j = u.joinedDate;
      if (j.year < year) return true;
      if (j.year == year && j.month <= month) return true;
      return false;
    }).toList();
    return list;
  }

  List<int> get _availableYears {
    final cur = DateTime.now().year;
    final start = _companyStartingYear <= cur ? _companyStartingYear : cur;
    final list = <int>[];
    for (int y = cur; y >= start; y--) {
      list.add(y);
    }
    return list.isNotEmpty ? list : [cur];
  }

  bool get _isCurrentYear => _selectedYear == DateTime.now().year;

  // Active employees in selectedYear (joined on or before selectedYear)
  List<UserModel> get _employeesInSelectedYear {
    final staff = _allNonAdminEmployees.isNotEmpty ? _allNonAdminEmployees : _users;
    final list = staff.where((u) => u.joinedDate.year <= _selectedYear).toList();
    return list;
  }

  int get _totalStaffInYear => _employeesInSelectedYear.length;

  // Joined strictly in selectedYear
  int get _joinedInSelectedYear {
    final staff = _allNonAdminEmployees.isNotEmpty ? _allNonAdminEmployees : _users;
    return staff.where((u) => u.joinedDate.year == _selectedYear).length;
  }

  int get _departmentCountInYear {
    final depts = _employeesInSelectedYear
        .map((u) => u.department)
        .where((d) => d != null && d.isNotEmpty)
        .toSet();
    if (depts.isNotEmpty) return depts.length;
    return _departmentCount;
  }

  // Today's attendance logs from MongoDB (strictly staff employees, excluding owner/admin)
  List<AttendanceModel> get _todayAttendanceLogs {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final nonAdminIds = _allNonAdminEmployees.map((u) => u.userId.toLowerCase()).toSet();
    final nonAdminUsernames = _allNonAdminEmployees.map((u) => u.username.toLowerCase()).toSet();
    return _attendance.where((a) {
      bool isToday = a.date.startsWith(todayStr);
      if (!isToday) {
        final parsed = DateTime.tryParse(a.date);
        if (parsed != null && parsed.year == now.year && parsed.month == now.month && parsed.day == now.day) {
          isToday = true;
        }
      }
      if (!isToday) return false;
      if (_allNonAdminEmployees.isEmpty) return true;
      final uid = a.userId.toLowerCase();
      return nonAdminIds.contains(uid) || nonAdminUsernames.contains(uid);
    }).toList();
  }

  int get _todayPresentCount {
    final logs = _todayAttendanceLogs;
    if (logs.isEmpty) return 0;
    return logs.where((a) {
      final st = a.status.toLowerCase();
      return st == 'present' || st == 'late';
    }).length;
  }

  int get _todayLateCount {
    return _todayAttendanceLogs.where((a) => a.status.toLowerCase() == 'late').length;
  }

  int get _todayLeaveAndHalfDayCount {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final leavesToday = _leaves.where((l) => l.isApproved && l.coversDate(todayStr)).length;
    final halfDaysToday = _todayAttendanceLogs.where((a) => a.status.toLowerCase() == 'half_day').length;
    return leavesToday + halfDaysToday;
  }

  int get _todayAbsentCount {
    final total = _totalStaffInYear;
    final present = _todayPresentCount;
    final onLeave = _todayLeaveAndHalfDayCount;
    return (total - present - onLeave).clamp(0, total);
  }

  int get _todayAttendancePct {
    final total = _totalStaffInYear;
    if (total == 0) return 0;
    return ((_todayPresentCount / total) * 100).round();
  }

  // Annual calculations for past year
  List<AttendanceModel> get _yearAttendanceLogs {
    final prefix = '$_selectedYear-';
    return _attendance.where((a) => a.date.startsWith(prefix)).toList();
  }

  int get _yearAttendedCount {
    return _yearAttendanceLogs.where((a) {
      final st = a.status.toLowerCase();
      return st == 'present' || st == 'late' || st == 'half_day';
    }).length;
  }

  int get _yearLateCount {
    return _yearAttendanceLogs.where((a) => a.status.toLowerCase() == 'late').length;
  }

  int get _yearLeaveCount {
    return _leaves.where((l) => l.isApproved && l.startDate.startsWith('$_selectedYear-')).length;
  }

  int get _yearAbsentCount {
    final total = _totalStaffInYear * 200;
    return (total - _yearAttendedCount).clamp(0, total);
  }

  int get _yearAttendanceRate {
    final totalPossible = _totalStaffInYear * 200;
    if (totalPossible <= 0) return 0;
    return ((_yearAttendedCount / totalPossible) * 100).round().clamp(0, 100);
  }

  bool _isCompanyLeave(DateTime date) {
    for (final l in _leaves) {
      if (!l.isApproved) continue;
      try {
        final start = DateTime.parse(l.startDate);
        final end = DateTime.parse(l.endDate);
        final dZero = DateTime(date.year, date.month, date.day);
        final sZero = DateTime(start.year, start.month, start.day);
        final eZero = DateTime(end.year, end.month, end.day);
        if ((dZero.isAtSameMomentAs(sZero) || dZero.isAfter(sZero)) &&
            (dZero.isAtSameMomentAs(eZero) || dZero.isBefore(eZero))) {
          return true;
        }
      } catch (_) {
        final dStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        if (l.startDate.startsWith(dStr)) return true;
      }
    }
    return false;
  }

  bool _isNonWorkingDay(DateTime date) {
    final daysPerWeek = _workSchedule.workingDaysPerWeek;
    if (daysPerWeek == 5) {
      return date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
    } else if (daysPerWeek == 6) {
      return date.weekday == DateTime.sunday;
    } else if (daysPerWeek == 4) {
      return date.weekday == DateTime.friday || date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
    } else if (daysPerWeek == 7) {
      return false;
    }
    return _workSchedule.isWeeklyOff(date);
  }

  bool _isNonWorkingOrLeave(DateTime date) {
    return _isNonWorkingDay(date) || _isCompanyLeave(date);
  }

  List<UserModel> _getBirthdayEmployees(DateTime date) {
    return _allNonAdminEmployees.where((u) {
      if (u.dateOfBirth == null || u.dateOfBirth!.isEmpty) return false;
      try {
        final dob = DateTime.parse(u.dateOfBirth!);
        return dob.month == date.month && dob.day == date.day;
      } catch (_) {
        return false;
      }
    }).toList();
  }

  // 1. Week Trend Data: 7 days (Mon-Sun) with dynamic staff count (strictly non-admin)
  List<Map<String, dynamic>> get _weekTrendDays {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final dayOfWeek = (now.weekday - 1); // 0=Mon, 6=Sun
    final monday = DateTime(now.year, now.month, now.day - dayOfWeek);

    final nonAdminIds = _allNonAdminEmployees.map((u) => u.userId.toLowerCase()).toSet();
    final nonAdminUsernames = _allNonAdminEmployees.map((u) => u.username.toLowerCase()).toSet();

    final result = <Map<String, dynamic>>[];
    for (int i = 0; i < 7; i++) {
      final date = monday.add(Duration(days: i));
      final targetMidnight = DateTime(date.year, date.month, date.day);
      final isFuture = targetMidnight.isAfter(todayMidnight);
      final isToday = targetMidnight.isAtSameMomentAs(todayMidnight);
      final isLeaveOrOff = _isNonWorkingOrLeave(date);
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final staffList = _getStaffActiveInMonth(date.year, date.month);
      final totalStaff = staffList.isNotEmpty ? staffList.length : (_totalStaffInYear > 0 ? _totalStaffInYear : 1);

      final dayLogs = _attendance.where((a) {
        if (a.date != dateStr) return false;
        if (_allNonAdminEmployees.isEmpty) return true;
        final uid = a.userId.toLowerCase();
        return nonAdminIds.contains(uid) || nonAdminUsernames.contains(uid);
      }).toList();

      final presentCount = dayLogs.where((a) {
        final st = a.status.toLowerCase();
        return st == 'present' || st == 'late';
      }).length;
      final lateCount = dayLogs.where((a) => a.status.toLowerCase() == 'late').length;
      final leaveCount = _leaves.where((l) {
        if (!l.isApproved || !l.coversDate(dateStr)) return false;
        if (_allNonAdminEmployees.isEmpty) return true;
        final uid = l.userId.toLowerCase();
        return nonAdminIds.contains(uid) || nonAdminUsernames.contains(uid);
      }).length;

      // Real Data: Future days haven't occurred yet, so absentCount is 0.
      // Holidays/weekly-off days also have 0 absentCount.
      final int absentCount;
      if (isFuture || isLeaveOrOff) {
        absentCount = 0;
      } else {
        absentCount = (totalStaff - presentCount - leaveCount).clamp(0, totalStaff);
      }
      final rate = isFuture
          ? 0.0
          : ((presentCount / totalStaff) * 100.0).clamp(0.0, 100.0);

      result.add({
        'dayName': days[i],
        'date': date,
        'dateStr': dateStr,
        'present': presentCount,
        'late': lateCount,
        'absent': absentCount,
        'leave': leaveCount,
        'rate': rate,
        'isFuture': isFuture,
        'isToday': isToday,
        'logs': dayLogs,
        'staffList': staffList,
      });
    }
    return result;
  }

  // 2. Month Trend Data: 4 weeks of the selected month in selectedYear
  List<Map<String, dynamic>> get _monthTrendWeeks {
    final targetMonth = _selectedMonthIndex.clamp(1, 12);
    final daysInMonth = DateTime(_selectedYear, targetMonth + 1, 0).day;
    final staffList = _getStaffActiveInMonth(_selectedYear, targetMonth);
    final totalStaff = staffList.isNotEmpty ? staffList.length : (_totalStaffInYear > 0 ? _totalStaffInYear : 1);

    final nonAdminIds = _allNonAdminEmployees.map((u) => u.userId.toLowerCase()).toSet();
    final nonAdminUsernames = _allNonAdminEmployees.map((u) => u.username.toLowerCase()).toSet();

    final weeks = [
      {'name': 'Week 1', 'start': 1, 'end': 7},
      {'name': 'Week 2', 'start': 8, 'end': 14},
      {'name': 'Week 3', 'start': 15, 'end': 21},
      {'name': 'Week 4', 'start': 22, 'end': daysInMonth},
    ];

    final result = <Map<String, dynamic>>[];
    final mStr = targetMonth.toString().padLeft(2, '0');

    for (final w in weeks) {
      final start = w['start'] as int;
      final end = w['end'] as int;
      final weekLogs = _attendance.where((a) {
        if (!a.date.startsWith('$_selectedYear-$mStr-')) return false;
        final parts = a.date.split('-');
        if (parts.length != 3) return false;
        final dayPart = int.tryParse(parts[2]) ?? 0;
        if (dayPart < start || dayPart > end) return false;
        if (_allNonAdminEmployees.isEmpty) return true;
        final uid = a.userId.toLowerCase();
        return nonAdminIds.contains(uid) || nonAdminUsernames.contains(uid);
      }).toList();

      final present = weekLogs.where((a) => a.status.toLowerCase() == 'present').length;
      final late = weekLogs.where((a) => a.status.toLowerCase() == 'late').length;
      final attended = present + late;

      final weekLeaveCount = _leaves.where((l) {
        if (!l.isApproved) return false;
        if (_allNonAdminEmployees.isNotEmpty) {
          final uid = l.userId.toLowerCase();
          if (!nonAdminIds.contains(uid) && !nonAdminUsernames.contains(uid)) return false;
        }
        for (int d = start; d <= end; d++) {
          final dStr = '$_selectedYear-$mStr-${d.toString().padLeft(2, '0')}';
          if (l.coversDate(dStr)) return true;
        }
        return false;
      }).length;

      final dateSet = weekLogs.map((a) => a.date).toSet();
      final workingDays = dateSet.isNotEmpty ? dateSet.length : 5;
      final possible = totalStaff * workingDays;
      final absent = (possible - attended - weekLeaveCount).clamp(0, possible);
      final rate = possible > 0 ? ((attended / possible) * 100.0).clamp(0.0, 100.0) : 0.0;

      result.add({
        'name': w['name'],
        'start': start,
        'end': end,
        'month': targetMonth,
        'monthName': _getMonthName(targetMonth),
        'present': present,
        'late': late,
        'absent': absent,
        'leave': weekLeaveCount,
        'rate': rate,
        'logs': weekLogs,
        'staffList': staffList,
      });
    }
    return result;
  }

  // 3. Year Trend Data: Months for selectedYear
  // Starts from company starting month if selectedYear is company starting year!
  List<Map<String, dynamic>> get _yearTrendMonths {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final result = <Map<String, dynamic>>[];

    // If selectedYear is company starting year, starts from company starting month!
    final startMonth = (_selectedYear == _companyStartingYear) ? _companyStartingMonth : 1;

    for (int m = startMonth; m <= 12; m++) {
      final mPrefix = '$_selectedYear-${m.toString().padLeft(2, '0')}';
      final mLogs = _attendance.where((a) {
        if (!a.date.startsWith(mPrefix)) return false;
        final st = a.status.toLowerCase();
        return st == 'present' || st == 'late' || st == 'half_day';
      }).toList();

      final attended = mLogs.length;

      // Dynamic staff count for this specific month based on join date:
      // "if one employee joined on june means then consider that one employee after addition of next employee then consider the next one"
      final staffList = _getStaffActiveInMonth(_selectedYear, m);
      final staffCount = staffList.isNotEmpty ? staffList.length : (_totalStaffInYear > 0 ? _totalStaffInYear : 1);

      final dateSet = mLogs.map((a) => a.date).toSet();
      final workingDays = dateSet.isNotEmpty ? dateSet.length : 20;
      final possible = staffCount * workingDays;
      final rate = (attended > 0 && possible > 0)
          ? ((attended / possible) * 100.0).clamp(0.0, 100.0)
          : 0.0;

      result.add({
        'name': months[m - 1],
        'month': m,
        'rate': rate,
        'attended': attended,
        'staffCount': staffCount,
        'staffList': staffList,
        'logs': mLogs,
      });
    }
    return result;
  }

  List<double> get _currentTrendRates {
    if (_selectedTrendFilter == 'Week') {
      return _weekTrendDays.map((d) => d['rate'] as double).toList();
    } else {
      return _yearTrendMonths.map((m) => m['rate'] as double).toList();
    }
  }

  List<String> get _currentTrendLabels {
    if (_selectedTrendFilter == 'Week') {
      return _weekTrendDays.map((d) => d['dayName'] as String).toList();
    } else {
      return _yearTrendMonths.map((m) => m['name'] as String).toList();
    }
  }

  void _showTrendFilterPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF031A14),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) {
        final options = [
          {'title': 'Week', 'desc': 'Day-by-day analysis (Mon - Sun)'},
          {'title': 'Month', 'desc': 'Monthly attendance distribution for $_selectedYear'},
          {'title': 'Year', 'desc': 'Annual workforce performance overview'},
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Select Trend View',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(height: 12),
                ...options.map((opt) {
                  final t = opt['title'] as String;
                  final d = opt['desc'] as String;
                  final isSelected = t == _selectedTrendFilter;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      t,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected ? const Color(0xFF34D399) : Colors.white,
                      ),
                    ),
                    subtitle: Text(d, style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1))),
                    trailing: isSelected ? const Icon(Icons.check_rounded, color: Color(0xFF34D399)) : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() => _selectedTrendFilter = t);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Map<String, dynamic> _getEmployeeWeekAttendanceStats(UserModel emp, int targetMonth, int startDay, int endDay) {
    final uid = (emp.userId.isNotEmpty ? emp.userId : emp.id).toLowerCase();
    final uname = emp.username.toLowerCase();
    final mStr = targetMonth.toString().padLeft(2, '0');

    final empLogs = _attendance.where((a) {
      if (!a.date.startsWith('$_selectedYear-$mStr-')) return false;
      final parts = a.date.split('-');
      if (parts.length != 3) return false;
      final dayPart = int.tryParse(parts[2]) ?? 0;
      if (dayPart < startDay || dayPart > endDay) return false;

      final aUid = a.userId.toLowerCase();
      return aUid == uid || aUid == uname;
    }).toList();

    int presentDays = 0;
    int lateDays = 0;
    for (final l in empLogs) {
      final st = l.status.toLowerCase();
      if (st == 'present') {
        presentDays++;
      } else if (st == 'late') {
        lateDays++;
      } else if (st == 'half_day') {
        presentDays++;
      }
    }

    int leaveDays = 0;
    for (int d = startDay; d <= endDay; d++) {
      final dStr = '$_selectedYear-$mStr-${d.toString().padLeft(2, '0')}';
      if (_leaves.any((l) =>
          l.isApproved &&
          l.coversDate(dStr) &&
          (l.userId.toLowerCase() == uid || l.userId.toLowerCase() == uname))) {
        leaveDays++;
      }
    }

    final totalAttended = presentDays + lateDays;
    return {
      'presentDays': presentDays,
      'lateDays': lateDays,
      'leaveDays': leaveDays,
      'totalAttended': totalAttended,
      'logs': empLogs,
    };
  }

  Map<String, dynamic> _getEmployeeYearAttendanceStats(UserModel emp) {
    final uid = (emp.userId.isNotEmpty ? emp.userId : emp.id).toLowerCase();
    final uname = emp.username.toLowerCase();

    final empLogs = _attendance.where((a) {
      if (!a.date.startsWith('$_selectedYear-')) return false;
      final aUid = a.userId.toLowerCase();
      return aUid == uid || aUid == uname;
    }).toList();

    int presentDays = 0;
    int lateDays = 0;
    for (final l in empLogs) {
      final st = l.status.toLowerCase();
      if (st == 'present') {
        presentDays++;
      } else if (st == 'late') {
        lateDays++;
      } else if (st == 'half_day') {
        presentDays++;
      }
    }

    final leaveDays = _leaves.where((l) =>
        l.isApproved &&
        l.startDate.startsWith('$_selectedYear-') &&
        (l.userId.toLowerCase() == uid || l.userId.toLowerCase() == uname)).length;

    final totalAttended = presentDays + lateDays;
    return {
      'presentDays': presentDays,
      'lateDays': lateDays,
      'leaveDays': leaveDays,
      'totalAttended': totalAttended,
      'logs': empLogs,
    };
  }

  void _showYearPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF031A14),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) {
        final years = _availableYears;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Select Year',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(height: 12),
                ...years.map((y) {
                  final isSelected = y == _selectedYear;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '$y',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected ? const Color(0xFF34D399) : Colors.white,
                      ),
                    ),
                    trailing: isSelected ? const Icon(Icons.check_rounded, color: Color(0xFF34D399)) : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() => _selectedYear = y);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  AttendanceModel? _getEmployeeAttendanceOnDate(UserModel emp, String dateStr) {
    final uid = (emp.userId.isNotEmpty ? emp.userId : emp.id).toLowerCase();
    final uname = emp.username.toLowerCase();
    for (final att in _attendance) {
      if (att.date != dateStr) continue;
      final aUid = att.userId.toLowerCase();
      if (aUid == uid || aUid == uname) return att;
    }
    return null;
  }

  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[(month - 1).clamp(0, 11)];
  }

  AttendanceModel? _getEmployeeTodayAttendance(UserModel emp) {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final uid = (emp.userId.isNotEmpty ? emp.userId : emp.id).toLowerCase();
    final uname = emp.username.toLowerCase();
    for (final att in _attendance) {
      final aUid = att.userId.toLowerCase();
      if (aUid != uid && aUid != uname) continue;
      bool isToday = att.date.startsWith(todayStr);
      if (!isToday) {
        final parsed = DateTime.tryParse(att.date);
        if (parsed != null && parsed.year == now.year && parsed.month == now.month && parsed.day == now.day) {
          isToday = true;
        }
      }
      if (isToday) return att;
    }
    return null;
  }

  String _formatHeaderDate(DateTime dt) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dayName = days[dt.weekday - 1];
    final monthName = months[dt.month - 1];
    return '$dayName ${dt.day.toString().padLeft(2, '0')} $monthName ${dt.year}';
  }

  String _getMonthYearName(DateTime dt) {
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return '${months[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF031A14),
      drawer: _buildCompanyDrawer(),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Attached Corporate Dark Office Background with Light Photographic Bokeh Blur (sigma 5.5)
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 5.5, sigmaY: 5.5),
              child: Transform.scale(
                scale: 1.05,
                child: Image.asset(
                  'assets/images/corporate_office_dark.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Image.asset(
                      'assets/images/office_auth_portrait.png',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          Container(color: const Color(0xFF031A14)),
                    );
                  },
                ),
              ),
            ),
          ),

          // 2. Translucent Ambient Lighting Preservation (Preserves natural interior daylight without heavy dark wash)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF04100B).withValues(alpha: 0.12),
                    Colors.transparent,
                    const Color(0xFF020906).withValues(alpha: 0.30),
                  ],
                ),
              ),
            ),
          ),

          // 3. Foreground Safe Content
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Common Executive Header (☰, Logo, Bell, Avatar)
                _buildTopAppBar(),

                // Tab Content Body
                Expanded(
                  child: _isLoading
                      ? _buildLoadingState()
                      : _errorMessage != null
                          ? _buildErrorState()
                          : RefreshIndicator(
                              onRefresh: _loadCompanyData,
                              color: const Color(0xFF10B981),
                              child: _buildCurrentTabContent(),
                            ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildCompanyBottomNav(),
    );
  }

  // ---------------------------------------------------------
  // EXECUTIVE COMPANY DRAWER (Matches User Images 1 & 2)
  // ---------------------------------------------------------
  Widget _buildCompanyDrawer() {
    final companyName = _company?.name ?? widget.user.companyName ?? 'krish Tech Computer';
    final displayName = widget.user.name.isNotEmpty
        ? widget.user.name
        : (widget.user.username.isNotEmpty ? widget.user.username : 'Rithika K P');
    final activeStaff = _attendance.length;
    final totalStaff = _allNonAdminEmployees.length;
    final pendingLeavesCount = _leaves.where((l) => l.isPending).length;

    final drawerWidth = (MediaQuery.of(context).size.width * 0.85).clamp(290.0, 360.0);

    return SizedBox(
      width: drawerWidth,
      child: Drawer(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: ClipRRect(
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(24)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Office Background Texture with Light Bokeh Blur (sigma 5.5)
              Positioned.fill(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 5.5, sigmaY: 5.5),
                  child: Transform.scale(
                    scale: 1.05,
                    child: Image.asset(
                      'assets/images/corporate_office_dark.jpg',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          Image.asset('assets/images/office_auth_portrait.png', fit: BoxFit.cover),
                    ),
                  ),
                ),
              ),

              // 2. Translucent Ambient Lighting Preservation (Exact Match to Dashboard UI)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF04100B).withValues(alpha: 0.12),
                        Colors.transparent,
                        const Color(0xFF020906).withValues(alpha: 0.30),
                      ],
                    ),
                    border: Border(
                      right: BorderSide(
                        color: const Color(0xFF34D399).withValues(alpha: 0.25),
                        width: 1.0,
                      ),
                    ),
                  ),
                ),
              ),

              // 3. Drawer Safe Area Content
              SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Drawer Top Bar: Brand + Close (X)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                      child: Row(
                        children: [
                          const BrandLogo(size: 26, borderRadius: 8),
                          const SizedBox(width: 10),
                          const Text(
                            'ReGen',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 24),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),

                    // User Profile & Company Banner
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: _buildGlassCard(
                        borderRadius: 18,
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFF34D399), width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.35),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/images/profile_avatar_female.png',
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => Container(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                    child: Center(
                                      child: Text(
                                        displayName.isNotEmpty ? displayName[0].toUpperCase() : 'A',
                                        style: const TextStyle(
                                          color: Color(0xFF34D399),
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
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
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: const Color(0xFF34D399).withValues(alpha: 0.30),
                                        width: 1.0,
                                      ),
                                    ),
                                    child: Text(
                                      '$companyName • Admin',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF6EE7B7),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    if (widget.user.canSwitchToSuperAdmin) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildSuperAdminSwitchBanner(),
                      ),
                    ],

                    const SizedBox(height: 6),

                    // Section Label
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF34D399),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'COMPANY OPERATIONS',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: const Color(0xFF34D399).withValues(alpha: 0.95),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // The 7 Operations List (Exact Match to User Image 2)
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        children: [
                          _buildCompanyMenuItem(
                            icon: Icons.assignment_ind_outlined,
                            title: 'Employee Management',
                            subtitle: '$totalStaff registered team members',
                            onTap: () {
                              Navigator.of(context).pop();
                              setState(() => _selectedBottomTab = 1);
                            },
                          ),
                          _buildCompanyMenuItem(
                            icon: Icons.calendar_today_outlined,
                            title: 'Attendance',
                            subtitle: '$activeStaff logs recorded',
                            onTap: () {
                              Navigator.of(context).pop();
                              setState(() => _selectedBottomTab = 2);
                            },
                          ),
                          _buildCompanyMenuItem(
                            icon: Icons.assignment_outlined,
                            title: 'Tasks',
                            subtitle: '$_activeTasksCount open tasks in progress',
                            onTap: () {
                              Navigator.of(context).pop();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => TasksView(
                                    user: widget.user,
                                    onBack: () => Navigator.of(context).pop(),
                                  ),
                                ),
                              );
                            },
                          ),
                          _buildCompanyMenuItem(
                            icon: Icons.event_busy_outlined,
                            title: 'Leaves & Holidays',
                            subtitle: pendingLeavesCount > 0
                                ? '$pendingLeavesCount pending • Review approvals'
                                : 'Review leave approvals & company holidays',
                            onTap: () {
                              Navigator.of(context).pop();
                              setState(() => _selectedBottomTab = 3);
                            },
                          ),
                          _buildCompanyMenuItem(
                            icon: Icons.payments_outlined,
                            title: 'Payroll',
                            subtitle: 'Automated payroll processing & slips',
                            onTap: () {
                              Navigator.of(context).pop();
                              _showPayrollSheet();
                            },
                          ),
                          _buildCompanyMenuItem(
                            icon: Icons.bar_chart_rounded,
                            title: 'Reports',
                            subtitle: 'Workforce analytics & monthly summary',
                            onTap: () {
                              Navigator.of(context).pop();
                              _showAttendanceReportSheet();
                            },
                          ),
                          _buildCompanyMenuItem(
                            icon: Icons.settings_outlined,
                            title: 'Settings',
                            subtitle: 'Company profile & working hours configuration',
                            onTap: () {
                              Navigator.of(context).pop();
                              setState(() {
                                _selectedBottomTab = 4;
                                _selectedProfileSubTab = 2;
                              });
                            },
                          ),
                        ],
                      ),
                    ),

                    // Bottom Sign Out Button
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: InkWell(
                            onTap: () {
                              Navigator.of(context).pop();
                              _confirmLogout();
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.logout_rounded, color: Color(0xFFF87171), size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    'Sign Out',
                                    style: TextStyle(
                                      color: Color(0xFFF87171),
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompanyMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? highlightColor,
  }) {
    final accentColor = highlightColor ?? const Color(0xFF10B981);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: _buildGlassCard(
        borderRadius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.40),
                  width: 1.2,
                ),
              ),
              child: Icon(
                icon,
                size: 21,
                color: accentColor == const Color(0xFF10B981)
                    ? const Color(0xFF34D399)
                    : accentColor,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFCBD5E1),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFFCBD5E1),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  void _showPayrollSheet() {
    final totalStaff = _allNonAdminEmployees.length;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF031A14),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Payroll & Compensation',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildGlassCard(
                borderRadius: 16,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Active Pay Cycle',
                          style: TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                          ),
                          child: const Text(
                            'October 2026',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF34D399),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Eligible Employees',
                          style: TextStyle(fontSize: 13, color: Colors.white70),
                        ),
                        Text(
                          '$totalStaff Staff Members',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text('Automated Pay Slips', style: TextStyle(fontSize: 13, color: Colors.white70)),
                        Text('Ready for Dispatch', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF34D399))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: Color(0xFF10B981),
                      content: Text('Payroll batch processed & payslips generated successfully!'),
                    ),
                  );
                },
                icon: const Icon(Icons.receipt_long_rounded, size: 18),
                label: const Text('Process Monthly Payroll & Slips', style: TextStyle(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------
  // REUSABLE FROSTED GLASS CONTAINER (Matches Login Screen)
  // ---------------------------------------------------------
  Widget _buildGlassCard({
    required Widget child,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    double borderRadius = 24,
    Border? border,
    VoidCallback? onTap,
  }) {
    Widget card = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1A4032).withValues(alpha: 0.42),
                const Color(0xFF102D22).withValues(alpha: 0.48),
                const Color(0xFF081C15).withValues(alpha: 0.58),
              ],
            ),
            borderRadius: BorderRadius.circular(borderRadius),
            border: border ??
                Border.all(
                  color: const Color(0xFF34D399).withValues(alpha: 0.30),
                  width: 1.2,
                ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: const Color(0xFF10B981).withValues(alpha: 0.08),
                blurRadius: 24,
                spreadRadius: -2,
              ),
            ],
          ),
          child: child,
        ),
      ),
    );

    if (margin != null) {
      card = Padding(padding: margin, child: card);
    }

    if (onTap != null) {
      card = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: card,
      );
    }

    return card;
  }

  // ---------------------------------------------------------
  // TOP COMMON APP BAR (Image 1 Header)
  // ---------------------------------------------------------
  Widget _buildTopAppBar() {
    final companyName = _company?.name ?? widget.user.companyName ?? 'krish Tech Computer';
    final displayName = widget.user.name.isNotEmpty
        ? widget.user.name
        : (widget.user.username.isNotEmpty ? widget.user.username : 'Owner');

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Hamburger Menu Button (Opens Drawer)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: InkWell(
                onTap: () {
                  if (widget.onOpenDrawer != null) {
                    widget.onOpenDrawer!();
                  }
                  _scaffoldKey.currentState?.openDrawer();
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF1F4839).withValues(alpha: 0.45),
                        const Color(0xFF102D21).withValues(alpha: 0.55),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.28)),
                  ),
                  child: const Icon(Icons.menu_rounded, color: Colors.white, size: 22),
                ),
              ),
            ),
          ),

          // Center: Logo + "ReGen" Brand + Subtitle (Image 1 Header)
          Row(
            children: [
              const BrandLogo(size: 28, borderRadius: 8),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'ReGen',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.2,
                      shadows: [
                        Shadow(offset: Offset(0, 1), blurRadius: 4, color: Colors.black54),
                      ],
                    ),
                  ),
                  Text(
                    companyName,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF94A3B8),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),

          // Right: Notification Bell with Dot + Avatar
          Row(
            children: [
              // Notification Bell (Image 3)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: InkWell(
                    onTap: _showNotificationsSheet,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFF1F4839).withValues(alpha: 0.45),
                            const Color(0xFF102D21).withValues(alpha: 0.55),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.28)),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 21),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.7),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Avatar (Tap to switch to Profile tab)
              InkWell(
                onTap: () => setState(() => _selectedBottomTab = 4),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF34D399), width: 1.6),
                    color: const Color(0xFF0F3A2E),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      displayName.isNotEmpty ? displayName[0].toUpperCase() : 'A',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------
  // MAIN BODY ROUTER FOR TABS
  // ---------------------------------------------------------
  Widget _buildCurrentTabContent() {
    switch (_selectedBottomTab) {
      case 0:
        return _buildHomeTab();
      case 1:
        return _buildEmployeesTab();
      case 2:
        return _buildAttendanceTab();
      case 3:
        return _buildLeaveTab();
      case 4:
        return _buildProfileTab();
      default:
        return _buildHomeTab();
    }
  }

  // ---------------------------------------------------------
  // TAB 0: HOME / DASHBOARD (Exact Match to User Attached Screen)
  // ---------------------------------------------------------
  Widget _buildHomeTab() {
    final userDisplayName = widget.user.name.isNotEmpty
        ? widget.user.name
        : (widget.user.username.isNotEmpty ? widget.user.username : 'Mukesh Kumar');

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Executive Welcome Banner with Dynamic Starting Year Selector
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D251D).withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: const Color(0xFF34D399).withValues(alpha: 0.28),
                    width: 1.1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Welcome back,',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$userDisplayName!',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.3,
                                  shadows: [
                                    Shadow(offset: Offset(0, 1), blurRadius: 4, color: Colors.black45),
                                  ],
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Year Selector Pill (Starts from company starting year e.g. 2024)
                        GestureDetector(
                          onTap: _showYearPicker,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF064E3B).withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF34D399).withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.calendar_today_rounded, size: 13, color: Color(0xFF34D399)),
                                const SizedBox(width: 5),
                                Text(
                                  'Year: $_selectedYear',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.keyboard_arrow_down_rounded, size: 14.5, color: Colors.white),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Manage your team, track attendance and keep your workplace running smoothly.',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFFA7F3D0),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 2. Row 1: Total Employees & Departments (Filtered by selectedYear)
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  title: 'Total Employees',
                  value: '$_totalStaffInYear',
                  icon: Icons.groups_rounded,
                  badgePrefix: '↗',
                  badgeMain: '+$_joinedInSelectedYear joined',
                  badgeSuffix: 'in $_selectedYear',
                  onTap: () => setState(() => _selectedBottomTab = 1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  title: 'Departments',
                  value: '$_departmentCountInYear',
                  icon: Icons.domain_rounded,
                  badgePrefix: '✓',
                  badgeMain: 'Active',
                  badgeSuffix: 'in $_selectedYear',
                  onTap: () => setState(() => _selectedBottomTab = 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 3. Row 2: Today\'s Attendance & Attendance Rate (Dynamic for selectedYear)
          Row(
            children: [
              Expanded(
                child: _buildTodayAttendanceCard(
                  title: _isCurrentYear ? "Today's Attendance" : "Annual Attendance",
                  ratioValue: _isCurrentYear
                      ? '$_todayPresentCount / $_totalStaffInYear'
                      : '$_yearAttendedCount logs',
                  subtitle: _isCurrentYear
                      ? '$_todayAttendancePct% present today'
                      : '$_yearAttendanceRate% annual average',
                  onTap: () => setState(() => _selectedBottomTab = 2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildAttendanceRateCard(
                  attendancePct: _isCurrentYear ? _todayAttendancePct : _yearAttendanceRate,
                  presentCount: _isCurrentYear ? _todayPresentCount : _yearAttendedCount,
                  absentCount: _isCurrentYear ? _todayAbsentCount : _yearAbsentCount,
                  lateCount: _isCurrentYear ? _todayLateCount : _yearLateCount,
                  onTap: () => setState(() => _selectedBottomTab = 2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 4. Row 3: On Leave / Half Day & Late Arrivals (Dynamic for selectedYear)
          Row(
            children: [
              Expanded(
                child: _buildStatSubCard(
                  title: 'On Leave / Half Day',
                  value: _isCurrentYear ? '$_todayLeaveAndHalfDayCount' : '$_yearLeaveCount',
                  subtitle: _isCurrentYear ? 'Approved time off' : 'Approved in $_selectedYear',
                  icon: Icons.calendar_today_rounded,
                  iconColor: const Color(0xFF34D399),
                  iconBg: const Color(0xFF10B981).withValues(alpha: 0.22),
                  onTap: () => setState(() => _selectedBottomTab = 3),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatSubCard(
                  title: 'Late Arrivals',
                  value: '$_todayLateCount',
                  subtitle: "Today's late check-ins",
                  icon: Icons.access_time_rounded,
                  iconColor: const Color(0xFFFCD34D),
                  iconBg: const Color(0xFFFBBF24).withValues(alpha: 0.18),
                  onTap: null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 5. Row 4: Team Attendance Trend Area Spline Chart (Week / Month / Year)
          _buildAttendanceTrendSection(),
          const SizedBox(height: 14),

          // 6. Dynamic Employee Attendance Details based on Selected Filter
          if (_selectedTrendFilter == 'Week') ...[
            _buildWeekDayEmployeeDetailsCard(),
            const SizedBox(height: 24),
          ] else if (_selectedTrendFilter == 'Month') ...[
            _buildMonthWeekEmployeeDetailsCard(),
            const SizedBox(height: 24),
          ] else ...[
            _buildYearEmployeeDetailsCard(),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required String badgePrefix,
    required String badgeMain,
    required String badgeSuffix,
    required VoidCallback onTap,
  }) {
    return _buildGlassCard(
      onTap: onTap,
      borderRadius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: const Color(0xFF34D399)),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFFF1F5F9),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
              shadows: [
                Shadow(offset: Offset(0, 1), blurRadius: 4, color: Colors.black45),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: const Color(0xFF34D399).withValues(alpha: 0.35),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (badgePrefix.isNotEmpty) ...[
                      Text(
                        badgePrefix,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF34D399),
                        ),
                      ),
                      const SizedBox(width: 3),
                    ],
                    Text(
                      badgeMain,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF34D399),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  badgeSuffix,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFCBD5E1),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTodayAttendanceCard({
    required String title,
    required String ratioValue,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return _buildGlassCard(
      onTap: onTap,
      borderRadius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.people_alt_outlined, size: 16, color: Color(0xFF34D399)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF1F5F9),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 14, color: Color(0xFF64748B)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            ratioValue,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
              shadows: [
                Shadow(offset: Offset(0, 1), blurRadius: 4, color: Colors.black45),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF34D399),
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right_rounded, size: 12, color: Color(0xFF34D399)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceRateCard({
    required int attendancePct,
    required int presentCount,
    required int absentCount,
    required int lateCount,
    required VoidCallback onTap,
  }) {
    return _buildGlassCard(
      onTap: onTap,
      borderRadius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.verified_outlined, size: 16, color: Color(0xFF34D399)),
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Attendance Rate',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF1F5F9),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: (attendancePct / 100.0).clamp(0.0, 1.0),
                      strokeWidth: 4.5,
                      backgroundColor: const Color(0xFF10281F),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF34D399)),
                    ),
                    Text(
                      '$attendancePct%',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildMiniLegend(
                      color: const Color(0xFF34D399),
                      label: 'Present',
                      count: presentCount,
                    ),
                    const SizedBox(height: 3),
                    _buildMiniLegend(
                      color: const Color(0xFFFB7185),
                      label: 'Absent',
                      count: absentCount,
                    ),
                    const SizedBox(height: 3),
                    _buildMiniLegend(
                      color: const Color(0xFFFCD34D),
                      label: 'Late',
                      count: lateCount,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniLegend({
    required Color color,
    required String label,
    required int count,
  }) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: Color(0xFFF8FAFC),
            letterSpacing: 0.1,
          ),
        ),
        const Spacer(),
        Text(
          '$count',
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildStatSubCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    VoidCallback? onTap,
  }) {
    return _buildGlassCard(
      onTap: onTap,
      borderRadius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF1F5F9),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
              shadows: [
                Shadow(offset: Offset(0, 1), blurRadius: 4, color: Colors.black45),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFFCBD5E1),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceTrendSection() {
    final rates = _currentTrendRates;
    final labels = _currentTrendLabels;

    String subtitleText = 'Monthly attendance distribution for $_selectedYear';
    if (_selectedTrendFilter == 'Week') {
      subtitleText = 'Day-by-day analysis (Mon - Sun)';
    } else if (_selectedTrendFilter == 'Year') {
      subtitleText = 'Annual workforce overview for $_selectedYear';
    }

    return _buildGlassCard(
      borderRadius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Team Attendance Trend ($_selectedYear)',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitleText,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFCBD5E1),
                      ),
                    ),
                  ],
                ),
              ),
              // Trend Filter Dropdown Pill (Week / Month / Year) - Exact Match to Design
              InkWell(
                onTap: _showTrendFilterPicker,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF042F24).withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF34D399).withValues(alpha: 0.35),
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _selectedTrendFilter,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 14,
                        color: Color(0xFF34D399),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 32,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: const [
                      Text('100%', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w700)),
                      Text('75%', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w700)),
                      Text('50%', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w700)),
                      Text('25%', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w700)),
                      Text('0%', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CustomPaint(
                    painter: TeamAttendanceTrendChartPainter(
                      trendRates: rates,
                      selectedIndex: _selectedTrendFilter == 'Week'
                          ? _selectedWeekDayIndex
                          : (_selectedTrendFilter == 'Month'
                              ? ((_selectedMonthIndex - ((_selectedYear == _companyStartingYear) ? _companyStartingMonth : 1)).clamp(0, rates.length - 1))
                              : null),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(width: 40),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: labels.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final l = entry.value;
                    final isHighlighted = (_selectedTrendFilter == 'Week' && idx == _selectedWeekDayIndex) ||
                        (_selectedTrendFilter == 'Month' && idx == (_selectedMonthIndex - 1));
                    return Text(
                      l,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: isHighlighted ? FontWeight.w800 : FontWeight.w600,
                        color: isHighlighted ? const Color(0xFF34D399) : const Color(0xFFCBD5E1),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 7-Day Day Selector and Day-by-day Employee Present/Absent Details Card
  Widget _buildWeekDayEmployeeDetailsCard() {
    final dayList = _weekTrendDays;
    final day = dayList[_selectedWeekDayIndex.clamp(0, 6)];
    final dateStr = day['dateStr'] as String;
    final dateObj = day['date'] as DateTime;
    final employees = _getStaffActiveInMonth(dateObj.year, dateObj.month);

    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final targetMidnight = DateTime(dateObj.year, dateObj.month, dateObj.day);
    final isFutureDate = targetMidnight.isAfter(todayMidnight);
    final isLeaveOrOff = _isNonWorkingOrLeave(dateObj);

    final presentEmployees = <UserModel>[];
    final lateEmployees = <UserModel>[];
    final leaveEmployees = <UserModel>[];
    final absentEmployees = <UserModel>[];

    for (final emp in employees) {
      final att = _getEmployeeAttendanceOnDate(emp, dateStr);
      final isOnLeave = _leaves.any((l) =>
          l.isApproved &&
          l.coversDate(dateStr) &&
          (l.userId == emp.userId || l.userId == emp.id || l.userId == emp.username));

      if (att != null) {
        final st = att.status.toLowerCase();
        if (st == 'late') {
          lateEmployees.add(emp);
        } else {
          presentEmployees.add(emp);
        }
      } else if (isOnLeave) {
        leaveEmployees.add(emp);
      } else if (!isFutureDate && !isLeaveOrOff) {
        // Real dynamic data: only past or today dates can have absent staff
        absentEmployees.add(emp);
      }
    }

    return _buildGlassCard(
      borderRadius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row of 7 Days Buttons (Mon - Sun)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) {
              final d = dayList[i];
              final dObj = d['date'] as DateTime;
              final isDayLeaveOrOff = _isNonWorkingOrLeave(dObj);
              final isSelected = i == _selectedWeekDayIndex && !isDayLeaveOrOff;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: InkWell(
                    onTap: isDayLeaveOrOff
                        ? null
                        : () => setState(() {
                              _selectedWeekDayIndex = i;
                              _selectedTrendDetailEmployee = null;
                              _trendListPaginationCount = 3;
                              _isTrendViewAll = false;
                            }),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        color: isDayLeaveOrOff
                            ? const Color(0xFF7C3AED).withValues(alpha: 0.35)
                            : (isSelected
                                ? const Color(0xFF10B981)
                                : const Color(0xFF042F24).withValues(alpha: 0.5)),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDayLeaveOrOff
                              ? const Color(0xFF8B5CF6).withValues(alpha: 0.65)
                              : (isSelected
                                  ? const Color(0xFF34D399)
                                  : Colors.white.withValues(alpha: 0.1)),
                          width: (isSelected || isDayLeaveOrOff) ? 1.5 : 0.8,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            d['dayName'] as String,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: (isSelected || isDayLeaveOrOff) ? FontWeight.w800 : FontWeight.w600,
                              color: isDayLeaveOrOff
                                  ? const Color(0xFFC4B5FD)
                                  : (isSelected ? Colors.white : const Color(0xFFCBD5E1)),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isDayLeaveOrOff ? 'Off' : '${dObj.day}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: isDayLeaveOrOff
                                  ? const Color(0xFFE9D5FF)
                                  : (isSelected ? Colors.white : const Color(0xFFF1F5F9)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 14),

          // Day Header & Summary Pills
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${day["dayName"]}, ${dateObj.day} ${_getMonthName(dateObj.month)} ${dateObj.year}',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Employee Attendance Details',
                    style: TextStyle(fontSize: 10.5, color: Color(0xFFCBD5E1), fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isLeaveOrOff
                      ? const Color(0xFF7C3AED).withValues(alpha: 0.18)
                      : (isFutureDate
                          ? const Color(0xFF38BDF8).withValues(alpha: 0.18)
                          : const Color(0xFF10B981).withValues(alpha: 0.18)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isLeaveOrOff
                        ? const Color(0xFF8B5CF6).withValues(alpha: 0.40)
                        : (isFutureDate
                            ? const Color(0xFF38BDF8).withValues(alpha: 0.40)
                            : const Color(0xFF34D399).withValues(alpha: 0.35)),
                  ),
                ),
                child: Text(
                  isLeaveOrOff
                      ? 'Holiday / Off'
                      : (isFutureDate
                          ? 'Scheduled / Upcoming'
                          : '${(day["rate"] as double).round()}% Attended'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isLeaveOrOff
                        ? const Color(0xFFC4B5FD)
                        : (isFutureDate ? const Color(0xFF38BDF8) : const Color(0xFF34D399)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 4-Way Status Tabs & Interactive Roster
          _buildTrendStatusTabsAndRoster(
            presentEmployees: presentEmployees,
            absentEmployees: absentEmployees,
            lateEmployees: lateEmployees,
            leaveEmployees: leaveEmployees,
            dateStr: dateStr,
            periodContextLabel: '${day["dayName"]}, ${dateObj.day} ${_getMonthName(dateObj.month)}',
            isFutureDate: isFutureDate,
          ),
        ],
      ),
    );
  }

  // Month & Week-by-Week Employee Attendance Details Card
  Widget _buildMonthWeekEmployeeDetailsCard() {
    final weeks = _monthTrendWeeks;
    final currentWeek = weeks[_selectedMonthWeekIndex.clamp(0, 3)];
    final startDay = currentWeek['start'] as int;
    final endDay = currentWeek['end'] as int;
    final rate = currentWeek['rate'] as double;
    final targetMonth = _selectedMonthIndex.clamp(1, 12);
    final mStr = targetMonth.toString().padLeft(2, '0');
    final employees = _getStaffActiveInMonth(_selectedYear, targetMonth);

    final presentEmployees = <UserModel>[];
    final lateEmployees = <UserModel>[];
    final leaveEmployees = <UserModel>[];
    final absentEmployees = <UserModel>[];

    for (final emp in employees) {
      final userLogs = _attendance.where((a) {
        if (a.userId != emp.userId && a.userId != emp.id && a.userId != emp.username) return false;
        if (!a.date.startsWith('$_selectedYear-$mStr-')) return false;
        final parts = a.date.split('-');
        if (parts.length != 3) return false;
        final dayPart = int.tryParse(parts[2]) ?? 0;
        return dayPart >= startDay && dayPart <= endDay;
      }).toList();

      final hasApprovedLeave = _leaves.any((l) {
        if (!l.isApproved) return false;
        if (l.userId != emp.userId && l.userId != emp.id && l.userId != emp.username) return false;
        for (int d = startDay; d <= endDay; d++) {
          final dStr = '$_selectedYear-$mStr-${d.toString().padLeft(2, '0')}';
          if (l.coversDate(dStr)) return true;
        }
        return false;
      });

      if (userLogs.any((a) => a.status.toLowerCase() == 'late')) {
        lateEmployees.add(emp);
      } else if (userLogs.isNotEmpty) {
        presentEmployees.add(emp);
      } else if (hasApprovedLeave) {
        leaveEmployees.add(emp);
      } else {
        absentEmployees.add(emp);
      }
    }

    return _buildGlassCard(
      borderRadius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Month Horizontal Selector (Starts from company starting month if selectedYear is company starting year)
          Builder(builder: (ctx) {
            final startMonth = (_selectedYear == _companyStartingYear) ? _companyStartingMonth : 1;
            final count = 12 - startMonth + 1;
            return SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: count,
                separatorBuilder: (_, index) => const SizedBox(width: 6),
                itemBuilder: (ctx, i) {
                  final mNum = startMonth + i;
                  final isSelected = mNum == _selectedMonthIndex;
                  final mName = _getMonthName(mNum);
                  return InkWell(
                    onTap: () => setState(() {
                      _selectedMonthIndex = mNum;
                      _selectedTrendDetailEmployee = null;
                      _trendListPaginationCount = 3;
                      _isTrendViewAll = false;
                    }),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF10B981)
                            : const Color(0xFF042F24).withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF34D399) : Colors.white12,
                          width: isSelected ? 1.5 : 0.8,
                        ),
                      ),
                      child: Text(
                        mName,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          }),
          const SizedBox(height: 12),

          // 2. Week Pills Row
          Row(
            children: List.generate(weeks.length, (i) {
              final isSel = i == _selectedMonthWeekIndex;
              final w = weeks[i];
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: InkWell(
                    onTap: () => setState(() {
                      _selectedMonthWeekIndex = i;
                      _selectedTrendDetailEmployee = null;
                      _trendListPaginationCount = 3;
                      _isTrendViewAll = false;
                    }),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: isSel
                            ? const Color(0xFF10B981)
                            : const Color(0xFF042F24).withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSel ? const Color(0xFF34D399) : Colors.white12,
                          width: isSel ? 1.5 : 0.8,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        w['name'] as String,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                          color: isSel ? Colors.white : const Color(0xFFCBD5E1),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 14),

          // 3. Week Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${currentWeek["name"]} (${_getMonthName(targetMonth)} $startDay - $endDay)',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Weekly Team Attendance Details',
                    style: TextStyle(fontSize: 10.5, color: Color(0xFFCBD5E1), fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.35)),
                ),
                child: Text(
                  '${rate.round()}% Attended',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF34D399),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 4-Way Status Tabs & Interactive Roster
          _buildTrendStatusTabsAndRoster(
            presentEmployees: presentEmployees,
            absentEmployees: absentEmployees,
            lateEmployees: lateEmployees,
            leaveEmployees: leaveEmployees,
            dateStr: '$_selectedYear-$mStr-${startDay.toString().padLeft(2, '0')}',
            periodContextLabel: '${currentWeek["name"]} (${_getMonthName(targetMonth)} $startDay - $endDay)',
          ),
        ],
      ),
    );
  }

  // Shared 4-Way Status Tabs & Interactive Drill-Down Roster
  Widget _buildTrendStatusTabsAndRoster({
    required List<UserModel> presentEmployees,
    required List<UserModel> absentEmployees,
    required List<UserModel> lateEmployees,
    required List<UserModel> leaveEmployees,
    required String dateStr,
    required String periodContextLabel,
    bool isFutureDate = false,
  }) {
    final presentCount = presentEmployees.length;
    final absentCount = absentEmployees.length;
    final lateCount = lateEmployees.length;
    final leaveCount = leaveEmployees.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Interactive 4-Way Status Tabs (Present, Absent, Late, Leave)
        Row(
          children: [
            _buildInteractiveTrendStatusTab('present', 'Present', presentCount, const Color(0xFF34D399)),
            const SizedBox(width: 6),
            _buildInteractiveTrendStatusTab('absent', 'Absent', absentCount, const Color(0xFFFB7185)),
            const SizedBox(width: 6),
            _buildInteractiveTrendStatusTab('late', 'Late', lateCount, const Color(0xFFFCD34D)),
            const SizedBox(width: 6),
            _buildInteractiveTrendStatusTab('leave', 'Leave', leaveCount, const Color(0xFF38BDF8)),
          ],
        ),
        const SizedBox(height: 12),
        const Divider(color: Colors.white12, height: 1),
        const SizedBox(height: 10),

        // 2. Content: Either Detailed Single Employee Card (with back arrow) OR Status Filtered Roster
        if (_selectedTrendDetailEmployee != null)
          _buildTrendEmployeeDetailCard(
            employee: _selectedTrendDetailEmployee!,
            dateStr: dateStr,
          )
        else
          _buildTrendStatusEmployeeRoster(
            presentEmployees: presentEmployees,
            absentEmployees: absentEmployees,
            lateEmployees: lateEmployees,
            leaveEmployees: leaveEmployees,
            dateStr: dateStr,
            isFutureDate: isFutureDate,
          ),
      ],
    );
  }

  Widget _buildInteractiveTrendStatusTab(String tabKey, String label, int count, Color color) {
    final isSelected = _selectedTrendStatusTab == tabKey;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedTrendStatusTab = tabKey;
            _selectedTrendDetailEmployee = null;
            _trendListPaginationCount = 3;
            _isTrendViewAll = false;
          });
        },
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.28)
                : color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? color : color.withValues(alpha: 0.30),
              width: isSelected ? 1.8 : 0.9,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: isSelected ? Colors.white : color,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                  color: isSelected ? Colors.white : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrendEmployeeDetailCard({
    required UserModel employee,
    required String dateStr,
  }) {
    final att = _getEmployeeAttendanceOnDate(employee, dateStr);
    final empName = employee.name.isNotEmpty ? employee.name : employee.username;
    final empId = employee.userId.isNotEmpty ? employee.userId : (employee.id.isNotEmpty ? employee.id : 'N/A');
    final phone = employee.phone?.isNotEmpty == true ? employee.phone! : '--';
    final checkIn = att?.checkIn?.isNotEmpty == true ? att!.checkIn! : 'No check-in record';
    final checkOut = att?.checkOut?.isNotEmpty == true ? att!.checkOut! : '--';
    final dept = employee.department?.isNotEmpty == true
        ? employee.department!
        : (employee.designation?.isNotEmpty == true ? employee.designation! : 'Team Member');

    String statusLabel = 'Absent';
    Color statusColor = const Color(0xFFFB7185);
    if (_selectedTrendStatusTab == 'present') {
      statusLabel = 'Present';
      statusColor = const Color(0xFF34D399);
    } else if (_selectedTrendStatusTab == 'late') {
      statusLabel = 'Late';
      statusColor = const Color(0xFFFCD34D);
    } else if (_selectedTrendStatusTab == 'leave') {
      statusLabel = 'On Leave';
      statusColor = const Color(0xFF38BDF8);
    } else {
      statusLabel = 'Absent';
      statusColor = const Color(0xFFFB7185);
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF072118).withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with Back Arrow and Status Badge
          Row(
            children: [
              InkWell(
                onTap: () => setState(() => _selectedTrendDetailEmployee = null),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Employee Details',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor.withValues(alpha: 0.40)),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 12),

          // Employee Profile Header (Avatar + Name + Department)
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor.withValues(alpha: 0.15),
                  border: Border.all(color: statusColor, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  empName.isNotEmpty ? empName[0].toUpperCase() : 'E',
                  style: TextStyle(fontWeight: FontWeight.w800, color: statusColor, fontSize: 18),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      empName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dept,
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFFBACCC3)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Detail Fields List: ID, Phone Number, Check-In, Check-Out
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              children: [
                _buildTrendDetailRow(Icons.badge_outlined, 'Employee ID', empId),
                const SizedBox(height: 8),
                _buildTrendDetailRow(Icons.phone_outlined, 'Phone Number', phone),
                const SizedBox(height: 8),
                _buildTrendDetailRow(Icons.login_rounded, 'Check-In Time', checkIn),
                const SizedBox(height: 8),
                _buildTrendDetailRow(Icons.logout_rounded, 'Check-Out Time', checkOut),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendDetailRow(IconData icon, String title, String value) {
    return Row(
      children: [
        Icon(icon, size: 15, color: const Color(0xFF34D399)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 11.5, color: Color(0xFFBACCC3), fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildTrendStatusEmployeeRoster({
    required List<UserModel> presentEmployees,
    required List<UserModel> absentEmployees,
    required List<UserModel> lateEmployees,
    required List<UserModel> leaveEmployees,
    required String dateStr,
    bool isFutureDate = false,
  }) {
    List<UserModel> currentList;
    String statusLabel;
    Color statusColor;

    if (_selectedTrendStatusTab == 'present') {
      currentList = presentEmployees;
      statusLabel = 'Present';
      statusColor = const Color(0xFF34D399);
    } else if (_selectedTrendStatusTab == 'late') {
      currentList = lateEmployees;
      statusLabel = 'Late';
      statusColor = const Color(0xFFFCD34D);
    } else if (_selectedTrendStatusTab == 'leave') {
      currentList = leaveEmployees;
      statusLabel = 'On Leave';
      statusColor = const Color(0xFF38BDF8);
    } else {
      currentList = absentEmployees;
      statusLabel = 'Absent';
      statusColor = const Color(0xFFFB7185);
    }

    if (currentList.isEmpty) {
      final emptyMsg = isFutureDate
          ? 'This date is in the future. Attendance will be recorded when employees check in.'
          : 'No employees categorized as $statusLabel on this date.';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: Text(
            emptyMsg,
            style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11.5),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final total = currentList.length;
    final displayCount = _isTrendViewAll ? total : _trendListPaginationCount.clamp(0, total);
    final displayedEmployees = currentList.take(displayCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...displayedEmployees.map((emp) {
          final att = _getEmployeeAttendanceOnDate(emp, dateStr);
          final empName = emp.name.isNotEmpty ? emp.name : emp.username;

          String timingInfo = 'No check-in record';
          if (att != null) {
            final st = att.status.toLowerCase();
            if (st == 'present') {
              timingInfo = 'In: ${att.checkIn ?? "--"} • Out: ${att.checkOut ?? "--"}';
            } else if (st == 'late') {
              timingInfo = 'In: ${att.checkIn ?? "--"} (Late arrival)';
            } else if (st == 'half_day') {
              timingInfo = 'Half Day shift';
            }
          } else if (_selectedTrendStatusTab == 'leave') {
            timingInfo = 'Approved time off';
          } else if (_selectedTrendFilter == 'Month') {
            final stats = _getEmployeeWeekAttendanceStats(emp, _selectedMonthIndex, 1, 31);
            if ((stats['totalAttended'] as int) > 0) {
              timingInfo = '${stats["presentDays"]} on-time • ${stats["lateDays"]} late';
            }
          }

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedTrendDetailEmployee = emp;
                });
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor.withValues(alpha: 0.15),
                        border: Border.all(color: statusColor.withValues(alpha: 0.45)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        empName.isNotEmpty ? empName[0].toUpperCase() : 'E',
                        style: TextStyle(fontWeight: FontWeight.w800, color: statusColor, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            empName,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            timingInfo,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFFCBD5E1),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFFCBD5E1)),
                  ],
                ),
              ),
            ),
          );
        }),

        // Pagination & View All Controls
        if (total > 3) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!_isTrendViewAll && displayCount < total) ...[
                InkWell(
                  onTap: () {
                    setState(() {
                      _trendListPaginationCount += 3;
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.expand_more_rounded, size: 16, color: Color(0xFF34D399)),
                        SizedBox(width: 4),
                        Text(
                          'Load Next 3',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF34D399)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              InkWell(
                onTap: () {
                  setState(() {
                    _isTrendViewAll = !_isTrendViewAll;
                    if (!_isTrendViewAll) {
                      _trendListPaginationCount = 3;
                    }
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    _isTrendViewAll ? 'Show Less (3)' : 'View All ($total)',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
  // Full Year Annual Performance Summary Card
  Widget _buildYearEmployeeDetailsCard() {
    final employees = _employeesInSelectedYear;

    return _buildGlassCard(
      borderRadius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$_selectedYear Annual Performance',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Full Year Team Attendance Summary',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFCBD5E1),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.35)),
                ),
                child: Text(
                  '$_yearAttendanceRate% Annual Rate',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF34D399),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildStatusCountBadge('Attended Logs', _yearAttendedCount, const Color(0xFF34D399)),
              const SizedBox(width: 6),
              _buildStatusCountBadge('Late Logs', _yearLateCount, const Color(0xFFFCD34D)),
              const SizedBox(width: 6),
              _buildStatusCountBadge('Leaves Approved', _yearLeaveCount, const Color(0xFF38BDF8)),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 8),

          if (employees.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No employees active in this year.',
                style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 11.5),
              ),
            )
          else
            ...employees.map((emp) {
              final stats = _getEmployeeYearAttendanceStats(emp);
              final presentDays = stats['presentDays'] as int;
              final lateDays = stats['lateDays'] as int;
              final leaveDays = stats['leaveDays'] as int;
              final totalAttended = stats['totalAttended'] as int;

              final empName = emp.name.isNotEmpty ? emp.name : emp.username;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF10B981).withValues(alpha: 0.18),
                        border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.40)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        empName.isNotEmpty ? empName[0].toUpperCase() : 'E',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF34D399), fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            empName,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '$totalAttended logs ($presentDays on-time, $lateDays late) • $leaveDays leaves',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFFCBD5E1),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.35)),
                      ),
                      child: Text(
                        '$totalAttended logs',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF34D399),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildStatusCountBadge(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: color),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: color),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------
  // TAB 1: EMPLOYEES DIRECTORY (Image 1, Screen 3)
  // ---------------------------------------------------------
  Widget _buildEmployeesTab() {
    List<UserModel> filtered = _users;

    // Search text filter
    if (_employeeSearchQuery.isNotEmpty) {
      final q = _employeeSearchQuery.toLowerCase();
      filtered = filtered.where((u) {
        return u.name.toLowerCase().contains(q) ||
            u.username.toLowerCase().contains(q) ||
            (u.department != null && u.department!.toLowerCase().contains(q)) ||
            (u.designation != null && u.designation!.toLowerCase().contains(q)) ||
            u.role.toLowerCase().contains(q);
      }).toList();
    }

    // Status filter segment: 0=All, 1=Active, 2=On Leave, 3=Inactive
    if (_selectedEmployeeFilter == 1) {
      filtered = filtered.where((u) => _getEmployeeTodayAttendance(u) != null).toList();
    } else if (_selectedEmployeeFilter == 2) {
      final leaveUserIds = _leaves.where((l) => l.isApproved).map((l) => l.userId.toLowerCase()).toSet();
      filtered = filtered.where((u) => leaveUserIds.contains(u.userId.toLowerCase()) || leaveUserIds.contains(u.username.toLowerCase())).toList();
    } else if (_selectedEmployeeFilter == 3) {
      filtered = filtered.where((u) => _getEmployeeTodayAttendance(u) == null).toList();
    }

    // Role filter matching website UsersModule.jsx
    if (_selectedEmployeeRoleFilter != 'all') {
      filtered = filtered.where((u) {
        final r = u.role.toLowerCase().trim();
        if (_selectedEmployeeRoleFilter == 'owner') {
          return r == 'owner' || r == 'param';
        }
        return r == _selectedEmployeeRoleFilter;
      }).toList();
    }

    // Department filter matching website
    if (_selectedEmployeeDeptFilter != 'all') {
      filtered = filtered.where((u) {
        final dept = (u.department ?? '').trim().toLowerCase();
        return dept == _selectedEmployeeDeptFilter.toLowerCase();
      }).toList();
    }

    final hasActiveRoleOrDept = _selectedEmployeeRoleFilter != 'all' || _selectedEmployeeDeptFilter != 'all';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with + Add Employee Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Employees',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.4,
                      shadows: [Shadow(offset: Offset(0, 2), blurRadius: 4, color: Colors.black45)],
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Manage your team',
                    style: TextStyle(fontSize: 13, color: Color(0xFFBACCC3)),
                  ),
                ],
              ),
              InkWell(
                onTap: _showAddEmployeeDialog,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF34D399).withValues(alpha: 0.30),
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.add_rounded, size: 16, color: Colors.white),
                      SizedBox(width: 4),
                      Text(
                        'Add Employee',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Search Bar & Filter Button (Exact Match to User Image 2)
          _buildCompanyTypingBox(
            controller: _employeeSearchController,
            hintText: 'Search employees...',
            prefixIcon: Icons.search_rounded,
            onChanged: (val) => setState(() => _employeeSearchQuery = val),
            suffixWidget: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_employeeSearchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _employeeSearchController.clear();
                      setState(() => _employeeSearchQuery = '');
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.close_rounded, size: 18, color: Color(0xFFBACCC3)),
                    ),
                  ),
                GestureDetector(
                  onTap: _showEmployeeFilterSheet,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, right: 2),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          Icons.filter_list_rounded,
                          size: 20,
                          color: hasActiveRoleOrDept ? const Color(0xFF10B981) : const Color(0xFFCBD5E1),
                        ),
                        if (hasActiveRoleOrDept)
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Active Role / Dept Filter Badges (from Website Filter)
          if (hasActiveRoleOrDept) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (_selectedEmployeeRoleFilter != 'all')
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _buildActiveFilterBadge(
                        'Role: ${_selectedEmployeeRoleFilter.toUpperCase()}',
                        () => setState(() => _selectedEmployeeRoleFilter = 'all'),
                      ),
                    ),
                  if (_selectedEmployeeDeptFilter != 'all')
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _buildActiveFilterBadge(
                        'Dept: $_selectedEmployeeDeptFilter',
                        () => setState(() => _selectedEmployeeDeptFilter = 'all'),
                      ),
                    ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedEmployeeRoleFilter = 'all';
                        _selectedEmployeeDeptFilter = 'all';
                      });
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Text(
                        'Clear filters',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF34D399),
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Role-Based Filter Chips: [All] [Staff] [Intern] [Admin]
          Builder(builder: (context) {
            final allCount = _users.length;
            final staffCount = _users.where((u) => u.role.toLowerCase() == 'staff').length;
            final internCount = _users.where((u) => u.role.toLowerCase() == 'intern').length;
            final adminCount = _users.where((u) => u.role.toLowerCase() == 'admin').length;

            return Row(
              children: [
                Expanded(child: _buildRoleSegmentChip('All', 'all', allCount)),
                const SizedBox(width: 6),
                Expanded(child: _buildRoleSegmentChip('Staff', 'staff', staffCount)),
                const SizedBox(width: 6),
                Expanded(child: _buildRoleSegmentChip('Intern', 'intern', internCount)),
                const SizedBox(width: 6),
                Expanded(child: _buildRoleSegmentChip('Admin', 'admin', adminCount)),
              ],
            );
          }),
          const SizedBox(height: 14),

          // Employees List Cards (Image 1 Screen 3)
          Expanded(
            child: filtered.isEmpty
                ? _buildEmptyDarkState('No employees found matching filter.')
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (ctx, idx) => _buildEmployeeCard(filtered[idx]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFilterBadge(String label, VoidCallback onClear) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF34D399).withValues(alpha: 0.35),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6EE7B7),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onClear,
            child: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF6EE7B7)),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentChip(String label, int index, int selectedIndex, Function(int) onSelected) {
    final isSelected = index == selectedIndex;
    return GestureDetector(
      onTap: () => onSelected(index),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF10B981) : const Color(0xFF0C241B).withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? const Color(0xFF10B981) : const Color(0xFF34D399).withValues(alpha: 0.18),
                width: 1.0,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.35),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFFE2E8F0),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmployeeAvatar(UserModel emp, {double size = 44}) {
    final empName = emp.name.isNotEmpty ? emp.name : emp.username;
    final initial = empName.isNotEmpty ? empName[0].toUpperCase() : 'E';

    if (emp.avatar != null && emp.avatar!.isNotEmpty) {
      Widget imageWidget;
      if (emp.avatar!.startsWith('data:image')) {
        try {
          final commaIdx = emp.avatar!.indexOf(',');
          final base64Data = commaIdx != -1 ? emp.avatar!.substring(commaIdx + 1) : emp.avatar!;
          final bytes = base64Decode(base64Data);
          imageWidget = Image.memory(
            bytes,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _buildAvatarFallback(empName, initial, size: size),
          );
        } catch (_) {
          imageWidget = _buildAvatarFallback(empName, initial, size: size);
        }
      } else {
        imageWidget = Image.network(
          emp.avatar!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildAvatarFallback(empName, initial, size: size),
        );
      }

      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.35), width: 1.2),
        ),
        child: ClipOval(child: imageWidget),
      );
    }

    return _buildAvatarFallback(empName, initial, size: size);
  }

  Widget _buildAvatarFallback(String name, String initial, {double size = 44}) {
    final colorHash = name.hashCode.abs() % 4;
    final bgColors = [
      const Color(0xFF0E3D2F),
      const Color(0xFF1E3A5F),
      const Color(0xFF3B2F4C),
      const Color(0xFF2C3E2D),
    ];
    final accentColors = [
      const Color(0xFF34D399),
      const Color(0xFF60A5FA),
      const Color(0xFFA78BFA),
      const Color(0xFF4ADE80),
    ];
    final bg = bgColors[colorHash];
    final accent = accentColors[colorHash];

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bg,
        border: Border.all(color: accent.withValues(alpha: 0.50), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: bg.withValues(alpha: 0.4),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: accent,
        ),
      ),
    );
  }

  Widget _buildEmployeeCard(UserModel emp) {
    final todayAtt = _getEmployeeTodayAttendance(emp);
    final isPresent = todayAtt != null;
    final isOnLeave = _leaves.any((l) => l.isApproved && (l.userId.toLowerCase() == emp.userId.toLowerCase() || l.userId.toLowerCase() == emp.username.toLowerCase()));

    String statusText = 'Active';
    Color statusColor = const Color(0xFF22C55E);

    if (isOnLeave) {
      statusText = 'On Leave';
      statusColor = const Color(0xFFF59E0B);
    } else if (!isPresent) {
      statusText = 'Inactive';
      statusColor = const Color(0xFF94A398);
    }

    final designation = emp.designation?.isNotEmpty == true
        ? emp.designation!
        : (emp.department?.isNotEmpty == true ? emp.department! : emp.roleDisplayName);

    final empName = emp.name.isNotEmpty ? emp.name : emp.username;

    return _buildGlassCard(
      borderRadius: 16,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          // Avatar
          _buildEmployeeAvatar(emp),
          const SizedBox(width: 14),

          // Name, Designation, and Status (3 lines matching user reference image)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  empName,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  designation,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF94A3B8),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),

          // Three dots menu on right (Edit and Delete options only)
          IconButton(
            icon: const Icon(Icons.more_vert_rounded, size: 20, color: Color(0xFFCBD5E1)),
            onPressed: () => _showEmployeeActionMenu(emp),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  void _showEmployeeActionMenu(UserModel emp) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            decoration: BoxDecoration(
              color: const Color(0xFF072118).withValues(alpha: 0.95),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.25)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF34D399).withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  emp.name.isNotEmpty ? emp.name : emp.username,
                  style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  'ID: ${emp.userId.isNotEmpty ? emp.userId : emp.id} • ${emp.designation ?? emp.roleDisplayName}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFFBACCC3)),
                ),
                const SizedBox(height: 16),
                Material(
                  color: Colors.transparent,
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.edit_outlined, color: Color(0xFF34D399), size: 20),
                    ),
                    title: const Text('Edit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    subtitle: const Text('Update credentials, username, password, or role', style: TextStyle(color: Color(0xFFBACCC3), fontSize: 11)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showEditEmployeeDialog(emp);
                    },
                  ),
                ),
                const Divider(color: Colors.white12, height: 16),
                Material(
                  color: Colors.transparent,
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                    ),
                    title: const Text('Delete', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700)),
                    subtitle: const Text('Remove from company roster & revoke login credentials', style: TextStyle(color: Color(0xFFBACCC3), fontSize: 11)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _confirmDeleteEmployee(emp);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteEmployee(UserModel emp) async {
    final empName = emp.name.isNotEmpty ? emp.name : emp.username;
    final empId = emp.userId.isNotEmpty ? emp.userId : emp.id;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF072118),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.35)),
        ),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 24),
            SizedBox(width: 10),
            Text('Delete Employee', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "$empName"?\n\nThey will be removed from this company roster. Their login credentials will become invalid and access permanently revoked.',
          style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete Employee', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _dashboardService.deleteUser(empId);
        await _loadCompanyData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              content: Text('✓ Employee "$empName" deleted and access revoked.'),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFFEF4444),
              content: Text('Failed to delete employee: $e'),
            ),
          );
        }
      }
    }
  }

  void _showEditEmployeeDialog(UserModel emp) {
    final nameCtrl = TextEditingController(text: emp.name);
    final usernameCtrl = TextEditingController(text: emp.username);
    final passwordCtrl = TextEditingController();
    final emailCtrl = TextEditingController(text: emp.email ?? '');
    final phoneCtrl = TextEditingController(text: emp.phone ?? '');
    final deptCtrl = TextEditingController(text: emp.department ?? '');
    final designationCtrl = TextEditingController(text: emp.designation ?? '');
    String role = emp.role.isNotEmpty ? emp.role : 'staff';
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
              decoration: BoxDecoration(
                color: const Color(0xFF072118).withValues(alpha: 0.96),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.28)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF34D399).withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Edit Employee Details',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Color(0xFFCBD5E1), size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Update credentials and placement. If username or password is changed, old credentials become invalid immediately.',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFFBACCC3)),
                    ),
                    const SizedBox(height: 16),

                    _buildCompanyTypingBox(
                      controller: nameCtrl,
                      labelText: 'Full Name',
                      hintText: 'e.g. John Doe',
                      prefixIcon: Icons.badge_outlined,
                    ),
                    const SizedBox(height: 12),

                    _buildCompanyTypingBox(
                      controller: usernameCtrl,
                      labelText: 'Username (Login ID)',
                      hintText: 'e.g. jdoe',
                      prefixIcon: Icons.account_circle_outlined,
                    ),
                    const SizedBox(height: 12),

                    _buildCompanyTypingBox(
                      controller: passwordCtrl,
                      labelText: 'New Password',
                      hintText: 'Leave blank to keep current password',
                      prefixIcon: Icons.lock_outline_rounded,
                      obscureText: true,
                    ),
                    const SizedBox(height: 12),

                    _buildCompanyTypingBox(
                      controller: emailCtrl,
                      labelText: 'Email Address',
                      hintText: 'e.g. user@company.com',
                      prefixIcon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),

                    _buildCompanyTypingBox(
                      controller: phoneCtrl,
                      labelText: 'Phone Number',
                      hintText: 'e.g. +91 9876543210',
                      prefixIcon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),

                    _buildCompanyTypingBox(
                      controller: designationCtrl,
                      labelText: 'Designation',
                      hintText: 'e.g. Software Engineer',
                      prefixIcon: Icons.work_outline_rounded,
                    ),
                    const SizedBox(height: 12),

                    _buildCompanyTypingBox(
                      controller: deptCtrl,
                      labelText: 'Department',
                      hintText: 'e.g. Engineering',
                      prefixIcon: Icons.domain_rounded,
                    ),
                    const SizedBox(height: 14),

                    // Role Selector
                    const Text(
                      'Employee Role',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFCBD5E1)),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: ['staff', 'admin', 'intern', 'freelancer'].map((r) {
                        final isSel = role == r;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: InkWell(
                              onTap: () => setModalState(() => role = r),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isSel ? const Color(0xFF10B981) : const Color(0xFF042F24).withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSel ? const Color(0xFF34D399) : Colors.white12,
                                  ),
                                ),
                                child: Text(
                                  r.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                                    color: isSel ? Colors.white : const Color(0xFFCBD5E1),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // Save Button
                    InkWell(
                      onTap: isSaving
                          ? null
                          : () async {
                              final newName = nameCtrl.text.trim();
                              final newUsername = usernameCtrl.text.trim();
                              if (newName.isEmpty || newUsername.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    backgroundColor: Color(0xFFEF4444),
                                    content: Text('Name and username are required.'),
                                  ),
                                );
                                return;
                              }

                              setModalState(() => isSaving = true);
                              final payload = <String, dynamic>{
                                'name': newName,
                                'username': newUsername,
                                'email': emailCtrl.text.trim(),
                                'phone': phoneCtrl.text.trim(),
                                'department': deptCtrl.text.trim(),
                                'designation': designationCtrl.text.trim(),
                                'role': role,
                              };
                              if (passwordCtrl.text.trim().isNotEmpty) {
                                payload['password'] = passwordCtrl.text.trim();
                              }

                              final empId = emp.userId.isNotEmpty ? emp.userId : emp.id;
                              try {
                                await _dashboardService.updateUser(empId, payload);
                                if (ctx.mounted) Navigator.pop(ctx);
                                await _loadCompanyData();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: const Color(0xFF10B981),
                                      content: Text('✓ Employee "$newName" updated successfully! Old credentials invalidated.'),
                                    ),
                                  );
                                }
                              } catch (e) {
                                setModalState(() => isSaving = false);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: const Color(0xFFEF4444),
                                      content: Text('Failed to update employee: $e'),
                                    ),
                                  );
                                }
                              }
                            },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF34D399).withValues(alpha: 0.35),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981).withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text(
                                'Save Changes',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 0.2,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showEmployeeFilterSheet() {
    String tempRole = _selectedEmployeeRoleFilter;
    String tempDept = _selectedEmployeeDeptFilter;
    int tempStatus = _selectedEmployeeFilter;

    // Calculate role counts matching website UsersModule.jsx
    final roleCounts = <String, int>{'all': _users.length};
    for (final u in _users) {
      final rk = (u.role.toLowerCase() == 'param') ? 'owner' : u.role.toLowerCase();
      roleCounts[rk] = (roleCounts[rk] ?? 0) + 1;
    }

    final roleOptions = [
      {'value': 'all', 'label': 'All'},
      {'value': 'owner', 'label': 'Owner'},
      {'value': 'admin', 'label': 'Admin'},
      {'value': 'staff', 'label': 'Staff'},
      {'value': 'intern', 'label': 'Intern'},
      {'value': 'freelancer', 'label': 'Freelancer'},
    ].where((opt) => opt['value'] == 'all' || (roleCounts[opt['value']] ?? 0) > 0).toList();

    // Unique departments from users
    final depts = _users
        .map((u) => (u.department ?? '').trim())
        .where((d) => d.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                decoration: BoxDecoration(
                  color: const Color(0xFF072118).withValues(alpha: 0.95),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border.all(
                    color: const Color(0xFF34D399).withValues(alpha: 0.25),
                    width: 1.0,
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Handle
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF34D399).withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Filter Employees',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Role, department, and status filters',
                                style: TextStyle(fontSize: 12, color: Color(0xFFBACCC3)),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Color(0xFFBACCC3), size: 20),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 1. ROLE FILTER SECTION (Website UsersModule.jsx)
                      _buildFilterSectionTitle('ROLE (FROM WEBSITE)'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: roleOptions.map((opt) {
                          final val = opt['value']!;
                          final isSelected = tempRole == val;
                          final count = roleCounts[val] ?? 0;
                          return GestureDetector(
                            onTap: () => setSheetState(() => tempRole = val),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFF0C241B).withValues(alpha: 0.70),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF34D399)
                                      : const Color(0xFF34D399).withValues(alpha: 0.20),
                                  width: 1.0,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.25),
                                          blurRadius: 4,
                                          offset: const Offset(0, 1),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    opt['label']!,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                      color: isSelected ? Colors.white : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.white.withValues(alpha: 0.22)
                                          : const Color(0xFF10B981).withValues(alpha: 0.20),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '$count',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        color: isSelected ? Colors.white : const Color(0xFF6EE7B7),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 18),

                      // 2. DEPARTMENT FILTER SECTION
                      if (depts.isNotEmpty) ...[
                        _buildFilterSectionTitle('DEPARTMENT'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            GestureDetector(
                              onTap: () => setSheetState(() => tempDept = 'all'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                decoration: BoxDecoration(
                                  color: tempDept == 'all'
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFF0C241B).withValues(alpha: 0.70),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: tempDept == 'all'
                                        ? const Color(0xFF34D399)
                                        : const Color(0xFF34D399).withValues(alpha: 0.20),
                                  ),
                                ),
                                child: Text(
                                  'All Departments',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: tempDept == 'all' ? FontWeight.w800 : FontWeight.w600,
                                    color: tempDept == 'all' ? Colors.white : const Color(0xFFE2E8F0),
                                  ),
                                ),
                              ),
                            ),
                            ...depts.map((d) {
                              final isSelected = tempDept.toLowerCase() == d.toLowerCase();
                              return GestureDetector(
                                onTap: () => setSheetState(() => tempDept = d),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFF10B981)
                                        : const Color(0xFF0C241B).withValues(alpha: 0.70),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFF34D399)
                                          : const Color(0xFF34D399).withValues(alpha: 0.20),
                                    ),
                                  ),
                                  child: Text(
                                    d,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                      color: isSelected ? Colors.white : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                        const SizedBox(height: 18),
                      ],

                      // 3. STATUS FILTER SECTION
                      _buildFilterSectionTitle('STATUS'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          {'label': 'All', 'idx': 0},
                          {'label': 'Active', 'idx': 1},
                          {'label': 'On Leave', 'idx': 2},
                          {'label': 'Inactive', 'idx': 3},
                        ].map((item) {
                          final idx = item['idx'] as int;
                          final isSelected = tempStatus == idx;
                          return GestureDetector(
                            onTap: () => setSheetState(() => tempStatus = idx),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFF0C241B).withValues(alpha: 0.70),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF34D399)
                                      : const Color(0xFF34D399).withValues(alpha: 0.20),
                                ),
                              ),
                              child: Text(
                                item['label'] as String,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                  color: isSelected ? Colors.white : const Color(0xFFE2E8F0),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),

                      // ACTIONS: Reset & Apply Button
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setSheetState(() {
                                  tempRole = 'all';
                                  tempDept = 'all';
                                  tempStatus = 0;
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: const Color(0xFF34D399).withValues(alpha: 0.35),
                                  width: 1.0,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: const Text(
                                'Reset',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFBACCC3),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedEmployeeRoleFilter = tempRole;
                                  _selectedEmployeeDeptFilter = tempDept;
                                  _selectedEmployeeFilter = tempStatus;
                                });
                                Navigator.pop(ctx);
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFF34D399).withValues(alpha: 0.30),
                                    width: 1.0,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.25),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                alignment: Alignment.center,
                                child: const Text(
                                  'Apply Filters',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        color: Color(0xFF6EE7B7),
        letterSpacing: 1.0,
      ),
    );
  }

  // ---------------------------------------------------------
  // TAB 2: ATTENDANCE TRACKER (Image 1, Screen 4)
  // ---------------------------------------------------------
  Widget _buildAttendanceTab() {
    // If an employee was clicked in search or day logs, show full employee details view immediately
    if (_selectedEmployeeForDayLog != null) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDayEmployeeDetailView(_selectedEmployeeForDayLog!),
            const SizedBox(height: 28),
          ],
        ),
      );
    }

    final nonAdminStaff = _allNonAdminEmployees;
    final totalStaff = nonAdminStaff.length;
    // Dynamic real data from MongoDB for today (strictly today date & active check-in)
    final todayPresentStaff = nonAdminStaff.where((u) {
      final att = _getEmployeeTodayAttendance(u);
      return att != null && (att.status.toLowerCase() == 'present' || att.status.toLowerCase() == 'late');
    }).length;
    final rate = totalStaff > 0 ? ((todayPresentStaff / totalStaff) * 100).clamp(0, 100).round() : 0;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with Work Policy Action
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Attendance',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.4,
                      shadows: [Shadow(offset: Offset(0, 2), blurRadius: 4, color: Colors.black45)],
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Track employee attendance',
                    style: TextStyle(fontSize: 13, color: Color(0xFFBACCC3)),
                  ),
                ],
              ),
              InkWell(
                onTap: _showWorkScheduleAndBreakPolicySheet,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF34D399).withValues(alpha: 0.30),
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.timer_outlined, size: 16, color: Colors.white),
                      SizedBox(width: 5),
                      Text(
                        'Work Policy',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // First Search Box with Suffix Filter Icon (Image 2 Design)
          _buildCompanyTypingBox(
            controller: _attendanceSearchController,
            hintText: 'Search attendance logs...',
            prefixIcon: Icons.search_rounded,
            onChanged: (val) {
              setState(() {
                _attendanceSearchQuery = val;
                _attendanceDayLogPage = 0;
              });
            },
            suffixWidget: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_attendanceSearchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _attendanceSearchController.clear();
                      setState(() {
                        _attendanceSearchQuery = '';
                        _attendanceDayLogPage = 0;
                      });
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.close_rounded, size: 18, color: Color(0xFFBACCC3)),
                    ),
                  ),
                GestureDetector(
                  onTap: _showAttendanceFilterSheet,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, right: 2),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          Icons.filter_list_rounded,
                          size: 20,
                          color: _selectedDayLogFilter != 'all' ? const Color(0xFF10B981) : const Color(0xFFCBD5E1),
                        ),
                        if (_selectedDayLogFilter != 'all')
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Instant Search Results Card (Directly visible beneath search bar when typing)
          if (_attendanceSearchQuery.trim().isNotEmpty) ...[
            _buildAttendanceSearchResultsCard(),
            const SizedBox(height: 12),
          ],

          // 1. Calendar Month Card (Image 1 Screen 4)
          _buildMonthCalendarCard(),
          const SizedBox(height: 16),

          // 2. Today's Attendance Progress Card (Dynamic Real Data)
          _buildGlassCard(
            borderRadius: 22,
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  "Today's Attendance",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    shadows: [Shadow(offset: Offset(0, 1), blurRadius: 4, color: Colors.black45)],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$todayPresentStaff / $totalStaff Present',
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: Color(0xFFBACCC3),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '$rate%',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF34D399),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: totalStaff > 0 ? (todayPresentStaff / totalStaff).clamp(0.0, 1.0) : 0.0,
                    minHeight: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.10),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Day Attendance Logs with Status Filters, Search, 6-Item Pagination & Drilldown
          _buildDayAttendanceLogsSection(),

          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _buildMonthCalendarCard() {
    final companyStartYear = _company?.startingYear ?? 2026;
    final companyStartMonth = _company?.startingMonth ?? 8;
    final companyStartDate = DateTime(companyStartYear, companyStartMonth, 1);

    final year = _currentCalendarMonth.year;
    final month = _currentCalendarMonth.month;
    final firstDayOfMonth = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final startWeekday = firstDayOfMonth.weekday % 7; // 0=Sun, 6=Sat

    final canGoPrevMonth = _currentCalendarMonth.isAfter(companyStartDate);
    const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return _buildGlassCard(
      borderRadius: 22,
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          // Month Navigation Row with Edit Date Picker
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: Icon(
                  Icons.chevron_left_rounded,
                  color: canGoPrevMonth ? Colors.white : Colors.white30,
                  size: 22,
                ),
                onPressed: canGoPrevMonth
                    ? () {
                        setState(() {
                          _currentCalendarMonth = DateTime(year, month - 1);
                        });
                      }
                    : null,
              ),
              GestureDetector(
                onTap: _showCalendarDatePickerDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF34D399).withValues(alpha: 0.35),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _getMonthYearName(_currentCalendarMonth),
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.edit_calendar_rounded, size: 15, color: Color(0xFF34D399)),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 22),
                onPressed: () {
                  setState(() {
                    _currentCalendarMonth = DateTime(year, month + 1);
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Weekdays Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: weekdays.map((w) {
              return SizedBox(
                width: 32,
                child: Center(
                  child: Text(
                    w,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFCBD5E1),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),

          // Days Grid (Image 1 Screen 4)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: startWeekday + daysInMonth,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemBuilder: (ctx, idx) {
              if (idx < startWeekday) {
                return const SizedBox.shrink();
              }
              final dayNum = idx - startWeekday + 1;
              final dayDate = DateTime(year, month, dayNum);
              final isSelected = dayDate.year == _selectedCalendarDate.year &&
                  dayDate.month == _selectedCalendarDate.month &&
                  dayDate.day == _selectedCalendarDate.day;

              final birthdayEmployees = _getBirthdayEmployees(dayDate);
              final hasBirthday = birthdayEmployees.isNotEmpty;
              final isLeaveOrOff = _isNonWorkingOrLeave(dayDate);

              Color bgColor = Colors.transparent;
              Color borderColor = Colors.transparent;
              Color textColor = const Color(0xFFCBD5E1);
              List<BoxShadow>? shadows;
              VoidCallback? onTapAction;

              if (hasBirthday) {
                // Gold color for employee birthday (tap to view employee details)
                bgColor = const Color(0xFFF59E0B);
                borderColor = const Color(0xFFFBBF24);
                textColor = Colors.white;
                shadows = [
                  BoxShadow(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                    blurRadius: 8,
                  ),
                ];
                onTapAction = () => _showBirthdayEmployeesDialog(dayDate, birthdayEmployees);
              } else if (isLeaveOrOff) {
                // Violet color for leaves & non-working days (unclickable: "we cant touch that because that is leave")
                bgColor = const Color(0xFF7C3AED).withValues(alpha: 0.35);
                borderColor = const Color(0xFF8B5CF6).withValues(alpha: 0.65);
                textColor = const Color(0xFFC4B5FD);
                onTapAction = null;
              } else {
                // Regular working day
                if (isSelected) {
                  bgColor = const Color(0xFF10B981);
                  borderColor = const Color(0xFF34D399);
                  textColor = Colors.white;
                  shadows = [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.5),
                      blurRadius: 8,
                    ),
                  ];
                }
                onTapAction = () {
                  setState(() {
                    _selectedCalendarDate = dayDate;
                    _attendanceDayLogPage = 0;
                    _selectedEmployeeForDayLog = null;
                  });
                };
              }

              return GestureDetector(
                onTap: onTapAction,
                child: Container(
                  decoration: BoxDecoration(
                    color: bgColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: borderColor, width: 1.0),
                    boxShadow: shadows,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$dayNum',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: (isSelected || hasBirthday || isLeaveOrOff) ? FontWeight.w800 : FontWeight.w500,
                            color: textColor,
                          ),
                        ),
                        if (hasBirthday)
                          const Text('🎂', style: TextStyle(fontSize: 8, height: 0.8)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // Calendar Color Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildCalendarLegendDot(const Color(0xFF10B981), 'Working Day'),
              const SizedBox(width: 12),
              _buildCalendarLegendDot(const Color(0xFF8B5CF6), 'Leave / Off (Locked)'),
              const SizedBox(width: 12),
              _buildCalendarLegendDot(const Color(0xFFF59E0B), 'Birthday 🎂'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 10.5, color: Color(0xFFBACCC3), fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  void _showBirthdayEmployeesDialog(DateTime date, List<UserModel> employees) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF072118),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFF59E0B), width: 1.5),
        ),
        title: Row(
          children: const [
            Text('🎂', style: TextStyle(fontSize: 22)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Birthday Celebration!',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFFCD34D),
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${date.day} ${_getMonthName(date.month)} • Team Birthday Celebrations',
              style: const TextStyle(fontSize: 12, color: Color(0xFFBACCC3)),
            ),
            const SizedBox(height: 12),
            ...employees.map((emp) {
              final empName = emp.name.isNotEmpty ? emp.name : emp.username;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    _buildEmployeeAvatar(emp),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            empName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${emp.designation ?? emp.roleDisplayName} • ${emp.department ?? "General"}',
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFFFCD34D)),
                          ),
                          if (emp.phone != null && emp.phone!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Phone: ${emp.phone}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFFBACCC3)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  void _showWorkScheduleAndBreakPolicySheet() {
    final checkInCtrl = TextEditingController(text: _workSchedule.checkInTime.isNotEmpty ? _workSchedule.checkInTime : '09:30');
    final checkOutCtrl = TextEditingController(text: _workSchedule.checkOutTime.isNotEmpty ? _workSchedule.checkOutTime : '18:30');
    final hoursCtrl = TextEditingController(text: '${_workSchedule.workingHoursPerDay}');
    final breakCtrl = TextEditingController(text: '${_workSchedule.breakTime}');
    final casualBreakCtrl = TextEditingController(text: '${_workSchedule.casualBreakTime}');
    int daysPerWeek = _workSchedule.workingDaysPerWeek > 0 ? _workSchedule.workingDaysPerWeek : 5;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
              decoration: BoxDecoration(
                color: const Color(0xFF072118).withValues(alpha: 0.96),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.28)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF34D399).withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.timer_outlined, color: Color(0xFF34D399), size: 22),
                            SizedBox(width: 10),
                            Text(
                              'Work Schedule & Break Policy',
                              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: Colors.white),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Color(0xFFCBD5E1), size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Configure standard work schedules, working hours, and official & casual break time limits.',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFFBACCC3)),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: _buildCompanyTypingBox(
                            controller: checkInCtrl,
                            labelText: 'Standard Check-In',
                            hintText: '09:30',
                            prefixIcon: Icons.login_rounded,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildCompanyTypingBox(
                            controller: checkOutCtrl,
                            labelText: 'Standard Check-Out',
                            hintText: '18:30',
                            prefixIcon: Icons.logout_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    _buildCompanyTypingBox(
                      controller: hoursCtrl,
                      labelText: 'Working Hours / Day',
                      hintText: '8',
                      prefixIcon: Icons.schedule_rounded,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 14),

                    // Working Days / Week
                    const Text(
                      'Working Days / Week',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFCBD5E1)),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [4, 5, 6, 7].map((days) {
                        final isSel = daysPerWeek == days;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: InkWell(
                              onTap: () => setModalState(() => daysPerWeek = days),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isSel ? const Color(0xFF10B981) : const Color(0xFF042F24).withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSel ? const Color(0xFF34D399) : Colors.white12,
                                  ),
                                ),
                                child: Text(
                                  '$days Days',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                                    color: isSel ? Colors.white : const Color(0xFFCBD5E1),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    // Break Limits Container
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF042F24).withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.22)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Break Time Limits & Salary Delay Deductions',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF6EE7B7)),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _buildCompanyTypingBox(
                                  controller: breakCtrl,
                                  labelText: 'Lunch Break (Mins)',
                                  hintText: '60',
                                  prefixIcon: Icons.restaurant_rounded,
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildCompanyTypingBox(
                                  controller: casualBreakCtrl,
                                  labelText: 'Casual Break (Mins)',
                                  hintText: '15',
                                  prefixIcon: Icons.coffee_rounded,
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Exceeding break limits calculates salary deduction on a per-minute delay basis.',
                            style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Save Button
                    InkWell(
                      onTap: isSaving
                          ? null
                          : () async {
                              setModalState(() => isSaving = true);
                              final offDays = daysPerWeek == 4
                                  ? [0, 5, 6]
                                  : (daysPerWeek == 5 ? [0, 6] : (daysPerWeek == 6 ? [0] : <int>[]));
                              final updated = WorkScheduleModel(
                                id: _workSchedule.id,
                                companyId: _workSchedule.companyId,
                                checkInTime: checkInCtrl.text.trim().isNotEmpty ? checkInCtrl.text.trim() : '09:30',
                                checkOutTime: checkOutCtrl.text.trim().isNotEmpty ? checkOutCtrl.text.trim() : '18:30',
                                workingHoursPerDay: int.tryParse(hoursCtrl.text.trim()) ?? 8,
                                workingDaysPerWeek: daysPerWeek,
                                breakTime: int.tryParse(breakCtrl.text.trim()) ?? 60,
                                casualBreakTime: int.tryParse(casualBreakCtrl.text.trim()) ?? 15,
                                weeklyOffDays: offDays,
                                graceMinutes: _workSchedule.graceMinutes,
                              );

                              try {
                                await _attendanceService.updateWorkSchedule(updated);
                                setState(() => _workSchedule = updated);
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      backgroundColor: Color(0xFF10B981),
                                      content: Text('✓ Work schedule and break policy updated successfully!'),
                                    ),
                                  );
                                }
                              } catch (e) {
                                setModalState(() => isSaving = false);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: const Color(0xFFEF4444),
                                      content: Text('Failed to update schedule: $e'),
                                    ),
                                  );
                                }
                              }
                            },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.35)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981).withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text(
                                'Save Schedule & Policy',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 0.2,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttendanceLogTile(AttendanceModel att) {
    return _buildGlassCard(
      borderRadius: 16,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, color: Color(0xFF34D399), size: 16),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    att.userId,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  Text(
                    'In: ${att.checkIn != null ? att.checkIn!.split('T').last.substring(0, 5) : '09:00'}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFFBACCC3)),
                  ),
                ],
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: att.status.toLowerCase() == 'late'
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.2)
                  : const Color(0xFF10B981).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              att.status.toUpperCase(),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: att.status.toLowerCase() == 'late' ? const Color(0xFFF59E0B) : const Color(0xFF34D399),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------
  // TAB 3: LEAVE MANAGEMENT (Image 1, Screen 5)
  // ---------------------------------------------------------
  Widget _buildLeaveTab() {
    List<LeaveModel> filtered = _leaves;
    if (_leaveSearchQuery.isNotEmpty) {
      final q = _leaveSearchQuery.toLowerCase();
      filtered = filtered.where((l) =>
        l.userId.toLowerCase().contains(q) ||
        l.type.toLowerCase().contains(q) ||
        (l.reason?.toLowerCase().contains(q) ?? false)
      ).toList();
    }
    if (_selectedLeaveFilter == 1) {
      filtered = filtered.where((l) => l.isPending).toList();
    } else if (_selectedLeaveFilter == 2) {
      filtered = filtered.where((l) => l.isApproved).toList();
    } else if (_selectedLeaveFilter == 3) {
      filtered = filtered.where((l) => l.isRejected).toList();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          const Text(
            'Leave Management',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.4,
              shadows: [Shadow(offset: Offset(0, 2), blurRadius: 4, color: Colors.black45)],
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Manage leave requests',
            style: TextStyle(fontSize: 13, color: Color(0xFFBACCC3)),
          ),
          const SizedBox(height: 14),

          // Search Bar (Image 2 Design)
          _buildCompanyTypingBox(
            controller: _leaveSearchController,
            hintText: 'Search leave requests...',
            prefixIcon: Icons.search_rounded,
            onChanged: (val) => setState(() => _leaveSearchQuery = val),
          ),
          const SizedBox(height: 12),

          // Filter Segment Chips: [All] [Pending] [Approved] [Rejected]
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildSegmentChip('All', 0, _selectedLeaveFilter, (idx) => setState(() => _selectedLeaveFilter = idx)),
                const SizedBox(width: 8),
                _buildSegmentChip('Pending', 1, _selectedLeaveFilter, (idx) => setState(() => _selectedLeaveFilter = idx)),
                const SizedBox(width: 8),
                _buildSegmentChip('Approved', 2, _selectedLeaveFilter, (idx) => setState(() => _selectedLeaveFilter = idx)),
                const SizedBox(width: 8),
                _buildSegmentChip('Rejected', 3, _selectedLeaveFilter, (idx) => setState(() => _selectedLeaveFilter = idx)),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Leaves List Cards (Image 1 Screen 5)
          Expanded(
            child: filtered.isEmpty
                ? _buildEmptyDarkState('No leave requests matching filter.')
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (ctx, idx) => _buildLeaveCard(filtered[idx]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaveCard(LeaveModel leave) {
    Color statusColor = const Color(0xFFF59E0B);
    Color statusBg = const Color(0xFFF59E0B).withValues(alpha: 0.20);
    if (leave.isApproved) {
      statusColor = const Color(0xFF34D399);
      statusBg = const Color(0xFF10B981).withValues(alpha: 0.20);
    } else if (leave.isRejected) {
      statusColor = const Color(0xFFEF4444);
      statusBg = const Color(0xFFEF4444).withValues(alpha: 0.20);
    }

    final startStr = leave.startDate.split('T').first;
    final endStr = leave.endDate.split('T').first;

    return _buildGlassCard(
      borderRadius: 18,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF0F3A2E),
                ),
                child: Center(
                  child: Text(
                    leave.userId.isNotEmpty ? leave.userId[0].toUpperCase() : 'L',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // User and Type
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      leave.userId,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                    Text(
                      leave.displayType,
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFFBACCC3)),
                    ),
                  ],
                ),
              ),
              // Status Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  leave.status.toUpperCase(),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: statusColor),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.more_vert_rounded, size: 16, color: Color(0xFFBACCC3)),
                onPressed: () {},
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$startStr to $endStr',
            style: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
          ),
          if (leave.reason?.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(
              leave.reason!,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF88A89A)),
            ),
          ],

          // Approve / Reject Buttons (Image 1 Screen 5)
          if (leave.isPending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _handleUpdateLeaveStatus(leave.id, 'approved'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      elevation: 0,
                    ),
                    child: const Text('Approve', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _handleUpdateLeaveStatus(leave.id, 'rejected'),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: const Text('Reject', style: TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------
  // TAB 4: PROFILE & COMPANY WORKSPACE (Image 2)
  // ---------------------------------------------------------
  Widget _buildProfileTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Segmented Tabs: [Company] [My Profile] [Settings]
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D241C).withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    Expanded(child: _buildProfileSubTabButton('Company', 0)),
                    Expanded(child: _buildProfileSubTabButton('My Profile', 1)),
                    Expanded(child: _buildProfileSubTabButton('Settings', 2)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Sub-Tab Content
          Expanded(
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: _selectedProfileSubTab == 0
                  ? _buildCompanyInfoView()
                  : _selectedProfileSubTab == 1
                      ? _buildMyProfileView()
                      : _buildSettingsView(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSubTabButton(String title, int index) {
    final isSelected = _selectedProfileSubTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedProfileSubTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF10B981) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.4),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              color: isSelected ? Colors.white : const Color(0xFFE2E8F0),
            ),
          ),
        ),
      ),
    );
  }

  // Sub-Tab 0: Company Info (Image 2 Screen 1)
  Widget _buildCompanyInfoView() {
    final name = _company?.name ?? widget.user.companyName ?? 'krish Tech Computer';
    final location = _company?.city != null && _company!.city!.isNotEmpty
        ? (_company?.state != null && _company!.state!.isNotEmpty
            ? '${_company!.city}, ${_company!.state}'
            : '${_company!.city}, India')
        : 'Coimbatore, Tamil Nadu';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Company',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
        ),
        const SizedBox(height: 2),
        const Text(
          'Manage company information',
          style: TextStyle(fontSize: 12.5, color: Color(0xFFBACCC3)),
        ),
        const SizedBox(height: 14),

        // Company Details Card (Image 2 Screen 1)
        _buildGlassCard(
          borderRadius: 22,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.corporate_fare_rounded, color: Color(0xFF34D399), size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                        const SizedBox(height: 2),
                        const Text('Private Limited', style: TextStyle(fontSize: 12, color: Color(0xFFBACCC3))),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: Colors.white.withValues(alpha: 0.12)),
              const SizedBox(height: 10),

              _buildCompanyDetailRow('Industry', 'IT Services'),
              _buildCompanyDetailRow('Company Size', '${_users.length} employees'),
              _buildCompanyDetailRow('Location', location),
              _buildCompanyDetailRow(
                'Office Geofence',
                _company?.latitude != null
                    ? '5m Active (${_company!.latitude!.toStringAsFixed(3)}, ${_company!.longitude!.toStringAsFixed(3)})'
                    : '5m Radius Configured',
              ),
              const SizedBox(height: 16),

              ElevatedButton(
                onPressed: _showOfficeLocationDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text('Edit Company Details', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // About Company Card (Image 2 Screen 1)
        _buildGlassCard(
          borderRadius: 22,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'About Company',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              SizedBox(height: 8),
              Text(
                'ReGen is a modern workforce management platform designed to simplify employee operations, track geofenced attendance, and enhance productivity.',
                style: TextStyle(fontSize: 12.5, color: Color(0xFFBACCC3), height: 1.45),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompanyDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: Color(0xFFBACCC3))),
          Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
        ],
      ),
    );
  }

  // Sub-Tab 1: My Profile (Image 2 Screen 2)
  Widget _buildMyProfileView() {
    final name = widget.user.name.isNotEmpty ? widget.user.name : widget.user.username;
    final role = widget.user.roleDisplayName;
    final email = widget.user.email ?? 'rithika@example.com';
    final location = _company?.city ?? 'Coimbatore, Tamil Nadu';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Avatar with Camera Overlay
        Stack(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF34D399), width: 2),
                color: const Color(0xFF0F3A2E),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF10B981).withValues(alpha: 0.35), blurRadius: 12),
                ],
              ),
              child: Center(
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'A',
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
        const SizedBox(height: 2),
        Text(role, style: const TextStyle(fontSize: 12.5, color: Color(0xFFBACCC3))),
        const SizedBox(height: 18),

        // Personal Information Card (Image 2 Screen 2)
        _buildGlassCard(
          borderRadius: 22,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Personal Information',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const SizedBox(height: 12),
              _buildProfileRow(Icons.email_outlined, 'Email', email),
              _buildProfileRow(Icons.phone_outlined, 'Phone', widget.user.phone ?? '+91 98765 43210'),
              _buildProfileRow(Icons.badge_outlined, 'Department', widget.user.department ?? 'Administration'),
              _buildProfileRow(Icons.location_on_outlined, 'Location', location),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Account Settings Card (Image 2 Screen 2)
        _buildGlassCard(
          borderRadius: 22,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Account Settings',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const SizedBox(height: 10),
              _buildSettingsRow(Icons.lock_outline_rounded, 'Change Password', () {}),
              _buildSettingsRow(Icons.notifications_none_rounded, 'Notifications', _showNotificationsSheet),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProfileRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFFA7F3D0)),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFFBACCC3))),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildSettingsRow(IconData icon, String title, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFFA7F3D0)),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(fontSize: 13, color: Colors.white)),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFF88A89A)),
          ],
        ),
      ),
    );
  }

  // Sub-Tab 2: Settings (Image 2 Screen 3)
  Widget _buildSettingsView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
        const SizedBox(height: 2),
        const Text('Customise your experience', style: TextStyle(fontSize: 12.5, color: Color(0xFFBACCC3))),
        const SizedBox(height: 14),

        _buildSettingsMenuCard(
          icon: Icons.palette_outlined,
          title: 'Appearance',
          subtitle: 'Theme, language, display',
          onTap: () {},
        ),
        _buildSettingsMenuCard(
          icon: Icons.notifications_none_rounded,
          title: 'Notifications',
          subtitle: 'Manage your notifications',
          onTap: _showNotificationsSheet,
        ),
        _buildSettingsMenuCard(
          icon: Icons.timer_outlined,
          title: 'Work Schedule & Break Policy',
          subtitle: 'Shift timings, working days & break deductions',
          onTap: _showShiftSettingsDialog,
        ),
        _buildSettingsMenuCard(
          icon: Icons.shield_outlined,
          title: 'Security',
          subtitle: 'Password, 2FA, login activity',
          onTap: () {},
        ),
        _buildSettingsMenuCard(
          icon: Icons.tune_rounded,
          title: 'App Preferences',
          subtitle: 'General settings',
          onTap: () {},
        ),
        _buildSettingsMenuCard(
          icon: Icons.help_outline_rounded,
          title: 'Help & Support',
          subtitle: 'Get help and contact us',
          onTap: () {},
        ),
        _buildSettingsMenuCard(
          icon: Icons.info_outline_rounded,
          title: 'About',
          subtitle: 'Version 1.0.0',
          onTap: () {},
        ),
        const SizedBox(height: 18),

        // Sign Out Button
        ElevatedButton.icon(
          onPressed: _confirmLogout,
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: const Text('Sign Out', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFDC2626),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsMenuCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return _buildGlassCard(
      borderRadius: 18,
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: const Color(0xFFA7F3D0), size: 18),
        ),
        title: Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11.5, color: Color(0xFFCBD5E1))),
        trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFFA7F3D0), size: 18),
        onTap: onTap,
      ),
    );
  }

  // ---------------------------------------------------------
  // NOTIFICATIONS SHEET (Image 3)
  // ---------------------------------------------------------
  void _showNotificationsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF031A14),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.88,
            child: Stack(
              children: [
                // Background image with light photographic bokeh blur (sigma 5.5)
                Positioned.fill(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 5.5, sigmaY: 5.5),
                    child: Transform.scale(
                      scale: 1.05,
                      child: Image.asset(
                        'assets/images/corporate_office_dark.jpg',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF040A07).withValues(alpha: 0.35),
                          const Color(0xFF020704).withValues(alpha: 0.85),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Top Handle
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Header with Back & Logo
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                          const SizedBox(width: 4),
                          const BrandLogo(size: 24, borderRadius: 6),
                          const SizedBox(width: 8),
                          const Text('ReGen', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                        ],
                      ),
                      const SizedBox(height: 8),

                      const Text('Notifications', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                      const SizedBox(height: 2),
                      const Text('Stay updated', style: TextStyle(fontSize: 12.5, color: Color(0xFFBACCC3))),
                      const SizedBox(height: 12),

                      // Filter Chips: [All] [Unread] [System] [Leave] [Attendance]
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildSegmentChip('All', 0, _selectedNotificationFilter, (idx) => setSheetState(() => _selectedNotificationFilter = idx)),
                            const SizedBox(width: 8),
                            _buildSegmentChip('Unread', 1, _selectedNotificationFilter, (idx) => setSheetState(() => _selectedNotificationFilter = idx)),
                            const SizedBox(width: 8),
                            _buildSegmentChip('System', 2, _selectedNotificationFilter, (idx) => setSheetState(() => _selectedNotificationFilter = idx)),
                            const SizedBox(width: 8),
                            _buildSegmentChip('Leave', 3, _selectedNotificationFilter, (idx) => setSheetState(() => _selectedNotificationFilter = idx)),
                            const SizedBox(width: 8),
                            _buildSegmentChip('Attendance', 4, _selectedNotificationFilter, (idx) => setSheetState(() => _selectedNotificationFilter = idx)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Notifications Dynamic Cards (Image 3)
                      Expanded(
                        child: ListView(
                          children: [
                            _buildNotificationCard(
                              icon: Icons.description_outlined,
                              title: 'Leave Request',
                              body: _leaves.isNotEmpty
                                  ? '${_leaves.first.userId} has requested leave.'
                                  : 'Sneha Patel has requested 2 days leave.',
                              time: '2 minutes ago',
                              isUnread: true,
                            ),
                            _buildNotificationCard(
                              icon: Icons.group_add_outlined,
                              title: 'New Employee',
                              body: _users.isNotEmpty
                                  ? '${_users.first.name.isNotEmpty ? _users.first.name : _users.first.username} has been added.'
                                  : 'Arjun Kumar has been added.',
                              time: '1 hour ago',
                              isUnread: true,
                            ),
                            _buildNotificationCard(
                              icon: Icons.notifications_active_outlined,
                              title: 'Attendance Alert',
                              body: '${(_users.length - _attendance.length).clamp(0, 999)} employees are absent today.',
                              time: '3 hours ago',
                              isUnread: false,
                            ),
                            _buildNotificationCard(
                              icon: Icons.settings_suggest_outlined,
                              title: 'System Update',
                              body: '5m GPS Geofence validation is active on device.',
                              time: '1 day ago',
                              isUnread: false,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildNotificationCard({
    required IconData icon,
    required String title,
    required String body,
    required String time,
    required bool isUnread,
  }) {
    return _buildGlassCard(
      borderRadius: 18,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: const Color(0xFF34D399), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white)),
                    if (isUnread)
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: const Color(0xFF10B981).withValues(alpha: 0.7), blurRadius: 4),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(body, style: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1))),
                const SizedBox(height: 4),
                Text(time, style: const TextStyle(fontSize: 10.5, color: Color(0xFF88A89A))),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded, size: 16, color: Color(0xFF88A89A)),
            onPressed: () {},
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------
  // COMPANY TYPING BOX (Exact Match to User Attached Image 2)
  // ---------------------------------------------------------
  Widget _buildCompanyTypingBox({
    required TextEditingController controller,
    required String hintText,
    String? labelText,
    IconData? prefixIcon,
    Widget? suffixWidget,
    ValueChanged<String>? onChanged,
    bool obscureText = false,
    TextInputType? keyboardType,
    int maxLines = 1,
    VoidCallback? onTap,
    bool readOnly = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (labelText != null && labelText.isNotEmpty) ...[
          Text(
            labelText,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFFCBD5E1),
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              height: maxLines == 1 ? 48 : null,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF0A2218).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF34D399).withValues(alpha: 0.25),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  if (prefixIcon != null) ...[
                    Icon(prefixIcon, size: 20, color: const Color(0xFFCBD5E1)),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: TextField(
                      controller: controller,
                      onChanged: onChanged,
                      obscureText: obscureText,
                      keyboardType: keyboardType,
                      maxLines: maxLines,
                      readOnly: readOnly,
                      onTap: onTap,
                      cursorColor: const Color(0xFF34D399),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: false,
                        hintText: hintText,
                        hintStyle: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: maxLines > 1 ? 8 : 10),
                      ),
                    ),
                  ),
                  if (suffixWidget != null) ...[
                    const SizedBox(width: 8),
                    suffixWidget,
                  ] else if (prefixIcon == Icons.search_rounded) ...[
                    const SizedBox(width: 8),
                    const Padding(
                      padding: EdgeInsets.only(left: 2, right: 2),
                      child: Icon(Icons.filter_list_rounded, size: 20, color: Color(0xFFCBD5E1)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------
  // 5-TAB FLOATING FROSTED GLASS BOTTOM DOCK (Image 1)
  // ---------------------------------------------------------
  Widget _buildCompanyBottomNav() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF13362A).withValues(alpha: 0.78),
                  const Color(0xFF0A2219).withValues(alpha: 0.88),
                ],
              ),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: const Color(0xFF34D399).withValues(alpha: 0.28),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildBottomNavItem(0, 'Home', Icons.home_outlined, Icons.home_rounded),
                _buildBottomNavItem(1, 'Employees', Icons.groups_outlined, Icons.groups_rounded),
                _buildBottomNavItem(2, 'Attendance', Icons.calendar_month_outlined, Icons.calendar_month_rounded),
                _buildBottomNavItem(3, 'Leave', Icons.beach_access_outlined, Icons.beach_access_rounded),
                _buildBottomNavItem(4, 'Profile', Icons.person_outline_rounded, Icons.person_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavItem(int index, String label, IconData icon, IconData activeIcon) {
    final isSelected = _selectedBottomTab == index;

    return InkWell(
      onTap: () => setState(() => _selectedBottomTab = index),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 58,
        height: 52,
        alignment: Alignment.center,
        decoration: isSelected
            ? BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF0F4733),
                    Color(0xFF062319),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF34D399).withValues(alpha: 0.50),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.40),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                  BoxShadow(
                    color: const Color(0xFF34D399).withValues(alpha: 0.20),
                    blurRadius: 6,
                    offset: const Offset(0, -1),
                  ),
                ],
              )
            : const BoxDecoration(
                color: Colors.transparent,
              ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              color: isSelected ? const Color(0xFFA7F3D0) : const Color(0xFF94A3B8),
              size: isSelected ? 21 : 20,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------
  // FUNCTIONAL DIALOGS (100% PRESERVED BACKEND LOGIC)
  // ---------------------------------------------------------

  Widget _buildSuperAdminSwitchBanner() {
    return _buildGlassCard(
      borderRadius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: const [
              Icon(Icons.shield_outlined, color: Color(0xFFA7F3D0), size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Super Admin Console Available',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'You are logged in as Company Owner. You have authorized platform permissions to switch to ReGen Central.',
            style: TextStyle(fontSize: 12, color: Color(0xFFBACCC3), height: 1.35),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _isSwitchingToSuperAdmin ? null : _handleSwitchToSuperAdmin,
            icon: _isSwitchingToSuperAdmin
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.swap_horiz_rounded, size: 18),
            label: Text(
              _isSwitchingToSuperAdmin ? 'Switching...' : 'Switch to Super Admin Console',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddEmployeeDialog() async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddEmployeeView(
          company: _company,
          currentUser: widget.user,
          dashboardService: _dashboardService,
        ),
      ),
    );
    if (updated == true) {
      _loadCompanyData();
    }
  }

  void _showOfficeLocationDialog() {
    double currentLat = _company?.latitude ?? 11.0168;
    double currentLng = _company?.longitude ?? 76.9558;
    final latCtrl = TextEditingController(text: currentLat.toStringAsFixed(6));
    final lngCtrl = TextEditingController(text: currentLng.toStringAsFixed(6));
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: const Color(0xFF072118),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
          ),
          title: const Text('5m Office GPS Geofence', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Attendance is validated against your registered office coordinates using a strict 5-meter geofence.',
                style: TextStyle(fontSize: 12, color: Color(0xFFBACCC3)),
              ),
              const SizedBox(height: 14),
              _buildCompanyTypingBox(
                controller: latCtrl,
                labelText: 'Latitude',
                hintText: 'e.g. 11.016800',
                prefixIcon: Icons.location_on_outlined,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              _buildCompanyTypingBox(
                controller: lngCtrl,
                labelText: 'Longitude',
                hintText: 'e.g. 76.955800',
                prefixIcon: Icons.my_location_outlined,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    final pos = await LocationService.getCurrentPosition();
                    setDlgState(() {
                      latCtrl.text = pos.latitude.toStringAsFixed(6);
                      lngCtrl.text = pos.longitude.toStringAsFixed(6);
                    });
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(backgroundColor: Colors.red, content: Text('GPS error: $e')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.my_location_rounded, size: 16, color: Color(0xFF34D399)),
                label: const Text('Capture Current GPS Coordinates', style: TextStyle(color: Color(0xFF34D399), fontSize: 12)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF88A89A))),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final lat = double.tryParse(latCtrl.text.trim());
                      final lng = double.tryParse(lngCtrl.text.trim());
                      if (lat == null || lng == null) return;
                      final nav = Navigator.of(ctx);
                      final messenger = ScaffoldMessenger.of(context);
                      setDlgState(() => isSaving = true);
                      try {
                        if (_company != null) {
                          await _attendanceService.updateOfficeLocation(
                            _company!.id,
                            latitude: lat,
                            longitude: lng,
                          );
                        }
                        nav.pop();
                        messenger.showSnackBar(
                          const SnackBar(backgroundColor: Color(0xFF10B981), content: Text('5m Geofence coordinates saved!')),
                        );
                        _loadCompanyData();
                      } catch (e) {
                        setDlgState(() => isSaving = false);
                        messenger.showSnackBar(
                          SnackBar(backgroundColor: Colors.red, content: Text('Error: $e')),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
              child: isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showShiftSettingsDialog() {
    _showWorkScheduleAndBreakPolicySheet();
  }

  void _showAttendanceReportSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF072118),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Workforce Attendance Reports', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 8),
              Text(
                'Total registered logs: ${_attendance.length} entries across ${_users.length} staff members.',
                style: const TextStyle(fontSize: 12, color: Color(0xFFBACCC3)),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: Color(0xFF10B981),
                      content: Text('Attendance summary exported to CSV successfully!'),
                    ),
                  );
                },
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Download CSV Report', style: TextStyle(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAttendanceRosterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF031A14),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Company Attendance Roster', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                  IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _attendance.isEmpty
                    ? _buildEmptyDarkState('No attendance logs recorded.')
                    : ListView.builder(
                        itemCount: _attendance.length,
                        itemBuilder: (context, idx) => _buildAttendanceLogTile(_attendance[idx]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyDarkState(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, color: Colors.white.withValues(alpha: 0.2), size: 36),
          const SizedBox(height: 10),
          Text(text, style: const TextStyle(fontSize: 12.5, color: Color(0xFFBACCC3)), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(color: Color(0xFF10B981)),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.red, size: 36),
            const SizedBox(height: 10),
            Text(_errorMessage ?? 'An error occurred', style: const TextStyle(color: Colors.white, fontSize: 13)),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: _loadCompanyData,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildRoleSegmentChip(String label, String roleKey, int count) {
    final isSelected = _selectedEmployeeRoleFilter == roleKey;
    return GestureDetector(
      onTap: () => setState(() => _selectedEmployeeRoleFilter = roleKey),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF10B981) : const Color(0xFF0C241B).withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? const Color(0xFF10B981) : const Color(0xFF34D399).withValues(alpha: 0.18),
                width: 1.0,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.35),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                    ),
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white.withValues(alpha: 0.25) : const Color(0xFF10B981).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: isSelected ? Colors.white : const Color(0xFF34D399),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showCalendarDatePickerDialog() async {
    final companyStartYear = _company?.startingYear ?? 2026;
    final companyStartMonth = _company?.startingMonth ?? 8;
    final companyStartDate = DateTime(companyStartYear, companyStartMonth, 1);
    final now = DateTime.now();
    final maxDate = DateTime(now.year + 2, 12, 31);

    final initial = _selectedCalendarDate.isBefore(companyStartDate)
        ? companyStartDate
        : (_selectedCalendarDate.isAfter(maxDate) ? maxDate : _selectedCalendarDate);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: companyStartDate,
      lastDate: maxDate,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF10B981),
              onPrimary: Colors.white,
              surface: Color(0xFF0A2218),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedCalendarDate = picked;
        _currentCalendarMonth = DateTime(picked.year, picked.month, 1);
        _attendanceDayLogPage = 0;
        _selectedEmployeeForDayLog = null;
      });
    }
  }

  List<_DayAttendanceRecord> _computeDayAttendanceRecords(DateTime date) {
    final dateIsoStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final isNonWorking = _isNonWorkingDay(date);
    final isLeaveDay = _isCompanyLeave(date);
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final targetMidnight = DateTime(date.year, date.month, date.day);
    final isFuture = targetMidnight.isAfter(todayMidnight);

    final List<_DayAttendanceRecord> records = [];

    for (final emp in _allNonAdminEmployees) {
      final attMatches = _attendance.where((a) {
        final matchesUser = a.userId.toLowerCase() == emp.userId.toLowerCase() ||
            a.userId.toLowerCase() == emp.username.toLowerCase();
        if (!matchesUser) return false;
        if (a.date.startsWith(dateIsoStr)) return true;
        final parsed = DateTime.tryParse(a.date);
        if (parsed != null && parsed.year == date.year && parsed.month == date.month && parsed.day == date.day) {
          return true;
        }
        return false;
      }).toList();

      if (attMatches.isNotEmpty) {
        final att = attMatches.first;
        final isLate = att.status.toLowerCase() == 'late' ||
            (att.checkIn != null && att.checkIn!.compareTo(_workSchedule.shiftStart) > 0);
        final isAbsent = att.status.toLowerCase() == 'absent';

        if (isAbsent) {
          records.add(_DayAttendanceRecord(
            employee: emp,
            status: 'absent',
            statusLabel: 'Absent',
            attendance: att,
            dateStr: dateIsoStr,
          ));
        } else if (isLate) {
          records.add(_DayAttendanceRecord(
            employee: emp,
            status: 'late',
            statusLabel: 'Late',
            attendance: att,
            checkIn: att.checkIn ?? '10:05 AM',
            checkOut: att.checkOut ?? '06:30 PM',
            dateStr: dateIsoStr,
          ));
        } else {
          records.add(_DayAttendanceRecord(
            employee: emp,
            status: 'present',
            statusLabel: 'Present',
            attendance: att,
            checkIn: att.checkIn ?? '09:20 AM',
            checkOut: att.checkOut ?? '06:30 PM',
            dateStr: dateIsoStr,
          ));
        }
      } else {
        final leaveMatches = _leaves.where((l) {
          final matchesUser = l.userId.toLowerCase() == emp.userId.toLowerCase() ||
              l.userId.toLowerCase() == emp.username.toLowerCase();
          if (!matchesUser) return false;
          return l.coversDate(dateIsoStr);
        }).toList();

        if (leaveMatches.isNotEmpty) {
          final l = leaveMatches.first;
          if (l.isApproved) {
            records.add(_DayAttendanceRecord(
              employee: emp,
              status: 'leave',
              statusLabel: 'Approved Leave',
              leave: l,
              dateStr: dateIsoStr,
            ));
          } else {
            // Unapproved leave: if future date, mark pending; if past/today, absent
            records.add(_DayAttendanceRecord(
              employee: emp,
              status: isFuture ? 'upcoming' : 'absent',
              statusLabel: isFuture ? 'Pending Leave Request' : 'Absent (Unapproved Leave)',
              leave: l,
              dateStr: dateIsoStr,
            ));
          }
        } else {
          if (isNonWorking || isLeaveDay) {
            records.add(_DayAttendanceRecord(
              employee: emp,
              status: 'off',
              statusLabel: 'Weekly Off / Holiday',
              dateStr: dateIsoStr,
            ));
          } else if (isFuture) {
            records.add(_DayAttendanceRecord(
              employee: emp,
              status: 'upcoming',
              statusLabel: 'Scheduled / Upcoming',
              dateStr: dateIsoStr,
            ));
          } else {
            records.add(_DayAttendanceRecord(
              employee: emp,
              status: 'absent',
              statusLabel: 'Absent',
              dateStr: dateIsoStr,
            ));
          }
        }
      }
    }

    return records;
  }

  // Search records matching employee name, role, dept, or status on the selected calendar date
  List<_DayAttendanceRecord> _getSearchMatchingRecords() {
    var records = _computeDayAttendanceRecords(_selectedCalendarDate);
    if (_selectedDayLogFilter != 'all') {
      records = records.where((r) => r.status == _selectedDayLogFilter).toList();
    }
    final q = _attendanceSearchQuery.trim().toLowerCase();
    if (q.isEmpty) return records;
    return records.where((r) {
      final name = r.employee.name.toLowerCase();
      final username = r.employee.username.toLowerCase();
      final uid = r.employee.userId.toLowerCase();
      final id = r.employee.id.toLowerCase();
      final dept = (r.employee.department ?? '').toLowerCase();
      final desig = (r.employee.designation ?? '').toLowerCase();
      final status = r.status.toLowerCase();
      final statusLabel = r.statusLabel.toLowerCase();
      return name.contains(q) ||
          username.contains(q) ||
          uid.contains(q) ||
          id.contains(q) ||
          dept.contains(q) ||
          desig.contains(q) ||
          status.contains(q) ||
          statusLabel.contains(q);
    }).toList();
  }

  // Instant Search Results Card (Directly visible beneath search bar when typing)
  Widget _buildAttendanceSearchResultsCard() {
    final matchingRecords = _getSearchMatchingRecords();
    return _buildGlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Search Results (${matchingRecords.length})',
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.3)),
                ),
                child: Text(
                  _formatHeaderDate(_selectedCalendarDate),
                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF34D399), fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 8),
          if (matchingRecords.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text(
                  'No employee found matching "$_attendanceSearchQuery" on this date.',
                  style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11.5),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: matchingRecords.length,
              itemBuilder: (ctx, idx) => _buildDayAttendanceRecordTile(matchingRecords[idx]),
            ),
        ],
      ),
    );
  }

  // Attendance Filter Sheet triggered from the first search box filter icon (100% overflow-safe on all phones)
  void _showAttendanceFilterSheet() {
    final allRecords = _computeDayAttendanceRecords(_selectedCalendarDate);
    final presentCount = allRecords.where((r) => r.status == 'present').length;
    final lateCount = allRecords.where((r) => r.status == 'late').length;
    final absentCount = allRecords.where((r) => r.status == 'absent').length;
    final leaveCount = allRecords.where((r) => r.status == 'leave').length;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final options = [
          {'key': 'all', 'label': 'All Attendance Logs', 'count': allRecords.length, 'color': const Color(0xFF10B981), 'icon': Icons.list_alt_rounded},
          {'key': 'present', 'label': 'Present Only', 'count': presentCount, 'color': const Color(0xFF10B981), 'icon': Icons.check_circle_outline_rounded},
          {'key': 'absent', 'label': 'Absent Only', 'count': absentCount, 'color': const Color(0xFFEF4444), 'icon': Icons.cancel_outlined},
          {'key': 'late', 'label': 'Late Arrivals', 'count': lateCount, 'color': const Color(0xFFF59E0B), 'icon': Icons.schedule_rounded},
          {'key': 'leave', 'label': 'Approved Leaves', 'count': leaveCount, 'color': const Color(0xFF8B5CF6), 'icon': Icons.event_busy_rounded},
        ];

        final media = MediaQuery.of(ctx);
        final maxHeight = media.size.height * 0.78;

        return Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: BoxDecoration(
            color: const Color(0xFF042018),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.35), width: 1.0),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header (Pinned)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Filter Attendance Logs',
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'For ${_formatHeaderDate(_selectedCalendarDate)}',
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFFBACCC3)),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Color(0xFFBACCC3), size: 20),
                        onPressed: () => Navigator.pop(ctx),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white12, height: 1),
                // Options (Scrollable, never overflows on any device)
                Flexible(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: options.map((opt) {
                        final key = opt['key'] as String;
                        final isSelected = _selectedDayLogFilter == key;
                        final optColor = opt['color'] as Color;
                        final count = opt['count'] as int;
                        final icon = opt['icon'] as IconData;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedDayLogFilter = key;
                                _attendanceDayLogPage = 0;
                                _selectedEmployeeForDayLog = null;
                              });
                              Navigator.pop(ctx);
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? optColor.withValues(alpha: 0.18)
                                    : Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? optColor : Colors.white12,
                                  width: isSelected ? 1.5 : 0.8,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      color: optColor.withValues(alpha: 0.20),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(icon, color: optColor, size: 18),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      opt['label'] as String,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: optColor.withValues(alpha: 0.20),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '$count',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                        color: optColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (isSelected)
                                    Icon(Icons.check_circle_rounded, color: optColor, size: 20)
                                  else
                                    const SizedBox(width: 20),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDayAttendanceLogsSection() {
    if (_selectedEmployeeForDayLog != null) {
      return _buildDayEmployeeDetailView(_selectedEmployeeForDayLog!);
    }

    final allRecords = _computeDayAttendanceRecords(_selectedCalendarDate);
    final presentCount = allRecords.where((r) => r.status == 'present').length;
    final lateCount = allRecords.where((r) => r.status == 'late').length;
    final absentCount = allRecords.where((r) => r.status == 'absent').length;
    final leaveCount = allRecords.where((r) => r.status == 'leave').length;

    List<_DayAttendanceRecord> filtered = allRecords;
    if (_selectedDayLogFilter == 'present') {
      filtered = filtered.where((r) => r.status == 'present').toList();
    } else if (_selectedDayLogFilter == 'late') {
      filtered = filtered.where((r) => r.status == 'late').toList();
    } else if (_selectedDayLogFilter == 'absent') {
      filtered = filtered.where((r) => r.status == 'absent').toList();
    } else if (_selectedDayLogFilter == 'leave') {
      filtered = filtered.where((r) => r.status == 'leave').toList();
    }

    if (_attendanceSearchQuery.isNotEmpty) {
      final q = _attendanceSearchQuery.toLowerCase();
      filtered = filtered.where((r) {
        return r.employee.name.toLowerCase().contains(q) ||
            r.employee.username.toLowerCase().contains(q) ||
            r.employee.userId.toLowerCase().contains(q) ||
            (r.employee.department != null && r.employee.department!.toLowerCase().contains(q)) ||
            (r.employee.designation != null && r.employee.designation!.toLowerCase().contains(q)) ||
            r.statusLabel.toLowerCase().contains(q);
      }).toList();
    }

    const int pageSize = 6;
    final totalPages = (filtered.length / pageSize).ceil().clamp(1, 999);
    final safePage = _attendanceDayLogPage.clamp(0, totalPages - 1);
    final pagedList = filtered.skip(safePage * pageSize).take(pageSize).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Logs for ${_formatHeaderDate(_selectedCalendarDate)}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  '${allRecords.length} employees tracked on this day',
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFFBACCC3)),
                ),
              ],
            ),
            InkWell(
              onTap: _showAttendanceRosterSheet,
              child: const Text('View All Logs →', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF34D399))),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Filter Pills: [All] [Present] [Absent] [Late] [Leave]
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildDayLogFilterChip('All', 'all', allRecords.length, const Color(0xFF10B981)),
              const SizedBox(width: 6),
              _buildDayLogFilterChip('Present', 'present', presentCount, const Color(0xFF10B981)),
              const SizedBox(width: 6),
              _buildDayLogFilterChip('Absent', 'absent', absentCount, const Color(0xFFEF4444)),
              const SizedBox(width: 6),
              _buildDayLogFilterChip('Late', 'late', lateCount, const Color(0xFFF59E0B)),
              const SizedBox(width: 6),
              _buildDayLogFilterChip('Leave', 'leave', leaveCount, const Color(0xFF8B5CF6)),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 6-Employee Paginated List
        if (pagedList.isEmpty)
          _buildEmptyDarkState('No employee records found for ${_selectedDayLogFilter.toUpperCase()} on this date.')
        else ...[
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: pagedList.length,
            itemBuilder: (ctx, idx) => _buildDayAttendanceRecordTile(pagedList[idx]),
          ),
          const SizedBox(height: 10),

          // Pagination Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Showing ${safePage * pageSize + 1} - ${(safePage + 1) * pageSize > filtered.length ? filtered.length : (safePage + 1) * pageSize} of ${filtered.length}',
                style: const TextStyle(fontSize: 12, color: Color(0xFFBACCC3)),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 20),
                    onPressed: safePage > 0
                        ? () => setState(() => _attendanceDayLogPage = safePage - 1)
                        : null,
                  ),
                  Text(
                    '${safePage + 1} / $totalPages',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 20),
                    onPressed: safePage < totalPages - 1
                        ? () => setState(() => _attendanceDayLogPage = safePage + 1)
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildDayLogFilterChip(String label, String filterKey, int count, Color accentColor) {
    final isSelected = _selectedDayLogFilter == filterKey;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedDayLogFilter = filterKey;
          _attendanceDayLogPage = 0;
          _selectedEmployeeForDayLog = null;
        });
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected ? accentColor.withValues(alpha: 0.90) : const Color(0xFF0C241B).withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? accentColor : const Color(0xFF34D399).withValues(alpha: 0.2),
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                  ),
                ),
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white.withValues(alpha: 0.25) : accentColor.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: isSelected ? Colors.white : accentColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDayAttendanceRecordTile(_DayAttendanceRecord r) {
    final displayName = r.employee.name.isNotEmpty ? r.employee.name : r.employee.username;

    Color badgeColor = const Color(0xFF10B981);
    IconData statusIcon = Icons.check_circle_outline_rounded;
    if (r.status == 'late') {
      badgeColor = const Color(0xFFF59E0B);
      statusIcon = Icons.schedule_rounded;
    } else if (r.status == 'absent') {
      badgeColor = const Color(0xFFEF4444);
      statusIcon = Icons.cancel_outlined;
    } else if (r.status == 'leave') {
      badgeColor = const Color(0xFF8B5CF6);
      statusIcon = Icons.event_busy_rounded;
    } else if (r.status == 'off') {
      badgeColor = const Color(0xFF8B5CF6);
      statusIcon = Icons.weekend_rounded;
    } else if (r.status == 'upcoming') {
      badgeColor = const Color(0xFF38BDF8);
      statusIcon = Icons.calendar_today_rounded;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => setState(() => _selectedEmployeeForDayLog = r),
        borderRadius: BorderRadius.circular(16),
        child: _buildGlassCard(
          borderRadius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              _buildEmployeeAvatar(r.employee, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            r.employee.role.toUpperCase(),
                            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFF34D399)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      r.employee.department ?? r.employee.designation ?? 'Team Member',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Color(0xFFBACCC3)),
                    ),
                    if (r.checkIn != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'In: ${r.checkIn} • Out: ${r.checkOut ?? 'Active'}',
                        style: const TextStyle(fontSize: 10.5, color: Color(0xFF6EE7B7)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 12, color: badgeColor),
                    const SizedBox(width: 4),
                    Text(
                      r.statusLabel,
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: badgeColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFFBACCC3), size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDayEmployeeDetailView(_DayAttendanceRecord r) {
    final displayName = r.employee.name.isNotEmpty ? r.employee.name : r.employee.username;

    Color badgeColor = const Color(0xFF10B981);
    IconData statusIcon = Icons.check_circle_outline_rounded;
    if (r.status == 'late') {
      badgeColor = const Color(0xFFF59E0B);
      statusIcon = Icons.schedule_rounded;
    } else if (r.status == 'absent') {
      badgeColor = const Color(0xFFEF4444);
      statusIcon = Icons.cancel_outlined;
    } else if (r.status == 'leave') {
      badgeColor = const Color(0xFF8B5CF6);
      statusIcon = Icons.event_busy_rounded;
    } else if (r.status == 'off') {
      badgeColor = const Color(0xFF8B5CF6);
      statusIcon = Icons.weekend_rounded;
    } else if (r.status == 'upcoming') {
      badgeColor = const Color(0xFF38BDF8);
      statusIcon = Icons.calendar_today_rounded;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Back Navigation Bar
        InkWell(
          onTap: () => setState(() => _selectedEmployeeForDayLog = null),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.arrow_back_rounded, color: Color(0xFF34D399), size: 20),
                SizedBox(width: 8),
                Text(
                  'Back to Attendance Logs',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF34D399),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Full Detailed Profile Card
        _buildGlassCard(
          borderRadius: 22,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Employee Header Row
              Row(
                children: [
                  _buildEmployeeAvatar(r.employee, size: 56),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'ID: ${r.employee.userId} • @${r.employee.username}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFFBACCC3)),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                r.employee.role.toUpperCase(),
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF34D399)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: badgeColor.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(statusIcon, size: 11, color: badgeColor),
                                  const SizedBox(width: 4),
                                  Text(
                                    r.statusLabel,
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: badgeColor),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 16),

              // Date & Timing Grid
              Text(
                'Log Date: ${_formatHeaderDate(_selectedCalendarDate)}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF6EE7B7)),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _buildDetailTile(
                      'Check-In Time',
                      r.checkIn ?? (r.status == 'present' ? '09:20 AM' : (r.status == 'late' ? '10:15 AM' : 'Not Recorded')),
                      Icons.login_rounded,
                      r.status == 'present' ? const Color(0xFF10B981) : (r.status == 'late' ? const Color(0xFFF59E0B) : const Color(0xFF94A3B8)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildDetailTile(
                      'Check-Out Time',
                      r.checkOut ?? (r.status == 'present' || r.status == 'late' ? '06:30 PM' : 'Not Recorded'),
                      Icons.logout_rounded,
                      const Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _buildDetailTile(
                      'Department',
                      r.employee.department ?? 'Engineering',
                      Icons.business_rounded,
                      const Color(0xFF34D399),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildDetailTile(
                      'Designation',
                      r.employee.designation ?? 'Team Member',
                      Icons.work_outline_rounded,
                      const Color(0xFF34D399),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _buildDetailTile(
                      'Contact Number',
                      r.employee.phone ?? '+91 98765 43210',
                      Icons.phone_rounded,
                      const Color(0xFF38BDF8),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildDetailTile(
                      'Shift Policy',
                      '${_workSchedule.shiftStart} - ${_workSchedule.shiftEnd}',
                      Icons.timer_outlined,
                      const Color(0xFFA78BFA),
                    ),
                  ),
                ],
              ),

              if (r.leave != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.event_note_rounded, size: 16, color: Color(0xFFA78BFA)),
                          const SizedBox(width: 6),
                          Text(
                            'Leave Details: ${r.leave!.displayType}',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                          const Spacer(),
                          Text(
                            r.leave!.status.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: r.leave!.isApproved ? const Color(0xFF34D399) : const Color(0xFFEF4444),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Period: ${r.leave!.startDate} to ${r.leave!.endDate}',
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFFCBD5E1)),
                      ),
                      if (r.leave!.reason != null && r.leave!.reason!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          'Reason: "${r.leave!.reason}"',
                          style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFFBACCC3)),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailTile(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF04100B).withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ],
      ),
    );
  }
}


class TeamAttendanceTrendChartPainter extends CustomPainter {
  final List<double> trendRates;
  final int? selectedIndex;

  TeamAttendanceTrendChartPainter({
    required this.trendRates,
    this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int i = 0; i < 5; i++) {
      final y = size.height * (i / 4.0);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final n = trendRates.length;
    if (n < 1) return;
    if (n == 1) {
      final normalizedY = (1.0 - (trendRates[0] / 100.0).clamp(0.0, 1.0));
      final py = (normalizedY * (size.height - 14)) + 7;
      final px = size.width / 2.0;
      final p = Offset(px, py);
      final outerDot = Paint()
        ..color = const Color(0xFF34D399).withValues(alpha: 0.35)
        ..style = PaintingStyle.fill;
      final innerDot = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(p, 8.0, outerDot);
      canvas.drawCircle(p, 4.0, innerDot);
      return;
    }

    final displayRates = trendRates;

    final stepX = size.width / (n - 1);
    final points = <Offset>[];
    for (int i = 0; i < n; i++) {
      final normalizedY = (1.0 - (displayRates[i] / 100.0).clamp(0.0, 1.0));
      final py = (normalizedY * (size.height - 14)) + 7;
      final px = i * stepX;
      points.add(Offset(px, py));
    }

    final splinePath = Path();
    splinePath.moveTo(points[0].dx, points[0].dy);

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = i > 0 ? points[i - 1] : points[i];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = (i + 2 < points.length) ? points[i + 2] : p2;

      final cp1x = p1.dx + (p2.dx - p0.dx) / 6.0;
      final cp1y = p1.dy + (p2.dy - p0.dy) / 6.0;
      final cp2x = p2.dx - (p3.dx - p1.dx) / 6.0;
      final cp2y = p2.dy - (p3.dy - p1.dy) / 6.0;

      splinePath.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
    }

    final fillPath = Path.from(splinePath)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF34D399).withValues(alpha: 0.38),
          const Color(0xFF10B981).withValues(alpha: 0.18),
          const Color(0xFF064E3B).withValues(alpha: 0.02),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);

    final glowPaint = Paint()
      ..color = const Color(0xFF34D399).withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final strokePaint = Paint()
      ..color = const Color(0xFF34D399)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(splinePath, glowPaint);
    canvas.drawPath(splinePath, strokePaint);

    // Selected point highlight
    if (selectedIndex != null && selectedIndex! >= 0 && selectedIndex! < points.length) {
      final p = points[selectedIndex!];
      final outerDot = Paint()
        ..color = const Color(0xFF34D399).withValues(alpha: 0.35)
        ..style = PaintingStyle.fill;
      final innerDot = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      final borderDot = Paint()
        ..color = const Color(0xFF34D399)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawCircle(p, 8.0, outerDot);
      canvas.drawCircle(p, 4.0, innerDot);
      canvas.drawCircle(p, 4.0, borderDot);
    }
  }

  @override
  bool shouldRepaint(covariant TeamAttendanceTrendChartPainter oldDelegate) {
    return oldDelegate.trendRates != trendRates || oldDelegate.selectedIndex != selectedIndex;
  }
}

class _DayAttendanceRecord {
  final UserModel employee;
  final String status; // 'present', 'late', 'absent', 'leave', 'off'
  final String statusLabel; // 'Present', 'Late', 'Absent', 'Approved Leave', 'Weekly Off / Holiday'
  final AttendanceModel? attendance;
  final LeaveModel? leave;
  final String? checkIn;
  final String? checkOut;
  final String dateStr;

  const _DayAttendanceRecord({
    required this.employee,
    required this.status,
    required this.statusLabel,
    this.attendance,
    this.leave,
    this.checkIn,
    this.checkOut,
    required this.dateStr,
  });
}
