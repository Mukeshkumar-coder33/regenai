import 'attendance_model.dart';

/// ReGen Attendance Report Model
///
/// Returned by `GET /api/attendance/report?period=day|week|month|year`
class AttendanceReportModel {
  final String companyName;
  final String period;
  final String periodLabel;
  final int totalRecords;
  final int uniqueEmployees;
  final double totalWorkingHours;
  final double averageDailyHours;
  final int presentCount;
  final int lateCount;
  final int halfDayCount;
  final int absentCount;
  final List<AttendanceModel> records;

  const AttendanceReportModel({
    required this.companyName,
    required this.period,
    required this.periodLabel,
    this.totalRecords = 0,
    this.uniqueEmployees = 0,
    this.totalWorkingHours = 0.0,
    this.averageDailyHours = 0.0,
    this.presentCount = 0,
    this.lateCount = 0,
    this.halfDayCount = 0,
    this.absentCount = 0,
    this.records = const [],
  });

  factory AttendanceReportModel.fromJson(Map<String, dynamic> json) {
    final rawRecords = json['records'];
    final List<AttendanceModel> parsedRecords = [];
    if (rawRecords is List) {
      for (final r in rawRecords) {
        if (r is Map<String, dynamic>) {
          parsedRecords.add(AttendanceModel.fromJson(r));
        }
      }
    }

    return AttendanceReportModel(
      companyName: (json['companyName'] ?? '').toString(),
      period: (json['period'] ?? 'month').toString(),
      periodLabel: (json['periodLabel'] ?? '').toString(),
      totalRecords: _parseInt(json['totalRecords']),
      uniqueEmployees: _parseInt(json['uniqueEmployees']),
      totalWorkingHours: _parseDouble(json['totalWorkingHours']),
      averageDailyHours: _parseDouble(json['averageDailyHours']),
      presentCount: _parseInt(json['presentCount']),
      lateCount: _parseInt(json['lateCount']),
      halfDayCount: _parseInt(json['halfDayCount']),
      absentCount: _parseInt(json['absentCount']),
      records: parsedRecords,
    );
  }

  static int _parseInt(dynamic val) {
    if (val == null) return 0;
    if (val is int) return val;
    if (val is double) return val.toInt();
    return int.tryParse(val.toString()) ?? 0;
  }

  static double _parseDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is double) return val;
    if (val is int) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }
}

