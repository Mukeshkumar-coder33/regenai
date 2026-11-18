import 'dart:convert';

/// Holiday & Company Event Model
///
/// Maps to MongoDB `Holiday` documents returned by `GET /api/holidays`.
/// Supports both Official Company Holidays and Company Events (persisted with
/// URL-safe metadata inside `id` so backend payroll & web schemas stay intact).
class HolidayModel {
  final String id;
  final String? companyId;
  final String name;
  final String date; // Normalized YYYY-MM-DD
  final String? description;
  final bool isEvent;
  final bool salaryDeduction;

  const HolidayModel({
    required this.id,
    this.companyId,
    required this.name,
    required this.date,
    this.description,
    this.isEvent = false,
    this.salaryDeduction = false,
  });

  /// Builds a URL-safe ID carrying optional event flag, salary deduction flag,
  /// and UTF-8 description without special characters (safe for `DELETE /api/holidays/:id`).
  static String buildEncodedId({
    required bool isEvent,
    String? description,
    bool salaryDeduction = false,
    int? timestampMs,
  }) {
    final ts = timestampMs ?? DateTime.now().millisecondsSinceEpoch;
    final prefix = isEvent
        ? 'event-$ts-s${salaryDeduction ? '1' : '0'}'
        : 'holiday-$ts';
    final cleanDesc = (description ?? '').trim();
    if (cleanDesc.isEmpty) return prefix;

    // Cap description length so encoded ID stays well within URL & MongoDB index limits
    final truncated = cleanDesc.length > 260 ? cleanDesc.substring(0, 260) : cleanDesc;
    final encoded = base64Url.encode(utf8.encode(truncated)).replaceAll('=', '');
    return '${prefix}__d_$encoded';
  }

  static String? _decodeDescriptionFromId(String id) {
    const marker = '__d_';
    final idx = id.indexOf(marker);
    if (idx == -1) return null;
    final raw = id.substring(idx + marker.length);
    if (raw.isEmpty) return null;
    try {
      final normalized = base64Url.normalize(raw);
      return utf8.decode(base64Url.decode(normalized));
    } catch (_) {
      return null;
    }
  }

  static bool _decodeSalaryDeductionFromId(String id) {
    final base = id.split('__d_').first;
    return base.endsWith('-s1');
  }

  factory HolidayModel.fromJson(Map<String, dynamic> json) {
    final rawId = (json['id'] ?? json['_id'] ?? '').toString();
    final rawDate = (json['date'] ?? '').toString();
    final normalizedDate = rawDate.contains('T') ? rawDate.split('T').first : rawDate;

    final isEventFlag = rawId.startsWith('event-') ||
        json['isEvent'] == true ||
        json['type']?.toString().toLowerCase() == 'event' ||
        rawDate.endsWith('T00:00:01Z');

    final explicitDesc = json['description']?.toString().trim();
    final decodedDesc = (explicitDesc != null && explicitDesc.isNotEmpty)
        ? explicitDesc
        : _decodeDescriptionFromId(rawId);

    final salaryDed = json['salaryDeduction'] == true ||
        (isEventFlag && _decodeSalaryDeductionFromId(rawId));

    return HolidayModel(
      id: rawId,
      companyId: json['companyId']?.toString(),
      name: (json['name'] ?? json['title'] ?? (isEventFlag ? 'Company Event' : 'Holiday')).toString(),
      date: normalizedDate,
      description: decodedDesc,
      isEvent: isEventFlag,
      salaryDeduction: salaryDed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (companyId != null) 'companyId': companyId,
      'name': name,
      'date': date,
      if (description != null) 'description': description,
      if (isEvent) 'isEvent': true,
      if (isEvent) 'salaryDeduction': salaryDeduction,
    };
  }
}
