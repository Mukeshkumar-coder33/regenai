import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../../core/widgets/regen_page_header.dart';
import '../../dashboard/data/payroll_service.dart';

/// Company Payroll Management Dashboard & Policy Workbench
///
/// Supports:
/// - Monthly employee salary list, totals, bonuses, manual deductions, paid & remaining
/// - Pending salaries from previous months + independent or multi-month settlement
/// - Full / partial dummy internal salary payments + transaction history
/// - Adding bonuses & manual deductions per employee
/// - Configuring full Company Payroll Policy (work hours, divisor, late, OT, break delay ₹1/10m, leave %)
/// - Finalizing/closing payroll month + viewing & downloading employee PDF payslips
class CompanyPayrollView extends StatefulWidget {
  final VoidCallback? onBack;
  final bool embedded;

  const CompanyPayrollView({super.key, this.onBack, this.embedded = true});

  @override
  State<CompanyPayrollView> createState() => _CompanyPayrollViewState();
}

class _CompanyPayrollViewState extends State<CompanyPayrollView> {
  final PayrollService _payrollService = PayrollService();
  final TextEditingController _searchCtrl = TextEditingController();

  late String _selectedMonth;
  String _statusTab = 'all'; // 'all', 'pending', 'processed', 'previous_pending'
  bool _isLoading = true;
  String? _error;

  Map<String, dynamic> _summary = {};
  Map<String, dynamic> _settings = {};
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _pendingPrior = [];
  double _totalPendingPrior = 0.0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  double _toDouble(dynamic val) {
    if (val is num) return val.toDouble();
    return double.tryParse(val?.toString() ?? '') ?? 0.0;
  }

  String _formatInr(double amount) {
    final absRounded = amount.abs().toStringAsFixed(amount.truncateToDouble() == amount ? 0 : 2);
    final parts = absRounded.split('.');
    final intPart = parts[0];
    String formattedInt;
    if (intPart.length <= 3) {
      formattedInt = intPart;
    } else {
      final last3 = intPart.substring(intPart.length - 3);
      final rest = intPart.substring(0, intPart.length - 3);
      final buf = StringBuffer();
      for (int i = 0; i < rest.length; i++) {
        if (i > 0 && (rest.length - i) % 2 == 0) buf.write(',');
        buf.write(rest[i]);
      }
      formattedInt = '$buf,$last3';
    }
    final dec = parts.length > 1 ? '.${parts[1]}' : '';
    return '${amount < 0 ? '-' : ''}₹$formattedInt$dec';
  }

