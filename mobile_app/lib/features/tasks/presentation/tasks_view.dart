import 'package:flutter/material.dart';

/// Screen 2 in UI Reference: Tasks Screen (Premium Modern Office Theme)
///
/// Palette:
/// - Primary Dark Green: #1B5E3F
/// - Light Mint Background: #E8F5ED
/// - White Cards: #FFFFFF
/// - Priority Badges:
///     - High: #EF4444 (bg #FEE2E2)
///     - Medium: #F59E0B (bg #FEF3C7)
///     - Low: #3B82F6 (bg #E0F2FE)
///     - Done/Completed: #22C55E (bg #DCFCE7)
class TasksView extends StatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback? onOpenDrawer;

  const TasksView({super.key, this.onBack, this.onOpenDrawer});

  @override
  State<TasksView> createState() => _TasksViewState();
}

class _TasksViewState extends State<TasksView> {
  // 0: All, 1: Active, 2: Completed
  int _selectedFilter = 0;

  // Search query for the top search bar
  bool _isSearchActive = false;
  final TextEditingController _searchController = TextEditingController();

  // Dynamic stateful task list matching the reference specification
  late List<_TaskModel> _tasks;

  @override
  void initState() {
    super.initState();
    _tasks = [
      _TaskModel(
        id: 'task_1',
        title: 'UI Design Review',
        time: '10:00 AM - 11:00 AM',
        date: 'Mon, 20 Oct 2026',
        description: 'Review the high-fidelity Premium Office design system for ReGen mobile screens with the product and engineering teams.',
        priority: 'High',
        priorityColor: const Color(0xFFEF4444),
        priorityBg: const Color(0xFFFEE2E2),
        icon: Icons.design_services_outlined,
        iconColor: const Color(0xFF3B82F6),
        iconBg: const Color(0xFFE0F2FE),
        status: 'In Progress',
        isCompleted: false,
      ),
      _TaskModel(
        id: 'task_2',
        title: 'API Integration',
        time: '11:30 AM - 01:00 PM',
        date: 'Mon, 20 Oct 2026',
        description: 'Synchronize dual authentication service between PostgreSQL and MongoDB backend endpoints on port 5006.',
        priority: 'Medium',
        priorityColor: const Color(0xFFF59E0B),
        priorityBg: const Color(0xFFFEF3C7),
        icon: Icons.sync_rounded,
        iconColor: const Color(0xFFF59E0B),
        iconBg: const Color(0xFFFEF3C7),
        status: 'In Progress',
        isCompleted: false,
      ),
      _TaskModel(
        id: 'task_3',
        title: 'Team Meeting',
        time: '02:00 PM - 03:00 PM',
        date: 'Mon, 20 Oct 2026',
        description: 'Bi-weekly engineering sync on sprint deliverables, attendance automation, and geofencing verification.',
        priority: 'Low',
        priorityColor: const Color(0xFF3B82F6),
        priorityBg: const Color(0xFFE0F2FE),
        icon: Icons.people_outline_rounded,
        iconColor: const Color(0xFFA855F7),
        iconBg: const Color(0xFFF3E8FF),
        status: 'In Progress',
        isCompleted: false,
      ),
      _TaskModel(
        id: 'task_4',
        title: 'Update Documentation',
        time: '03:30 PM - 04:30 PM',
        date: 'Mon, 20 Oct 2026',
        description: 'Document the multi-branch Git workflow and mobile component architecture for future maintainers.',
        priority: 'Medium',
        priorityColor: const Color(0xFFF59E0B),
        priorityBg: const Color(0xFFFEF3C7),
        icon: Icons.description_outlined,
        iconColor: const Color(0xFFA855F7),
        iconBg: const Color(0xFFF3E8FF),
        status: 'In Progress',
        isCompleted: false,
      ),
      _TaskModel(
        id: 'task_5',
        title: 'Fix Attendance UI',
        time: '04:30 PM - 05:30 PM',
        date: 'Mon, 20 Oct 2026',
        description: 'Refactor check-in timestamp visualization and segmented date toggle pills for better tap accessibility.',
        priority: 'Low',
        priorityColor: const Color(0xFF3B82F6),
        priorityBg: const Color(0xFFE0F2FE),
        icon: Icons.check_circle_outline_rounded,
        iconColor: const Color(0xFF3B82F6),
        iconBg: const Color(0xFFE0F2FE),
        status: 'Done',
        isCompleted: true,
      ),
    ];
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Dynamic counts calculated from real task state
  int get _allCount => _tasks.length;
  int get _activeCount => _tasks.where((t) => !t.isCompleted).length;
  int get _completedCount => _tasks.where((t) => t.isCompleted).length;

  List<_TaskModel> get _filteredTasks {
    final query = _searchController.text.trim().toLowerCase();
    return _tasks.where((task) {
      // Filter tab check
      if (_selectedFilter == 1 && task.isCompleted) return false;
      if (_selectedFilter == 2 && !task.isCompleted) return false;

      // Search query check
      if (query.isNotEmpty) {
        final matchesTitle = task.title.toLowerCase().contains(query);
        final matchesDesc = task.description.toLowerCase().contains(query);
        final matchesPriority = task.priority.toLowerCase().contains(query);
        if (!matchesTitle && !matchesDesc && !matchesPriority) return false;
      }
      return true;
    }).toList();
  }

  void _toggleTaskCompletion(_TaskModel task) {
    setState(() {
      final index = _tasks.indexWhere((t) => t.id == task.id);
      if (index != -1) {
        final current = _tasks[index];
        final nextCompleted = !current.isCompleted;
        _tasks[index] = current.copyWith(
          isCompleted: nextCompleted,
          status: nextCompleted ? 'Done' : 'In Progress',
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const primaryGreen = Color(0xFF1B5E3F);
    const backgroundMint = Color(0xFFE8F5ED);

    final displayTasks = _filteredTasks;

    return Scaffold(
      backgroundColor: backgroundMint,
      floatingActionButton: FloatingActionButton(
        heroTag: 'tasks_fab',
        onPressed: _showCreateTaskSheet,
        backgroundColor: primaryGreen,
        elevation: 4,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Top App Bar Header
            _buildTasksHeader(primaryGreen),

            // Search Bar (expandable)
            if (_isSearchActive) _buildSearchBar(primaryGreen),

            const SizedBox(height: 12),

            // 2. Redesigned Segmented Filter Container: [All] [Active] [Completed]
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildFilterSegmentedBar(primaryGreen),
            ),
            const SizedBox(height: 16),

            // 3. Task Cards List
            Expanded(
              child: displayTasks.isEmpty
                  ? _buildEmptyState(primaryGreen)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 2, 20, 90),
                      itemCount: displayTasks.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final task = displayTasks[index];
                        return _buildTaskCard(task, primaryGreen);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 1. Top Tasks Header: Back Arrow, Bold Title, Search & Filter Options
  Widget _buildTasksHeader(Color primaryGreen) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          if (widget.onOpenDrawer != null)
            Container(
              width: 38,
              height: 38,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1B5E3F).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(
                  Icons.menu_rounded,
                  color: Color(0xFF1B5E3F),
                  size: 22,
                ),
                tooltip: 'Menu',
                onPressed: widget.onOpenDrawer,
              ),
            )
          else if (widget.onBack != null)
            IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 20,
                color: Color(0xFF1B5E3F),
              ),
              onPressed: widget.onBack,
            )
          else
            const SizedBox(width: 4),
          const Text(
            'Tasks',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1B5E3F),
              letterSpacing: -0.3,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
              _isSearchActive ? Icons.close_rounded : Icons.search_rounded,
              color: primaryGreen,
              size: 22,
            ),
            tooltip: 'Search tasks',
            onPressed: () {
              setState(() {
                _isSearchActive = !_isSearchActive;
                if (!_isSearchActive) _searchController.clear();
              });
            },
          ),
          IconButton(
            icon: const Icon(
              Icons.tune_rounded,
              color: Color(0xFF1B5E3F),
              size: 22,
            ),
            tooltip: 'Filter options',
            onPressed: _showFilterMenu,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(Color primaryGreen) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD1E7DD)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x061B5E3F),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: 14, color: Color(0xFF1B4332)),
          decoration: const InputDecoration(
            hintText: 'Search tasks by title, priority...',
            hintStyle: TextStyle(fontSize: 13, color: Color(0xFF8DA499)),
            prefixIcon: Icon(Icons.search_rounded, size: 20, color: Color(0xFF1B5E3F)),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ),
    );
  }

  /// 2. Segmented Rounded Light-Mint Container with [All], [Active], [Completed]
  Widget _buildFilterSegmentedBar(Color primaryGreen) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFD8EFE2),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          _buildFilterSegment(
            label: 'All',
            count: _allCount,
            index: 0,
            primaryGreen: primaryGreen,
          ),
          _buildFilterSegment(
            label: 'Active',
            count: _activeCount,
            index: 1,
            primaryGreen: primaryGreen,
          ),
          _buildFilterSegment(
            label: 'Completed',
            count: _completedCount,
            index: 2,
            primaryGreen: primaryGreen,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSegment({
    required String label,
    required int count,
    required int index,
    required Color primaryGreen,
  }) {
    final isSelected = _selectedFilter == index;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedFilter = index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? primaryGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              if (isSelected)
                BoxShadow(
                  color: primaryGreen.withValues(alpha: 0.28),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? Colors.white : const Color(0xFF2D6A4F),
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.22)
                      : const Color(0xFFC7E6D4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : const Color(0xFF1B5E3F),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 3. Redesigned Task Card Matching Reference Screen 2
  Widget _buildTaskCard(_TaskModel task, Color primaryGreen) {
    return InkWell(
      onTap: () => _showTaskDetails(task, primaryGreen),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFFE2EFE7),
            width: 1.2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x061B5E3F),
              blurRadius: 12,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Soft Rounded Icon, Title, Priority Badge, Chevron
            Row(
              children: [
                // Soft coloured rounded icon container
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: task.iconBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    task.icon,
                    color: task.iconColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),

                // Task Title
                Expanded(
                  child: Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1B4332),
                      decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                      decorationColor: const Color(0xFF8DA499),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Priority Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: task.priorityBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    task.priority,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: task.priorityColor,
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Subtle chevron navigation indicator
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: Color(0xFF8DA499),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Bottom Row: Clock + Time range & Status pill
            Padding(
              padding: const EdgeInsets.only(left: 56),
              child: Row(
                children: [
                  const Icon(
                    Icons.access_time_rounded,
                    size: 14,
                    color: Color(0xFF8DA499),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    task.time,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF8DA499),
                    ),
                  ),
                  const Spacer(),

                  // Status Label
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: task.isCompleted
                          ? const Color(0xFFDCFCE7)
                          : const Color(0xFFE8F5ED),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: task.isCompleted
                                ? const Color(0xFF22C55E)
                                : primaryGreen,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          task.status,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: task.isCompleted
                                ? const Color(0xFF15803D)
                                : primaryGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(Color primaryGreen) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A1B5E3F),
                  blurRadius: 14,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              Icons.task_alt_rounded,
              size: 42,
              color: primaryGreen.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'No tasks found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1B4332),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'There are no tasks matching this filter.',
            style: TextStyle(fontSize: 13, color: Color(0xFF52796F)),
          ),
        ],
      ),
    );
  }

  /// Task Details Modal Sheet
  void _showTaskDetails(_TaskModel task, Color primaryGreen) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Color(0x18000000),
                blurRadius: 20,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Grab handle
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD8EADB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Priority & Status header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: task.priorityBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${task.priority} Priority',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: task.priorityColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: task.isCompleted
                          ? const Color(0xFFDCFCE7)
                          : const Color(0xFFE8F5ED),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      task.status,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: task.isCompleted
                            ? const Color(0xFF15803D)
                            : primaryGreen,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF52796F)),
                    onPressed: () => Navigator.pop(sheetContext),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Title
              Text(
                task.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1B4332),
                ),
              ),
              const SizedBox(height: 16),

              // Date & Time Info
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAF9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE8F3EA)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_rounded, size: 16, color: primaryGreen),
                    const SizedBox(width: 8),
                    Text(
                      task.date,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1B4332),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Icon(Icons.access_time_rounded, size: 16, color: primaryGreen),
                    const SizedBox(width: 8),
                    Text(
                      task.time,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1B4332),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Description
              const Text(
                'Description',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1B4332),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                task.description,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: Color(0xFF52796F),
                ),
              ),
              const SizedBox(height: 24),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFD8EADB)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Close', style: TextStyle(color: Color(0xFF52796F), fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _toggleTaskCompletion(task);
                        Navigator.pop(sheetContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: primaryGreen,
                            content: Text(
                              task.isCompleted
                                  ? 'Task marked as In Progress'
                                  : 'Task marked as Completed!',
                            ),
                          ),
                        );
                      },
                      icon: Icon(
                        task.isCompleted
                            ? Icons.replay_rounded
                            : Icons.check_circle_rounded,
                        size: 18,
                      ),
                      label: Text(task.isCompleted ? 'Reopen Task' : 'Mark as Done'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: MediaQuery.of(sheetContext).padding.bottom + 8),
            ],
          ),
        );
      },
    );
  }

  /// Create Task Bottom Sheet
  void _showCreateTaskSheet() {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    String selectedPriority = 'Medium';
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              padding: EdgeInsets.only(
                top: 20,
                left: 24,
                right: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Create New Task',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1B5E3F),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Color(0xFF52796F)),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Task Title
                      const Text(
                        'Task Title *',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1B4332)),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: titleController,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1B4332)),
                        decoration: InputDecoration(
                          hintText: 'e.g. Conduct Code Review',
                          fillColor: const Color(0xFFE8F5ED),
                          filled: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFFD8EADB)),
                          ),
                        ),
                        validator: (val) =>
                            (val == null || val.trim().isEmpty) ? 'Please enter a title' : null,
                      ),
                      const SizedBox(height: 16),

                      // Priority Selection
                      const Text(
                        'Priority',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1B4332)),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: ['Low', 'Medium', 'High'].map((p) {
                          final isPSelected = selectedPriority == p;
                          final Color color = p == 'High'
                              ? const Color(0xFFEF4444)
                              : (p == 'Medium'
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFF3B82F6));
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: ChoiceChip(
                                label: Text(p),
                                selected: isPSelected,
                                selectedColor: color.withValues(alpha: 0.18),
                                labelStyle: TextStyle(
                                  color: isPSelected ? color : const Color(0xFF52796F),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                ),
                                onSelected: (sel) {
                                  if (sel) setSheetState(() => selectedPriority = p);
                                },
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),

                      // Description
                      const Text(
                        'Description',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1B4332)),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: descController,
                        maxLines: 3,
                        style: const TextStyle(fontSize: 13.5, color: Color(0xFF1B4332)),
                        decoration: InputDecoration(
                          hintText: 'Enter task description and objectives...',
                          fillColor: const Color(0xFFE8F5ED),
                          filled: true,
                          contentPadding: const EdgeInsets.all(14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFFD8EADB)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Action Button
                      ElevatedButton(
                        onPressed: () {
                          if (!formKey.currentState!.validate()) return;
                          final newTask = _TaskModel(
                            id: 'task_${DateTime.now().millisecondsSinceEpoch}',
                            title: titleController.text.trim(),
                            time: 'Today',
                            date: '20 Oct 2026',
                            description: descController.text.trim().isNotEmpty
                                ? descController.text.trim()
                                : 'No additional description provided.',
                            priority: selectedPriority,
                            priorityColor: selectedPriority == 'High'
                                ? const Color(0xFFEF4444)
                                : (selectedPriority == 'Medium'
                                    ? const Color(0xFFF59E0B)
                                    : const Color(0xFF3B82F6)),
                            priorityBg: selectedPriority == 'High'
                                ? const Color(0xFFFEE2E2)
                                : (selectedPriority == 'Medium'
                                    ? const Color(0xFFFEF3C7)
                                    : const Color(0xFFE0F2FE)),
                            icon: Icons.assignment_outlined,
                            iconColor: const Color(0xFF1B5E3F),
                            iconBg: const Color(0xFFE8F5ED),
                            status: 'In Progress',
                            isCompleted: false,
                          );

                          setState(() {
                            _tasks.insert(0, newTask);
                          });

                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: Color(0xFF1B5E3F),
                              content: Text('New task created successfully!'),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1B5E3F),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('Save Task', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showFilterMenu() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sorted by scheduled time and priority.'),
        backgroundColor: Color(0xFF1B5E3F),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

class _TaskModel {
  final String id;
  final String title;
  final String time;
  final String date;
  final String description;
  final String priority;
  final Color priorityColor;
  final Color priorityBg;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String status;
  final bool isCompleted;

  const _TaskModel({
    required this.id,
    required this.title,
    required this.time,
    required this.date,
    required this.description,
    required this.priority,
    required this.priorityColor,
    required this.priorityBg,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.status,
    required this.isCompleted,
  });

  _TaskModel copyWith({
    String? id,
    String? title,
    String? time,
    String? date,
    String? description,
    String? priority,
    Color? priorityColor,
    Color? priorityBg,
    IconData? icon,
    Color? iconColor,
    Color? iconBg,
    String? status,
    bool? isCompleted,
  }) {
    return _TaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      time: time ?? this.time,
      date: date ?? this.date,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      priorityColor: priorityColor ?? this.priorityColor,
      priorityBg: priorityBg ?? this.priorityBg,
      icon: icon ?? this.icon,
      iconColor: iconColor ?? this.iconColor,
      iconBg: iconBg ?? this.iconBg,
      status: status ?? this.status,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}
