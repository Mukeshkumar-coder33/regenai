import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';

/// Screen 4: Attendance Screen (Premium Modern Office Theme)
///
/// Features:
/// - Light mint background with executive corporate theme
/// - Segmented toggle pills: [Month], [Week], [List]
/// - Polished white calendar card with active date selection and status indicators
/// - Check In / Out status card with geofence verification tag
/// - Full-width action button with interactive state feedback
class AttendanceView extends StatefulWidget {
  final VoidCallback? onBack;

  const AttendanceView({super.key, this.onBack});

  @override
  State<AttendanceView> createState() => _AttendanceViewState();
}

class _AttendanceViewState extends State<AttendanceView> {
  int _selectedSegment = 0; // 0: Month, 1: Week, 2: List
  int _selectedDay = 20;
  bool _isCheckedIn = true;
  String _checkInTime = '09:10 AM';

  final List<Map<String, String>> _attendanceLogs = const [
    {'date': '20 Oct 2026', 'in': '09:10 AM', 'out': '--:--', 'status': 'Present'},
    {'date': '19 Oct 2026', 'in': '09:05 AM', 'out': '06:12 PM', 'status': 'Present'},
    {'date': '18 Oct 2026', 'in': '08:58 AM', 'out': '06:05 PM', 'status': 'Present'},
    {'date': '17 Oct 2026', 'in': '09:15 AM', 'out': '06:20 PM', 'status': 'Present'},
    {'date': '16 Oct 2026', 'in': '--:--', 'out': '--:--', 'status': 'Approved Leave'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CeladonColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Top Bar
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
                    'Attendance',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: CeladonColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

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

              // 3. View Switcher
              if (_selectedSegment == 0) ...[
                _buildMonthCalendarCard(),
              ] else if (_selectedSegment == 1) ...[
                _buildWeekViewCard(),
              ] else ...[
                _buildListViewCard(),
              ],
              const SizedBox(height: 18),

              // 4. Status Card: "Check In  09:10 AM"
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _isCheckedIn ? CeladonColors.primary : CeladonColors.textMuted,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isCheckedIn ? 'Check In' : 'Checked Out',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: CeladonColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _checkInTime,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: CeladonColors.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: CeladonColors.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.check_circle_rounded, size: 14, color: CeladonColors.primary),
                          SizedBox(width: 6),
                          Text(
                            'Verified Office Zone (HQ Campus)',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: CeladonColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 5. Full-width Action Button
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      if (_isCheckedIn) {
                        _isCheckedIn = false;
                        _checkInTime = '06:15 PM';
                      } else {
                        _isCheckedIn = true;
                        _checkInTime = '09:10 AM';
                      }
                    });

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _isCheckedIn
                              ? 'Checked in successfully at $_checkInTime'
                              : 'Checked out successfully at $_checkInTime',
                        ),
                        backgroundColor: CeladonColors.primary,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CeladonColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  child: Text(
                    _isCheckedIn ? 'Check Out' : 'Check In',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
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
            boxShadow: [
              if (isSelected)
                BoxShadow(
                  color: CeladonColors.primary.withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
            ],
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

  Widget _buildMonthCalendarCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.chevron_left_rounded,
                  color: CeladonColors.textPrimary,
                  size: 22,
                ),
                onPressed: () {},
              ),
              const Text(
                'October 2026',
                style: TextStyle(
                  fontSize: 16.5,
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
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: const [
              _WeekdayLabel('S'),
              _WeekdayLabel('M'),
              _WeekdayLabel('T'),
              _WeekdayLabel('W'),
              _WeekdayLabel('T'),
              _WeekdayLabel('F'),
              _WeekdayLabel('S'),
            ],
          ),
          const SizedBox(height: 10),
          _buildCalendarGrid(),
        ],
      ),
    );
  }

  Widget _buildWeekViewCard() {
    const weekDays = ['Mon (19)', 'Tue (20)', 'Wed (21)', 'Thu (22)', 'Fri (23)'];
    const hours = ['8h 45m', 'Active', '--', '--', '--'];

    return Container(
      padding: const EdgeInsets.all(18),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This Week\'s Working Hours',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: CeladonColors.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          ...List.generate(weekDays.length, (i) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    weekDays[i],
                    style: const TextStyle(fontSize: 13, color: CeladonColors.textSecondary, fontWeight: FontWeight.w500),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: hours[i] == 'Active'
                          ? CeladonColors.primaryContainer
                          : CeladonColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      hours[i],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: hours[i] == 'Active' ? CeladonColors.primary : CeladonColors.textPrimary,
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

  Widget _buildListViewCard() {
    return Container(
      padding: const EdgeInsets.all(18),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent Attendance Logs',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: CeladonColors.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          ..._attendanceLogs.map((log) {
            final isLeave = log['status'] == 'Approved Leave';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    isLeave ? Icons.beach_access_outlined : Icons.check_circle_outline_rounded,
                    size: 18,
                    color: isLeave ? const Color(0xFFEF4444) : CeladonColors.primary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    log['date']!,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: CeladonColors.textPrimary),
                  ),
                  const Spacer(),
                  Text(
                    isLeave ? 'Leave' : '${log['in']} - ${log['out']}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isLeave ? const Color(0xFFEF4444) : CeladonColors.textSecondary,
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

  Widget _buildCalendarGrid() {
    final days = <Widget>[];

    for (int i = 0; i < 4; i++) {
      days.add(const SizedBox());
    }

    for (int day = 1; day <= 31; day++) {
      final isSelected = day == _selectedDay;

      days.add(
        GestureDetector(
          onTap: () => setState(() => _selectedDay = day),
          child: Container(
            margin: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              color: isSelected ? CeladonColors.primary : Colors.transparent,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$day',
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : (day < 20
                        ? CeladonColors.textPrimary
                        : CeladonColors.textSecondary),
              ),
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
