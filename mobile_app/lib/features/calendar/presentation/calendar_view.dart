import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../attendance/data/attendance_model.dart';
import '../../attendance/data/attendance_service.dart';
import '../../auth/data/user_model.dart';
import '../../dashboard/data/dashboard_service.dart';
import '../../dashboard/data/leave_model.dart';
import '../../tasks/data/task_model.dart';
import '../data/calendar_event_model.dart';
import '../data/calendar_service.dart';
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
  int _selectedViewPill = 0; // 0=Month, 1=Week (preserves test compatibility)

  bool _isLoading = true;
  String? _errorMessage;

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

  Future<void> _loadAllBackendData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final user = widget.user;

    try {
      final results = await Future.wait([
        _calendarService.fetchEvents(
          user: user ?? const UserModel(id: '', userId: '', username: '', name: '', role: 'staff', token: ''),
        ),
        _attendanceService.getUserAttendanceHistory(
          user?.userId.isNotEmpty == true ? user!.userId : (user?.id ?? ''),
        ),
        _dashboardService.getTasks(),
        _leaveService.getUserLeaves(
          user?.userId.isNotEmpty == true ? user!.userId : (user?.id ?? ''),
        ),
        _dashboardService.getUsers(),
      ]);

      if (!mounted) return;

      final allEvents = results[0] as List<CalendarEventModel>;
      final attList = results[1] as List<AttendanceModel>;
      final taskList = results[2] as List<TaskModel>;
      final leaveList = results[3] as List<LeaveModel>;
      final userList = results[4] as List<UserModel>;

      final eventsOnly = <CalendarEventModel>[];
      final holidaysOnly = <CalendarEventModel>[];

      for (final e in allEvents) {
        if (e.category.toLowerCase() == 'event') {
          eventsOnly.add(e);
        } else {
          holidaysOnly.add(e);
        }
      }

      setState(() {
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
    for (final e in _companyEvents) {
      if (e.dateTime.year == date.year &&
          e.dateTime.month == date.month &&
          e.dateTime.day == date.day) {
        return e;
      }
    }
    return null;
  }

  CalendarEventModel? _getHolidayOnDate(DateTime date) {
    for (final h in _holidays) {
      if (h.dateTime.year == date.year &&
          h.dateTime.month == date.month &&
          h.dateTime.day == date.day) {
        return h;
      }
    }
    return null;
  }

  AttendanceModel? _getAttendanceOnDate(DateTime date) {
    final targetStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    for (final att in _attendance) {
      if (att.date == targetStr || att.date.startsWith(targetStr)) {
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
      floatingActionButton: FloatingActionButton(
        heroTag: 'calendar_fab_main',
        onPressed: _showCalendarDatePickerDialog,
        backgroundColor: CeladonColors.primary,
        elevation: 4,
        shape: const CircleBorder(),
        tooltip: 'Select Date',
        child: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 26),
      ),
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
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            if (widget.onOpenDrawer != null)
              Container(
                width: 38,
                height: 38,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: CeladonColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.menu_rounded, color: CeladonColors.primary, size: 22),
                  tooltip: 'Menu',
                  onPressed: widget.onOpenDrawer,
                ),
              )
            else if (widget.onBack != null)
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: CeladonColors.primary),
                onPressed: widget.onBack,
              ),

            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'WORKSPACE',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: Color(0xFF829089),
                  ),
                ),
                Text(
                  'Calendar',
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF17231F),
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ],
        ),

        // View Segment Filter (Month / Week - preserving test compatibility)
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE1E8E4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildViewPill('Month', 0),
              _buildViewPill('Week', 1),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildViewPill(String label, int index) {
    final isSelected = _selectedViewPill == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedViewPill = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? CeladonColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : const Color(0xFF829089),
          ),
        ),
      ),
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
                        Icons.edit_calendar_rounded,
                        size: 16,
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

              // 1. Birthday Check
              final birthdayEmployees = _getBirthdayEmployees(dayDate);
              final hasBirthday = birthdayEmployees.isNotEmpty;

              // 2. Company Event Check
              final event = _getCompanyEventOnDate(dayDate);
              final isEvent = event != null;

              // 3. Holiday Check
              final holiday = _getHolidayOnDate(dayDate);
              final isHoliday = holiday != null;

              // 4. Attendance Check
              final att = _getAttendanceOnDate(dayDate);
              final isAbsent = att?.isAbsent == true;
              final isLate = att?.isLate == true;
              final isPresent = (att?.isPresent == true || att?.isHalfDay == true) && !isLate;

              // Attendance Color
              Color? attendanceColor;
              if (isAbsent) {
                attendanceColor = const Color(0xFFEF4444); // Red
              } else if (isLate) {
                attendanceColor = const Color(0xFFF97316); // Amber/Orange
              } else if (isPresent) {
                attendanceColor = const Color(0xFF1B5E4B); // Green
              }

              // Special Day Color
              Color? specialDayColor;
              if (hasBirthday) {
                specialDayColor = const Color(0xFFF59E0B); // Gold
              } else if (isEvent) {
                specialDayColor = const Color(0xFF7C3AED); // Violet
              } else if (isHoliday) {
                specialDayColor = const Color(0xFF1E293B); // Dark Slate
              }

              final bool isDualColor = attendanceColor != null && specialDayColor != null;
              final bool isSunday = dayDate.weekday == DateTime.sunday;

              BoxDecoration cellDecoration;
              Color textColor = CeladonColors.textPrimary;

              if (isDualColor) {
                // Dual Color: Split diagonal half-and-half gradient between attendance status and event/birthday/holiday
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
                // Pure Attendance Color (Absent Red, Late Orange, Present Green)
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
              } else if (isSunday) {
                // Weekly off / Sunday
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
                // Regular Working Day
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
                        else if (isLate)
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

          // Calendar Color Legend matching Company styling
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: [
              _buildLegendDot(const Color(0xFF1B5E4B), 'Present'),
              _buildLegendDot(const Color(0xFFF97316), 'Late'),
              _buildLegendDot(const Color(0xFFEF4444), 'Absent'),
              _buildLegendDot(const Color(0xFF7C3AED), 'Event ★'),
              _buildLegendDot(const Color(0xFF1E293B), 'Holiday'),
              _buildLegendDot(const Color(0xFFF59E0B), 'Birthday 🎂'),
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

    final now = DateTime.now();
    final isToday = _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;

    final isAbsent = att?.isAbsent == true;
    final isLate = att?.isLate == true;
    final isPresent = (att?.isPresent == true || att?.isHalfDay == true) && !isLate;

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
                        if (isAbsent)
                          _buildStatusChip('ABSENT', const Color(0xFFEF4444), Colors.white),
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
          if (att != null) ...[
            _buildAttendanceDetailItem(att),
            const SizedBox(height: 12),
          ] else if (!isToday && _selectedDate.isBefore(now) && _selectedDate.weekday != DateTime.sunday) ...[
            _buildInfoCard(
              icon: Icons.info_outline_rounded,
              color: const Color(0xFF94A3B8),
              title: 'No Attendance Recorded',
              subtitle: 'No punch-in or check-in was recorded on this past date.',
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

          // 5. Leave Request Card
          if (leaves.isNotEmpty) ...[
            ...leaves.map((l) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildDetailCard(
                    icon: Icons.flight_takeoff_rounded,
                    header: 'Leave Request (${l.status.toUpperCase()})',
                    headerColor: l.isApproved
                        ? const Color(0xFF059669)
                        : (l.isPending ? const Color(0xFFD97706) : const Color(0xFFDC4C4C)),
                    title: '${l.type.toUpperCase()} LEAVE',
                    subtitle: l.reason?.isNotEmpty == true ? l.reason! : 'Applied leave request',
                    tag: '${l.startDate} to ${l.endDate}',
                  ),
                )),
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
              Row(
                children: [
                  Icon(
                    att.isAbsent
                        ? Icons.cancel_outlined
                        : (att.isLate ? Icons.alarm_on_rounded : Icons.check_circle_outline_rounded),
                    color: statusColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    att.isAbsent
                        ? 'Absent on Duty'
                        : (att.isLate ? 'Late Arrival Recorded' : 'Present • On Duty'),
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
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
                      Text(
                        header,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: headerColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (tag.isNotEmpty)
                        Text(
                          tag,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: headerColor.withValues(alpha: 0.8),
                          ),
                        ),
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
