import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../../app/app_config.dart';
import '../../../core/storage/session_storage.dart';
import '../../auth/data/auth_service.dart';
import '../../dashboard/data/leave_model.dart';

/// ReGen Leave Requests Service
///
/// Connects to:
/// - `GET/POST /api/leaves`
/// - `GET /api/leaves/user/:userId`
/// - `PUT /api/leaves/:id` (Approve/Reject)
/// - `GET /api/leaves/policy`
/// - `PUT /api/leaves/policy`
/// - `GET /api/leaves/balance`
class LeaveService {
  final http.Client _client;

  LeaveService({http.Client? client}) : _client = client ?? http.Client();

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

  /// 1. Fetch Company Leave Policy
  Future<LeavePolicyModel> getLeavePolicy() async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/leaves/policy');

    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return LeavePolicyModel.fromJson(data);
      }
      return LeavePolicyModel.defaultPolicy();
    } catch (_) {
      return LeavePolicyModel.defaultPolicy();
    }
  }

  /// 2. Update Company Leave Policy
  Future<LeavePolicyModel> updateLeavePolicy(Map<String, dynamic> policyData) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/leaves/policy');

    try {
      final res = await _client.put(
        url,
        headers: headers,
        body: jsonEncode(policyData),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return LeavePolicyModel.fromJson(data);
      }
      throw AuthException(
        message: 'Failed to update leave policy (${res.statusCode})',
        statusCode: res.statusCode,
      );
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable', statusCode: 0);
    }
  }

  /// 3. Fetch Leave Balance for Current or Specified User
  Future<LeaveBalanceModel> getLeaveBalance({String? userId}) async {
    final headers = await _getHeaders();
    final endpoint = userId != null && userId.isNotEmpty
        ? '${AppConfig.activeBaseUrl}/api/leaves/balance/$userId'
        : '${AppConfig.activeBaseUrl}/api/leaves/balance';
    final url = Uri.parse(endpoint);

    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return LeaveBalanceModel.fromJson(data);
      }
      return LeaveBalanceModel.initial();
    } catch (_) {
      return LeaveBalanceModel.initial();
    }
  }

  /// 4. Fetch All Leaves (Company / Super Admin view)
  Future<List<LeaveModel>> getAllLeaves({
    String? status,
    String? type,
    int? page,
    int? limit,
  }) async {
    final headers = await _getHeaders();
    final queryParams = <String, String>{};
    if (status != null && status.isNotEmpty && status.toLowerCase() != 'all') {
      queryParams['status'] = status.toLowerCase();
    }
    if (type != null && type.isNotEmpty && type.toLowerCase() != 'all') {
      queryParams['type'] = type.toLowerCase();
    }
    if (page != null) queryParams['page'] = page.toString();
    if (limit != null) queryParams['limit'] = limit.toString();

    final uri = Uri.parse('${AppConfig.activeBaseUrl}/api/leaves').replace(
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );

    try {
      final res = await _client.get(uri, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is List) {
          return decoded.map((json) => LeaveModel.fromJson(json as Map<String, dynamic>)).toList();
        } else if (decoded is Map<String, dynamic> && decoded['leaves'] is List) {
          final list = decoded['leaves'] as List<dynamic>;
          return list.map((json) => LeaveModel.fromJson(json as Map<String, dynamic>)).toList();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// 5. Fetch User Leaves (Employee view)
  Future<List<LeaveModel>> getUserLeaves(
    String userId, {
    String? status,
    int? page,
    int? limit,
  }) async {
    final headers = await _getHeaders();
    final queryParams = <String, String>{};
    if (status != null && status.isNotEmpty && status.toLowerCase() != 'all') {
      queryParams['status'] = status.toLowerCase();
    }
    if (page != null) queryParams['page'] = page.toString();
    if (limit != null) queryParams['limit'] = limit.toString();

    final uri = Uri.parse('${AppConfig.activeBaseUrl}/api/leaves/user/$userId').replace(
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );

    try {
      final res = await _client.get(uri, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is List) {
          return decoded.map((json) => LeaveModel.fromJson(json as Map<String, dynamic>)).toList();
        } else if (decoded is Map<String, dynamic> && decoded['leaves'] is List) {
          final list = decoded['leaves'] as List<dynamic>;
          return list.map((json) => LeaveModel.fromJson(json as Map<String, dynamic>)).toList();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// 6. Apply for Leave
  Future<LeaveModel> applyLeave({
    required String type,
    required String startDate,
    required String endDate,
    String? reason,
    String? userId,
    int? workingDays,
  }) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/leaves');

    final payload = <String, dynamic>{
      'type': type.toLowerCase(),
      'startDate': startDate,
      'endDate': endDate,
      'reason': reason ?? '',
    };
    if (userId != null) {
      payload['userId'] = userId;
    }
    if (workingDays != null) {
      payload['workingDays'] = workingDays;
    }

    try {
      final res = await _client.post(
        url,
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200 || res.statusCode == 201) {
        final Map<String, dynamic> data = jsonDecode(res.body) as Map<String, dynamic>;
        return LeaveModel.fromJson(data);
      }
      final errorBody = jsonDecode(res.body);
      final errMsg = errorBody is Map && errorBody['message'] != null
          ? errorBody['message'].toString()
          : 'Failed to submit leave request (${res.statusCode})';
      throw AuthException(message: errMsg, statusCode: res.statusCode);
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable', statusCode: 0);
    }
  }

  /// 7. Approve or Reject Leave (Manager / Admin action)
  Future<LeaveModel> updateLeaveStatus({
    required String id,
    required String status, // 'approved' or 'rejected'
    String? remarks,
  }) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/leaves/$id');

    final payload = <String, dynamic>{'status': status};
    if (remarks != null && remarks.isNotEmpty) {
      payload['remarks'] = remarks;
      payload['rejectionReason'] = remarks;
    }

    try {
      final res = await _client.put(
        url,
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(res.body) as Map<String, dynamic>;
        return LeaveModel.fromJson(data);
      }
      throw AuthException(message: 'Failed to update leave request (${res.statusCode})', statusCode: res.statusCode);
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable', statusCode: 0);
    }
  }

  /// 8. Delete Leave Application
  Future<bool> deleteLeave(String id) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/leaves/$id');

    try {
      final res = await _client.delete(url, headers: headers).timeout(const Duration(seconds: 10));
      return res.statusCode == 200 || res.statusCode == 204;
    } catch (_) {
      return false;
    }
  }
}
