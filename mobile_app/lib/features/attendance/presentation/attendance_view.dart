import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/services/location_service.dart';
import '../../../core/storage/session_storage.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../auth/data/user_model.dart';
import '../../company/data/company_model.dart';
import '../../dashboard/data/dashboard_service.dart';
import '../data/attendance_model.dart';
import '../data/attendance_service.dart';
import '../data/work_schedule_model.dart';

/// Screen 4: Attendance Screen
///
/// Reproduces Screen 4 from the "8. Premium Celadon" design specification
/// connected to live MongoDB attendance records and strictly enforcing the
/// 5-metre backend geofence rule.
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
  List<AttendanceModel> _history = [];

  bool _isLoading = true;
  bool _isActionInProgress = false;
  String? _errorMessage;

  int _selectedSegment = 0; // 0: Month, 1: Week, 2: List
  late DateTime _displayedMonth;
  late DateTime _selectedDate;

  Timer? _breakTimer;
  int _breakSecondsElapsed = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _displayedMonth = DateTime(now.year, now.month, 1);
    _selectedDate = DateTime(now.year, now.month, now.day);
    _loadAllData();
  }

  @override
  void dispose() {
    _breakTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = await SessionStorage.getUserSession();
      _currentUser = user;

      // 1. Fetch Company details for office geofence coords
      final companies = await _dashboardService.getCompanies();
      if (companies.isNotEmpty) {
        _userCompany = companies.first;
      }

      // 2. Fetch Work Schedule (shift hours & break times)
      final schedule = await _attendanceService.getWorkSchedule();
      _workSchedule = schedule;

      // 3. Fetch Today's Attendance
      final todayRecord = await _attendanceService.getTodayAttendance();
      _todayAttendance = todayRecord;

      // 4. Fetch Attendance History
      if (user != null) {
        final historyList = await _attendanceService.getUserAttendanceHistory(user.userId);
        _history = historyList;
      }

      _startBreakTimerIfNeeded();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _startBreakTimerIfNeeded() {
    _breakTimer?.cancel();
    if (_todayAttendance != null && _todayAttendance!.isOnBreak) {
      final startStr = _todayAttendance!.isOnOfficialBreak
          ? _todayAttendance!.breakStart
          : _todayAttendance!.casualBreakStart;

      if (startStr != null) {
        final startTime = DateTime.tryParse(startStr);
        if (startTime != null) {
          _breakSecondsElapsed = DateTime.now().difference(startTime).inSeconds;
          _breakTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
            if (mounted) {
              setState(() {
                _breakSecondsElapsed++;
              });
            }
          });
        }
      }
    }
  }

  String _formatTimeOnly(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '--:--';
    final dt = DateTime.tryParse(isoString)?.toLocal();
    if (dt == null) return '--:--';

    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '${displayHour.toString().padLeft(2, '0')}:$minute $period';
  }

  String _formatDateYMD(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _monthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }

  /// Perform Check-In or Check-Out with real GPS coordinates
  Future<void> _handleCheckInOut() async {
    setState(() => _isActionInProgress = true);

    try {
      // 1. Acquire real high-accuracy GPS position
      final position = await LocationService.getCurrentPosition();

      if (_todayAttendance == null || !_todayAttendance!.isCheckedIn) {
        // Perform Check-In
        final newRecord = await _attendanceService.checkIn(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
        );
        setState(() {
          _todayAttendance = newRecord;
          _history.insert(0, newRecord);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Checked in at ${_formatTimeOnly(newRecord.checkIn)} (GPS verified <= 5m)'),
              backgroundColor: CeladonColors.primary,
            ),
          );
        }
      } else if (!_todayAttendance!.isCheckedOut) {
        // Perform Check-Out
        final updatedRecord = await _attendanceService.checkOut(
          attendanceId: _todayAttendance!.id,
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
        );
        setState(() {
          _todayAttendance = updatedRecord;
          final idx = _history.indexWhere((h) => h.id == updatedRecord.id);
          if (idx != -1) {
            _history[idx] = updatedRecord;
          }
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Checked out at ${_formatTimeOnly(updatedRecord.checkOut)}'),
              backgroundColor: CeladonColors.primary,
            ),
          );
        }
      }
    } on LocationCustomException catch (e) {
      _showErrorDialog('GPS Location Required', e.message);
    } on GeofenceException catch (e) {
      if (e.code == 'OFFICE_LOCATION_NOT_SET') {
        _showOfficeLocationNotSetDialog();
      } else if (e.code == 'OUTSIDE_GEOFENCE') {
        final dist = e.distance != null ? '${e.distance} metres' : 'outside allowed radius';
        _showErrorDialog(
          'Outside 5m Geofence',
          'You are currently $dist away from the company office.\n\nThe system strictly requires you to be within 5 metres of the office to check in or check out.',
        );
      } else {
        _showErrorDialog('Attendance Validation Error', e.message);
      }
    } catch (e) {
      _showErrorDialog('Error', e.toString());
    } finally {
      if (mounted) {
        setState(() => _isActionInProgress = false);
      }
    }
  }

  /// Toggle Official or Casual Break with GPS validation
  Future<void> _handleBreakToggle(String breakType) async {
    if (_todayAttendance == null) return;
    setState(() => _isActionInProgress = true);

    try {
      final position = await LocationService.getCurrentPosition();
      final isCurrentlyOnThisBreak = (_todayAttendance!.activeBreakType == breakType);

      AttendanceModel updated;
      if (isCurrentlyOnThisBreak) {
        // End break
        updated = await _attendanceService.endBreak(
          attendanceId: _todayAttendance!.id,
          breakType: breakType,
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
        );
      } else {
        // Start break
        updated = await _attendanceService.startBreak(
          attendanceId: _todayAttendance!.id,
          breakType: breakType,
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
        );
      }

      setState(() {
        _todayAttendance = updated;
        final idx = _history.indexWhere((h) => h.id == updated.id);
        if (idx != -1) _history[idx] = updated;
      });
      _startBreakTimerIfNeeded();

      if (mounted) {
        final action = isCurrentlyOnThisBreak ? 'ended' : 'started';
        final typeLabel = breakType == 'official' ? 'Lunch break' : 'Tea break';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$typeLabel $action successfully.'),
            backgroundColor: CeladonColors.primary,
          ),
        );
      }
    } on LocationCustomException catch (e) {
      _showErrorDialog('GPS Required', e.message);
    } on GeofenceException catch (e) {
      _showErrorDialog('Geofence Restriction', e.message);
    } catch (e) {
      _showErrorDialog('Error', e.toString());
    } finally {
      if (mounted) {
        setState(() => _isActionInProgress = false);
      }
    }
  }

  void _showErrorDialog(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 26),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: Text(message, style: const TextStyle(fontSize: 14, height: 1.4)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: CeladonColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showOfficeLocationNotSetDialog() {
    if (!mounted) return;
    final isOwner = _currentUser?.isCompanyAdmin ?? false;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.location_off_rounded, color: Colors.orange, size: 26),
            SizedBox(width: 8),
            Expanded(
              child: Text('Office Location Not Set', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        content: Text(
          isOwner
              ? 'Your company does not have an office location registered yet. Please set your office GPS coordinates to enable the 5-metre geofence.'
              : 'Your company administrator has not yet configured the office location coordinates. Please notify your administrator.',
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          if (isOwner && _userCompany != null)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _showSetOfficeLocationDialog();
              },
              child: const Text('Set Location Now', style: TextStyle(color: CeladonColors.primary, fontWeight: FontWeight.bold)),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: CeladonColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showSetOfficeLocationDialog() {
    final messenger = ScaffoldMessenger.of(context);
    final latController = TextEditingController();
    final lonController = TextEditingController();
    final addrController = TextEditingController(text: _userCompany?.name ?? 'Office');
    bool isDetecting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Set Company Office Location', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Employees must be within 5 metres of these coordinates to check in or out.',
                  style: TextStyle(fontSize: 13, color: CeladonColors.textSecondary),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  icon: isDetecting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location_rounded, size: 18),
                  label: Text(isDetecting ? 'Acquiring GPS...' : 'Use Current Device GPS'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CeladonColors.primary,
                    side: const BorderSide(color: CeladonColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: isDetecting
                      ? null
                      : () async {
                          setDialogState(() => isDetecting = true);
                          try {
                            final pos = await LocationService.getCurrentPosition();
                            latController.text = pos.latitude.toStringAsFixed(6);
                            lonController.text = pos.longitude.toStringAsFixed(6);
                          } catch (e) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('GPS Error: $e')),
                            );
                          } finally {
                            setDialogState(() => isDetecting = false);
                          }
                        },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: latController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'Latitude (e.g. 11.011339)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: lonController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'Longitude (e.g. 76.946477)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: addrController,
                  decoration: const InputDecoration(labelText: 'Address / Label', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CeladonColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final nav = Navigator.of(ctx);
                final lat = double.tryParse(latController.text.trim());
                final lon = double.tryParse(lonController.text.trim());
                if (lat == null || lon == null) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Please enter valid numeric latitude and longitude')),
                  );
                  return;
                }

                try {
                  await _attendanceService.updateOfficeLocation(
                    _userCompany!.id,
                    latitude: lat,
                    longitude: lon,
                    address: addrController.text.trim(),
                  );
                  nav.pop();
                  _loadAllData();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Office location updated! 5m Geofence is active.'),
                      backgroundColor: CeladonColors.primary,
                    ),
                  );
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('Failed: $e')),
                  );
                }
              },
              child: const Text('Save Coordinates', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

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
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Top Navigation Bar
                      Row(
                        children: [
                          if (widget.onOpenDrawer != null) ...[
                            Container(
                              width: 38,
                              height: 38,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: CeladonColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                icon: const Icon(
                                  Icons.menu_rounded,
                                  color: CeladonColors.primaryDark,
                                  size: 22,
                                ),
                                tooltip: 'Menu',
                                onPressed: widget.onOpenDrawer,
                              ),
                            ),
                          ],
                          if (widget.onBack != null)
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                size: 20,
                                color: CeladonColors.textPrimary,
                              ),
                              onPressed: widget.onBack,
                            )
                          else
                            const SizedBox(width: 4),
                          const Expanded(
                            child: Text(
                              'Attendance',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: CeladonColors.textPrimary,
                              ),
                            ),
                          ),
                          // Geofence status chip
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: (_userCompany?.hasOfficeLocation ?? false)
                                  ? const Color(0xFFE8F5E9)
                                  : const Color(0xFFFFF3E0),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: (_userCompany?.hasOfficeLocation ?? false)
                                    ? Colors.green.shade300
                                    : Colors.orange.shade300,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.location_on_rounded,
                                  size: 14,
                                  color: (_userCompany?.hasOfficeLocation ?? false)
                                      ? Colors.green.shade800
                                      : Colors.orange.shade800,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  (_userCompany?.hasOfficeLocation ?? false) ? '5m Geofence' : 'No Office GPS',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: (_userCompany?.hasOfficeLocation ?? false)
                                        ? Colors.green.shade800
                                        : Colors.orange.shade800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Error Banner if any
                      if (_errorMessage != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEBEE),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, color: Colors.red, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                              ),
                              IconButton(
                                icon: const Icon(Icons.refresh, size: 18, color: Colors.red),
                                onPressed: _loadAllData,
                              ),
                            ],
                          ),
                        ),

                      // 2. Segmented Pill Bar: [Month] [Week] [List]
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2EFE7),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          children: [
                            _buildSegmentItem('Month', 0),
                            _buildSegmentItem('Week', 1),
                            _buildSegmentItem('List', 2),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // 3. Dynamic Segment View
                      if (_selectedSegment == 0) _buildMonthView(),
                      if (_selectedSegment == 1) _buildWeekView(),
                      if (_selectedSegment == 2) _buildListView(),

                      const SizedBox(height: 20),

                      // 4. Status Card: Dynamic Check In & Out info
                      _buildCheckInStatusCard(),
                      const SizedBox(height: 16),

                      // 5. Breaks Management Card (when employee is checked in & active)
                      if (_todayAttendance != null &&
                          _todayAttendance!.isCheckedIn &&
                          !_todayAttendance!.isCheckedOut)
                        _buildBreakControlCard(),

                      const SizedBox(height: 18),

                      // 6. Action Button: "Check In" / "Check Out"
                      _buildActionButton(),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildSegmentItem(String title, int index) {
    final isSelected = _selectedSegment == index;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedSegment = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? CeladonColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          alignment: Alignment.center,
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? Colors.white : CeladonColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // SEGMENT 0: MONTH CALENDAR VIEW
  // ==========================================
  Widget _buildMonthView() {
    final monthStr = '${_monthName(_displayedMonth.month)} ${_displayedMonth.year}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: CeladonColors.borderLight),
        boxShadow: const [
          BoxShadow(
            color: Color(0x062D6A4F),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // Month Selector Header: < Month Year >
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.chevron_left_rounded,
                  color: CeladonColors.textPrimary,
                  size: 22,
                ),
                onPressed: () {
                  setState(() {
                    _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month - 1, 1);
                  });
                },
              ),
              Text(
                monthStr,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: CeladonColors.textPrimary,
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.chevron_right_rounded,
                  color: CeladonColors.textPrimary,
                  size: 22,
                ),
                onPressed: () {
                  setState(() {
                    _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month + 1, 1);
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Day of Week Header: S M T W T F S
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _WeekdayLabel('S'),
              _WeekdayLabel('M'),
              _WeekdayLabel('T'),
              _WeekdayLabel('W'),
              _WeekdayLabel('T'),
              _WeekdayLabel('F'),
              _WeekdayLabel('S'),
            ],
          ),
          const SizedBox(height: 10),

          // Calendar Grid
          _buildCalendarGrid(),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final firstDayOfMonth = DateTime(_displayedMonth.year, _displayedMonth.month, 1);
    final daysInMonth = DateTime(_displayedMonth.year, _displayedMonth.month + 1, 0).day;

    // Sunday = 7 in Dart, map to 0 (Sunday) through 6 (Saturday)
    final leadingSpaces = firstDayOfMonth.weekday == 7 ? 0 : firstDayOfMonth.weekday;

    final days = <Widget>[];

    for (int i = 0; i < leadingSpaces; i++) {
      days.add(const SizedBox());
    }

    for (int day = 1; day <= daysInMonth; day++) {
      final thisDate = DateTime(_displayedMonth.year, _displayedMonth.month, day);
      final dateStr = _formatDateYMD(thisDate);
      final isSelected = (_selectedDate.year == thisDate.year &&
          _selectedDate.month == thisDate.month &&
          _selectedDate.day == thisDate.day);

      // Match attendance for this date
      AttendanceModel? record;
      for (final h in _history) {
        if (h.date == dateStr) {
          record = h;
          break;
        }
      }

      Color dotColor = Colors.transparent;
      if (record != null) {
        if (record.isLate) {
          dotColor = const Color(0xFFF4A261); // Amber
        } else if (record.isPresent) {
          dotColor = const Color(0xFF2D6A4F); // Green
        } else if (record.isAbsent) {
          dotColor = Colors.redAccent;
        }
      }

      days.add(
        GestureDetector(
          onTap: () => setState(() => _selectedDate = thisDate),
          child: Container(
            margin: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              color: isSelected ? CeladonColors.primary : Colors.transparent,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? Colors.white : CeladonColors.textPrimary,
                  ),
                ),
                if (!isSelected && record != null)
                  Positioned(
                    bottom: 2,
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 7,
      childAspectRatio: 1.15,
      children: days,
    );
  }

  // ==========================================
  // SEGMENT 1: WEEK VIEW
  // ==========================================
  Widget _buildWeekView() {
    final now = DateTime.now();
    final dayOfWeek = now.weekday == 7 ? 0 : now.weekday; // Sunday = 0
    final startOfWeek = now.subtract(Duration(days: dayOfWeek));

    return Column(
      children: List.generate(7, (index) {
        final dayDate = startOfWeek.add(Duration(days: index));
        final dateStr = _formatDateYMD(dayDate);
        final isToday = dayDate.year == now.year && dayDate.month == now.month && dayDate.day == now.day;

        AttendanceModel? att;
        for (final h in _history) {
          if (h.date == dateStr) {
            att = h;
            break;
          }
        }

        const weekdayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isToday ? const Color(0xFFF0FDF4) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isToday ? CeladonColors.primary : CeladonColors.borderLight,
              width: isToday ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: isToday ? CeladonColors.primary : const Color(0xFFE2EFE7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      weekdayNames[index],
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isToday ? Colors.white : CeladonColors.textSecondary,
                      ),
                    ),
                    Text(
                      '${dayDate.day}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: isToday ? Colors.white : CeladonColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      att != null
                          ? 'In: ${_formatTimeOnly(att.checkIn)}  •  Out: ${_formatTimeOnly(att.checkOut)}'
                          : (_workSchedule.isWeeklyOff(dayDate) ? 'Weekly Off' : 'Not Recorded'),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: CeladonColors.textPrimary),
                    ),
                    if (att != null && att.breakMinutes > 0)
                      Text(
                        'Break: ${att.breakMinutes}m (Delay: ${att.breakDelayMinutes}m)',
                        style: const TextStyle(fontSize: 11, color: CeladonColors.textSecondary),
                      ),
                  ],
                ),
              ),
              _buildStatusPill(att?.status ?? (_workSchedule.isWeeklyOff(dayDate) ? 'off' : 'absent')),
            ],
          ),
        );
      }),
    );
  }

  // ==========================================
  // SEGMENT 2: LIST VIEW
  // ==========================================
  Widget _buildListView() {
    if (_history.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: CeladonColors.borderLight),
        ),
        alignment: Alignment.center,
        child: const Text('No attendance history found for this account.', style: TextStyle(color: CeladonColors.textSecondary)),
      );
    }

    return Column(
      children: _history.take(15).map((att) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: CeladonColors.borderLight),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF5EE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.fingerprint_rounded, color: CeladonColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(att.date, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: CeladonColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                      'In: ${_formatTimeOnly(att.checkIn)} | Out: ${_formatTimeOnly(att.checkOut)}',
                      style: const TextStyle(fontSize: 12, color: CeladonColors.textSecondary),
                    ),
                    if (att.distance != null)
                      Text(
                        'Distance: ${att.distance!.toStringAsFixed(1)}m from office',
                        style: const TextStyle(fontSize: 11, color: CeladonColors.primary, fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
              ),
              _buildStatusPill(att.status),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStatusPill(String status) {
    Color bg = const Color(0xFFE8F5E9);
    Color fg = const Color(0xFF2D6A4F);
    String label = 'Present';

    switch (status.toLowerCase()) {
      case 'present':
        bg = const Color(0xFFE8F5E9);
        fg = const Color(0xFF2D6A4F);
        label = 'Present';
        break;
      case 'late':
        bg = const Color(0xFFFFF3E0);
        fg = const Color(0xFFE65100);
        label = 'Late';
        break;
      case 'half_day':
        bg = const Color(0xFFEDE7F6);
        fg = const Color(0xFF5E35B1);
        label = 'Half-Day';
        break;
      case 'off':
        bg = const Color(0xFFF5F5F5);
        fg = const Color(0xFF757575);
        label = 'Off';
        break;
      case 'absent':
      default:
        bg = const Color(0xFFFFEBEE);
        fg = const Color(0xFFC62828);
        label = 'Absent';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
    );
  }

  // ==========================================
  // STATUS CARD: CHECK IN & OUT
  // ==========================================
  Widget _buildCheckInStatusCard() {
    final isCheckedIn = _todayAttendance?.isCheckedIn ?? false;
    final isCheckedOut = _todayAttendance?.isCheckedOut ?? false;

    String title = 'Check In';
    String displayTime = '--:--';

    if (isCheckedOut) {
      title = 'Checked Out';
      displayTime = _formatTimeOnly(_todayAttendance!.checkOut);
    } else if (isCheckedIn) {
      title = 'Check In';
      displayTime = _formatTimeOnly(_todayAttendance!.checkIn);
    } else {
      title = 'Shift Target: ${_workSchedule.checkInTime}';
      displayTime = 'Not Checked In';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF5EE),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: CeladonColors.border),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: CeladonColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            displayTime,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: CeladonColors.primary,
            ),
          ),
          if (isCheckedIn && !isCheckedOut)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _todayAttendance!.isOnBreak
                    ? 'Currently on ${_todayAttendance!.activeBreakType == 'official' ? 'Lunch' : 'Tea'} Break'
                    : 'Actively Working in Office',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _todayAttendance!.isOnBreak ? Colors.orange.shade800 : CeladonColors.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ==========================================
  // BREAK CONTROLS CARD
  // ==========================================
  Widget _buildBreakControlCard() {
    final onOfficial = _todayAttendance?.isOnOfficialBreak ?? false;
    final onCasual = _todayAttendance?.isOnCasualBreak ?? false;

    final mins = _breakSecondsElapsed ~/ 60;
    final secs = _breakSecondsElapsed % 60;
    final timerStr = '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CeladonColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Break Management',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: CeladonColors.textPrimary),
              ),
              if (onOfficial || onCasual)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Text(
                    'Active: $timerStr',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.orange.shade800),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Official Break (Lunch)
              Expanded(
                child: ElevatedButton.icon(
                  icon: Icon(
                    onOfficial ? Icons.stop_circle_rounded : Icons.restaurant_rounded,
                    size: 16,
                  ),
                  label: Text(onOfficial ? 'End Lunch' : 'Lunch Break'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: onOfficial ? Colors.redAccent : const Color(0xFFE2EFE7),
                    foregroundColor: onOfficial ? Colors.white : CeladonColors.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: (_isActionInProgress || onCasual) ? null : () => _handleBreakToggle('official'),
                ),
              ),
              const SizedBox(width: 10),
              // Casual Break (Tea/Coffee)
              Expanded(
                child: ElevatedButton.icon(
                  icon: Icon(
                    onCasual ? Icons.stop_circle_rounded : Icons.local_cafe_rounded,
                    size: 16,
                  ),
                  label: Text(onCasual ? 'End Tea' : 'Tea Break'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: onCasual ? Colors.redAccent : const Color(0xFFE2EFE7),
                    foregroundColor: onCasual ? Colors.white : CeladonColors.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: (_isActionInProgress || onOfficial) ? null : () => _handleBreakToggle('casual'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // ACTION BUTTON: CHECK IN / OUT
  // ==========================================
  Widget _buildActionButton() {
    final isCheckedIn = _todayAttendance?.isCheckedIn ?? false;
    final isCheckedOut = _todayAttendance?.isCheckedOut ?? false;

    String btnText = 'Check In';
    Color btnColor = CeladonColors.primary;
    bool isCompleted = false;

    if (isCheckedOut) {
      btnText = 'Completed for Today';
      btnColor = Colors.grey.shade400;
      isCompleted = true;
    } else if (isCheckedIn) {
      btnText = 'Check Out';
      btnColor = const Color(0xFFB71C1C); // Deep red for check-out
    }

    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: (_isActionInProgress || isCompleted) ? null : _handleCheckInOut,
        style: ElevatedButton.styleFrom(
          backgroundColor: btnColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
        ),
        child: _isActionInProgress
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Verifying 5m GPS Geofence...',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ],
              )
            : Text(
                btnText,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
      ),
    );
  }
}

class _WeekdayLabel extends StatelessWidget {
  final String label;

  const _WeekdayLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: CeladonColors.textMuted,
        ),
      ),
    );
  }
}
