/// Work Schedule & Shift Settings Model
///
/// Maps to MongoDB `PayrollSetting` documents which define company working hours,
/// shift check-in/out targets, break allowances, and weekly off days.
class WorkScheduleModel {
  final String? id;
  final String? companyId;
  final String checkInTime;
  final String checkOutTime;
  final int workingHoursPerDay;
  final int workingDaysPerWeek;
  final int breakTime; // minutes allowed for official/lunch break
  final int casualBreakTime; // minutes allowed for casual/tea break
  final List<int> weeklyOffDays; // 0 = Sunday, 6 = Saturday
  final int graceMinutes;
  final double hourlyDeductionPct;
  final double hourlyOvertimePct;

  const WorkScheduleModel({
    this.id,
    this.companyId,
    this.checkInTime = '09:30',
    this.checkOutTime = '18:30',
    this.workingHoursPerDay = 8,
    this.workingDaysPerWeek = 5,
    this.breakTime = 60,
    this.casualBreakTime = 15,
    this.weeklyOffDays = const [0, 6],
    this.graceMinutes = 0,
    this.hourlyDeductionPct = 50.0,
    this.hourlyOvertimePct = 75.0,
  });

  factory WorkScheduleModel.fromJson(Map<String, dynamic> json) {
    List<int> offDays = [0, 6];
    if (json['weeklyOffDays'] is List) {
      offDays = (json['weeklyOffDays'] as List)
          .map((e) => int.tryParse(e.toString()) ?? 0)
          .toList();
    }

    return WorkScheduleModel(
      id: (json['_id'] ?? json['id'])?.toString(),
      companyId: json['companyId']?.toString(),
      checkInTime: (json['checkInTime'] ?? '09:30').toString(),
      checkOutTime: (json['checkOutTime'] ?? '18:30').toString(),
      workingHoursPerDay: _parseInt(json['workingHoursPerDay'], defaultVal: 8),
      workingDaysPerWeek: _parseInt(json['workingDaysPerWeek'], defaultVal: 5),
      breakTime: _parseInt(json['breakTime'], defaultVal: 60),
      casualBreakTime: _parseInt(json['casualBreakTime'], defaultVal: 15),
      weeklyOffDays: offDays,
      graceMinutes: _parseInt(json['graceMinutes'], defaultVal: 0),
      hourlyDeductionPct: _parseDouble(json['hourlyDeductionPct'], defaultVal: 50.0),
      hourlyOvertimePct: _parseDouble(json['hourlyOvertimePct'], defaultVal: 75.0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'checkInTime': checkInTime,
      'checkOutTime': checkOutTime,
      'workingHoursPerDay': workingHoursPerDay,
      'workingDaysPerWeek': workingDaysPerWeek,
      'breakTime': breakTime,
      'casualBreakTime': casualBreakTime,
      'weeklyOffDays': weeklyOffDays,
      'graceMinutes': graceMinutes,
      'hourlyDeductionPct': hourlyDeductionPct,
      'hourlyOvertimePct': hourlyOvertimePct,
    };
  }

  static int _parseInt(dynamic val, {int defaultVal = 0}) {
    if (val == null) return defaultVal;
    if (val is int) return val;
    if (val is double) return val.toInt();
    return int.tryParse(val.toString()) ?? defaultVal;
  }

  static double _parseDouble(dynamic val, {double defaultVal = 0.0}) {
    if (val == null) return defaultVal;
    if (val is double) return val;
    if (val is int) return val.toDouble();
    return double.tryParse(val.toString()) ?? defaultVal;
  }

  /// Helper to check if a specific weekday is a scheduled weekly off day.
  /// Note: DateTime.sunday is 7 in Dart, while MongoDB uses 0 for Sunday.
  bool isWeeklyOff(DateTime dt) {
    final mongoDay = dt.weekday == 7 ? 0 : dt.weekday;
    return weeklyOffDays.contains(mongoDay);
  }
}

