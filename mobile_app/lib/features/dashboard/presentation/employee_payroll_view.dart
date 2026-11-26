import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../../core/widgets/regen_page_header.dart';
import '../../auth/data/user_model.dart';
import '../data/dashboard_service.dart';
import '../data/payroll_service.dart';

/// Employee Personal Payroll & Payment Page (100% Dynamic MongoDB Data)
///
/// Displays:
/// - Monthly original salary, earned salary, amount paid & remaining payable
/// - Pending salaries from previous months
/// - Downloadable monthly PDF payslip
/// - Daily attendance, leave, overtime, late, break-delay & manual adjustment explanations
/// - Monthly payment transactions & multi-year history
class EmployeePayrollView extends StatefulWidget {
  final UserModel user;
  final VoidCallback? onBack;
  final bool embedded;
  final DashboardService? dashboardService;

  const EmployeePayrollView({
    super.key,
    required this.user,
    this.onBack,
    this.embedded = true,
    this.dashboardService,
  });

  @override
  State<EmployeePayrollView> createState() => _EmployeePayrollViewState();
}

class _EmployeePayrollViewState extends State<EmployeePayrollView> {
  late DashboardService _dashboardService;
  final PayrollService _payrollService = PayrollService();
  bool _isLoading = true;
  bool _isDownloadingPdf = false;
  late int _selectedYear;
  late String _selectedMonth; // YYYY-MM

