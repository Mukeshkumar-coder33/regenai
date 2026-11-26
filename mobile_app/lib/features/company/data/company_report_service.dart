import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../../app/app_config.dart';
import '../../../core/storage/session_storage.dart';
import '../../auth/data/auth_service.dart';

enum CompanyReportType {
  attendance,
  payment,
  generalTask,
  project,
}

/// Service connecting the Company Role Reports UI to ReGen's historical
/// backend report endpoints (`attendance`, `payroll`, `tasks`, `projects`).
class CompanyReportService {
  final http.Client _client;

  CompanyReportService({http.Client? client}) : _client = client ?? http.Client();

  Future<Map<String, String>> _getHeaders() async {
    final token = await SessionStorage.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'x-portal-view': 'ems',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  String _endpointPath(CompanyReportType type, {bool email = false}) {
    switch (type) {
      case CompanyReportType.attendance:
        return email ? '/api/attendance/send-report' : '/api/attendance/report';
      case CompanyReportType.payment:
        return email ? '/api/payroll/send-report' : '/api/payroll/report';
      case CompanyReportType.generalTask:
        return email ? '/api/tasks/send-report' : '/api/tasks/report';
      case CompanyReportType.project:
        return email ? '/api/projects/send-report' : '/api/projects/report';
    }
  }

  /// Builds clean query map excluding 'all' sentinel filters unless meaningful.
  static Map<String, String> buildQueryParams({
    required CompanyReportType type,
    required String period,
    String? date,
    String? startDate,
    String? endDate,
    String? month,
    String? year,
    String? employeeId,
    String? department,
    String? status,
    String? priority,
    String? projectId,
    String? search,
    int page = 1,
    dynamic limit = 25,
  }) {
    final params = <String, String>{
      'period': period,
      'page': page.toString(),
      'limit': limit.toString(),
    };
    if (type == CompanyReportType.generalTask) {
      params['scope'] = 'general';
    }
    if (date != null && date.isNotEmpty) params['date'] = date;
    if (startDate != null && startDate.isNotEmpty) params['startDate'] = startDate;
    if (endDate != null && endDate.isNotEmpty) params['endDate'] = endDate;
    if (month != null && month.isNotEmpty) params['month'] = month;
    if (year != null && year.isNotEmpty) params['year'] = year;
    if (employeeId != null && employeeId.isNotEmpty && employeeId != 'all') {
      params['employeeId'] = employeeId;
    }
    if (department != null && department.isNotEmpty && department != 'all') {
      params['department'] = department;
    }
    if (status != null && status.isNotEmpty && status != 'all') {
      params['status'] = status;
    }
    if (priority != null && priority.isNotEmpty && priority != 'all') {
      params['priority'] = priority;
    }
    if (projectId != null && projectId.isNotEmpty && projectId != 'all') {
      params['projectId'] = projectId;
    }
    if (search != null && search.trim().isNotEmpty) {
      params['search'] = search.trim();
    }
    return params;
  }

  Future<Map<String, dynamic>> fetchReport({
    required CompanyReportType type,
    required String period,
    String? date,
    String? startDate,
    String? endDate,
    String? month,
    String? year,
    String? employeeId,
    String? department,
    String? status,
    String? priority,
    String? projectId,
    String? search,
    int page = 1,
    dynamic limit = 25,
  }) async {
    final headers = await _getHeaders();
    final params = buildQueryParams(
      type: type,
      period: period,
      date: date,
      startDate: startDate,
      endDate: endDate,
      month: month,
      year: year,
      employeeId: employeeId,
      department: department,
      status: status,
      priority: priority,
      projectId: projectId,
      search: search,
      page: page,
      limit: limit,
    );

    final uri = Uri.parse('${AppConfig.activeBaseUrl}${_endpointPath(type)}')
        .replace(queryParameters: params);

    try {
      final res = await _client.get(uri, headers: headers).timeout(const Duration(seconds: 20));
      final body = res.body.isNotEmpty ? jsonDecode(res.body) : {};
      if (res.statusCode >= 200 && res.statusCode < 300 && body is Map<String, dynamic>) {
        return body;
      }
      final msg = body is Map ? (body['message'] ?? 'Failed to load report') : 'Failed to load report';
      throw AuthException(message: msg.toString(), statusCode: res.statusCode);
    } on SocketException {
      throw AuthException(message: 'Cannot reach ReGen server at ${AppConfig.activeBaseUrl}', statusCode: 0);
    }
  }

  Future<String> sendReportEmail({
    required CompanyReportType type,
    required String recipientEmail,
    String notes = '',
    required Map<String, String> filters,
  }) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}${_endpointPath(type, email: true)}');

    final payload = <String, dynamic>{
      ...filters,
      'recipientEmail': recipientEmail.trim(),
      'notes': notes.trim(),
    };
    if (type == CompanyReportType.generalTask) {
      payload['scope'] = 'general';
    }

    try {
      final res = await _client
          .post(url, headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 20));
      final body = res.body.isNotEmpty ? jsonDecode(res.body) : {};
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return (body is Map ? body['message']?.toString() : null) ??
            'Report dispatched to $recipientEmail';
      }
      final msg = body is Map ? (body['message'] ?? 'Failed to send report') : 'Failed to send report';
      throw AuthException(message: msg.toString(), statusCode: res.statusCode);
    } on SocketException {
      throw AuthException(message: 'Cannot reach ReGen server at ${AppConfig.activeBaseUrl}', statusCode: 0);
    }
  }
}
