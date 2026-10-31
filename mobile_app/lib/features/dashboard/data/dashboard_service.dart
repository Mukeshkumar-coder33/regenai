import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../../app/app_config.dart';
import '../../../core/storage/session_storage.dart';
import '../../attendance/data/attendance_model.dart';
import '../../auth/data/auth_service.dart';
import '../../auth/data/user_model.dart';
import '../../company/data/company_model.dart';
import '../../tasks/data/task_model.dart';
import 'leave_model.dart';

/// Central Dashboard API Service
///
/// Fetches live business data from the ReGen Node.js/Express backend
/// using authenticated requests with Bearer tokens.
class DashboardService {
  final http.Client _client;

  DashboardService({http.Client? client}) : _client = client ?? http.Client();

  /// Helper to get common authenticated headers
  Future<Map<String, String>> _getHeaders({bool isSuperAdmin = false}) async {
    final token = await SessionStorage.getToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (isSuperAdmin) {
      headers['x-portal-view'] = 'superadmin';
    }
    return headers;
  }

  /// Fetch Companies
  ///
  /// For Super Admin (isSuperAdmin: true), returns all companies on the platform.
  /// For Company Owner / Employee, returns only the user's company.
  Future<List<CompanyModel>> getCompanies({bool isSuperAdmin = false}) async {
    final headers = await _getHeaders(isSuperAdmin: isSuperAdmin);
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/company');

    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
        return data.map((json) => CompanyModel.fromJson(json as Map<String, dynamic>)).toList();
      }
      throw AuthException(
        message: 'Failed to load companies (${res.statusCode})',
        statusCode: res.statusCode,
      );
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable', statusCode: 0);
    }
  }

  /// Fetch Users
  ///
  /// For Super Admin, returns all platform users.
  /// For Company Owner / Employee, returns all members of the company.
  Future<List<UserModel>> getUsers({bool isSuperAdmin = false}) async {
    final headers = await _getHeaders(isSuperAdmin: isSuperAdmin);
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/users');

    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
        return data.map((json) => UserModel.fromJson(json as Map<String, dynamic>)).toList();
      }
      throw AuthException(
        message: 'Failed to load user list (${res.statusCode})',
        statusCode: res.statusCode,
      );
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable', statusCode: 0);
    }
  }

  /// Fetch Current User Profile (/api/users/me)
  Future<UserModel> getMe() async {
    final headers = await _getHeaders();
    final url = Uri.parse(AppConfig.profileUrl);

    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(res.body) as Map<String, dynamic>;
        return UserModel.fromJson(data);
      }
      throw AuthException(
        message: 'Failed to load profile (${res.statusCode})',
        statusCode: res.statusCode,
      );
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable', statusCode: 0);
    }
  }

  /// Fetch Tasks (/api/tasks)
  Future<List<TaskModel>> getTasks() async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/tasks');

    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
        return data.map((json) => TaskModel.fromJson(json as Map<String, dynamic>)).toList();
      }
      throw AuthException(
        message: 'Failed to load tasks (${res.statusCode})',
        statusCode: res.statusCode,
      );
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable', statusCode: 0);
    }
  }

  /// Fetch Attendance Records (/api/attendance)
  Future<List<AttendanceModel>> getAttendance() async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/attendance');

    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
        return data.map((json) => AttendanceModel.fromJson(json as Map<String, dynamic>)).toList();
      }
      throw AuthException(
        message: 'Failed to load attendance (${res.statusCode})',
        statusCode: res.statusCode,
      );
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable', statusCode: 0);
    }
  }

  /// Fetch Leave Requests (/api/leaves)
  Future<List<LeaveModel>> getLeaves() async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/leaves');

    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
        return data.map((json) => LeaveModel.fromJson(json as Map<String, dynamic>)).toList();
      }
      throw AuthException(
        message: 'Failed to load leaves (${res.statusCode})',
        statusCode: res.statusCode,
      );
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable', statusCode: 0);
    }
  }
}

