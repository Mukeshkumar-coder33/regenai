import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../app/app_config.dart';
import '../../auth/data/user_model.dart';
import 'calendar_event_model.dart';

/// Calendar and Holidays Service connecting with ReGen backend
class CalendarService {
  final http.Client _client;

  CalendarService({http.Client? client}) : _client = client ?? http.Client();

  /// Fetch events & holidays based on logged-in role
  Future<List<CalendarEventModel>> fetchEvents({
    required UserModel user,
  }) async {
    final List<CalendarEventModel> loadedEvents = [];

    try {
      final holidaysUrl = Uri.parse('${AppConfig.activeBaseUrl}/api/holidays');
      final response = await _client.get(
        holidaysUrl,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (user.token.isNotEmpty) 'Authorization': 'Bearer ${user.token}',
          'x-portal-view': user.isSuperAdmin
              ? 'superadmin'
              : (user.isCompanyAdmin ? 'company' : 'staff'),
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final List<dynamic> list = jsonDecode(response.body) as List<dynamic>;
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final dateStr = (item['date'] ?? '').toString();
            DateTime? dt;
            try {
              dt = DateTime.parse(dateStr);
            } catch (_) {}

            if (dt != null) {
              loadedEvents.add(CalendarEventModel(
                id: (item['id'] ?? item['_id'] ?? '').toString(),
                title: (item['name'] ?? item['title'] ?? 'Company Holiday').toString(),
                dateTime: dt,
                time: 'All Day',
                category: 'Holiday',
                companyId: item['companyId']?.toString(),
                roleAccess: 'all',
              ));
            }
          }
        }
      }
    } catch (_) {
      // Backend offline or timeout -> handled gracefully
    }

    return loadedEvents;
  }

  /// Create a new event or holiday
  Future<bool> createEvent({
    required UserModel user,
    required CalendarEventModel event,
  }) async {
    try {
      final url = Uri.parse('${AppConfig.activeBaseUrl}/api/holidays');
      final dateFormatted = "${event.dateTime.year}-${event.dateTime.month.toString().padLeft(2, '0')}-${event.dateTime.day.toString().padLeft(2, '0')}";
      final payload = jsonEncode({
        'name': event.title,
        'date': dateFormatted,
        if (user.companyId != null) 'companyId': user.companyId,
      });

      final response = await _client.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (user.token.isNotEmpty) 'Authorization': 'Bearer ${user.token}',
          'x-portal-view': user.isSuperAdmin ? 'superadmin' : 'company',
        },
        body: payload,
      ).timeout(const Duration(seconds: 8));

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  /// Delete an event/holiday
  Future<bool> deleteEvent({
    required UserModel user,
    required String eventId,
  }) async {
    try {
      final url = Uri.parse('${AppConfig.activeBaseUrl}/api/holidays/$eventId');
      final response = await _client.delete(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (user.token.isNotEmpty) 'Authorization': 'Bearer ${user.token}',
        },
      ).timeout(const Duration(seconds: 8));

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

