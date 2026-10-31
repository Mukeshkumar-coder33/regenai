import 'package:flutter/material.dart';
import '../../auth/data/user_model.dart';
import '../data/calendar_event_model.dart';
import '../data/calendar_service.dart';

/// Screen 5: Calendar Screen (Matching UI Reference)
///
/// Implements the exact design from the reference image:
/// - "WORKSPACE" small uppercase label + bold "Calendar" title + subtitle
/// - Notification bell icon with active dot on the top right
/// - Pill segment tab buttons: [ Month ] [ Week ] [ Agenda ] with deep green highlight
/// - Calendar Card with dark green decorative wave header: `< October 2026 >`
/// - Month calendar grid with Sun..Sat weekday abbreviations, previous/next month days dimmed
/// - Selected date marked with large dark-emerald circular highlight and centered white text
/// - Event dots below dates with scheduled events
/// - "TUESDAY, OCT 20" day header with soft green count pill ("3 events")
/// - Rich event cards with rounded icon badges, time slots, category tags ("Meeting", "Discussion", "Review"), and more-options menu
/// - Green floating action button (+) for authorized users
/// - Full interactive support for Month, Week, and Agenda views with role-based permissions
class CalendarView extends StatefulWidget {
  final VoidCallback? onBack;
  final UserModel? user;

  const CalendarView({
    super.key,
    this.onBack,
    this.user,
  });

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  final CalendarService _calendarService = CalendarService();
  int _selectedViewIndex = 0; // 0: Month, 1: Week, 2: Agenda
  late DateTime _selectedDate;
  late DateTime _currentMonth;

  late List<CalendarEventModel> _events;

  @override
  void initState() {
    super.initState();
    // Default to Oct 20, 2026 to faithfully match visual reference
    _selectedDate = DateTime(2026, 10, 20);
    _currentMonth = DateTime(2026, 10, 1);
    _initRoleEvents();
    _loadBackendEvents();
  }

  void _initRoleEvents() {
    final user = widget.user;
    final isSuperAdmin = user?.isSuperAdmin ?? false;
    final isCompanyAdmin = user?.isCompanyAdmin ?? false;

    _events = [
      CalendarEventModel(
        id: 'evt_1',
        title: 'Team Meeting',
        dateTime: DateTime(2026, 10, 20, 10, 0),
        time: '10:00 AM ΓÇô 11:00 AM',
        category: 'Meeting',
        description: 'Weekly team sync and coordination',
        icon: Icons.groups_outlined,
        color: const Color(0xFF1B5E3F),
        bg: const Color(0xFFE8F5ED),
      ),
      CalendarEventModel(
        id: 'evt_2',
        title: 'Project Discussion',
        dateTime: DateTime(2026, 10, 20, 13, 0),
        time: '1:00 PM ΓÇô 2:00 PM',
        category: 'Discussion',
        description: 'Quarterly review and deliverables',
        icon: Icons.article_outlined,
        color: const Color(0xFF7C3AED),
        bg: const Color(0xFFF3E8FF),
      ),
      CalendarEventModel(
        id: 'evt_3',
        title: 'Design Review',
        dateTime: DateTime(2026, 10, 20, 15, 0),
        time: '3:00 PM ΓÇô 4:00 PM',
        category: 'Review',
        description: 'Mobile app glassmorphism UI audit',
        icon: Icons.palette_outlined,
        color: const Color(0xFFD97706),
        bg: const Color(0xFFFEF3C7),
      ),
      CalendarEventModel(
        id: 'evt_4',
        title: 'Sprint Planning',
        dateTime: DateTime(2026, 10, 6, 11, 0),
        time: '11:00 AM ΓÇô 12:30 PM',
        category: 'Meeting',
        description: 'Sprint backlog grooming',
        icon: Icons.speed_outlined,
        color: const Color(0xFF1B5E3F),
        bg: const Color(0xFFE8F5ED),
      ),
      CalendarEventModel(
        id: 'evt_5',
        title: 'Code Architecture Audit',
        dateTime: DateTime(2026, 10, 9, 14, 0),
        time: '2:00 PM ΓÇô 3:30 PM',
        category: 'Review',
        description: 'Flutter state management review',
        icon: Icons.code_rounded,
        color: const Color(0xFF0284C7),
        bg: const Color(0xFFE0F2FE),
      ),
      CalendarEventModel(
        id: 'evt_6',
        title: 'Department All-Hands',
        dateTime: DateTime(2026, 10, 13, 10, 30),
        time: '10:30 AM ΓÇô 12:00 PM',
        category: 'Meeting',
        description: 'Company-wide updates and policy reminders',
        icon: Icons.corporate_fare_rounded,
        color: const Color(0xFF1B5E3F),
        bg: const Color(0xFFE8F5ED),
      ),
      CalendarEventModel(
        id: 'evt_7',
        title: isSuperAdmin
            ? 'Tenant Infrastructure Maintenance'
            : (isCompanyAdmin ? 'Payroll & Shift Planning' : 'Product Demo'),
        dateTime: DateTime(2026, 10, 22, 16, 0),
        time: '4:00 PM ΓÇô 5:00 PM',
        category: isSuperAdmin ? 'Admin' : (isCompanyAdmin ? 'Operations' : 'Discussion'),
        description: 'Cross-functional alignment',
        icon: isSuperAdmin ? Icons.dns_outlined : Icons.event_note_outlined,
        color: const Color(0xFF059669),
        bg: const Color(0xFFD1FAE5),
      ),
    ];
  }

