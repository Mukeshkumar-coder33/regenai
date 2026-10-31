/// Holiday Model
///
/// Maps to MongoDB `Holiday` documents returned by `GET /api/holidays`.
class HolidayModel {
  final String id;
  final String? companyId;
  final String name;
  final String date;

  const HolidayModel({
    required this.id,
    this.companyId,
    required this.name,
    required this.date,
  });

  factory HolidayModel.fromJson(Map<String, dynamic> json) {
    return HolidayModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      companyId: json['companyId']?.toString(),
      name: (json['name'] ?? 'Holiday').toString(),
      date: (json['date'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (companyId != null) 'companyId': companyId,
      'name': name,
      'date': date,
    };
  }
}

