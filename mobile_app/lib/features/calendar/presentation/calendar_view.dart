import 'package:flutter/material.dart';
import '../../attendance/data/attendance_model.dart';
import '../../attendance/data/attendance_service.dart';
import '../../auth/data/user_model.dart';
import '../../dashboard/data/dashboard_service.dart';
import '../../dashboard/data/leave_model.dart';
import '../../tasks/data/task_model.dart';
import '../data/calendar_event_model.dart';
import '../data/calendar_service.dart';
import '../data/leave_service.dart';

/// Screen 5: Comprehensive Calendar, Leaves & Holidays Module
///
/// Features:
/// - 100% Dynamic MongoDB Multi-Collection Sync (Holidays, Attendance, Tasks, Leaves)
/// - Top Navigation Toggle: [Calendar], [Leaves], [Holidays]
/// - Month, Week, and Agenda views with date picker
/// - Apply for Leave dialog for employees (Casual, Sick, Earned, Unpaid)
/// - Leave approval and rejection actions for Company Admins and Super Admin
/// - Company Holiday Management: View, add, and delete official holidays
/// - Modern Celadon executive office theme matching ReGen design system
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

  // 0: Calendar, 1: Leaves, 2: Holidays
  int _selectedModuleTab = 0;

  // For Calendar Tab: 0: Month, 1: Week, 2: Agenda
  int _selectedCalendarViewIndex = 0;

  late DateTime _selectedDate;
  late DateTime _currentMonth;

  bool _isLoading = true;
  String? _errorMessage;

  List<CalendarEventModel> _events = [];
  List<LeaveModel> _leaves = [];
  List<CalendarEventModel> _holidays = [];

  bool get _isManager =>
      widget.user?.isSuperAdmin == true ||
      widget.user?.isCompanyAdmin == true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _currentMonth = DateTime(now.year, now.month, 1);
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
        _isManager
            ? _leaveService.getAllLeaves()
            : _leaveService.getUserLeaves(user?.userId.isNotEmpty == true ? user!.userId : (user?.id ?? '')),
      ]);

      if (!mounted) return;

      final holidays = results[0] as List<CalendarEventModel>;
      final attendance = results[1] as List<AttendanceModel>;
      final tasks = results[2] as List<TaskModel>;
      final leaves = results[3] as List<LeaveModel>;

      final List<CalendarEventModel> dynamicEvents = [];

      // 1. Live Public Holidays
      for (final h in holidays) {
        dynamicEvents.add(h.copyWith(
          icon: Icons.celebration_outlined,
          color: const Color(0xFFD97706),
          bg: const Color(0xFFFEF3C7),
        ));
      }

      // 2. Live Attendance Work Sessions
      for (final att in attendance) {
        DateTime? dt;
        if (att.checkIn != null && att.checkIn!.isNotEmpty) {
          dt = DateTime.tryParse(att.checkIn!)?.toLocal();
        }
        dt ??= DateTime.tryParse(att.date)?.toLocal();
        if (dt != null) {
          final statusUpper = att.status.toUpperCase();
          final inTime = _formatTimeStr(att.checkIn);
          final outTime = _formatTimeStr(att.checkOut);
          final timeStr = 'In: $inTime • Out: $outTime';

          dynamicEvents.add(CalendarEventModel(
            id: att.id.isNotEmpty ? att.id : 'att_${att.date}',
            title: 'Work Session ($statusUpper)',
            dateTime: dt,
            time: timeStr,
            category: 'Attendance',
            description: 'Logged Attendance: $statusUpper (${(att.workMode ?? 'OFFICE').toUpperCase()})',
            icon: Icons.fingerprint_rounded,
            color: const Color(0xFF1B5E3F),
            bg: const Color(0xFFE8F5ED),
          ));
        }
      }

      // 3. Live Tasks with Due Dates
      for (final t in tasks) {
        if (t.dueDate != null && t.dueDate!.isNotEmpty) {
          final dt = DateTime.tryParse(t.dueDate!)?.toLocal();
          if (dt != null) {
            dynamicEvents.add(CalendarEventModel(
              id: t.id,
              title: t.title,
              dateTime: dt,
              time: 'Due: ${t.dueDate!.split('T').first}',
              category: 'Task',
              description: t.description ?? 'Assigned Task (${t.displayPriority})',
              icon: Icons.assignment_outlined,
              color: const Color(0xFF7C3AED),
              bg: const Color(0xFFF3E8FF),
            ));
          }
        }
      }

      // 4. Live Leaves
      for (final l in leaves) {
        final dt = DateTime.tryParse(l.startDate)?.toLocal();
        if (dt != null) {
          dynamicEvents.add(CalendarEventModel(
            id: l.id,
            title: '${l.type.toUpperCase()} Leave (${l.status.toUpperCase()})',
            dateTime: dt,
            time: '${l.startDate} to ${l.endDate}',
            category: 'Leave',
            description: l.reason?.isNotEmpty == true ? l.reason! : 'Leave Request',
            icon: Icons.beach_access_outlined,
            color: l.isApproved ? const Color(0xFF059669) : (l.isPending ? const Color(0xFFD97706) : const Color(0xFFDC2626)),
            bg: l.isApproved ? const Color(0xFFDEF7EC) : (l.isPending ? const Color(0xFFFEF3C7) : const Color(0xFFFEE2E2)),
          ));
        }
      }

      setState(() {
        _events = dynamicEvents;
        _holidays = holidays;
        _leaves = leaves;
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

  List<CalendarEventModel> _getEventsForDate(DateTime date) {
    return _events.where((e) =>
      e.dateTime.year == date.year &&
      e.dateTime.month == date.month &&
      e.dateTime.day == date.day
    ).toList();
  }

  bool _hasEventsOnDate(DateTime date) {
    return _getEventsForDate(date).isNotEmpty;
  }

  Future<void> _handleUpdateLeave(String id, String status) async {
    try {
      final updated = await _leaveService.updateLeaveStatus(id: id, status: status);
      if (mounted) {
        setState(() {
          final idx = _leaves.indexWhere((l) => l.id == id);
          if (idx != -1) _leaves[idx] = updated;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: status == 'approved' ? const Color(0xFF1B5E3F) : const Color(0xFFDC2626),
            content: Text('Leave request marked as ${status.toUpperCase()}'),
          ),
        );
        _loadAllBackendData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _handleDeleteHoliday(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Holiday', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('Are you sure you want to remove this official holiday?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _calendarService.deleteEvent(
        user: widget.user ?? const UserModel(id: '', userId: '', username: '', name: '', role: 'staff', token: ''),
        eventId: id,
      );
      if (mounted) {
        setState(() => _holidays.removeWhere((h) => h.id == id));
        _loadAllBackendData();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    const primaryGreen = Color(0xFF1B5E3F);

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF8),
      floatingActionButton: FloatingActionButton(
        heroTag: 'calendar_fab_main',
        onPressed: _showActionMenu,
        backgroundColor: primaryGreen,
        elevation: 4,
        shape: const CircleBorder(),
        tooltip: 'Quick Actions',
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadAllBackendData,
          color: primaryGreen,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Workspace Header with Hamburger Menu
                _buildWorkspaceHeader(primaryGreen),
                const SizedBox(height: 12),

                // 2. Main Module Toggle: [Calendar] [Leaves] [Holidays]
                _buildMainModuleToggle(primaryGreen),
                const SizedBox(height: 14),

                if (_selectedModuleTab == 0)
                  _buildCalendarSection(primaryGreen)
                else if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator(color: primaryGreen)),
                  )
                else if (_errorMessage != null)
                  _buildErrorState(primaryGreen)
                else if (_selectedModuleTab == 1)
                  _buildLeavesSection(primaryGreen)
                else
                  _buildHolidaysSection(primaryGreen),

                const SizedBox(height: 90),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWorkspaceHeader(Color primaryGreen) {
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
                  color: primaryGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.menu_rounded, color: Color(0xFF1B5E3F), size: 22),
                  tooltip: 'Menu',
                  onPressed: widget.onOpenDrawer,
                ),
              )
            else if (widget.onBack != null)
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF1B5E3F)),
                onPressed: widget.onBack,
              ),

            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'WORKSPACE',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: Color(0xFF718096),
                  ),
                ),
                Text(
                  'Calendar & Leaves',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A202C),
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ],
        ),

        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Color(0xFF1B5E3F), size: 22),
          tooltip: 'Refresh',
          onPressed: _loadAllBackendData,
        ),
      ],
    );
  }

  Widget _buildMainModuleToggle(Color primaryGreen) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F2EC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _buildMainModuleTabItem('Calendar', 0, Icons.calendar_month_rounded, primaryGreen),
          _buildMainModuleTabItem('Leaves (${_leaves.length})', 1, Icons.beach_access_rounded, primaryGreen),
          _buildMainModuleTabItem('Holidays (${_holidays.length})', 2, Icons.celebration_rounded, primaryGreen),
        ],
      ),
    );
  }

  Widget _buildMainModuleTabItem(String label, int index, IconData icon, Color primaryGreen) {
    final isSelected = _selectedModuleTab == index;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedModuleTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? const [BoxShadow(color: Color(0x10000000), blurRadius: 4, offset: Offset(0, 1))]
                : null,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: isSelected ? primaryGreen : const Color(0xFF718096)),
              const SizedBox(width: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? primaryGreen : const Color(0xFF718096),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// CALENDAR SUB-SECTION (Month, Week, Agenda)
  Widget _buildCalendarSection(Color primaryGreen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Sub-view Toggle: [Month] [Week] [Agenda]
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              _buildSubViewItem('Month', 0, primaryGreen),
              _buildSubViewItem('Week', 1, primaryGreen),
              _buildSubViewItem('Agenda', 2, primaryGreen),
            ],
          ),
        ),
        const SizedBox(height: 14),

        if (_isLoading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator(color: primaryGreen)),
          )
        else if (_errorMessage != null)
          _buildErrorState(primaryGreen)
        else if (_selectedCalendarViewIndex == 0)
          _buildMonthView(primaryGreen)
        else if (_selectedCalendarViewIndex == 1)
          _buildWeekView(primaryGreen)
        else
          _buildAgendaView(primaryGreen),
      ],
    );
  }

  Widget _buildSubViewItem(String label, int index, Color primaryGreen) {
    final isSelected = _selectedCalendarViewIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedCalendarViewIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? primaryGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? Colors.white : const Color(0xFF64748B),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMonthView(Color primaryGreen) {
    final eventsForSelected = _getEventsForDate(_selectedDate);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Month Navigation Card
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2))],
          ),
          child: Column(
            children: [
              // Month Title & Arrows
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, color: Color(0xFF1B5E3F)),
                      onPressed: () {
                        setState(() {
                          _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
                        });
                      },
                    ),
                    Text(
                      '${_getMonthName(_currentMonth.month)} ${_currentMonth.year}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1B5E3F)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, color: Color(0xFF1B5E3F)),
                      onPressed: () {
                        setState(() {
                          _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
                        });
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFEDF2F7)),

              // Day of week abbreviations
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: const [
                    Text('Sun', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8))),
                    Text('Mon', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8))),
                    Text('Tue', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8))),
                    Text('Wed', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8))),
                    Text('Thu', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8))),
                    Text('Fri', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8))),
                    Text('Sat', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8))),
                  ],
                ),
              ),

              // Calendar Grid
              _buildMonthGrid(primaryGreen),
              const SizedBox(height: 10),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Selected Date Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "${_getDayOfWeekName(_selectedDate.weekday)}, ${_selectedDate.day} ${_getMonthName(_selectedDate.month).substring(0, 3)}".toUpperCase(),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: Color(0xFF1B5E3F)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5ED),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${eventsForSelected.length} event(s)',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF1B5E3F)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Events list for selected date
        if (eventsForSelected.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            alignment: Alignment.center,
            child: const Text('No activities scheduled for this date', style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
          )
        else
          ...eventsForSelected.map((e) => _buildEventCard(e)),
      ],
    );
  }

  Widget _buildMonthGrid(Color primaryGreen) {
    final firstDayOfMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    final startWeekday = firstDayOfMonth.weekday % 7; // Sunday = 0

    final totalCells = ((startWeekday + daysInMonth) / 7).ceil() * 7;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 1.1,
      ),
      itemCount: totalCells,
      itemBuilder: (context, idx) {
        final dayOffset = idx - startWeekday + 1;
        if (dayOffset < 1 || dayOffset > daysInMonth) {
          return const SizedBox.shrink();
        }

        final cellDate = DateTime(_currentMonth.year, _currentMonth.month, dayOffset);
        final isSelected = cellDate.year == _selectedDate.year &&
            cellDate.month == _selectedDate.month &&
            cellDate.day == _selectedDate.day;
        final isToday = cellDate.year == DateTime.now().year &&
            cellDate.month == DateTime.now().month &&
            cellDate.day == DateTime.now().day;
        final hasEvents = _hasEventsOnDate(cellDate);

        return GestureDetector(
          onTap: () => setState(() => _selectedDate = cellDate),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? primaryGreen : (isToday ? const Color(0xFFE8F5ED) : Colors.transparent),
              shape: BoxShape.circle,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  dayOffset.toString(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected || isToday ? FontWeight.w800 : FontWeight.w500,
                    color: isSelected ? Colors.white : (isToday ? primaryGreen : const Color(0xFF1A202C)),
                  ),
                ),
                if (hasEvents) ...[
                  const SizedBox(height: 2),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white : const Color(0xFFD97706),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWeekView(Color primaryGreen) {
    // Show 7 days starting from current week
    final startOfWeek = _selectedDate.subtract(Duration(days: _selectedDate.weekday % 7));
    final weekDays = List.generate(7, (i) => startOfWeek.add(Duration(days: i)));

    return Column(
      children: weekDays.map((date) {
        final evts = _getEventsForDate(date);
        final isSelected = date.day == _selectedDate.day && date.month == _selectedDate.month;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isSelected ? primaryGreen : const Color(0xFFE2E8F0), width: isSelected ? 1.6 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "${_getDayOfWeekName(date.weekday)}, ${date.day} ${_getMonthName(date.month)}",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: isSelected ? primaryGreen : const Color(0xFF1A202C),
                    ),
                  ),
                  Text('${evts.length} events', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                ],
              ),
              if (evts.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...evts.map((e) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: e.color, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(e.title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                      Text(e.time, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                    ],
                  ),
                )),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAgendaView(Color primaryGreen) {
    if (_events.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No agenda items')));
    }

    // Sort by date ascending
    final sorted = List<CalendarEventModel>.from(_events)..sort((a, b) => a.dateTime.compareTo(b.dateTime));

    return Column(
      children: sorted.map((e) => _buildEventCard(e)).toList(),
    );
  }

  Widget _buildEventCard(CalendarEventModel event) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [BoxShadow(color: Color(0x04000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: event.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(event.icon, color: event.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Color(0xFF1A202C)),
                ),
                const SizedBox(height: 3),
                Text(
                  event.time,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                ),
                if (event.description != null && event.description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    event.description!,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: event.bg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              event.category,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: event.color),
            ),
          ),
        ],
      ),
    );
  }

  /// LEAVES SUB-SECTION
  Widget _buildLeavesSection(Color primaryGreen) {
    final pendingCount = _leaves.where((l) => l.isPending).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Leave Action Banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Leave Management', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    _isManager ? '$pendingCount pending approval' : 'Submit or track leave requests',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _showApplyLeaveDialog,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Apply Leave'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Leaves List
        if (_leaves.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 40),
            alignment: Alignment.center,
            child: const Text('No leave records found', style: TextStyle(color: Color(0xFF94A3B8))),
          )
        else
          ..._leaves.map((l) => _buildLeaveCard(l, primaryGreen)),
      ],
    );
  }

  Widget _buildLeaveCard(LeaveModel leave, Color primaryGreen) {
    Color statusColor = const Color(0xFFD97706);
    Color statusBg = const Color(0xFFFEF3C7);

    if (leave.isApproved) {
      statusColor = const Color(0xFF15803D);
      statusBg = const Color(0xFFDEF7EC);
    } else if (leave.isRejected) {
      statusColor = const Color(0xFFDC2626);
      statusBg = const Color(0xFFFEE2E2);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [BoxShadow(color: Color(0x05000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${leave.type.toUpperCase()} LEAVE',
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Color(0xFF1A202C)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  leave.status.toUpperCase(),
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.date_range_rounded, size: 14, color: Color(0xFF64748B)),
              const SizedBox(width: 6),
              Text(
                '${leave.startDate} to ${leave.endDate}',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF4A5568)),
              ),
            ],
          ),
          if (leave.reason != null && leave.reason!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Reason: ${leave.reason}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],

          // If Manager and Leave is pending -> show Approve and Reject buttons!
          if (_isManager && leave.isPending) ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _handleUpdateLeave(leave.id, 'rejected'),
                  icon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFFDC2626)),
                  label: const Text('Reject', style: TextStyle(color: Color(0xFFDC2626), fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFFCA5A5)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _handleUpdateLeave(leave.id, 'approved'),
                  icon: const Icon(Icons.check_rounded, size: 14),
                  label: const Text('Approve', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// HOLIDAYS SUB-SECTION
  Widget _buildHolidaysSection(Color primaryGreen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Company Holidays', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('${_holidays.length} observed holidays', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                ],
              ),
              if (_isManager)
                ElevatedButton.icon(
                  onPressed: _showAddHolidayDialog,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Holiday'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (_holidays.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 40),
            alignment: Alignment.center,
            child: const Text('No holidays configured', style: TextStyle(color: Color(0xFF94A3B8))),
          )
        else
          ..._holidays.map((h) => _buildHolidayCard(h, primaryGreen)),
      ],
    );
  }

  Widget _buildHolidayCard(CalendarEventModel holiday, Color primaryGreen) {
    final dateStr = "${holiday.dateTime.year}-${holiday.dateTime.month.toString().padLeft(2, '0')}-${holiday.dateTime.day.toString().padLeft(2, '0')}";

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [BoxShadow(color: Color(0x04000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.celebration_outlined, color: Color(0xFFD97706), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  holiday.title,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Color(0xFF1A202C)),
                ),
                const SizedBox(height: 2),
                Text(
                  dateStr,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFD97706)),
                ),
              ],
            ),
          ),
          if (_isManager)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626), size: 20),
              tooltip: 'Delete Holiday',
              onPressed: () => _handleDeleteHoliday(holiday.id),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorState(Color primaryGreen) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.red, size: 36),
            const SizedBox(height: 12),
            Text(_errorMessage ?? 'Failed to load calendar data', textAlign: TextAlign.center),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: _loadAllBackendData,
              style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, foregroundColor: Colors.white),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  /// Floating Action Menu
  void _showActionMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Quick Actions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFFDEF7EC), child: Icon(Icons.beach_access, color: Color(0xFF1B5E3F))),
              title: const Text('Apply for Leave', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Submit casual, sick, or earned leave request'),
              onTap: () {
                Navigator.pop(ctx);
                _showApplyLeaveDialog();
              },
            ),
            if (_isManager)
              ListTile(
                leading: const CircleAvatar(backgroundColor: Color(0xFFFEF3C7), child: Icon(Icons.celebration, color: Color(0xFFD97706))),
                title: const Text('Add Company Holiday', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Add an official paid holiday to platform schedule'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddHolidayDialog();
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Apply Leave Dialog
  void _showApplyLeaveDialog() {
    String selectedType = 'casual';
    DateTime startDate = DateTime.now().add(const Duration(days: 1));
    DateTime endDate = DateTime.now().add(const Duration(days: 2));
    final reasonCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => Padding(
          padding: EdgeInsets.only(
            top: 24,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Apply for Leave', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1B5E3F))),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedType,
                decoration: InputDecoration(
                  labelText: 'Leave Type',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: const [
                  DropdownMenuItem(value: 'casual', child: Text('Casual Leave')),
                  DropdownMenuItem(value: 'sick', child: Text('Sick Leave')),
                  DropdownMenuItem(value: 'earned', child: Text('Earned Leave')),
                  DropdownMenuItem(value: 'unpaid', child: Text('Unpaid Leave')),
                ],
                onChanged: (v) => setDlgState(() => selectedType = v ?? 'casual'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.date_range, size: 16),
                      label: Text("${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}", style: const TextStyle(fontSize: 12)),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: startDate,
                          firstDate: DateTime.now().subtract(const Duration(days: 7)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) setDlgState(() => startDate = picked);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.date_range, size: 16),
                      label: Text("${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}", style: const TextStyle(fontSize: 12)),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: endDate,
                          firstDate: startDate,
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) setDlgState(() => endDate = picked);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Reason for Leave',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  final sStr = "${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}";
                  final eStr = "${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}";

                  final scaffoldMessenger = ScaffoldMessenger.of(context);
                  Navigator.pop(ctx);
                  try {
                    await _leaveService.applyLeave(
                      type: selectedType,
                      startDate: sStr,
                      endDate: eStr,
                      reason: reasonCtrl.text.trim(),
                      userId: widget.user?.userId.isNotEmpty == true ? widget.user!.userId : widget.user?.id,
                    );
                    if (mounted) {
                      scaffoldMessenger.showSnackBar(
                        const SnackBar(backgroundColor: Color(0xFF1B5E3F), content: Text('Leave request submitted successfully!')),
                      );
                      _loadAllBackendData();
                    }
                  } catch (e) {
                    if (mounted) {
                      scaffoldMessenger.showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text('Error: $e')));
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B5E3F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Submit Leave Request'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Add Holiday Dialog
  void _showAddHolidayDialog() {
    final nameCtrl = TextEditingController();
    DateTime holidayDate = DateTime.now().add(const Duration(days: 7));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Add Company Holiday', style: TextStyle(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Holiday Name *',
                  hintText: 'e.g. Diwali Festival',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today_rounded, size: 16),
                label: Text("${holidayDate.year}-${holidayDate.month.toString().padLeft(2, '0')}-${holidayDate.day.toString().padLeft(2, '0')}"),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: holidayDate,
                    firstDate: DateTime(DateTime.now().year - 1),
                    lastDate: DateTime(DateTime.now().year + 2),
                  );
                  if (picked != null) setDlgState(() => holidayDate = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final holidayTitle = nameCtrl.text.trim();

                Navigator.pop(ctx);
                try {
                  await _calendarService.createEvent(
                    user: widget.user ?? const UserModel(id: '', userId: '', username: '', name: '', role: 'staff', token: ''),
                    event: CalendarEventModel(
                      id: 'hol-${DateTime.now().millisecondsSinceEpoch}',
                      title: holidayTitle,
                      dateTime: holidayDate,
                      time: 'All Day',
                      category: 'Holiday',
                    ),
                  );
                  if (mounted) {
                    scaffoldMessenger.showSnackBar(
                      SnackBar(backgroundColor: const Color(0xFF1B5E3F), content: Text('Holiday "$holidayTitle" added!')),
                    );
                    _loadAllBackendData();
                  }
                } catch (_) {}
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B5E3F), foregroundColor: Colors.white),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  String _getMonthName(int month) {
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return months[(month - 1) % 12];
  }

  String _getDayOfWeekName(int weekday) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[(weekday - 1) % 7];
  }
}
