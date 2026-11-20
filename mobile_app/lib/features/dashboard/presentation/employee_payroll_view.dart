import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../auth/data/user_model.dart';
import '../data/dashboard_service.dart';

/// Employee Personal Payroll & Earnings View (100% Dynamic MongoDB Data)
///
/// Reuses `GET /api/payroll/my-records?month=YYYY-MM` to display:
/// - Selected year's total earned amount (₹)
/// - Paid vs Pending cycle summary
/// - Live payslip breakdown for any selected month
/// - Full payment history list for the selected year
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
  late final DashboardService _dashboardService;
  bool _isLoading = true;
  late int _selectedYear;
  late String _selectedMonth; // YYYY-MM

  Map<String, dynamic>? _currentPayroll;
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
      setState(() {
        _selectedMonth = targetMonth;
        _currentPayroll = payroll;
        _history = rawHistory.whereType<Map<String, dynamic>>().toList();
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
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
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Select Payroll Year',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: CeladonColors.textPrimary,
                ),
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
                  trailing: selected
                      ? const Icon(Icons.check_circle_rounded, color: CeladonColors.primary)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    final now = DateTime.now();
                    final targetMonth = y == now.year
                        ? '$y-${now.month.toString().padLeft(2, '0')}'
                        : '$y-12';
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
    final bonusTotal = _toDouble(p?['bonusTotal'] ?? p?['totalBonus']);
    final deductionTotal = _toDouble(p?['deductionTotal'] ?? p?['totalDeduction']);
    final payStatus = (p?['paymentStatus'] ?? p?['status'] ?? 'draft').toString();

    return RefreshIndicator(
      color: CeladonColors.primary,
      onRefresh: () => _loadPayroll(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.onBack != null)
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: CeladonColors.textPrimary,
                          size: 22,
                        ),
                        tooltip: 'Back',
                        onPressed: widget.onBack,
                      ),
                    const Text(
                      'My Payroll',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: CeladonColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: _showYearPicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today_outlined, size: 13, color: CeladonColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          'Year: $_selectedYear',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: CeladonColors.textPrimary,
                          ),
                        ),
                        const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Color(0xFF64748B)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Annual Earned Hero Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF4E4),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Color(0xFFD9822B),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Earned Payment ($_selectedYear)',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF475569),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatInr(_earnedInSelectedYear),
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: CeladonColors.textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: CeladonColors.softMint,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '${_yearHistory.length} cycles',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: CeladonColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Selected Month Payslip Breakdown
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Payslip • ${_formatMonthLabel(_selectedMonth)}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: CeladonColors.textPrimary,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: payStatus == 'paid'
                              ? const Color(0xFFDCFCE7)
                              : const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          payStatus.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: payStatus == 'paid'
                                ? const Color(0xFF15803D)
                                : const Color(0xFFB45309),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _payslipRow('Base Salary', _formatInr(baseSalary)),
                  _payslipRow('Bonuses / Overtime', '+${_formatInr(bonusTotal)}', valueColor: const Color(0xFF15803D)),
                  _payslipRow('Deductions', '-${_formatInr(deductionTotal)}', valueColor: CeladonColors.error),
                  const Divider(height: 20, color: Color(0xFFE2E8F0)),
                  _payslipRow('Net Payable', _formatInr(netPayable), bold: true),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Monthly History for Selected Year
            Text(
              'Payment History ($_selectedYear)',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: CeladonColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            if (_yearHistory.isEmpty)
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  'No finalized payroll cycles recorded for $_selectedYear yet.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
              )
            else
              ..._yearHistory.map((item) {
                final m = (item['month'] ?? '').toString();
                final amt = _toDouble(item['totalAmount'] ?? item['netPayable']);
                final st = (item['paymentStatus'] ?? item['status'] ?? 'pending').toString();
                final isSelected = m == _selectedMonth;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: isSelected ? CeladonColors.softMint : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: isSelected ? CeladonColors.primary : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: ListTile(
                      onTap: () => _loadPayroll(month: m),
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFEAF5EF),
                        child: Icon(Icons.receipt_long_rounded, color: CeladonColors.primary, size: 19),
                      ),
                      title: Text(
                        _formatMonthLabel(m),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      subtitle: Text(
                        st.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: st == 'paid' ? const Color(0xFF15803D) : const Color(0xFFB45309),
                        ),
                      ),
                      trailing: Text(
                        _formatInr(amt),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: CeladonColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _payslipRow(String label, String value, {Color? valueColor, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: bold ? 14 : 13,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              color: bold ? CeladonColors.textPrimary : const Color(0xFF475569),
            ),
          ),
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
      return Container(
        color: CeladonColors.background,
        child: SafeArea(bottom: false, child: _buildBody()),
      );
    }
    return Scaffold(
      backgroundColor: CeladonColors.background,
      body: SafeArea(child: _buildBody()),
    );
  }
}

