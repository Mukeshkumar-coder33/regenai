import 'package:flutter/material.dart';
import '../../../core/storage/session_storage.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../auth/data/user_model.dart';
import '../../dashboard/data/dashboard_service.dart';
import '../data/project_model.dart';
import '../data/task_model.dart';
import '../data/task_service.dart';

/// Screen 6: Tasks, Projects & Schedules Screen
///
/// Features:
/// - 100% Dynamic MongoDB Tasks & Projects data via `TaskService`
/// - Filter Tabs: [All], [Active], [Completed], [Projects]
/// - Search bar with instant text filtering
/// - Task completion toggle directly on the card
/// - Task detail & status update sheet (To Do, In Progress, Paused, Completed)
/// - Create Task dialog with priority, assignee from live company users, project, due date & time
/// - Delete Task with confirmation dialog
/// - Projects section: View all enterprise projects, filter tasks by project, and create new projects
/// - Hamburger menu icon opening `AppDrawer`
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

  // 0: All, 1: Active, 2: Completed, 3: Projects
  int _selectedFilter = 0;

  bool _isSearchActive = false;
  final TextEditingController _searchController = TextEditingController();

  List<TaskModel> _tasks = [];
  List<ProjectModel> _projects = [];
  List<UserModel> _teamMembers = [];
  String? _selectedProjectIdFilter;

  @override
  void initState() {
    super.initState();
    _taskService = widget.taskService ?? TaskService();
    _dashboardService = widget.dashboardService ?? DashboardService();
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchController.dispose();
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
        _taskService.getTasks(isSuperAdmin: user?.isSuperAdmin ?? false),
        _taskService.getProjects(),
        _dashboardService.getUsers(isSuperAdmin: user?.isSuperAdmin ?? false),
      ]);

      if (mounted) {
        setState(() {
          _tasks = results[0] as List<TaskModel>;
          _projects = results[1] as List<ProjectModel>;
          _teamMembers = results[2] as List<UserModel>;
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

  int get _allCount => _tasks.length;
  int get _activeCount => _tasks.where((t) => !t.isCompleted).length;
  int get _completedCount => _tasks.where((t) => t.isCompleted).length;

  List<TaskModel> get _filteredTasks {
    final query = _searchController.text.trim().toLowerCase();
    final currentUser = widget.user ?? _loggedInUser;

    return _tasks.where((task) {
      // Role enforcement: Employees only see tasks assigned to them
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

      // If a specific project is selected to filter
      if (_selectedProjectIdFilter != null && _selectedProjectIdFilter!.isNotEmpty) {
        if (task.projectId != _selectedProjectIdFilter) return false;
      }

      // Filter tab check
      if (_selectedFilter == 1 && task.isCompleted) return false;
      if (_selectedFilter == 2 && !task.isCompleted) return false;

      // Search query check
      if (query.isNotEmpty) {
        final matchesTitle = task.title.toLowerCase().contains(query);
        final matchesDesc = (task.description ?? '').toLowerCase().contains(query);
        final matchesPriority = task.priority.toLowerCase().contains(query);
        final matchesAssignee = (task.assignedTo ?? '').toLowerCase().contains(query);
        final matchesProject = (task.projectName ?? '').toLowerCase().contains(query);
        if (!matchesTitle && !matchesDesc && !matchesPriority && !matchesAssignee && !matchesProject) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Future<void> _toggleTaskCompletion(TaskModel task) async {
    final nextCompleted = !task.isCompleted;
    final originalTasks = List<TaskModel>.from(_tasks);

    // Optimistic UI update
    setState(() {
      final index = _tasks.indexWhere((t) => t.id == task.id);
      if (index != -1) {
        _tasks[index] = task.copyWith(
          status: nextCompleted ? 'done' : 'in_progress',
        );
      }
    });

    try {
      final updated = await _taskService.toggleTaskComplete(task.id, nextCompleted);
      if (mounted) {
        setState(() {
          final index = _tasks.indexWhere((t) => t.id == task.id);
          if (index != -1) _tasks[index] = updated;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: nextCompleted ? CeladonColors.primary : CeladonColors.primaryDark,
            duration: const Duration(seconds: 2),
            content: Text(
              nextCompleted ? 'Task marked as completed' : 'Task resumed to In Progress',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _tasks = originalTasks);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: CeladonColors.error,
            content: Text('Failed to update task: $e'),
          ),
        );
      }
    }
  }

  Future<void> _updateTaskStatus(TaskModel task, String newStatus) async {
    try {
      final updated = await _taskService.updateTask(task.id, {'status': newStatus});
      if (mounted) {
        setState(() {
          final idx = _tasks.indexWhere((t) => t.id == task.id);
          if (idx != -1) _tasks[idx] = updated;
        });
        Navigator.pop(context); // Close detail sheet
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: CeladonColors.primary,
            content: Text('Task status changed to ${updated.displayStatus}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: CeladonColors.error, content: Text('Error updating status: $e')),
        );
      }
    }
  }

  Future<void> _deleteTask(TaskModel task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Task', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('Are you sure you want to permanently delete "${task.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
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
        Navigator.pop(context); // Close detail sheet if open
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFFDC2626),
            content: Text('Task deleted successfully'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: CeladonColors.error, content: Text('Failed to delete task: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryGreen = Color(0xFF1B5E3F);
    const backgroundMint = Color(0xFFE8F5ED);

    return Scaffold(
      backgroundColor: backgroundMint,
      floatingActionButton: _canManage
          ? FloatingActionButton(
              heroTag: 'tasks_fab',
              onPressed: _showCreateTaskSheet,
              backgroundColor: primaryGreen,
              elevation: 4,
              shape: const CircleBorder(),
              tooltip: 'Create New Task',
              child: const Icon(Icons.add, color: Colors.white, size: 28),
            )
          : null,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Top App Bar Header with Hamburger Menu
            _buildTasksHeader(primaryGreen),

            // Search Bar (expandable)
            if (_isSearchActive) _buildSearchBar(primaryGreen),

            // Active Project Filter Banner (if filtering by a project)
            if (_selectedProjectIdFilter != null) _buildProjectFilterBanner(primaryGreen),

            const SizedBox(height: 10),

            // 2. Segmented Filter Container: [All] [Active] [Completed] [Projects]
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildFilterSegmentedBar(primaryGreen),
            ),
            const SizedBox(height: 14),

            // 3. Body: Tasks List or Projects Tab
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: primaryGreen))
                  : _errorMessage != null
                      ? _buildErrorState(primaryGreen)
                      : RefreshIndicator(
                          onRefresh: _loadInitialData,
                          color: primaryGreen,
                          child: _selectedFilter == 3
                              ? _buildProjectsList(primaryGreen)
                              : _buildTasksList(primaryGreen),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  /// 1. Top Tasks Header: Hamburger Menu, Bold Title, Search & Filter Options
  Widget _buildTasksHeader(Color primaryGreen) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
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
            )
          else
            const SizedBox(width: 4),

          const Text(
            'Tasks & Schedules',
            style: TextStyle(
              fontSize: 21,
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
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF1B5E3F), size: 22),
            tooltip: 'Refresh tasks',
            onPressed: _loadInitialData,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(Color primaryGreen) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primaryGreen.withValues(alpha: 0.2)),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        decoration: InputDecoration(
          icon: Icon(Icons.search_rounded, color: primaryGreen, size: 20),
          hintText: 'Search by task title, assignee, or priority...',
          hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          border: InputBorder.none,
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildProjectFilterBanner(Color primaryGreen) {
    final proj = _projects.firstWhere(
      (p) => p.id == _selectedProjectIdFilter,
      orElse: () => ProjectModel(id: '', name: 'Selected Project'),
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: primaryGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryGreen.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_open_rounded, size: 16, color: Color(0xFF1B5E3F)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Filtered by: ${proj.name}',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF1B5E3F)),
            ),
          ),
          InkWell(
            onTap: () => setState(() => _selectedProjectIdFilter = null),
            child: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF1B5E3F)),
          ),
        ],
      ),
    );
  }

  /// Segmented Filter: [All] [Active] [Completed] [Projects]
  Widget _buildFilterSegmentedBar(Color primaryGreen) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFD8ECE0),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _buildSegmentItem('All ($_allCount)', 0, primaryGreen),
          _buildSegmentItem('Active ($_activeCount)', 1, primaryGreen),
          _buildSegmentItem('Done ($_completedCount)', 2, primaryGreen),
          _buildSegmentItem('Projects (${_projects.length})', 3, primaryGreen),
        ],
      ),
    );
  }

  Widget _buildSegmentItem(String label, int index, Color primaryGreen) {
    final isSelected = _selectedFilter == index;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedFilter = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? const [BoxShadow(color: Color(0x10000000), blurRadius: 4, offset: Offset(0, 1))]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected ? primaryGreen : const Color(0xFF4A5568),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTasksList(Color primaryGreen) {
    final tasks = _filteredTasks;

    if (tasks.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 60),
            alignment: Alignment.center,
            child: Column(
              children: [
                Icon(Icons.assignment_turned_in_outlined, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Text(
                  _selectedFilter == 2 ? 'No completed tasks yet' : 'No tasks match current filter',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _showCreateTaskSheet,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Create New Task'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
      itemCount: tasks.length,
      separatorBuilder: (_, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final task = tasks[index];
        return _buildTaskCard(task, primaryGreen);
      },
    );
  }

  Widget _buildTaskCard(TaskModel task, Color primaryGreen) {
    final priorityColor = _getPriorityColor(task.priority);
    final priorityBg = _getPriorityBg(task.priority);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: task.isCompleted ? const Color(0xFFD1FAE5) : CeladonColors.borderLight,
          width: 1.2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _showTaskDetailsSheet(task, primaryGreen),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Checkbox, Title, Chevron
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Interactive Checkbox Button
                    InkWell(
                      onTap: () => _toggleTaskCompletion(task),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: task.isCompleted ? primaryGreen : Colors.transparent,
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: task.isCompleted ? primaryGreen : Colors.grey.shade400,
                            width: 1.8,
                          ),
                        ),
                        child: task.isCompleted
                            ? const Icon(Icons.check, size: 18, color: Colors.white)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Title & Description
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: task.isCompleted ? Colors.grey.shade500 : const Color(0xFF1A202C),
                              decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          if (task.description != null && task.description!.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              task.description!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Priority Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: priorityBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        task.displayPriority,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: priorityColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Bottom row: Assignee, Project tag, Status pill, and Deadline
                Row(
                  children: [
                    // Assignee badge
                    if (task.assignedTo != null && task.assignedTo!.isNotEmpty) ...[
                      CircleAvatar(
                        radius: 10,
                        backgroundColor: primaryGreen.withValues(alpha: 0.15),
                        child: Text(
                          task.assignedTo![0].toUpperCase(),
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: primaryGreen),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        task.assignedTo!,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF4A5568)),
                      ),
                      const SizedBox(width: 8),
                    ],

                    // Project badge
                    if (task.projectName != null && task.projectName!.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3E8FF),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          task.projectName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF7C3AED)),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],

                    const Spacer(),

                    // Due date
                    if (task.dueDate != null && task.dueDate!.isNotEmpty) ...[
                      const Icon(Icons.schedule_rounded, size: 13, color: Color(0xFF718096)),
                      const SizedBox(width: 4),
                      Text(
                        task.dueDate!.split('T').first,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF718096)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 4. Projects Tab View
  Widget _buildProjectsList(Color primaryGreen) {
    if (_projects.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 60),
            alignment: Alignment.center,
            child: Column(
              children: [
                Icon(Icons.folder_special_outlined, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                const Text(
                  'No enterprise projects created yet',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF4A5568)),
                ),
                if (_canManage) ...[
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _showCreateProjectDialog,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Create New Project'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
      itemCount: _projects.length + 1,
      separatorBuilder: (_, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Enterprise Projects',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF1B5E3F)),
              ),
              if (_canManage)
                TextButton.icon(
                  onPressed: _showCreateProjectDialog,
                  icon: const Icon(Icons.add, size: 16, color: Color(0xFF1B5E3F)),
                  label: const Text('New Project', style: TextStyle(color: Color(0xFF1B5E3F), fontWeight: FontWeight.w700)),
                ),
            ],
          );
        }

        final proj = _projects[index - 1];
        final taskCount = _tasks.where((t) => t.projectId == proj.id).length;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: CeladonColors.borderLight),
            boxShadow: const [
              BoxShadow(color: Color(0x06000000), blurRadius: 6, offset: Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      proj.name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1A202C)),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: proj.status.toLowerCase() == 'active' ? const Color(0xFFDEF7EC) : const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      proj.displayStatus.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: proj.status.toLowerCase() == 'active' ? const Color(0xFF03543F) : const Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ),
              if (proj.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  proj.description,
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5ED),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.assignment_outlined, size: 12, color: Color(0xFF1B5E3F)),
                        const SizedBox(width: 4),
                        Text(
                          '$taskCount Tasks',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF1B5E3F)),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedProjectIdFilter = proj.id;
                        _selectedFilter = 0; // Switch to All tasks filtered by this project
                      });
                    },
                    child: const Text('View Tasks →', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildErrorState(Color primaryGreen) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, color: CeladonColors.error, size: 40),
            const SizedBox(height: 12),
            Text(_errorMessage ?? 'Failed to load tasks', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadInitialData,
              style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, foregroundColor: Colors.white),
              child: const Text('Retry Connection'),
            ),
          ],
        ),
      ),
    );
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'urgent':
        return const Color(0xFFB91C1C);
      case 'high':
        return const Color(0xFFEF4444);
      case 'medium':
        return const Color(0xFFD97706);
      case 'low':
      default:
        return const Color(0xFF0284C7);
    }
  }

  Color _getPriorityBg(String priority) {
    switch (priority.toLowerCase()) {
      case 'urgent':
        return const Color(0xFFFEE2E2);
      case 'high':
        return const Color(0xFFFEE2E2);
      case 'medium':
        return const Color(0xFFFEF3C7);
      case 'low':
      default:
        return const Color(0xFFE0F2FE);
    }
  }

  /// Task Creation Modal Sheet
  void _showCreateTaskSheet() {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    String selectedPriority = 'medium';
    String? selectedAssignee;
    String? selectedProjectId;
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    TimeOfDay selectedTime = const TimeOfDay(hour: 17, minute: 0);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: EdgeInsets.only(
            top: 24,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Create New Task',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1B5E3F)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Title
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    labelText: 'Task Title *',
                    hintText: 'e.g. Design System Review',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),

                // Description
                TextField(
                  controller: descController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Description',
                    hintText: 'Add details or deliverables...',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 14),

                // Priority & Assignee Row
                Row(
                  children: [
                    // Priority
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: selectedPriority,
                        decoration: InputDecoration(
                          labelText: 'Priority',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'low', child: Text('Low')),
                          DropdownMenuItem(value: 'medium', child: Text('Medium')),
                          DropdownMenuItem(value: 'high', child: Text('High')),
                          DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                        ],
                        onChanged: (v) => setSheetState(() => selectedPriority = v ?? 'medium'),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Assignee
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: selectedAssignee,
                        decoration: InputDecoration(
                          labelText: 'Assignee',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        hint: const Text('Select User'),
                        items: _teamMembers.map((u) {
                          final label = u.name.isNotEmpty ? u.name : u.username;
                          return DropdownMenuItem(value: u.userId.isNotEmpty ? u.userId : u.id, child: Text(label, maxLines: 1));
                        }).toList(),
                        onChanged: (v) => setSheetState(() => selectedAssignee = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Project attachment dropdown
                if (_projects.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    initialValue: selectedProjectId,
                    decoration: InputDecoration(
                      labelText: 'Attach to Project (Optional)',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    hint: const Text('None'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None (Direct Task)')),
                      ..._projects.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))),
                    ],
                    onChanged: (v) => setSheetState(() => selectedProjectId = v),
                  ),
                  const SizedBox(height: 14),
                ],

                // Date & Time pickers
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today_rounded, size: 16),
                        label: Text(
                          "${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}",
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime.now().subtract(const Duration(days: 30)),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) setSheetState(() => selectedDate = picked);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.access_time_rounded, size: 16),
                        label: Text(selectedTime.format(context), style: const TextStyle(fontSize: 12)),
                        onPressed: () async {
                          final picked = await showTimePicker(context: context, initialTime: selectedTime);
                          if (picked != null) setSheetState(() => selectedTime = picked);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Submit Button
                ElevatedButton(
                  onPressed: () async {
                    if (titleController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a task title')),
                      );
                      return;
                    }

                    final newTaskId = 'task-${DateTime.now().millisecondsSinceEpoch}';
                    final dateStr = "${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}";
                    final timeStr = "${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}";
                    final proj = _projects.cast<ProjectModel?>().firstWhere((p) => p?.id == selectedProjectId, orElse: () => null);

                    final newTask = TaskModel(
                      id: newTaskId,
                      title: titleController.text.trim(),
                      description: descController.text.trim(),
                      priority: selectedPriority,
                      assignedTo: selectedAssignee,
                      status: 'todo',
                      dueDate: dateStr,
                      dueTime: timeStr,
                      projectId: selectedProjectId,
                      projectName: proj?.name,
                      isProjectTask: selectedProjectId != null,
                    );

                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                    Navigator.pop(ctx);

                    try {
                      final created = await _taskService.createTask(newTask);
                      if (mounted) {
                        setState(() => _tasks.insert(0, created));
                        scaffoldMessenger.showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFF1B5E3F),
                            content: Text('Task "${created.title}" created successfully!'),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        scaffoldMessenger.showSnackBar(
                          SnackBar(backgroundColor: CeladonColors.error, content: Text('Error: $e')),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B5E3F),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Create Task', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Task Details & Lifecycle Modal Sheet
  void _showTaskDetailsSheet(TaskModel task, Color primaryGreen) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    task.title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1A202C)),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getPriorityBg(task.priority),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    task.displayPriority,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _getPriorityColor(task.priority),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (task.description != null && task.description!.isNotEmpty) ...[
              Text(task.description!, style: TextStyle(fontSize: 13.5, color: Colors.grey.shade700, height: 1.4)),
              const SizedBox(height: 16),
            ],

            _buildDetailRow('Status', task.displayStatus),
            if (task.assignedTo != null) _buildDetailRow('Assignee', task.assignedTo!),
            if (task.projectName != null) _buildDetailRow('Project', task.projectName!),
            if (task.dueDate != null) _buildDetailRow('Due Date', task.dueDate!.split('T').first),
            if (task.dueTime != null) _buildDetailRow('Due Time', task.dueTime!),

            const SizedBox(height: 20),
            const Text('Change Status:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),

            // Status Changer Chips: [To Do] [In Progress] [Paused] [Done]
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildStatusChip(task, 'todo', 'To Do', const Color(0xFF64748B)),
                _buildStatusChip(task, 'in_progress', 'In Progress', const Color(0xFF1B5E3F)),
                _buildStatusChip(task, 'paused', 'Paused', const Color(0xFFD97706)),
                _buildStatusChip(task, 'done', 'Done', const Color(0xFF15803D)),
              ],
            ),

            const SizedBox(height: 24),

            // Delete Task Button (Only Manager/Admin can delete company tasks)
            if (_canManage)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _deleteTask(task),
                      icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626), size: 18),
                      label: const Text('Delete Task', style: TextStyle(color: Color(0xFFDC2626))),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFFCA5A5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(TaskModel task, String statusKey, String label, Color color) {
    final isCurrent = task.status.toLowerCase() == statusKey;

    return ActionChip(
      backgroundColor: isCurrent ? color : color.withValues(alpha: 0.1),
      label: Text(
        label,
        style: TextStyle(
          color: isCurrent ? Colors.white : color,
          fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
          fontSize: 12,
        ),
      ),
      onPressed: isCurrent ? null : () => _updateTaskStatus(task, statusKey),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: Color(0xFF718096))),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1A202C))),
        ],
      ),
    );
  }

  /// Create Project Dialog
  void _showCreateProjectDialog() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String priority = 'medium';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Create New Project', style: TextStyle(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Project Name *',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: priority,
                decoration: InputDecoration(
                  labelText: 'Priority',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: const [
                  DropdownMenuItem(value: 'low', child: Text('Low')),
                  DropdownMenuItem(value: 'medium', child: Text('Medium')),
                  DropdownMenuItem(value: 'high', child: Text('High')),
                  DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                ],
                onChanged: (v) => setDlgState(() => priority = v ?? 'medium'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final proj = ProjectModel(
                  id: 'proj-${DateTime.now().millisecondsSinceEpoch}',
                  name: nameCtrl.text.trim(),
                  description: descCtrl.text.trim(),
                  priority: priority,
                  status: 'active',
                );

                final scaffoldMessenger = ScaffoldMessenger.of(context);
                Navigator.pop(ctx);
                try {
                  final created = await _taskService.createProject(proj);
                  if (mounted) {
                    setState(() => _projects.add(created));
                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF1B5E3F),
                        content: Text('Project "${created.name}" created!'),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    scaffoldMessenger.showSnackBar(
                      SnackBar(backgroundColor: CeladonColors.error, content: Text('Error: $e')),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B5E3F),
                foregroundColor: Colors.white,
              ),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}
