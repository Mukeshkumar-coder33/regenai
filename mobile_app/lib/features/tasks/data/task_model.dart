// ReGen Task Model
//
// Maps exactly to MongoDB `Task` documents returned by `GET /api/tasks`.

class TaskAttachmentModel {
  final String name;
  final String? url;
  final String? fileType;
  final num? size;
  final String? data; // base64 string

  const TaskAttachmentModel({
    required this.name,
    this.url,
    this.fileType,
    this.size,
    this.data,
  });

  factory TaskAttachmentModel.fromJson(Map<String, dynamic> json) {
    return TaskAttachmentModel(
      name: (json['name'] ?? 'document').toString(),
      url: json['url']?.toString(),
      fileType: json['fileType']?.toString(),
      size: json['size'] as num?,
      data: json['data']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (url != null) 'url': url,
      if (fileType != null) 'fileType': fileType,
      if (size != null) 'size': size,
      if (data != null) 'data': data,
    };
  }

  String get displaySize {
    if (size == null || size! <= 0) return '';
    final kb = size! / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class TaskProgressUpdateModel {
  final String date;
  final String updateText;
  final int percentage;
  final String? employeeName;
  final String? employeeId;

  const TaskProgressUpdateModel({
    required this.date,
    required this.updateText,
    required this.percentage,
    this.employeeName,
    this.employeeId,
  });

  factory TaskProgressUpdateModel.fromJson(Map<String, dynamic> json) {
    return TaskProgressUpdateModel(
      date: (json['date'] ?? '').toString(),
      updateText: (json['updateText'] ?? '').toString(),
      percentage: (json['percentage'] is num) ? (json['percentage'] as num).toInt() : 0,
      employeeName: json['employeeName']?.toString(),
      employeeId: json['employeeId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'updateText': updateText,
      'percentage': percentage,
      if (employeeName != null) 'employeeName': employeeName,
      if (employeeId != null) 'employeeId': employeeId,
    };
  }
}

class TaskCompletionReportModel {
  final String reportText;
  final String submittedAt;
  final String startDay;
  final String startTime;
  final String endDay;
  final String endTime;
  final String? employeeName;
  final String? employeeId;
  final String? workingTime;

  const TaskCompletionReportModel({
    required this.reportText,
    required this.submittedAt,
    required this.startDay,
    required this.startTime,
    required this.endDay,
    required this.endTime,
    this.employeeName,
    this.employeeId,
    this.workingTime,
  });

  factory TaskCompletionReportModel.fromJson(Map<String, dynamic> json) {
    return TaskCompletionReportModel(
      reportText: (json['reportText'] ?? '').toString(),
      submittedAt: (json['submittedAt'] ?? '').toString(),
      startDay: (json['startDay'] ?? '').toString(),
      startTime: (json['startTime'] ?? '').toString(),
      endDay: (json['endDay'] ?? '').toString(),
      endTime: (json['endTime'] ?? '').toString(),
      employeeName: json['employeeName']?.toString(),
      employeeId: json['employeeId']?.toString(),
      workingTime: json['workingTime']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'reportText': reportText,
      'submittedAt': submittedAt,
      'startDay': startDay,
      'startTime': startTime,
      'endDay': endDay,
      'endTime': endTime,
      if (employeeName != null) 'employeeName': employeeName,
      if (employeeId != null) 'employeeId': employeeId,
      if (workingTime != null) 'workingTime': workingTime,
    };
  }
}

class TaskExtensionRequestModel {
  final String? requestedDueDate;
  final String? requestedDueTime;
  final String? reason;
  final String status; // 'none', 'pending', 'accepted', 'rejected'
  final String? requestedAt;
  final String? reviewedAt;
  final String? companyResponse;

  const TaskExtensionRequestModel({
    this.requestedDueDate,
    this.requestedDueTime,
    this.reason,
    this.status = 'none',
    this.requestedAt,
    this.reviewedAt,
    this.companyResponse,
  });

  factory TaskExtensionRequestModel.fromJson(Map<String, dynamic> json) {
    return TaskExtensionRequestModel(
      requestedDueDate: json['requestedDueDate']?.toString(),
      requestedDueTime: json['requestedDueTime']?.toString(),
      reason: json['reason']?.toString(),
      status: (json['status'] ?? 'none').toString(),
      requestedAt: json['requestedAt']?.toString(),
      reviewedAt: json['reviewedAt']?.toString(),
      companyResponse: json['companyResponse']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (requestedDueDate != null) 'requestedDueDate': requestedDueDate,
      if (requestedDueTime != null) 'requestedDueTime': requestedDueTime,
      if (reason != null) 'reason': reason,
      'status': status,
      if (requestedAt != null) 'requestedAt': requestedAt,
      if (reviewedAt != null) 'reviewedAt': reviewedAt,
      if (companyResponse != null) 'companyResponse': companyResponse,
    };
  }

  TaskExtensionRequestModel copyWith({
    String? requestedDueDate,
    String? requestedDueTime,
    String? reason,
    String? status,
    String? requestedAt,
    String? reviewedAt,
    String? companyResponse,
  }) {
    return TaskExtensionRequestModel(
      requestedDueDate: requestedDueDate ?? this.requestedDueDate,
      requestedDueTime: requestedDueTime ?? this.requestedDueTime,
      reason: reason ?? this.reason,
      status: status ?? this.status,
      requestedAt: requestedAt ?? this.requestedAt,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      companyResponse: companyResponse ?? this.companyResponse,
    );
  }

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isRejected => status == 'rejected';
}

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
  final String? startedAt;
  final String? workingTime;
  final String? completedAt;
  final String? completionTime;
  final String? projectId;
  final String? projectName;
  final bool isProjectTask;
  final List<TaskAttachmentModel> attachments;
  final int progressPercentage;
  final List<TaskProgressUpdateModel> progressUpdates;
  final TaskCompletionReportModel? completionReport;
  final TaskExtensionRequestModel? extensionRequest;

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
    this.startedAt,
    this.workingTime,
    this.completedAt,
    this.completionTime,
    this.projectId,
    this.projectName,
    this.isProjectTask = false,
    this.attachments = const [],
    this.progressPercentage = 0,
    this.progressUpdates = const [],
    this.completionReport,
    this.extensionRequest,
  });

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    var rawAttachments = json['attachments'];
    List<TaskAttachmentModel> atts = [];
    if (rawAttachments is List) {
      atts = rawAttachments
          .whereType<Map<String, dynamic>>()
          .map((m) => TaskAttachmentModel.fromJson(m))
          .toList();
    }

