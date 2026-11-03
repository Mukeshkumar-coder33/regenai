import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../app/app_config.dart';
import '../../../core/storage/session_storage.dart';
import '../../company/data/company_model.dart';

class PolicyReviewModel {
  final String id;
  final String companyId;
  final String policyId;
  final String policyTitle;
  final String policyContent;
  final String userId;
  final String userName;
  final String userEmail;
  final String department;
  final String status; // 'pending', 'accepted', 'declined', 'allowed'
  final String? declineReason;
  final String? declinedAt;
  final String? allowedAt;
  final String? allowedBy;
  final String? ownerNotes;

  const PolicyReviewModel({
    required this.id,
    required this.companyId,
    required this.policyId,
    required this.policyTitle,
    required this.policyContent,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.department,
    required this.status,
    this.declineReason,
    this.declinedAt,
    this.allowedAt,
    this.allowedBy,
    this.ownerNotes,
  });

  bool get isDeclined => status.toLowerCase() == 'declined';
  bool get isAllowed => status.toLowerCase() == 'allowed';
  bool get isAccepted => status.toLowerCase() == 'accepted';
  bool get isPending => status.toLowerCase() == 'pending';

  factory PolicyReviewModel.fromJson(Map<String, dynamic> json) {
    return PolicyReviewModel(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      companyId: (json['companyId'] ?? '').toString(),
      policyId: (json['policyId'] ?? '').toString(),
      policyTitle: (json['policyTitle'] ?? 'Company Policy').toString(),
      policyContent: (json['policyContent'] ?? '').toString(),
      userId: (json['userId'] ?? '').toString(),
      userName: (json['userName'] ?? 'Employee').toString(),
      userEmail: (json['userEmail'] ?? '').toString(),
      department: (json['department'] ?? 'General').toString(),
      status: (json['status'] ?? 'pending').toString(),
      declineReason: json['declineReason']?.toString(),
      declinedAt: json['declinedAt']?.toString(),
      allowedAt: json['allowedAt']?.toString(),
      allowedBy: json['allowedBy']?.toString(),
      ownerNotes: json['ownerNotes']?.toString(),
    );
  }
}

class EmployeePolicyStatus {
  final bool hasBlockedPolicy;
  final List<Map<String, dynamic>> blockedPolicies;
  final List<Map<String, dynamic>> pendingPolicies;

  const EmployeePolicyStatus({
    required this.hasBlockedPolicy,
    required this.blockedPolicies,
    required this.pendingPolicies,
  });

  factory EmployeePolicyStatus.fromJson(Map<String, dynamic> json) {
    final blocked = (json['blockedPolicies'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final pending = (json['pendingPolicies'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    return EmployeePolicyStatus(
      hasBlockedPolicy: json['hasBlockedPolicy'] == true || blocked.isNotEmpty,
      blockedPolicies: blocked,
      pendingPolicies: pending,
    );
  }
}

class PolicyService {
  final http.Client _client;

  PolicyService({http.Client? client}) : _client = client ?? http.Client();

  Future<Map<String, String>> _getHeaders() async {
    final token = await SessionStorage.getToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// 1. Employee: Check Policy Status (returns whether blocked or has pending policies)
  Future<EmployeePolicyStatus> getEmployeePolicyStatus() async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/policies/employee-status');

    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return EmployeePolicyStatus.fromJson(data);
      }
      return const EmployeePolicyStatus(hasBlockedPolicy: false, blockedPolicies: [], pendingPolicies: []);
    } catch (_) {
      return const EmployeePolicyStatus(hasBlockedPolicy: false, blockedPolicies: [], pendingPolicies: []);
    }
  }

  /// 2. Employee: Accept a Policy
  Future<bool> acceptPolicy(String policyId) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/policies/$policyId/accept');

    try {
      final res = await _client.post(url, headers: headers).timeout(const Duration(seconds: 10));
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  /// 3. Employee: Decline a Policy with Reason
  Future<bool> declinePolicy(String policyId, String reason) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/policies/$policyId/decline');

    try {
      final res = await _client.post(
        url,
        headers: headers,
        body: jsonEncode({'reason': reason}),
      ).timeout(const Duration(seconds: 10));
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  /// 4. Company Owner: Fetch all Employee Policy Reviews / Declined Responses
  Future<List<PolicyReviewModel>> getCompanyPolicyReviews() async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/policies/reviews');

    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>;
        return list.map((json) => PolicyReviewModel.fromJson(json as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// 5. Company Owner: Allow Employee to Work Forward after review
  Future<bool> allowEmployeeWorkForward(String ackId, {String? notes}) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/policies/acknowledgments/$ackId/allow');

    try {
      final res = await _client.post(
        url,
        headers: headers,
        body: jsonEncode({'notes': notes ?? 'Allowed by company owner'}),
      ).timeout(const Duration(seconds: 10));
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  /// 6. Company Owner: Add or Update Company Policy
  Future<CompanyModel?> addCompanyPolicy({
    required String companyId,
    required String title,
    required String content,
    String? effectiveDate,
    required List<CompanyPolicyItem> existingPolicies,
  }) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/company/$companyId');

    final updatedPolicies = List<Map<String, dynamic>>.from(
      existingPolicies.map((p) => p.toJson()),
    );
    updatedPolicies.add({
      'title': title,
      'content': content,
      'effectiveDate': effectiveDate ?? DateTime.now().toIso8601String().substring(0, 10),
    });

    try {
      final res = await _client.put(
        url,
        headers: headers,
        body: jsonEncode({'companyPolicies': updatedPolicies}),
      ).timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return CompanyModel.fromJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 7. Company Owner: Update All Company Profile Details
  Future<CompanyModel?> updateCompanyDetails({
    required String companyId,
    required Map<String, dynamic> updates,
  }) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/company/$companyId');

    try {
      final res = await _client.put(
        url,
        headers: headers,
        body: jsonEncode(updates),
      ).timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return CompanyModel.fromJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
