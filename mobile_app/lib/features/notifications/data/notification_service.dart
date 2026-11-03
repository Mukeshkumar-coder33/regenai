import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../../app/app_config.dart';
import '../../../core/storage/session_storage.dart';
import 'notification_model.dart';

/// ReGen Notification Service
///
/// Connects to:
/// - `GET /api/notifications/user/:userId`
/// - `PUT /api/notifications/:id/read`
/// - `PUT /api/notifications/user/:userId/read-all`
/// - `DELETE /api/notifications/user/:userId/clear-all`
/// - `DELETE /api/notifications/:id`
class NotificationService {
  final http.Client _client;

  NotificationService({http.Client? client}) : _client = client ?? http.Client();

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

  /// 1. Fetch user notifications
  Future<List<NotificationModel>> getUserNotifications(String userId) async {
    if (userId.isEmpty) return [];
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/notifications/user/$userId');

    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final dynamic body = jsonDecode(res.body);
        if (body is List) {
          return body.map((json) => NotificationModel.fromJson(json as Map<String, dynamic>)).toList();
        }
      }
      return [];
    } on SocketException {
      return [];
    } catch (_) {
      return [];
    }
  }

  /// 2. Mark single notification as read
  Future<bool> markAsRead(String id, {String? mongoId}) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/notifications/$id/read');

    try {
      final res = await _client.put(url, headers: headers).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) return true;
      if (mongoId != null && mongoId.isNotEmpty && mongoId != id) {
        final fallbackUrl = Uri.parse('${AppConfig.activeBaseUrl}/api/notifications/$mongoId/read');
        final res2 = await _client.put(fallbackUrl, headers: headers).timeout(const Duration(seconds: 8));
        return res2.statusCode == 200;
      }
      return false;
    } catch (_) {
      if (mongoId != null && mongoId.isNotEmpty && mongoId != id) {
        try {
          final fallbackUrl = Uri.parse('${AppConfig.activeBaseUrl}/api/notifications/$mongoId/read');
          final res2 = await _client.put(fallbackUrl, headers: headers).timeout(const Duration(seconds: 8));
          return res2.statusCode == 200;
        } catch (_) {}
      }
      return false;
    }
  }

  /// 3. Mark all notifications as read
  Future<bool> markAllAsRead(String userId) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/notifications/user/$userId/read-all');

    try {
      final res = await _client.put(url, headers: headers).timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 4. Clear all notifications
  Future<bool> clearAll(String userId) async {
    final headers = await _getHeaders();
    bool success = false;
    try {
      final url = Uri.parse('${AppConfig.activeBaseUrl}/api/notifications/user/$userId/clear-all');
      final res = await _client.delete(url, headers: headers).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) success = true;
    } catch (_) {}

    try {
      final fallbackUrl = Uri.parse('${AppConfig.activeBaseUrl}/api/notifications/clear-all');
      final res2 = await _client.delete(fallbackUrl, headers: headers).timeout(const Duration(seconds: 8));
      if (res2.statusCode == 200) success = true;
    } catch (_) {}

    return success;
  }

  /// 5. Delete specific notification
  Future<bool> deleteNotification(String id) async {
    final headers = await _getHeaders();
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/notifications/$id');

    try {
      final res = await _client.delete(url, headers: headers).timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

