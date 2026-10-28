import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';

/// Screen 5: Calendar Screen
///
/// Reproduces Screen 5 from the "8. Premium Celadon" design specification:
/// - Header with title "Calendar"
/// - Segmented toggle pills: [Month], [Week], [List]
/// - Month calendar picker with header "< October 2026 >"
/// - Section header showing active date ("20 Oct 2026")
/// - Scheduled meetings and event cards with distinct color-coded badges:
///   * Team Meeting (10:00 AM - 11:00 AM)
///   * Project Discussion (01:00 PM - 02:00 PM)
///   * Design Review (03:00 PM - 04:00 PM)
/// - Green (+) Floating Action Button to schedule events
class CalendarView extends StatefulWidget {
  final VoidCallback? onBack;

  const CalendarView({super.key, this.onBack});

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  int _selectedSegment = 0; // 0: Month, 1: Week, 2: List
  int _selectedDay = 20;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CeladonColors.background,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEventDialog(),
        backgroundColor: CeladonColors.primary,
        elevation: 3,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
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
                    // Header: < October 2026 >
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
                    const SizedBox(height: 10),

                    // Weekday Initials: S M T W T F S
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
                    const SizedBox(height: 8),

                    // Calendar Grid
                    _buildCalendarGrid(),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 4. Section Header: "20 Oct 2026"
              Text(
                '$_selectedDay Oct 2026',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: CeladonColors.textPrimary,
                ),
              ),
              const SizedBox(height: 14),

              // 5. Events List
              _buildEventCard(
                icon: Icons.schedule_rounded,
                iconColor: const Color(0xFF2D6A4F),
                iconBg: CeladonColors.primaryContainer,
                title: 'Team Meeting',
                time: '10:00 AM - 11:00 AM',
              ),
              const SizedBox(height: 10),

              _buildEventCard(
                icon: Icons.event_note_rounded,
                iconColor: const Color(0xFF8B5CF6),
                iconBg: const Color(0xFFEDE9FE),
                title: 'Project Discussion',
                time: '01:00 PM - 02:00 PM',
              ),
              const SizedBox(height: 10),

              _buildEventCard(
                icon: Icons.pie_chart_outline_rounded,
                iconColor: const Color(0xFFD97706),
                iconBg: const Color(0xFFFEF3C7),
                title: 'Design Review',
                time: '03:00 PM - 04:00 PM',
              ),
              const SizedBox(height: 80), // room for FAB
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
                color: isSelected ? Colors.white : CeladonColors.textPrimary,
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

  Widget _buildEventCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String time,
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
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: CeladonColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  time,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
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

  void _showAddEventDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Schedule New Event',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: CeladonColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Add meetings, review sessions, or project discussions to your ReGen team calendar.',
                style: TextStyle(fontSize: 13, color: CeladonColors.textSecondary),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: CeladonColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      },
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

