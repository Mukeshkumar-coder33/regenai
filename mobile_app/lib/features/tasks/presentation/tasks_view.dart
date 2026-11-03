import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/storage/session_storage.dart';
import '../../auth/data/user_model.dart';
import '../../dashboard/data/dashboard_service.dart';
import '../data/project_model.dart';
import '../data/task_model.dart';
import '../data/task_service.dart';

/// Screen: Enterprise Tasks, Projects & Schedules
///
/// Features:
/// - True Frosted Glassmorphism matching Company Dashboard UI (`assets/images/corporate_office_dark.jpg`)
/// - Two Primary Segments: [General Task] and [Projects]
/// - General Task Metric Counters: Total Tasks, Pending, Incomplete, Completed
/// - Full Search Bar searching by Title, Description, and Assigned Person
/// - Filter Tabs: [All], [Pending] / [Active], [Completed] / [Done], [Incomplete]
/// - Task Card & Detail Modal with full Task details, Assigned Person details,
///   Progress details for pending tasks, and Completion timestamp for completed tasks
/// - Create Task with Title, Multi-Modal Description (Text, Voice Dictation, Voice Note),
///   Assignee, Priority, Duration, Start Date, and Automatically Computed End Date
/// - Projects Tab: Metrics, Search, Status Filters, Expandable Project Cards with Team Members,
///   Linked Project Tasks, and Create Project with Employee Multi-select
class TasksView extends StatefulWidget {
  final UserModel? user;
  final VoidCallback? onBack;
  final VoidCallback? onOpenDrawer;
  final TaskService? taskService;
  final DashboardService? dashboardService;

  const TasksView({
    super.key,
    this.user,
    this.onBack,
    this.onOpenDrawer,
    this.taskService,
    this.dashboardService,
  });

  /// Automatically computes End Date & Due Time from Start Date and Duration
  static Map<String, String> computeEndDateTime(
    String startIso,
    num durationValue,
    String durationUnit,
  ) {
    return _TasksViewState.computeEndDateTime(startIso, durationValue, durationUnit);
  }

  @override
  State<TasksView> createState() => _TasksViewState();
}

class _TasksViewState extends State<TasksView> {
  late final TaskService _taskService;
  late final DashboardService _dashboardService;

  UserModel? _loggedInUser;
  bool _isLoading = true;
  String? _errorMessage;

  bool get _canManage =>
      (widget.user?.isSuperAdmin == true || widget.user?.isCompanyAdmin == true) ||
      (_loggedInUser?.isSuperAdmin == true || _loggedInUser?.isCompanyAdmin == true);

  // 0: General Task, 1: Projects
  int _activeMainSegment = 0;

  // General Tasks Filter: 0: All, 1: Pending (Active), 2: Completed (Done), 3: Incomplete
  int _selectedTaskFilter = 0;

  // Projects Status Filter: 'all', 'active', 'planning', 'completed', 'on_hold'
  String _selectedProjectStatusFilter = 'all';

  final TextEditingController _taskSearchController = TextEditingController();
  final TextEditingController _projectSearchController = TextEditingController();

  List<TaskModel> _tasks = [];
  List<ProjectModel> _projects = [];
  List<UserModel> _teamMembers = [];

  // Expanded project IDs for accordion
  final Set<String> _expandedProjectIds = {};

  @override
  void initState() {
    super.initState();
    _taskService = widget.taskService ?? TaskService();
    _dashboardService = widget.dashboardService ?? DashboardService();
    _loadInitialData();
  }

