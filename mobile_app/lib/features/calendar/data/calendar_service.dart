import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../app/app_config.dart';
import '../../auth/data/user_model.dart';
import 'calendar_event_model.dart';
import 'holiday_model.dart';

/// Calendar and Holidays Service connecting with ReGen backend
class CalendarService {
  final http.Client _client;

  CalendarService({http.Client? client}) : _client = client ?? http.Client();

  /// Fetch company events & official holidays based on logged-in role
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
          'x-portal-view': user.isSuperAdmin ? 'superadmin' : 'ems',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final List<dynamic> list = jsonDecode(response.body) as List<dynamic>;
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final parsed = HolidayModel.fromJson(item);
            DateTime? dt;
            try {
              dt = DateTime.parse(parsed.date);
            } catch (_) {}

            if (dt != null) {
              loadedEvents.add(CalendarEventModel(
                id: parsed.id,
                title: parsed.name,
                dateTime: dt,
                time: parsed.isEvent ? 'Company Event • Working Day' : 'All Day • Official Holiday',
                category: parsed.isEvent ? 'Event' : 'Holiday',
                description: parsed.description,
                companyId: parsed.companyId,
                roleAccess: 'all',
                salaryDeduction: parsed.salaryDeduction,
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
      final isCompanyEvent = event.category.toLowerCase() == 'event';
      final dateFormatted =
          "${event.dateTime.year}-${event.dateTime.month.toString().padLeft(2, '0')}-${event.dateTime.day.toString().padLeft(2, '0')}";
      final encodedId = HolidayModel.buildEncodedId(
        isEvent: isCompanyEvent,
        description: event.description,
        salaryDeduction: event.salaryDeduction,
      );
      final payload = jsonEncode({
        'id': encodedId,
        'name': event.title,
        'date': isCompanyEvent ? '${dateFormatted}T00:00:01Z' : dateFormatted,
        if (event.description != null && event.description!.isNotEmpty)
          'description': event.description,
        if (user.companyId != null) 'companyId': user.companyId,
      });

      final response = await _client.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (user.token.isNotEmpty) 'Authorization': 'Bearer ${user.token}',
          'x-portal-view': user.isSuperAdmin ? 'superadmin' : 'ems',
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
          'x-portal-view': user.isSuperAdmin ? 'superadmin' : 'ems',
        },
      ).timeout(const Duration(seconds: 8));

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
