import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../attendance/data/attendance_model.dart';
import '../../attendance/data/attendance_service.dart';
import '../../attendance/data/work_schedule_model.dart';
import '../../auth/data/user_model.dart';
import '../../dashboard/data/dashboard_service.dart';
import '../../dashboard/data/leave_model.dart';
import '../../tasks/data/task_model.dart';
import '../data/calendar_event_model.dart';
import '../data/calendar_service.dart';
import '../data/holiday_model.dart';
import '../data/leave_service.dart';
import 'widgets/calendar_item_detail_dialog.dart';

/// Screen 5: Professional Employee Calendar Module
///
/// Features:
/// - Exact visual and structural parity with Company Calendar design system
/// - Starts strictly from employee joining year and month (cannot navigate prior to joining)
/// - Company calendar color scheme:
///   - Event: Violet (#7C3AED) with ★
///   - Holiday: Dark Grey (#1E293B) with dot indicator
///   - Birthday: Gold/Amber (#F59E0B) with 🎂
///   - Absent: Red (#EF4444)
///   - Late: Orange/Amber (#F97316)
///   - Present: Forest Green (#1B5E4B)
/// - Dual Color: Renders diagonal split gradient when a day has BOTH attendance status AND an event/holiday/birthday
/// - Pure Calendar display (no attendance toggle inside calendar)
/// - Comprehensive Selected Day Details section below the calendar grid
class CalendarView extends StatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback? onOpenDrawer;
  final UserModel? user;

  const CalendarView({
    super.key,
    this.onBack,
    this.onOpenDrawer,
    this.user,
  });

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  final CalendarService _calendarService = CalendarService();
  final AttendanceService _attendanceService = AttendanceService();
  final DashboardService _dashboardService = DashboardService();
  final LeaveService _leaveService = LeaveService();

  late DateTime _selectedDate;
  late DateTime _currentMonth;

  bool _isLoading = true;
  String? _errorMessage;

  WorkScheduleModel _workSchedule = const WorkScheduleModel();
  List<HolidayModel> _rawHolidays = [];
  List<CalendarEventModel> _companyEvents = [];
  List<CalendarEventModel> _holidays = [];
  List<AttendanceModel> _attendance = [];
  List<TaskModel> _tasks = [];
  List<LeaveModel> _leaves = [];
  List<UserModel> _teamMembers = [];

  DateTime get _startMonthDate {
    if (widget.user != null) {
      final jd = widget.user!.joinedDate;
      return DateTime(jd.year, jd.month, 1);
    }
    return DateTime(2024, 1, 1);
  }

  bool get _canGoPrevMonth {
    final prevMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    return !prevMonth.isBefore(_startMonthDate);
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final startDate = _startMonthDate;
    final currentTarget = DateTime(now.year, now.month, 1);
    _currentMonth = currentTarget.isBefore(startDate) ? startDate : currentTarget;

    final today = DateTime(now.year, now.month, now.day);
    _selectedDate = today.isBefore(startDate) ? startDate : today;

    _loadAllBackendData();
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

  String _getMonthYearName(DateTime dt) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[(dt.month - 1).clamp(0, 11)]} ${dt.year}';
  }

  String _formatFullDate(DateTime dt) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final dayName = days[(dt.weekday - 1).clamp(0, 6)];
    final monthName = months[(dt.month - 1).clamp(0, 11)];
    return '$dayName, ${dt.day} $monthName ${dt.year}';
  }

  String _getDayName(DateTime dt) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[(dt.weekday - 1).clamp(0, 6)];
  }

  bool _isNonWorkingDay(DateTime date) {
    final daysPerWeek = _workSchedule.workingDaysPerWeek;
    if (daysPerWeek == 5) {
      return date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
    } else if (daysPerWeek == 6) {
      return date.weekday == DateTime.sunday;
    } else if (daysPerWeek == 4) {
      return date.weekday == DateTime.friday ||
          date.weekday == DateTime.saturday ||
          date.weekday == DateTime.sunday;
    } else if (daysPerWeek == 7) {
      return false;
    }
    return _workSchedule.isWeeklyOff(date);
  }

  Future<void> _loadAllBackendData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final user = widget.user;

    try {
      // 1. Fetch holidays and work schedule from attendance service (matches Company Calendar exactly)
      List<HolidayModel> holidayModels = [];
      WorkScheduleModel schedule = const WorkScheduleModel();
      try {
        final results = await Future.wait([
          _attendanceService.getHolidays(),
          _attendanceService.getWorkSchedule(),
        ]);
        holidayModels = results[0] as List<HolidayModel>;
        schedule = results[1] as WorkScheduleModel;
      } catch (_) {
        try {
          holidayModels = await _attendanceService.getHolidays();
        } catch (_) {}
        try {
          schedule = await _attendanceService.getWorkSchedule();
        } catch (_) {}
      }

      if (holidayModels.isEmpty) {
        try {
          final calEvents = await _calendarService.fetchEvents(
            user: user ?? const UserModel(id: '', userId: '', username: '', name: '', role: 'staff', token: ''),
          );
          for (final ce in calEvents) {
            holidayModels.add(HolidayModel(
              id: ce.id,
              name: ce.title,
              date: '${ce.dateTime.year}-${ce.dateTime.month.toString().padLeft(2, '0')}-${ce.dateTime.day.toString().padLeft(2, '0')}',
              description: ce.description,
              isEvent: ce.category.toLowerCase() == 'event',
              salaryDeduction: ce.salaryDeduction,
            ));
          }
        } catch (_) {}
      }

      final eventsOnly = <CalendarEventModel>[];
      final holidaysOnly = <CalendarEventModel>[];

      for (final h in holidayModels) {
        DateTime? dt;
        try {
          dt = DateTime.parse(h.date);
        } catch (_) {}
        if (dt != null) {
          final calEvent = CalendarEventModel(
            id: h.id,
            title: h.name,
            dateTime: dt,
            time: h.isEvent ? 'Company Event • Working Day' : 'All Day • Official Holiday',
            category: h.isEvent ? 'Event' : 'Holiday',
            description: h.description,
            companyId: h.companyId,
            roleAccess: 'all',
            salaryDeduction: h.salaryDeduction,
          );
          if (h.isEvent) {
            eventsOnly.add(calEvent);
          } else {
            holidaysOnly.add(calEvent);
          }
        }
      }

      // 2. Comprehensive Attendance Fetching (by userId, id, company roster, and today)
      final attList = <AttendanceModel>[];
      final seenAttDates = <String>{};

      // 2a. Fetch by user.userId
      if (user?.userId.isNotEmpty == true) {
        try {
          final list = await _attendanceService.getUserAttendanceHistory(user!.userId);
          for (final a in list) {
            final d = a.date.contains('T') ? a.date.split('T').first : a.date;
            if (seenAttDates.add(d)) {
              attList.add(a);
            }
          }
        } catch (_) {}
      }

      // 2b. Fetch by user.id if distinct
      if (user?.id.isNotEmpty == true && user!.id != user.userId) {
        try {
          final list = await _attendanceService.getUserAttendanceHistory(user.id);
          for (final a in list) {
            final d = a.date.contains('T') ? a.date.split('T').first : a.date;
            if (seenAttDates.add(d)) {
              attList.add(a);
            }
          }
        } catch (_) {}
      }

      // 2c. Fetch Company Attendance roster fallback
      try {
        final companyAtt = await _attendanceService.getCompanyAttendance();
        for (final a in companyAtt) {
          final matchesUser = (user != null) &&
              (a.userId == user.userId ||
               a.userId == user.id ||
               (user.username.isNotEmpty && a.userId == user.username));
          if (matchesUser) {
            final d = a.date.contains('T') ? a.date.split('T').first : a.date;
            if (seenAttDates.add(d)) {
              attList.add(a);
            }
          }
        }
      } catch (_) {}

      // 2d. Explicit Today's Attendance Fetch
      try {
        final todayAtt = await _attendanceService.getTodayAttendance(
          userId: user?.userId.isNotEmpty == true ? user!.userId : user?.id,
        );
        if (todayAtt != null) {
          final d = todayAtt.date.contains('T') ? todayAtt.date.split('T').first : todayAtt.date;
          attList.removeWhere((a) => (a.date.contains('T') ? a.date.split('T').first : a.date) == d);
          attList.add(todayAtt);
        }
      } catch (_) {}

      // 3. Concurrent Tasks, Leaves, and Team Members Fetching
      final remaining = await Future.wait([
        _dashboardService.getTasks(),
        _leaveService.getUserLeaves(
          user?.userId.isNotEmpty == true ? user!.userId : (user?.id ?? ''),
        ),
        _dashboardService.getUsers(),
      ]);

      if (!mounted) return;

      final taskList = remaining[0] as List<TaskModel>;
      final leaveList = remaining[1] as List<LeaveModel>;
      final userList = remaining[2] as List<UserModel>;

      setState(() {
        _workSchedule = schedule;
        _rawHolidays = holidayModels;
        _companyEvents = eventsOnly;
        _holidays = holidaysOnly;
        _attendance = attList;
        _tasks = taskList;
        _leaves = leaveList;
        _teamMembers = userList;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showCalendarDatePickerDialog() async {
    final startDate = _startMonthDate;
    final now = DateTime.now();
    final maxDate = DateTime(now.year + 2, 12, 31);

    final initial = _selectedDate.isBefore(startDate)
        ? startDate
        : (_selectedDate.isAfter(maxDate) ? maxDate : _selectedDate);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: startDate,
      lastDate: maxDate,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: CeladonColors.primary,
              onPrimary: Colors.white,
              onSurface: CeladonColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
        _currentMonth = DateTime(picked.year, picked.month, 1);
      });
    }
  }

  List<UserModel> _getBirthdayEmployees(DateTime date) {
    return _teamMembers.where((u) {
      if (u.dateOfBirth == null || u.dateOfBirth!.isEmpty) return false;
      try {
        final dob = DateTime.parse(u.dateOfBirth!);
        return dob.month == date.month && dob.day == date.day;
      } catch (_) {
        return false;
      }
    }).toList();
  }

  CalendarEventModel? _getCompanyEventOnDate(DateTime date) {
    final targetStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    for (final e in _companyEvents) {
      if (e.dateTime.year == date.year &&
          e.dateTime.month == date.month &&
          e.dateTime.day == date.day) {
        return e;
      }
      final eStr = e.dateTime.toIso8601String();
      if (eStr.startsWith(targetStr)) {
        return e;
      }
    }
    return null;
  }

  CalendarEventModel? _getHolidayOnDate(DateTime date) {
    final targetStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    for (final h in _holidays) {
      if (h.dateTime.year == date.year &&
          h.dateTime.month == date.month &&
          h.dateTime.day == date.day) {
        return h;
      }
      final hStr = h.dateTime.toIso8601String();
      if (hStr.startsWith(targetStr)) {
        return h;
      }
    }
    for (final raw in _rawHolidays) {
      if (!raw.isEvent && (raw.date == targetStr || raw.date.startsWith(targetStr))) {
        return CalendarEventModel(
          id: raw.id,
          title: raw.name,
          dateTime: DateTime(date.year, date.month, date.day),
          time: 'All Day • Official Holiday',
          category: 'Holiday',
          description: raw.description,
          companyId: raw.companyId,
          roleAccess: 'all',
          salaryDeduction: raw.salaryDeduction,
        );
      }
    }
    return null;
  }

  AttendanceModel? _getAttendanceOnDate(DateTime date) {
    final targetStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    for (final att in _attendance) {
      final cleanDate = att.date.contains('T') ? att.date.split('T').first : att.date;
      if (cleanDate == targetStr || att.date.startsWith(targetStr)) {
        return att;
      }
      final parsed = DateTime.tryParse(att.date);
      if (parsed != null &&
          parsed.year == date.year &&
          parsed.month == date.month &&
          parsed.day == date.day) {
        return att;
      }
      if (att.checkIn != null) {
        final inParsed = DateTime.tryParse(att.checkIn!);
        if (inParsed != null &&
            inParsed.year == date.year &&
            inParsed.month == date.month &&
            inParsed.day == date.day) {
          return att;
        }
      }
    }
    return null;
  }

  List<TaskModel> _getTasksOnDate(DateTime date) {
    return _tasks.where((t) {
      if (t.dueDate == null || t.dueDate!.isEmpty) return false;
      final parsed = DateTime.tryParse(t.dueDate!);
      return parsed != null &&
          parsed.year == date.year &&
          parsed.month == date.month &&
          parsed.day == date.day;
    }).toList();
  }

  List<LeaveModel> _getLeavesOnDate(DateTime date) {
    return _leaves.where((l) {
      final start = DateTime.tryParse(l.startDate);
      final end = DateTime.tryParse(l.endDate);
      if (start == null) return false;
      final target = DateTime(date.year, date.month, date.day);
      final s = DateTime(start.year, start.month, start.day);
      final e = end != null ? DateTime(end.year, end.month, end.day) : s;
      return (target.isAfter(s) || target.isAtSameMomentAs(s)) &&
          (target.isBefore(e) || target.isAtSameMomentAs(e));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CeladonColors.background,
      floatingActionButton: null,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadAllBackendData,
          color: CeladonColors.primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Header Bar with Brand and View Pills
                _buildHeaderBar(),
                const SizedBox(height: 12),

                if (_errorMessage != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFDC2626)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 80),
                    child: Center(
                      child: CircularProgressIndicator(color: CeladonColors.primary),
                    ),
                  )
                else ...[
                  // 2. Month Calendar Card (Mirroring Company Calendar UI with Dual Color)
                  _buildMonthCalendarCard(),
                  const SizedBox(height: 16),

                  // 3. Selected Day Details Card (Dynamic details for selected date)
                  _buildSelectedDayDetailsCard(),
                ],
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderBar() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: CeladonColors.textPrimary,
            size: 22,
          ),
          tooltip: 'Back',
          onPressed: widget.onBack ??
              () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                } else if (widget.onOpenDrawer != null) {
                  widget.onOpenDrawer!();
                }
              },
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Calendar',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: CeladonColors.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'View company holidays, work shifts & schedule timelines',
                style: TextStyle(
                  fontSize: 11.5,
                  color: CeladonColors.textMuted,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Canonical Month Calendar Card mirroring Company Calendar UI with Dual Color support
  Widget _buildMonthCalendarCard() {
    final year = _currentMonth.year;
    final month = _currentMonth.month;
    final firstDayOfMonth = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final startWeekday = firstDayOfMonth.weekday % 7; // 0=Sun, 6=Sat

    const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return Container(
      decoration: BoxDecoration(
        color: CeladonColors.cardBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: CeladonColors.border, width: 1.0),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          // Month Navigation Row with constrained Date Picker
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: Icon(
                  Icons.chevron_left_rounded,
                  color: _canGoPrevMonth ? CeladonColors.textPrimary : CeladonColors.textPlaceholder,
                  size: 24,
                ),
                onPressed: _canGoPrevMonth
                    ? () {
                        setState(() {
                          _currentMonth = DateTime(year, month - 1, 1);
                        });
                      }
                    : null,
              ),
              GestureDetector(
                onTap: _showCalendarDatePickerDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: CeladonColors.searchBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: CeladonColors.border, width: 1.0),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _getMonthYearName(_currentMonth),
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: CeladonColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 15,
                        color: CeladonColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.chevron_right_rounded,
                  color: CeladonColors.textPrimary,
                  size: 24,
                ),
                onPressed: () {
                  setState(() {
                    _currentMonth = DateTime(year, month + 1, 1);
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
                      color: CeladonColors.textMuted,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),

          // Days Grid (Square Cells with Dual Color Support)
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
              final isSelected = dayDate.year == _selectedDate.year &&
                  dayDate.month == _selectedDate.month &&
                  dayDate.day == _selectedDate.day;

              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              final isToday = dayDate.year == today.year &&
                  dayDate.month == today.month &&
                  dayDate.day == today.day;
              final isPast = dayDate.isBefore(today);
              final isNonWorking = _isNonWorkingDay(dayDate);

              // 1. Birthday Check
              final birthdayEmployees = _getBirthdayEmployees(dayDate);
              final hasBirthday = birthdayEmployees.isNotEmpty;

              // 2. Company Event Check
              final event = _getCompanyEventOnDate(dayDate);
              final isEvent = event != null;

              // 3. Holiday Check
              final holiday = _getHolidayOnDate(dayDate);
              final isHoliday = holiday != null;

              // 4. Leave Check (both approved and unapproved leaves are considered absent in employee calendar)
              final leaves = _getLeavesOnDate(dayDate);
              final hasLeave = leaves.isNotEmpty;

              // 5. Attendance Check
              final att = _getAttendanceOnDate(dayDate);
              bool isLate = false;
              bool isAbsent = false;

              if (hasLeave) {
                // In employee calendar, both approved and unapproved leaves are considered absent
                isAbsent = true;
              } else if (att != null) {
                if (att.isLate || att.status.toLowerCase() == 'late') {
                  isLate = true;
                } else if (att.status.toLowerCase() == 'absent') {
                  isAbsent = true;
                }
              } else if (!isNonWorking && !isHoliday) {
                if (!dayDate.isBefore(_startMonthDate)) {
                  if (isPast || isToday) {
                    isAbsent = true;
                  }
                }
              }

              // Attendance Color: DO NOT give color for present in employee calendar!
              // Only absent, late, event, holiday, birthday show color.
              Color? attendanceColor;
              if (isAbsent) {
                attendanceColor = const Color(0xFFEF4444); // Red
              } else if (isLate) {
                attendanceColor = const Color(0xFFF97316); // Amber/Orange
              }
              // Present is deliberately uncolored in employee calendar per user request

              // Special Day Color
              Color? specialDayColor;
              final hasApprovedUpcomingLeave = leaves.any((l) => l.isApproved && !dayDate.isBefore(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)));
              if (hasApprovedUpcomingLeave) {
                specialDayColor = const Color(0xFF2563EB); // Golden Blue for approved upcoming leaves
              } else if (hasBirthday) {
                specialDayColor = const Color(0xFFF59E0B); // Gold
              } else if (isEvent) {
                specialDayColor = const Color(0xFF7C3AED); // Violet
              } else if (isHoliday) {
                specialDayColor = const Color(0xFF1E293B); // Dark Slate
              }

              final bool isDualColor = attendanceColor != null && specialDayColor != null;

              BoxDecoration cellDecoration;
              Color textColor = CeladonColors.textPrimary;

              if (isDualColor) {
                // Dual Color: Split diagonal half-and-half gradient between attendance status (late/absent) and event/birthday/holiday
                cellDecoration = BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    stops: const [0.5, 0.5],
                    colors: [attendanceColor, specialDayColor],
                  ),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected ? CeladonColors.primary : Colors.white70,
                    width: isSelected ? 2.5 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: attendanceColor.withValues(alpha: 0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                );
                textColor = Colors.white;
              } else if (attendanceColor != null) {
                // Pure Attendance Color (Absent Red, Late Orange)
                cellDecoration = BoxDecoration(
                  color: attendanceColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.transparent,
                    width: isSelected ? 2.5 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: attendanceColor.withValues(alpha: 0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                );
                textColor = Colors.white;
              } else if (specialDayColor != null) {
                // Pure Special Day Color (Birthday Gold, Event Violet, Holiday Dark Grey)
                cellDecoration = BoxDecoration(
                  color: specialDayColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected ? CeladonColors.primary : Colors.transparent,
                    width: isSelected ? 2.5 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: specialDayColor.withValues(alpha: 0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                );
                textColor = Colors.white;
              } else if (isNonWorking) {
                // Weekly off / Saturday & Sunday per company work policy
                cellDecoration = BoxDecoration(
                  color: CeladonColors.holidayLight,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected ? CeladonColors.primary : CeladonColors.holidayBorder,
                    width: isSelected ? 2.0 : 1.0,
                  ),
                );
                textColor = CeladonColors.holidayGrey;
              } else {
                // Regular Working Day (including Present)
                cellDecoration = BoxDecoration(
                  color: isSelected ? CeladonColors.primaryLight : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected ? CeladonColors.primary : CeladonColors.border,
                    width: isSelected ? 2.0 : 1.0,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: CeladonColors.primary.withValues(alpha: 0.2),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                );
                textColor = isSelected ? CeladonColors.primaryDark : CeladonColors.textPrimary;
              }

              return GestureDetector(
                onTap: () {
                  setState(() => _selectedDate = dayDate);
                },
                child: Container(
                  decoration: cellDecoration,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$dayNum',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: (isSelected ||
                                    attendanceColor != null ||
                                    specialDayColor != null)
                                ? FontWeight.w800
                                : FontWeight.w500,
                            color: textColor,
                          ),
                        ),
                        if (hasBirthday)
                          const Text(
                            '🎂',
                            style: TextStyle(fontSize: 8, height: 0.8),
                          )
                        else if (isEvent)
                          const Text(
                            '★',
                            style: TextStyle(fontSize: 8, height: 0.8, color: Colors.white),
                          )
                        else if (isHoliday)
                          Container(
                            margin: const EdgeInsets.only(top: 1.5),
                            width: 4.5,
                            height: 4.5,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          )
                        else if (isLate || isAbsent)
                          Container(
                            margin: const EdgeInsets.only(top: 1.5),
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),

          // Calendar Color Legend matching Company styling (Present has no color in employee calendar)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: [
              _buildLegendDot(const Color(0xFFEF4444), 'Absent'),
              _buildLegendDot(const Color(0xFFF97316), 'Late'),
              _buildLegendDot(const Color(0xFF7C3AED), 'Event ★'),
              _buildLegendDot(const Color(0xFF1E293B), 'Holiday'),
              _buildLegendDot(const Color(0xFFF59E0B), 'Birthday 🎂'),
              _buildLegendDot(CeladonColors.holidayBorder, 'Weekly Off'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            color: CeladonColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  /// Day Details Section right beneath the Calendar Card
  Widget _buildSelectedDayDetailsCard() {
    final att = _getAttendanceOnDate(_selectedDate);
    final event = _getCompanyEventOnDate(_selectedDate);
    final holiday = _getHolidayOnDate(_selectedDate);
    final birthdays = _getBirthdayEmployees(_selectedDate);
    final tasks = _getTasksOnDate(_selectedDate);
    final leaves = _getLeavesOnDate(_selectedDate);
    final hasLeave = leaves.isNotEmpty;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isToday = _selectedDate.year == today.year &&
        _selectedDate.month == today.month &&
        _selectedDate.day == today.day;
    final isPast = _selectedDate.isBefore(today);
    final isNonWorking = _isNonWorkingDay(_selectedDate);

    bool isLate = false;
    bool isPresent = false;
    bool isAbsent = false;

    if (hasLeave) {
      // In employee calendar, both approved and unapproved leaves are considered absent
      isAbsent = true;
    } else if (att != null) {
      if (att.isLate || att.status.toLowerCase() == 'late') {
        isLate = true;
      } else if (att.status.toLowerCase() == 'absent') {
        isAbsent = true;
      } else if (att.isPresent ||
          att.isHalfDay ||
          att.status.toLowerCase() == 'present' ||
          att.status == '0' ||
          att.status.toLowerCase() == 'half_day' ||
          (att.checkIn != null && att.checkIn!.isNotEmpty)) {
        isPresent = true;
      }
    } else if (!isNonWorking && holiday == null) {
      if (!_selectedDate.isBefore(_startMonthDate)) {
        if (isPast || isToday) {
          isAbsent = true;
        }
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: CeladonColors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CeladonColors.border, width: 1.0),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Row with Date & Tags
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: CeladonColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.event_note_rounded,
                  color: CeladonColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatFullDate(_selectedDate),
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: CeladonColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (isToday)
                          _buildStatusChip('TODAY', CeladonColors.primary, Colors.white),
                        if (isNonWorking)
                          _buildStatusChip('WEEKLY OFF', CeladonColors.holidayGrey, Colors.white),
                        if (isAbsent)
                          _buildStatusChip(hasLeave ? 'ABSENT (LEAVE)' : 'ABSENT', const Color(0xFFEF4444), Colors.white),
                        if (isLate)
                          _buildStatusChip(
                            att?.breakDelayMinutes != null && att!.breakDelayMinutes > 0
                                ? 'LATE • ${att.breakDelayMinutes}m'
                                : 'LATE ARRIVAL',
                            const Color(0xFFF97316),
                            Colors.white,
                          ),
                        if (isPresent)
                          _buildStatusChip('PRESENT', const Color(0xFF1B5E4B), Colors.white),
                        if (event != null)
                          _buildStatusChip('EVENT ★', const Color(0xFF7C3AED), Colors.white),
                        if (holiday != null)
                          _buildStatusChip('HOLIDAY', const Color(0xFF1E293B), Colors.white),
                        if (birthdays.isNotEmpty)
                          _buildStatusChip('BIRTHDAY 🎂', const Color(0xFFF59E0B), Colors.white),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: CeladonColors.divider, height: 1),
          const SizedBox(height: 14),

          // 1. Attendance Record Detail Card
          if (att != null && !hasLeave) ...[
            _buildAttendanceDetailItem(att),
            const SizedBox(height: 12),
          ] else if (isAbsent && !hasLeave) ...[
            _buildDetailCard(
              icon: Icons.cancel_outlined,
              header: 'Attendance Status (ABSENT)',
              headerColor: const Color(0xFFEF4444),
              title: isToday ? 'Absent Today' : 'Marked Absent',
              subtitle: isToday
                  ? 'No check-in recorded for today yet. Employee is currently absent.'
                  : 'No punch-in was recorded on this past working day.',
              tag: isToday ? 'Pending Check-In' : 'Unexcused Absence',
            ),
            const SizedBox(height: 12),
          ] else if (isNonWorking) ...[
            _buildInfoCard(
              icon: Icons.weekend_outlined,
              color: CeladonColors.holidayGrey,
              title: 'Weekly Off (${_getDayName(_selectedDate)})',
              subtitle: 'Official non-working weekend day according to company work policy (${_workSchedule.workingDaysPerWeek} days/week).',
            ),
            const SizedBox(height: 12),
          ],

          // 2. Company Event Detail Card
          if (event != null) ...[
            _buildDetailCard(
              icon: Icons.event_available_rounded,
              header: 'Company Event ★',
              headerColor: const Color(0xFF7C3AED),
              title: event.title,
              subtitle: event.description != null && event.description!.isNotEmpty
                  ? event.description!
                  : 'Official company event • Working Day',
              tag: event.time,
              onTap: () {
                CalendarItemDetailDialog.show(
                  context,
                  title: event.title,
                  description: event.description,
                  date: event.dateTime.toIso8601String(),
                  isEvent: true,
                  salaryDeduction: event.salaryDeduction,
                );
              },
            ),
            const SizedBox(height: 12),
          ],

          // 3. Official Holiday Detail Card
          if (holiday != null) ...[
            _buildDetailCard(
              icon: Icons.beach_access_rounded,
              header: 'Official Holiday',
              headerColor: const Color(0xFF1E293B),
              title: holiday.title,
              subtitle: holiday.description != null && holiday.description!.isNotEmpty
                  ? holiday.description!
                  : 'Official non-working company holiday',
              tag: 'Public Holiday',
              onTap: () {
                CalendarItemDetailDialog.show(
                  context,
                  title: holiday.title,
                  description: holiday.description,
                  date: holiday.dateTime.toIso8601String(),
                  isEvent: false,
                );
              },
            ),
            const SizedBox(height: 12),
          ],

          // 4. Team Birthday Celebration Card
          if (birthdays.isNotEmpty) ...[
            _buildDetailCard(
              icon: Icons.cake_rounded,
              header: 'Birthday Celebration 🎂',
              headerColor: const Color(0xFFF59E0B),
              title: birthdays.map((u) => u.name.isNotEmpty ? u.name : u.username).join(', '),
              subtitle: 'Wishing our colleague(s) a wonderful and joyous birthday!',
              tag: '${birthdays.length} Celebration',
            ),
            const SizedBox(height: 12),
          ],

          // 5. Leave Request Card (Approved shown in Golden Blue, unapproved/pending in appropriate tag)
          if (leaves.isNotEmpty) ...[
            ...leaves.map((l) {
              final isApproved = l.isApproved;
              final cardColor = isApproved ? const Color(0xFF2563EB) : const Color(0xFFEF4444);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildDetailCard(
                  icon: isApproved ? Icons.event_available_rounded : Icons.flight_takeoff_rounded,
                  header: isApproved ? 'Upcoming Approved Leave (${l.displayType})' : 'Leave / Absence (${l.status.toUpperCase()})',
                  headerColor: cardColor,
                  title: '${l.type.toUpperCase()} LEAVE - ${l.workingDays} working day(s)',
                  subtitle: l.reason?.isNotEmpty == true ? l.reason! : (isApproved ? 'Approved time off recorded on calendar' : 'Leave request recorded as absent'),
                  tag: '${l.startDate} to ${l.endDate}',
                ),
              );
            }),
          ],

          // 6. Assigned Tasks Card
          if (tasks.isNotEmpty) ...[
            ...tasks.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildDetailCard(
                    icon: Icons.assignment_outlined,
                    header: 'Assigned Task (${t.displayPriority})',
                    headerColor: const Color(0xFF7C3AED),
                    title: t.title,
                    subtitle: t.description ?? 'Task assigned to you',
                    tag: 'Due: ${t.dueDate?.split('T').first ?? ''}',
                  ),
                )),
          ],

          // 7. Empty State when nothing is recorded
          if (att == null && event == null && holiday == null && birthdays.isEmpty && tasks.isEmpty && leaves.isEmpty)
            _buildInfoCard(
              icon: Icons.calendar_today_rounded,
              color: CeladonColors.textMuted,
              title: 'Standard Working Day',
              subtitle: 'Regular office hours apply (09:00 AM - 06:00 PM). No events or special logs scheduled.',
            ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label, Color bg, Color text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: text,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildAttendanceDetailItem(AttendanceModel att) {
    final statusColor = att.isAbsent
        ? const Color(0xFFEF4444)
        : (att.isLate ? const Color(0xFFF97316) : const Color(0xFF1B5E4B));

    final inTime = _formatTimeStr(att.checkIn);
    final outTime = _formatTimeStr(att.checkOut);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      att.isAbsent
                          ? Icons.cancel_outlined
                          : (att.isLate ? Icons.alarm_on_rounded : Icons.check_circle_outline_rounded),
                      color: statusColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        att.isAbsent
                            ? 'Absent on Duty'
                            : (att.isLate ? 'Late Arrival Recorded' : 'Present • On Duty'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  (att.workMode ?? 'OFFICE').toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Check-in and Check-out Grid
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: CeladonColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CHECK IN',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: CeladonColors.textMuted),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        inTime,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: CeladonColors.textPrimary),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: CeladonColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CHECK OUT',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: CeladonColors.textMuted),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        outTime,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: CeladonColors.textPrimary),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          if (att.isLate) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFDBA74)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFFEA580C)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      att.breakDelayMinutes > 0
                          ? 'Late arrival by ${att.breakDelayMinutes} minutes recorded.'
                          : 'Clocked in past regular shift start time.',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFFC2410C)),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (att.isAbsent) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Row(
                children: const [
                  Icon(Icons.error_outline_rounded, size: 14, color: Color(0xFFDC2626)),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Unapproved absence recorded for this scheduled workday.',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFFB91C1C)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailCard({
    required IconData icon,
    required String header,
    required Color headerColor,
    required String title,
    required String subtitle,
    required String tag,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: headerColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: headerColor.withValues(alpha: 0.25), width: 1.0),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: headerColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: headerColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          header,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: headerColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      if (tag.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            tag,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: headerColor.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: CeladonColors.textPrimary,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: CeladonColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.chevron_right_rounded,
                color: headerColor.withValues(alpha: 0.6),
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CeladonColors.searchBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CeladonColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: CeladonColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: CeladonColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
