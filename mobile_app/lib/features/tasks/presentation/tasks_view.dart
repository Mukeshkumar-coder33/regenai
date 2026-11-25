import '../../notifications/data/notification_model.dart';
import '../../notifications/data/notification_service.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../../core/storage/session_storage.dart';
import '../../auth/data/user_model.dart';
import '../../dashboard/data/dashboard_service.dart';
import '../data/project_model.dart';
import '../data/task_model.dart';
import '../data/task_service.dart';
import '../../messenger/data/call_notification_service.dart';
import '../../messenger/data/messenger_socket_service.dart';
import '../../../core/theme/celadon_colors.dart';

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
  final bool embedded;
  final NotificationModel? initialNotification;

  const TasksView({
    super.key,
    this.user,
    this.onBack,
    this.onOpenDrawer,
    this.taskService,
    this.dashboardService,
    this.embedded = false,
    this.initialNotification,
  });

  /// Automatically computes End Date & Due Time from Start Date and Duration
  static Map<String, String> computeEndDateTime(
    String startIso,
    num durationValue,
    String durationUnit,
  ) {
    return _TasksViewState.computeEndDateTime(
      startIso,
      durationValue,
      durationUnit,
    );
  }

  @override
  State<TasksView> createState() => _TasksViewState();
}

class _TasksViewState extends State<TasksView> {
  late final TaskService _taskService;
  late final DashboardService _dashboardService;
  final NotificationService _notificationService = NotificationService();

  UserModel? _loggedInUser;
  bool _isLoading = true;
  String? _errorMessage;

  bool get _canManage =>
      (widget.user?.isSuperAdmin == true ||
          widget.user?.isCompanyAdmin == true) ||
      (_loggedInUser?.isSuperAdmin == true ||
          _loggedInUser?.isCompanyAdmin == true);

  // 0: General Task, 1: Projects
  int _activeMainSegment = 0;

  // General Tasks Filter: 0: All, 1: Pending (Active), 2: Completed (Done), 3: Incomplete
  int _selectedTaskFilter = 0;

  final TextEditingController _taskSearchController = TextEditingController();
  final TextEditingController _projectSearchController =
      TextEditingController();
  final TextEditingController _projectTaskSearchController =
      TextEditingController();

  List<TaskModel> _tasks = [];
  List<ProjectModel> _projects = [];
  List<UserModel> _teamMembers = [];

  // Selected project for full details view
  ProjectModel? _selectedProjectForDetail;
  ProjectModel? _overviewSelectedProject;
  int _selectedProjectTaskFilter =
      0; // 0: All, 1: Pending, 2: Completed, 3: Incomplete

  Timer? _liveTicker;
  StreamSubscription? _socketNotifSub;
  StreamSubscription? _socketTaskSub;
  final Set<String> _handledNotificationIds = <String>{};
  BuildContext? _activeDialogContext;

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