  Future<void> _loadBackendEvents() async {
    if (widget.user == null) return;
    try {
      final backendEvents = await _calendarService.fetchEvents(user: widget.user!);
      if (backendEvents.isNotEmpty && mounted) {
        setState(() {
          for (final be in backendEvents) {
            if (!_events.any((e) => e.title == be.title && e.dateTime.day == be.dateTime.day && e.dateTime.month == be.dateTime.month)) {
              _events.add(be.copyWith(
                icon: Icons.celebration_outlined,
                color: const Color(0xFFD97706),
                bg: const Color(0xFFFEF3C7),
              ));
            }
          }
        });
      }
    } catch (_) {}
  }

  bool get _canAddEvents {
    // Both Company Admin and Super Admin have event creation privileges; Employees can also request
    return true;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF8),
      floatingActionButton: _canAddEvents
          ? Container(
              margin: const EdgeInsets.only(bottom: 12, right: 6),
              child: FloatingActionButton(
                heroTag: 'calendar_fab_main',
                onPressed: _showAddEventDialog,
                backgroundColor: const Color(0xFF1B5E3F),
                elevation: 4,
                shape: const CircleBorder(),
                child: const Icon(Icons.add, color: Colors.white, size: 28),
              ),
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Workspace Header with Notification Bell
              _buildWorkspaceHeader(),
              const SizedBox(height: 18),

              // 2. View Toggle Pill Bar: [Month] [Week] [Agenda]
              _buildViewToggleBar(),
              const SizedBox(height: 18),

              // 3. View Switcher
              if (_selectedViewIndex == 0)
                _buildMonthView()
              else if (_selectedViewIndex == 1)
                _buildWeekView()
              else
                _buildAgendaView(),

              const SizedBox(height: 90),
            ],
          ),
        ),
      ),
    );
  }

  // Header matching visual reference: "WORKSPACE", bold "Calendar", subtitle, notification icon
  Widget _buildWorkspaceHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.onBack != null)
              GestureDetector(
                onTap: widget.onBack,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: Color(0xFF64748B)),
                      SizedBox(width: 4),
                      Text(
                        'BACK',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const Text(
              'WORKSPACE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: Color(0xFF718096),
              ),
            ),
            const SizedBox(height: 3),
            const Text(
              'Calendar',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                color: Color(0xFF1A202C),
              ),
            ),
            const SizedBox(height: 3),
            const Text(
              'Manage your schedules and stay productive',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF718096),
              ),
            ),
          ],
        ),

        // Notification Icon with Active Indicator
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF4EE),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFD4E7DC), width: 1),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(
                Icons.notifications_outlined,
                size: 22,
                color: Color(0xFF2D3748),
              ),
              Positioned(
                top: 10,
                right: 12,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Segment toggle pills: [ Month ] [ Week ] [ Agenda ]
  Widget _buildViewToggleBar() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F2EC),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          _buildToggleItem(title: 'Month', index: 0),
          _buildToggleItem(title: 'Week', index: 1),
          _buildToggleItem(title: 'Agenda', index: 2),
        ],
      ),
    );
  }

  Widget _buildToggleItem({required String title, required int index}) {
    final isSelected = _selectedViewIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedViewIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF10462C) : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              if (isSelected)
                BoxShadow(
                  color: const Color(0xFF10462C).withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              color: isSelected ? Colors.white : const Color(0xFF4A5568),
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // 1. MONTH VIEW
  // ==========================================
  Widget _buildMonthView() {
    final eventsForDay = _getEventsForDate(_selectedDate);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Calendar Grid Card
        _buildMonthCalendarCard(),
        const SizedBox(height: 22),

        // Selected Day Title + Event Count Badge
        _buildDateHeaderRow(
          title: _formatDayTitle(_selectedDate),
          count: eventsForDay.length,
        ),
        const SizedBox(height: 14),

        // Event Cards List
        if (eventsForDay.isEmpty)
          _buildEmptyEventsState('No events scheduled for this day')
        else
          ...eventsForDay.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildEventCard(e),
              )),
      ],
    );
  }

  Widget _buildMonthCalendarCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x081B5E3F),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            // Dark green top header with navigation and subtle organic curve
            Container(
              height: 58,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF0F3A2E),
                    Color(0xFF134E3C),
                    Color(0xFF0A2B22),
                  ],
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 24),
                    onPressed: () {
                      setState(() {
                        _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
                      });
                    },
                  ),
                  Text(
                    _formatMonthYear(_currentMonth),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 24),
                    onPressed: () {
                      setState(() {
                        _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
                      });
                    },
                  ),
                ],
              ),
            ),

            // Weekday Initial Row (Sun Mon Tue Wed Thu Fri Sat)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: const [
                  _WeekdayLabel('Sun'),
                  _WeekdayLabel('Mon'),
                  _WeekdayLabel('Tue'),
                  _WeekdayLabel('Wed'),
                  _WeekdayLabel('Thu'),
                  _WeekdayLabel('Fri'),
                  _WeekdayLabel('Sat'),
                ],
              ),
            ),

            // 7x5 Days Grid
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
              child: _buildDaysGrid(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDaysGrid() {
    final year = _currentMonth.year;
    final month = _currentMonth.month;

    final firstDayOfMonth = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final daysInPrevMonth = DateTime(year, month, 0).day;

    // weekday: Mon=1..Sun=7 -> Sunday index should be 0
    final startWeekday = firstDayOfMonth.weekday % 7;

    final totalGridCells = 35; // 5 weeks x 7 days
    final gridItems = <Widget>[];

    // Leading previous month days
    for (int i = startWeekday - 1; i >= 0; i--) {
      final prevDayNum = daysInPrevMonth - i;
      gridItems.add(_buildDimmedDayCell(prevDayNum));
    }

    // Current month days
    for (int day = 1; day <= daysInMonth; day++) {
      final cellDate = DateTime(year, month, day);
      final isSelected = cellDate.year == _selectedDate.year &&
          cellDate.month == _selectedDate.month &&
          cellDate.day == _selectedDate.day;
      final hasEvents = _hasEventsOnDate(cellDate);

      gridItems.add(
        GestureDetector(
          onTap: () {
            setState(() {
              _selectedDate = cellDate;
            });
          },
          child: Container(
            alignment: Alignment.center,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF1B8A5A) : Colors.transparent,
                shape: BoxShape.circle,
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: const Color(0xFF1B8A5A).withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$day',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected ? Colors.white : const Color(0xFF1A202C),
                    ),
                  ),
                  if (hasEvents)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : const Color(0xFF1B8A5A),
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Trailing next month days to complete 35 cells
    final remainingCells = totalGridCells - gridItems.length;
    for (int nextDay = 1; nextDay <= remainingCells; nextDay++) {
      gridItems.add(_buildDimmedDayCell(nextDay));
    }

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 7,
      mainAxisSpacing: 4,
      crossAxisSpacing: 2,
      childAspectRatio: 1.12,
      children: gridItems,
    );
  }

  Widget _buildDimmedDayCell(int dayNumber) {
    return Container(
      alignment: Alignment.center,
      child: Text(
        '$dayNumber',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: Color(0xFFA0AEC0),
        ),
      ),
    );
  }

  // ==========================================
  // 2. WEEK VIEW
  // ==========================================
  Widget _buildWeekView() {
    // Compute the 7 days of the selected week (Sunday to Saturday)
    final weekStart = _selectedDate.subtract(Duration(days: _selectedDate.weekday % 7));
    final weekDates = List.generate(7, (i) => weekStart.add(Duration(days: i)));
    final eventsForDay = _getEventsForDate(_selectedDate);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Week Bar Card with Navigation
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x081B5E3F),
                blurRadius: 14,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Week range title & prev/next buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, color: Color(0xFF1A202C)),
                    onPressed: () {
                      setState(() {
                        _selectedDate = _selectedDate.subtract(const Duration(days: 7));
                        _currentMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
                      });
                    },
                  ),
                  Text(
                    'Week of ${_formatMonthDay(weekDates.first)} ΓÇô ${_formatMonthDay(weekDates.last)}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A202C),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, color: Color(0xFF1A202C)),
                    onPressed: () {
                      setState(() {
                        _selectedDate = _selectedDate.add(const Duration(days: 7));
                        _currentMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 7 Day Selection Pills
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: weekDates.map((d) {
                  final isSelected = d.year == _selectedDate.year &&
                      d.month == _selectedDate.month &&
                      d.day == _selectedDate.day;
                  final hasEvents = _hasEventsOnDate(d);
                  const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
                  final dayName = dayNames[d.weekday % 7];

                  return GestureDetector(
                    onTap: () => setState(() => _selectedDate = d),
                    child: Container(
                      width: 44,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF1B8A5A) : const Color(0xFFF7FAF8),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? Colors.transparent : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            dayName,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? Colors.white70 : const Color(0xFF718096),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${d.day}',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: isSelected ? Colors.white : const Color(0xFF1A202C),
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (hasEvents)
                            Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.white : const Color(0xFF1B8A5A),
                                shape: BoxShape.circle,
                              ),
                            )
                          else
                            const SizedBox(height: 4),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),

        // Selected Day Title + Event Count
        _buildDateHeaderRow(
          title: _formatDayTitle(_selectedDate),
          count: eventsForDay.length,
        ),
        const SizedBox(height: 14),

        if (eventsForDay.isEmpty)
          _buildEmptyEventsState('No events scheduled for this day')
        else
          ...eventsForDay.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildEventCard(e),
              )),
      ],
    );
  }

  // ==========================================
  // 3. AGENDA VIEW
  // ==========================================
  Widget _buildAgendaView() {
    // Sort events chronologically
    final sortedEvents = List<CalendarEventModel>.from(_events)
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

    // Group events by date
    final Map<String, List<CalendarEventModel>> grouped = {};
    for (final e in sortedEvents) {
      final key = _formatDayTitle(e.dateTime);
      grouped.putIfAbsent(key, () => []).add(e);
    }

    if (grouped.isEmpty) {
      return _buildEmptyEventsState('No upcoming agenda items scheduled');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: grouped.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDateHeaderRow(
              title: entry.key,
              count: entry.value.length,
            ),
            const SizedBox(height: 12),
            ...entry.value.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildEventCard(e),
                )),
            const SizedBox(height: 16),
          ],
        );
      }).toList(),
    );
  }

  // Date Header Row with pill badge: "TUESDAY, OCT 20" + "3 events"
  Widget _buildDateHeaderRow({required String title, required int count}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: Color(0xFF1A202C),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFE2F3E9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count event${count == 1 ? '' : 's'}',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1B5E3F),
            ),
          ),
        ),
      ],
    );
  }

  // Event Card matching visual reference: left-colored accent stripe, icon badge, title, time, category pill, more icon
  Widget _buildEventCard(CalendarEventModel event) {
    final cardColor = event.color ?? const Color(0xFF1B5E3F);
    final cardBg = event.bg ?? const Color(0xFFE8F5ED);
    final iconData = event.icon ?? Icons.event_note_outlined;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Left Accent Colored Stripe
              Container(
                width: 5,
                color: cardColor,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Row(
                    children: [
                      // Circular / Rounded Icon Badge
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          iconData,
                          size: 24,
                          color: cardColor,
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Event Title, Time & Category
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              event.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1A202C),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(
                                  Icons.access_time_rounded,
                                  size: 14,
                                  color: Color(0xFF718096),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  event.time,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF718096),
                                  ),
                                ),
                                const SizedBox(width: 10),

                                // Category Pill
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: cardBg,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    event.category,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: cardColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // 3-dots More Actions Menu
                      IconButton(
                        icon: const Icon(Icons.more_vert_rounded, color: Color(0xFFCBD5E1), size: 20),
                        onPressed: () => _showEventOptions(event),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyEventsState(String message) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Color(0xFFF0FDF4),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.event_available_outlined,
              color: Color(0xFF10B981),
              size: 26,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF718096),
            ),
          ),
        ],
      ),
    );
  }

  void _showEventOptions(CalendarEventModel event) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  event.title,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '${event.time} ΓÇó ${event.category}',
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF718096)),
                ),
                if (event.description != null) ...[
                  const SizedBox(height: 10),
                  Text(event.description!, style: const TextStyle(fontSize: 13)),
                ],
                const Divider(height: 24),
                ListTile(
                  leading: const Icon(Icons.alarm_on_rounded, color: Color(0xFF1B5E3F)),
                  title: const Text('Add 15m Reminder'),
                  onTap: () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF1B5E3F),
                        content: Text('Reminder set for "${event.title}"'),
                      ),
                    );
                  },
                ),
                if (_canAddEvents)
                  ListTile(
                    leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
                    title: const Text('Delete Event', style: TextStyle(color: Color(0xFFEF4444))),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _events.removeWhere((e) => e.id == event.id);
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: const Color(0xFF1B5E3F),
                          content: Text('Deleted "${event.title}"'),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAddEventDialog() {
    final titleController = TextEditingController();
    final timeController = TextEditingController(text: '10:00 AM ΓÇô 11:00 AM');
    String selectedCategory = 'Meeting';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 22,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 22,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'New Schedule Event',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A202C),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: 'Event Title',
                      hintText: 'e.g. Client Design Workshop',
                      filled: true,
                      fillColor: const Color(0xFFF7FAF8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: timeController,
                    decoration: InputDecoration(
                      labelText: 'Time Range',
                      hintText: '10:00 AM ΓÇô 11:00 AM',
                      filled: true,
                      fillColor: const Color(0xFFF7FAF8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Category',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ['Meeting', 'Discussion', 'Review', 'Holiday'].map((cat) {
                      final isSel = selectedCategory == cat;
                      return ChoiceChip(
                        label: Text(cat),
                        selected: isSel,
                        selectedColor: const Color(0xFF1B5E3F),
                        labelStyle: TextStyle(
                          color: isSel ? Colors.white : const Color(0xFF2D3748),
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: (val) {
                          if (val) setSheetState(() => selectedCategory = cat);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      final title = titleController.text.trim();
                      if (title.isEmpty) return;

                      Color catColor = const Color(0xFF1B5E3F);
                      Color catBg = const Color(0xFFE8F5ED);
                      IconData catIcon = Icons.groups_outlined;

                      if (selectedCategory == 'Discussion') {
                        catColor = const Color(0xFF7C3AED);
                        catBg = const Color(0xFFF3E8FF);
                        catIcon = Icons.article_outlined;
                      } else if (selectedCategory == 'Review') {
                        catColor = const Color(0xFFD97706);
                        catBg = const Color(0xFFFEF3C7);
                        catIcon = Icons.palette_outlined;
                      } else if (selectedCategory == 'Holiday') {
                        catColor = const Color(0xFFDC2626);
                        catBg = const Color(0xFFFEE2E2);
                        catIcon = Icons.celebration_outlined;
                      }

                      final newEvent = CalendarEventModel(
                        id: 'evt_${DateTime.now().millisecondsSinceEpoch}',
                        title: title,
                        dateTime: _selectedDate,
                        time: timeController.text.trim(),
                        category: selectedCategory,
                        color: catColor,
                        bg: catBg,
                        icon: catIcon,
                      );

                      setState(() {
                        _events.add(newEvent);
                      });

                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: const Color(0xFF1B5E3F),
                          content: Text('Added "$title" to ${_formatMonthDay(_selectedDate)}'),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B5E3F),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Save Event', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Format Helpers
  String _formatMonthYear(DateTime dt) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[dt.month - 1]} ${dt.year}';
  }

  String _formatMonthDay(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dDay(dt.day)}';
  }

  String _formatDayTitle(DateTime dt) {
    const weekDays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${weekDays[dt.weekday % 7]}, ${months[dt.month - 1]} ${dt.day}';
  }

  String dDay(int day) => day.toString();
}

class _WeekdayLabel extends StatelessWidget {
  final String label;

  const _WeekdayLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 38,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF718096),
        ),
      ),
    );
  }
}
