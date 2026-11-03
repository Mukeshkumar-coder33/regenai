/// ReGen Leave Request Model
///
/// Maps to MongoDB `Leave` documents returned by `GET /api/leaves`.
class LeaveModel {
  final String id;
  final String? companyId;
  final String userId;
  final String type;
  final String startDate;
  final String endDate;
  final String? reason;
  final String status;
  final String createdAt;

  const LeaveModel({
    required this.id,
    this.companyId,
    required this.userId,
    this.type = 'casual',
    required this.startDate,
    required this.endDate,
    this.reason,
    this.status = 'pending',
    this.createdAt = '',
  });

  factory LeaveModel.fromJson(Map<String, dynamic> json) {
    return LeaveModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      companyId: json['companyId']?.toString(),
      userId: (json['userId'] ?? '').toString(),
      type: (json['type'] ?? 'casual').toString(),
      startDate: (json['startDate'] ?? '').toString(),
      endDate: (json['endDate'] ?? '').toString(),
      reason: json['reason']?.toString(),
      status: (json['status'] ?? 'pending').toString(),
      createdAt: (json['createdAt'] ?? json['appliedDate'] ?? json['appliedAt'] ?? json['date'] ?? '').toString(),
    );
  }

  bool get isApproved => status.toLowerCase() == 'approved';
  bool get isPending => status.toLowerCase() == 'pending';
  bool get isRejected => status.toLowerCase() == 'rejected' || status.toLowerCase() == 'not_approved' || status.toLowerCase() == 'not approved';
  bool get isNotApproved => isRejected;

  String get displayStatus {
    if (isApproved) return 'Approved';
    if (isRejected) return 'Not Approved';
    return 'Pending';
  }

  bool coversDate(String targetDate) {
    if (startDate.isEmpty || endDate.isEmpty || targetDate.isEmpty) return false;
    return startDate.compareTo(targetDate) <= 0 && endDate.compareTo(targetDate) >= 0;
  }

  String get displayType {
    if (type.isEmpty) return 'Leave';
    return '${type[0].toUpperCase()}${type.substring(1)} Leave';
  }
}
