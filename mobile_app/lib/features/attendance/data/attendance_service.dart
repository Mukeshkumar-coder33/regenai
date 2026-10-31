import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../../app/app_config.dart';
import '../../../core/storage/session_storage.dart';
import '../../auth/data/auth_service.dart';
import '../../calendar/data/holiday_model.dart';
import 'attendance_model.dart';
import 'attendance_report_model.dart';
import 'work_schedule_model.dart';

/// Custom Exception for Geofence & Location validation failures
class GeofenceException implements Exception {
  final String message;
  final String? code;
  final double? distance;
  final double? maxAllowedDistance;

  const GeofenceException({
    required this.message,
    this.code,
    this.distance,
    this.maxAllowedDistance,
  });

  @override
  String toString() => message;
}

/// Central Attendance & Scheduling Service
///
/// Handles real GPS geofenced check-ins, check-outs, break management,
/// work schedules, company roster, and calendar holidays.
class AttendanceService {
  final http.Client _client;

  AttendanceService({http.Client? client}) : _client = client ?? http.Client();

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

  static String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Get today's attendance record for the current user
  Future<AttendanceModel?> getTodayAttendance({String? userId}) async {
    final user = await SessionStorage.getUserSession();
    final targetUserId = userId ?? user?.userId ?? user?.id ?? '';
    if (targetUserId.isEmpty) return null;

    final todayStr = _formatDate(DateTime.now());
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/attendance/user/$targetUserId');

    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final List<dynamic> list = jsonDecode(res.body) as List<dynamic>;
        for (final item in list) {
          final att = AttendanceModel.fromJson(item as Map<String, dynamic>);
          if (att.date == todayStr) {
            return att;
          }
        }
        return null;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Get all attendance records for a user
  Future<List<AttendanceModel>> getUserAttendanceHistory(String userId) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/attendance/user/$userId');

    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final List<dynamic> list = jsonDecode(res.body) as List<dynamic>;
        final results = list.map((item) => AttendanceModel.fromJson(item as Map<String, dynamic>)).toList();
        // Sort newest first
        results.sort((a, b) => b.date.compareTo(a.date));
        return results;
      }
      throw AuthException(message: 'Failed to load attendance history (${res.statusCode})');
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable');
    }
  }

  /// Get company attendance roster (Company Owner / Admin)
  Future<List<AttendanceModel>> getCompanyAttendance() async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/attendance');

    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final List<dynamic> list = jsonDecode(res.body) as List<dynamic>;
        final results = list.map((item) => AttendanceModel.fromJson(item as Map<String, dynamic>)).toList();
        results.sort((a, b) => b.date.compareTo(a.date));
        return results;
      }
      throw AuthException(message: 'Failed to load company attendance (${res.statusCode})');
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable');
    }
  }

  /// Check-In with real GPS coordinates (Backend validates <= 5 metres)
  Future<AttendanceModel> checkIn({
    required double latitude,
    required double longitude,
    double? accuracy,
    String? workMode,
  }) async {
    final user = await SessionStorage.getUserSession();
    final userId = user?.userId ?? user?.id ?? '';
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/attendance');
    final now = DateTime.now();
    final todayStr = _formatDate(now);

    final body = jsonEncode({
      'userId': userId,
      'date': todayStr,
      'status': 'present',
      'checkIn': now.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'workMode': workMode ?? 'office',
    });

    try {
      final res = await _client.post(url, headers: headers, body: body).timeout(const Duration(seconds: 12));
      final dynamic data = jsonDecode(res.body);

      if (res.statusCode == 200 || res.statusCode == 201) {
        return AttendanceModel.fromJson(data as Map<String, dynamic>);
      }

      final errorMsg = data is Map ? (data['message'] ?? 'Check-in failed') : 'Check-in failed';
      final errorCode = data is Map ? data['code']?.toString() : null;
      final dist = data is Map && data['distance'] != null ? double.tryParse(data['distance'].toString()) : null;
      final maxDist = data is Map && data['maxAllowedDistance'] != null ? double.tryParse(data['maxAllowedDistance'].toString()) : null;

      throw GeofenceException(
        message: errorMsg.toString(),
        code: errorCode,
        distance: dist,
        maxAllowedDistance: maxDist,
      );
    } on SocketException {
      throw const GeofenceException(message: 'Server unreachable. Please check connection.');
    }
  }

  /// Check-Out with real GPS coordinates
  Future<AttendanceModel> checkOut({
    required String attendanceId,
    required double latitude,
    required double longitude,
    double? accuracy,
  }) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/attendance/$attendanceId');
    final now = DateTime.now();

    final body = jsonEncode({
      'checkOut': now.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
    });

    try {
      final res = await _client.put(url, headers: headers, body: body).timeout(const Duration(seconds: 12));
      final dynamic data = jsonDecode(res.body);

      if (res.statusCode == 200) {
        return AttendanceModel.fromJson(data as Map<String, dynamic>);
      }

      final errorMsg = data is Map ? (data['message'] ?? 'Check-out failed') : 'Check-out failed';
      final errorCode = data is Map ? data['code']?.toString() : null;
      final dist = data is Map && data['distance'] != null ? double.tryParse(data['distance'].toString()) : null;
      final maxDist = data is Map && data['maxAllowedDistance'] != null ? double.tryParse(data['maxAllowedDistance'].toString()) : null;

      throw GeofenceException(
        message: errorMsg.toString(),
        code: errorCode,
        distance: dist,
        maxAllowedDistance: maxDist,
      );
    } on SocketException {
      throw const GeofenceException(message: 'Server unreachable. Please check connection.');
    }
  }

  /// Start Official Break (Lunch) or Casual Break (Tea/Coffee)
  Future<AttendanceModel> startBreak({
    required String attendanceId,
    required String breakType, // 'official' or 'casual'
    required double latitude,
    required double longitude,
    double? accuracy,
  }) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/attendance/$attendanceId');
    final now = DateTime.now();

    final Map<String, dynamic> payload = {
      'activeBreakType': breakType,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
    };
    if (breakType == 'official') {
      payload['breakStart'] = now.toIso8601String();
    } else {
      payload['casualBreakStart'] = now.toIso8601String();
    }

    try {
      final res = await _client.put(url, headers: headers, body: jsonEncode(payload)).timeout(const Duration(seconds: 12));
      final dynamic data = jsonDecode(res.body);

      if (res.statusCode == 200) {
        return AttendanceModel.fromJson(data as Map<String, dynamic>);
      }

      final errorMsg = data is Map ? (data['message'] ?? 'Failed to start break') : 'Failed to start break';
      final errorCode = data is Map ? data['code']?.toString() : null;
      final dist = data is Map && data['distance'] != null ? double.tryParse(data['distance'].toString()) : null;
      final maxDist = data is Map && data['maxAllowedDistance'] != null ? double.tryParse(data['maxAllowedDistance'].toString()) : null;

      throw GeofenceException(
        message: errorMsg.toString(),
        code: errorCode,
        distance: dist,
        maxAllowedDistance: maxDist,
      );
    } on SocketException {
      throw const GeofenceException(message: 'Server unreachable. Please check connection.');
    }
  }

  /// End Break and return to work
  Future<AttendanceModel> endBreak({
    required String attendanceId,
    required String breakType,
    required double latitude,
    required double longitude,
    double? accuracy,
  }) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/attendance/$attendanceId');
    final now = DateTime.now();

    final Map<String, dynamic> payload = {
      'activeBreakType': 'none',
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
    };
    if (breakType == 'official') {
      payload['breakEnd'] = now.toIso8601String();
    } else {
      payload['casualBreakEnd'] = now.toIso8601String();
    }

    try {
      final res = await _client.put(url, headers: headers, body: jsonEncode(payload)).timeout(const Duration(seconds: 12));
      final dynamic data = jsonDecode(res.body);

      if (res.statusCode == 200) {
        return AttendanceModel.fromJson(data as Map<String, dynamic>);
      }

      final errorMsg = data is Map ? (data['message'] ?? 'Failed to end break') : 'Failed to end break';
      final errorCode = data is Map ? data['code']?.toString() : null;
      final dist = data is Map && data['distance'] != null ? double.tryParse(data['distance'].toString()) : null;
      final maxDist = data is Map && data['maxAllowedDistance'] != null ? double.tryParse(data['maxAllowedDistance'].toString()) : null;

      throw GeofenceException(
        message: errorMsg.toString(),
        code: errorCode,
        distance: dist,
        maxAllowedDistance: maxDist,
      );
    } on SocketException {
      throw const GeofenceException(message: 'Server unreachable. Please check connection.');
    }
  }

  /// Get Work Schedule & Shift Settings (`GET /api/payroll/settings`)
  Future<WorkScheduleModel> getWorkSchedule() async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/payroll/settings');

    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return WorkScheduleModel.fromJson(data);
      }
      return const WorkScheduleModel();
    } catch (_) {
      return const WorkScheduleModel();
    }
  }

  /// Update Work Schedule & Shift Settings (`PUT /api/payroll/settings`)
  Future<WorkScheduleModel> updateWorkSchedule(WorkScheduleModel schedule) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/payroll/settings');

    try {
      final res = await _client.put(url, headers: headers, body: jsonEncode(schedule.toJson())).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return WorkScheduleModel.fromJson(data);
      }
      throw AuthException(message: 'Failed to update shift settings (${res.statusCode})');
    } on SocketException {
      throw const AuthException(message: 'Server unreachable');
    }
  }

  /// Get Company Holidays (`GET /api/holidays`)
  Future<List<HolidayModel>> getHolidays() async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/holidays');

    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final List<dynamic> list = jsonDecode(res.body) as List<dynamic>;
        return list.map((item) => HolidayModel.fromJson(item as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Get Attendance Report (`GET /api/attendance/report?period=day|week|month|year`)
  Future<AttendanceReportModel> getAttendanceReport({String period = 'month', String? date}) async {
    final headers = await _getHeaders();
    String query = 'period=$period';
    if (date != null && date.isNotEmpty) {
      query += '&date=$date';
    }
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/attendance/report?$query');

    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return AttendanceReportModel.fromJson(data);
      }
      throw AuthException(message: 'Failed to load attendance report (${res.statusCode})');
    } on SocketException {
      throw const AuthException(message: 'Server unreachable');
    }
  }

  /// Configure Company Office Location & Geofence (`PUT /api/company/:id/office-location`)
  Future<void> updateOfficeLocation(
    String companyId, {
    required double latitude,
    required double longitude,
    String? address,
  }) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/company/$companyId/office-location');

    final body = jsonEncode({
      'latitude': latitude,
      'longitude': longitude,
      'address': address ?? 'Company Office',
    });

    try {
      final res = await _client.put(url, headers: headers, body: body).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        return;
      }
      final data = jsonDecode(res.body);
      final msg = data is Map ? (data['message'] ?? 'Failed to update office location') : 'Failed to update office location';
      throw AuthException(message: msg.toString());
    } on SocketException {
      throw const AuthException(message: 'Server unreachable');
    }
  }
}
