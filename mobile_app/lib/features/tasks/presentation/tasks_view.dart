import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';

/// Screen 6: Tasks Screen
///
/// Reproduces Screen 6 from the "8. Premium Celadon" design specification:
/// - Header with title "Tasks"
/// - Filter pills: [All], [Active], [Completed]
/// - List of task cards with priority badges (High, Medium, Low), time slots, and chevron:
///   * UI Design Review (10:00 AM - 11:00 AM) -> [High]
///   * API Integration (11:30 AM - 01:00 PM) -> [Medium]
///   * Team Meeting (02:00 PM - 03:00 PM) -> [Low]
///   * Update Documentation (03:30 PM - 04:30 PM) -> [Medium]
///   * Fix Attendance UI (04:30 PM - 05:30 PM) -> [Low]
/// - Green (+) Floating Action Button to add tasks
class TasksView extends StatefulWidget {
  final VoidCallback? onBack;

  const TasksView({super.key, this.onBack});

  @override
  State<TasksView> createState() => _TasksViewState();
}

class _TasksViewState extends State<TasksView> {
  int _selectedFilter = 0; // 0: All, 1: Active, 2: Completed

  final List<_TaskItem> _tasks = const [
    _TaskItem(
      title: 'UI Design Review',
      time: '10:00 AM - 11:00 AM',
      priority: 'High',
      priorityColor: Color(0xFFEF4444),
      priorityBg: Color(0xFFFEE2E2),
      icon: Icons.check_circle_outline_rounded,
      iconColor: Color(0xFF2D6A4F),
      isCompleted: false,
    ),
    _TaskItem(
      title: 'API Integration',
      time: '11:30 AM - 01:00 PM',
      priority: 'Medium',
      priorityColor: Color(0xFFD97706),
      priorityBg: Color(0xFFFEF3C7),
      icon: Icons.warning_amber_rounded,
      iconColor: Color(0xFFD97706),
      isCompleted: false,
    ),
    _TaskItem(
      title: 'Team Meeting',
      time: '02:00 PM - 03:00 PM',
      priority: 'Low',
      priorityColor: Color(0xFF0284C7),
      priorityBg: Color(0xFFE0F2FE),
      icon: Icons.person_outline_rounded,
      iconColor: Color(0xFF0284C7),
      isCompleted: false,
    ),
    _TaskItem(
      title: 'Update Documentation',
      time: '03:30 PM - 04:30 PM',
      priority: 'Medium',
      priorityColor: Color(0xFFD97706),
      priorityBg: Color(0xFFFEF3C7),
      icon: Icons.sync_rounded,
      iconColor: Color(0xFF0284C7),
      isCompleted: false,
    ),
    _TaskItem(
      title: 'Fix Attendance UI',
      time: '04:30 PM - 05:30 PM',
      priority: 'Low',
      priorityColor: Color(0xFF0284C7),
      priorityBg: Color(0xFFE0F2FE),
      icon: Icons.radio_button_unchecked_rounded,
      iconColor: Color(0xFF2D6A4F),
      isCompleted: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final filteredTasks = _tasks.where((t) {
      if (_selectedFilter == 1) return !t.isCompleted;
      if (_selectedFilter == 2) return t.isCompleted;
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: CeladonColors.background,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddTaskDialog(),
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
                    'Tasks',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: CeladonColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 2. Filter Pills: [All] [Active] [Completed]
              Row(
                children: [
                  _buildFilterPill('All', 0),
                  const SizedBox(width: 10),
                  _buildFilterPill('Active', 1),
                  const SizedBox(width: 10),
                  _buildFilterPill('Completed', 2),
                ],
              ),
              const SizedBox(height: 18),

              // 3. Task Cards List
              ...filteredTasks.map((task) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildTaskCard(task),
                  )),

              const SizedBox(height: 80), // room for FAB
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterPill(String title, int index) {
    final isSelected = _selectedFilter == index;

    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? CeladonColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? CeladonColors.primary : CeladonColors.borderLight,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: CeladonColors.primary.withValues(alpha: 0.18),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
          ],
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : CeladonColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildTaskCard(_TaskItem task) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CeladonColors.borderLight),
        boxShadow: const [
          BoxShadow(
            color: Color(0x062D6A4F),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(task.icon, color: task.iconColor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  task.title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: CeladonColors.textPrimary,
                    decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: CeladonColors.textMuted,
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  task.time,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: CeladonColors.textMuted,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: task.priorityBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    task.priority,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: task.priorityColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAddTaskDialog() {
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
                'Create New Task',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: CeladonColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Assign new tasks, set priority levels (High, Medium, Low), and attach deadlines.',
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
                child: const Text('Save Task'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TaskItem {
  final String title;
  final String time;
  final String priority;
  final Color priorityColor;
  final Color priorityBg;
  final IconData icon;
  final Color iconColor;
  final bool isCompleted;

  const _TaskItem({
    required this.title,
    required this.time,
    required this.priority,
    required this.priorityColor,
    required this.priorityBg,
    required this.icon,
    required this.iconColor,
    required this.isCompleted,
  });
}

