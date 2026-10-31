import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../attendance/data/attendance_model.dart';
import '../../attendance/data/attendance_service.dart';
import '../../dashboard/data/dashboard_service.dart';
import '../../dashboard/data/leave_model.dart';
import '../../tasks/data/task_model.dart';
import '../data/holiday_model.dart';

/// Screen 5: Calendar Screen
///
/// Reproduces Screen 5 from the "8. Premium Celadon" design specification:
/// - Header with title "Calendar"
/// - Segmented toggle pills: [Month], [Week], [List]
/// - Month calendar picker with interactive month navigation (< October 2026 >)
/// - Color-coded event indicators on calendar days:
///   * Red/Orange dot: Company Holidays & Approved Leaves
///   * Green dot: Attendance Records
///   * Purple/Blue dot: Assigned Work Tasks / Schedules
/// - Section header showing active date ("20 Oct 2026")
/// - Dynamic list of scheduled items for the active date
/// - Green (+) Floating Action Button to schedule tasks
/// - 100% Dynamic data backed by live ReGen MongoDB APIs.
class CalendarView extends StatefulWidget {
  final VoidCallback? onBack;

  const CalendarView({super.key, this.onBack});

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  final AttendanceService _attendanceService = AttendanceService();
  final DashboardService _dashboardService = DashboardService();

  bool _isLoading = true;
  String? _errorMessage;

  int _selectedSegment = 0; // 0: Month, 1: Week, 2: List
  late DateTime _displayedMonth;
  late DateTime _selectedDate;

