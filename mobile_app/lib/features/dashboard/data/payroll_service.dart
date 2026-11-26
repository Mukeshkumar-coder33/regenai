import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../../app/app_config.dart';
import '../../../core/storage/session_storage.dart';
import '../../auth/data/auth_service.dart';

/// Payroll & Employee Payment API Service (Company Admin & Employee Endpoints)
class PayrollService {
  final http.Client _client;

  PayrollService({http.Client? client}) : _client = client ?? http.Client();

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

  /// Fetch Company Payroll Settings & Policy (`GET /api/payroll/settings`)
  Future<Map<String, dynamic>> getPayrollSettings() async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/payroll/settings');
    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final raw = jsonDecode(res.body);
        if (raw is Map<String, dynamic>) return raw;
      }
      throw AuthException(message: 'Failed to load payroll settings (${res.statusCode})', statusCode: res.statusCode);
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable', statusCode: 0);
    }
  }

  /// Update Company Payroll Policy (`PUT /api/payroll/settings`)
  Future<Map<String, dynamic>> updatePayrollSettings(Map<String, dynamic> payload) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/payroll/settings');
    try {
      final res = await _client
          .put(url, headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 12));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data is Map<String, dynamic>) {
        return data;
      }
      final msg = data is Map ? (data['message'] ?? 'Failed to update payroll settings') : 'Failed to update payroll settings';
      throw AuthException(message: msg.toString(), statusCode: res.statusCode);
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable', statusCode: 0);
    }
  }

  /// Fetch Monthly Payroll Summary for Company Dashboard (`GET /api/payroll/summary`)
  Future<Map<String, dynamic>> getPayrollSummary({
    required String month,
    String? search,
    String? department,
    String? statusTab,
  }) async {
    final headers = await _getHeaders();
    final params = <String, String>{'month': month};
    if (search != null && search.trim().isNotEmpty) params['search'] = search.trim();
    if (department != null && department.isNotEmpty && department != 'all') params['department'] = department;
    if (statusTab != null && statusTab.isNotEmpty && statusTab != 'all') params['statusTab'] = statusTab;

    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/payroll/summary').replace(queryParameters: params);
    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data is Map<String, dynamic>) {
        return data;
      }
      final msg = data is Map ? (data['message'] ?? 'Failed to load payroll summary') : 'Failed to load payroll summary';
      throw AuthException(message: msg.toString(), statusCode: res.statusCode);
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable', statusCode: 0);
    }
  }

  /// Fetch Single Employee Detailed Payroll Preview (`GET /api/payroll/preview`)
  Future<Map<String, dynamic>> getEmployeePayrollPreview({
    required String userId,
    required String month,
  }) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/payroll/preview').replace(
      queryParameters: {'userId': userId, 'month': month},
    );
    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data is Map<String, dynamic>) {
        return data;
      }
      final msg = data is Map ? (data['message'] ?? 'Failed to load employee payroll preview') : 'Failed to load preview';
      throw AuthException(message: msg.toString(), statusCode: res.statusCode);
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable', statusCode: 0);
    }
  }

  /// Fetch Pending Salary Records Across Previous Months (`GET /api/payroll/pending`)
  Future<Map<String, dynamic>> getPendingPayrolls({String? userId, String? beforeMonth}) async {
    final headers = await _getHeaders();
    final params = <String, String>{};
    if (userId != null && userId.isNotEmpty) params['userId'] = userId;
    if (beforeMonth != null && beforeMonth.isNotEmpty) params['beforeMonth'] = beforeMonth;
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/payroll/pending')
        .replace(queryParameters: params.isEmpty ? null : params);
    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final raw = jsonDecode(res.body);
        if (raw is Map<String, dynamic>) return raw;
      }
      return const {'pending': [], 'totalPending': 0};
    } catch (_) {
      return const {'pending': [], 'totalPending': 0};
    }
  }

  /// Finalize Single Employee Payroll (`POST /api/payroll/finalize`)
  Future<Map<String, dynamic>> finalizePayroll({
    required String userId,
    required String month,
    String? notes,
  }) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/payroll/finalize');
    try {
      final res = await _client
          .post(url, headers: headers, body: jsonEncode({'userId': userId, 'month': month, 'notes': ?notes}))
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data is Map<String, dynamic>) return data;
      final msg = data is Map ? (data['message'] ?? 'Failed to finalize payroll') : 'Failed to finalize payroll';
      throw AuthException(message: msg.toString(), statusCode: res.statusCode);
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable', statusCode: 0);
    }
  }

  /// Finalize & Close Whole Month Payroll (`POST /api/payroll/finalize-month`)
  Future<Map<String, dynamic>> finalizeMonth({required String month, String? notes}) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/payroll/finalize-month');
    try {
      final res = await _client
          .post(url, headers: headers, body: jsonEncode({'month': month, 'notes': ?notes}))
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data is Map<String, dynamic>) return data;
      final msg = data is Map ? (data['message'] ?? 'Failed to finalize month') : 'Failed to finalize month';
      throw AuthException(message: msg.toString(), statusCode: res.statusCode);
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable', statusCode: 0);
    }
  }

  /// Process Single Partial/Full Payment (`POST /api/payroll/pay`)
  Future<Map<String, dynamic>> processPayment({
    String? payrollId,
    String? userId,
    String? month,
    double? amount,
    String paymentMethod = 'bank_transfer',
    required String referenceId,
    String payoutType = 'salary',
    String? notes,
  }) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/payroll/pay');
    final body = <String, dynamic>{
      'payrollId': ?payrollId,
      'userId': ?userId,
      'month': ?month,
      'amount': ?amount,
      'paymentMethod': paymentMethod,
      'referenceId': referenceId,
      'payoutType': payoutType,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    };
    try {
      final res = await _client
          .post(url, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data is Map<String, dynamic>) return data;
      final msg = data is Map ? (data['message'] ?? 'Payment failed') : 'Payment failed';
      throw AuthException(message: msg.toString(), statusCode: res.statusCode);
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable', statusCode: 0);
    }
  }

  /// Process Multiple Pending Months Together (`POST /api/payroll/pay-bulk`)
  Future<Map<String, dynamic>> processBulkPayment({
    required String userId,
    required List<Map<String, dynamic>> items,
    String paymentMethod = 'bank_transfer',
    required String referenceId,
    String? notes,
  }) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/payroll/pay-bulk');
    try {
      final res = await _client
          .post(
            url,
            headers: headers,
            body: jsonEncode({
              'userId': userId,
              'items': items,
              'paymentMethod': paymentMethod,
              'referenceId': referenceId,
              if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
            }),
          )
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data is Map<String, dynamic>) return data;
      final msg = data is Map ? (data['message'] ?? 'Bulk payment failed') : 'Bulk payment failed';
      throw AuthException(message: msg.toString(), statusCode: res.statusCode);
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable', statusCode: 0);
    }
  }

  /// Add Bonus or Manual Deduction (`POST /api/payroll/adjustment`)
  Future<Map<String, dynamic>> addAdjustment({
    required String userId,
    required String month,
    required String type, // 'bonus' or 'deduction'
    required double amount,
    String? reason,
  }) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/payroll/adjustment');
    try {
      final res = await _client
          .post(
            url,
            headers: headers,
            body: jsonEncode({
              'userId': userId,
              'month': month,
              'type': type,
              'amount': amount,
              if (reason != null) 'reason': reason.trim(),
            }),
          )
          .timeout(const Duration(seconds: 12));
      final data = jsonDecode(res.body);
      if ((res.statusCode == 200 || res.statusCode == 201) && data is Map<String, dynamic>) {
        return data;
      }
      final msg = data is Map ? (data['message'] ?? 'Failed to add adjustment') : 'Failed to add adjustment';
      throw AuthException(message: msg.toString(), statusCode: res.statusCode);
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable', statusCode: 0);
    }
  }

  /// Delete Bonus/Deduction Adjustment (`DELETE /api/payroll/adjustment/:id`)
  Future<void> deleteAdjustment(String adjustmentId) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/payroll/adjustment/$adjustmentId');
    try {
      final res = await _client.delete(url, headers: headers).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) return;
      final data = jsonDecode(res.body);
      final msg = data is Map ? (data['message'] ?? 'Failed to delete adjustment') : 'Failed to delete adjustment';
      throw AuthException(message: msg.toString(), statusCode: res.statusCode);
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable', statusCode: 0);
    }
  }

  /// Fetch Recent Transactions (`GET /api/payroll/transactions`)
  Future<List<Map<String, dynamic>>> getRecentTransactions({String? month, String? userId, int limit = 50}) async {
    final headers = await _getHeaders();
    final params = <String, String>{'limit': '$limit'};
    if (month != null && month.isNotEmpty) params['month'] = month;
    if (userId != null && userId.isNotEmpty) params['userId'] = userId;
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/payroll/transactions').replace(queryParameters: params);
    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final raw = jsonDecode(res.body);
        if (raw is Map<String, dynamic> && raw['transactions'] is List) {
          return (raw['transactions'] as List).whereType<Map<String, dynamic>>().toList();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Fetch Structured Payslip JSON (`GET /api/payroll/payslip`)
  Future<Map<String, dynamic>> getPayslipJson({String? payrollId, String? userId, String? month}) async {
    final headers = await _getHeaders();
    final Uri url;
    if (payrollId != null && payrollId.isNotEmpty) {
      url = Uri.parse('${AppConfig.activeBaseUrl}/api/payroll/$payrollId/payslip');
    } else {
      final params = <String, String>{};
      if (userId != null && userId.isNotEmpty) params['userId'] = userId;
      if (month != null && month.isNotEmpty) params['month'] = month;
      url = Uri.parse('${AppConfig.activeBaseUrl}/api/payroll/payslip')
          .replace(queryParameters: params.isEmpty ? null : params);
    }
    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data is Map<String, dynamic>) return data;
      final msg = data is Map ? (data['message'] ?? 'Failed to load payslip') : 'Failed to load payslip';
      throw AuthException(message: msg.toString(), statusCode: res.statusCode);
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable', statusCode: 0);
    }
  }

  /// Download Monthly Payslip PDF to device Downloads/Documents directory
  Future<File> downloadPayslipPdf({String? payrollId, String? userId, required String month}) async {
    final headers = await _getHeaders();
    headers['Accept'] = 'application/pdf';
    final Uri url;
    if (payrollId != null && payrollId.isNotEmpty) {
      url = Uri.parse('${AppConfig.activeBaseUrl}/api/payroll/$payrollId/payslip?format=pdf');
    } else {
      final params = <String, String>{'month': month, 'format': 'pdf'};
      if (userId != null && userId.isNotEmpty) params['userId'] = userId;
      url = Uri.parse('${AppConfig.activeBaseUrl}/api/payroll/payslip').replace(queryParameters: params);
    }

    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        throw AuthException(message: 'Failed to download payslip (${res.statusCode})', statusCode: res.statusCode);
      }

      Directory? targetDir;
      try {
        targetDir = await getDownloadsDirectory();
      } catch (_) {}
      targetDir ??= await getApplicationDocumentsDirectory();

      final safeUser = (userId ?? 'self').replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final file = File('${targetDir.path}${Platform.pathSeparator}ReGen_Payslip_${safeUser}_$month.pdf');
      await file.writeAsBytes(res.bodyBytes, flush: true);
      return file;
    } on SocketException {
      throw const AuthException(message: 'Server connection unreachable', statusCode: 0);
    }
  }
}
