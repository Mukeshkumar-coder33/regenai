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
  final int workingDays;
  final String? reason;
  final String status;
  final String createdAt;
  final String appliedAt;
  final String? approvedBy;
  final String? approvedByName;
  final String? approvalDate;
  final String? rejectionReason;
  final String? remarks;
  final String? employeeName;
  final String? department;
  final num? balanceAtRequest;

  const LeaveModel({
    required this.id,
    this.companyId,
    required this.userId,
    this.type = 'casual',
    required this.startDate,
    required this.endDate,
    this.workingDays = 1,
    this.reason,
    this.status = 'pending',
    this.createdAt = '',
    this.appliedAt = '',
    this.approvedBy,
    this.approvedByName,
    this.approvalDate,
    this.rejectionReason,
    this.remarks,
    this.employeeName,
    this.department,
    this.balanceAtRequest,
  });

  factory LeaveModel.fromJson(Map<String, dynamic> json) {
    return LeaveModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      companyId: json['companyId']?.toString(),
      userId: (json['userId'] ?? '').toString(),
      type: (json['type'] ?? 'casual').toString().toLowerCase(),
      startDate: (json['startDate'] ?? '').toString(),
      endDate: (json['endDate'] ?? '').toString(),
      workingDays: (json['workingDays'] as num?)?.toInt() ?? 1,
      reason: json['reason']?.toString(),
      status: (json['status'] ?? 'pending').toString(),
      createdAt: (json['createdAt'] ?? json['appliedDate'] ?? json['appliedAt'] ?? json['date'] ?? '').toString(),
      appliedAt: (json['appliedAt'] ?? json['createdAt'] ?? '').toString(),
      approvedBy: json['approvedBy']?.toString(),
      approvedByName: json['approvedByName']?.toString(),
      approvalDate: json['approvalDate']?.toString(),
      rejectionReason: (json['rejectionReason'] ?? json['remarks'])?.toString(),
      remarks: (json['remarks'] ?? json['rejectionReason'])?.toString(),
      employeeName: json['employeeName']?.toString(),
      department: json['department']?.toString(),
      balanceAtRequest: json['balanceAtRequest'] as num?,
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

/// Leave Policy Model representing company leave configuration
class LeavePolicyModel {
  final LeaveTypePolicy casualLeave;
  final LeaveTypePolicy sickLeave;
  final LeaveTypePolicy earnedLeave;
  final UnpaidLeavePolicy unpaidLeave;

  const LeavePolicyModel({
    required this.casualLeave,
    required this.sickLeave,
    this.earnedLeave = const LeaveTypePolicy(maxCarryForward: 24.0),
    required this.unpaidLeave,
  });

  factory LeavePolicyModel.fromJson(Map<String, dynamic> json) {
    return LeavePolicyModel(
      casualLeave: LeaveTypePolicy.fromJson((json['casualLeave'] as Map<String, dynamic>?) ?? {}),
      sickLeave: LeaveTypePolicy.fromJson((json['sickLeave'] as Map<String, dynamic>?) ?? {}),
      earnedLeave: LeaveTypePolicy.fromJson((json['earnedLeave'] as Map<String, dynamic>?) ?? {}),
      unpaidLeave: UnpaidLeavePolicy.fromJson((json['unpaidLeave'] as Map<String, dynamic>?) ?? {}),
    );
  }

  factory LeavePolicyModel.defaultPolicy() {
    return const LeavePolicyModel(
      casualLeave: LeaveTypePolicy(
        enabled: true,
        monthlyEntitlement: 1.0,
        carryForward: true,
        maxCarryForward: 12.0,
        requiresApproval: true,
        unapprovedDeductionRate: 100.0,
      ),
      sickLeave: LeaveTypePolicy(
        enabled: true,
        monthlyEntitlement: 1.0,
        carryForward: false,
        maxCarryForward: 6.0,
        requiresApproval: true,
        unapprovedDeductionRate: 100.0,
      ),
      earnedLeave: LeaveTypePolicy(
        enabled: true,
        monthlyEntitlement: 1.0,
        carryForward: true,
        maxCarryForward: 24.0,
        requiresApproval: true,
        unapprovedDeductionRate: 100.0,
      ),
      unpaidLeave: UnpaidLeavePolicy(
        enabled: true,
        approvedDeductionRate: 100.0,
        unapprovedDeductionRate: 100.0,
        sameDeductionRate: true,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'casualLeave': casualLeave.toJson(),
    'sickLeave': sickLeave.toJson(),
    'earnedLeave': earnedLeave.toJson(),
    'unpaidLeave': unpaidLeave.toJson(),
  };
}

class LeaveTypePolicy {
  final bool enabled;
  final double monthlyEntitlement;
  final bool carryForward;
  final double maxCarryForward;
  final bool requiresApproval;
  final double unapprovedDeductionRate;

  const LeaveTypePolicy({
    this.enabled = true,
    this.monthlyEntitlement = 1.0,
    this.carryForward = true,
    this.maxCarryForward = 12.0,
    this.requiresApproval = true,
    this.unapprovedDeductionRate = 100.0,
  });

  factory LeaveTypePolicy.fromJson(Map<String, dynamic> json) {
    return LeaveTypePolicy(
      enabled: json['enabled'] != false,
      monthlyEntitlement: (json['monthlyEntitlement'] as num?)?.toDouble() ?? 1.0,
      carryForward: json['carryForward'] == true,
      maxCarryForward: (json['maxCarryForward'] as num?)?.toDouble() ?? 12.0,
      requiresApproval: json['requiresApproval'] != false,
      unapprovedDeductionRate: (json['unapprovedDeductionRate'] as num?)?.toDouble() ?? 100.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'monthlyEntitlement': monthlyEntitlement,
    'carryForward': carryForward,
    'maxCarryForward': maxCarryForward,
    'requiresApproval': requiresApproval,
    'unapprovedDeductionRate': unapprovedDeductionRate,
  };
}

class UnpaidLeavePolicy {
  final bool enabled;
  final double approvedDeductionRate;
  final double unapprovedDeductionRate;
  final bool sameDeductionRate;

  const UnpaidLeavePolicy({
    this.enabled = true,
    this.approvedDeductionRate = 100.0,
    this.unapprovedDeductionRate = 100.0,
    this.sameDeductionRate = true,
  });

  factory UnpaidLeavePolicy.fromJson(Map<String, dynamic> json) {
    return UnpaidLeavePolicy(
      enabled: json['enabled'] != false,
      approvedDeductionRate: (json['approvedDeductionRate'] as num?)?.toDouble() ?? 100.0,
      unapprovedDeductionRate: (json['unapprovedDeductionRate'] as num?)?.toDouble() ?? 100.0,
      sameDeductionRate: json['sameDeductionRate'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'approvedDeductionRate': approvedDeductionRate,
    'unapprovedDeductionRate': unapprovedDeductionRate,
    'sameDeductionRate': sameDeductionRate,
  };
}

/// Leave Balance Model for individual employee
class LeaveBalanceModel {
  final LeaveBalanceCategory casual;
  final LeaveBalanceCategory sick;
  final UnpaidBalanceCategory unpaid;

  const LeaveBalanceModel({
    required this.casual,
    required this.sick,
    required this.unpaid,
  });

  factory LeaveBalanceModel.fromJson(Map<String, dynamic> json) {
    return LeaveBalanceModel(
      casual: LeaveBalanceCategory.fromJson((json['casual'] as Map<String, dynamic>?) ?? {}),
      sick: LeaveBalanceCategory.fromJson((json['sick'] as Map<String, dynamic>?) ?? {}),
      unpaid: UnpaidBalanceCategory.fromJson((json['unpaid'] as Map<String, dynamic>?) ?? {}),
    );
  }

  factory LeaveBalanceModel.initial() {
    return const LeaveBalanceModel(
      casual: LeaveBalanceCategory(enabled: true, entitlement: 1, carriedForward: 0, used: 0, remaining: 1),
      sick: LeaveBalanceCategory(enabled: true, entitlement: 1, carriedForward: 0, used: 0, remaining: 1),
      unpaid: UnpaidBalanceCategory(enabled: true, used: 0, approvedDeductionRate: 100, unapprovedDeductionRate: 100),
    );
  }
}

class LeaveBalanceCategory {
  final bool enabled;
  final double entitlement;
  final double carriedForward;
  final double used;
  final double remaining;
  final bool requiresApproval;
  final double unapprovedDeductionRate;

  const LeaveBalanceCategory({
    this.enabled = true,
    this.entitlement = 1.0,
    this.carriedForward = 0.0,
    this.used = 0.0,
    this.remaining = 1.0,
    this.requiresApproval = true,
    this.unapprovedDeductionRate = 100.0,
  });

  factory LeaveBalanceCategory.fromJson(Map<String, dynamic> json) {
    return LeaveBalanceCategory(
      enabled: json['enabled'] != false,
      entitlement: (json['entitlement'] as num?)?.toDouble() ?? 1.0,
      carriedForward: (json['carriedForward'] as num?)?.toDouble() ?? 0.0,
      used: (json['used'] as num?)?.toDouble() ?? 0.0,
      remaining: (json['remaining'] as num?)?.toDouble() ?? 0.0,
      requiresApproval: json['requiresApproval'] != false,
      unapprovedDeductionRate: (json['unapprovedDeductionRate'] as num?)?.toDouble() ?? 100.0,
    );
  }
}

class UnpaidBalanceCategory {
  final bool enabled;
  final double used;
  final double approvedDeductionRate;
  final double unapprovedDeductionRate;
  final bool sameDeductionRate;

  const UnpaidBalanceCategory({
    this.enabled = true,
    this.used = 0.0,
    this.approvedDeductionRate = 100.0,
    this.unapprovedDeductionRate = 100.0,
    this.sameDeductionRate = true,
  });

  factory UnpaidBalanceCategory.fromJson(Map<String, dynamic> json) {
    return UnpaidBalanceCategory(
      enabled: json['enabled'] != false,
      used: (json['used'] as num?)?.toDouble() ?? 0.0,
      approvedDeductionRate: (json['approvedDeductionRate'] as num?)?.toDouble() ?? 100.0,
      unapprovedDeductionRate: (json['unapprovedDeductionRate'] as num?)?.toDouble() ?? 100.0,
      sameDeductionRate: json['sameDeductionRate'] != false,
    );
  }
}
