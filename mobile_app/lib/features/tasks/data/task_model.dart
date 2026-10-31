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
  final String? startDate;
  final String? endDate;

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
    this.startDate,
    this.endDate,
  });

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    return TaskModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      mongoId: json['_id']?.toString(),
      companyId: json['companyId']?.toString(),
      title: (json['title'] ?? 'Task').toString(),
      description: json['description']?.toString(),
      assignedTo: json['assignedTo']?.toString(),
      status: (json['status'] ?? 'todo').toString(),
      priority: (json['priority'] ?? 'medium').toString(),
      assignorName: json['assignorName']?.toString(),
      durationValue: json['durationValue'] as num?,
      durationUnit: json['durationUnit']?.toString(),
      dueDate: json['dueDate']?.toString(),
      startDate: json['startDate']?.toString(),
      endDate: json['endDate']?.toString(),
    );
  }

  bool get isCompleted =>
      status.toLowerCase() == 'done' ||
      status.toLowerCase() == 'completed';

  bool get isHighPriority => priority.toLowerCase() == 'high';
  bool get isMediumPriority => priority.toLowerCase() == 'medium';
  bool get isLowPriority => priority.toLowerCase() == 'low';

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

