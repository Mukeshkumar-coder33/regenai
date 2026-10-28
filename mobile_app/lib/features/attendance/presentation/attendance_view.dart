import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';

/// Screen 4: Attendance Screen
///
/// Reproduces Screen 4 from the "8. Premium Celadon" design specification:
/// - Header with back navigation and title "Attendance"
/// - Segmented toggle pills: [Month], [Week], [List]
/// - Month calendar picker with header "< October 2026 >" and active date circle
/// - "Check In" card displaying active check-in time ("09:10 AM")
/// - Full-width "Check Out" action button with interactive state feedback
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
                    'Attendance',
                    style: TextStyle(
                      fontSize: 20,
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

              // 3. Calendar Month Card
              Container(
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
                    // Month Selector Header: < October 2026 >
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
                          onPressed: () {},
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Day of Week Header: S M T W T F S
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

                    // Calendar Grid (31 Days)
                    _buildCalendarGrid(),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 4. Status Card: "Check In  09:10 AM"
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF5EE),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: CeladonColors.border),
                ),
                child: Column(
                  children: [
                    Text(
                      _isCheckedIn ? 'Check In' : 'Checked Out',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: CeladonColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _checkInTime,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: CeladonColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 5. Full-width Action Button: "Check Out"
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
              const SizedBox(height: 20),
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

  Widget _buildCalendarGrid() {
    // October 2026 starts on Thursday (index 4)
    // 31 days in October
    final days = <Widget>[];

    // Leading empty days (Sun, Mon, Tue, Wed)
    for (int i = 0; i < 4; i++) {
      days.add(const SizedBox());
    }

    // Days 1 through 31
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

