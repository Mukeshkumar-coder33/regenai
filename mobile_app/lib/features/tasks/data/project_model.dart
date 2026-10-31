/// ReGen Project Model
///
/// Maps to MongoDB `Project` documents returned by `GET /api/projects`.
class ProjectModel {
  final String id;
  final String? mongoId;
  final String? companyId;
  final String name;
  final String description;
  final String status; // 'planning', 'active', 'completed', 'on_hold'
  final String priority; // 'low', 'medium', 'high', 'urgent'
  final String? startDate;
  final String? dueDate;
  final String? createdBy;
  final List<Map<String, dynamic>> assignedEmployees;

  const ProjectModel({
    required this.id,
    this.mongoId,
    this.companyId,
    required this.name,
    this.description = '',
    this.status = 'active',
    this.priority = 'medium',
    this.startDate,
    this.dueDate,
    this.createdBy,
    this.assignedEmployees = const [],
  });

  factory ProjectModel.fromJson(Map<String, dynamic> json) {
    return ProjectModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      mongoId: json['_id']?.toString(),
      companyId: json['companyId']?.toString(),
      name: (json['name'] ?? 'Project').toString(),
      description: (json['description'] ?? '').toString(),
      status: (json['status'] ?? 'active').toString(),
      priority: (json['priority'] ?? 'medium').toString(),
      startDate: json['startDate']?.toString(),
      dueDate: json['dueDate']?.toString(),
      createdBy: json['createdBy']?.toString(),
      assignedEmployees: (json['assignedEmployees'] as List<dynamic>?)
              ?.map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{})
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'status': status,
      'priority': priority,
      if (startDate != null) 'startDate': startDate,
      if (dueDate != null) 'dueDate': dueDate,
      if (companyId != null) 'companyId': companyId,
      if (createdBy != null) 'createdBy': createdBy,
    };
  }

  String get displayStatus {
    switch (status.toLowerCase()) {
      case 'active':
        return 'Active';
      case 'completed':
        return 'Completed';
      case 'on_hold':
        return 'On Hold';
      case 'planning':
      default:
        return 'Planning';
    }
  }

  String get displayPriority {
    if (priority.isEmpty) return 'Medium';
    return priority[0].toUpperCase() + priority.substring(1).toLowerCase();
  }
}

