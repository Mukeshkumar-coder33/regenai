import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/storage/session_storage.dart';
import '../../auth/data/user_model.dart';
import '../../dashboard/data/dashboard_service.dart';
import '../data/project_model.dart';
import '../data/task_model.dart';
import '../data/task_service.dart';
import '../../../core/widgets/brand_logo.dart';

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

  final TextEditingController _taskSearchController = TextEditingController();
  final TextEditingController _projectSearchController = TextEditingController();
  final TextEditingController _projectTaskSearchController = TextEditingController();

  List<TaskModel> _tasks = [];
  List<ProjectModel> _projects = [];
  List<UserModel> _teamMembers = [];

  // Selected project for full details view
  ProjectModel? _selectedProjectForDetail;
  int _selectedProjectTaskFilter = 0; // 0: All, 1: Pending, 2: Completed, 3: Incomplete

  Timer? _liveTicker;

  @override
  void initState() {
    super.initState();
    _taskService = widget.taskService ?? TaskService();
    _dashboardService = widget.dashboardService ?? DashboardService();
    _loadInitialData();

    _liveTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _tasks.any((t) => t.isInProgress)) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _liveTicker?.cancel();
    _taskSearchController.dispose();
    _projectSearchController.dispose();
    _projectTaskSearchController.dispose();
    super.dispose();
  }

  String _formatRunningDuration(TaskModel task) {
    DateTime? startTime;
    if (task.startedAt != null && task.startedAt!.isNotEmpty) {
      startTime = DateTime.tryParse(task.startedAt!);
    }
    if (startTime == null && task.startDate != null && task.startDate!.isNotEmpty) {
      startTime = DateTime.tryParse(task.startDate!);
    }
    startTime ??= DateTime.now();
    final diff = DateTime.now().difference(startTime);
    if (diff.isNegative) return '00:00:01';
    final h = diff.inHours.toString().padLeft(2, '0');
    final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
    final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Future<void> _handleStartTask(TaskModel task) async {
    final nowIso = DateTime.now().toIso8601String();
    final optimistic = task.copyWith(status: 'in_progress', startedAt: nowIso, startDate: nowIso);
    setState(() {
      final idx = _tasks.indexWhere((t) => t.id == task.id);
      if (idx != -1) _tasks[idx] = optimistic;
    });
    try {
      final updated = await _taskService.updateTask(task.id, {
        'status': 'in_progress',
        'startDate': nowIso,
        'startedAt': nowIso,
      });
      if (mounted) {
        setState(() {
          final idx = _tasks.indexWhere((t) => t.id == task.id);
          if (idx != -1) _tasks[idx] = updated;
        });
      }
    } catch (_) {}
  }

  Future<void> _handleCompleteTask(TaskModel task) async {
    final now = DateTime.now();
    final nowIso = now.toIso8601String();
    final hour = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    final formattedTime = '${hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} $ampm';

    final optimistic = task.copyWith(
      status: 'done',
      completedAt: nowIso,
      completionTime: formattedTime,
    );
    setState(() {
      final idx = _tasks.indexWhere((t) => t.id == task.id);
      if (idx != -1) _tasks[idx] = optimistic;
    });
    try {
      final updated = await _taskService.updateTask(task.id, {
        'status': 'done',
        'completedAt': nowIso,
        'completionTime': formattedTime,
      });
      if (mounted) {
        setState(() {
          final idx = _tasks.indexWhere((t) => t.id == task.id);
          if (idx != -1) _tasks[idx] = updated;
        });
      }
    } catch (_) {}
  }

  Future<void> _handleIncompleteTask(TaskModel task) async {
    final optimistic = task.copyWith(status: 'not_completed');
    setState(() {
      final idx = _tasks.indexWhere((t) => t.id == task.id);
      if (idx != -1) _tasks[idx] = optimistic;
    });
    try {
      final updated = await _taskService.updateTask(task.id, {
        'status': 'not_completed',
      });
      if (mounted) {
        setState(() {
          final idx = _tasks.indexWhere((t) => t.id == task.id);
          if (idx != -1) _tasks[idx] = updated;
        });
      }
    } catch (_) {}
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
    return PopScope(
      canPop: _selectedProjectForDetail == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) {
          setState(() => _selectedProjectForDetail = null);
        }
      },
      child: Scaffold(
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
                  onPressed: () {
                    if (_activeMainSegment == 0) {
                      _showCreateTaskSheet();
                    } else if (_selectedProjectForDetail != null) {
                      _showCreateTaskSheet(
                        defaultProjectId: _selectedProjectForDetail?.id,
                        defaultProjectName: _selectedProjectForDetail?.name,
                      );
                    } else {
                      _showCreateProjectSheet();
                    }
                  },
                  backgroundColor: const Color(0xFF10B981),
                  icon: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
                  label: Text(
                    _activeMainSegment == 0
                        ? 'Add Task'
                        : (_selectedProjectForDetail != null ? 'Add Project Task' : 'Create Project'),
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
                  // 1. Pinned Top Header with Brand, Company Name, Back Arrow & Avatar
                  _buildHeader(),

                  // 2. Section Header Title & Subtitle (Dashboard Style)
                  _buildSectionHeader(),

                  // 3. Primary Segment Switcher: [General Task] vs [Projects]
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: _buildMainSegmentSwitcher(),
                  ),

                  // 4. Tab Body
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
      ),
    );
  }

  // 1. Top App Bar (Matches Company Dashboard App Bar Exactly)
  Widget _buildHeader() {
    final currentUser = widget.user ?? _loggedInUser;
    final companyName = (currentUser?.companyName?.isNotEmpty == true)
        ? currentUser!.companyName!
        : 'Enterprise Workspace';
    final userChar = (currentUser?.name.isNotEmpty == true)
        ? currentUser!.name[0].toUpperCase()
        : ((currentUser?.username.isNotEmpty == true) ? currentUser!.username[0].toUpperCase() : 'U');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Squircle Back Button
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: InkWell(
                onTap: () {
                  if (_selectedProjectForDetail != null) {
                    setState(() => _selectedProjectForDetail = null);
                    return;
                  }
                  if (widget.onBack != null) {
                    widget.onBack!();
                  } else if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF1F4839).withValues(alpha: 0.45),
                        const Color(0xFF102D21).withValues(alpha: 0.55),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.28)),
                  ),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
              ),
            ),
          ),

          // Center: Logo + "ReGen" Brand + Subtitle (Company Name)
          Row(
            children: [
              const BrandLogo(size: 28, borderRadius: 8),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'ReGen',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.2,
                      shadows: [
                        Shadow(offset: Offset(0, 1), blurRadius: 4, color: Colors.black54),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 130,
                    child: Text(
                      companyName,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF94A3B8),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Right: Refresh Button & Avatar in Squircle Containers
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: InkWell(
                    onTap: _loadInitialData,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFF1F4839).withValues(alpha: 0.45),
                            const Color(0xFF102D21).withValues(alpha: 0.55),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.28)),
                      ),
                      child: const Icon(
                        Icons.refresh_rounded,
                        color: Color(0xFF34D399),
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF1F4839).withValues(alpha: 0.45),
                      const Color(0xFF102D21).withValues(alpha: 0.55),
                    ],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.40)),
                ),
                alignment: Alignment.center,
                child: Text(
                  userChar,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Section Header (Matches Company Dashboard Sections Exactly)
  Widget _buildSectionHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'Tasks & Schedules',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.4,
              shadows: [Shadow(offset: Offset(0, 2), blurRadius: 4, color: Colors.black45)],
            ),
          ),
          SizedBox(height: 2),
          Text(
            'Manage tasks, projects & workforce schedules',
            style: TextStyle(fontSize: 12, color: Color(0xFFBACCC3)),
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
  // Unified to match Company Employee and Attendance Typing Box (Image 1)
  Widget _buildTaskSearchBar() {
    return _buildTypingBoxStyle(
      controller: _taskSearchController,
      hintText: 'Search by title, description, or assigned person...',
      prefixIcon: Icons.search_rounded,
      onChanged: (_) => setState(() {}),
      suffixWidget: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_taskSearchController.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _taskSearchController.clear();
                setState(() {});
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.close_rounded, size: 18, color: Color(0xFFBACCC3)),
              ),
            ),
          GestureDetector(
            onTap: _showTaskFilterSheet,
            child: const Padding(
              padding: EdgeInsets.only(left: 4, right: 2),
              child: Icon(Icons.filter_list_rounded, size: 20, color: Color(0xFFBACCC3)),
            ),
          ),
        ],
      ),
    );
  }

  void _showTaskFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final options = [
          {'label': 'All Tasks', 'count': _totalTaskCount, 'idx': 0, 'color': const Color(0xFF10B981), 'icon': Icons.assignment_rounded},
          {'label': 'Pending (Active)', 'count': _pendingCount, 'idx': 1, 'color': const Color(0xFF06B6D4), 'icon': Icons.schedule_rounded},
          {'label': 'Completed (Done)', 'count': _completedCount, 'idx': 2, 'color': const Color(0xFF10B981), 'icon': Icons.check_circle_outline_rounded},
          {'label': 'Incomplete', 'count': _incompleteCount, 'idx': 3, 'color': const Color(0xFFEF4444), 'icon': Icons.cancel_outlined},
        ];

        final media = MediaQuery.of(ctx);
        final maxHeight = media.size.height * 0.75;

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF042018),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.35), width: 1.0),
            ),
            child: SafeArea(
              top: false,
              bottom: true,
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Filter Tasks',
                            style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Color(0xFFBACCC3), size: 20),
                            onPressed: () => Navigator.pop(ctx),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Divider(color: Colors.white12, height: 1),
                      const SizedBox(height: 8),
                      ...options.map((opt) {
                        final idx = opt['idx'] as int;
                        final isSelected = _selectedTaskFilter == idx;
                        final optColor = opt['color'] as Color;
                        final count = opt['count'] as int;
                        final icon = opt['icon'] as IconData;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: InkWell(
                            onTap: () {
                              setState(() => _selectedTaskFilter = idx);
                              Navigator.pop(ctx);
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected ? optColor.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isSelected ? optColor : Colors.white12, width: isSelected ? 1.5 : 0.8),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(color: optColor.withValues(alpha: 0.20), borderRadius: BorderRadius.circular(8)),
                                    child: Icon(icon, color: optColor, size: 18),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      opt['label'] as String,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(color: optColor.withValues(alpha: 0.20), borderRadius: BorderRadius.circular(10)),
                                    child: Text(
                                      '$count',
                                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: optColor),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (isSelected)
                                    Icon(Icons.check_circle_rounded, color: optColor, size: 20)
                                  else
                                    const SizedBox(width: 20),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
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
    final isRunning = task.isInProgress;

    // Status colors
    final statusColor = isDone
        ? const Color(0xFF10B981)
        : isIncomplete
            ? const Color(0xFFEF4444)
            : (isRunning ? const Color(0xFF10B981) : const Color(0xFF06B6D4));

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

                  if (_canManage)
                    // Read-only status indicator for Company Management (Company cannot complete/incomplete once assigned)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDone
                            ? const Color(0xFF10B981).withValues(alpha: 0.20)
                            : (isRunning
                                ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                : (isIncomplete
                                    ? const Color(0xFFEF4444).withValues(alpha: 0.20)
                                    : const Color(0xFFF59E0B).withValues(alpha: 0.18))),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDone
                              ? const Color(0xFF10B981)
                              : (isRunning
                                  ? const Color(0xFF10B981)
                                  : (isIncomplete ? const Color(0xFFEF4444) : const Color(0xFFF59E0B))),
                          width: 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isDone
                                ? Icons.check_circle_rounded
                                : (isRunning
                                    ? Icons.timer_rounded
                                    : (isIncomplete ? Icons.cancel_rounded : Icons.schedule_rounded)),
                            size: 13,
                            color: isDone
                                ? const Color(0xFF34D399)
                                : (isRunning
                                    ? const Color(0xFF34D399)
                                    : (isIncomplete ? const Color(0xFFEF4444) : const Color(0xFFF59E0B))),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isDone
                                ? 'Completed${task.completionTime != null ? ' ${task.completionTime}' : ''}'
                                : (isRunning
                                    ? 'Running ${_formatRunningDuration(task)}'
                                    : (isIncomplete ? 'Incomplete' : 'Waiting to Start')),
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: isDone
                                  ? const Color(0xFF34D399)
                                  : (isRunning
                                      ? const Color(0xFF34D399)
                                      : (isIncomplete ? const Color(0xFFEF4444) : const Color(0xFFF59E0B))),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (!isIncomplete)
                    // Quick Action Buttons for Employee
                    if (task.isToDo)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 14),
                        label: const Text('Start', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _handleStartTask(task),
                      )
                    else if (isRunning)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF10B981)),
                            ),
                            child: Text(
                              _formatRunningDuration(task),
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF10B981)),
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => _handleCompleteTask(task),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check, size: 14, color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () => _handleIncompleteTask(task),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Color(0xFFEF4444),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                          ),
                        ],
                      )
                    else if (isDone)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF10B981)),
                        ),
                        child: Text(
                          'Done${task.completionTime != null ? ' (${task.completionTime})' : ''}',
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF34D399)),
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

                        // Action Buttons: Company View vs Employee View
                        if (_canManage)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isDone
                                      ? Icons.check_circle_rounded
                                      : (task.isInProgress ? Icons.timer_rounded : Icons.lock_outline_rounded),
                                  color: isDone ? const Color(0xFF10B981) : const Color(0xFFBACCC3),
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isDone
                                      ? 'Task Completed by Assignee'
                                      : (task.isInProgress
                                          ? 'Task in progress (running timer)'
                                          : 'Awaiting Assignee to start task'),
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFFBACCC3)),
                                ),
                              ],
                            ),
                          )
                        else if (!isIncomplete)
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                if (task.isToDo) {
                                  _handleStartTask(task);
                                } else if (task.isInProgress) {
                                  _handleCompleteTask(task);
                                } else {
                                  _toggleTaskCompletion(task);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDone ? const Color(0xFF0284C7) : const Color(0xFF10B981),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              ),
                              child: Text(
                                task.isToDo
                                    ? 'Start Task'
                                    : (isDone ? 'Reopen / Resume Task' : 'Mark as Completed'),
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
  void _showCreateTaskSheet({String? defaultProjectId, String? defaultProjectName}) {
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
                                  projectId: defaultProjectId,
                                  projectName: defaultProjectName,
                                  isProjectTask: defaultProjectId != null,
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
  // TAB 2: PROJECTS TAB (Below Search Only Project Name Displays, Details on Tap)
  // ===========================================================================
  Widget _buildProjectsTab() {
    if (_selectedProjectForDetail != null) {
      return _buildProjectDetailView(_selectedProjectForDetail!);
    }

    final projs = _filteredProjects;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
      children: [
        // 1. Unified Search Bar matching Company Employee typing box (Image 1)
        _buildTypingBoxStyle(
          controller: _projectSearchController,
          hintText: 'Search projects by name...',
          prefixIcon: Icons.search_rounded,
          onChanged: (_) => setState(() {}),
          suffixWidget: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_projectSearchController.text.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _projectSearchController.clear();
                    setState(() {});
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.close_rounded, size: 18, color: Color(0xFFBACCC3)),
                  ),
                ),
              GestureDetector(
                onTap: _showProjectFilterSheet,
                child: const Padding(
                  padding: EdgeInsets.only(left: 4, right: 2),
                  child: Icon(Icons.filter_list_rounded, size: 20, color: Color(0xFFBACCC3)),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // 2. Below search: ONLY Project Names display!
        if (projs.isEmpty)
          _buildEmptyProjectsPlaceholder()
        else
          ...projs.map((p) => _buildCompactProjectNameCard(p)),
      ],
    );
  }

  /// Clean, compact project card showing ONLY the project name
  Widget _buildCompactProjectNameCard(ProjectModel proj) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedProjectForDetail = proj;
            _projectTaskSearchController.clear();
            _selectedProjectTaskFilter = 0;
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF042018).withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.28), width: 1.1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.folder_copy_rounded, color: Color(0xFF34D399), size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  proj.name,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF34D399), size: 22),
            ],
          ),
        ),
      ),
    );
  }

  /// Full Project Details View with Members, Metrics, Search Box, Text Box, and Project Tasks
  Widget _buildProjectDetailView(ProjectModel proj) {
    final allProjectTasks = _tasks.where((t) => t.projectId == proj.id).toList();
    final totalCount = allProjectTasks.length;
    final pendingCount = allProjectTasks.where((t) => t.isPending).length;
    final completedCount = allProjectTasks.where((t) => t.isCompleted).length;
    final incompleteCount = allProjectTasks.where((t) => t.isIncomplete).length;

    // Filter by query and segment tab
    final query = _projectTaskSearchController.text.trim().toLowerCase();
    final filteredTasks = allProjectTasks.where((t) {
      if (_selectedProjectTaskFilter == 1 && !t.isPending) return false;
      if (_selectedProjectTaskFilter == 2 && !t.isCompleted) return false;
      if (_selectedProjectTaskFilter == 3 && !t.isIncomplete) return false;

      if (query.isNotEmpty) {
        final titleMatches = t.title.toLowerCase().contains(query);
        final descMatches = t.description?.toLowerCase().contains(query) ?? false;
        final assigneeMatches = _getAssigneeDisplayName(t.assignedTo).toLowerCase().contains(query);
        return titleMatches || descMatches || assigneeMatches;
      }
      return true;
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
      children: [
        // 1. Back Header to return to Project List
        Row(
          children: [
            InkWell(
              onTap: () => setState(() => _selectedProjectForDetail = null),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.30)),
                ),
                child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                proj.name,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
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
          ],
        ),

        const SizedBox(height: 14),

        // 2. Project Details Card (Description, Dates)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF042018).withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (proj.description.isNotEmpty) ...[
                Text(
                  proj.description,
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFFBACCC3)),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  const Icon(Icons.calendar_today_rounded, size: 13, color: Color(0xFF34D399)),
                  const SizedBox(width: 5),
                  Text(
                    proj.dueDate != null ? 'Due: ${proj.dueDate}' : 'Ongoing project',
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFFCBD5E1), fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  _buildPriorityBadge(proj.priority),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // 3. Team Members Section
        Text(
          'Project Members (${proj.assignedEmployees.length})',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white),
        ),
        const SizedBox(height: 8),
        if (proj.assignedEmployees.isEmpty)
          const Text('No members assigned yet.', style: TextStyle(fontSize: 11.5, color: Color(0xFFBACCC3)))
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: proj.assignedEmployees.map((empMap) {
                final empId = (empMap['userId'] ?? empMap['id'] ?? empMap['_id'] ?? '').toString();
                final rawName = (empMap['name'] ?? empMap['username'] ?? '').toString();
                final emp = _resolveEmployee(empId.isNotEmpty ? empId : rawName);
                final name = rawName.isNotEmpty ? rawName : _getAssigneeDisplayName(empId);
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Row(
                    children: [
                      _buildEmployeeAvatarMini(emp, name),
                      const SizedBox(width: 6),
                      Text(name, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

        const SizedBox(height: 14),

        // 4. Metrics Row (Matching General Task: Total Tasks, Pending, Completed, Incomplete)
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                title: 'Total Tasks',
                count: totalCount,
                icon: Icons.assignment_rounded,
                color: const Color(0xFF10B981),
                isSelected: _selectedProjectTaskFilter == 0,
                onTap: () => setState(() => _selectedProjectTaskFilter = 0),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricTile(
                title: 'Pending',
                count: pendingCount,
                icon: Icons.pending_actions_rounded,
                color: const Color(0xFF06B6D4),
                isSelected: _selectedProjectTaskFilter == 1,
                onTap: () => setState(() => _selectedProjectTaskFilter = 1),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricTile(
                title: 'Completed',
                count: completedCount,
                icon: Icons.check_circle_rounded,
                color: const Color(0xFF34D399),
                isSelected: _selectedProjectTaskFilter == 2,
                onTap: () => setState(() => _selectedProjectTaskFilter = 2),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricTile(
                title: 'Incomplete',
                count: incompleteCount,
                icon: Icons.cancel_outlined,
                color: const Color(0xFFEF4444),
                isSelected: _selectedProjectTaskFilter == 3,
                onTap: () => setState(() => _selectedProjectTaskFilter = 3),
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // 5. Search Box (Matching company employee search box style, Image 1)
        _buildTypingBoxStyle(
          controller: _projectTaskSearchController,
          hintText: 'Search tasks by title, desc, assignee...',
          prefixIcon: Icons.search_rounded,
          onChanged: (_) => setState(() {}),
          suffixWidget: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_projectTaskSearchController.text.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _projectTaskSearchController.clear();
                    setState(() {});
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.close_rounded, size: 18, color: Color(0xFFBACCC3)),
                  ),
                ),
              GestureDetector(
                onTap: _showProjectTaskFilterSheet,
                child: const Padding(
                  padding: EdgeInsets.only(left: 4, right: 2),
                  child: Icon(Icons.filter_list_rounded, size: 20, color: Color(0xFFBACCC3)),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // 6. Filter Tabs: [All] [Pending] [Completed] [Incomplete]
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildProjectTaskFilterTab('All ($totalCount)', 0),
              const SizedBox(width: 8),
              _buildProjectTaskFilterTab('Pending ($pendingCount)', 1),
              const SizedBox(width: 8),
              _buildProjectTaskFilterTab('Completed ($completedCount)', 2),
              const SizedBox(width: 8),
              _buildProjectTaskFilterTab('Incomplete ($incompleteCount)', 3),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // 7. Project Tasks List
        if (filteredTasks.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
            decoration: BoxDecoration(
              color: const Color(0xFF042018).withValues(alpha: 0.50),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              children: [
                const Icon(Icons.task_alt_rounded, size: 36, color: Color(0xFFBACCC3)),
                const SizedBox(height: 8),
                const Text('No tasks in this category for this project.', style: TextStyle(color: Color(0xFFBACCC3), fontSize: 13)),
                if (_canManage) ...[
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => _showCreateTaskSheet(defaultProjectId: proj.id, defaultProjectName: proj.name),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                    label: const Text('Add First Project Task', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ],
              ],
            ),
          )
        else ...[
          ...filteredTasks.map((t) => _buildTaskCard(t)),
          if (_canManage) ...[
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () => _showCreateTaskSheet(defaultProjectId: proj.id, defaultProjectName: proj.name),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
              label: const Text('Add Project Task', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.white)),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildProjectTaskFilterTab(String label, int index) {
    final isSelected = _selectedProjectTaskFilter == index;
    return InkWell(
      onTap: () => setState(() => _selectedProjectTaskFilter = index),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF10B981) : const Color(0xFF042018).withValues(alpha: 0.60),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? const Color(0xFF10B981) : const Color(0xFF34D399).withValues(alpha: 0.25),
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
    );
  }

  /// Typing box styled identically to Company Employee Typing Box (Image 1)
  Widget _buildTypingBoxStyle({
    required TextEditingController controller,
    required String hintText,
    required ValueChanged<String> onChanged,
    IconData prefixIcon = Icons.search_rounded,
    Widget? suffixWidget,
    VoidCallback? onClear,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF0A2218).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF34D399).withValues(alpha: 0.25),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(prefixIcon, color: const Color(0xFFCBD5E1), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Theme(
                  data: Theme.of(context).copyWith(
                    inputDecorationTheme: const InputDecorationTheme(
                      filled: false,
                      fillColor: Colors.transparent,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                    ),
                  ),
                  child: TextField(
                    controller: controller,
                    cursorColor: const Color(0xFF34D399),
                    style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      fillColor: Colors.transparent,
                      hintText: hintText,
                      hintStyle: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: onChanged,
                  ),
                ),
              ),
              if (suffixWidget != null)
                suffixWidget
              else if (controller.text.isNotEmpty)
                GestureDetector(
                  onTap: onClear ??
                      () {
                        controller.clear();
                        onChanged('');
                      },
                  child: const Icon(Icons.close_rounded, size: 18, color: Color(0xFFBACCC3)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showProjectFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final totalCount = _projects.length;
        final activeCount = _projects.where((p) => p.status.toLowerCase() != 'completed').length;
        final completedCount = _projects.where((p) => p.status.toLowerCase() == 'completed').length;
        final options = [
          {'label': 'All Projects', 'count': totalCount, 'color': const Color(0xFF10B981), 'icon': Icons.folder_rounded},
          {'label': 'Active Projects', 'count': activeCount, 'color': const Color(0xFF06B6D4), 'icon': Icons.pending_actions_rounded},
          {'label': 'Completed Projects', 'count': completedCount, 'color': const Color(0xFF10B981), 'icon': Icons.check_circle_outline_rounded},
        ];

        final media = MediaQuery.of(ctx);
        final maxHeight = media.size.height * 0.65;

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF042018),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.35), width: 1.0),
            ),
            child: SafeArea(
              top: false,
              bottom: true,
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Filter Projects',
                            style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Color(0xFFBACCC3), size: 20),
                            onPressed: () => Navigator.pop(ctx),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Divider(color: Colors.white12, height: 1),
                      const SizedBox(height: 8),
                      ...options.map((opt) {
                        final optColor = opt['color'] as Color;
                        final count = opt['count'] as int;
                        final icon = opt['icon'] as IconData;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: InkWell(
                            onTap: () {
                              Navigator.pop(ctx);
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white12, width: 0.8),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(color: optColor.withValues(alpha: 0.20), borderRadius: BorderRadius.circular(8)),
                                    child: Icon(icon, color: optColor, size: 18),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      opt['label'] as String,
                                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Colors.white),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(color: optColor.withValues(alpha: 0.20), borderRadius: BorderRadius.circular(10)),
                                    child: Text(
                                      '$count',
                                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: optColor),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showProjectTaskFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final options = [
          {'label': 'All Tasks', 'idx': 0, 'color': const Color(0xFF10B981), 'icon': Icons.assignment_rounded},
          {'label': 'Pending', 'idx': 1, 'color': const Color(0xFF06B6D4), 'icon': Icons.schedule_rounded},
          {'label': 'Completed', 'idx': 2, 'color': const Color(0xFF10B981), 'icon': Icons.check_circle_outline_rounded},
          {'label': 'Incomplete', 'idx': 3, 'color': const Color(0xFFEF4444), 'icon': Icons.cancel_outlined},
        ];

        final media = MediaQuery.of(ctx);
        final maxHeight = media.size.height * 0.70;

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF042018),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.35), width: 1.0),
            ),
            child: SafeArea(
              top: false,
              bottom: true,
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Filter Project Tasks',
                        style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Color(0xFFBACCC3), size: 20),
                        onPressed: () => Navigator.pop(ctx),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(color: Colors.white12, height: 1),
                  const SizedBox(height: 8),
                  ...options.map((opt) {
                    final idx = opt['idx'] as int;
                    final isSelected = _selectedProjectTaskFilter == idx;
                    final optColor = opt['color'] as Color;
                    final icon = opt['icon'] as IconData;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: InkWell(
                        onTap: () {
                          setState(() => _selectedProjectTaskFilter = idx);
                          Navigator.pop(ctx);
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? optColor.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isSelected ? optColor : Colors.white12, width: isSelected ? 1.5 : 0.8),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(color: optColor.withValues(alpha: 0.20), borderRadius: BorderRadius.circular(8)),
                                child: Icon(icon, color: optColor, size: 18),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  opt['label'] as String,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              if (isSelected) Icon(Icons.check_circle_rounded, color: optColor, size: 20),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      );
    },
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