  String _formatMonthLabel(String ym) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final parts = ym.split('-');
    if (parts.length == 2) {
      final m = int.tryParse(parts[1]) ?? 1;
      if (m >= 1 && m <= 12) return '${months[m - 1]} ${parts[0]}';
    }
    return ym;
  }

  void _shiftMonth(int delta) {
    final parts = _selectedMonth.split('-');
    final y = int.tryParse(parts[0]) ?? DateTime.now().year;
    final m = int.tryParse(parts[1]) ?? DateTime.now().month;
    final dt = DateTime(y, m + delta, 1);
    setState(() {
      _selectedMonth = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
    });
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _payrollService.getPayrollSummary(
          month: _selectedMonth,
          search: _searchCtrl.text.trim(),
          statusTab: _statusTab == 'previous_pending' ? 'all' : _statusTab,
        ),
        _payrollService.getPendingPayrolls(beforeMonth: _selectedMonth),
      ]);

      if (!mounted) return;
      final summaryRes = results[0];
      final pendingRes = results[1];

      setState(() {
        _summary = (summaryRes['summary'] as Map<String, dynamic>?) ?? {};
        _settings = (summaryRes['settings'] as Map<String, dynamic>?) ?? {};
        _items = ((summaryRes['items'] as List<dynamic>?) ?? []).whereType<Map<String, dynamic>>().toList();
        _pendingPrior = ((pendingRes['pending'] as List<dynamic>?) ?? []).whereType<Map<String, dynamic>>().toList();
        _totalPendingPrior = _toDouble(pendingRes['totalPending']);
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _finalizeWholeMonth() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Finalize & Close ${_formatMonthLabel(_selectedMonth)}?'),
        content: const Text(
          'This snapshots current attendance, leaves, deductions, overtime, and policy settings for all employees. Pending unpaid balances will remain attached to this month for later settlement.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: CeladonColors.primary, foregroundColor: Colors.white),
            child: const Text('Finalize Month'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final res = await _payrollService.finalizeMonth(month: _selectedMonth);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: CeladonColors.primary, content: Text(res['message']?.toString() ?? 'Month finalized')),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: CeladonColors.error, content: Text('$e')));
      }
    }
  }

  void _showPolicySheet() async {
    Map<String, dynamic> liveSettings = Map<String, dynamic>.from(_settings);
    try {
      liveSettings = await _payrollService.getPayrollSettings();
    } catch (_) {}
    if (!mounted) return;

    final hoursCtrl = TextEditingController(text: '${liveSettings['workingHoursPerDay'] ?? 8}');
    final daysCtrl = TextEditingController(text: '${liveSettings['workingDaysPerWeek'] ?? 5}');
    final divisorCtrl = TextEditingController(text: '${liveSettings['fixedPayrollDivisor'] ?? 200}');
    final lunchCtrl = TextEditingController(text: '${liveSettings['breakTime'] ?? 60}');
    final casualCtrl = TextEditingController(text: '${liveSettings['casualBreakTime'] ?? 15}');
    final graceCtrl = TextEditingController(text: '${liveSettings['graceMinutes'] ?? 0}');
    final lateRateCtrl = TextEditingController(text: '${liveSettings['lateDeductionRate'] ?? 0}');
    final otPctCtrl = TextEditingController(text: '${liveSettings['hourlyOvertimePct'] ?? 75}');
    final otMinCtrl = TextEditingController(text: '${liveSettings['overtimeMinMinutes'] ?? 0}');
    final shortfallPctCtrl = TextEditingController(text: '${liveSettings['hourlyDeductionPct'] ?? 50}');
    final breakIntervalCtrl = TextEditingController(text: '${liveSettings['breakDelayIntervalMinutes'] ?? 10}');
    final breakAmountCtrl = TextEditingController(text: '${liveSettings['breakDelayIntervalAmount'] ?? 1}');
    final approvedLeaveCtrl = TextEditingController(text: '${liveSettings['approvedLeaveDeductionPct'] ?? 25}');
    final unapprovedLeaveCtrl = TextEditingController(text: '${liveSettings['unapprovedLeaveDeductionPct'] ?? 100}');

    String divisorType = (liveSettings['payrollDivisorType'] ?? 'scheduled_hours').toString();
    String lateMode = (liveSettings['lateDeductionMode'] ?? 'per_minute').toString();
    String breakRuleType = (liveSettings['breakDelayRuleType'] ?? 'per_interval_flat').toString();
    bool lateEnabled = liveSettings['lateDeductionEnabled'] == true;
    bool shortfallEnabled = liveSettings['shortfallDeductionEnabled'] != false;
    bool otEnabled = liveSettings['overtimeEnabled'] != false;
    bool breakDelayEnabled = liveSettings['breakDelayDeductionEnabled'] != false;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheet) => SizedBox(
          height: MediaQuery.of(context).size.height * 0.90,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.tune_rounded, color: CeladonColors.primary),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Company Payroll Policy',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: CeladonColors.textPrimary),
                      ),
                    ),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                  ],
                ),
                const Text(
                  'Changes apply to future / open payroll cycles without altering finalized months.',
                  style: TextStyle(fontSize: 11.5, color: CeladonColors.textMuted),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _policySectionHeader('Work Schedule & Divisor'),
                        Row(
                          children: [
                            Expanded(child: _numField(hoursCtrl, 'Hours / Day')),
                            const SizedBox(width: 10),
                            Expanded(child: _numField(daysCtrl, 'Days / Week')),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _numField(lunchCtrl, 'Lunch Break (min)')),
                            const SizedBox(width: 10),
                            Expanded(child: _numField(casualCtrl, 'Casual Break (min)')),
                          ],
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: divisorType,
                          decoration: const InputDecoration(labelText: 'Monthly Payroll Divisor', border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: 'scheduled_hours', child: Text('Dynamic Scheduled Hours')),
                            DropdownMenuItem(value: 'fixed_hours', child: Text('Fixed Monthly Hours')),
                          ],
                          onChanged: (v) => setSheet(() => divisorType = v ?? 'scheduled_hours'),
                        ),
                        if (divisorType == 'fixed_hours') ...[
                          const SizedBox(height: 10),
                          _numField(divisorCtrl, 'Fixed Divisor Hours (e.g. 200)'),
                        ],
                        const SizedBox(height: 16),

                        _policySectionHeader('Late Arrival Deduction'),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Enable Late Deduction', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                          value: lateEnabled,
                          activeThumbColor: CeladonColors.primary,
                          onChanged: (v) => setSheet(() => lateEnabled = v),
                        ),
                        Row(
                          children: [
                            Expanded(child: _numField(graceCtrl, 'Grace Buffer (min)')),
                            const SizedBox(width: 10),
                            Expanded(child: _numField(lateRateCtrl, lateMode == 'hourly_rate' ? 'Rate (%)' : 'Rate (₹)')),
                          ],
                        ),
                        if (lateEnabled) ...[
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: lateMode,
                            decoration: const InputDecoration(labelText: 'Late Deduction Mode', border: OutlineInputBorder()),
                            items: const [
                              DropdownMenuItem(value: 'per_minute', child: Text('₹ per Late Minute')),
                              DropdownMenuItem(value: 'fixed_per_late', child: Text('Fixed ₹ per Late Day')),
                              DropdownMenuItem(value: 'hourly_rate', child: Text('% of Hourly Salary Rate')),
                            ],
                            onChanged: (v) => setSheet(() => lateMode = v ?? 'per_minute'),
                          ),
                        ],
                        const SizedBox(height: 16),

                        _policySectionHeader('Shortfall & Overtime'),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Deduct Insufficient Working Hours', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                          value: shortfallEnabled,
                          activeThumbColor: CeladonColors.primary,
                          onChanged: (v) => setSheet(() => shortfallEnabled = v),
                        ),
                        if (shortfallEnabled) _numField(shortfallPctCtrl, 'Hourly Deduction Rate (% of Hourly Salary)'),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Enable Overtime Earnings', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                          value: otEnabled,
                          activeThumbColor: CeladonColors.primary,
                          onChanged: (v) => setSheet(() => otEnabled = v),
                        ),
                        if (otEnabled)
                          Row(
                            children: [
                              Expanded(child: _numField(otPctCtrl, 'OT Rate (% of Hourly)')),
                              const SizedBox(width: 10),
                              Expanded(child: _numField(otMinCtrl, 'Min OT Threshold (min)')),
                            ],
                          ),
                        const SizedBox(height: 16),

                        _policySectionHeader('Lunch & Casual Break Delay Rule'),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Enable Break Delay Deduction', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                          value: breakDelayEnabled,
                          activeThumbColor: CeladonColors.primary,
                          onChanged: (v) => setSheet(() => breakDelayEnabled = v),
                        ),
                        if (breakDelayEnabled) ...[
                          DropdownButtonFormField<String>(
                            initialValue: breakRuleType,
                            decoration: const InputDecoration(labelText: 'Break Delay Calculation', border: OutlineInputBorder()),
                            items: const [
                              DropdownMenuItem(value: 'per_interval_flat', child: Text('Fixed ₹ per Excess Interval (e.g. ₹1 / 10m)')),
                              DropdownMenuItem(value: 'salary_minute_rate', child: Text('Salary Hourly % per Minute')),
                            ],
                            onChanged: (v) => setSheet(() => breakRuleType = v ?? 'per_interval_flat'),
                          ),
                          if (breakRuleType == 'per_interval_flat') ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(child: _numField(breakIntervalCtrl, 'Excess Interval (min)')),
                                const SizedBox(width: 10),
                                Expanded(child: _numField(breakAmountCtrl, 'Deduct Amount (₹)')),
                              ],
                            ),
                          ],
                        ],
                        const SizedBox(height: 16),

                        _policySectionHeader('Fallback Leave Deduction Rates (%)'),
                        Row(
                          children: [
                            Expanded(child: _numField(approvedLeaveCtrl, 'Approved Unpaid (%)')),
                            const SizedBox(width: 10),
                            Expanded(child: _numField(unapprovedLeaveCtrl, 'Unapproved Leave (%)')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          setSheet(() => isSaving = true);
                          try {
                            final messenger = ScaffoldMessenger.of(this.context);
                            final nav = Navigator.of(ctx);
                            await _payrollService.updatePayrollSettings({
                              'workingHoursPerDay': int.tryParse(hoursCtrl.text.trim()) ?? 8,
                              'workingDaysPerWeek': int.tryParse(daysCtrl.text.trim()) ?? 5,
                              'breakTime': int.tryParse(lunchCtrl.text.trim()) ?? 60,
                              'casualBreakTime': int.tryParse(casualCtrl.text.trim()) ?? 15,
                              'graceMinutes': int.tryParse(graceCtrl.text.trim()) ?? 0,
                              'payrollDivisorType': divisorType,
                              'fixedPayrollDivisor': double.tryParse(divisorCtrl.text.trim()) ?? 200,
                              'lateDeductionEnabled': lateEnabled,
                              'lateDeductionMode': lateMode,
                              'lateDeductionRate': double.tryParse(lateRateCtrl.text.trim()) ?? 0,
                              'shortfallDeductionEnabled': shortfallEnabled,
                              'hourlyDeductionPct': double.tryParse(shortfallPctCtrl.text.trim()) ?? 50,
                              'overtimeEnabled': otEnabled,
                              'hourlyOvertimePct': double.tryParse(otPctCtrl.text.trim()) ?? 75,
                              'overtimeMinMinutes': int.tryParse(otMinCtrl.text.trim()) ?? 0,
                              'breakDelayDeductionEnabled': breakDelayEnabled,
                              'breakDelayRuleType': breakRuleType,
                              'breakDelayIntervalMinutes': int.tryParse(breakIntervalCtrl.text.trim()) ?? 10,
                              'breakDelayIntervalAmount': double.tryParse(breakAmountCtrl.text.trim()) ?? 1,
                              'approvedLeaveDeductionPct': double.tryParse(approvedLeaveCtrl.text.trim()) ?? 25,
                              'unapprovedLeaveDeductionPct': double.tryParse(unapprovedLeaveCtrl.text.trim()) ?? 100,
                            });
                            if (nav.mounted) nav.pop();
                            if (mounted) {
                              messenger.showSnackBar(
                                const SnackBar(backgroundColor: CeladonColors.primary, content: Text('Payroll Policy saved successfully!')),
                              );
                              _loadData();
                            }
                          } catch (e) {
                            if (ctx.mounted) setSheet(() => isSaving = false);
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(backgroundColor: CeladonColors.error, content: Text('$e')));
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CeladonColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(isSaving ? 'Saving...' : 'Save Payroll Policy', style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAdjustmentDialog(Map<String, dynamic> emp) {
    final userId = (emp['userId'] ?? '').toString();
    final name = (emp['name'] ?? userId).toString();
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    String type = 'bonus';
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          title: Text('Adjustment for $name (${_formatMonthLabel(_selectedMonth)})'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'bonus', label: Text('Bonus (+₹)')),
                  ButtonSegment(value: 'deduction', label: Text('Deduction (-₹)')),
                ],
                selected: {type},
                onSelectionChanged: (s) => setDState(() => type = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount (₹)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(labelText: 'Reason / Note', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      final amt = double.tryParse(amountCtrl.text.trim()) ?? 0;
                      if (amt <= 0) return;
                      setDState(() => saving = true);
                      try {
                        final messenger = ScaffoldMessenger.of(this.context);
                        final nav = Navigator.of(ctx);
                        await _payrollService.addAdjustment(
                          userId: userId,
                          month: _selectedMonth,
                          type: type,
                          amount: amt,
                          reason: reasonCtrl.text.trim(),
                        );
                        if (nav.mounted) nav.pop();
                        if (mounted) {
                          messenger.showSnackBar(
                            SnackBar(backgroundColor: CeladonColors.primary, content: Text('${type == 'bonus' ? 'Bonus' : 'Deduction'} added for $name')),
                          );
                          _loadData();
                        }
                      } catch (e) {
                        if (ctx.mounted) setDState(() => saving = false);
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(backgroundColor: CeladonColors.error, content: Text('$e')));
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: CeladonColors.primary, foregroundColor: Colors.white),
              child: Text(saving ? 'Saving...' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPayDialog(Map<String, dynamic> emp, {String? overrideMonth}) async {
    final userId = (emp['userId'] ?? '').toString();
    final name = (emp['name'] ?? userId).toString();
    final targetMonth = overrideMonth ?? _selectedMonth;
    final remainingCurrent = _toDouble(emp['pendingAmount'] ?? emp['totalAmount']);

    // Load pending prior months for optional multi-month settlement
    List<Map<String, dynamic>> priorMonths = [];
    try {
      final res = await _payrollService.getPendingPayrolls(userId: userId);
      priorMonths = ((res['pending'] as List<dynamic>?) ?? []).whereType<Map<String, dynamic>>().toList();
    } catch (_) {}
    if (!mounted) return;

    final amountCtrl = TextEditingController(
      text: remainingCurrent > 0 ? remainingCurrent.toStringAsFixed(2).replaceAll(RegExp(r'\.00$'), '') : '',
    );
    final refCtrl = TextEditingController(text: 'PAY-${DateTime.now().millisecondsSinceEpoch}');
    final notesCtrl = TextEditingController();
    String method = 'bank_transfer';
    String payoutType = 'salary';
    bool includeMultipleMonths = false;
    final selectedMonths = <String, bool>{};
    for (final pm in priorMonths) {
      final m = (pm['month'] ?? '').toString();
      if (m.isNotEmpty) selectedMonths[m] = m == targetMonth;
    }
    bool paying = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          title: Text('Pay Salary — $name'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Month: ${_formatMonthLabel(targetMonth)} • Remaining: ${_formatInr(remainingCurrent)}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: CeladonColors.primary),
                ),
                if (priorMonths.length > 1) ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text('Pay multiple pending months together (${priorMonths.length})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    value: includeMultipleMonths,
                    onChanged: (v) => setDState(() => includeMultipleMonths = v == true),
                  ),
                ],
                if (includeMultipleMonths)
                  ...priorMonths.map((pm) {
                    final m = (pm['month'] ?? '').toString();
                    final pend = _toDouble(pm['pendingAmount']);
                    return CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text('${_formatMonthLabel(m)} (${_formatInr(pend)})', style: const TextStyle(fontSize: 12)),
                      value: selectedMonths[m] == true,
                      onChanged: (v) => setDState(() => selectedMonths[m] = v == true),
                    );
                  })
                else ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Amount to Pay Now (Partial or Full ₹)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: method,
                  decoration: const InputDecoration(labelText: 'Payment Method (Internal)', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'bank_transfer', child: Text('Bank Transfer')),
                    DropdownMenuItem(value: 'upi', child: Text('UPI')),
                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                  ],
                  onChanged: (v) => setDState(() => method = v ?? 'bank_transfer'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: payoutType,
                  decoration: const InputDecoration(labelText: 'Payout Type', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'salary', child: Text('Salary')),
                    DropdownMenuItem(value: 'bonus', child: Text('Bonus')),
                  ],
                  onChanged: (v) => setDState(() => payoutType = v ?? 'salary'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: refCtrl,
                  decoration: const InputDecoration(labelText: 'Reference ID', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(labelText: 'Notes (optional)', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: paying
                  ? null
                  : () async {
                      final ref = refCtrl.text.trim();
                      if (ref.isEmpty) return;
                      setDState(() => paying = true);
                      try {
                        final messenger = ScaffoldMessenger.of(this.context);
                        final nav = Navigator.of(ctx);
                        Map<String, dynamic> res;
                        if (includeMultipleMonths) {
                          final items = priorMonths
                              .where((pm) => selectedMonths[(pm['month'] ?? '').toString()] == true)
                              .map((pm) => {
                                    'month': pm['month'],
                                    'amount': _toDouble(pm['pendingAmount']),
                                    'payoutType': payoutType,
                                  })
                              .toList();
                          res = await _payrollService.processBulkPayment(
                            userId: userId,
                            items: items,
                            paymentMethod: method,
                            referenceId: ref,
                            notes: notesCtrl.text.trim(),
                          );
                        } else {
                          final amt = double.tryParse(amountCtrl.text.trim());
                          res = await _payrollService.processPayment(
                            userId: userId,
                            month: targetMonth,
                            amount: amt,
                            paymentMethod: method,
                            referenceId: ref,
                            payoutType: payoutType,
                            notes: notesCtrl.text.trim(),
                          );
                        }
                        if (nav.mounted) nav.pop();
                        if (mounted) {
                          messenger.showSnackBar(
                            SnackBar(backgroundColor: CeladonColors.primary, content: Text(res['message']?.toString() ?? 'Payment processed')),
                          );
                          _loadData();
                        }
                      } catch (e) {
                        if (ctx.mounted) setDState(() => paying = false);
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(backgroundColor: CeladonColors.error, content: Text('$e')));
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: CeladonColors.primary, foregroundColor: Colors.white),
              child: Text(paying ? 'Processing...' : 'Confirm Payment'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEmployeeBreakdownModal(Map<String, dynamic> emp) async {
    final userId = (emp['userId'] ?? '').toString();
    final name = (emp['name'] ?? userId).toString();
    Map<String, dynamic>? preview;
    try {
      preview = await _payrollService.getEmployeePayrollPreview(userId: userId, month: _selectedMonth);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: CeladonColors.error, content: Text('$e')));
      }
      return;
    }
    if (!mounted) return;

    final daily = ((preview['dailyBreakdown'] as List<dynamic>?) ?? []).whereType<Map<String, dynamic>>().toList();
    final txs = ((preview['transactions'] as List<dynamic>?) ?? []).whereType<Map<String, dynamic>>().toList();
    final adjs = ((preview['adjustments'] as List<dynamic>?) ?? []).whereType<Map<String, dynamic>>().toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.88,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                        Text(
                          '${_formatMonthLabel(_selectedMonth)} • Net: ${_formatInr(_toDouble(preview!['netPayable']))} • Paid: ${_formatInr(_toDouble(preview['amountPaid']))} • Pending: ${_formatInr(_toDouble(preview['pendingAmount']))}',
                          style: const TextStyle(fontSize: 11.5, color: CeladonColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.download_rounded, color: CeladonColors.primary),
                    tooltip: 'Download PDF Payslip',
                    onPressed: () async {
                      try {
                        final file = await _payrollService.downloadPayslipPdf(userId: userId, month: _selectedMonth);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(backgroundColor: CeladonColors.primary, content: Text('Payslip saved: ${file.path}')),
                          );
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(backgroundColor: CeladonColors.error, content: Text('$e')));
                        }
                      }
                    },
                  ),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                ],
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  children: [
                    _kvRow('Base Salary', _formatInr(_toDouble(preview['baseSalary']))),
                    _kvRow('Overtime Additions', '+${_formatInr(_toDouble(preview['hourlyOvertimeAddition']))}'),
                    _kvRow('Bonuses', '+${_formatInr(_toDouble(preview['bonus']))}'),
                    _kvRow('Shortfall Deductions', '-${_formatInr(_toDouble(preview['hourlyShortfallDeduction']))}'),
                    _kvRow('Late Deductions', '-${_formatInr(_toDouble(preview['lateDeduction']))}'),
                    _kvRow('Break Delay Deductions', '-${_formatInr(_toDouble(preview['totalBreakDeduction']))}'),
                    _kvRow('Approved Leave Deductions', '-${_formatInr(_toDouble(preview['approvedLeaveDeduction']))}'),
                    _kvRow('Unapproved Leave Deductions', '-${_formatInr(_toDouble(preview['unapprovedLeaveDeduction']))}'),
                    _kvRow('Manual Deductions', '-${_formatInr(_toDouble(preview['manualDeduction']))}'),
                    const Divider(),
                    if (adjs.isNotEmpty) ...[
                      const Text('Adjustments', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                      const SizedBox(height: 6),
                      ...adjs.map((a) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text('${a['type'] == 'bonus' ? '+' : '-'}${_formatInr(_toDouble(a['amount']))} • ${a['reason'] ?? ''}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                          )),
                      const Divider(),
                    ],
                    if (txs.isNotEmpty) ...[
                      const Text('Transactions', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                      const SizedBox(height: 6),
                      ...txs.map((t) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text('${_formatInr(_toDouble(t['amount']))} (${t['paymentMethod'] ?? 'bank'})', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                            subtitle: Text('Ref: ${t['referenceId'] ?? '-'} • ${(t['paidAt'] ?? '').toString().split('T').first}', style: const TextStyle(fontSize: 11)),
                          )),
                      const Divider(),
                    ],
                    const Text('Daily Attendance & Salary Explanations', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                    const SizedBox(height: 6),
                    ...daily.where((d) => d['isFuture'] != true).map((d) => Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Text(
                            (d['explanation'] ?? '${d['date']} — ${d['notes'] ?? ''}').toString(),
                            style: const TextStyle(fontSize: 12, color: CeladonColors.textPrimary),
                          ),
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _policySectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: CeladonColors.primary)),
      );

  Widget _numField(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
      );

  Widget _kvRow(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(fontSize: 12.5, color: CeladonColors.textSecondary)),
            Text(v, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: CeladonColors.textPrimary)),
          ],
        ),
      );

  Widget _buildContent() {
    return RefreshIndicator(
      color: CeladonColors.primary,
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
        children: [
          ReGenPageHeader(
            title: 'Company Payroll',
            subtitle: 'Dynamic salary calculations, pending balances & payouts.',
            onBack: widget.onBack,
            backTooltip: 'Back to Home',
            trailing: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: _showPolicySheet,
              tooltip: 'Payroll Policy Settings',
              icon: const Icon(Icons.tune_rounded, color: CeladonColors.primary, size: 22),
            ),
          ),
          const SizedBox(height: 12),

          // Month Switcher + Finalize Month (Wrap prevents horizontal overflow)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () => _shiftMonth(-1),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Text(_formatMonthLabel(_selectedMonth), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () => _shiftMonth(1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _finalizeWholeMonth,
                icon: const Icon(Icons.lock_clock_rounded, size: 15),
                label: const Text('Finalize Month', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: CeladonColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Responsive 2-column Summary KPI Grid
          LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth = (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _kpiTile('Net Payable', _formatInr(_toDouble(_summary['totalNetPayable'])), CeladonColors.primary, width: tileWidth),
                  _kpiTile('Total Deductions', '-${_formatInr(_toDouble(_summary['totalDeductions']))}', CeladonColors.error, width: tileWidth),
                  _kpiTile('Paid', _formatInr(_toDouble(_summary['totalAmountSent'])), const Color(0xFF15803D), width: tileWidth),
                  _kpiTile('Remaining', _formatInr(_toDouble(_summary['totalAmountToPay'])), const Color(0xFFD97706), width: tileWidth),
                  if (_totalPendingPrior > 0)
                    _kpiTile('Prev. Pending', _formatInr(_totalPendingPrior), const Color(0xFFDC2626), width: tileWidth),
                ],
              );
            },
          ),
          const SizedBox(height: 12),

          // Search + Status Filter Chips
          TextField(
            controller: _searchCtrl,
            onSubmitted: (_) => _loadData(),
            decoration: InputDecoration(
              hintText: 'Search employee name or ID...',
              prefixIcon: const Icon(Icons.search_rounded, size: 19),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear_rounded, size: 18), onPressed: () { _searchCtrl.clear(); _loadData(); })
                  : null,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('All (${_items.length})', 'all'),
                const SizedBox(width: 8),
                _filterChip('Pending', 'pending'),
                const SizedBox(width: 8),
                _filterChip('Processed', 'processed'),
                const SizedBox(width: 8),
                _filterChip('Prior Months Due (${_pendingPrior.length})', 'previous_pending'),
              ],
            ),
          ),
          const SizedBox(height: 14),

          if (_isLoading)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(color: CeladonColors.primary)))
          else if (_error != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(14)),
              child: Text(_error!, style: const TextStyle(color: CeladonColors.error)),
            )
          else if (_statusTab == 'previous_pending') ...[
            if (_pendingPrior.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('No pending balances from previous months.', style: TextStyle(color: CeladonColors.textMuted))),
              )
            else
              ..._pendingPrior.map((p) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${p['employeeName'] ?? p['userId']} • ${_formatMonthLabel((p['month'] ?? '').toString())}',
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                              Text(
                                'Net: ${_formatInr(_toDouble(p['netPayable']))} | Paid: ${_formatInr(_toDouble(p['amountPaid']))} | Pending: ${_formatInr(_toDouble(p['pendingAmount']))}',
                                style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626), fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: () => _showPayDialog(
                            {'userId': p['userId'], 'name': p['employeeName'] ?? p['userId'], 'pendingAmount': p['pendingAmount']},
                            overrideMonth: (p['month'] ?? '').toString(),
                          ),
                          style: ElevatedButton.styleFrom(backgroundColor: CeladonColors.primary, foregroundColor: Colors.white),
                          child: const Text('Settle'),
                        ),
                      ],
                    ),
                  )),
          ] else if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No employees found for this filter.', style: TextStyle(color: CeladonColors.textMuted))),
            )
          else
            ..._items.map((emp) => _buildEmployeePayrollCard(emp)),
        ],
      ),
    );
  }

  Widget _buildEmployeePayrollCard(Map<String, dynamic> emp) {
    final name = (emp['name'] ?? emp['userId'] ?? 'Employee').toString();
    final base = _toDouble(emp['baseSalary']);
    final ded = _toDouble(emp['totalDeductions']);
    final lateDed = _toDouble(emp['lateDeduction']);
    final leaveDed = _toDouble(emp['approvedLeaveDeduction']) + _toDouble(emp['unapprovedLeaveDeduction']);
    final shortfallDed = _toDouble(emp['hourlyShortfallDeduction']);
    final breakDed = _toDouble(emp['totalBreakDeduction']);
    final bonus = _toDouble(emp['bonus']);
    final otPay = _toDouble(emp['hourlyOvertimeAddition']);
    final manualDed = _toDouble(emp['manualDeduction']);
    final netPay = _toDouble(emp['totalAmount'] ?? emp['netPayable']);
    final paid = _toDouble(emp['amountPaid']);
    final pending = _toDouble(emp['pendingAmount'] ?? emp['totalAmount']);
    final prevPending = _toDouble(emp['previousPendingTotal']);
    final payStatus = (emp['paymentStatus'] ?? 'unpaid').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: CeladonColors.textPrimary),
                    ),
                    Text(
                      '${emp['department'] ?? 'General'} • ${emp['StaffId'] ?? emp['userId'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: CeladonColors.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: payStatus == 'paid' ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  payStatus.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: payStatus == 'paid' ? const Color(0xFF15803D) : const Color(0xFFB45309),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _metricTag('Base', _formatInr(base), CeladonColors.textPrimary),
              _metricTag('Net', _formatInr(netPay), CeladonColors.primaryDark),
              _metricTag('Deductions', '-${_formatInr(ded)}', ded > 0 ? CeladonColors.error : CeladonColors.textMuted),
              if (otPay > 0) _metricTag('OT', '+${_formatInr(otPay)}', const Color(0xFF15803D)),
              if (bonus > 0) _metricTag('Bonus', '+${_formatInr(bonus)}', const Color(0xFF15803D)),
              _metricTag('Paid', _formatInr(paid), const Color(0xFF15803D)),
              _metricTag('Remaining', _formatInr(pending), pending > 0 ? const Color(0xFFB45309) : const Color(0xFF15803D)),
            ],
          ),
          if (leaveDed > 0 || lateDed > 0 || shortfallDed > 0 || breakDed > 0 || manualDed > 0) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (leaveDed > 0) _deductionChip('Leave -${_formatInr(leaveDed)}'),
                if (lateDed > 0) _deductionChip('Late -${_formatInr(lateDed)}'),
                if (shortfallDed > 0) _deductionChip('Shortfall -${_formatInr(shortfallDed)}'),
                if (breakDed > 0) _deductionChip('Break -${_formatInr(breakDed)}'),
                if (manualDed > 0) _deductionChip('Manual -${_formatInr(manualDed)}'),
              ],
            ),
          ],
          if (prevPending > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Previous months pending: ${_formatInr(prevPending)}',
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFDC2626)),
              ),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _showEmployeeBreakdownModal(emp),
                      icon: const Icon(Icons.receipt_long_rounded, size: 15),
                      label: const Text('Breakdown', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _showAdjustmentDialog(emp),
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 15),
                      label: const Text('Bonus/Ded', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: (pending > 0 || prevPending > 0) ? () => _showPayDialog(emp) : null,
                  icon: const Icon(Icons.payments_rounded, size: 15),
                  label: Text(pending > 0 ? 'Pay' : 'Paid', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CeladonColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricTag(String label, String val, Color color) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: CeladonColors.textMuted, fontWeight: FontWeight.w600)),
          Text(val, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color)),
        ],
      );

  Widget _deductionChip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: CeladonColors.error)),
      );

  Widget _kpiTile(String label, String value, Color accent, {double width = 155}) => Container(
        width: width,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: CeladonColors.textMuted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: accent)),
          ],
        ),
      );

  Widget _filterChip(String label, String tabKey) {
    final active = _statusTab == tabKey;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: active ? Colors.white : CeladonColors.textPrimary)),
      selected: active,
      selectedColor: CeladonColors.primary,
      backgroundColor: Colors.white,
      onSelected: (_) {
        setState(() => _statusTab = tabKey);
        _loadData();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Container(color: CeladonColors.background, child: SafeArea(top: false, bottom: false, child: _buildContent()));
    }
    return Scaffold(backgroundColor: CeladonColors.background, body: SafeArea(child: _buildContent()));
  }
}