    var rawUpdates = json['progressUpdates'];
    List<TaskProgressUpdateModel> updates = [];
    if (rawUpdates is List) {
      updates = rawUpdates
          .whereType<Map<String, dynamic>>()
          .map((m) => TaskProgressUpdateModel.fromJson(m))
          .toList();
    }

    TaskCompletionReportModel? compReport;
    if (json['completionReport'] is Map<String, dynamic>) {
      compReport = TaskCompletionReportModel.fromJson(json['completionReport'] as Map<String, dynamic>);
    }

    TaskExtensionRequestModel? extReq;
    if (json['extensionRequest'] is Map<String, dynamic>) {
      extReq = TaskExtensionRequestModel.fromJson(json['extensionRequest'] as Map<String, dynamic>);
    }

    int progPercent = 0;
    if (json['progressPercentage'] != null) {
      final parsed = num.tryParse(json['progressPercentage'].toString());
      if (parsed != null) {
        progPercent = parsed.toInt().clamp(0, 100);
      }
    } else if (updates.isNotEmpty) {
      progPercent = updates.last.percentage.clamp(0, 100);
    } else if (json['status'] == 'done' || json['status'] == 'completed') {
      progPercent = 100;
    }

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
      startedAt: (json['startedAt'] ?? json['startTime'])?.toString(),
      workingTime: json['workingTime']?.toString(),
      completedAt: json['completedAt']?.toString(),
      completionTime: json['completionTime']?.toString(),
      projectId: json['projectId']?.toString(),
      projectName: json['projectName']?.toString(),
      isProjectTask: json['isProjectTask'] == true || (json['projectId'] != null && json['projectId'].toString().isNotEmpty),
      attachments: atts,
      progressPercentage: progPercent,
      progressUpdates: updates,
      completionReport: compReport,
      extensionRequest: extReq,
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
      if (startedAt != null) 'startedAt': startedAt,
      if (workingTime != null) 'workingTime': workingTime,
      if (completedAt != null) 'completedAt': completedAt,
      if (completionTime != null) 'completionTime': completionTime,
      if (projectId != null) 'projectId': projectId,
      if (projectName != null) 'projectName': projectName,
      'isProjectTask': isProjectTask,
      if (companyId != null) 'companyId': companyId,
      if (attachments.isNotEmpty) 'attachments': attachments.map((a) => a.toJson()).toList(),
      'progressPercentage': progressPercentage,
      if (progressUpdates.isNotEmpty) 'progressUpdates': progressUpdates.map((u) => u.toJson()).toList(),
      if (completionReport != null) 'completionReport': completionReport!.toJson(),
      if (extensionRequest != null) 'extensionRequest': extensionRequest!.toJson(),
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
    String? startedAt,
    String? workingTime,
    String? completedAt,
    String? completionTime,
    String? projectId,
    String? projectName,
    bool? isProjectTask,
    List<TaskAttachmentModel>? attachments,
    int? progressPercentage,
    List<TaskProgressUpdateModel>? progressUpdates,
    TaskCompletionReportModel? completionReport,
    TaskExtensionRequestModel? extensionRequest,
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
      startedAt: startedAt ?? this.startedAt,
      workingTime: workingTime ?? this.workingTime,
      completedAt: completedAt ?? this.completedAt,
      completionTime: completionTime ?? this.completionTime,
      projectId: projectId ?? this.projectId,
      projectName: projectName ?? this.projectName,
      isProjectTask: isProjectTask ?? this.isProjectTask,
      attachments: attachments ?? this.attachments,
      progressPercentage: progressPercentage ?? this.progressPercentage,
      progressUpdates: progressUpdates ?? this.progressUpdates,
      completionReport: completionReport ?? this.completionReport,
      extensionRequest: extensionRequest ?? this.extensionRequest,
    );
  }

  bool get isCompleted =>
      status.toLowerCase() == 'done' ||
      status.toLowerCase() == 'completed';

  bool get isIncomplete =>
      status.toLowerCase() == 'not_completed' ||
      status.toLowerCase() == 'notcompleted' ||
      isExpired;

  bool get isPending => !isCompleted && !isIncomplete;

  bool get isExpired {
    if (isCompleted) return false;
    if (status.toLowerCase() == 'not_completed' || status.toLowerCase() == 'notcompleted') return true;
    final timeStr = dueTime;
    final endStr = endDate ?? dueDate;
    if (endStr != null && endStr.isNotEmpty) {
      try {
        final datePart = endStr.contains('T') ? endStr.split('T')[0] : endStr;
        final parts = datePart.split('-');
        if (parts.length == 3) {
          int hh = 23;
          int mm = 59;
          if (timeStr != null && timeStr.contains(':')) {
            final tParts = timeStr.split(':');
            hh = int.tryParse(tParts[0]) ?? 23;
            mm = int.tryParse(tParts[1]) ?? 59;
          }
          final deadline = DateTime(
            int.parse(parts[0]),
            int.parse(parts[1]),
            int.parse(parts[2]),
            hh,
            mm,
          );
          return DateTime.now().isAfter(deadline);
        }
      } catch (_) {}
    }
    return false;
  }

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
