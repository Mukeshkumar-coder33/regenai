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

  /// 1. Fetch All Leaves (Company / Super Admin view)
  Future<List<LeaveModel>> getAllLeaves() async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/leaves');

    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
        return data.map((json) => LeaveModel.fromJson(json as Map<String, dynamic>)).toList();
      }
      throw AuthException(message: 'Failed to load leaves (${res.statusCode})', statusCode: res.statusCode);
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable', statusCode: 0);
    }
  }

  /// 2. Fetch User Leaves (Employee view)
  Future<List<LeaveModel>> getUserLeaves(String userId) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/leaves/user/$userId');

    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
        return data.map((json) => LeaveModel.fromJson(json as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// 3. Apply for Leave
  Future<LeaveModel> applyLeave({
    required String type,
    required String startDate,
    required String endDate,
    String? reason,
    String? userId,
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
      throw AuthException(message: 'Failed to submit leave request (${res.statusCode})', statusCode: res.statusCode);
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable', statusCode: 0);
    }
  }

  /// 4. Approve or Reject Leave (Manager / Admin action)
  Future<LeaveModel> updateLeaveStatus({
    required String id,
    required String status, // 'approved' or 'rejected'
  }) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/leaves/$id');

    try {
      final res = await _client.put(
        url,
        headers: headers,
        body: jsonEncode({'status': status}),
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
}

