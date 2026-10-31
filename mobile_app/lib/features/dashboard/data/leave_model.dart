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

  const LeaveModel({
    required this.id,
    this.companyId,
    required this.userId,
    this.type = 'casual',
    required this.startDate,
    required this.endDate,
    this.reason,
    this.status = 'pending',
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
    );
  }

  bool get isApproved => status.toLowerCase() == 'approved';
  bool get isPending => status.toLowerCase() == 'pending';
  bool get isRejected => status.toLowerCase() == 'rejected';
}

