import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/storage/session_storage.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../../core/widgets/regen_page_header.dart';
import '../../attendance/data/attendance_service.dart';
import '../../attendance/data/work_schedule_model.dart';
import '../../auth/data/user_model.dart';
import '../../calendar/data/holiday_model.dart';
import '../../calendar/data/leave_service.dart';
import '../../dashboard/data/leave_model.dart';

/// Screen: Professional Leave Policy & Management Screen for Employees
class LeaveRequestView extends StatefulWidget {
  final VoidCallback? onBack;
  final UserModel? user;

  const LeaveRequestView({super.key, this.onBack, this.user});

  @override
  State<LeaveRequestView> createState() => _LeaveRequestViewState();
}

class _LeaveRequestViewState extends State<LeaveRequestView> {
  final _formKey = GlobalKey<FormState>();
  final LeaveService _leaveService = LeaveService();
  final AttendanceService _attendanceService = AttendanceService();

  String _selectedLeaveType = 'casual';
  final TextEditingController _reasonController = TextEditingController();
  DateTime _startDate = DateTime.now().add(const Duration(days: 1));
  DateTime _endDate = DateTime.now().add(const Duration(days: 1));

  bool _isLoading = true;
  bool _isSubmitting = false;
  List<LeaveModel> _leaves = [];
  UserModel? _currentUser;

  LeaveBalanceModel _balance = LeaveBalanceModel.initial();
  LeavePolicyModel _policy = LeavePolicyModel.defaultPolicy();
  WorkScheduleModel _workSchedule = const WorkScheduleModel();
  List<HolidayModel> _holidays = [];