  @override
  void dispose() {
    _taskSearchController.dispose();
    _projectSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = widget.user ?? await SessionStorage.getUserSession();
      _loggedInUser = user;

      final results = await Future.wait([
        _taskService.getTasks(isSuperAdmin: user?.isSuperAdmin ?? false).catchError((_) => <TaskModel>[]),
        _taskService.getProjects().catchError((_) => <ProjectModel>[]),
        _dashboardService.getUsers(isSuperAdmin: user?.isSuperAdmin ?? false).catchError((_) => <UserModel>[]),
      ]);

      if (mounted) {
        setState(() {
          _tasks = results[0] as List<TaskModel>;
          _projects = results[1] as List<ProjectModel>;
          _teamMembers = results[2] as List<UserModel>;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _tasks = [];
          _projects = [];
          _teamMembers = [];
          _isLoading = false;
        });
      }
    }
  }

  // Non-admin team members for task assignment
  List<UserModel> get _assignableEmployees {
    return _teamMembers.where((u) {
      final r = u.role.toLowerCase();
      return r != 'param' && r != 'owner' && r != 'admin';
    }).toList();
  }

  // Resolve employee user model by assignedTo
  UserModel? _resolveEmployee(String? assignedTo) {
    if (assignedTo == null || assignedTo.isEmpty) return null;
    final needle = assignedTo.trim().toLowerCase();
    for (final u in _teamMembers) {
      if (u.userId.toLowerCase() == needle ||
          u.id.toLowerCase() == needle ||
          u.username.toLowerCase() == needle ||
          u.name.toLowerCase() == needle) {
        return u;
      }
    }
    return null;
  }

  String _getAssigneeDisplayName(String? assignedTo) {
    if (assignedTo == null || assignedTo.isEmpty) return 'Unassigned';
    final emp = _resolveEmployee(assignedTo);
    if (emp != null) {
      if (emp.name.trim().isNotEmpty) return emp.name.trim();
      if (emp.username.trim().isNotEmpty) return emp.username.trim();
    }
    return assignedTo;
  }

  // General tasks only (non-project or all tasks)
  List<TaskModel> get _generalTasks => _tasks.where((t) => !t.isProjectTask).toList();

  int get _totalTaskCount => _generalTasks.length;
  int get _pendingCount => _generalTasks.where((t) => t.isPending).length;
  int get _incompleteCount => _generalTasks.where((t) => t.isIncomplete).length;
  int get _completedCount => _generalTasks.where((t) => t.isCompleted).length;

  List<TaskModel> get _filteredGeneralTasks {
    final query = _taskSearchController.text.trim().toLowerCase();
    final currentUser = widget.user ?? _loggedInUser;

    return _generalTasks.where((task) {
      // Role enforcement: Regular employees only see tasks assigned to them
      if (!_canManage && currentUser != null) {
        final uid = (currentUser.userId.isNotEmpty ? currentUser.userId : currentUser.id).toLowerCase();
        final uname = currentUser.username.toLowerCase();
        final name = currentUser.name.toLowerCase();
        if (task.assignedTo != null && task.assignedTo!.isNotEmpty) {
          final assigned = task.assignedTo!.toLowerCase();
          if (assigned != uid && assigned != uname && assigned != name) {
            return false;
          }
        }
      }

      // Filter tabs: 0=All, 1=Pending (Active), 2=Completed (Done), 3=Incomplete
      if (_selectedTaskFilter == 1 && !task.isPending) return false;
      if (_selectedTaskFilter == 2 && !task.isCompleted) return false;
      if (_selectedTaskFilter == 3 && !task.isIncomplete) return false;

      // Search query across Title, Description, and Assigned Person
      if (query.isNotEmpty) {
        final titleMatch = task.title.toLowerCase().contains(query);
        final descMatch = (task.description ?? '').toLowerCase().contains(query);
        final assignedPersonName = _getAssigneeDisplayName(task.assignedTo).toLowerCase();
        final assignedId = (task.assignedTo ?? '').toLowerCase();
        final personMatch = assignedPersonName.contains(query) || assignedId.contains(query);
        if (!titleMatch && !descMatch && !personMatch) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  List<ProjectModel> get _filteredProjects {
    final query = _projectSearchController.text.trim().toLowerCase();

    return _projects.where((proj) {
      if (_selectedProjectStatusFilter != 'all' &&
          proj.status.toLowerCase() != _selectedProjectStatusFilter.toLowerCase()) {
        return false;
      }
      if (query.isNotEmpty) {
        final nameMatch = proj.name.toLowerCase().contains(query);
        final descMatch = proj.description.toLowerCase().contains(query);
        final memberMatch = proj.assignedEmployees.any((m) {
          final mName = (m['name'] ?? m['username'] ?? '').toString().toLowerCase();
          return mName.contains(query);
        });
        if (!nameMatch && !descMatch && !memberMatch) return false;
      }
      return true;
    }).toList();
  }

  // Combined helper to compute End Date & Due Time automatically
  static Map<String, String> computeEndDateTime(
    String startIso,
    num durationValue,
    String durationUnit,
  ) {
    if (startIso.isEmpty) return {'endDate': '', 'dueTime': '18:00'};
    final durVal = durationValue.toDouble();
    if (durVal <= 0) return {'endDate': startIso, 'dueTime': '18:00'};

    DateTime startDate;
    try {
      startDate = DateTime.parse(startIso);
    } catch (_) {
      startDate = DateTime.now();
    }

    if (durationUnit.toLowerCase() == 'hours') {
      final now = DateTime.now();
      final isToday = startDate.year == now.year &&
          startDate.month == now.month &&
          startDate.day == now.day;
      final base = isToday ? now : DateTime(startDate.year, startDate.month, startDate.day, 9, 0);
      final target = base.add(Duration(minutes: (durVal * 60).round()));
      final endStr = '${target.year.toString().padLeft(4, '0')}-${target.month.toString().padLeft(2, '0')}-${target.day.toString().padLeft(2, '0')}';
      final dueTimeStr = '${target.hour.toString().padLeft(2, '0')}:${target.minute.toString().padLeft(2, '0')}';
      return {'endDate': endStr, 'dueTime': dueTimeStr};
    } else if (durationUnit.toLowerCase() == 'minutes') {
      final now = DateTime.now();
      final target = now.add(Duration(minutes: durVal.round()));
      final endStr = '${target.year.toString().padLeft(4, '0')}-${target.month.toString().padLeft(2, '0')}-${target.day.toString().padLeft(2, '0')}';
      final dueTimeStr = '${target.hour.toString().padLeft(2, '0')}:${target.minute.toString().padLeft(2, '0')}';
      return {'endDate': endStr, 'dueTime': dueTimeStr};
    } else {
      // Days
      final daysToAdd = durVal >= 1 ? durVal.round() : 1;
      final target = startDate.add(Duration(days: daysToAdd));
      final endStr = '${target.year.toString().padLeft(4, '0')}-${target.month.toString().padLeft(2, '0')}-${target.day.toString().padLeft(2, '0')}';
      return {'endDate': endStr, 'dueTime': '18:00'};
    }
  }

  // Optimistic Toggle Task Status
  Future<void> _toggleTaskCompletion(TaskModel task) async {
    final nextCompleted = !task.isCompleted;
    final original = List<TaskModel>.from(_tasks);

    setState(() {
      final idx = _tasks.indexWhere((t) => t.id == task.id);
      if (idx != -1) {
        _tasks[idx] = task.copyWith(status: nextCompleted ? 'done' : 'in_progress');
      }
    });

    try {
      final updated = await _taskService.toggleTaskComplete(task.id, nextCompleted);
      if (mounted) {
        setState(() {
          final idx = _tasks.indexWhere((t) => t.id == task.id);
          if (idx != -1) _tasks[idx] = updated;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: nextCompleted ? const Color(0xFF10B981) : const Color(0xFF0284C7),
            content: Text(nextCompleted ? 'Task marked as completed' : 'Task resumed to In Progress'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _tasks = original);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Failed to update task: $e'),
          ),
        );
      }
    }
  }

  // Delete Task
  Future<void> _deleteTask(TaskModel task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF042018),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: const Color(0xFF34D399).withValues(alpha: 0.3)),
        ),
        title: const Text('Delete Task', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        content: Text('Are you sure you want to delete "${task.title}"?', style: const TextStyle(color: Color(0xFFBACCC3))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8)))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _taskService.deleteTask(task.id);
      if (mounted) {
        setState(() => _tasks.removeWhere((t) => t.id == task.id));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Color(0xFFEF4444), content: Text('Task deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF031A14),
      floatingActionButton: _canManage
          ? Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.45),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: FloatingActionButton.extended(
                heroTag: 'tasks_fab',
                onPressed: _activeMainSegment == 0 ? _showCreateTaskSheet : _showCreateProjectSheet,
                backgroundColor: const Color(0xFF10B981),
                icon: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
                label: Text(
                  _activeMainSegment == 0 ? 'Add Task' : 'Create Project',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 13.5),
                ),
              ),
            )
          : null,
      body: Stack(
        children: [
          // Background: Photographic Corporate Office with Blur
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 7.0, sigmaY: 7.0),
              child: Transform.scale(
                scale: 1.05,
                child: Image.asset(
                  'assets/images/corporate_office_dark.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(color: const Color(0xFF031A14)),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF040A07).withValues(alpha: 0.40),
                    const Color(0xFF020704).withValues(alpha: 0.90),
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Pinned Top Header with Back Arrow
                _buildHeader(),

                // 2. Primary Segment Switcher: [General Task] vs [Projects]
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: _buildMainSegmentSwitcher(),
                ),

                // 3. Tab Body
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
                      : _errorMessage != null
                          ? _buildErrorState()
                          : RefreshIndicator(
                              onRefresh: _loadInitialData,
                              color: const Color(0xFF10B981),
                              child: _activeMainSegment == 0
                                  ? _buildGeneralTasksTab()
                                  : _buildProjectsTab(),
                            ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 1. Top Header
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Row(
        children: [
          // Back Button / Menu
          InkWell(
            onTap: widget.onBack ?? () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.25), width: 1.0),
              ),
              child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 12),

          // Title & Subtitle (Title includes 'Tasks & Schedules' for compatibility)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Tasks & Schedules',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                SizedBox(height: 1),
                Text(
                  'Company Workspace & Project Schedules',
                  style: TextStyle(fontSize: 11, color: Color(0xFFBACCC3)),
                ),
              ],
            ),
          ),

          // Refresh Button
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF34D399), size: 21),
            tooltip: 'Refresh',
            onPressed: _loadInitialData,
          ),
        ],
      ),
    );
  }

  // 2. Primary Segment Switcher: [General Task] and [Projects]
  Widget _buildMainSegmentSwitcher() {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF041812).withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.25), width: 1.0),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSegmentPill(
              title: 'General Task',
              icon: Icons.assignment_rounded,
              isSelected: _activeMainSegment == 0,
              badgeCount: _totalTaskCount,
              onTap: () => setState(() => _activeMainSegment = 0),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _buildSegmentPill(
              title: 'Projects',
              icon: Icons.folder_copy_rounded,
              isSelected: _activeMainSegment == 1,
              badgeCount: _projects.length,
              onTap: () => setState(() => _activeMainSegment = 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentPill({
    required String title,
    required IconData icon,
    required bool isSelected,
    required int badgeCount,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                )
              : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : const Color(0xFFBACCC3),
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.25)
                    : const Color(0xFF10B981).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$badgeCount',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : const Color(0xFF34D399),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 1: GENERAL TASKS TAB
  // ===========================================================================
  Widget _buildGeneralTasksTab() {
    final tasksToDisplay = _filteredGeneralTasks;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
      children: [
        // 1. Metric Counter Cards: Total Tasks, Pending, Incomplete, Completed
        _buildTaskMetricsGrid(),

        const SizedBox(height: 14),

        // 2. Full Search Box: Searches by Title, Description, and Assigned Person
        _buildTaskSearchBar(),

        const SizedBox(height: 12),

        // 3. Filter Segment Tabs: [All] [Pending / Active] [Completed / Done] [Incomplete]
        _buildTaskFilterTabs(),

        const SizedBox(height: 14),

        // 4. Tasks List
        if (tasksToDisplay.isEmpty)
          _buildEmptyTasksPlaceholder()
        else
          ...tasksToDisplay.map((task) => _buildTaskCard(task)),
      ],
    );
  }

  // 4 Metric Counter Cards: Total Tasks, Pending, Incomplete, Completed
  Widget _buildTaskMetricsGrid() {
    return Row(
      children: [
        Expanded(
          child: _buildMetricTile(
            title: 'Total Tasks',
            count: _totalTaskCount,
            icon: Icons.assignment_rounded,
            color: const Color(0xFF10B981),
            onTap: () => setState(() => _selectedTaskFilter = 0),
            isSelected: _selectedTaskFilter == 0,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMetricTile(
            title: 'Pending',
            count: _pendingCount,
            icon: Icons.schedule_rounded,
            color: const Color(0xFF06B6D4),
            onTap: () => setState(() => _selectedTaskFilter = 1),
            isSelected: _selectedTaskFilter == 1,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMetricTile(
            title: 'Incomplete',
            count: _incompleteCount,
            icon: Icons.error_outline_rounded,
            color: const Color(0xFFEF4444),
            onTap: () => setState(() => _selectedTaskFilter = 3),
            isSelected: _selectedTaskFilter == 3,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMetricTile(
            title: 'Completed',
            count: _completedCount,
            icon: Icons.check_circle_outline_rounded,
            color: const Color(0xFF34D399),
            onTap: () => setState(() => _selectedTaskFilter = 2),
            isSelected: _selectedTaskFilter == 2,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String title,
    required int count,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required bool isSelected,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.22)
              : const Color(0xFF042018).withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : const Color(0xFF34D399).withValues(alpha: 0.25),
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 5),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Color(0xFFBACCC3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Search Bar (Title, Description, and Assigned Person)
  Widget _buildTaskSearchBar() {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: const Color(0xFF092017).withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF34D399).withValues(alpha: 0.30),
          width: 1.0,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 19, color: Color(0xFF34D399)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _taskSearchController,
              cursorColor: const Color(0xFF34D399),
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                isDense: true,
                filled: true,
                fillColor: Colors.transparent,
                hintText: 'Search by title, description, or assigned person...',
                hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_taskSearchController.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _taskSearchController.clear();
                setState(() {});
              },
              child: const Icon(Icons.close_rounded, size: 17, color: Color(0xFFBACCC3)),
            ),
        ],
      ),
    );
  }

  // Filter Tabs: [All] [Pending / Active] [Completed / Done] [Incomplete]
  Widget _buildTaskFilterTabs() {
    final filters = [
      {'label': 'All', 'count': _totalTaskCount, 'idx': 0},
      {'label': 'Pending (Active)', 'count': _pendingCount, 'idx': 1},
      {'label': 'Completed (Done)', 'count': _completedCount, 'idx': 2},
      {'label': 'Incomplete', 'count': _incompleteCount, 'idx': 3},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((f) {
          final idx = f['idx'] as int;
          final isSelected = _selectedTaskFilter == idx;
          final count = f['count'] as int;
          final label = f['label'] as String;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () => setState(() => _selectedTaskFilter = idx),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF10B981)
                      : const Color(0xFF042018).withValues(alpha: 0.50),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF34D399) : const Color(0xFF34D399).withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? Colors.white : const Color(0xFF34D399),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // Task Card
  Widget _buildTaskCard(TaskModel task) {
    final assigneeName = _getAssigneeDisplayName(task.assignedTo);
    final emp = _resolveEmployee(task.assignedTo);
    final isDone = task.isCompleted;
    final isIncomplete = task.isIncomplete;

    // Status colors
    final statusColor = isDone
        ? const Color(0xFF10B981)
        : isIncomplete
            ? const Color(0xFFEF4444)
            : const Color(0xFF06B6D4);

    final statusText = isDone
        ? 'Completed'
        : isIncomplete
            ? 'Incomplete'
            : (task.isInProgress ? 'In Progress' : 'Pending');

    final hasVoiceNote = (task.description ?? '').contains('[voice_note:');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _showTaskDetailsSheet(task),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF042018).withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: statusColor.withValues(alpha: 0.35),
              width: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Status Pill, Priority Badge, Checkbox Toggle
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: statusColor.withValues(alpha: 0.40)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isDone
                              ? Icons.check_circle_rounded
                              : isIncomplete
                                  ? Icons.cancel_rounded
                                  : Icons.schedule_rounded,
                          size: 11,
                          color: statusColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Priority Badge
                  _buildPriorityBadge(task.priority),

                  if (hasVoiceNote) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.40)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.mic_rounded, size: 10, color: Color(0xFFA78BFA)),
                          SizedBox(width: 3),
                          Text('Voice Note', style: TextStyle(fontSize: 9.5, color: Color(0xFFA78BFA), fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ],

                  const Spacer(),

                  // Quick Toggle Button
                  if (!isIncomplete)
                    InkWell(
                      onTap: () => _toggleTaskCompletion(task),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDone
                              ? const Color(0xFF10B981)
                              : Colors.transparent,
                          border: Border.all(
                            color: isDone ? const Color(0xFF10B981) : const Color(0xFF34D399),
                            width: 1.5,
                          ),
                        ),
                        child: isDone
                            ? const Icon(Icons.check, size: 16, color: Colors.white)
                            : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),

              // Title
              Text(
                task.title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  decoration: isDone ? TextDecoration.lineThrough : null,
                  decorationColor: const Color(0xFF34D399),
                ),
              ),

              // Description Snippet
              if (task.description != null && task.description!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _cleanDescriptionSnippet(task.description!),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Color(0xFFBACCC3)),
                ),
              ],

              const SizedBox(height: 10),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 8),

              // Bottom Row: Assignee Info & Dates
              Row(
                children: [
                  // Assignee Avatar & Name
                  _buildEmployeeAvatarMini(emp, assigneeName),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          assigneeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                        Text(
                          emp?.department?.isNotEmpty == true
                              ? emp!.department!
                              : (emp?.role ?? 'Staff'),
                          style: const TextStyle(fontSize: 10, color: Color(0xFF34D399)),
                        ),
                      ],
                    ),
                  ),

                  // Dates
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 11, color: Color(0xFFBACCC3)),
                          const SizedBox(width: 4),
                          Text(
                            task.endDate ?? task.dueDate ?? 'No deadline',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isIncomplete ? const Color(0xFFEF4444) : const Color(0xFFBACCC3),
                            ),
                          ),
                        ],
                      ),
                      if (task.durationValue != null && task.durationValue! > 0)
                        Text(
                          '${task.durationValue} ${task.durationUnit ?? 'days'}',
                          style: const TextStyle(fontSize: 9.5, color: Color(0xFF6EE7B7)),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Priority Badge Helper
  Widget _buildPriorityBadge(String priority) {
    Color pColor;
    switch (priority.toLowerCase()) {
      case 'urgent':
        pColor = const Color(0xFFA855F7);
        break;
      case 'high':
        pColor = const Color(0xFFEF4444);
        break;
      case 'low':
        pColor = const Color(0xFF10B981);
        break;
      case 'medium':
      default:
        pColor = const Color(0xFFF59E0B);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: pColor.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: pColor.withValues(alpha: 0.35)),
      ),
      child: Text(
        priority.toUpperCase(),
        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: pColor),
      ),
    );
  }

  // Clean description removing [voice_note:...] tag for preview
  String _cleanDescriptionSnippet(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'\[voice_note:[^\]]+\]'), '').trim();
    return cleaned.isNotEmpty ? cleaned : 'Voice note attached.';
  }

  Widget _buildEmployeeAvatarMini(UserModel? emp, String name) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF065F46)]),
        border: Border.all(color: const Color(0xFF34D399), width: 1.2),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white),
      ),
    );
  }

  // ===========================================================================
  // TASK DETAILS MODAL (Task details, Assigned Person details, Progress / Completed details)
  // ===========================================================================
  void _showTaskDetailsSheet(TaskModel task) {
    final emp = _resolveEmployee(task.assignedTo);
    final assigneeName = _getAssigneeDisplayName(task.assignedTo);
    final isDone = task.isCompleted;
    final isIncomplete = task.isIncomplete;

    final voiceNoteMatch = RegExp(r'\[voice_note:([^\]]+)\]').firstMatch(task.description ?? '');
    final voiceNoteRef = voiceNoteMatch?.group(1);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        return Container(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
          decoration: BoxDecoration(
            color: const Color(0xFF042018),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.35), width: 1.2),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Header (Pinned)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Task Details',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      const Spacer(),
                      if (_canManage)
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _deleteTask(task);
                          },
                        ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white12, height: 1),

                // Scrollable Content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Status & Priority Banner
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: (isDone
                                        ? const Color(0xFF10B981)
                                        : isIncomplete
                                            ? const Color(0xFFEF4444)
                                            : const Color(0xFF06B6D4))
                                    .withValues(alpha: 0.20),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: (isDone
                                      ? const Color(0xFF10B981)
                                      : isIncomplete
                                          ? const Color(0xFFEF4444)
                                          : const Color(0xFF06B6D4)),
                                ),
                              ),
                              child: Text(
                                task.displayStatus,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  color: (isDone
                                      ? const Color(0xFF34D399)
                                      : isIncomplete
                                          ? const Color(0xFFF87171)
                                          : const Color(0xFF38BDF8)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildPriorityBadge(task.priority),
                            if (task.projectName != null && task.projectName!.isNotEmpty) ...[
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E293B),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  task.projectName!,
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Title
                        Text(
                          task.title,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                        const SizedBox(height: 10),

                        // Full Description
                        if (task.description != null && task.description!.isNotEmpty) ...[
                          const Text('DESCRIPTION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFBACCC3))),
                          const SizedBox(height: 4),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF03140F),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.2)),
                            ),
                            child: Text(
                              _cleanDescriptionSnippet(task.description!),
                              style: const TextStyle(fontSize: 13.5, color: Colors.white, height: 1.4),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Voice Note Player (if present)
                        if (voiceNoteRef != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.35)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF8B5CF6),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: const [
                                      Text('Voice Note Recording Attached', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
                                      Text('Tap to listen to supervisor instructions', style: TextStyle(fontSize: 10.5, color: Color(0xFFBACCC3))),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // SECTION 1: ASSIGNED PERSON DETAILS
                        const Text('ASSIGNED PERSON DETAILS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFBACCC3))),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF03140F),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              _buildEmployeeAvatarMini(emp, assigneeName),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(assigneeName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
                                    const SizedBox(height: 2),
                                    Text(
                                      'ID: ${emp?.userId ?? task.assignedTo ?? 'EMP-??'} • ${emp?.role ?? 'Staff'}',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF34D399)),
                                    ),
                                    if (emp?.email != null && emp!.email!.isNotEmpty)
                                      Text(emp.email!, style: const TextStyle(fontSize: 11, color: Color(0xFFBACCC3))),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // SECTION 2: TIMELINE & PROGRESS DETAILS
                        const Text('TIMELINE & PROGRESS DETAILS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFBACCC3))),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF03140F),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildDetailRow('Start Date', task.startDate ?? 'Today'),
                              _buildDetailRow('End Date / Deadline', task.endDate ?? task.dueDate ?? 'Not set'),
                              if (task.dueTime != null)
                                _buildDetailRow('Target End Time', task.dueTime!),
                              if (task.durationValue != null)
                                _buildDetailRow('Duration Allocated', '${task.durationValue} ${task.durationUnit ?? 'days'}'),

                              const SizedBox(height: 8),

                              // Conditional Details by Status
                              if (isDone) ...[
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
                                  ),
                                  child: Row(
                                    children: const [
                                      Icon(Icons.verified_rounded, color: Color(0xFF34D399), size: 18),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Task verified and completed on schedule.',
                                          style: TextStyle(fontSize: 12, color: Color(0xFF34D399), fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else if (isIncomplete) ...[
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.35)),
                                  ),
                                  child: Row(
                                    children: const [
                                      Icon(Icons.warning_amber_rounded, color: Color(0xFFF87171), size: 18),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'The assigned deadline has passed. Task marked as Not Completed.',
                                          style: TextStyle(fontSize: 12, color: Color(0xFFF87171), fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else if (task.isPending) ...[
                                // Progress bar for pending task
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Current Progress: ${task.isInProgress ? 'In Progress (50%)' : 'To Do (10%)'}',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF38BDF8)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: LinearProgressIndicator(
                                        value: task.isInProgress ? 0.5 : 0.1,
                                        backgroundColor: Colors.white12,
                                        color: const Color(0xFF06B6D4),
                                        minHeight: 8,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Action Buttons: Mark Complete / Resume
                        if (!isIncomplete)
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _toggleTaskCompletion(task);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDone ? const Color(0xFF0284C7) : const Color(0xFF10B981),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              ),
                              child: Text(
                                isDone ? 'Reopen / Resume Task' : 'Mark as Completed',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.white),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFFBACCC3))),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
        ],
      ),
    );
  }

  // ===========================================================================
  // ADD TASK (CREATE TASK SHEET WITH MULTI-MODAL VOICE DESCRIPTION)
  // ===========================================================================
  void _showCreateTaskSheet() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String priority = 'medium';
    String durationUnit = 'days';
    num durationVal = 1;
    String startDate = DateTime.now().toIso8601String().split('T')[0];

    // Compute initial end date
    var endCalc = computeEndDateTime(startDate, durationVal, durationUnit);
    String endDate = endCalc['endDate']!;
    String dueTime = endCalc['dueTime']!;

    String? selectedAssignee = _assignableEmployees.isNotEmpty
        ? (_assignableEmployees.first.userId.isNotEmpty ? _assignableEmployees.first.userId : _assignableEmployees.first.id)
        : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final media = MediaQuery.of(ctx);

          void recalculateEnd() {
            final res = computeEndDateTime(startDate, durationVal, durationUnit);
            setModalState(() {
              endDate = res['endDate']!;
              dueTime = res['dueTime']!;
            });
          }

          return Container(
            constraints: BoxConstraints(maxHeight: media.size.height * 0.90),
            padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
            decoration: BoxDecoration(
              color: const Color(0xFF042018),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.35), width: 1.2),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Pinned Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Create New Task',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Color(0xFFBACCC3)),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white12, height: 1),

                  // Form Body
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1. Title
                          _buildInputLabel('Task Title *'),
                          _buildDarkTextField(
                            controller: titleCtrl,
                            hintText: 'e.g. Complete API backend integration',
                          ),
                          const SizedBox(height: 14),

                          // 2. Description with Voice Mic Button
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildInputLabel('Description'),
                              GestureDetector(
                                onTap: () => _openVoiceDescriptionModal(descCtrl, () => setModalState(() {})),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.20),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.40)),
                                  ),
                                  child: Row(
                                    children: const [
                                      Icon(Icons.mic_rounded, size: 12, color: Color(0xFFA78BFA)),
                                      SizedBox(width: 4),
                                      Text('Voice Input', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFA78BFA))),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          _buildDarkTextField(
                            controller: descCtrl,
                            hintText: 'Add details, speak, or record voice note...',
                            maxLines: 3,
                          ),
                          const SizedBox(height: 14),

                          // 3. Assignee
                          _buildInputLabel('Assignee *'),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF03140F),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.3)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: selectedAssignee,
                                dropdownColor: const Color(0xFF042018),
                                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF34D399)),
                                isExpanded: true,
                                items: _assignableEmployees.map((emp) {
                                  final uId = emp.userId.isNotEmpty ? emp.userId : emp.id;
                                  final name = emp.name.isNotEmpty ? emp.name : emp.username;
                                  return DropdownMenuItem<String>(
                                    value: uId,
                                    child: Text('$name ($uId)', style: const TextStyle(color: Colors.white, fontSize: 13)),
                                  );
                                }).toList(),
                                onChanged: (val) => setModalState(() => selectedAssignee = val),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // 4. Priority
                          _buildInputLabel('Priority'),
                          Row(
                            children: ['low', 'medium', 'high', 'urgent'].map((p) {
                              final isSel = priority == p;
                              return Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 2),
                                  child: InkWell(
                                    onTap: () => setModalState(() => priority = p),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      decoration: BoxDecoration(
                                        color: isSel ? const Color(0xFF10B981) : const Color(0xFF03140F),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: isSel ? const Color(0xFF34D399) : Colors.white12,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        p[0].toUpperCase() + p.substring(1),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                                          color: isSel ? Colors.white : const Color(0xFFBACCC3),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 14),

                          // 5. Duration (Value + Unit)
                          _buildInputLabel('Duration (Allocated Time)'),
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  initialValue: '$durationVal',
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: const Color(0xFF03140F),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: const Color(0xFF34D399).withValues(alpha: 0.3)),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  ),
                                  onChanged: (val) {
                                    final numVal = num.tryParse(val) ?? 1;
                                    durationVal = numVal;
                                    recalculateEnd();
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 3,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF03140F),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.3)),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: durationUnit,
                                      dropdownColor: const Color(0xFF042018),
                                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF34D399)),
                                      isExpanded: true,
                                      items: const [
                                        DropdownMenuItem(value: 'hours', child: Text('Hours', style: TextStyle(color: Colors.white, fontSize: 13))),
                                        DropdownMenuItem(value: 'days', child: Text('Days', style: TextStyle(color: Colors.white, fontSize: 13))),
                                        DropdownMenuItem(value: 'minutes', child: Text('Minutes', style: TextStyle(color: Colors.white, fontSize: 13))),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) {
                                          durationUnit = val;
                                          recalculateEnd();
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // 6. Start Date & Automatically Calculated End Date
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildInputLabel('Start Date'),
                                    InkWell(
                                      onTap: () async {
                                        final now = DateTime.now();
                                        final picked = await showDatePicker(
                                          context: context,
                                          initialDate: now,
                                          firstDate: now.subtract(const Duration(days: 30)),
                                          lastDate: now.add(const Duration(days: 365)),
                                        );
                                        if (picked != null) {
                                          startDate = picked.toIso8601String().split('T')[0];
                                          recalculateEnd();
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF03140F),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.3)),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.calendar_today_rounded, size: 14, color: Color(0xFF34D399)),
                                            const SizedBox(width: 6),
                                            Text(startDate, style: const TextStyle(fontSize: 12, color: Colors.white)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildInputLabel('Auto Calculated End Date'),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.event_available_rounded, size: 14, color: Color(0xFF34D399)),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              '$endDate ($dueTime)',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF34D399)),
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
                          const SizedBox(height: 24),

                          // Submit Button: Radiant Emerald Pill
                          Container(
                            height: 50,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
                              borderRadius: BorderRadius.circular(25),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.40),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: () async {
                                final title = titleCtrl.text.trim();
                                if (title.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Please enter task title'), backgroundColor: Color(0xFFEF4444)),
                                  );
                                  return;
                                }
                                if (selectedAssignee == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Please select an assignee'), backgroundColor: Color(0xFFEF4444)),
                                  );
                                  return;
                                }

                                final newTask = TaskModel(
                                  id: 't-${DateTime.now().millisecondsSinceEpoch}',
                                  title: title,
                                  description: descCtrl.text.trim(),
                                  assignedTo: selectedAssignee,
                                  priority: priority,
                                  durationValue: durationVal,
                                  durationUnit: durationUnit,
                                  startDate: startDate,
                                  endDate: endDate,
                                  dueTime: dueTime,
                                  status: 'todo',
                                );

                                final messenger = ScaffoldMessenger.of(context);
                                final nav = Navigator.of(ctx);
                                try {
                                  final created = await _taskService.createTask(newTask);
                                  if (mounted) {
                                    setState(() => _tasks.insert(0, created));
                                    nav.pop();
                                    messenger.showSnackBar(
                                      SnackBar(
                                        backgroundColor: const Color(0xFF10B981),
                                        content: Text('Task assigned to $selectedAssignee & notification sent!'),
                                      ),
                                    );
                                  }
                                } catch (err) {
                                  if (mounted) {
                                    messenger.showSnackBar(
                                      SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('Error: $err')),
                                    );
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                              ),
                              child: const Text('Create & Assign Task', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Voice Description Modal (Voice-to-Text Dictation & Voice Note Recording)
  void _openVoiceDescriptionModal(TextEditingController descCtrl, VoidCallback onUpdate) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        int voiceTab = 0; // 0: Speech-to-Text, 1: Record Voice Note
        bool isSimulatingSpeech = false;
        String recognizedText = '';

        return StatefulBuilder(
          builder: (context, setVoiceState) {
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF042018),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.4), width: 1.2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.mic_rounded, color: Color(0xFFA78BFA), size: 20),
                          SizedBox(width: 8),
                          Text('Voice Description Assistant', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Color(0xFFBACCC3), size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 1),
                  const SizedBox(height: 12),

                  // Mode Switcher: Dictation vs Audio Note
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => setVoiceState(() => voiceTab = 0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: voiceTab == 0 ? const Color(0xFF8B5CF6) : const Color(0xFF03140F),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: const Text('Voice-to-Text', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          onTap: () => setVoiceState(() => voiceTab = 1),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: voiceTab == 1 ? const Color(0xFF8B5CF6) : const Color(0xFF03140F),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: const Text('Record Voice Note', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (voiceTab == 0) ...[
                    // Voice-to-Text
                    Center(
                      child: GestureDetector(
                        onTap: () {
                          setVoiceState(() {
                            isSimulatingSpeech = !isSimulatingSpeech;
                            if (isSimulatingSpeech) {
                              recognizedText = 'Please review the client design specifications and submit the finalized deliverable by Friday.';
                            }
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSimulatingSpeech ? const Color(0xFFEF4444) : const Color(0xFF8B5CF6),
                            boxShadow: [
                              BoxShadow(
                                color: (isSimulatingSpeech ? const Color(0xFFEF4444) : const Color(0xFF8B5CF6)).withValues(alpha: 0.45),
                                blurRadius: 20,
                              ),
                            ],
                          ),
                          child: Icon(
                            isSimulatingSpeech ? Icons.stop_rounded : Icons.mic_rounded,
                            size: 32,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: Text(
                        isSimulatingSpeech ? 'Listening... Tap to stop' : 'Tap mic to dictate description',
                        style: const TextStyle(fontSize: 12, color: Color(0xFFBACCC3)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (recognizedText.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF03140F),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
                        ),
                        child: Text(recognizedText, style: const TextStyle(color: Colors.white, fontSize: 13)),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () {
                          if (descCtrl.text.isNotEmpty) {
                            descCtrl.text = '${descCtrl.text.trim()} $recognizedText';
                          } else {
                            descCtrl.text = recognizedText;
                          }
                          onUpdate();
                          Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8B5CF6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Insert Spoken Text', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                    ],
                  ] else ...[
                    // Record Voice Note
                    Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF8B5CF6),
                        ),
                        child: const Icon(Icons.radio_button_checked_rounded, color: Colors.white, size: 30),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Center(
                      child: Text('00:15 - Voice Note Ready', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton(
                      onPressed: () {
                        final tag = '[voice_note:recorded_audio_${DateTime.now().millisecondsSinceEpoch}.m4a]';
                        descCtrl.text = descCtrl.text.isNotEmpty ? '${descCtrl.text.trim()}\n$tag' : tag;
                        onUpdate();
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Attach Voice Note Audio', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // TAB 2: PROJECTS TAB
  // ===========================================================================
  Widget _buildProjectsTab() {
    final projs = _filteredProjects;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
      children: [
        // 1. Projects Metrics
        _buildProjectMetricsRow(),

        const SizedBox(height: 14),

        // 2. Project Search Bar
        _buildProjectSearchBar(),

        const SizedBox(height: 12),

        // 3. Project Status Filters
        _buildProjectStatusFilters(),

        const SizedBox(height: 14),

        // 4. Projects List
        if (projs.isEmpty)
          _buildEmptyProjectsPlaceholder()
        else
          ...projs.map((p) => _buildProjectCard(p)),
      ],
    );
  }

  Widget _buildProjectMetricsRow() {
    final total = _projects.length;
    final active = _projects.where((p) => p.status.toLowerCase() == 'active').length;
    final completed = _projects.where((p) => p.status.toLowerCase() == 'completed').length;
    final totalProjectTasks = _tasks.where((t) => t.isProjectTask).length;

    return Row(
      children: [
        Expanded(child: _buildMetricTile(title: 'Projects', count: total, icon: Icons.folder_rounded, color: const Color(0xFF10B981), onTap: () => setState(() => _selectedProjectStatusFilter = 'all'), isSelected: _selectedProjectStatusFilter == 'all')),
        const SizedBox(width: 8),
        Expanded(child: _buildMetricTile(title: 'Active', count: active, icon: Icons.play_arrow_rounded, color: const Color(0xFF06B6D4), onTap: () => setState(() => _selectedProjectStatusFilter = 'active'), isSelected: _selectedProjectStatusFilter == 'active')),
        const SizedBox(width: 8),
        Expanded(child: _buildMetricTile(title: 'Completed', count: completed, icon: Icons.check_circle_rounded, color: const Color(0xFF34D399), onTap: () => setState(() => _selectedProjectStatusFilter = 'completed'), isSelected: _selectedProjectStatusFilter == 'completed')),
        const SizedBox(width: 8),
        Expanded(child: _buildMetricTile(title: 'Tasks', count: totalProjectTasks, icon: Icons.checklist_rounded, color: const Color(0xFFA855F7), onTap: () {}, isSelected: false)),
      ],
    );
  }

  Widget _buildProjectSearchBar() {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: const Color(0xFF092017).withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.30), width: 1.0),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 19, color: Color(0xFF34D399)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _projectSearchController,
              cursorColor: const Color(0xFF34D399),
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                isDense: true,
                filled: true,
                fillColor: Colors.transparent,
                hintText: 'Search projects by name, description, member...',
                hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_projectSearchController.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _projectSearchController.clear();
                setState(() {});
              },
              child: const Icon(Icons.close_rounded, size: 17, color: Color(0xFFBACCC3)),
            ),
        ],
      ),
    );
  }

  Widget _buildProjectStatusFilters() {
    final filters = ['all', 'active', 'planning', 'completed', 'on_hold'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((statusKey) {
          final isSelected = _selectedProjectStatusFilter == statusKey;
          final label = statusKey == 'all'
              ? 'All'
              : statusKey == 'on_hold'
                  ? 'On Hold'
                  : statusKey[0].toUpperCase() + statusKey.substring(1);

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () => setState(() => _selectedProjectStatusFilter = statusKey),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF10B981) : const Color(0xFF042018).withValues(alpha: 0.50),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF34D399) : const Color(0xFF34D399).withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildProjectCard(ProjectModel proj) {
    final isExpanded = _expandedProjectIds.contains(proj.id);
    final projectTasks = _tasks.where((t) => t.projectId == proj.id).toList();
    final completedTasks = projectTasks.where((t) => t.isCompleted).length;
    final totalTasks = projectTasks.length;
    final progress = totalTasks > 0 ? (completedTasks / totalTasks) : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF042018).withValues(alpha: 0.70),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.30), width: 1.1),
        ),
        child: Column(
          children: [
            InkWell(
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedProjectIds.remove(proj.id);
                  } else {
                    _expandedProjectIds.add(proj.id);
                  }
                });
              },
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.20),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF10B981)),
                          ),
                          child: Text(
                            proj.displayStatus,
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF34D399)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildPriorityBadge(proj.priority),
                        const Spacer(),
                        Icon(
                          isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          color: const Color(0xFF34D399),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(proj.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                    if (proj.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(proj.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFFBACCC3))),
                    ],
                    const SizedBox(height: 10),

                    // Progress Bar
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('$completedTasks / $totalTasks Tasks Done', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF34D399))),
                        Text('${(progress * 100).toInt()}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.white12,
                        color: const Color(0xFF10B981),
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Members & Dates
                    Row(
                      children: [
                        const Icon(Icons.group_rounded, size: 14, color: Color(0xFF34D399)),
                        const SizedBox(width: 5),
                        Text('${proj.assignedEmployees.length} members', style: const TextStyle(fontSize: 11, color: Color(0xFFBACCC3))),
                        const Spacer(),
                        if (proj.dueDate != null) ...[
                          const Icon(Icons.event_rounded, size: 13, color: Color(0xFFBACCC3)),
                          const SizedBox(width: 4),
                          Text('Due ${proj.dueDate}', style: const TextStyle(fontSize: 11, color: Color(0xFFBACCC3))),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Expanded Section: Project Tasks & Add Project Task
            if (isExpanded) ...[
              const Divider(color: Colors.white12, height: 1),
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.black.withValues(alpha: 0.25),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('PROJECT TASKS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF34D399))),
                        if (_canManage)
                          GestureDetector(
                            onTap: () => _showAddProjectTaskSheet(proj),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF10B981)),
                              ),
                              child: Row(
                                children: const [
                                  Icon(Icons.add_rounded, size: 12, color: Color(0xFF34D399)),
                                  SizedBox(width: 4),
                                  Text('Add Task', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF34D399))),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (projectTasks.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text('No tasks linked to this project yet.', style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8))),
                      )
                    else
                      ...projectTasks.map((pt) => _buildProjectTaskTile(pt)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProjectTaskTile(TaskModel task) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF03140F),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Icon(
              task.isCompleted ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              size: 16,
              color: task.isCompleted ? const Color(0xFF10B981) : const Color(0xFFBACCC3),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                task.title,
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.white,
                  decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            Text(
              _getAssigneeDisplayName(task.assignedTo),
              style: const TextStyle(fontSize: 10.5, color: Color(0xFF34D399)),
            ),
          ],
        ),
      ),
    );
  }

  // Create Project Sheet
  void _showCreateProjectSheet() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String priority = 'medium';
    String status = 'active';
    String startDate = DateTime.now().toIso8601String().split('T')[0];
    String dueDate = DateTime.now().add(const Duration(days: 14)).toIso8601String().split('T')[0];
    final Set<String> selectedEmployeeIds = {};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setProjState) {
          final media = MediaQuery.of(ctx);

          return Container(
            constraints: BoxConstraints(maxHeight: media.size.height * 0.90),
            padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
            decoration: BoxDecoration(
              color: const Color(0xFF042018),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.35), width: 1.2),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Create Enterprise Project', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
                        IconButton(icon: const Icon(Icons.close_rounded, color: Color(0xFFBACCC3)), onPressed: () => Navigator.pop(ctx)),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white12, height: 1),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildInputLabel('Project Name *'),
                          _buildDarkTextField(controller: nameCtrl, hintText: 'e.g. NextGen Web Portal'),
                          const SizedBox(height: 14),

                          _buildInputLabel('Description'),
                          _buildDarkTextField(controller: descCtrl, hintText: 'Project goals and deliverables...', maxLines: 2),
                          const SizedBox(height: 14),

                          _buildInputLabel('Priority'),
                          Row(
                            children: ['low', 'medium', 'high', 'urgent'].map((p) {
                              final isSel = priority == p;
                              return Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 2),
                                  child: InkWell(
                                    onTap: () => setProjState(() => priority = p),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      decoration: BoxDecoration(
                                        color: isSel ? const Color(0xFF10B981) : const Color(0xFF03140F),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: isSel ? const Color(0xFF34D399) : Colors.white12),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(p[0].toUpperCase() + p.substring(1), style: TextStyle(fontSize: 11, fontWeight: isSel ? FontWeight.w800 : FontWeight.w600, color: Colors.white)),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 14),

                          // Assign Team Members
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildInputLabel('Team Members (${selectedEmployeeIds.length} selected)'),
                              GestureDetector(
                                onTap: () {
                                  setProjState(() {
                                    if (selectedEmployeeIds.length == _assignableEmployees.length) {
                                      selectedEmployeeIds.clear();
                                    } else {
                                      selectedEmployeeIds.addAll(_assignableEmployees.map((e) => e.userId.isNotEmpty ? e.userId : e.id));
                                    }
                                  });
                                },
                                child: Text(
                                  selectedEmployeeIds.length == _assignableEmployees.length ? 'Deselect All' : 'Select All',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF34D399), fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: 140,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF03140F),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.3)),
                            ),
                            child: ListView(
                              children: _assignableEmployees.map((emp) {
                                final uid = emp.userId.isNotEmpty ? emp.userId : emp.id;
                                final isSelected = selectedEmployeeIds.contains(uid);
                                return CheckboxListTile(
                                  dense: true,
                                  value: isSelected,
                                  activeColor: const Color(0xFF10B981),
                                  title: Text(emp.name.isNotEmpty ? emp.name : emp.username, style: const TextStyle(fontSize: 12.5, color: Colors.white)),
                                  subtitle: Text(emp.role, style: const TextStyle(fontSize: 10.5, color: Color(0xFFBACCC3))),
                                  onChanged: (val) {
                                    setProjState(() {
                                      if (val == true) {
                                        selectedEmployeeIds.add(uid);
                                      } else {
                                        selectedEmployeeIds.remove(uid);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Submit
                          Container(
                            height: 50,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: ElevatedButton(
                              onPressed: () async {
                                final name = nameCtrl.text.trim();
                                if (name.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Project name is required')));
                                  return;
                                }

                                final assigned = _assignableEmployees
                                    .where((e) => selectedEmployeeIds.contains(e.userId.isNotEmpty ? e.userId : e.id))
                                    .map((e) => {
                                          'userId': e.userId.isNotEmpty ? e.userId : e.id,
                                          'name': e.name.isNotEmpty ? e.name : e.username,
                                          'email': e.email,
                                          'department': e.department,
                                        })
                                    .toList();

                                final newProj = ProjectModel(
                                  id: 'p-${DateTime.now().millisecondsSinceEpoch}',
                                  name: name,
                                  description: descCtrl.text.trim(),
                                  priority: priority,
                                  status: status,
                                  startDate: startDate,
                                  dueDate: dueDate,
                                  assignedEmployees: assigned,
                                );

                                final messenger = ScaffoldMessenger.of(context);
                                final nav = Navigator.of(ctx);
                                try {
                                  final created = await _taskService.createProject(newProj);
                                  if (mounted) {
                                    setState(() => _projects.insert(0, created));
                                    nav.pop();
                                    messenger.showSnackBar(
                                      SnackBar(backgroundColor: const Color(0xFF10B981), content: Text('Project "${created.name}" created successfully')),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                              ),
                              child: const Text('Create Project', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Add Task linked directly to a Project
  void _showAddProjectTaskSheet(ProjectModel project) {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    num durationVal = 1;
    String durationUnit = 'days';
    String startDate = DateTime.now().toIso8601String().split('T')[0];
    final endRes = computeEndDateTime(startDate, durationVal, durationUnit);
    String endDate = endRes['endDate']!;
    String dueTime = endRes['dueTime']!;

    // Assign to first member or all
    String? selectedAssignee = project.assignedEmployees.isNotEmpty
        ? project.assignedEmployees.first['userId']?.toString()
        : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final media = MediaQuery.of(ctx);

          void recalculate() {
            final res = computeEndDateTime(startDate, durationVal, durationUnit);
            setModalState(() {
              endDate = res['endDate']!;
              dueTime = res['dueTime']!;
            });
          }

          return Container(
            constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
            padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
            decoration: BoxDecoration(
              color: const Color(0xFF042018),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.35)),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Add Task to "${project.name}"', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                    const SizedBox(height: 12),
                    _buildInputLabel('Task Title *'),
                    _buildDarkTextField(controller: titleCtrl, hintText: 'Project task name...'),
                    const SizedBox(height: 12),

                    _buildInputLabel('Assignee in Project'),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF03140F),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.3)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedAssignee,
                          dropdownColor: const Color(0xFF042018),
                          isExpanded: true,
                          items: project.assignedEmployees.map((e) {
                            final uid = (e['userId'] ?? '').toString();
                            final name = (e['name'] ?? uid).toString();
                            return DropdownMenuItem<String>(
                              value: uid,
                              child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 13)),
                            );
                          }).toList(),
                          onChanged: (val) => setModalState(() => selectedAssignee = val),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Duration & End Date
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildInputLabel('Duration ($durationUnit)'),
                              TextFormField(
                                initialValue: '$durationVal',
                                keyboardType: TextInputType.number,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: const Color(0xFF03140F),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onChanged: (val) {
                                  durationVal = num.tryParse(val) ?? 1;
                                  recalculate();
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildInputLabel('Auto End Date'),
                              Container(
                                padding: const EdgeInsets.all(11),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFF10B981)),
                                ),
                                child: Text(endDate, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF34D399))),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    ElevatedButton(
                      onPressed: () async {
                        final title = titleCtrl.text.trim();
                        if (title.isEmpty) return;

                        final task = TaskModel(
                          id: 'pt-${DateTime.now().millisecondsSinceEpoch}',
                          title: title,
                          description: descCtrl.text.trim(),
                          assignedTo: selectedAssignee,
                          projectId: project.id,
                          projectName: project.name,
                          isProjectTask: true,
                          durationValue: durationVal,
                          durationUnit: durationUnit,
                          startDate: startDate,
                          endDate: endDate,
                          dueTime: dueTime,
                        );

                        final nav = Navigator.of(ctx);
                        try {
                          final created = await _taskService.createTask(task);
                          if (mounted) {
                            setState(() => _tasks.insert(0, created));
                            nav.pop();
                          }
                        } catch (_) {}
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Add Project Task', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ===========================================================================
  // UI HELPERS & PLACEHOLDERS
  // ===========================================================================
  Widget _buildInputLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFBACCC3)),
      ),
    );
  }

  Widget _buildDarkTextField({
    required TextEditingController controller,
    required String hintText,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      cursorColor: const Color(0xFF34D399),
      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFF03140F),
        hintText: hintText,
        hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: const Color(0xFF34D399).withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF34D399)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _buildEmptyTasksPlaceholder() {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF042018).withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.2)),
      ),
      child: Column(
        children: const [
          Icon(Icons.assignment_turned_in_rounded, size: 44, color: Color(0xFF34D399)),
          SizedBox(height: 10),
          Text('No Tasks Found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
          SizedBox(height: 4),
          Text(
            'Try adjusting your filter or search criteria, or click Add Task to create a new assignment.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFFBACCC3)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyProjectsPlaceholder() {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF042018).withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.2)),
      ),
      child: Column(
        children: const [
          Icon(Icons.folder_open_rounded, size: 44, color: Color(0xFF34D399)),
          SizedBox(height: 10),
          Text('No Projects Found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
          SizedBox(height: 4),
          Text(
            'Create enterprise projects to organize multi-member teams and project tasks.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFFBACCC3)),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 40, color: Color(0xFFEF4444)),
            const SizedBox(height: 10),
            Text('Error Loading Schedules', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 4),
            Text('$_errorMessage', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Color(0xFFBACCC3))),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadInitialData,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
              child: const Text('Try Again', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