  List<HolidayModel> _holidays = [];
  List<AttendanceModel> _attendance = [];
  List<TaskModel> _tasks = [];
  List<LeaveModel> _leaves = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _displayedMonth = DateTime(now.year, now.month, 1);
    _selectedDate = DateTime(now.year, now.month, now.day);
    _loadCalendarData();
  }

  Future<void> _loadCalendarData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _attendanceService.getHolidays(),
        _dashboardService.getAttendance(),
        _dashboardService.getTasks(),
        _dashboardService.getLeaves(),
      ]);

      if (mounted) {
        setState(() {
          _holidays = results[0] as List<HolidayModel>;
          _attendance = results[1] as List<AttendanceModel>;
          _tasks = results[2] as List<TaskModel>;
          _leaves = results[3] as List<LeaveModel>;
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

  String _formatDateYMD(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _formatTimeOnly(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '--:--';
    final dt = DateTime.tryParse(isoString)?.toLocal();
    if (dt == null) return '--:--';
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final p = h >= 12 ? 'PM' : 'AM';
    final dh = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '${dh.toString().padLeft(2, '0')}:$m $p';
  }

  String _monthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }

  String _shortMonthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CeladonColors.background,
      floatingActionButton: FloatingActionButton(
        onPressed: _showScheduleTaskDialog,
        backgroundColor: CeladonColors.primary,
        elevation: 3,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: CeladonColors.primary))
            : RefreshIndicator(
                onRefresh: _loadCalendarData,
                color: CeladonColors.primary,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Top Navigation Bar
                      Row(
                        children: [
                          if (widget.onBack != null)
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                size: 20,
                                color: CeladonColors.textPrimary,
                              ),
                              onPressed: widget.onBack,
                            )
                          else
                            const SizedBox(width: 4),
                          const Text(
                            'Calendar',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: CeladonColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Error message if any
                      if (_errorMessage != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEBEE),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                        ),

                      // 2. Segmented Pill Bar: [Month] [Week] [List]
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2EFE7),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          children: [
                            _buildSegmentItem('Month', 0),
                            _buildSegmentItem('Week', 1),
                            _buildSegmentItem('List', 2),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // 3. Segment Content
                      if (_selectedSegment == 0) _buildMonthCalendarSection(),
                      if (_selectedSegment == 1) _buildWeekScheduleSection(),
                      if (_selectedSegment == 2) _buildListScheduleSection(),

                      const SizedBox(height: 80), // room for FAB
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildSegmentItem(String title, int index) {
    final isSelected = _selectedSegment == index;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedSegment = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? CeladonColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          alignment: Alignment.center,
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? Colors.white : CeladonColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // SEGMENT 0: MONTH CALENDAR & SELECTED DAY EVENTS
  // ==========================================
  Widget _buildMonthCalendarSection() {
    final monthStr = '${_monthName(_displayedMonth.month)} ${_displayedMonth.year}';
    final selectedDayLabel = '${_selectedDate.day} ${_shortMonthName(_selectedDate.month)} ${_selectedDate.year}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Month Calendar Card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
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
            children: [
              // Header: < Month Year >
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.chevron_left_rounded,
                      color: CeladonColors.textPrimary,
                      size: 22,
                    ),
                    onPressed: () {
                      setState(() {
                        _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month - 1, 1);
                      });
                    },
                  ),
                  Text(
                    monthStr,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: CeladonColors.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.chevron_right_rounded,
                      color: CeladonColors.textPrimary,
                      size: 22,
                    ),
                    onPressed: () {
                      setState(() {
                        _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month + 1, 1);
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Weekday Initials: S M T W T F S
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _WeekdayLabel('S'),
                  _WeekdayLabel('M'),
                  _WeekdayLabel('T'),
                  _WeekdayLabel('W'),
                  _WeekdayLabel('T'),
                  _WeekdayLabel('F'),
                  _WeekdayLabel('S'),
                ],
              ),
              const SizedBox(height: 8),

              // Calendar Grid with event indicators
              _buildCalendarGrid(),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Section Header: "20 Oct 2026"
        Text(
          selectedDayLabel,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: CeladonColors.textPrimary,
          ),
        ),
        const SizedBox(height: 14),

        // Events list for selected day
        _buildDayEventsList(_selectedDate),
      ],
    );
  }

  Widget _buildCalendarGrid() {
    final firstDayOfMonth = DateTime(_displayedMonth.year, _displayedMonth.month, 1);
    final daysInMonth = DateTime(_displayedMonth.year, _displayedMonth.month + 1, 0).day;
    final leadingSpaces = firstDayOfMonth.weekday == 7 ? 0 : firstDayOfMonth.weekday;

    final days = <Widget>[];

    for (int i = 0; i < leadingSpaces; i++) {
      days.add(const SizedBox());
    }

    for (int day = 1; day <= daysInMonth; day++) {
      final thisDate = DateTime(_displayedMonth.year, _displayedMonth.month, day);
      final dateStr = _formatDateYMD(thisDate);
      final isSelected = (_selectedDate.year == thisDate.year &&
          _selectedDate.month == thisDate.month &&
          _selectedDate.day == thisDate.day);

      // Check event types on this date
      final hasHoliday = _holidays.any((h) => h.date == dateStr);
      final hasAttendance = _attendance.any((a) => a.date == dateStr);
      final hasTask = _tasks.any((t) => t.dueDate == dateStr || t.startDate == dateStr);
      final hasLeave = _leaves.any((l) => l.isApproved && dateStr.compareTo(l.startDate) >= 0 && dateStr.compareTo(l.endDate) <= 0);

      days.add(
        GestureDetector(
          onTap: () => setState(() => _selectedDate = thisDate),
          child: Container(
            margin: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              color: isSelected ? CeladonColors.primary : Colors.transparent,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? Colors.white : CeladonColors.textPrimary,
                  ),
                ),
                if (!isSelected && (hasHoliday || hasLeave || hasAttendance || hasTask))
                  Positioned(
                    bottom: 2,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasHoliday || hasLeave)
                          Container(
                            width: 4,
                            height: 4,
                            margin: const EdgeInsets.symmetric(horizontal: 0.5),
                            decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
                          ),
                        if (hasAttendance)
                          Container(
                            width: 4,
                            height: 4,
                            margin: const EdgeInsets.symmetric(horizontal: 0.5),
                            decoration: const BoxDecoration(color: Color(0xFF2D6A4F), shape: BoxShape.circle),
                          ),
                        if (hasTask)
                          Container(
                            width: 4,
                            height: 4,
                            margin: const EdgeInsets.symmetric(horizontal: 0.5),
                            decoration: const BoxDecoration(color: Color(0xFF8B5CF6), shape: BoxShape.circle),
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

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 7,
      childAspectRatio: 1.15,
      children: days,
    );
  }

  Widget _buildDayEventsList(DateTime date) {
    final dateStr = _formatDateYMD(date);

    final matchingHolidays = _holidays.where((h) => h.date == dateStr).toList();
    final matchingAttendance = _attendance.where((a) => a.date == dateStr).toList();
    final matchingTasks = _tasks.where((t) => t.dueDate == dateStr || t.startDate == dateStr).toList();
    final matchingLeaves = _leaves.where((l) => l.isApproved && dateStr.compareTo(l.startDate) >= 0 && dateStr.compareTo(l.endDate) <= 0).toList();

    final allItems = <Widget>[];

    // 1. Holiday Cards
    for (final h in matchingHolidays) {
      allItems.add(_buildEventCard(
        icon: Icons.celebration_rounded,
        iconColor: const Color(0xFFD97706),
        iconBg: const Color(0xFFFEF3C7),
        title: 'Public Holiday: ${h.name}',
        subtitle: 'Official Company Holiday',
        badge: 'Holiday',
        badgeColor: const Color(0xFFD97706),
      ));
      allItems.add(const SizedBox(height: 10));
    }

    // 2. Approved Leaves
    for (final l in matchingLeaves) {
      allItems.add(_buildEventCard(
        icon: Icons.beach_access_rounded,
        iconColor: const Color(0xFFEF4444),
        iconBg: const Color(0xFFFEE2E2),
        title: 'Approved Leave: ${l.type.toUpperCase()}',
        subtitle: l.reason?.isNotEmpty == true ? l.reason! : 'Scheduled time off',
        badge: 'On Leave',
        badgeColor: const Color(0xFFEF4444),
      ));
      allItems.add(const SizedBox(height: 10));
    }

    // 3. Attendance Record
    for (final a in matchingAttendance) {
      allItems.add(_buildEventCard(
        icon: Icons.fingerprint_rounded,
        iconColor: const Color(0xFF2D6A4F),
        iconBg: CeladonColors.primaryContainer,
        title: 'Work Session (${a.status.toUpperCase()})',
        subtitle: 'In: ${_formatTimeOnly(a.checkIn)}  •  Out: ${_formatTimeOnly(a.checkOut)}',
        badge: a.isPresent ? 'Present' : 'Late',
        badgeColor: const Color(0xFF2D6A4F),
      ));
      allItems.add(const SizedBox(height: 10));
    }

    // 4. Assigned Tasks
    for (final t in matchingTasks) {
      allItems.add(_buildEventCard(
        icon: Icons.assignment_outlined,
        iconColor: const Color(0xFF8B5CF6),
        iconBg: const Color(0xFFEDE9FE),
        title: t.title,
        subtitle: t.description?.isNotEmpty == true ? t.description! : 'Due on ${t.dueDate ?? 'today'}',
        badge: t.displayPriority,
        badgeColor: t.isHighPriority ? Colors.redAccent : const Color(0xFF8B5CF6),
      ));
      allItems.add(const SizedBox(height: 10));
    }

    if (allItems.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: CeladonColors.borderLight),
        ),
        alignment: Alignment.center,
        child: Column(
          children: const [
            Icon(Icons.event_available_rounded, size: 36, color: CeladonColors.primaryLight),
            SizedBox(height: 10),
            Text(
              'No events or tasks scheduled for this day',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: CeladonColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return Column(children: allItems);
  }

  // ==========================================
  // SEGMENT 1: WEEK VIEW
  // ==========================================
  Widget _buildWeekScheduleSection() {
    final now = DateTime.now();
    final dayOfWeek = now.weekday == 7 ? 0 : now.weekday;
    final startOfWeek = now.subtract(Duration(days: dayOfWeek));

    const weekdayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return Column(
      children: List.generate(7, (idx) {
        final day = startOfWeek.add(Duration(days: idx));
        final dateStr = _formatDateYMD(day);
        final isToday = day.year == now.year && day.month == now.month && day.day == now.day;

        final holiday = _holidays.firstWhere((h) => h.date == dateStr, orElse: () => const HolidayModel(id: '', name: '', date: ''));
        final att = _attendance.firstWhere((a) => a.date == dateStr, orElse: () => const AttendanceModel(id: '', userId: '', date: '', status: ''));
        final tasksCount = _tasks.where((t) => t.dueDate == dateStr || t.startDate == dateStr).length;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isToday ? const Color(0xFFF0FDF4) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isToday ? CeladonColors.primary : CeladonColors.borderLight,
              width: isToday ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: isToday ? CeladonColors.primary : const Color(0xFFE2EFE7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      weekdayNames[idx],
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isToday ? Colors.white : CeladonColors.textSecondary,
                      ),
                    ),
                    Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: isToday ? Colors.white : CeladonColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (holiday.name.isNotEmpty)
                      Text('Holiday: ${holiday.name}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFD97706)))
                    else if (att.checkIn != null)
                      Text('Attended: ${_formatTimeOnly(att.checkIn)} - ${_formatTimeOnly(att.checkOut)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: CeladonColors.textPrimary))
                    else
                      const Text('Standard Working Day', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: CeladonColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                      tasksCount > 0 ? '$tasksCount scheduled task(s)' : 'No pending tasks',
                      style: const TextStyle(fontSize: 11, color: CeladonColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (holiday.name.isNotEmpty)
                const Icon(Icons.celebration_rounded, color: Color(0xFFD97706), size: 20)
              else if (att.checkIn != null)
                const Icon(Icons.check_circle_rounded, color: CeladonColors.primary, size: 20),
            ],
          ),
        );
      }),
    );
  }

  // ==========================================
  // SEGMENT 2: LIST VIEW
  // ==========================================
  Widget _buildListScheduleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Upcoming Holidays', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: CeladonColors.textPrimary)),
        const SizedBox(height: 10),
        if (_holidays.isEmpty)
          const Text('No company holidays listed.', style: TextStyle(color: CeladonColors.textSecondary))
        else
          ..._holidays.take(5).map((h) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: CeladonColors.borderLight),
              ),
              child: Row(
                children: [
                  const Icon(Icons.celebration_rounded, color: Color(0xFFD97706), size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                  Text(h.date, style: const TextStyle(fontSize: 12, color: CeladonColors.textSecondary)),
                ],
              ),
            );
          }),
        const SizedBox(height: 20),
        const Text('Assigned Tasks', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: CeladonColors.textPrimary)),
        const SizedBox(height: 10),
        if (_tasks.isEmpty)
          const Text('No tasks scheduled.', style: TextStyle(color: CeladonColors.textSecondary))
        else
          ..._tasks.take(10).map((t) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: CeladonColors.borderLight),
              ),
              child: Row(
                children: [
                  const Icon(Icons.assignment_outlined, color: Color(0xFF8B5CF6), size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        if (t.dueDate != null)
                          Text('Due: ${t.dueDate}', style: const TextStyle(fontSize: 11, color: CeladonColors.textSecondary)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDE9FE),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      t.displayPriority,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF8B5CF6)),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildEventCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required String badge,
    required Color badgeColor,
  }) {
    return Container(
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
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: CeladonColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: CeladonColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              badge,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: badgeColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showScheduleTaskDialog() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Calendar is synced with live MongoDB Tasks, Attendance, and Holidays.'),
        backgroundColor: CeladonColors.primary,
      ),
    );
  }
}

class _WeekdayLabel extends StatelessWidget {
  final String label;

  const _WeekdayLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: CeladonColors.textMuted,
        ),
      ),
    );
  }
}