  // History Filter & Pagination
  int _selectedFilterIndex = 0; // 0=All, 1=Pending, 2=Approved, 3=Rejected
  int _currentPage = 1;
  static const int _pageSize = 5;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  @override
  void didUpdateWidget(covariant LeaveRequestView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldUid = oldWidget.user?.userId.isNotEmpty == true ? oldWidget.user!.userId : oldWidget.user?.id;
    final newUid = widget.user?.userId.isNotEmpty == true ? widget.user!.userId : widget.user?.id;
    if (oldUid != newUid || oldWidget.user?.role != widget.user?.role || oldWidget.user?.token != widget.user?.token) {
      _loadAllData();
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    final user = widget.user ?? await SessionStorage.getUserSession();
    _currentUser = user;

    final myId = user?.userId.isNotEmpty == true ? user!.userId : (user?.id ?? '');

    try {
      final results = await Future.wait([
        _leaveService.getLeavePolicy(),
        _leaveService.getLeaveBalance(userId: myId),
        _leaveService.getUserLeaves(myId),
        _attendanceService.getWorkSchedule(),
        _attendanceService.getHolidays(),
      ]);

      if (mounted) {
        setState(() {
          _policy = results[0] as LeavePolicyModel;
          _balance = results[1] as LeaveBalanceModel;
          _leaves = results[2] as List<LeaveModel>;
          _workSchedule = results[3] as WorkScheduleModel;
          _holidays = results[4] as List<HolidayModel>;

          // Adjust selected type if currently selected is disabled
          final isCasual = _policy.casualLeave.enabled && _balance.casual.enabled;
          final isSick = _policy.sickLeave.enabled && _balance.sick.enabled;
          if (_selectedLeaveType == 'casual' && !isCasual) {
            _selectedLeaveType = isSick ? 'sick' : 'unpaid';
          } else if (_selectedLeaveType == 'sick' && !isSick) {
            _selectedLeaveType = isCasual ? 'casual' : 'unpaid';
          }
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int _calculateWorkingDays(DateTime start, DateTime end) {
    if (end.isBefore(start)) return 0;
    int count = 0;
    DateTime cur = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    final holidayDates = _holidays.map((h) => h.date.split('T').first).toSet();
    while (!cur.isAfter(endDay)) {
      final isOff = _workSchedule.isWeeklyOff(cur);
      final isoStr = "${cur.year}-${cur.month.toString().padLeft(2, '0')}-${cur.day.toString().padLeft(2, '0')}";
      final isHoliday = holidayDates.contains(isoStr);
      if (!isOff && !isHoliday) {
        count++;
      }
      cur = cur.add(const Duration(days: 1));
    }
    return count;
  }

  String _getWorkingDaysPolicyDescription() {
    final days = _workSchedule.workingDaysPerWeek;
    final offs = _workSchedule.weeklyOffDays;
    if (days >= 7 || offs.isEmpty) {
      return '(7-day schedule; excludes holidays)';
    }
    const dayNames = {
      0: 'Sun',
      1: 'Mon',
      2: 'Tue',
      3: 'Wed',
      4: 'Thu',
      5: 'Fri',
      6: 'Sat',
    };
    final offNames = offs.map((d) => dayNames[d] ?? 'Off').join('/');
    return '($days-day schedule; excludes $offNames & holidays)';
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final workingDays = _calculateWorkingDays(_startDate, _endDate);
    if (workingDays <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Selected range has 0 working days according to company work policy (${_workSchedule.workingDaysPerWeek} days/week).'),
          backgroundColor: CeladonColors.error,
        ),
      );
      return;
    }

    // Check balance for paid leave categories
    if (_selectedLeaveType == 'casual' && workingDays > _balance.casual.remaining) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Insufficient Casual Leave balance. You need $workingDays days, but have ${_balance.casual.remaining} remaining.'),
          backgroundColor: CeladonColors.error,
        ),
      );
      return;
    }
    if (_selectedLeaveType == 'sick' && workingDays > _balance.sick.remaining) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Insufficient Sick Leave balance. You need $workingDays days, but have ${_balance.sick.remaining} remaining.'),
          backgroundColor: CeladonColors.error,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final sStr = "${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}";
    final eStr = "${_endDate.year}-${_endDate.month.toString().padLeft(2, '0')}-${_endDate.day.toString().padLeft(2, '0')}";

    try {
      final created = await _leaveService.applyLeave(
        type: _selectedLeaveType,
        startDate: sStr,
        endDate: eStr,
        workingDays: workingDays,
        reason: _reasonController.text.trim(),
        userId: _currentUser?.userId.isNotEmpty == true ? _currentUser!.userId : _currentUser?.id,
      );

      if (mounted) {
        setState(() {
          _leaves.insert(0, created);
          _isSubmitting = false;
          _reasonController.clear();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Leave request submitted successfully for company owner review.'),
            backgroundColor: CeladonColors.primary,
          ),
        );
        _loadAllData();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit leave: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryGreen = CeladonColors.primary;
    final workingDays = _calculateWorkingDays(_startDate, _endDate);
    final todayStr = DateTime.now().toIso8601String().split('T').first;

    // Filter upcoming approved leaves
    final upcomingLeaves = _leaves.where((l) {
      return l.isApproved && l.endDate.compareTo(todayStr) >= 0;
    }).toList();

    // Filter history leaves
    final filteredHistory = _leaves.where((l) {
      if (_selectedFilterIndex == 1) return l.isPending;
      if (_selectedFilterIndex == 2) return l.isApproved;
      if (_selectedFilterIndex == 3) return l.isRejected;
      return true;
    }).toList();

    final totalPages = max(1, (filteredHistory.length / _pageSize).ceil());
    final effectivePage = min(_currentPage, totalPages);
    final startIndex = (effectivePage - 1) * _pageSize;
    final pageLeaves = filteredHistory.skip(startIndex).take(_pageSize).toList();

    return Scaffold(
      backgroundColor: CeladonColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadAllData,
          color: primaryGreen,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ReGenPageHeader(
                  title: 'Leaves',
                  subtitle: 'Submit leave requests and view balances.',
                  onBack: () {
                    if (widget.onBack != null) {
                      widget.onBack!();
                    } else {
                      Navigator.maybePop(context);
                    }
                  },
                  backTooltip: 'Back to Home',
                ),
                const SizedBox(height: 16),

                // 2. Real-Time Leave Balance Cards (Only display enabled categories)
                _buildLeaveBalanceSection(),
                const SizedBox(height: 18),

                // 3. Upcoming Approved Leaves Section (Golden Blue Distinguishable Theme)
                if (upcomingLeaves.isNotEmpty) ...[
                  _buildUpcomingLeavesSection(upcomingLeaves),
                  const SizedBox(height: 18),
                ],

                // 4. Application Form Card
                _buildApplicationFormCard(workingDays),
                const SizedBox(height: 22),

                // 5. Leave History Header & Filters
                _buildHistoryHeader(filteredHistory.length),
                const SizedBox(height: 10),

                // Filter Chips (All, Pending, Approved, Rejected)
                _buildHistoryFilterChips(),
                const SizedBox(height: 14),

                // 6. History Leave List with Pagination
                if (_isLoading)
                  const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: primaryGreen)))
                else if (filteredHistory.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    alignment: Alignment.center,
                    child: const Text('No leave applications in this filter.', style: TextStyle(color: CeladonColors.textMuted)),
                  )
                else ...[
                  ...pageLeaves.map((l) => _buildLeaveHistoryCard(l)),
                  const SizedBox(height: 12),
                  _buildPaginationControls(filteredHistory.length, effectivePage, totalPages),
                ],

                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // LEAVE BALANCE CARDS
  // --------------------------------------------------------------------------
  Widget _buildLeaveBalanceSection() {
    final cards = <Widget>[];

    final bool showCasual = _policy.casualLeave.enabled && _balance.casual.enabled;
    final bool showSick = _policy.sickLeave.enabled && _balance.sick.enabled;
    final bool showUnpaid = _policy.unpaidLeave.enabled && _balance.unpaid.enabled;

    if (showCasual) {
      cards.add(_buildSingleBalanceCard(
        title: 'Casual Leave',
        tag: 'Paid Leave',
        tagColor: CeladonColors.primary,
        entitlement: _balance.casual.entitlement,
        carriedForward: _balance.casual.carriedForward,
        used: _balance.casual.used,
        remaining: _balance.casual.remaining,
      ));
    }

    if (showSick) {
      cards.add(_buildSingleBalanceCard(
        title: 'Sick Leave',
        tag: 'Paid Leave',
        tagColor: const Color(0xFF0D9488),
        entitlement: _balance.sick.entitlement,
        carriedForward: _balance.sick.carriedForward,
        used: _balance.sick.used,
        remaining: _balance.sick.remaining,
      ));
    }

    if (showUnpaid) {
      cards.add(_buildUnpaidBalanceCard());
    }

    if (cards.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your Leave Balances',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: CeladonColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: cards.map((c) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: c,
            )).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSingleBalanceCard({
    required String title,
    required String tag,
    required Color tagColor,
    required double entitlement,
    required double carriedForward,
    required double used,
    required double remaining,
  }) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CeladonColors.border),
        boxShadow: const [
          BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: CeladonColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: tagColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: tagColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                remaining.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: CeladonColors.primary,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'days remaining',
                style: TextStyle(fontSize: 11.5, color: CeladonColors.textMuted, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: CeladonColors.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(child: _buildMiniStat('Entitled', '${entitlement.toStringAsFixed(1)}/mo')),
                const SizedBox(width: 4),
                Expanded(child: _buildMiniStat('Carried', carriedForward.toStringAsFixed(1))),
                const SizedBox(width: 4),
                Expanded(child: _buildMiniStat('Used', used.toStringAsFixed(1))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnpaidBalanceCard() {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CeladonColors.border),
        boxShadow: const [
          BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Unpaid Leave',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: CeladonColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Working-Day Based',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFD97706),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _balance.unpaid.used.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFD97706),
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'days taken',
                style: TextStyle(fontSize: 11.5, color: CeladonColors.textMuted, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: CeladonColors.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(child: _buildMiniStat('Entitlement', 'Unlimited')),
                const SizedBox(width: 4),
                Expanded(child: _buildMiniStat('Deduction', '${_balance.unpaid.approvedDeductionRate.toInt()}%')),
                const SizedBox(width: 4),
                Expanded(child: _buildMiniStat('Approval', 'Required')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String val) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: CeladonColors.textMuted, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          val,
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: CeladonColors.textPrimary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // UPCOMING APPROVED LEAVES (GOLDEN BLUE THEME)
  // --------------------------------------------------------------------------
  Widget _buildUpcomingLeavesSection(List<LeaveModel> upcoming) {
    const goldenBlue = Color(0xFF2563EB);
    const goldenBlueBg = Color(0xFFEFF6FF);
    const goldenBlueBorder = Color(0xFFBFDBFE);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: goldenBlueBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: goldenBlueBorder, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_month_rounded, color: goldenBlue, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Upcoming Approved Leaves',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E3A8A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: goldenBlue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${upcoming.length} Scheduled',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...upcoming.map((l) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: goldenBlueBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: goldenBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.flight_takeoff_rounded, color: goldenBlue, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.displayType,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1E3A8A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${l.startDate}  →  ${l.endDate}  (${l.workingDays} working days)',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: CeladonColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDEF7EC),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'APPROVED',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF087A4B),
                    ),
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // APPLICATION FORM
  // --------------------------------------------------------------------------
  Widget _buildApplicationFormCard(int workingDays) {
    const primaryGreen = CeladonColors.primary;

    // Filter available leave types
    final availableTypes = <DropdownMenuItem<String>>[];
    if (_policy.casualLeave.enabled && _balance.casual.enabled) {
      availableTypes.add(const DropdownMenuItem(
        value: 'casual',
        child: Text('Casual Leave (Paid)', overflow: TextOverflow.ellipsis, maxLines: 1),
      ));
    }
    if (_policy.sickLeave.enabled && _balance.sick.enabled) {
      availableTypes.add(const DropdownMenuItem(
        value: 'sick',
        child: Text('Sick Leave (Paid)', overflow: TextOverflow.ellipsis, maxLines: 1),
      ));
    }
    if (_policy.unpaidLeave.enabled && _balance.unpaid.enabled) {
      availableTypes.add(const DropdownMenuItem(
        value: 'unpaid',
        child: Text('Unpaid Leave (Loss of Pay)', overflow: TextOverflow.ellipsis, maxLines: 1),
      ));
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CeladonColors.borderLight),
        boxShadow: const [
          BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Apply for Leave',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: CeladonColors.primary),
            ),
            const SizedBox(height: 4),
            const Text(
              'Select leave category and dates. Salary deductions apply on working-day basis for unpaid leave.',
              style: TextStyle(fontSize: 11.5, color: CeladonColors.textMuted),
            ),
            const SizedBox(height: 14),

            // Leave Type
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: availableTypes.any((t) => t.value == _selectedLeaveType)
                  ? _selectedLeaveType
                  : (availableTypes.isNotEmpty ? availableTypes.first.value : 'unpaid'),
              decoration: InputDecoration(
                labelText: 'Leave Type *',
                filled: true,
                fillColor: const Color(0xFFF8FAF9),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              selectedItemBuilder: (BuildContext context) {
                return availableTypes.map((item) {
                  final text = (item.child as Text).data ?? '';
                  return Text(
                    text,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 13,
                      color: CeladonColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }).toList();
              },
              items: availableTypes,
              onChanged: (v) {
                if (v != null) setState(() => _selectedLeaveType = v);
              },
            ),
            const SizedBox(height: 12),

            // Date Pickers Row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Start Date', style: TextStyle(fontSize: 11, color: CeladonColors.textMuted, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today_rounded, size: 14, color: CeladonColors.primary),
                        label: Text(
                          "${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}",
                          style: const TextStyle(fontSize: 11.5, color: CeladonColors.textPrimary, fontWeight: FontWeight.w600),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _startDate,
                            firstDate: DateTime.now().subtract(const Duration(days: 7)),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setState(() {
                              _startDate = picked;
                              if (_endDate.isBefore(_startDate)) {
                                _endDate = _startDate;
                              }
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('End Date', style: TextStyle(fontSize: 11, color: CeladonColors.textMuted, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today_rounded, size: 14, color: CeladonColors.primary),
                        label: Text(
                          "${_endDate.year}-${_endDate.month.toString().padLeft(2, '0')}-${_endDate.day.toString().padLeft(2, '0')}",
                          style: const TextStyle(fontSize: 11.5, color: CeladonColors.textPrimary, fontWeight: FontWeight.w600),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _endDate.isBefore(_startDate) ? _startDate : _endDate,
                            firstDate: _startDate,
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) setState(() => _endDate = picked);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Working Days indicator badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: CeladonColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: CeladonColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 14, color: CeladonColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Working Days: $workingDays day(s) ${_getWorkingDaysPolicyDescription()}',
                      style: const TextStyle(fontSize: 11, color: CeladonColors.textSecondary, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Reason Field
            TextFormField(
              controller: _reasonController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Reason for Leave *',
                hintText: 'Provide brief explanation for company owner approval...',
                filled: true,
                fillColor: const Color(0xFFF8FAF9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) return 'Please specify a reason';
                return null;
              },
            ),
            const SizedBox(height: 16),

            ElevatedButton(
              onPressed: _isSubmitting ? null : _handleSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSubmitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Submit Leave Application', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // LEAVE HISTORY & FILTERS
  // --------------------------------------------------------------------------
  Widget _buildHistoryHeader(int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Leave Request History',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: CeladonColors.textPrimary),
        ),
        Text(
          '$count records',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CeladonColors.textMuted),
        ),
      ],
    );
  }

  Widget _buildHistoryFilterChips() {
    final filters = ['All', 'Pending', 'Approved', 'Rejected'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.asMap().entries.map((e) {
          final isSelected = _selectedFilterIndex == e.key;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(e.value),
              selected: isSelected,
              selectedColor: CeladonColors.primary,
              backgroundColor: Colors.white,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : CeladonColors.textSecondary,
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              ),
              onSelected: (val) {
                if (val) {
                  setState(() {
                    _selectedFilterIndex = e.key;
                    _currentPage = 1;
                  });
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLeaveHistoryCard(LeaveModel leave) {
    Color statusColor = const Color(0xFFD97706);
    Color statusBg = const Color(0xFFFEF3C7);

    if (leave.isApproved) {
      statusColor = const Color(0xFF087A4B);
      statusBg = const Color(0xFFDEF7EC);
    } else if (leave.isRejected) {
      statusColor = const Color(0xFFDC4C4C);
      statusBg = const Color(0xFFFEE2E2);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CeladonColors.borderLight),
        boxShadow: const [BoxShadow(color: Color(0x04000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  leave.displayType.toUpperCase(),
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: CeladonColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  leave.displayStatus.toUpperCase(),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.date_range_rounded, size: 14, color: CeladonColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${leave.startDate}  →  ${leave.endDate} (${leave.workingDays} working days)',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CeladonColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (leave.reason != null && leave.reason!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Reason: ${leave.reason}',
              style: const TextStyle(fontSize: 11.5, color: CeladonColors.textMuted),
            ),
          ],
          if (leave.remarks != null && leave.remarks!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Remarks: ${leave.remarks}',
              style: const TextStyle(fontSize: 11, color: CeladonColors.error, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaginationControls(int totalItems, int page, int totalPages) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Page $page of $totalPages ($totalItems total)',
          style: const TextStyle(fontSize: 11.5, color: CeladonColors.textMuted, fontWeight: FontWeight.w600),
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: page > 1 ? () => setState(() => _currentPage = page - 1) : null,
              tooltip: 'Previous Page',
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: page < totalPages ? () => setState(() => _currentPage = page + 1) : null,
              tooltip: 'Next Page',
            ),
          ],
        ),
      ],
    );
  }
}