    _socketNotifSub =
        MessengerSocketService.instance.onNotification.listen((data) {
      if (mounted) {
        _loadInitialData();
        try {
          final notif = NotificationModel.fromJson(data);
          final currentUid = widget.user?.userId.isNotEmpty == true ? widget.user!.userId : widget.user?.id;

          // 1. Never show if addressed to another user
          if (notif.userId.isNotEmpty && currentUid != null && notif.userId != currentUid) {
            return;
          }
          // 2. Never show if originated by ourselves
          if (notif.senderId != null && notif.senderId!.isNotEmpty && currentUid != null && notif.senderId == currentUid) {
            return;
          }
          // 3. Deduplicate by notification ID
          if (_handledNotificationIds.contains(notif.id)) {
            return;
          }
          _handledNotificationIds.add(notif.id);

          if (notif.isTask ||
              notif.type.contains('task') ||
              notif.type.contains('daily_progress') ||
              notif.type.contains('completion') ||
              notif.type.contains('extension')) {
            _handleNotificationPopup(notif);
          }
        } catch (_) {}
      }
    });
    _socketTaskSub =
        MessengerSocketService.instance.onTaskChange.listen((_) {
      if (mounted) _loadInitialData();
    });
  }

  @override
  void didUpdateWidget(covariant TasksView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldUid = oldWidget.user?.userId.isNotEmpty == true ? oldWidget.user!.userId : oldWidget.user?.id;
    final newUid = widget.user?.userId.isNotEmpty == true ? widget.user!.userId : widget.user?.id;
    if (oldUid != newUid || oldWidget.user?.role != widget.user?.role || oldWidget.user?.token != widget.user?.token) {
      _taskService = widget.taskService ?? TaskService();
      _dashboardService = widget.dashboardService ?? DashboardService();
      _loadInitialData();
    }
  }

  @override
  void dispose() {
    _liveTicker?.cancel();
    _socketNotifSub?.cancel();
    _socketTaskSub?.cancel();
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
    if (startTime == null &&
        task.startDate != null &&
        task.startDate!.isNotEmpty) {
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
    final optimistic = task.copyWith(
      status: 'in_progress',
      startedAt: nowIso,
      startDate: nowIso,
    );
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
    _showCompletionReportSheet(task);
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

  static String _formatDisplayDate(DateTime dt) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final dayName = days[dt.weekday - 1];
    final monthName = months[dt.month - 1];
    return '$dayName, $monthName ${dt.day}, ${dt.year}';
  }

  static String? _formatCleanDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final trimmed = raw.trim();
    final dt = DateTime.tryParse(trimmed);
    if (dt != null) {
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    }
    if (trimmed.contains('T')) {
      return trimmed.split('T')[0];
    }
    if (trimmed.length > 24) {
      return trimmed.substring(0, 10);
    }
    return trimmed;
  }

  static String _formatCleanDateTime(String raw) {
    final dt = DateTime.tryParse(raw.trim());
    if (dt != null) {
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final dateStr = '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
      final timeStr = _formatDisplayTime(dt);
      return '$dateStr at $timeStr';
    }
    return _formatCleanDate(raw) ?? raw;
  }

  static String _formatDisplayTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $ampm';
  }

  Future<void> _downloadAttachment(
    TaskModel task,
    TaskAttachmentModel doc,
  ) async {
    try {
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        await [Permission.storage].request();
      }

      Uint8List bytes;
      if (doc.data != null && doc.data!.isNotEmpty) {
        bytes = base64Decode(doc.data!);
      } else if (doc.url != null && doc.url!.isNotEmpty) {
        final uri = Uri.parse(doc.url!);
        final request = await HttpClient().getUrl(uri);
        final response = await request.close();
        final chunks = <int>[];
        await for (var chunk in response) {
          chunks.addAll(chunk);
        }
        bytes = Uint8List.fromList(chunks);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No document data available to download'),
              backgroundColor: CeladonColors.error,
            ),
          );
        }
        return;
      }

      String targetDir;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (await downloadDir.exists()) {
          targetDir = downloadDir.path;
        } else {
          final extDir = await getExternalStorageDirectory();
          targetDir =
              extDir?.path ?? (await getApplicationDocumentsDirectory()).path;
        }
      } else {
        final appDir = await getApplicationDocumentsDirectory();
        targetDir = appDir.path;
      }

      final safeName = doc.name.replaceAll(RegExp(r'[^\w\.\-]'), '_');
      final targetFile = File('$targetDir/$safeName');
      await targetFile.writeAsBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: CeladonColors.primary,
            content: Text('Saved to device storage: ${targetFile.path}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: CeladonColors.error,
            content: Text('Error downloading file: $e'),
          ),
        );
      }
    }
  }

  void _showDailyProgressSheet(TaskModel task) {
    int percentage = task.progressPercentage.clamp(0, 100);
    final notesCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final media = MediaQuery.of(ctx);
          return Container(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 18,
              bottom: media.viewInsets.bottom + 20,
            ),
            decoration: BoxDecoration(
              color: CeladonColors.cardBackground,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border.all(color: CeladonColors.border, width: 1.2),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Daily Progress Update',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: CeladonColors.textPrimary,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: CeladonColors.textMuted,
                        ),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(color: CeladonColors.divider, height: 1),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Completion Percentage',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: CeladonColors.textSecondary,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: CeladonColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: CeladonColors.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          '$percentage%',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: CeladonColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Slider(
                    value: percentage.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: '$percentage%',
                    activeColor: CeladonColors.primary,
                    inactiveColor: CeladonColors.divider,
                    onChanged: (val) {
                      setSheetState(() => percentage = val.toInt());
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildInputLabel('Daily Progress Notes / Summary'),
                  _buildDarkTextField(
                    controller: notesCtrl,
                    hintText:
                        'Describe today\'s work and milestones reached...',
                    maxLines: 3,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () async {
                      final notes = notesCtrl.text.trim();
                      final user = widget.user ?? _loggedInUser;
                      final nav = Navigator.of(ctx);
                      final messenger = ScaffoldMessenger.of(context);

                      try {
                        final updated = await _taskService.submitProgressUpdate(
                          task: task,
                          updateText: notes.isNotEmpty
                              ? notes
                              : 'Updated progress to $percentage%',
                          percentage: percentage,
                          employeeName: user?.name ?? user?.username,
                          employeeId: user?.userId ?? user?.id,
                        );
                        CallNotificationService.instance.showTaskAlert(
                          id: 'prog_${task.id}_${DateTime.now().millisecondsSinceEpoch}',
                          title: 'Task Progress Updated',
                          body: '${user?.name ?? 'Employee'} updated "${task.title}" to $percentage%${notes.isNotEmpty ? ': $notes' : ''}',
                        );
                        if (mounted) {
                          final guaranteed = updated.copyWith(
                            progressPercentage: percentage,
                          );
                          setState(() {
                            final idx = _tasks.indexWhere(
                              (t) =>
                                  t.id == task.id ||
                                  (t.mongoId != null &&
                                      t.mongoId == task.mongoId),
                            );
                            if (idx != -1) {
                              _tasks[idx] = guaranteed;
                            } else {
                              _tasks.add(guaranteed);
                            }
                          });
                          nav.pop();
                          messenger.showSnackBar(
                            const SnackBar(
                              backgroundColor: CeladonColors.primary,
                              content: Text(
                                'Daily progress updated & company notified!',
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(
                            backgroundColor: CeladonColors.error,
                            content: Text('Failed to update progress: $e'),
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CeladonColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Submit Daily Update',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        fontSize: 14,
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

  void _showCompletionReportSheet(TaskModel task) {
    final now = DateTime.now();
    DateTime startDt = now;
    if (task.startedAt != null && task.startedAt!.isNotEmpty) {
      startDt = DateTime.tryParse(task.startedAt!) ?? now;
    } else if (task.startDate != null && task.startDate!.isNotEmpty) {
      startDt = DateTime.tryParse(task.startDate!) ?? now;
    }

    final startDay = _formatDisplayDate(startDt);
    final startTime = _formatDisplayTime(startDt);
    final endDay = _formatDisplayDate(now);
    final endTime = _formatDisplayTime(now);

    final duration = now.difference(startDt);
    final hours = duration.inHours;
    final mins = duration.inMinutes % 60;
    final workingTimeStr =
        hours > 0 ? '$hours hrs $mins mins' : '$mins mins';

    final user = widget.user ?? _loggedInUser;
    final empName = user?.name.isNotEmpty == true
        ? user!.name
        : (user?.username ?? _getAssigneeDisplayName(task.assignedTo));
    final empId = user?.userId.isNotEmpty == true
        ? user!.userId
        : (user?.id ?? task.assignedTo ?? 'EMP-01');

    final notesCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final media = MediaQuery.of(ctx);
          return Container(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 18,
              bottom: media.viewInsets.bottom + 20,
            ),
            decoration: BoxDecoration(
              color: CeladonColors.cardBackground,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border.all(color: CeladonColors.border, width: 1.2),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Task Completion Report',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: CeladonColors.textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: CeladonColors.textMuted,
                          ),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const Divider(color: CeladonColors.divider, height: 1),
                    const SizedBox(height: 14),

                    // Auto-populated summary card
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: CeladonColors.searchBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: CeladonColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildDetailRow('Employee Name', empName),
                          _buildDetailRow('Employee ID', empId),
                          const Divider(
                            color: CeladonColors.divider,
                            height: 12,
                          ),
                          _buildDetailRow('Start Day', startDay),
                          _buildDetailRow('Start Time', startTime),
                          const Divider(
                            color: CeladonColors.divider,
                            height: 12,
                          ),
                          _buildDetailRow('End Day', endDay),
                          _buildDetailRow('End Time', endTime),
                          const Divider(
                            color: CeladonColors.divider,
                            height: 12,
                          ),
                          _buildDetailRow(
                            'Total Working Time',
                            workingTimeStr,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    _buildInputLabel('Work Summary / Completion Notes *'),
                    _buildDarkTextField(
                      controller: notesCtrl,
                      hintText:
                          'Summarize work completed, results, or notes for the company...',
                      maxLines: 4,
                    ),
                    const SizedBox(height: 20),

                    ElevatedButton(
                      onPressed: () async {
                        final text = notesCtrl.text.trim();
                        if (text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: CeladonColors.error,
                              content: Text(
                                'Please enter completion notes / summary',
                              ),
                            ),
                          );
                          return;
                        }

                        final nav = Navigator.of(ctx);
                        final messenger = ScaffoldMessenger.of(context);

                        final report = TaskCompletionReportModel(
                          reportText: text,
                          submittedAt: now.toIso8601String(),
                          startDay: startDay,
                          startTime: startTime,
                          endDay: endDay,
                          endTime: endTime,
                          employeeName: empName,
                          employeeId: empId,
                          workingTime: workingTimeStr,
                        );

                        try {
                          final updated =
                              await _taskService.submitCompletionReport(
                            id: task.id,
                            report: report,
                          );
                          CallNotificationService.instance.showTaskAlert(
                            id: 'comp_${task.id}_${DateTime.now().millisecondsSinceEpoch}',
                            title: 'Task Completion Report',
                            body: 'Task "${task.title}" completed by $empName: $text',
                          );
                          if (mounted) {
                            setState(() {
                              final idx = _tasks.indexWhere(
                                (t) => t.id == task.id,
                              );
                              if (idx != -1) _tasks[idx] = updated;
                            });
                            nav.pop();
                            messenger.showSnackBar(
                              const SnackBar(
                                backgroundColor: CeladonColors.primary,
                                content: Text(
                                  'Completion report submitted & task completed!',
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          messenger.showSnackBar(
                            SnackBar(
                              backgroundColor: CeladonColors.error,
                              content: Text('Failed to submit report: $e'),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CeladonColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Submit Final Report & Complete',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
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

  void _showExtensionRequestSheet(TaskModel task) {
    final now = DateTime.now();
    String requestedDate =
        task.endDate ?? task.dueDate ?? now.toIso8601String().split('T')[0];
    String requestedTime = task.dueTime ?? '05:00 PM';
    final reasonCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final media = MediaQuery.of(ctx);
          return Container(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 18,
              bottom: media.viewInsets.bottom + 20,
            ),
            decoration: BoxDecoration(
              color: CeladonColors.cardBackground,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border.all(color: CeladonColors.border, width: 1.2),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Request Deadline Extension',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: CeladonColors.textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: CeladonColors.textMuted,
                          ),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const Divider(color: CeladonColors.divider, height: 1),
                    const SizedBox(height: 14),

                    _buildInputLabel('Current Deadline'),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: CeladonColors.searchBackground,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: CeladonColors.border),
                      ),
                      child: Text(
                        '${task.endDate ?? task.dueDate ?? 'Not set'} at ${task.dueTime ?? 'EOD'}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: CeladonColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildInputLabel('Requested New Date *'),
                              InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate:
                                        now.add(const Duration(days: 1)),
                                    firstDate: now,
                                    lastDate:
                                        now.add(const Duration(days: 180)),
                                  );
                                  if (picked != null) {
                                    setSheetState(() {
                                      requestedDate = picked
                                          .toIso8601String()
                                          .split('T')[0];
                                    });
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: CeladonColors.inputBackground,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: CeladonColors.inputBorder,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.calendar_month_rounded,
                                        size: 16,
                                        color: CeladonColors.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          requestedDate,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color:
                                                CeladonColors.textPrimary,
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
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildInputLabel('Requested Time *'),
                              InkWell(
                                onTap: () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: const TimeOfDay(
                                      hour: 17,
                                      minute: 0,
                                    ),
                                  );
                                  if (picked != null) {
                                    final hour = picked.hourOfPeriod == 0
                                        ? 12
                                        : picked.hourOfPeriod;
                                    final ampm =
                                        picked.period == DayPeriod.pm
                                            ? 'PM'
                                            : 'AM';
                                    final timeStr =
                                        '${hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')} $ampm';
                                    setSheetState(() {
                                      requestedTime = timeStr;
                                    });
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: CeladonColors.inputBackground,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: CeladonColors.inputBorder,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.access_time_rounded,
                                        size: 16,
                                        color: CeladonColors.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          requestedTime,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color:
                                                CeladonColors.textPrimary,
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
                      ],
                    ),
                    const SizedBox(height: 14),

                    _buildInputLabel('Reason for Extra Time *'),
                    _buildDarkTextField(
                      controller: reasonCtrl,
                      hintText:
                          'Explain why more time is needed to complete the task...',
                      maxLines: 3,
                    ),
                    const SizedBox(height: 20),

                    ElevatedButton(
                      onPressed: () async {
                        final reason = reasonCtrl.text.trim();
                        if (reason.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: CeladonColors.error,
                              content: Text(
                                'Please state the reason for extra time',
                              ),
                            ),
                          );
                          return;
                        }

                        final nav = Navigator.of(ctx);
                        final messenger = ScaffoldMessenger.of(context);

                        final extReq = TaskExtensionRequestModel(
                          requestedDueDate: requestedDate,
                          requestedDueTime: requestedTime,
                          reason: reason,
                          status: 'pending',
                          requestedAt: DateTime.now().toIso8601String(),
                        );

                        try {
                          final updated =
                              await _taskService.requestDeadlineExtension(
                            id: task.id,
                            request: extReq,
                          );
                          if (mounted) {
                            setState(() {
                              final idx = _tasks.indexWhere(
                                (t) => t.id == task.id,
                              );
                              if (idx != -1) _tasks[idx] = updated;
                            });
                            nav.pop();
                            messenger.showSnackBar(
                              const SnackBar(
                                backgroundColor: CeladonColors.primary,
                                content: Text(
                                  'Deadline extension requested & manager notified!',
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          messenger.showSnackBar(
                            SnackBar(
                              backgroundColor: CeladonColors.error,
                              content: Text('Failed to submit request: $e'),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CeladonColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Send Extension Request',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
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

  Future<void> _handleReviewExtension(
    TaskModel task,
    bool accept,
    BuildContext modalCtx,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final modalNav = Navigator.of(modalCtx);
    if (modalNav.canPop()) {
      modalNav.pop();
    }
    try {
      final updated = await _taskService.reviewDeadlineExtension(
        task: task,
        accept: accept,
        companyResponse: accept
            ? 'Deadline extended by company manager'
            : 'Extension rejected by company manager',
      );
      if (mounted) {
        setState(() {
          final idx = _tasks.indexWhere((t) => t.id == task.id);
          if (idx != -1) _tasks[idx] = updated;
        });
        _loadInitialData();
        messenger.showSnackBar(
          SnackBar(
            backgroundColor:
                accept ? CeladonColors.primary : CeladonColors.error,
            content: Text(
              accept
                  ? 'Deadline extension approved and updated!'
                  : 'Deadline extension rejected.',
            ),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: CeladonColors.error,
          content: Text('Failed to update extension: $e'),
        ),
      );
    }
  }

  Widget _buildExtensionRequestCard(TaskModel task, BuildContext modalCtx) {
    final ext = task.extensionRequest;
    if (ext == null || ext.status == 'none') return const SizedBox.shrink();

    final isPending = ext.status == 'pending';
    final isAccepted = ext.status == 'accepted';

    Color bgColor = isPending
        ? const Color(0xFFFEF3C7)
        : (isAccepted ? CeladonColors.lightGreen : const Color(0xFFFEF2F2));
    Color borderColor = isPending
        ? const Color(0xFFF59E0B)
        : (isAccepted ? CeladonColors.primary : CeladonColors.error);
    Color textColor = isPending
        ? const Color(0xFFB45309)
        : (isAccepted ? CeladonColors.primary : CeladonColors.error);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPending
                    ? Icons.hourglass_top_rounded
                    : (isAccepted
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded),
                color: borderColor,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                isPending
                    ? 'Deadline Extension Requested'
                    : (isAccepted
                        ? 'Extension Approved'
                        : 'Extension Rejected'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Requested Deadline: ${ext.requestedDueDate ?? 'Date'} (${ext.requestedDueTime ?? 'Time'})',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: CeladonColors.textPrimary,
            ),
          ),
          if (ext.reason != null && ext.reason!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Reason: ${ext.reason!}',
              style: const TextStyle(
                fontSize: 11.5,
                color: CeladonColors.textSecondary,
              ),
            ),
          ],
          if (ext.companyResponse != null &&
              ext.companyResponse!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Company Response: ${ext.companyResponse!}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],

          // If Company Owner and pending: Show Accept and Reject buttons
          if (_canManage && isPending) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () =>
                        _handleReviewExtension(task, true, modalCtx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CeladonColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Accept & Extend',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        _handleReviewExtension(task, false, modalCtx),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: CeladonColors.error),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Reject',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: CeladonColors.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompletionReportCard(TaskCompletionReportModel report) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CeladonColors.searchBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: CeladonColors.primary.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(
                Icons.assignment_turned_in_rounded,
                color: CeladonColors.primary,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Task Completion Report',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: CeladonColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildDetailRow('Employee Name', report.employeeName ?? 'Assignee'),
          if (report.employeeId != null)
            _buildDetailRow('Employee ID', report.employeeId!),
          const Divider(color: CeladonColors.divider, height: 12),
          _buildDetailRow(
            'Start Day & Time',
            '${report.startDay} • ${report.startTime}',
          ),
          _buildDetailRow(
            'End Day & Time',
            '${report.endDay} • ${report.endTime}',
          ),
          if (report.workingTime != null)
            _buildDetailRow('Total Working Time', report.workingTime!),
          const Divider(color: CeladonColors.divider, height: 12),
          const Text(
            'Work Summary & Report:',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: CeladonColors.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            report.reportText,
            style: const TextStyle(
              fontSize: 12.5,
              color: CeladonColors.textPrimary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
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
        _taskService
            .getTasks(isSuperAdmin: user?.isSuperAdmin ?? false)
            .catchError((_) => <TaskModel>[]),
        _taskService.getProjects().catchError((_) => <ProjectModel>[]),
        _dashboardService
            .getUsers(isSuperAdmin: user?.isSuperAdmin ?? false)
            .catchError((_) => <UserModel>[]),
      ]);

      if (mounted) {
        setState(() {
          _tasks = results[0] as List<TaskModel>;
          _projects = results[1] as List<ProjectModel>;
          _teamMembers = results[2] as List<UserModel>;
          _isLoading = false;
        });

        if (widget.initialNotification != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _handleNotificationPopup(widget.initialNotification!);
          });
        }
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
  List<TaskModel> get _generalTasks =>
      _tasks.where((t) => !t.isProjectTask).toList();

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
        final uid =
            (currentUser.userId.isNotEmpty
                    ? currentUser.userId
                    : currentUser.id)
                .toLowerCase();
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
        final descMatch = (task.description ?? '').toLowerCase().contains(
          query,
        );
        final assignedPersonName = _getAssigneeDisplayName(task.assignedTo)
            .toLowerCase();
        final assignedId = (task.assignedTo ?? '').toLowerCase();
        final personMatch =
            assignedPersonName.contains(query) || assignedId.contains(query);
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
          final mName = (m['name'] ?? m['username'] ?? '')
              .toString()
              .toLowerCase();
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
      final isToday =
          startDate.year == now.year &&
          startDate.month == now.month &&
          startDate.day == now.day;
      final base = isToday
          ? now
          : DateTime(startDate.year, startDate.month, startDate.day, 9, 0);
      final target = base.add(Duration(minutes: (durVal * 60).round()));
      final endStr =
          '${target.year.toString().padLeft(4, '0')}-${target.month.toString().padLeft(2, '0')}-${target.day.toString().padLeft(2, '0')}';
      final dueTimeStr =
          '${target.hour.toString().padLeft(2, '0')}:${target.minute.toString().padLeft(2, '0')}';
      return {'endDate': endStr, 'dueTime': dueTimeStr};
    } else if (durationUnit.toLowerCase() == 'minutes') {
      final now = DateTime.now();
      final target = now.add(Duration(minutes: durVal.round()));
      final endStr =
          '${target.year.toString().padLeft(4, '0')}-${target.month.toString().padLeft(2, '0')}-${target.day.toString().padLeft(2, '0')}';
      final dueTimeStr =
          '${target.hour.toString().padLeft(2, '0')}:${target.minute.toString().padLeft(2, '0')}';
      return {'endDate': endStr, 'dueTime': dueTimeStr};
    } else {
      // Days
      final daysToAdd = durVal >= 1 ? durVal.round() : 1;
      final target = startDate.add(Duration(days: daysToAdd));
      final endStr =
          '${target.year.toString().padLeft(4, '0')}-${target.month.toString().padLeft(2, '0')}-${target.day.toString().padLeft(2, '0')}';
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
        _tasks[idx] = task.copyWith(
          status: nextCompleted ? 'done' : 'in_progress',
        );
      }
    });

    try {
      final updated = await _taskService.toggleTaskComplete(
        task.id,
        nextCompleted,
      );
      if (mounted) {
        setState(() {
          final idx = _tasks.indexWhere((t) => t.id == task.id);
          if (idx != -1) _tasks[idx] = updated;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: nextCompleted
                ? CeladonColors.primary
                : const Color(0xFF3186C8),
            content: Text(
              nextCompleted
                  ? 'Task marked as completed'
                  : 'Task resumed to In Progress',
            ),
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
          side: BorderSide(color: CeladonColors.primary.withValues(alpha: 0.3)),
        ),
        title: const Text(
          'Delete Task',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Are you sure you want to delete "${task.title}"?',
          style: const TextStyle(color: Color(0xFFBACCC3)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF829089)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFFEF4444),
            content: Text('Task deleted successfully'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Error: $e'),
          ),
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
        backgroundColor: CeladonColors.background,
        floatingActionButton:
            (_canManage &&
                _activeMainSegment != 1 &&
                _overviewSelectedProject == null)
            ? Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: CeladonColors.primary.withValues(alpha: 0.35),
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
                  backgroundColor: CeladonColors.primary,
                  icon: const Icon(
                    Icons.add_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  label: Text(
                    _activeMainSegment == 0
                        ? 'Add Task'
                        : (_selectedProjectForDetail != null
                              ? 'Add Project Task'
                              : 'Create Project'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              )
            : null,
        body: Stack(
          children: [
            // Background: Clean Solid App Canvas
            Positioned.fill(child: Container(color: CeladonColors.background)),

            SafeArea(
              top: !widget.embedded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Section Header Title & Subtitle with Back Arrow & Refresh Button
                  _buildSectionHeader(),

                  // 3. Primary Segment Switcher: [General Task] vs [Projects]
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: _buildMainSegmentSwitcher(),
                  ),

                  // 4. Tab Body
                  Expanded(
                    child: _isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: CeladonColors.primary,
                            ),
                          )
                        : _errorMessage != null
                        ? _buildErrorState()
                        : RefreshIndicator(
                            onRefresh: _loadInitialData,
                            color: CeladonColors.primary,
                            child: _activeMainSegment == 0
                                ? _buildGeneralTasksTab()
                                : (_activeMainSegment == 1
                                      ? _buildOverviewTab()
                                      : _buildProjectsTab()),
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

  // Single Unified Header with Back Button, Title & Refresh (Messenger Style)
  Widget _buildSectionHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: CeladonColors.textPrimary,
              size: 22,
            ),
            tooltip: 'Back',
            onPressed: () {
              if (_selectedProjectForDetail != null) {
                setState(() => _selectedProjectForDetail = null);
                return;
              }
              if (widget.onBack != null) {
                widget.onBack!();
              } else if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else if (widget.onOpenDrawer != null) {
                widget.onOpenDrawer!();
              }
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'Tasks',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: CeladonColors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Track project tasks and team deliverables.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: CeladonColors.textMuted,
                    height: 1.25,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Spacer(),
          IconButton(
            tooltip: 'Refresh tasks',
            icon: const Icon(
              Icons.refresh_rounded,
              color: CeladonColors.primary,
              size: 21,
            ),
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
        color: CeladonColors.cardBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: CeladonColors.border, width: 1.0),
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
          const SizedBox(width: 4),
          Expanded(
            child: _buildSegmentPill(
              title: 'Overview',
              icon: Icons.dashboard_outlined,
              isSelected: _activeMainSegment == 1,
              badgeCount: _totalTaskCount + _projects.length,
              onTap: () => setState(() => _activeMainSegment = 1),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildSegmentPill(
              title: 'Projects',
              icon: Icons.folder_copy_rounded,
              isSelected: _activeMainSegment == 2,
              badgeCount: _projects.length,
              onTap: () => setState(() => _activeMainSegment = 2),
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
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected ? CeladonColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: CeladonColors.primary.withValues(alpha: 0.30),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : CeladonColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected
                      ? Colors.white
                      : CeladonColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.25)
                    : CeladonColors.lightGreen,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$badgeCount',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : CeladonColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 0: OVERVIEW TAB (Executive Summary for General Tasks & Projects)
  // ===========================================================================
  Widget _buildOverviewTab() {
    if (_overviewSelectedProject != null) {
      return _buildProjectOverviewDetailView(_overviewSelectedProject!);
    }

    final completedRate = _totalTaskCount > 0
        ? ((_completedCount / _totalTaskCount) * 100).round()
        : 0;

    final inProgressProjects = _projects
        .where((p) => p.status.toLowerCase() != 'completed')
        .length;
    final completedProjects = _projects
        .where((p) => p.status.toLowerCase() == 'completed')
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
      children: [
        // 1. General Tasks Summary Section
        _buildOverviewSectionHeader(
          title: 'General Tasks Overview',
          subtitle: 'Operational task assignments & progress',
          icon: Icons.assignment_rounded,
          actionLabel: '',
          onAction: () {},
        ),
        const SizedBox(height: 10),

        // 4 Metric Counter Cards (Image 3)
        _buildTaskMetricsGrid(
          onTapOverride: (filterIdx) {
            setState(() {
              _selectedTaskFilter = filterIdx;
              _activeMainSegment = 0;
            });
          },
        ),
        const SizedBox(height: 12),

        // Task Completion Rate Banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Task Completion Rate',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: CeladonColors.textPrimary,
                    ),
                  ),
                  Text(
                    '$completedRate%',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: CeladonColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _totalTaskCount > 0
                      ? (_completedCount / _totalTaskCount)
                      : 0.0,
                  minHeight: 7,
                  backgroundColor: CeladonColors.border,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    CeladonColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // 2. Projects Overview Section
        _buildOverviewSectionHeader(
          title: 'Project Overview',
          subtitle: 'Active deliverables & team allocations',
          icon: Icons.folder_copy_rounded,
          actionLabel: '',
          onAction: () {},
        ),
        const SizedBox(height: 10),

        // Project Metric Counters Row
        Row(
          children: [
            Expanded(
              child: _buildProjectOverviewTile(
                title: 'Total Projects',
                count: _projects.length,
                icon: Icons.folder_rounded,
                color: CeladonColors.primary,
                onTap: () {},
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildProjectOverviewTile(
                title: 'In Progress',
                count: inProgressProjects,
                icon: Icons.timelapse_rounded,
                color: const Color(0xFF0284C7),
                onTap: () {},
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildProjectOverviewTile(
                title: 'Completed',
                count: completedProjects,
                icon: Icons.verified_rounded,
                color: const Color(0xFF10B981),
                onTap: () {},
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Projects List (Clicking any project reveals full project overview details)
        if (_projects.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Text(
              'No projects available',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF475569)),
            ),
          )
        else
          ..._projects.map((proj) => _buildProjectOverviewCard(proj)),
      ],
    );
  }

  Widget _buildOverviewSectionHeader({
    required String title,
    required String subtitle,
    required IconData icon,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: CeladonColors.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 16, color: CeladonColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: CeladonColors.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (actionLabel.isNotEmpty) ...[
          const SizedBox(width: 8),
          InkWell(
            onTap: onAction,
            child: Text(
              actionLabel,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: CeladonColors.primary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildProjectOverviewTile({
    required String title,
    required int count,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: CeladonColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectOverviewCard(ProjectModel proj) {
    return InkWell(
      onTap: () => setState(() => _overviewSelectedProject = proj),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
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
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: CeladonColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: proj.status.toLowerCase() == 'completed'
                        ? const Color(0xFFDEF7EC)
                        : const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    proj.status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: proj.status.toLowerCase() == 'completed'
                          ? const Color(0xFF03543F)
                          : const Color(0xFF0369A1),
                    ),
                  ),
                ),
              ],
            ),
            if (proj.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                proj.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.people_outline_rounded,
                  size: 14,
                  color: Color(0xFF475569),
                ),
                const SizedBox(width: 4),
                Text(
                  '${proj.assignedEmployees.length} members',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF475569),
                  ),
                ),
                const Spacer(),
                if (proj.dueDate != null && proj.dueDate!.isNotEmpty) ...[
                  const Icon(
                    Icons.event_outlined,
                    size: 14,
                    color: Color(0xFF475569),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    proj.dueDate!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF475569),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Project Overview Detail Screen (Image 1 Structure with Dark Typography & Zero Redirection)
  Widget _buildProjectOverviewDetailView(ProjectModel proj) {
    final projTasks = _tasks
        .where((t) => t.isProjectTask && t.projectId == proj.id)
        .toList();
    final totalCount = projTasks.length;
    final completedCount = projTasks.where((t) => t.isCompleted).length;
    final pendingCount = projTasks.where((t) => t.isPending).length;
    final incompleteCount = projTasks
        .where((t) => !t.isCompleted && !t.isPending)
        .length;
    final rate = totalCount > 0
        ? ((completedCount / totalCount) * 100).round()
        : 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
      children: [
        // 1. Back navigation row
        InkWell(
          onTap: () => setState(() => _overviewSelectedProject = null),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: const [
                Icon(
                  Icons.arrow_back_rounded,
                  size: 18,
                  color: CeladonColors.primary,
                ),
                SizedBox(width: 6),
                Text(
                  'Back to Overview',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: CeladonColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // 2. Project Card Banner (Title, Description, Due Date, Status)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: CeladonColors.border),
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
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: CeladonColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: proj.status.toLowerCase() == 'completed'
                          ? const Color(0xFFDEF7EC)
                          : const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      proj.status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: proj.status.toLowerCase() == 'completed'
                            ? const Color(0xFF03543F)
                            : const Color(0xFF0369A1),
                      ),
                    ),
                  ),
                ],
              ),
              if (proj.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  proj.description,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF475569),
                    height: 1.35,
                  ),
                ),
              ],
              if (proj.dueDate != null && proj.dueDate!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.event_outlined,
                      size: 14,
                      color: Color(0xFF475569),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Due ${proj.dueDate}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF475569),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 3. Project Members (Exact Match to Image 1 with Dark Text)
        const Text(
          'Project Members',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: CeladonColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        if (proj.assignedEmployees.isEmpty)
          const Text(
            'No members assigned yet.',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF475569)),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: proj.assignedEmployees.map((empMap) {
                final empId =
                    (empMap['userId'] ?? empMap['id'] ?? empMap['_id'] ?? '')
                        .toString();
                final rawName = (empMap['name'] ?? empMap['username'] ?? '')
                    .toString();
                final emp = _resolveEmployee(
                  empId.isNotEmpty ? empId : rawName,
                );
                final name = rawName.isNotEmpty
                    ? rawName
                    : _getAssigneeDisplayName(empId);
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Row(
                    children: [
                      _buildEmployeeAvatarMini(emp, name),
                      const SizedBox(width: 6),
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: CeladonColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        const SizedBox(height: 16),

        // 4. Image 1 4 Metric Cards: Total Tasks, Pending, Completed, Incomplete
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                title: 'Total Tasks',
                count: totalCount,
                icon: Icons.assignment_rounded,
                color: CeladonColors.primary,
                isSelected: true,
                onTap: () {},
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricTile(
                title: 'Pending',
                count: pendingCount,
                icon: Icons.schedule_rounded,
                color: const Color(0xFF06B6D4),
                isSelected: false,
                onTap: () {},
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricTile(
                title: 'Completed',
                count: completedCount,
                icon: Icons.check_circle_rounded,
                color: CeladonColors.primary,
                isSelected: false,
                onTap: () {},
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricTile(
                title: 'Incomplete',
                count: incompleteCount,
                icon: Icons.cancel_outlined,
                color: const Color(0xFFEF4444),
                isSelected: false,
                onTap: () {},
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 5. Completion Progress
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: CeladonColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Project Progress',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: CeladonColors.textPrimary,
                    ),
                  ),
                  Text(
                    '$rate%',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: CeladonColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: totalCount > 0 ? (completedCount / totalCount) : 0.0,
                  minHeight: 7,
                  backgroundColor: CeladonColors.border,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    CeladonColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 6. Deliverables / Tasks List Overview
        const Text(
          'Project Tasks Overview',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: CeladonColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        if (projTasks.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: CeladonColors.border),
            ),
            child: const Text(
              'No tasks recorded for this project.',
              style: TextStyle(fontSize: 12, color: CeladonColors.textMuted),
            ),
          )
        else
          ...projTasks.map((t) => _buildTaskCard(t)),
      ],
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
        // 1. Full Search Box: Searches by Title, Description, and Assigned Person with Suffix Filter Icon
        _buildTaskSearchBar(),

        const SizedBox(height: 14),

        // 2. Tasks List
        if (tasksToDisplay.isEmpty)
          _buildEmptyTasksPlaceholder()
        else
          ...tasksToDisplay.map((task) => _buildTaskCard(task)),
      ],
    );
  }

  // 4 Metric Counter Cards: Total Tasks, Pending, Incomplete, Completed
  Widget _buildTaskMetricsGrid({
    void Function(int filterIndex)? onTapOverride,
  }) {
    return Row(
      children: [
        Expanded(
          child: _buildMetricTile(
            title: 'Total Tasks',
            count: _totalTaskCount,
            icon: Icons.assignment_rounded,
            color: CeladonColors.primary,
            onTap: () {
              if (onTapOverride != null) {
                onTapOverride(0);
              } else {
                setState(() => _selectedTaskFilter = 0);
              }
            },
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
            onTap: () {
              if (onTapOverride != null) {
                onTapOverride(1);
              } else {
                setState(() => _selectedTaskFilter = 1);
              }
            },
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
            onTap: () {
              if (onTapOverride != null) {
                onTapOverride(3);
              } else {
                setState(() => _selectedTaskFilter = 3);
              }
            },
            isSelected: _selectedTaskFilter == 3,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMetricTile(
            title: 'Completed',
            count: _completedCount,
            icon: Icons.check_circle_outline_rounded,
            color: CeladonColors.primary,
            onTap: () {
              if (onTapOverride != null) {
                onTapOverride(2);
              } else {
                setState(() => _selectedTaskFilter = 2);
              }
            },
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
              ? color.withValues(alpha: 0.12)
              : CeladonColors.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : CeladonColors.border,
            width: isSelected ? 1.4 : 1.0,
          ),
          boxShadow: const [
            BoxShadow(
              color: CeladonColors.shadow,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
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
                color: CeladonColors.textSecondary,
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
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: Color(0xFFBACCC3),
                ),
              ),
            ),
          GestureDetector(
            onTap: _showTaskFilterSheet,
            child: const Padding(
              padding: EdgeInsets.only(left: 4, right: 2),
              child: Icon(
                Icons.filter_list_rounded,
                size: 20,
                color: Color(0xFFBACCC3),
              ),
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
          {
            'label': 'All Tasks',
            'count': _totalTaskCount,
            'idx': 0,
            'color': CeladonColors.primary,
            'icon': Icons.assignment_rounded,
          },
          {
            'label': 'Pending (Active)',
            'count': _pendingCount,
            'idx': 1,
            'color': const Color(0xFF06B6D4),
            'icon': Icons.schedule_rounded,
          },
          {
            'label': 'Completed (Done)',
            'count': _completedCount,
            'idx': 2,
            'color': CeladonColors.primary,
            'icon': Icons.check_circle_outline_rounded,
          },
          {
            'label': 'Incomplete',
            'count': _incompleteCount,
            'idx': 3,
            'color': const Color(0xFFEF4444),
            'icon': Icons.cancel_outlined,
          },
        ];

        final media = MediaQuery.of(ctx);
        final maxHeight = media.size.height * 0.75;

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Container(
            decoration: BoxDecoration(
              color: CeladonColors.cardBackground,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
              border: Border.all(color: CeladonColors.border, width: 1.0),
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
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                              color: CeladonColors.textPrimary,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              color: CeladonColors.textMuted,
                              size: 20,
                            ),
                            onPressed: () => Navigator.pop(ctx),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Divider(color: CeladonColors.divider, height: 1),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? optColor.withValues(alpha: 0.12)
                                    : CeladonColors.searchBackground,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? optColor
                                      : CeladonColors.border,
                                  width: isSelected ? 1.5 : 0.8,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      color: optColor.withValues(alpha: 0.20),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      icon,
                                      color: optColor,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      opt['label'] as String,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: isSelected
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        color: isSelected
                                            ? optColor
                                            : CeladonColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: optColor.withValues(alpha: 0.20),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '$count',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                        color: optColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (isSelected)
                                    Icon(
                                      Icons.check_circle_rounded,
                                      color: optColor,
                                      size: 20,
                                    )
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

  // Task Card
  Widget _buildTaskCard(TaskModel task) {
    final assigneeName = _getAssigneeDisplayName(task.assignedTo);
    final emp = _resolveEmployee(task.assignedTo);
    final isDone = task.isCompleted;
    final isIncomplete = task.isIncomplete;
    final isRunning = task.isInProgress;

    // Status colors
    final statusColor = isDone
        ? CeladonColors.success
        : isIncomplete
        ? CeladonColors.error
        : (isRunning ? CeladonColors.primary : CeladonColors.warning);

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
            color: CeladonColors.cardBackground,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: CeladonColors.border, width: 1.0),
            boxShadow: const [
              BoxShadow(
                color: CeladonColors.shadow,
                blurRadius: 8,
                offset: Offset(0, 2),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.40),
                      ),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: CeladonColors.infoLight,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: CeladonColors.info.withValues(alpha: 0.40),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.mic_rounded,
                            size: 10,
                            color: CeladonColors.info,
                          ),
                          SizedBox(width: 3),
                          Text(
                            'Voice Note',
                            style: TextStyle(
                              fontSize: 9.5,
                              color: CeladonColors.info,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const Spacer(),

                  if (_canManage)
                    // Read-only status indicator for Company Management (Company cannot complete/incomplete once assigned)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isDone
                            ? CeladonColors.successLight
                            : (isRunning
                                  ? CeladonColors.lightGreen
                                  : (isIncomplete
                                        ? CeladonColors.errorLight
                                        : CeladonColors.warningLight)),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDone
                              ? CeladonColors.success
                              : (isRunning
                                    ? CeladonColors.primary
                                    : (isIncomplete
                                          ? CeladonColors.error
                                          : CeladonColors.warning)),
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
                                      : (isIncomplete
                                            ? Icons.cancel_rounded
                                            : Icons.schedule_rounded)),
                            size: 13,
                            color: isDone
                                ? CeladonColors.success
                                : (isRunning
                                      ? CeladonColors.primary
                                      : (isIncomplete
                                            ? CeladonColors.error
                                            : CeladonColors.warning)),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isDone
                                ? 'Completed${task.completionTime != null ? ' ${task.completionTime}' : ''}'
                                : (isRunning
                                      ? 'Running ${_formatRunningDuration(task)}'
                                      : (isIncomplete
                                            ? 'Incomplete'
                                            : 'Waiting to Start')),
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: isDone
                                  ? CeladonColors.success
                                  : (isRunning
                                        ? CeladonColors.primary
                                        : (isIncomplete
                                              ? CeladonColors.error
                                              : CeladonColors.warning)),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (!isIncomplete)
                    // Quick Action Buttons for Employee
                    if (task.isToDo)
                      ElevatedButton.icon(
                        icon: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                        label: const Text(
                          'Start',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CeladonColors.primary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: CeladonColors.lightGreen,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: CeladonColors.primary),
                            ),
                            child: Text(
                              _formatRunningDuration(task),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: CeladonColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => _handleCompleteTask(task),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: CeladonColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () => _handleIncompleteTask(task),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: CeladonColors.error,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      )
                    else if (isDone)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: CeladonColors.lightGreen,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: CeladonColors.primary),
                        ),
                        child: Text(
                          'Done${task.completionTime != null ? ' (${task.completionTime})' : ''}',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: CeladonColors.primary,
                          ),
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
                  color: CeladonColors.textPrimary,
                  decoration: isDone ? TextDecoration.lineThrough : null,
                  decorationColor: CeladonColors.primary,
                ),
              ),

              // Description Snippet
              if (task.description != null &&
                  task.description!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _cleanDescriptionSnippet(task.description!),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: CeladonColors.textSecondary,
                  ),
                ),
              ],

              // Daily Progress & Latest Notes
              if (!isDone) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Progress: ${task.progressPercentage}%',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: CeladonColors.primary,
                      ),
                    ),
                    if (task.progressUpdates.isNotEmpty)
                      Expanded(
                        child: InkWell(
                          onTap: () => _showNotificationNoteDialog(
                            title: 'Daily Progress Note',
                            taskTitle: task.title,
                            employeeName: _getAssigneeDisplayName(task.assignedTo),
                            note: task.progressUpdates.last.updateText,
                            percentage: task.progressPercentage,
                            task: task,
                          ),
                          child: Text(
                            'Last note: "${task.progressUpdates.last.updateText}"',
                            textAlign: TextAlign.end,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontStyle: FontStyle.italic,
                              color: CeladonColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (task.progressPercentage.clamp(0, 100)) / 100,
                    backgroundColor: CeladonColors.divider,
                    color: CeladonColors.primary,
                    minHeight: 5,
                  ),
                ),
              ],

              // Deadline Extension Request Banner on Card
              if (task.extensionRequest != null &&
                  task.extensionRequest!.status == 'pending') ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => _showNotificationNoteDialog(
                    title: 'Deadline Extension Request',
                    taskTitle: task.title,
                    employeeName: _getAssigneeDisplayName(task.assignedTo),
                    note: task.extensionRequest!.reason,
                    requestedDueDate: task.extensionRequest!.requestedDueDate,
                    requestedDueTime: task.extensionRequest!.requestedDueTime,
                    isExtraTime: true,
                    task: task,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.more_time_rounded,
                          size: 14,
                          color: Color(0xFFB45309),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Extra time requested: ${task.extensionRequest!.requestedDueDate ?? ''} (${task.extensionRequest!.requestedDueTime ?? ''})',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFB45309),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_canManage) ...[
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => _handleReviewExtensionFromCard(task, true),
                            child: const Tooltip(
                              message: 'Accept & Extend',
                              child: Icon(
                                Icons.check_circle_rounded,
                                size: 18,
                                color: CeladonColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => _handleReviewExtensionFromCard(task, false),
                            child: const Tooltip(
                              message: 'Decline',
                              child: Icon(
                                Icons.cancel_rounded,
                                size: 18,
                                color: CeladonColors.error,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],

              // Completion Report Summary Card
              if (task.completionReport != null) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => _showNotificationNoteDialog(
                    title: 'Task Completion Report',
                    taskTitle: task.title,
                    employeeName: task.completionReport!.employeeName ?? 'Employee',
                    workingTime: task.completionReport!.workingTime,
                    note: task.completionReport!.reportText,
                    task: task,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: CeladonColors.lightGreen,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: CeladonColors.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              size: 13,
                              color: CeladonColors.primary,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Report by ${task.completionReport!.employeeName ?? 'Employee'}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: CeladonColors.primary,
                              ),
                            ),
                            if (task.completionReport!.workingTime != null &&
                                task.completionReport!.workingTime!.isNotEmpty) ...[
                              const Spacer(),
                              Text(
                                task.completionReport!.workingTime!,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: CeladonColors.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (task.completionReport!.reportText.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            'Notes: "${task.completionReport!.reportText}"',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: CeladonColors.textPrimary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 10),
              const Divider(color: CeladonColors.divider, height: 1),
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
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: CeladonColors.textPrimary,
                          ),
                        ),
                        Text(
                          emp?.department?.isNotEmpty == true
                              ? emp!.department!
                              : (emp?.role ?? 'Staff'),
                          style: const TextStyle(
                            fontSize: 10,
                            color: CeladonColors.textSecondary,
                          ),
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
                          const Icon(
                            Icons.calendar_today_rounded,
                            size: 11,
                            color: CeladonColors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _formatCleanDate(task.endDate ?? task.dueDate) ??
                                  'No deadline',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isIncomplete
                                    ? CeladonColors.error
                                    : CeladonColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (task.durationValue != null && task.durationValue! > 0)
                        Text(
                          '${task.durationValue} ${task.durationUnit ?? 'days'}',
                          style: const TextStyle(
                            fontSize: 9.5,
                            color: CeladonColors.primary,
                          ),
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
        pColor = CeladonColors.primary;
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
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: pColor,
        ),
      ),
    );
  }


  // Handle Notification Popup (Redirected from notification click or live socket alert)
  void _handleNotificationPopup(NotificationModel notif) {
    final meta = notif.metadata;
    final taskId = meta['taskId']?.toString();
    final taskTitle = meta['taskTitle']?.toString() ?? '';
    final notifType = (meta['type'] ?? notif.type).toString().toLowerCase();

    TaskModel? matchedTask;
    if (taskId != null && taskId.isNotEmpty) {
      final idx = _tasks.indexWhere(
        (t) => t.id == taskId || t.mongoId == taskId,
      );
      if (idx != -1) matchedTask = _tasks[idx];
    }
    if (matchedTask == null) {
      for (final t in _tasks) {
        if (notif.message.contains(t.title) || notif.title.contains(t.title)) {
          matchedTask = t;
          break;
        }
      }
    }

    final effectiveTitle = matchedTask?.title ?? taskTitle;

    if (notifType.contains('extension') ||
        notif.title.toLowerCase().contains('extension') ||
        notif.message.toLowerCase().contains('extra time')) {
      final reqDate = meta['requestedDueDate']?.toString() ??
          matchedTask?.extensionRequest?.requestedDueDate ??
          '';
      final reqTime = meta['requestedDueTime']?.toString() ??
          matchedTask?.extensionRequest?.requestedDueTime ??
          '18:00';
      final reason = meta['reason']?.toString() ??
          matchedTask?.extensionRequest?.reason ??
          notif.message;
      final empName = meta['employeeName']?.toString() ??
          (matchedTask != null
              ? _getAssigneeDisplayName(matchedTask.assignedTo)
              : notif.senderName ?? 'Employee');

      _showNotificationNoteDialog(
        title: 'Deadline Extension Request',
        taskTitle: effectiveTitle.isNotEmpty ? effectiveTitle : 'Task Assignment',
        employeeName: empName,
        requestedDueDate: reqDate,
        requestedDueTime: reqTime,
        note: reason,
        isExtraTime: true,
        task: matchedTask,
        notif: notif,
      );
    } else if (notifType.contains('completion') ||
        notif.title.toLowerCase().contains('completion')) {
      final repText = meta['reportText']?.toString() ??
          matchedTask?.completionReport?.reportText ??
          notif.message;
      final workingTime = meta['workingTime']?.toString() ??
          matchedTask?.completionReport?.workingTime ??
          '';
      final empName = meta['employeeName']?.toString() ??
          matchedTask?.completionReport?.employeeName ??
          (matchedTask != null
              ? _getAssigneeDisplayName(matchedTask.assignedTo)
              : notif.senderName ?? 'Employee');

      _showNotificationNoteDialog(
        title: 'Task Completion Report',
        taskTitle: effectiveTitle.isNotEmpty ? effectiveTitle : 'Task Assignment',
        employeeName: empName,
        workingTime: workingTime.isNotEmpty ? workingTime : null,
        note: repText,
        task: matchedTask,
        notif: notif,
      );
    } else {
      // Daily progress
      final progPercent = meta['progressPercentage'] is num
          ? (meta['progressPercentage'] as num).toInt()
          : (num.tryParse(meta['progressPercentage']?.toString() ?? '')?.toInt() ??
              matchedTask?.progressPercentage ??
              0);
      final updateText = meta['updateText']?.toString() ??
          (matchedTask?.progressUpdates.isNotEmpty == true
              ? matchedTask!.progressUpdates.last.updateText
              : notif.message);
      final empName = meta['employeeName']?.toString() ??
          (matchedTask != null
              ? _getAssigneeDisplayName(matchedTask.assignedTo)
              : notif.senderName ?? 'Employee');

      _showNotificationNoteDialog(
        title: 'Daily Progress Update',
        taskTitle: effectiveTitle.isNotEmpty ? effectiveTitle : 'Task Assignment',
        employeeName: empName,
        percentage: progPercent,
        note: updateText,
        task: matchedTask,
        notif: notif,
      );
    }
  }

  // Beautiful Celadon Dialog for Notes (Daily Progress, Completion Report, Extra Time)
  void _showNotificationNoteDialog({
    required String title,
    required String taskTitle,
    required String employeeName,
    String? note,
    int? percentage,
    String? workingTime,
    String? requestedDueDate,
    String? requestedDueTime,
    bool isExtraTime = false,
    TaskModel? task,
    NotificationModel? notif,
  }) {
    if (_activeDialogContext != null) {
      try {
        Navigator.of(_activeDialogContext!).pop();
      } catch (_) {}
      _activeDialogContext = null;
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        _activeDialogContext = dialogCtx;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: CeladonColors.cardBackground,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: CeladonColors.border, width: 1.2),
              boxShadow: const [
                BoxShadow(
                  color: CeladonColors.shadow,
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (isExtraTime
                                ? const Color(0xFFF59E0B)
                                : CeladonColors.primary)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isExtraTime
                            ? Icons.more_time_rounded
                            : (workingTime != null
                                ? Icons.assignment_turned_in_rounded
                                : Icons.trending_up_rounded),
                        color: isExtraTime
                            ? const Color(0xFFB45309)
                            : CeladonColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: CeladonColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: CeladonColors.textMuted,
                        size: 20,
                      ),
                      onPressed: () => Navigator.pop(dialogCtx),
                    ),
                  ],
                ),
                const Divider(color: CeladonColors.divider, height: 16),

                // Details Box
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: CeladonColors.searchBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: CeladonColors.border),
                  ),
                  child: Column(
                    children: [
                      _buildDetailRow('Task', taskTitle),
                      _buildDetailRow('Employee', employeeName),
                      if (percentage != null)
                        _buildDetailRow('Completion Progress', '$percentage%'),
                      if (workingTime != null && workingTime.isNotEmpty)
                        _buildDetailRow('Working Time', workingTime),
                      if (requestedDueDate != null && requestedDueDate.isNotEmpty)
                        _buildDetailRow(
                          'Requested Deadline',
                          '${_formatCleanDate(requestedDueDate) ?? requestedDueDate} (${requestedDueTime ?? '18:00'})',
                        ),
                    ],
                  ),
                ),

                // Employee Note
                if (note != null && note.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Employee Note / Summary:',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: CeladonColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: CeladonColors.searchBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: CeladonColors.border),
                    ),
                    child: Text(
                      note,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: CeladonColors.textPrimary,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 18),

                // Action Buttons
                if (isExtraTime && _canManage && task != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            _activeDialogContext = null;
                            Navigator.of(dialogCtx).pop();
                            try {
                              await _taskService.reviewDeadlineExtension(
                                task: task,
                                accept: true,
                                requestedDueDate: requestedDueDate,
                                requestedDueTime: requestedDueTime,
                                companyResponse:
                                    'Deadline extended as requested by employee',
                              );
                              if (notif != null) {
                                _notificationService
                                    .markAsRead(notif.id, mongoId: notif.mongoId)
                                    .catchError((_) => false);
                              }
                              _loadInitialData();
                              messenger.showSnackBar(
                                SnackBar(
                                  backgroundColor: CeladonColors.primary,
                                  content: Text(
                                    'Deadline extended to ${requestedDueDate ?? 'new date'}!',
                                  ),
                                ),
                              );
                            } catch (e) {
                              messenger.showSnackBar(
                                SnackBar(
                                  backgroundColor: CeladonColors.error,
                                  content: Text('Failed to accept: $e'),
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: CeladonColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Accept & Extend',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            _activeDialogContext = null;
                            Navigator.of(dialogCtx).pop();
                            try {
                              await _taskService.reviewDeadlineExtension(
                                task: task,
                                accept: false,
                                requestedDueDate: requestedDueDate,
                                requestedDueTime: requestedDueTime,
                                companyResponse: 'Deadline extension declined',
                              );
                              if (notif != null) {
                                _notificationService
                                    .markAsRead(notif.id, mongoId: notif.mongoId)
                                    .catchError((_) => false);
                              }
                              _loadInitialData();
                              messenger.showSnackBar(
                                const SnackBar(
                                  backgroundColor: CeladonColors.error,
                                  content: Text(
                                    'Extension request declined. Original deadline retained.',
                                  ),
                                ),
                              );
                            } catch (e) {
                              messenger.showSnackBar(
                                SnackBar(
                                  backgroundColor: CeladonColors.error,
                                  content: Text('Failed to decline: $e'),
                                ),
                              );
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: CeladonColors.error),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Decline',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: CeladonColors.error,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  ElevatedButton(
                    onPressed: () {
                      _activeDialogContext = null;
                      if (notif != null) {
                        _notificationService
                            .markAsRead(notif.id, mongoId: notif.mongoId)
                            .catchError((_) => false);
                      }
                      Navigator.pop(dialogCtx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CeladonColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'OK',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
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

  // Quick review of deadline extension from task card
  Future<void> _handleReviewExtensionFromCard(TaskModel task, bool accept) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await _taskService.reviewDeadlineExtension(
        task: task,
        accept: accept,
        companyResponse: accept
            ? 'Deadline extended as requested by employee'
            : 'Extension request rejected by manager',
      );
      if (mounted) {
        setState(() {
          final idx = _tasks.indexWhere((t) => t.id == task.id);
          if (idx != -1) _tasks[idx] = updated;
        });
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: accept ? CeladonColors.primary : CeladonColors.error,
            content: Text(
              accept
                  ? 'Deadline extended to ${task.extensionRequest?.requestedDueDate ?? ''}!'
                  : 'Extension request declined.',
            ),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: CeladonColors.error,
          content: Text('Action failed: $e'),
        ),
      );
    }
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
        gradient: const LinearGradient(
          colors: [CeladonColors.primary, Color(0xFF065F46)],
        ),
        border: Border.all(color: CeladonColors.primary, width: 1.2),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
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

    final voiceNoteMatch = RegExp(r'\[voice_note:([^\]]+)\]')
        .firstMatch(task.description ?? '');
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
            color: CeladonColors.cardBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: CeladonColors.border, width: 1.2),
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
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: CeladonColors.textPrimary,
                          size: 20,
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Task Details',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: CeladonColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      if (_canManage)
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: CeladonColors.error,
                            size: 20,
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _deleteTask(task);
                          },
                        ),
                    ],
                  ),
                ),
                const Divider(color: CeladonColors.divider, height: 1),

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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: (isDone
                                    ? CeladonColors.lightGreen
                                    : isIncomplete
                                    ? const Color(0xFFFEF2F2)
                                    : const Color(0xFFEFF6FF)),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: (isDone
                                      ? CeladonColors.primary.withValues(
                                          alpha: 0.3,
                                        )
                                      : isIncomplete
                                      ? CeladonColors.error.withValues(
                                          alpha: 0.3,
                                        )
                                      : CeladonColors.info.withValues(
                                          alpha: 0.3,
                                        )),
                                ),
                              ),
                              child: Text(
                                task.displayStatus,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  color: (isDone
                                      ? CeladonColors.primary
                                      : isIncomplete
                                      ? CeladonColors.error
                                      : CeladonColors.info),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildPriorityBadge(task.priority),
                            if (task.projectName != null &&
                                task.projectName!.isNotEmpty) ...[
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: CeladonColors.searchBackground,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: CeladonColors.border,
                                  ),
                                ),
                                child: Text(
                                  task.projectName!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: CeladonColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Title
                        Text(
                          task.title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: CeladonColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Full Description
                        if (task.description != null &&
                            task.description!.isNotEmpty) ...[
                          const Text(
                            'DESCRIPTION',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: CeladonColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: CeladonColors.searchBackground,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: CeladonColors.border),
                            ),
                            child: Text(
                              _cleanDescriptionSnippet(task.description!),
                              style: const TextStyle(
                                fontSize: 13.5,
                                color: CeladonColors.textPrimary,
                                height: 1.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Voice Note Player (if present)
                        if (voiceNoteRef != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5CF6)
                                  .withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF8B5CF6)
                                    .withValues(alpha: 0.25),
                              ),
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
                                  child: const Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: const [
                                      Text(
                                        'Voice Note Recording Attached',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: CeladonColors.textPrimary,
                                        ),
                                      ),
                                      Text(
                                        'Tap to listen to supervisor instructions',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: CeladonColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // ATTACHED DOCUMENTS
                        if (task.attachments.isNotEmpty) ...[
                          const Text(
                            'ATTACHED DOCUMENTS',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: CeladonColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ...task.attachments.map((doc) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: CeladonColors.searchBackground,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: CeladonColors.border),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: CeladonColors.primary
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.description_rounded,
                                    color: CeladonColors.primary,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        doc.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: CeladonColors.textPrimary,
                                        ),
                                      ),
                                      Text(
                                        doc.displaySize.isNotEmpty
                                            ? doc.displaySize
                                            : (doc.fileType ?? 'Document'),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: CeladonColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.download_rounded,
                                    color: CeladonColors.primary,
                                    size: 22,
                                  ),
                                  tooltip: 'Download to device storage',
                                  onPressed: () =>
                                      _downloadAttachment(task, doc),
                                ),
                              ],
                            ),
                          )),
                          const SizedBox(height: 14),
                        ],

                        // DEADLINE EXTENSION REQUEST BANNER
                        if (task.extensionRequest != null &&
                            task.extensionRequest!.status != 'none') ...[
                          _buildExtensionRequestCard(task, ctx),
                          const SizedBox(height: 14),
                        ],

                        // COMPLETION REPORT CARD
                        if (task.completionReport != null) ...[
                          _buildCompletionReportCard(task.completionReport!),
                          const SizedBox(height: 14),
                        ],

                        // SECTION 1: ASSIGNED PERSON DETAILS
                        const Text(
                          'ASSIGNED PERSON DETAILS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: CeladonColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: CeladonColors.searchBackground,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: CeladonColors.border),
                          ),
                          child: Row(
                            children: [
                              _buildEmployeeAvatarMini(emp, assigneeName),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      assigneeName,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: CeladonColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'ID: ${emp?.userId ?? task.assignedTo ?? 'EMP-??'} • ${emp?.role ?? 'Staff'}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: CeladonColors.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (emp?.email != null &&
                                        emp!.email!.isNotEmpty)
                                      Text(
                                        emp.email!,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: CeladonColors.textSecondary,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // SECTION 2: TIMELINE & PROGRESS DETAILS
                        const Text(
                          'TIMELINE & PROGRESS DETAILS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: CeladonColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: CeladonColors.searchBackground,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: CeladonColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildDetailRow(
                                'Start Date',
                                _formatCleanDate(task.startDate) ?? 'Today',
                              ),
                              if (task.startedAt != null &&
                                  task.startedAt!.isNotEmpty)
                                _buildDetailRow(
                                  'Started At',
                                  _formatCleanDateTime(task.startedAt!),
                                ),
                              if (task.isInProgress)
                                _buildDetailRow(
                                  'Working Time (Live)',
                                  _formatRunningDuration(task),
                                )
                              else if (task.completionReport?.workingTime != null)
                                _buildDetailRow(
                                  'Working Time (Logged)',
                                  task.completionReport!.workingTime!,
                                ),
                              _buildDetailRow(
                                'End Date / Deadline',
                                _formatCleanDate(task.endDate ?? task.dueDate) ?? 'Not set',
                              ),
                              if (task.dueTime != null)
                                _buildDetailRow(
                                  'Target End Time',
                                  task.dueTime!,
                                ),
                              if (task.durationValue != null)
                                _buildDetailRow(
                                  'Duration Allocated',
                                  '${task.durationValue} ${task.durationUnit ?? 'days'}',
                                ),

                              const SizedBox(height: 8),

                              // Progress bar for pending task
                              if (task.isPending) ...[
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Current Progress: ${task.progressPercentage}%',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: CeladonColors.info,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: LinearProgressIndicator(
                                        value: task.progressPercentage.clamp(0, 100) / 100,
                                        backgroundColor: CeladonColors.divider,
                                        color: CeladonColors.info,
                                        minHeight: 8,
                                      ),
                                    ),
                                  ],
                                ),
                              ],

                              // Conditional Details by Status
                              if (isDone) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: CeladonColors.lightGreen,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: CeladonColors.primary.withValues(
                                        alpha: 0.35,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: const [
                                      Icon(
                                        Icons.verified_rounded,
                                        color: CeladonColors.primary,
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Task verified and completed on schedule.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: CeladonColors.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else if (isIncomplete) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF2F2),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: CeladonColors.error.withValues(
                                        alpha: 0.35,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: const [
                                      Icon(
                                        Icons.warning_amber_rounded,
                                        color: CeladonColors.error,
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'The assigned deadline has passed. Task marked as Not Completed.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: CeladonColors.error,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              // Daily Progress Log list
                              if (task.progressUpdates.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                const Text(
                                  'DAILY PROGRESS UPDATES',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: CeladonColors.textMuted,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                ...task.progressUpdates.reversed.map((prog) => Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: CeladonColors.cardBackground,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: CeladonColors.border),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: CeladonColors.primary
                                                  .withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              '${prog.percentage}% Complete',
                                              style: const TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w800,
                                                color: CeladonColors.primary,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            DateTime.tryParse(prog.date) != null
                                                ? '${_formatDisplayDate(DateTime.parse(prog.date))} ${_formatDisplayTime(DateTime.parse(prog.date))}'
                                                : prog.date,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color:
                                                  CeladonColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        prog.updateText,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: CeladonColors.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                )),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Action Buttons: Company View vs Employee View
                        if (_canManage)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                            decoration: BoxDecoration(
                              color: CeladonColors.searchBackground,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: CeladonColors.border),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isDone
                                      ? Icons.check_circle_rounded
                                      : (task.isInProgress
                                            ? Icons.timer_rounded
                                            : Icons.lock_outline_rounded),
                                  color: isDone
                                      ? CeladonColors.primary
                                      : CeladonColors.textMuted,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isDone
                                      ? 'Task Completed by Assignee'
                                      : (task.isInProgress
                                            ? 'Task in progress (running timer)'
                                            : 'Awaiting Assignee to start task'),
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: CeladonColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (!isIncomplete)
                          Column(
                            children: [
                              if (task.isToDo) ...[
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: ElevatedButton.icon(
                                    icon: const Icon(
                                      Icons.play_arrow_rounded,
                                      color: Colors.white,
                                    ),
                                    label: const Text(
                                      'Start Task (Record Working Time)',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: CeladonColors.primary,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                    ),
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _handleStartTask(task);
                                    },
                                  ),
                                ),
                              ] else if (task.isInProgress) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        icon: const Icon(
                                          Icons.edit_note_rounded,
                                          size: 16,
                                          color: CeladonColors.primary,
                                        ),
                                        label: const Text(
                                          'Daily Progress',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: CeladonColors.primary,
                                          ),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(
                                            color: CeladonColors.primary,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          ),
                                        ),
                                        onPressed: () {
                                          Navigator.pop(ctx);
                                          _showDailyProgressSheet(task);
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        icon: const Icon(
                                          Icons.access_time_filled_rounded,
                                          size: 16,
                                          color: Color(0xFFF59E0B),
                                        ),
                                        label: const Text(
                                          'Extra Time',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFFF59E0B),
                                          ),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(
                                            color: Color(0xFFF59E0B),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          ),
                                        ),
                                        onPressed: () {
                                          Navigator.pop(ctx);
                                          _showExtensionRequestSheet(task);
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: ElevatedButton.icon(
                                    icon: const Icon(
                                      Icons.assignment_turned_in_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      'Complete & Submit Report',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: CeladonColors.primary,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                    ),
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _showCompletionReportSheet(task);
                                    },
                                  ),
                                ),
                              ] else ...[
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: CeladonColors.lightGreen,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: CeladonColors.primary.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: const [
                                      Icon(
                                        Icons.check_circle_rounded,
                                        color: CeladonColors.primary,
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Task Completed & Final Report Filed',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: CeladonColors.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Center(
                                  child: TextButton.icon(
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _toggleTaskCompletion(task);
                                    },
                                    icon: const Icon(
                                      Icons.refresh_rounded,
                                      size: 16,
                                      color: Color(0xFF3186C8),
                                    ),
                                    label: const Text(
                                      'Reopen Task',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF3186C8),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: CeladonColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: CeladonColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // ADD TASK (CREATE TASK SHEET WITH MULTI-MODAL VOICE DESCRIPTION)
  // ===========================================================================
  void _showCreateTaskSheet({
    String? defaultProjectId,
    String? defaultProjectName,
  }) {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final List<TaskAttachmentModel> attachedDocs = [];
    String priority = 'medium';
    String durationUnit = 'days';
    num durationVal = 1;
    String startDate = DateTime.now().toIso8601String().split('T')[0];

    // Compute initial end date
    var endCalc = computeEndDateTime(startDate, durationVal, durationUnit);
    String endDate = endCalc['endDate']!;
    String dueTime = endCalc['dueTime']!;

    String? selectedAssignee = _assignableEmployees.isNotEmpty
        ? (_assignableEmployees.first.userId.isNotEmpty
              ? _assignableEmployees.first.userId
              : _assignableEmployees.first.id)
        : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final media = MediaQuery.of(ctx);

          void recalculateEnd() {
            final res = computeEndDateTime(
              startDate,
              durationVal,
              durationUnit,
            );
            setModalState(() {
              endDate = res['endDate']!;
              dueTime = res['dueTime']!;
            });
          }

          return Container(
            constraints: BoxConstraints(maxHeight: media.size.height * 0.90),
            padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
            decoration: BoxDecoration(
              color: CeladonColors.cardBackground,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border.all(color: CeladonColors.border, width: 1.2),
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
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: CeladonColors.textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: CeladonColors.textMuted,
                          ),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: CeladonColors.divider, height: 1),

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
                                onTap: () => _openVoiceDescriptionModal(
                                  descCtrl,
                                  () => setModalState(() {}),
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF8B5CF6)
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFF8B5CF6)
                                          .withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Row(
                                    children: const [
                                      Icon(
                                        Icons.mic_rounded,
                                        size: 12,
                                        color: Color(0xFF8B5CF6),
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'Voice Input',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF8B5CF6),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          _buildDarkTextField(
                            controller: descCtrl,
                            hintText: 'Add details or dictate via voice...',
                            maxLines: 3,
                          ),
                          const SizedBox(height: 14),

                          // Optional Document Attachments
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              _buildInputLabel(
                                'Attachments (Optional)',
                              ),
                              TextButton.icon(
                                onPressed: () async {
                                  try {
                                    final pickedFiles =
                                        await FilePicker.pickFiles();
                                    if (pickedFiles.isNotEmpty) {
                                      for (final file in pickedFiles) {
                                        final bytes =
                                            await file.xFile.readAsBytes();
                                        final base64Data =
                                            base64Encode(bytes);
                                        final size =
                                            await file.xFile.length();
                                        attachedDocs.add(
                                          TaskAttachmentModel(
                                            name: file.name,
                                            fileType:
                                                file.extension ?? 'file',
                                            size: size,
                                            data: base64Data,
                                          ),
                                        );
                                      }
                                      setModalState(() {});
                                    }
                                  } catch (e) {
                                    debugPrint('Pick file error: $e');
                                  }
                                },
                                icon: const Icon(
                                  Icons.attach_file_rounded,
                                  size: 16,
                                  color: CeladonColors.primary,
                                ),
                                label: const Text(
                                  '+ Add Files',
                                  style: TextStyle(
                                    color: CeladonColors.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (attachedDocs.isNotEmpty) ...[
                            ...attachedDocs.asMap().entries.map((entry) {
                              final idx = entry.key;
                              final doc = entry.value;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: CeladonColors.inputBackground,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: CeladonColors.border,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.description_rounded,
                                      size: 18,
                                      color: CeladonColors.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            doc.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color:
                                                  CeladonColors.textPrimary,
                                            ),
                                          ),
                                          Text(
                                            doc.displaySize,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color:
                                                  CeladonColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 16,
                                        color: CeladonColors.error,
                                      ),
                                      onPressed: () {
                                        setModalState(() {
                                          attachedDocs.removeAt(idx);
                                        });
                                      },
                                      constraints: const BoxConstraints(),
                                      padding: EdgeInsets.zero,
                                    ),
                                  ],
                                ),
                              );
                            }),
                            const SizedBox(height: 8),
                          ],

                          // 3. Assignee
                          _buildInputLabel('Assignee *'),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: CeladonColors.inputBackground,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: CeladonColors.inputBorder,
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: selectedAssignee,
                                dropdownColor: CeladonColors.cardBackground,
                                icon: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: CeladonColors.textMuted,
                                ),
                                isExpanded: true,
                                items: _assignableEmployees.map((emp) {
                                  final uId = emp.userId.isNotEmpty
                                      ? emp.userId
                                      : emp.id;
                                  final name = emp.name.isNotEmpty
                                      ? emp.name
                                      : emp.username;
                                  return DropdownMenuItem<String>(
                                    value: uId,
                                    child: Text(
                                      '$name ($uId)',
                                      style: const TextStyle(
                                        color: CeladonColors.textPrimary,
                                        fontSize: 13,
                                      ),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) =>
                                    setModalState(() => selectedAssignee = val),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // 4. Priority
                          _buildInputLabel('Priority'),
                          Row(
                            children: ['low', 'medium', 'high', 'urgent'].map((
                              p,
                            ) {
                              final isSel = priority == p;
                              return Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  child: InkWell(
                                    onTap: () =>
                                        setModalState(() => priority = p),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSel
                                            ? CeladonColors.primary
                                            : CeladonColors.inputBackground,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: isSel
                                              ? CeladonColors.primary
                                              : CeladonColors.border,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        p[0].toUpperCase() + p.substring(1),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: isSel
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                          color: isSel
                                              ? Colors.white
                                              : CeladonColors.textSecondary,
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
                                  style: const TextStyle(
                                    color: CeladonColors.textPrimary,
                                    fontSize: 13,
                                  ),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: CeladonColors.inputBackground,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: CeladonColors.inputBorder,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: CeladonColors.inputFocusBorder,
                                        width: 1.5,
                                      ),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: CeladonColors.inputBackground,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: CeladonColors.inputBorder,
                                    ),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: durationUnit,
                                      dropdownColor:
                                          CeladonColors.cardBackground,
                                      icon: const Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        color: CeladonColors.textMuted,
                                      ),
                                      isExpanded: true,
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'hours',
                                          child: Text(
                                            'Hours',
                                            style: TextStyle(
                                              color: CeladonColors.textPrimary,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        DropdownMenuItem(
                                          value: 'days',
                                          child: Text(
                                            'Days',
                                            style: TextStyle(
                                              color: CeladonColors.textPrimary,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        DropdownMenuItem(
                                          value: 'minutes',
                                          child: Text(
                                            'Minutes',
                                            style: TextStyle(
                                              color: CeladonColors.textPrimary,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
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
                                          firstDate: now.subtract(
                                            const Duration(days: 30),
                                          ),
                                          lastDate: now.add(
                                            const Duration(days: 365),
                                          ),
                                        );
                                        if (picked != null) {
                                          startDate = picked
                                              .toIso8601String()
                                              .split('T')[0];
                                          recalculateEnd();
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: CeladonColors.inputBackground,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: CeladonColors.inputBorder,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.calendar_today_rounded,
                                              size: 14,
                                              color: CeladonColors.primary,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              startDate,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color:
                                                    CeladonColors.textPrimary,
                                              ),
                                            ),
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
                                    _buildInputLabel(
                                      'Auto Calculated End Date',
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: CeladonColors.lightGreen,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: CeladonColors.primary
                                              .withValues(alpha: 0.35),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.event_available_rounded,
                                            size: 14,
                                            color: CeladonColors.primary,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              '$endDate ($dueTime)',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w700,
                                                color: CeladonColors.primary,
                                              ),
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

                          // Submit Button
                          Container(
                            height: 50,
                            decoration: BoxDecoration(
                              color: CeladonColors.primary,
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: ElevatedButton(
                              onPressed: () async {
                                final title = titleCtrl.text.trim();
                                if (title.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Please enter task title'),
                                      backgroundColor: CeladonColors.error,
                                    ),
                                  );
                                  return;
                                }
                                if (selectedAssignee == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Please select an assignee',
                                      ),
                                      backgroundColor: CeladonColors.error,
                                    ),
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
                                  attachments: attachedDocs,
                                );

                                final messenger = ScaffoldMessenger.of(context);
                                final nav = Navigator.of(ctx);
                                try {
                                  final created = await _taskService.createTask(
                                    newTask,
                                  );
                                  if (mounted) {
                                    setState(() => _tasks.insert(0, created));
                                    nav.pop();
                                    messenger.showSnackBar(
                                      SnackBar(
                                        backgroundColor: CeladonColors.primary,
                                        content: Text(
                                          'Task assigned to $selectedAssignee & notification sent!',
                                        ),
                                      ),
                                    );
                                  }
                                } catch (err) {
                                  if (mounted) {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        backgroundColor: CeladonColors.error,
                                        content: Text('Error: $err'),
                                      ),
                                    );
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(25),
                                ),
                              ),
                              child: const Text(
                                'Create & Assign Task',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
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
      ),
    );
  }

  // Voice Description Modal (Voice-to-Text Dictation)
  void _openVoiceDescriptionModal(
    TextEditingController descCtrl,
    VoidCallback onUpdate,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        bool isListening = false;
        String recognizedText = '';
        String statusText = 'Tap mic to dictate description';
        final speech = stt.SpeechToText();

        return StatefulBuilder(
          builder: (context, setVoiceState) {
            Future<void> toggleListening() async {
              if (isListening) {
                await speech.stop();
                setVoiceState(() {
                  isListening = false;
                  statusText = 'Speech recorded. Tap mic to speak more.';
                });
                return;
              }

              if (!kIsWeb &&
                  (defaultTargetPlatform == TargetPlatform.android ||
                      defaultTargetPlatform == TargetPlatform.iOS)) {
                final perm = await Permission.microphone.request();
                if (!perm.isGranted) {
                  setVoiceState(() {
                    statusText = 'Microphone permission denied. Enable in device settings.';
                  });
                  return;
                }
              }

              try {
                final available = await speech.initialize(
                  onStatus: (status) {
                    if (status == 'done' || status == 'notListening') {
                      if (context.mounted) {
                        setVoiceState(() {
                          isListening = false;
                          statusText = 'Finished listening. Tap mic to add more.';
                        });
                      }
                    }
                  },
                  onError: (err) {
                    if (context.mounted) {
                      setVoiceState(() {
                        isListening = false;
                        statusText = 'Speech: ${err.errorMsg}';
                      });
                    }
                  },
                );

                if (available) {
                  setVoiceState(() {
                    isListening = true;
                    statusText = 'Listening... Speak clearly into microphone';
                  });
                  await speech.listen(
                    onResult: (result) {
                      setVoiceState(() {
                        recognizedText = result.recognizedWords;
                      });
                    },
                  );
                } else {
                  setVoiceState(() {
                    statusText = 'Speech recognition not available on this device.';
                  });
                }
              } catch (e) {
                setVoiceState(() {
                  isListening = false;
                  statusText = 'Microphone error: $e';
                });
              }
            }

            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: CeladonColors.cardBackground,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                border: Border.all(color: CeladonColors.border, width: 1.2),
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
                          Icon(
                            Icons.mic_rounded,
                            color: Color(0xFF8B5CF6),
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Voice-to-Text Dictation',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: CeladonColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: CeladonColors.textMuted,
                          size: 20,
                        ),
                        onPressed: () {
                          speech.stop();
                          Navigator.pop(ctx);
                        },
                      ),
                    ],
                  ),
                  const Divider(color: CeladonColors.divider, height: 1),
                  const SizedBox(height: 16),

                  // Real Voice-to-Text
                  Center(
                    child: GestureDetector(
                      onTap: toggleListening,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isListening
                              ? CeladonColors.error
                              : const Color(0xFF8B5CF6),
                          boxShadow: [
                            BoxShadow(
                              color: (isListening
                                      ? CeladonColors.error
                                      : const Color(0xFF8B5CF6))
                                  .withValues(alpha: 0.35),
                              blurRadius: 18,
                            ),
                          ],
                        ),
                        child: Icon(
                          isListening
                              ? Icons.stop_rounded
                              : Icons.mic_rounded,
                          size: 34,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      statusText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isListening ? FontWeight.w700 : FontWeight.w500,
                        color: isListening ? CeladonColors.error : CeladonColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (recognizedText.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: CeladonColors.searchBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: CeladonColors.border),
                      ),
                      child: Text(
                        recognizedText,
                        style: const TextStyle(
                          color: CeladonColors.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () {
                        speech.stop();
                        if (descCtrl.text.isNotEmpty) {
                          descCtrl.text =
                              '${descCtrl.text.trim()} $recognizedText';
                        } else {
                          descCtrl.text = recognizedText;
                        }
                        onUpdate();
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Insert Spoken Text',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
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
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: Color(0xFFBACCC3),
                    ),
                  ),
                ),
              GestureDetector(
                onTap: _showProjectFilterSheet,
                child: const Padding(
                  padding: EdgeInsets.only(left: 4, right: 2),
                  child: Icon(
                    Icons.filter_list_rounded,
                    size: 20,
                    color: Color(0xFFBACCC3),
                  ),
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
            color: CeladonColors.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: CeladonColors.border, width: 1.0),
            boxShadow: const [
              BoxShadow(
                color: CeladonColors.shadow,
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: CeladonColors.lightGreen,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.folder_copy_rounded,
                  color: CeladonColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  proj.name,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: CeladonColors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: CeladonColors.textMuted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Full Project Details View with Members, Search Box, and Project Tasks
  Widget _buildProjectDetailView(ProjectModel proj) {
    final allProjectTasks = _tasks
        .where((t) => t.projectId == proj.id)
        .toList();

    // Filter by query and filter sheet selection
    final query = _projectTaskSearchController.text.trim().toLowerCase();
    final filteredTasks = allProjectTasks.where((t) {
      if (_selectedProjectTaskFilter == 1 && !t.isPending) return false;
      if (_selectedProjectTaskFilter == 2 && !t.isCompleted) return false;
      if (_selectedProjectTaskFilter == 3 && !t.isIncomplete) return false;

      if (query.isNotEmpty) {
        final titleMatches = t.title.toLowerCase().contains(query);
        final descMatches =
            t.description?.toLowerCase().contains(query) ?? false;
        final assigneeMatches = _getAssigneeDisplayName(t.assignedTo)
            .toLowerCase()
            .contains(query);
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
                  color: CeladonColors.searchBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: CeladonColors.border),
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  color: CeladonColors.textPrimary,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                proj.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: CeladonColors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: CeladonColors.lightGreen,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: CeladonColors.primary),
              ),
              child: Text(
                proj.displayStatus,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: CeladonColors.primary,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // 2. Project Details Card (Description, Dates)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: CeladonColors.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: CeladonColors.border),
            boxShadow: const [
              BoxShadow(
                color: CeladonColors.shadow,
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (proj.description.isNotEmpty) ...[
                Text(
                  proj.description,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: CeladonColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  const Icon(
                    Icons.calendar_today_rounded,
                    size: 13,
                    color: CeladonColors.primary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    proj.dueDate != null
                        ? 'Due: ${proj.dueDate}'
                        : 'Ongoing project',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: CeladonColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
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
        const Text(
          'Project Members',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: CeladonColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        if (proj.assignedEmployees.isEmpty)
          const Text(
            'No members assigned yet.',
            style: TextStyle(
              fontSize: 11.5,
              color: CeladonColors.textSecondary,
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: proj.assignedEmployees.map((empMap) {
                final empId =
                    (empMap['userId'] ?? empMap['id'] ?? empMap['_id'] ?? '')
                        .toString();
                final rawName = (empMap['name'] ?? empMap['username'] ?? '')
                    .toString();
                final emp = _resolveEmployee(
                  empId.isNotEmpty ? empId : rawName,
                );
                final name = rawName.isNotEmpty
                    ? rawName
                    : _getAssigneeDisplayName(empId);
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Row(
                    children: [
                      _buildEmployeeAvatarMini(emp, name),
                      const SizedBox(width: 6),
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: CeladonColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

        const SizedBox(height: 14),

        // 4. Search Box (Matching company employee search box style, Image 1)
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
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: Color(0xFFBACCC3),
                    ),
                  ),
                ),
              GestureDetector(
                onTap: _showProjectTaskFilterSheet,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4, right: 2),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        Icons.filter_list_rounded,
                        size: 20,
                        color: _selectedProjectTaskFilter != 0
                            ? CeladonColors.primary
                            : const Color(0xFF94A3B8),
                      ),
                      if (_selectedProjectTaskFilter != 0)
                        Positioned(
                          top: -2,
                          right: -2,
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: CeladonColors.primary,
                              shape: BoxShape.circle,
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

        const SizedBox(height: 14),

        // 5. Project Tasks List
        if (filteredTasks.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: CeladonColors.border),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.task_alt_rounded,
                  size: 36,
                  color: Color(0xFF64748B),
                ),
                SizedBox(height: 8),
                Text(
                  'No tasks in this category for this project.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          )
        else
          ...filteredTasks.map((t) => _buildTaskCard(t)),
      ],
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
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        decoration: BoxDecoration(
          color: CeladonColors.inputBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: CeladonColors.inputBorder, width: 1.0),
        ),
        child: Row(
          children: [
            Icon(prefixIcon, color: CeladonColors.textMuted, size: 20),
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
                  cursorColor: CeladonColors.primary,
                  style: const TextStyle(
                    color: CeladonColors.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    fillColor: Colors.transparent,
                    hintText: hintText,
                    hintStyle: const TextStyle(
                      color: CeladonColors.textPlaceholder,
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
                onTap:
                    onClear ??
                    () {
                      controller.clear();
                      onChanged('');
                    },
                child: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: CeladonColors.textMuted,
                ),
              ),
          ],
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
        final activeCount = _projects
            .where((p) => p.status.toLowerCase() != 'completed')
            .length;
        final completedCount = _projects
            .where((p) => p.status.toLowerCase() == 'completed')
            .length;
        final options = [
          {
            'label': 'All Projects',
            'count': totalCount,
            'color': CeladonColors.primary,
            'icon': Icons.folder_rounded,
          },
          {
            'label': 'Active Projects',
            'count': activeCount,
            'color': CeladonColors.info,
            'icon': Icons.pending_actions_rounded,
          },
          {
            'label': 'Completed Projects',
            'count': completedCount,
            'color': CeladonColors.primary,
            'icon': Icons.check_circle_outline_rounded,
          },
        ];

        final media = MediaQuery.of(ctx);
        final maxHeight = media.size.height * 0.65;

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Container(
            decoration: BoxDecoration(
              color: CeladonColors.cardBackground,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
              border: Border.all(color: CeladonColors.border, width: 1.0),
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
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                              color: CeladonColors.textPrimary,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              color: CeladonColors.textMuted,
                              size: 20,
                            ),
                            onPressed: () => Navigator.pop(ctx),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Divider(color: CeladonColors.divider, height: 1),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: CeladonColors.searchBackground,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: CeladonColors.border,
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      color: optColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      icon,
                                      color: optColor,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      opt['label'] as String,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: CeladonColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: optColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '$count',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                        color: optColor,
                                      ),
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
          {
            'label': 'All Tasks',
            'idx': 0,
            'color': CeladonColors.primary,
            'icon': Icons.assignment_rounded,
          },
          {
            'label': 'Pending',
            'idx': 1,
            'color': CeladonColors.info,
            'icon': Icons.schedule_rounded,
          },
          {
            'label': 'Completed',
            'idx': 2,
            'color': CeladonColors.primary,
            'icon': Icons.check_circle_outline_rounded,
          },
          {
            'label': 'Incomplete',
            'idx': 3,
            'color': CeladonColors.error,
            'icon': Icons.cancel_outlined,
          },
        ];

        final media = MediaQuery.of(ctx);
        final maxHeight = media.size.height * 0.70;

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Container(
            decoration: BoxDecoration(
              color: CeladonColors.cardBackground,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
              border: Border.all(color: CeladonColors.border, width: 1.0),
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
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            color: CeladonColors.textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: CeladonColors.textMuted,
                            size: 20,
                          ),
                          onPressed: () => Navigator.pop(ctx),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Divider(color: CeladonColors.divider, height: 1),
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? optColor.withValues(alpha: 0.12)
                                  : CeladonColors.searchBackground,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? optColor
                                    : CeladonColors.border,
                                width: isSelected ? 1.5 : 0.8,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: optColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(icon, color: optColor, size: 18),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    opt['label'] as String,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: isSelected
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      color: isSelected
                                          ? CeladonColors.textPrimary
                                          : CeladonColors.textSecondary,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  Icon(
                                    Icons.check_circle_rounded,
                                    color: optColor,
                                    size: 20,
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
    String dueDate = DateTime.now()
        .add(const Duration(days: 14))
        .toIso8601String()
        .split('T')[0];
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
              color: CeladonColors.cardBackground,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border.all(color: CeladonColors.border, width: 1.2),
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
                        const Text(
                          'Create Enterprise Project',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: CeladonColors.textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: CeladonColors.textMuted,
                          ),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: CeladonColors.divider, height: 1),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildInputLabel('Project Name *'),
                          _buildDarkTextField(
                            controller: nameCtrl,
                            hintText: 'e.g. NextGen Web Portal',
                          ),
                          const SizedBox(height: 14),

                          _buildInputLabel('Description'),
                          _buildDarkTextField(
                            controller: descCtrl,
                            hintText: 'Project goals and deliverables...',
                            maxLines: 2,
                          ),
                          const SizedBox(height: 14),

                          _buildInputLabel('Priority'),
                          Row(
                            children: ['low', 'medium', 'high', 'urgent'].map((
                              p,
                            ) {
                              final isSel = priority == p;
                              return Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  child: InkWell(
                                    onTap: () =>
                                        setProjState(() => priority = p),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSel
                                            ? CeladonColors.primary
                                            : CeladonColors.inputBackground,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: isSel
                                              ? CeladonColors.primary
                                              : CeladonColors.border,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        p[0].toUpperCase() + p.substring(1),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: isSel
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                          color: isSel
                                              ? Colors.white
                                              : CeladonColors.textSecondary,
                                        ),
                                      ),
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
                              _buildInputLabel(
                                'Team Members (${selectedEmployeeIds.length} selected)',
                              ),
                              GestureDetector(
                                onTap: () {
                                  setProjState(() {
                                    if (selectedEmployeeIds.length ==
                                        _assignableEmployees.length) {
                                      selectedEmployeeIds.clear();
                                    } else {
                                      selectedEmployeeIds.addAll(
                                        _assignableEmployees.map(
                                          (e) => e.userId.isNotEmpty
                                              ? e.userId
                                              : e.id,
                                        ),
                                      );
                                    }
                                  });
                                },
                                child: Text(
                                  selectedEmployeeIds.length ==
                                          _assignableEmployees.length
                                      ? 'Deselect All'
                                      : 'Select All',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: CeladonColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: 140,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: CeladonColors.inputBackground,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: CeladonColors.inputBorder,
                              ),
                            ),
                            child: ListView(
                              children: _assignableEmployees.map((emp) {
                                final uid = emp.userId.isNotEmpty
                                    ? emp.userId
                                    : emp.id;
                                final isSelected = selectedEmployeeIds.contains(
                                  uid,
                                );
                                return CheckboxListTile(
                                  dense: true,
                                  value: isSelected,
                                  activeColor: CeladonColors.primary,
                                  checkColor: Colors.white,
                                  title: Text(
                                    emp.name.isNotEmpty
                                        ? emp.name
                                        : emp.username,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: CeladonColors.textPrimary,
                                    ),
                                  ),
                                  subtitle: Text(
                                    emp.role,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      color: CeladonColors.textMuted,
                                    ),
                                  ),
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
                              color: CeladonColors.primary,
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: ElevatedButton(
                              onPressed: () async {
                                final name = nameCtrl.text.trim();
                                if (name.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Project name is required'),
                                    ),
                                  );
                                  return;
                                }

                                final assigned = _assignableEmployees
                                    .where(
                                      (e) => selectedEmployeeIds.contains(
                                        e.userId.isNotEmpty ? e.userId : e.id,
                                      ),
                                    )
                                    .map(
                                      (e) => {
                                        'userId': e.userId.isNotEmpty
                                            ? e.userId
                                            : e.id,
                                        'name': e.name.isNotEmpty
                                            ? e.name
                                            : e.username,
                                        'email': e.email,
                                        'department': e.department,
                                      },
                                    )
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
                                  final created = await _taskService
                                      .createProject(newProj);
                                  if (mounted) {
                                    setState(
                                      () => _projects.insert(0, created),
                                    );
                                    nav.pop();
                                    messenger.showSnackBar(
                                      SnackBar(
                                        backgroundColor: CeladonColors.primary,
                                        content: Text(
                                          'Project "${created.name}" created successfully',
                                        ),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    messenger.showSnackBar(
                                      SnackBar(content: Text('Error: $e')),
                                    );
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(25),
                                ),
                              ),
                              child: const Text(
                                'Create Project',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
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
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: CeladonColors.textSecondary,
        ),
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
      cursorColor: CeladonColors.primary,
      style: const TextStyle(
        color: CeladonColors.textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: CeladonColors.inputBackground,
        hintText: hintText,
        hintStyle: const TextStyle(
          color: CeladonColors.textPlaceholder,
          fontSize: 12.5,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: CeladonColors.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: CeladonColors.inputFocusBorder,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
    );
  }

  Widget _buildEmptyTasksPlaceholder() {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: CeladonColors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CeladonColors.border),
      ),
      child: Column(
        children: const [
          Icon(
            Icons.assignment_turned_in_rounded,
            size: 44,
            color: CeladonColors.textMuted,
          ),
          SizedBox(height: 10),
          Text(
            'No Tasks Found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: CeladonColors.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Try adjusting your filter or search criteria, or click Add Task to create a new assignment.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: CeladonColors.textSecondary),
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
        color: CeladonColors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CeladonColors.border),
      ),
      child: Column(
        children: const [
          Icon(
            Icons.folder_open_rounded,
            size: 44,
            color: CeladonColors.textMuted,
          ),
          SizedBox(height: 10),
          Text(
            'No Projects Found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: CeladonColors.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Create enterprise projects to organize multi-member teams and project tasks.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: CeladonColors.textSecondary),
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
            const Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: CeladonColors.error,
            ),
            const SizedBox(height: 10),
            Text(
              'Error Loading Schedules',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: CeladonColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$_errorMessage',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: CeladonColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadInitialData,
              style: ElevatedButton.styleFrom(
                backgroundColor: CeladonColors.primary,
              ),
              child: const Text(
                'Try Again',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
