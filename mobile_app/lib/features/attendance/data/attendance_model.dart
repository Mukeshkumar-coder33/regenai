/// ReGen Attendance Model
///
/// Maps exactly to MongoDB `Attendance` documents returned by `GET /api/attendance`.
class AttendanceModel {
  final String id;
  final String? mongoId;
  final String? companyId;
  final String userId;
  final String date;
  final String status;
  final String? checkIn;
  final String? checkOut;
  final String? workMode;
  final String? location;

  // Official Break (Lunch)
  final String? breakStart;
  final String? breakEnd;
  final int breakMinutes;
  final int breakDelayMinutes;

  // Casual Break (Tea/Coffee)
  final String? casualBreakStart;
  final String? casualBreakEnd;
  final int casualBreakMinutes;
  final int casualBreakDelayMinutes;

  // Combined break status & deductions
  final String activeBreakType; // 'none', 'official', 'casual'
  final int totalBreakDelayMinutes;
  final double breakDeduction;

  // Geofence & Location Coords
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final double? distance;
  final String? notes;

  const AttendanceModel({
    required this.id,
    this.mongoId,
    this.companyId,
    required this.userId,
    required this.date,
    required this.status,
    this.checkIn,
    this.checkOut,
    this.workMode,
    this.location,
    this.breakStart,
    this.breakEnd,
    this.breakMinutes = 0,
    this.breakDelayMinutes = 0,
    this.casualBreakStart,
    this.casualBreakEnd,
    this.casualBreakMinutes = 0,
    this.casualBreakDelayMinutes = 0,
    this.activeBreakType = 'none',
    this.totalBreakDelayMinutes = 0,
    this.breakDeduction = 0.0,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.distance,
    this.notes,
  });

  factory AttendanceModel.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? coords;
    if (json['locationCoords'] is Map<String, dynamic>) {
      coords = json['locationCoords'] as Map<String, dynamic>;
    }

    return AttendanceModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      mongoId: json['_id']?.toString(),
      companyId: json['companyId']?.toString(),
      userId: (json['userId'] ?? '').toString(),
      date: (json['date'] ?? '').toString(),
      status: (json['status'] ?? 'present').toString(),
      checkIn: json['checkIn']?.toString(),
      checkOut: json['checkOut']?.toString(),
      workMode: json['workMode']?.toString() ?? 'office',
      location: json['location']?.toString(),
      breakStart: json['breakStart']?.toString(),
      breakEnd: json['breakEnd']?.toString(),
      breakMinutes: _parseInt(json['breakMinutes']),
      breakDelayMinutes: _parseInt(json['breakDelayMinutes']),
      casualBreakStart: json['casualBreakStart']?.toString(),
      casualBreakEnd: json['casualBreakEnd']?.toString(),
      casualBreakMinutes: _parseInt(json['casualBreakMinutes']),
      casualBreakDelayMinutes: _parseInt(json['casualBreakDelayMinutes']),
      activeBreakType: (json['activeBreakType'] ?? 'none').toString(),
      totalBreakDelayMinutes: _parseInt(json['totalBreakDelayMinutes']),
      breakDeduction: _parseDouble(json['breakDeduction']),
      latitude: coords != null ? _parseDouble(coords['latitude']) : _parseDouble(json['latitude']),
      longitude: coords != null ? _parseDouble(coords['longitude']) : _parseDouble(json['longitude']),
      accuracy: coords != null ? _parseDouble(coords['accuracy']) : _parseDouble(json['accuracy']),
      distance: coords != null ? _parseDouble(coords['distance']) : _parseDouble(json['distance']),
      notes: json['notes']?.toString(),
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

  bool get isPresent =>
      status.toLowerCase() == 'present' ||
      status == '0' ||
      status.toLowerCase() == 'late';

  bool get isLate => status.toLowerCase() == 'late';
  bool get isAbsent => status.toLowerCase() == 'absent';
  bool get isHalfDay => status.toLowerCase() == 'half_day';

  bool get isCheckedIn => checkIn != null && checkIn!.isNotEmpty;
  bool get isCheckedOut => checkOut != null && checkOut!.isNotEmpty;

  bool get isOnOfficialBreak => activeBreakType == 'official';
  bool get isOnCasualBreak => activeBreakType == 'casual';
  bool get isOnBreak => isOnOfficialBreak || isOnCasualBreak;

  /// Whether employee is currently on the clock and working
  bool get isActivelyWorking => isCheckedIn && !isCheckedOut && !isOnBreak;
}
