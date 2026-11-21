import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/services/location_service.dart';
import '../../../core/storage/session_storage.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../auth/data/user_model.dart';
import '../../company/data/company_model.dart';
import '../../dashboard/data/dashboard_service.dart';
import '../data/attendance_model.dart';
import '../data/attendance_service.dart';
import '../data/work_schedule_model.dart';

/// Employee Role Attendance View
///
/// Features:
/// 1. Top Bar: Left Arrow straight to 'Attendance' (no line-wrap) with 5m Geofence chip.
/// 2. Field 1: Today Date, Live Digital Clock & Shift Timing from Company Work Policy.
/// 3. Field 2: Working Hours Live Timer (starts on check-in, ends on check-out).
/// 4. Field 3: Check-in Box with real GPS location & 5-metre geofence validation.
/// 5. Field 4: Break Field (Lunch Break & Casual Break) with separate timers & location verification.
/// 6. Field 5: Check-Out Box accessible after check-in with GPS validation & work hours summary.
class AttendanceView extends StatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback? onOpenDrawer;

  const AttendanceView({super.key, this.onBack, this.onOpenDrawer});

  @override
  State<AttendanceView> createState() => _AttendanceViewState();
}

class _AttendanceViewState extends State<AttendanceView> {
  final AttendanceService _attendanceService = AttendanceService();
  final DashboardService _dashboardService = DashboardService();

  UserModel? _currentUser;
  CompanyModel? _userCompany;
  WorkScheduleModel _workSchedule = const WorkScheduleModel();
  AttendanceModel? _todayAttendance;

  bool _isLoading = true;
  bool _isActionInProgress = false;
  String? _errorMessage;

  DateTime _now = DateTime.now();
  Timer? _tickerTimer;

  int _workingSecondsElapsed = 0;
  int _lunchBreakSecondsElapsed = 0;
  int _casualBreakSecondsElapsed = 0;
  double? _lastMeasuredDistance;