  Map<String, dynamic>? _currentPayroll;
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _adjustments = [];
  List<Map<String, dynamic>> _pendingMonths = [];
  double _totalPendingBalance = 0.0;
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _dashboardService = widget.dashboardService ?? DashboardService();
    final now = DateTime.now();
    _selectedYear = now.year;
    _selectedMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    _loadPayroll();
  }

  @override
  void didUpdateWidget(covariant EmployeePayrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldUid = oldWidget.user.userId.isNotEmpty ? oldWidget.user.userId : oldWidget.user.id;
    final newUid = widget.user.userId.isNotEmpty ? widget.user.userId : widget.user.id;
    if (oldUid != newUid || oldWidget.user.role != widget.user.role || oldWidget.user.token != widget.user.token) {
      _dashboardService = widget.dashboardService ?? DashboardService();
      _loadPayroll();
    }
  }

  int get _joiningYear {
    final raw = widget.user.joiningDate ?? widget.user.createdAt ?? '';
    final match = RegExp(r'(\d{4})').firstMatch(raw);
    final parsed = match != null ? int.tryParse(match.group(1)!) : null;
    final nowYear = DateTime.now().year;
    if (parsed != null && parsed >= 2000 && parsed <= nowYear) return parsed;
    return nowYear;
  }

  List<int> get _availableYears {
    final nowYear = DateTime.now().year;
    final start = _joiningYear;
    final years = <int>[];
    for (int y = nowYear; y >= start; y--) {
      years.add(y);
    }
    return years.isEmpty ? [nowYear] : years;
  }

  Future<void> _loadPayroll({String? month}) async {
    final targetMonth = month ?? _selectedMonth;
    setState(() => _isLoading = true);
    try {
      final data = await _dashboardService.getMyPayrollRecords(month: targetMonth);
      if (!mounted) return;
      final payroll = data['payroll'] is Map<String, dynamic>
          ? data['payroll'] as Map<String, dynamic>
          : null;
      final rawHistory = data['history'] as List<dynamic>? ?? const [];
      final rawTxs = data['transactions'] as List<dynamic>? ?? const [];
      final singleTx = data['transaction'];
      final txs = rawTxs.whereType<Map<String, dynamic>>().toList();
      if (txs.isEmpty && singleTx is Map<String, dynamic>) txs.add(singleTx);
      final rawAdjs = data['adjustments'] as List<dynamic>? ?? const [];
      final rawPending = data['pendingMonths'] as List<dynamic>? ?? const [];

      setState(() {
        _selectedMonth = targetMonth;
        _currentPayroll = payroll;
        _transactions = txs;
        _adjustments = rawAdjs.whereType<Map<String, dynamic>>().toList();
        _pendingMonths = rawPending.whereType<Map<String, dynamic>>().toList();
        _totalPendingBalance = _toDouble(data['totalPendingBalance'] ?? payroll?['pendingAmount']);
        _history = rawHistory.whereType<Map<String, dynamic>>().toList();
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadPayslip() async {
    setState(() => _isDownloadingPdf = true);
    try {
      final file = await _payrollService.downloadPayslipPdf(
        payrollId: _currentPayroll?['_id']?.toString(),
        userId: widget.user.userId.isNotEmpty ? widget.user.userId : widget.user.id,
        month: _selectedMonth,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: CeladonColors.primary,
            content: Text('Payslip PDF downloaded to ${file.path}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: CeladonColors.error, content: Text('Failed to download payslip: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloadingPdf = false);
    }
  }

  double _toDouble(dynamic val) {
    if (val is num) return val.toDouble();
    return double.tryParse(val?.toString() ?? '') ?? 0.0;
  }

  List<Map<String, dynamic>> get _yearHistory {
    final prefix = '$_selectedYear-';
    return _history.where((h) => (h['month'] ?? '').toString().startsWith(prefix)).toList();
  }

  double get _earnedInSelectedYear {
    double total = 0;
    final seenMonths = <String>{};
    for (final h in _yearHistory) {
      final m = (h['month'] ?? '').toString();
      seenMonths.add(m);
      final paid = _toDouble(h['amountPaid']);
      final net = _toDouble(h['totalAmount'] ?? h['netPayable']);
      total += paid > 0 ? paid : net;
    }
    if (_currentPayroll != null) {
      final cm = (_currentPayroll!['month'] ?? _selectedMonth).toString();
      if (cm.startsWith('$_selectedYear-') && !seenMonths.contains(cm)) {
        final net = _toDouble(_currentPayroll!['totalAmount'] ?? _currentPayroll!['netPayable']);
        if (net > 0) total += net;
      }
    }
    return total;
  }

  String _formatInr(double amount) {
    final rounded = amount.round();
    final s = rounded.abs().toString();
    if (s.length <= 3) return '${rounded < 0 ? '-' : ''}₹$s';
    final last3 = s.substring(s.length - 3);
    final rest = s.substring(0, s.length - 3);
    final buf = StringBuffer();
    for (int i = 0; i < rest.length; i++) {
      if (i > 0 && (rest.length - i) % 2 == 0) buf.write(',');
      buf.write(rest[i]);
    }
    return '${rounded < 0 ? '-' : ''}₹$buf,$last3';
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

  void _showYearPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Select Payroll Year',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: CeladonColors.textPrimary),
              ),
              const SizedBox(height: 12),
              ..._availableYears.map((y) {
                final selected = y == _selectedYear;
                return ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: selected ? CeladonColors.softMint : null,
                  title: Text(
                    '$y',
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected ? CeladonColors.primary : CeladonColors.textPrimary,
                    ),
                  ),
                  trailing: selected ? const Icon(Icons.check_circle_rounded, color: CeladonColors.primary) : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    final now = DateTime.now();
                    final targetMonth = y == now.year ? '$y-${now.month.toString().padLeft(2, '0')}' : '$y-12';
                    setState(() => _selectedYear = y);
                    _loadPayroll(month: targetMonth);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: CeladonColors.primary));
    }

    final p = _currentPayroll;
    final netPayable = _toDouble(p?['totalAmount'] ?? p?['netPayable']);
    final baseSalary = _toDouble(p?['baseSalary'] ?? p?['monthlySalary']);
    final earnedSalary = _toDouble(p?['earnedSalary'] ?? netPayable);
    final otAddition = _toDouble(p?['hourlyOvertimeAddition']);
    final bonusTotal = _toDouble(p?['bonus'] ?? p?['bonusTotal'] ?? p?['totalBonus']);
    final shortfallDed = _toDouble(p?['hourlyShortfallDeduction']);
    final lateDed = _toDouble(p?['lateDeduction']);
    final breakDed = _toDouble(p?['totalBreakDeduction']);
    final leaveDed = _toDouble(p?['approvedLeaveDeduction']) + _toDouble(p?['unapprovedLeaveDeduction']);
    final manualDed = _toDouble(p?['manualDeduction']);
    final deductionTotal = _toDouble(p?['totalDeductions'] ?? p?['deductionTotal'] ?? p?['totalDeduction']);
    final amountPaid = _toDouble(p?['amountPaid']);
    final remainingPayable = p != null && p['pendingAmount'] != null
        ? _toDouble(p['pendingAmount'])
        : (netPayable - amountPaid).clamp(0.0, double.infinity);
    final payStatus = (p?['paymentStatus'] ?? p?['status'] ?? 'draft').toString();
    final dailyBreakdown = ((p?['dailyBreakdown'] as List<dynamic>?) ?? [])
        .whereType<Map<String, dynamic>>()
        .where((d) => d['isFuture'] != true)
        .toList();

    return RefreshIndicator(
      color: CeladonColors.primary,
      onRefresh: () => _loadPayroll(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ReGenPageHeader(
              title: 'Payroll',
              subtitle: 'View monthly salary slips, daily deductions, pending pay & payments.',
              onBack: () {
                if (widget.onBack != null) {
                  widget.onBack!();
                } else if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
              trailing: GestureDetector(
                onTap: _showYearPicker,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 13, color: CeladonColors.primary),
                      const SizedBox(width: 5),
                      Text('$_selectedYear', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: CeladonColors.textPrimary)),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Color(0xFF64748B)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Month Selector Chips
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 12,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, idx) {
                  final m = '$_selectedYear-${(idx + 1).toString().padLeft(2, '0')}';
                  final active = m == _selectedMonth;
                  return ChoiceChip(
                    label: Text(_formatMonthLabel(m).split(' ').first,
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: active ? Colors.white : CeladonColors.textPrimary)),
                    selected: active,
                    selectedColor: CeladonColors.primary,
                    backgroundColor: Colors.white,
                    onSelected: (_) => _loadPayroll(month: m),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),

            // Pending Previous Months Alert Banner
            if (_pendingMonths.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.pending_actions_rounded, color: Color(0xFFDC2626), size: 19),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Pending Salaries (${_pendingMonths.length} prior month${_pendingMonths.length > 1 ? 's' : ''})',
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF991B1B)),
                          ),
                        ),
                        Text(_formatInr(_totalPendingBalance), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFFDC2626))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _pendingMonths.map((pm) {
                        final m = (pm['month'] ?? '').toString();
                        final pend = _toDouble(pm['pendingAmount']);
                        return ActionChip(
                          label: Text('${_formatMonthLabel(m)}: ${_formatInr(pend)}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                          backgroundColor: Colors.white,
                          onPressed: () => _loadPayroll(month: m),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

            // Hero Summary Card: Earned & Remaining Payable
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(color: const Color(0xFFFEF4E4), borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFFD9822B), size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Remaining Payable (${_formatMonthLabel(_selectedMonth)})',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
                            const SizedBox(height: 2),
                            Text(_formatInr(remainingPayable),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: CeladonColors.textPrimary)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('Earned Payment ($_selectedYear)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10.5, color: CeladonColors.textMuted)),
                            Text(_formatInr(_earnedInSelectedYear),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: CeladonColors.primary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _miniStat('Original Salary', _formatInr(baseSalary))),
                      const SizedBox(width: 8),
                      Expanded(child: _miniStat('Salary Earned', _formatInr(earnedSalary))),
                      const SizedBox(width: 8),
                      Expanded(child: _miniStat('Paid So Far', _formatInr(amountPaid), valueColor: const Color(0xFF15803D))),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Selected Month Payslip Breakdown + PDF Download
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Payslip • ${_formatMonthLabel(_selectedMonth)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: CeladonColors.textPrimary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: payStatus == 'paid' ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          payStatus.replaceAll('_', ' ').toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: payStatus == 'paid' ? const Color(0xFF15803D) : const Color(0xFFB45309),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton.icon(
                        onPressed: _isDownloadingPdf ? null : _downloadPayslip,
                        icon: Icon(_isDownloadingPdf ? Icons.hourglass_top_rounded : Icons.download_rounded, size: 15),
                        label: Text(_isDownloadingPdf ? '...' : 'PDF', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _payslipRow('Monthly Original Salary', _formatInr(baseSalary)),
                  _payslipRow('Overtime Earnings', '+${_formatInr(otAddition)}', valueColor: otAddition > 0 ? const Color(0xFF15803D) : CeladonColors.textMuted),
                  _payslipRow('Bonuses', '+${_formatInr(bonusTotal)}', valueColor: bonusTotal > 0 ? const Color(0xFF15803D) : CeladonColors.textMuted),
                  _payslipRow('Late Arrival Deductions', '-${_formatInr(lateDed)}', valueColor: lateDed > 0 ? CeladonColors.error : CeladonColors.textMuted),
                  _payslipRow('Break Delay Deductions', '-${_formatInr(breakDed)}', valueColor: breakDed > 0 ? CeladonColors.error : CeladonColors.textMuted),
                  _payslipRow('Shortfall Deductions', '-${_formatInr(shortfallDed)}', valueColor: shortfallDed > 0 ? CeladonColors.error : CeladonColors.textMuted),
                  _payslipRow('Leave Deductions', '-${_formatInr(leaveDed)}', valueColor: leaveDed > 0 ? CeladonColors.error : CeladonColors.textMuted),
                  if (manualDed > 0) _payslipRow('Manual Deductions', '-${_formatInr(manualDed)}', valueColor: CeladonColors.error),
                  _payslipRow('Total Deductions', '-${_formatInr(deductionTotal)}', valueColor: deductionTotal > 0 ? CeladonColors.error : CeladonColors.textMuted, bold: deductionTotal > 0),
                  const Divider(height: 20, color: Color(0xFFE2E8F0)),
                  _payslipRow('Net Payable', _formatInr(netPayable), bold: true),
                  _payslipRow('Amount Paid', _formatInr(amountPaid), valueColor: const Color(0xFF15803D)),
                  _payslipRow('Remaining Payable', _formatInr(remainingPayable), bold: true, valueColor: remainingPayable > 0 ? const Color(0xFFB45309) : const Color(0xFF15803D)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Bonuses & Manual Deductions
            if (_adjustments.isNotEmpty) ...[
              const Text('Bonuses & Manual Deductions', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: CeladonColors.textPrimary)),
              const SizedBox(height: 8),
              ..._adjustments.map((adj) {
                final isBonus = adj['type'] == 'bonus';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Icon(isBonus ? Icons.add_circle_rounded : Icons.remove_circle_rounded,
                          color: isBonus ? const Color(0xFF15803D) : CeladonColors.error, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(isBonus ? 'Bonus Added' : 'Manual Deduction', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            if ((adj['reason'] ?? '').toString().isNotEmpty)
                              Text((adj['reason'] ?? '').toString(), style: const TextStyle(fontSize: 11.5, color: CeladonColors.textMuted)),
                          ],
                        ),
                      ),
                      Text(
                        '${isBonus ? '+' : '-'}${_formatInr(_toDouble(adj['amount']))}',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: isBonus ? const Color(0xFF15803D) : CeladonColors.error),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 12),
            ],

            // Payment Transactions for Selected Month
            if (_transactions.isNotEmpty) ...[
              Text('Transactions (${_formatMonthLabel(_selectedMonth)})',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: CeladonColors.textPrimary)),
              const SizedBox(height: 8),
              ..._transactions.map((tx) {
                final dt = (tx['paidAt'] ?? '').toString().split('T').first;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF15803D), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${(tx['type'] ?? 'salary').toString().toUpperCase()} • ${(tx['paymentMethod'] ?? 'bank').toString().replaceAll('_', ' ')}',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            Text('$dt • Ref: ${tx['referenceId'] ?? '-'}', style: const TextStyle(fontSize: 11.5, color: CeladonColors.textMuted)),
                          ],
                        ),
                      ),
                      Text(_formatInr(_toDouble(tx['amount'])), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF15803D))),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 12),
            ],

            // Daily Attendance & Payroll Breakdown with Explanations
            if (dailyBreakdown.isNotEmpty) ...[
              Text('Daily Breakdown (${_formatMonthLabel(_selectedMonth)})',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: CeladonColors.textPrimary)),
              const SizedBox(height: 8),
              ...dailyBreakdown.reversed.map((day) {
                final exp = (day['explanation'] ?? '${day['date']} — ${day['notes'] ?? ''}').toString();
                final hasDed = _toDouble(day['leaveDeduction']) > 0 ||
                    _toDouble(day['shortfallDeduction']) > 0 ||
                    _toDouble(day['lateDeduction']) > 0 ||
                    _toDouble(day['breakDeduction']) > 0;
                final hasOt = _toDouble(day['overtimeAddition']) > 0;
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: hasDed ? const Color(0xFFFECACA) : (hasOt ? const Color(0xFFBBF7D0) : const Color(0xFFE2E8F0)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        hasDed ? Icons.warning_amber_rounded : (hasOt ? Icons.trending_up_rounded : Icons.check_circle_outline_rounded),
                        size: 17,
                        color: hasDed ? CeladonColors.error : (hasOt ? const Color(0xFF15803D) : CeladonColors.primary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(exp, style: const TextStyle(fontSize: 12.2, fontWeight: FontWeight.w600, color: CeladonColors.textPrimary))),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 14),
            ],

            // Monthly History for Selected Year
            Text('Payment History ($_selectedYear)',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: CeladonColors.textPrimary)),
            const SizedBox(height: 10),
            if (_yearHistory.isEmpty)
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text('No finalized payroll cycles recorded for $_selectedYear yet.',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
              )
            else
              ..._yearHistory.map((item) {
                final m = (item['month'] ?? '').toString();
                final amt = _toDouble(item['totalAmount'] ?? item['netPayable']);
                final pend = _toDouble(item['pendingAmount']);
                final st = (item['paymentStatus'] ?? item['status'] ?? 'pending').toString();
                final isSelected = m == _selectedMonth;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: isSelected ? CeladonColors.softMint : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: isSelected ? CeladonColors.primary : const Color(0xFFE2E8F0)),
                    ),
                    child: ListTile(
                      onTap: () => _loadPayroll(month: m),
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFEAF5EF),
                        child: Icon(Icons.receipt_long_rounded, color: CeladonColors.primary, size: 19),
                      ),
                      title: Text(_formatMonthLabel(m), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      subtitle: Text(
                        pend > 0 ? '${st.toUpperCase()} • Pending ${_formatInr(pend)}' : st.toUpperCase(),
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: st == 'paid' ? const Color(0xFF15803D) : const Color(0xFFB45309)),
                      ),
                      trailing: Text(_formatInr(amt), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: CeladonColors.textPrimary)),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value, {Color? valueColor}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: CeladonColors.textMuted)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: valueColor ?? CeladonColors.textPrimary)),
          ],
        ),
      );

  Widget _payslipRow(String label, String value, {Color? valueColor, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: bold ? 14 : 13,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                color: bold ? CeladonColors.textPrimary : const Color(0xFF475569),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 16 : 13.5,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
              color: valueColor ?? CeladonColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Container(color: CeladonColors.background, child: SafeArea(top: false, bottom: false, child: _buildBody()));
    }
    return Scaffold(backgroundColor: CeladonColors.background, body: SafeArea(child: _buildBody()));
  }
}
