/// ReGen Task Model
///
/// Maps exactly to MongoDB `Task` documents returned by `GET /api/tasks`.
class TaskModel {
  final String id;
  final String? mongoId;
  final String? companyId;
  final String title;
  final String? description;
  final String? assignedTo;
  final String status;
  final String priority;
  final String? assignorName;
  final num? durationValue;
  final String? durationUnit;
  final String? dueDate;
  final String? dueTime;
  final String? startDate;
  final String? endDate;
  final String? projectId;
  final String? projectName;
  final bool isProjectTask;

  const TaskModel({
    required this.id,
    this.mongoId,
    this.companyId,
    required this.title,
    this.description,
    this.assignedTo,
    this.status = 'todo',
    this.priority = 'medium',
    this.assignorName,
    this.durationValue,
    this.durationUnit,
    this.dueDate,
    this.dueTime,
    this.startDate,
    this.endDate,
    this.projectId,
    this.projectName,
    this.isProjectTask = false,
  });

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    return TaskModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      mongoId: json['_id']?.toString(),
      companyId: json['companyId']?.toString(),
      title: (json['title'] ?? 'Task').toString(),
      description: json['description']?.toString(),
      assignedTo: (json['assignedTo'] ?? json['assignee'])?.toString(),
      status: (json['status'] ?? 'todo').toString(),
      priority: (json['priority'] ?? 'medium').toString(),
      assignorName: json['assignorName']?.toString(),
      durationValue: json['durationValue'] as num?,
      durationUnit: json['durationUnit']?.toString(),
      dueDate: json['dueDate']?.toString(),
      dueTime: json['dueTime']?.toString(),
      startDate: json['startDate']?.toString(),
      endDate: json['endDate']?.toString(),
      projectId: json['projectId']?.toString(),
      projectName: json['projectName']?.toString(),
      isProjectTask: json['isProjectTask'] == true || (json['projectId'] != null && json['projectId'].toString().isNotEmpty),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      if (description != null) 'description': description,
      if (assignedTo != null) 'assignedTo': assignedTo,
      'status': status,
      'priority': priority,
      if (assignorName != null) 'assignorName': assignorName,
      if (durationValue != null) 'durationValue': durationValue,
      if (durationUnit != null) 'durationUnit': durationUnit,
      if (dueDate != null) 'dueDate': dueDate,
      if (dueTime != null) 'dueTime': dueTime,
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
      if (projectId != null) 'projectId': projectId,
      if (projectName != null) 'projectName': projectName,
      'isProjectTask': isProjectTask,
      if (companyId != null) 'companyId': companyId,
    };
  }

  TaskModel copyWith({
    String? id,
    String? mongoId,
    String? companyId,
    String? title,
    String? description,
    String? assignedTo,
    String? status,
    String? priority,
    String? assignorName,
    num? durationValue,
    String? durationUnit,
    String? dueDate,
    String? dueTime,
    String? startDate,
    String? endDate,
    String? projectId,
    String? projectName,
    bool? isProjectTask,
  }) {
    return TaskModel(
      id: id ?? this.id,
      mongoId: mongoId ?? this.mongoId,
      companyId: companyId ?? this.companyId,
      title: title ?? this.title,
      description: description ?? this.description,
      assignedTo: assignedTo ?? this.assignedTo,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      assignorName: assignorName ?? this.assignorName,
      durationValue: durationValue ?? this.durationValue,
      durationUnit: durationUnit ?? this.durationUnit,
      dueDate: dueDate ?? this.dueDate,
      dueTime: dueTime ?? this.dueTime,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      projectId: projectId ?? this.projectId,
      projectName: projectName ?? this.projectName,
      isProjectTask: isProjectTask ?? this.isProjectTask,
    );
  }

  bool get isCompleted =>
      status.toLowerCase() == 'done' ||
      status.toLowerCase() == 'completed';

  bool get isInProgress => status.toLowerCase() == 'in_progress';
  bool get isPaused => status.toLowerCase() == 'paused';
  bool get isToDo => status.toLowerCase() == 'todo';

  bool get isHighPriority => priority.toLowerCase() == 'high';
  bool get isMediumPriority => priority.toLowerCase() == 'medium';
  bool get isLowPriority => priority.toLowerCase() == 'low';
  bool get isUrgentPriority => priority.toLowerCase() == 'urgent';

  String get displayPriority {
    if (priority.isEmpty) return 'Medium';
    return priority[0].toUpperCase() + priority.substring(1).toLowerCase();
  }

  String get displayStatus {
    switch (status.toLowerCase()) {
      case 'done':
      case 'completed':
        return 'Done';
      case 'in_progress':
        return 'In Progress';
      case 'paused':
        return 'Paused';
      case 'review':
        return 'Review';
      case 'blocked':
        return 'Blocked';
      case 'not_completed':
        return 'Incomplete';
      case 'todo':
      default:
        return 'To Do';
    }
  }
}