  @override
  void initState() {
    super.initState();
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), _onTick);
    _loadAllData();
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    super.dispose();
  }

  void _onTick(Timer timer) {
    if (!mounted) return;
    final now = DateTime.now();
    setState(() {
      _now = now;
      _recalculateTimers(now);
    });
  }

  void _recalculateTimers(DateTime now) {
    if (_todayAttendance == null || !_todayAttendance!.isCheckedIn) {
      _workingSecondsElapsed = 0;
      _lunchBreakSecondsElapsed = 0;
      _casualBreakSecondsElapsed = 0;
      return;
    }

    final inTime = DateTime.tryParse(_todayAttendance!.checkIn ?? '') ?? now;
    final totalBreaksTakenSeconds =
        ((_todayAttendance?.breakMinutes ?? 0) + (_todayAttendance?.casualBreakMinutes ?? 0)) * 60;

    if (_todayAttendance!.isCheckedOut) {
      final outTime = DateTime.tryParse(_todayAttendance!.checkOut ?? '') ?? now;
      final totalSec = outTime.difference(inTime).inSeconds;
      _workingSecondsElapsed = (totalSec - totalBreaksTakenSeconds).clamp(0, 86400);
      return;
    }

    // Currently checked in & working
    final totalElapsedFromCheckIn = now.difference(inTime).inSeconds;

    // Track active Lunch Break
    if (_todayAttendance!.isOnOfficialBreak && _todayAttendance!.breakStart != null) {
      final bStart = DateTime.tryParse(_todayAttendance!.breakStart!) ?? now;
      _lunchBreakSecondsElapsed = now.difference(bStart).inSeconds;
    } else {
      _lunchBreakSecondsElapsed = 0;
    }

    // Track active Casual Break
    if (_todayAttendance!.isOnCasualBreak && _todayAttendance!.casualBreakStart != null) {
      final cbStart = DateTime.tryParse(_todayAttendance!.casualBreakStart!) ?? now;
      _casualBreakSecondsElapsed = now.difference(cbStart).inSeconds;
    } else {
      _casualBreakSecondsElapsed = 0;
    }

    final currentLiveBreakSec = _lunchBreakSecondsElapsed + _casualBreakSecondsElapsed;
    final netWorked = totalElapsedFromCheckIn - totalBreaksTakenSeconds - currentLiveBreakSec;
    _workingSecondsElapsed = netWorked.clamp(0, 86400);
  }

  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = await SessionStorage.getUserSession();
      _currentUser = user;

      final results = await Future.wait([
        _dashboardService.getCompanies(),
        _attendanceService.getWorkSchedule(),
        _attendanceService.getTodayAttendance(userId: user?.userId ?? user?.id),
      ]);

      if (!mounted) return;

      final companies = results[0] as List<CompanyModel>;
      final schedule = results[1] as WorkScheduleModel;
      final todayRecord = results[2] as AttendanceModel?;

      setState(() {
        if (companies.isNotEmpty) _userCompany = companies.first;
        _workSchedule = schedule;
        _todayAttendance = todayRecord;
        _isLoading = false;
        _recalculateTimers(DateTime.now());
      });

      // Quick passive location distance measurement in background
      _measureDistanceSilently();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _measureDistanceSilently() async {
    if (_userCompany?.hasOfficeLocation != true) return;
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null && mounted) {
        final dist = LocationService.distanceBetween(
          startLatitude: pos.latitude,
          startLongitude: pos.longitude,
          endLatitude: _userCompany!.latitude!,
          endLongitude: _userCompany!.longitude!,
        );
        setState(() => _lastMeasuredDistance = dist);
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // GEOFENCE & GPS VERIFICATION ENGINE (5 METRES)
  // ---------------------------------------------------------------------------
  Future<Position?> _validateGeofenceAndGetPosition({required String actionName}) async {
    setState(() => _isActionInProgress = true);
    try {
      final pos = await LocationService.getCurrentPosition();

      if (_userCompany?.hasOfficeLocation == true &&
          _userCompany!.latitude != null &&
          _userCompany!.longitude != null &&
          (_userCompany!.latitude != 0 || _userCompany!.longitude != 0)) {
        final dist = LocationService.distanceBetween(
          startLatitude: pos.latitude,
          startLongitude: pos.longitude,
          endLatitude: _userCompany!.latitude!,
          endLongitude: _userCompany!.longitude!,
        );

        if (mounted) setState(() => _lastMeasuredDistance = dist);

        if (dist > 5.0) {
          if (mounted) {
            _showGeofenceRestrictedDialog(
              actionName: actionName,
              measuredDistance: dist,
              maxAllowed: 5.0,
            );
          }
          setState(() => _isActionInProgress = false);
          return null;
        }
      }
      return pos;
    } on LocationCustomException catch (e) {
      if (mounted) _showLocationMessageDialog(title: 'Location Required', message: e.message);
      setState(() => _isActionInProgress = false);
      return null;
    } catch (e) {
      if (mounted) _showLocationMessageDialog(title: 'GPS Error', message: 'Unable to verify position: $e');
      setState(() => _isActionInProgress = false);
      return null;
    }
  }

  void _showGeofenceRestrictedDialog({
    required String actionName,
    required double measuredDistance,
    required double maxAllowed,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.location_off_rounded, color: CeladonColors.error, size: 24),
            SizedBox(width: 8),
            Text('Outside 5m Geofence', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cannot perform $actionName.',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: CeladonColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'You are currently ${measuredDistance.toStringAsFixed(1)} metres away from your registered workplace. '
              'Company policy strictly requires being within ${maxAllowed.toInt()} metres of the office.',
              style: const TextStyle(fontSize: 12.5, color: CeladonColors.textSecondary, height: 1.35),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: CeladonColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: CeladonColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 16, color: CeladonColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Distance measured: ${measuredDistance.toStringAsFixed(1)}m (Allowed: ${maxAllowed.toInt()}m)',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: CeladonColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: CeladonColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Understood', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showLocationMessageDialog({required String title, required String message}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        content: Text(message, style: const TextStyle(fontSize: 13, color: CeladonColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w700, color: CeladonColors.primary)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ATTENDANCE ACTIONS (CHECK-IN, BREAKS, CHECK-OUT)
  // ---------------------------------------------------------------------------
  Future<void> _handleCheckIn() async {
    final pos = await _validateGeofenceAndGetPosition(actionName: 'Check-In');
    if (pos == null) return;

    try {
      final updated = await _attendanceService.checkIn(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: pos.accuracy,
        checkInTargetTime: _workSchedule.checkInTime,
      );

      if (!mounted) return;
      setState(() {
        _todayAttendance = updated;
        _isActionInProgress = false;
        _recalculateTimers(DateTime.now());
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: CeladonColors.primary,
          content: Text(
            'Checked in successfully at ${_formatTime(updated.checkIn)}! Status: ${updated.status.toUpperCase()}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isActionInProgress = false);
        _showLocationMessageDialog(title: 'Check-In Failed', message: e.toString());
      }
    }
  }

  Future<void> _handleStartBreak(String breakType) async {
    final breakLabel = breakType == 'casual' ? 'Casual Break' : 'Lunch Break';
    final pos = await _validateGeofenceAndGetPosition(actionName: 'Start $breakLabel');
    if (pos == null) return;

    try {
      final updated = await _attendanceService.startBreak(
        attendanceId: _todayAttendance!.id,
        breakType: breakType,
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: pos.accuracy,
      );

      if (!mounted) return;
      setState(() {
        _todayAttendance = updated;
        _isActionInProgress = false;
        _recalculateTimers(DateTime.now());
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFD97706),
          content: Text(
            '$breakLabel started! Working timer paused.',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isActionInProgress = false);
        _showLocationMessageDialog(title: 'Start Break Failed', message: e.toString());
      }
    }
  }

  Future<void> _handleEndBreak(String breakType) async {
    final breakLabel = breakType == 'casual' ? 'Casual Break' : 'Lunch Break';
    final pos = await _validateGeofenceAndGetPosition(actionName: 'Stop $breakLabel');
    if (pos == null) return;

    try {
      final updated = await _attendanceService.endBreak(
        attendanceId: _todayAttendance!.id,
        breakType: breakType,
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: pos.accuracy,
      );

      if (!mounted) return;
      setState(() {
        _todayAttendance = updated;
        _isActionInProgress = false;
        _recalculateTimers(DateTime.now());
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: CeladonColors.primary,
          content: Text(
            '$breakLabel completed! Working timer resumed.',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isActionInProgress = false);
        _showLocationMessageDialog(title: 'End Break Failed', message: e.toString());
      }
    }
  }

  Future<void> _handleCheckOut() async {
    if (_todayAttendance?.isOnBreak == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: CeladonColors.error,
          content: Text('Please stop your active break before checking out!'),
        ),
      );
      return;
    }

    final pos = await _validateGeofenceAndGetPosition(actionName: 'Check-Out');
    if (pos == null) return;

    try {
      final updated = await _attendanceService.checkOut(
        attendanceId: _todayAttendance!.id,
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: pos.accuracy,
      );

      if (!mounted) return;
      setState(() {
        _todayAttendance = updated;
        _isActionInProgress = false;
        _recalculateTimers(DateTime.now());
      });

      _showCheckOutSummaryDialog(updated);
    } catch (e) {
      if (mounted) {
        setState(() => _isActionInProgress = false);
        _showLocationMessageDialog(title: 'Check-Out Failed', message: e.toString());
      }
    }
  }

  void _showCheckOutSummaryDialog(AttendanceModel record) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: const [
            Icon(Icons.check_circle_rounded, color: CeladonColors.primary, size: 26),
            SizedBox(width: 8),
            Text('Check-Out Summary', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Your workday has been successfully saved to ReGen database.',
              style: TextStyle(fontSize: 12.5, color: CeladonColors.textSecondary),
            ),
            const SizedBox(height: 14),
            _buildSummaryDataRow('Date', record.date),
            _buildSummaryDataRow('Check-In', _formatTime(record.checkIn)),
            _buildSummaryDataRow('Check-Out', _formatTime(record.checkOut)),
            _buildSummaryDataRow('Lunch Break', '${record.breakMinutes} mins'),
            _buildSummaryDataRow('Casual Break', '${record.casualBreakMinutes} mins'),
            const Divider(height: 20, color: CeladonColors.border),
            _buildSummaryDataRow(
              'Total Working Time',
              _formatSecondsToHMS(_workingSecondsElapsed),
              isHighlight: true,
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: CeladonColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Great', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryDataRow(String label, String value, {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isHighlight ? FontWeight.w800 : FontWeight.w600,
              color: isHighlight ? CeladonColors.textPrimary : CeladonColors.textMuted,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: isHighlight ? CeladonColors.primary : CeladonColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // FORMATTERS
  // ---------------------------------------------------------------------------
  String _formatTodayDate(DateTime dt) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${days[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  String _formatLiveClock(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${h.toString().padLeft(2, '0')}:$m:$s $ampm';
  }

  String _formatShiftTimeString(String timeStr) {
    if (timeStr.isEmpty) return '09:30 AM';
    final parts = timeStr.trim().split(':');
    final hRaw = int.tryParse(parts[0]) ?? 9;
    final mRaw = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final h = hRaw % 12 == 0 ? 12 : hRaw % 12;
    final ampm = hRaw >= 12 ? 'PM' : 'AM';
    return '${h.toString().padLeft(2, '0')}:${mRaw.toString().padLeft(2, '0')} $ampm';
  }

  String _formatTime(String? isoStr) {
    if (isoStr == null || isoStr.isEmpty) return '--:--';
    final dt = DateTime.tryParse(isoStr);
    if (dt == null) return isoStr;
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${h.toString().padLeft(2, '0')}:$m $ampm';
  }

  String _formatSecondsToHMS(int totalSec) {
    final hours = totalSec ~/ 3600;
    final minutes = (totalSec % 3600) ~/ 60;
    final seconds = totalSec % 60;
    return '${hours.toString().padLeft(2, '0')}h ${minutes.toString().padLeft(2, '0')}m ${seconds.toString().padLeft(2, '0')}s';
  }

  // ---------------------------------------------------------------------------
  // MAIN BUILD METHOD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CeladonColors.background,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: CeladonColors.primary))
            : RefreshIndicator(
                onRefresh: _loadAllData,
                color: CeladonColors.primary,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. TOP HEADER (Messenger Style straight to back arrow, no wrap)
                      _buildTopHeader(),
                      const SizedBox(height: 16),

                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, size: 18, color: CeladonColors.error),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(fontSize: 12, color: CeladonColors.error, fontWeight: FontWeight.w600),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 16, color: CeladonColors.error),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => setState(() => _errorMessage = null),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // 2. FIELD 1: Date, Digital Clock & Shift Policy Card
                      _buildField1DateAndShiftCard(),
                      const SizedBox(height: 14),

                      // 3. FIELD 2: Working Hours Live Timer Card
                      _buildField2WorkingHoursTimerCard(),
                      const SizedBox(height: 14),

                      // 4. FIELD 3: Check-in Box
                      _buildField3CheckInBox(),
                      const SizedBox(height: 14),

                      // 5. FIELD 4: Break Field (Lunch Break & Casual Break)
                      _buildField4BreaksCard(),
                      const SizedBox(height: 14),

                      // 6. FIELD 5: Check-Out Box
                      _buildField5CheckOutBox(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TASK 1: TOP HEADER (Messenger style straight to arrow, no line wrapping)
  // ---------------------------------------------------------------------------
  Widget _buildTopHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: CeladonColors.textPrimary,
            size: 22,
          ),
          tooltip: 'Back',
          onPressed: widget.onBack ??
              () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                } else if (widget.onOpenDrawer != null) {
                  widget.onOpenDrawer!();
                }
              },
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text(
                'Attendance',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: CeladonColors.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Track daily check-in, hours & breaks.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: CeladonColors.textMuted,
                  height: 1.25,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Geofence chip badge (No Spacer, so Attendance never wraps)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF5EE),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: CeladonColors.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_on_rounded, size: 13, color: CeladonColors.primary),
              const SizedBox(width: 4),
              Text(
                _lastMeasuredDistance != null
                    ? '${_lastMeasuredDistance!.toStringAsFixed(1)}m'
                    : '5m Geofence',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: CeladonColors.primary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TASK 2 - FIELD 1: Today Date, Live Clock & Shift Timing from Work Policy
  // ---------------------------------------------------------------------------
  Widget _buildField1DateAndShiftCard() {
    final shiftStartFormatted = _formatShiftTimeString(_workSchedule.shiftStart);
    final shiftEndFormatted = _formatShiftTimeString(_workSchedule.shiftEnd);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CeladonColors.border),
        boxShadow: const [
          BoxShadow(color: Color(0x06000000), blurRadius: 10, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: CeladonColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.calendar_today_rounded, color: CeladonColors.primary, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatTodayDate(_now),
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: CeladonColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _currentUser?.name.isNotEmpty == true
                            ? 'Employee: ${_currentUser!.name}'
                            : 'Workday Schedule',
                        style: const TextStyle(fontSize: 11, color: CeladonColors.textMuted),
                      ),
                    ],
                  ),
                ],
              ),
              // Live Clock Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: CeladonColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: CeladonColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.access_time_rounded, size: 13, color: CeladonColors.primary),
                    const SizedBox(width: 5),
                    Text(
                      _formatLiveClock(_now),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: CeladonColors.textPrimary,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: CeladonColors.borderLight),
          const SizedBox(height: 12),
          // Shift Timing from Company Policy
          Row(
            children: [
              Expanded(
                child: _buildPolicyDetailPill(
                  icon: Icons.schedule_rounded,
                  label: 'Shift Timing',
                  value: '$shiftStartFormatted - $shiftEndFormatted',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildPolicyDetailPill(
                  icon: Icons.timelapse_rounded,
                  label: 'Standard Hours',
                  value: '${_workSchedule.workingHoursPerDay} hrs / day',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPolicyDetailPill({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: CeladonColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: CeladonColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: CeladonColors.primary),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(fontSize: 10.5, color: CeladonColors.textMuted, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: CeladonColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TASK 2 - FIELD 2: Working Hours Live Timer Card
  // ---------------------------------------------------------------------------
  Widget _buildField2WorkingHoursTimerCard() {
    final isCheckedIn = _todayAttendance?.isCheckedIn ?? false;
    final isCheckedOut = _todayAttendance?.isCheckedOut ?? false;
    final isOnBreak = _todayAttendance?.isOnBreak ?? false;

    Color badgeBg;
    Color badgeColor;
    String badgeText;
    IconData badgeIcon;

    if (!isCheckedIn) {
      badgeBg = const Color(0xFFF1F5F9);
      badgeColor = const Color(0xFF64748B);
      badgeText = 'Not Started';
      badgeIcon = Icons.hourglass_empty_rounded;
    } else if (isCheckedOut) {
      badgeBg = const Color(0xFFEAF5EE);
      badgeColor = CeladonColors.primary;
      badgeText = 'Completed';
      badgeIcon = Icons.check_circle_rounded;
    } else if (isOnBreak) {
      badgeBg = const Color(0xFFFEF3C7);
      badgeColor = const Color(0xFFD97706);
      badgeText = 'Paused (On ${_todayAttendance!.activeBreakType == 'casual' ? 'Casual' : 'Lunch'} Break)';
      badgeIcon = Icons.pause_circle_rounded;
    } else {
      badgeBg = const Color(0xFFEAF5EE);
      badgeColor = CeladonColors.primary;
      badgeText = 'Active Working';
      badgeIcon = Icons.play_circle_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isCheckedIn && !isCheckedOut && !isOnBreak
              ? CeladonColors.primary.withValues(alpha: 0.5)
              : CeladonColors.border,
          width: isCheckedIn && !isCheckedOut && !isOnBreak ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isCheckedIn && !isCheckedOut && !isOnBreak
                ? CeladonColors.primary.withValues(alpha: 0.08)
                : const Color(0x06000000),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Working Hours',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: CeladonColors.textPrimary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 12, color: badgeColor),
                    const SizedBox(width: 4),
                    Text(
                      badgeText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: badgeColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Large digital stopwatch counter
          Center(
            child: Text(
              _formatSecondsToHMS(_workingSecondsElapsed),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: CeladonColors.textPrimary,
                letterSpacing: 0.5,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              !isCheckedIn
                  ? 'Timer starts immediately upon check-in'
                  : isCheckedOut
                      ? 'Workday concluded at ${_formatTime(_todayAttendance?.checkOut)}'
                      : isOnBreak
                          ? 'Timer paused during break period'
                          : 'Live timer counting active worked hours',
              style: const TextStyle(fontSize: 11, color: CeladonColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TASK 2 - FIELD 3: Check-in Box
  // ---------------------------------------------------------------------------
  Widget _buildField3CheckInBox() {
    final isCheckedIn = _todayAttendance?.isCheckedIn ?? false;
    final isLate = _todayAttendance?.isLate ?? false;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CeladonColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.login_rounded, size: 18, color: CeladonColors.primary),
                  SizedBox(width: 6),
                  Text(
                    'Check-In',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: CeladonColors.textPrimary,
                    ),
                  ),
                ],
              ),
              if (isCheckedIn)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isLate ? const Color(0xFFFEF3C7) : const Color(0xFFEAF5EE),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isLate ? 'LATE' : 'PRESENT',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: isLate ? const Color(0xFFD97706) : CeladonColors.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (!isCheckedIn) ...[
            const Text(
              'Verify you are within 5 metres of the office location and tap Check-In.',
              style: TextStyle(fontSize: 11.5, color: CeladonColors.textSecondary),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: _isActionInProgress
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.fingerprint_rounded, size: 20),
              label: Text(
                _isActionInProgress ? 'Verifying 5m Geofence...' : 'Check In',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: CeladonColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              onPressed: _isActionInProgress ? null : _handleCheckIn,
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CeladonColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: CeladonColors.borderLight),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: CeladonColors.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Checked in at ${_formatTime(_todayAttendance?.checkIn)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: CeladonColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'GPS Verified • Distance: ${_todayAttendance?.distance?.toStringAsFixed(1) ?? '2.1'}m from office',
                          style: const TextStyle(fontSize: 11, color: CeladonColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TASK 2 - FIELD 4: Break Field (Lunch Break & Casual Break)
  // ---------------------------------------------------------------------------
  Widget _buildField4BreaksCard() {
    final isCheckedIn = _todayAttendance?.isCheckedIn ?? false;
    final isCheckedOut = _todayAttendance?.isCheckedOut ?? false;
    final isOnOfficial = _todayAttendance?.isOnOfficialBreak ?? false;
    final isOnCasual = _todayAttendance?.isOnCasualBreak ?? false;
    final isEnabled = isCheckedIn && !isCheckedOut;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CeladonColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.free_breakfast_rounded, size: 18, color: CeladonColors.primary),
                  SizedBox(width: 6),
                  Text(
                    'Breaks',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: CeladonColors.textPrimary,
                    ),
                  ),
                ],
              ),
              if (!isEnabled)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isCheckedOut ? Icons.check_circle_outline : Icons.lock_outline_rounded,
                          size: 11, color: const Color(0xFF64748B)),
                      const SizedBox(width: 3),
                      Text(
                        isCheckedOut ? 'Concluded' : 'Locked until Check-In',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Break Option 1: Lunch Break
          _buildBreakOptionItem(
            title: 'Lunch Break',
            subtitle: '${_workSchedule.breakTime} mins allowed per policy',
            minutesTaken: _todayAttendance?.breakMinutes ?? 0,
            isActive: isOnOfficial,
            activeSecondsElapsed: _lunchBreakSecondsElapsed,
            isEnabled: isEnabled && !isOnCasual,
            onStart: () => _handleStartBreak('official'),
            onStop: () => _handleEndBreak('official'),
          ),
          const SizedBox(height: 10),

          // Break Option 2: Casual Break
          _buildBreakOptionItem(
            title: 'Casual Break',
            subtitle: '${_workSchedule.casualBreakTime} mins allowed per policy',
            minutesTaken: _todayAttendance?.casualBreakMinutes ?? 0,
            isActive: isOnCasual,
            activeSecondsElapsed: _casualBreakSecondsElapsed,
            isEnabled: isEnabled && !isOnOfficial,
            onStart: () => _handleStartBreak('casual'),
            onStop: () => _handleEndBreak('casual'),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakOptionItem({
    required String title,
    required String subtitle,
    required int minutesTaken,
    required bool isActive,
    required int activeSecondsElapsed,
    required bool isEnabled,
    required VoidCallback onStart,
    required VoidCallback onStop,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFFFFBEB) : CeladonColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? const Color(0xFFF59E0B) : CeladonColors.borderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: CeladonColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 11, color: CeladonColors.textMuted),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: CeladonColors.borderLight),
                ),
                child: Text(
                  '$minutesTaken mins taken',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: CeladonColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (isActive) ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              alignment: Alignment.center,
              child: Text(
                'Active: ${_formatSecondsToHMS(activeSecondsElapsed)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFD97706),
                ),
              ),
            ),
            const SizedBox(height: 6),
            ElevatedButton.icon(
              icon: _isActionInProgress
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.stop_circle_rounded, size: 18),
              label: Text('Stop $title', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              onPressed: _isActionInProgress ? null : onStop,
            ),
          ] else ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text('Start $title', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
              style: OutlinedButton.styleFrom(
                foregroundColor: isEnabled ? CeladonColors.primary : CeladonColors.textMuted,
                side: BorderSide(color: isEnabled ? CeladonColors.primary : CeladonColors.border),
                padding: const EdgeInsets.symmetric(vertical: 9),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: isEnabled && !_isActionInProgress ? onStart : null,
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TASK 2 - FIELD 5: Check-Out Box
  // ---------------------------------------------------------------------------
  Widget _buildField5CheckOutBox() {
    final isCheckedIn = _todayAttendance?.isCheckedIn ?? false;
    final isCheckedOut = _todayAttendance?.isCheckedOut ?? false;
    final isOnBreak = _todayAttendance?.isOnBreak ?? false;
    final isEnabled = isCheckedIn && !isCheckedOut;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CeladonColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: const [
              Icon(Icons.logout_rounded, size: 18, color: CeladonColors.primary),
              SizedBox(width: 6),
              Text(
                'Check-Out',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: CeladonColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (isCheckedOut) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CeladonColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: CeladonColors.borderLight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.verified_rounded, color: CeladonColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Checked out at ${_formatTime(_todayAttendance?.checkOut)}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: CeladonColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Total Workday: ${_formatSecondsToHMS(_workingSecondsElapsed)} • GPS Verified (${_todayAttendance?.distance?.toStringAsFixed(1) ?? '2.1'}m)',
                    style: const TextStyle(fontSize: 11, color: CeladonColors.textMuted),
                  ),
                ],
              ),
            ),
          ] else ...[
            Text(
              isOnBreak
                  ? 'Please finish and stop your active break before checking out.'
                  : !isCheckedIn
                      ? 'Check-out will become available after you check in.'
                      : 'Ensure you are within 5 metres of the office to stop working hours.',
              style: const TextStyle(fontSize: 11.5, color: CeladonColors.textSecondary),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: _isActionInProgress
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.logout_rounded, size: 18),
              label: Text(
                _isActionInProgress ? 'Verifying Location...' : 'Check Out',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isEnabled && !isOnBreak ? CeladonColors.error : const Color(0xFFCBD5E1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              onPressed: isEnabled && !isOnBreak && !_isActionInProgress ? _handleCheckOut : null,
            ),
          ],
        ],
      ),
    );
  }
}
