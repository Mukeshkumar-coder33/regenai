/// ReGen Notification Model
///
/// Maps exactly to MongoDB `Notification` documents returned by `GET /api/notifications/user/:userId`.
class NotificationModel {
  final String id;
  final String? mongoId;
  final String? companyId;
  final String userId;
  final String title;
  final String message;
  final String type;
  final String? senderId;
  final String? senderName;
  final String? conversationId;
  final String? callId;
  final String? meetingId;
  final String actionStatus;
  final Map<String, dynamic> metadata;
  final String createdAt;
  bool read;

  NotificationModel({
    required this.id,
    this.mongoId,
    this.companyId,
    required this.userId,
    required this.title,
    required this.message,
    this.type = 'general',
    this.senderId,
    this.senderName,
    this.conversationId,
    this.callId,
    this.meetingId,
    this.actionStatus = 'none',
    this.metadata = const {},
    required this.createdAt,
    this.read = false,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      mongoId: json['_id']?.toString(),
      companyId: json['companyId']?.toString(),
      userId: (json['userId'] ?? '').toString(),
      title: (json['title'] ?? 'Notification').toString(),
      message: (json['message'] ?? '').toString(),
      type: (json['type'] ?? 'general').toString(),
      senderId: json['senderId']?.toString(),
      senderName: json['senderName']?.toString(),
      conversationId: json['conversationId']?.toString(),
      callId: json['callId']?.toString(),
      meetingId: json['meetingId']?.toString(),
      actionStatus: (json['actionStatus'] ?? 'none').toString(),
      metadata: json['metadata'] is Map<String, dynamic>
          ? json['metadata'] as Map<String, dynamic>
          : <String, dynamic>{},
      createdAt: (json['createdAt'] ?? DateTime.now().toIso8601String()).toString(),
      read: json['read'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'title': title,
      'message': message,
      'type': type,
      if (companyId != null) 'companyId': companyId,
      if (senderId != null) 'senderId': senderId,
      if (senderName != null) 'senderName': senderName,
      if (conversationId != null) 'conversationId': conversationId,
      if (callId != null) 'callId': callId,
      if (meetingId != null) 'meetingId': meetingId,
      'actionStatus': actionStatus,
      'metadata': metadata,
      'createdAt': createdAt,
      'read': read,
    };
  }

  NotificationModel copyWith({
    String? id,
    String? mongoId,
    String? companyId,
    String? userId,
    String? title,
    String? message,
    String? type,
    String? senderId,
    String? senderName,
    String? conversationId,
    String? callId,
    String? meetingId,
    String? actionStatus,
    Map<String, dynamic>? metadata,
    String? createdAt,
    bool? read,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      mongoId: mongoId ?? this.mongoId,
      companyId: companyId ?? this.companyId,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      message: message ?? this.message,
      type: type ?? this.type,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      conversationId: conversationId ?? this.conversationId,
      callId: callId ?? this.callId,
      meetingId: meetingId ?? this.meetingId,
      actionStatus: actionStatus ?? this.actionStatus,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      read: read ?? this.read,
    );
  }

  bool get isCall => type == 'voice_call' || type == 'video_call';
  bool get isMeeting => type == 'team_meeting';
  bool get isTask => type.contains('task') || title.toLowerCase().contains('task') || message.toLowerCase().contains('task');
  bool get isAttendance => type.contains('attendance') || type.contains('leave') || title.toLowerCase().contains('leave') || message.toLowerCase().contains('leave');
  bool get isPayment => type.contains('payment') || type.contains('payroll') || type.contains('salary') || type.contains('bonus');
  bool get isBirthday => title.toLowerCase().contains('birthday') || message.toLowerCase().contains('birthday');
  bool get isSystem => type == 'general' || type == 'policy';
}

