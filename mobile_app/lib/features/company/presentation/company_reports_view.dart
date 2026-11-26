import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../../core/widgets/regen_page_header.dart';
import '../data/company_report_service.dart';
import '../data/report_exporter.dart';

/// Complete Historical Company Reporting Workbench
///
/// Covers 4 comprehensive historical reports from company beginning & employee joining dates:
/// 1. Attendance Report (daily/monthly/yearly/all/range, breaks, OT, late, GPS, leaves, holidays)
/// 2. Payment Report (salary components, deductions, OT, bonuses, leave deductions, transactions, audit trail)
/// 3. General Task Report (overdue analysis, progress updates, completion report, activity history)
/// 4. Project Report (project details, team contributions, associated tasks, delays, timeline)
class CompanyReportsView extends StatefulWidget {
  final VoidCallback? onBack;
  final CompanyReportService? reportService;
  final String? defaultRecipientEmail;

  const CompanyReportsView({
    super.key,
    this.onBack,
    this.reportService,
    this.defaultRecipientEmail,
  });

  @override
  State<CompanyReportsView> createState() => _CompanyReportsViewState();
}

class _CompanyReportsViewState extends State<CompanyReportsView> {
  late final CompanyReportService _service;
  final TextEditingController _searchCtrl = TextEditingController();

  CompanyReportType _activeType = CompanyReportType.attendance;
  String _period = 'all'; // 'all' | 'range' | 'day' | 'week' | 'month' | 'year'
  late String _selectedDate;
  late String _selectedMonth;
  late String _selectedYear;
  String _rangeStart = '';
  String _rangeEnd = '';

  String _employeeId = 'all';
  String _department = 'all';
  String _status = 'all';
  String _priority = 'all';
  String _projectId = 'all';
  int _page = 1;
  static const int _pageSize = 25;

  // Secondary sub-view toggles
  bool _showAttendanceByEmployee = false;
  bool _showPaymentTransactions = false;

  bool _isLoading = true;
  bool _isExporting = false;
  String? _error;
  Map<String, dynamic> _data = const {};

  @override
  void initState() {
    super.initState();
    _service = widget.reportService ?? CompanyReportService();
    final now = DateTime.now();
    _selectedDate = _fmtDate(now);
    _selectedMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    _selectedYear = '${now.year}';
    _rangeStart = '${now.year}-01-01';
    _rangeEnd = _selectedDate;
    _loadReport();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  num _asNum(dynamic v) => v is num ? v : (num.tryParse(v?.toString() ?? '') ?? 0);

  String _asStr(dynamic v, [String fallback = '']) =>
      v == null ? fallback : v.toString();

  List<Map<String, dynamic>> _asListOfMaps(dynamic v) {
    if (v is! List) return const [];
    return v.whereType<Map<String, dynamic>>().toList();
  }

  String _fmtInr(num value) {
    final abs = value.abs().toStringAsFixed(value.truncateToDouble() == value ? 0 : 2);
    final parts = abs.split('.');
    final whole = parts[0];
    String formattedWhole = whole;
    if (whole.length > 3) {
      final last3 = whole.substring(whole.length - 3);
      final rest = whole.substring(0, whole.length - 3);
      final buf = StringBuffer();
      for (int i = 0; i < rest.length; i++) {
        if (i > 0 && (rest.length - i) % 2 == 0) buf.write(',');
        buf.write(rest[i]);
      }
      formattedWhole = '$buf,$last3';
    }
    final dec = parts.length > 1 ? '.${parts[1]}' : '';
    return '${value < 0 ? '-' : ''}₹$formattedWhole$dec';
  }

  Future<void> _loadReport({int? targetPage}) async {
    setState(() {
      _isLoading = true;
      _error = null;
      if (targetPage != null) _page = targetPage;
    });

    try {
      final res = await _service.fetchReport(
        type: _activeType,
        period: _period,
        date: _selectedDate,
        startDate: _period == 'range' ? _rangeStart : null,
        endDate: _period == 'range' ? _rangeEnd : null,
        month: _selectedMonth,
        year: _selectedYear,
        employeeId: _employeeId,
        department: _department,
        status: _status,
        priority: (_activeType == CompanyReportType.generalTask ||
                _activeType == CompanyReportType.project)
            ? _priority
            : null,
        projectId: _activeType == CompanyReportType.project ? _projectId : null,
        search: _searchCtrl.text,
        page: _page,
        limit: _pageSize,
      );
      if (mounted) {
        setState(() {
          _data = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('AuthException: ', '');
          _isLoading = false;
        });
      }
    }
  }

  void _switchReportType(CompanyReportType type) {
    if (_activeType == type) return;
    setState(() {
      _activeType = type;
      _status = 'all';
      _priority = 'all';
      _projectId = 'all';
      _page = 1;
      _showAttendanceByEmployee = false;
      _showPaymentTransactions = false;
    });
    _loadReport();
  }

  Future<Map<String, dynamic>> _fetchFullDatasetForExport() async {
    return _service.fetchReport(
      type: _activeType,
      period: _period,
      date: _selectedDate,
      startDate: _period == 'range' ? _rangeStart : null,
      endDate: _period == 'range' ? _rangeEnd : null,
      month: _selectedMonth,
      year: _selectedYear,
      employeeId: _employeeId,
      department: _department,
      status: _status,
      priority: (_activeType == CompanyReportType.generalTask ||
              _activeType == CompanyReportType.project)
          ? _priority
          : null,
      projectId: _activeType == CompanyReportType.project ? _projectId : null,
      search: _searchCtrl.text,
      page: 1,
      limit: 'all',
    );
  }

  String _reportFilenameBase() {
    switch (_activeType) {
      case CompanyReportType.attendance:
        return 'ReGen_Attendance_Report';
      case CompanyReportType.payment:
        return 'ReGen_Payment_Report';
      case CompanyReportType.generalTask:
        return 'ReGen_General_Task_Report';
      case CompanyReportType.project:
        return 'ReGen_Project_Report';
    }
  }

  Future<void> _exportCsv() async {
    setState(() => _isExporting = true);
    try {
      final full = await _fetchFullDatasetForExport();
      final csv = _asStr(full['csvContent']);
      final table = ReportExporter.buildTableData(_activeType, full);
      final content = csv.isNotEmpty
          ? csv
          : [
              table.headers.map((h) => '"${h.replaceAll('"', '""')}"').join(','),
              ...table.rows.map((r) => r.map((c) => '"${c.replaceAll('"', '""')}"').join(',')),
            ].join('\n');
      final savedPath = await ReportExporter.saveReportFile(
        filenamePrefix: _reportFilenameBase(),
        extension: 'csv',
        content: content,
      );
      if (mounted) _showSnack('CSV saved: $savedPath');
    } catch (e) {
      if (mounted) _showSnack('CSV export failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportExcel() async {
    setState(() => _isExporting = true);
    try {
      final full = await _fetchFullDatasetForExport();
      final table = ReportExporter.buildTableData(_activeType, full);
      final xls = ReportExporter.buildExcelXmlContent(table);
      final savedPath = await ReportExporter.saveReportFile(
        filenamePrefix: _reportFilenameBase(),
        extension: 'xls',
        content: xls,
        includeUtf8Bom: false,
      );
      if (mounted) _showSnack('Excel workbook saved: $savedPath');
    } catch (e) {
      if (mounted) _showSnack('Excel export failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _openPrintPreview() async {
    setState(() => _isExporting = true);
    try {
      final full = await _fetchFullDatasetForExport();
      final table = ReportExporter.buildTableData(_activeType, full);
      if (!mounted) return;
      setState(() => _isExporting = false);
      await _showPrintPreviewSheet(table);
    } catch (e) {
      if (mounted) {
        setState(() => _isExporting = false);
        _showSnack('Could not build print view: $e', isError: true);
      }
    }
  }

  Future<void> _showPrintPreviewSheet(ReportTableData table) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.88,
        minChildSize: 0.5,
        maxChildSize: 0.96,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 8),
              child: Row(
                children: [
                  const Icon(Icons.print_rounded, color: CeladonColors.primary, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${table.companyName} — ${table.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: CeladonColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Print-Friendly Layout • ${table.periodLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: CeladonColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () async {
                      try {
                        final html = ReportExporter.buildPrintableHtml(table);
                        final path = await ReportExporter.saveReportFile(
                          filenamePrefix: '${_reportFilenameBase()}_Print',
                          extension: 'html',
                          content: html,
                          includeUtf8Bom: false,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) _showSnack('Print-ready HTML saved: $path');
                      } catch (e) {
                        if (mounted) _showSnack('Save failed: $e', isError: true);
                      }
                    },
                    icon: const Icon(Icons.download_rounded, size: 15),
                    label: const Text('Save Print HTML', style: TextStyle(fontSize: 11.5)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: table.summaryLines
                          .map((line) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: CeladonColors.primaryContainer,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: CeladonColors.border),
                                ),
                                child: Text(
                                  line,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: CeladonColors.primaryDark,
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 14),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(CeladonColors.primary),
                        headingTextStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                        dataTextStyle: const TextStyle(
                          color: CeladonColors.textPrimary,
                          fontSize: 11,
                        ),
                        columnSpacing: 14,
                        columns: table.headers
                            .map((h) => DataColumn(label: Text(h)))
                            .toList(),
                        rows: table.rows
                            .take(250)
                            .map((row) => DataRow(
                                  cells: row
                                      .map((cell) => DataCell(
                                            ConstrainedBox(
                                              constraints: const BoxConstraints(maxWidth: 180),
                                              child: Text(
                                                cell,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ))
                                      .toList(),
                                ))
                            .toList(),
                      ),
                    ),
                    if (table.rows.length > 250)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          'Showing first 250 of ${table.rows.length} rows in preview. Save Print HTML / CSV / Excel for all ${table.rows.length} rows.',
                          style: const TextStyle(fontSize: 11, color: CeladonColors.textMuted),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEmailDialog() async {
    final emailCtrl = TextEditingController(text: widget.defaultRecipientEmail ?? '');
    final notesCtrl = TextEditingController();
    final sent = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Email Report', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Recipient Email',
                hintText: 'manager@company.com',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes (Optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: CeladonColors.primary, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );

    final email = emailCtrl.text.trim();
    final notes = notesCtrl.text.trim();
    emailCtrl.dispose();
    notesCtrl.dispose();

    if (sent == true && email.isNotEmpty) {
      try {
        final filters = CompanyReportService.buildQueryParams(
          type: _activeType,
          period: _period,
          date: _selectedDate,
          startDate: _period == 'range' ? _rangeStart : null,
          endDate: _period == 'range' ? _rangeEnd : null,
          month: _selectedMonth,
          year: _selectedYear,
          employeeId: _employeeId,
          department: _department,
          status: _status,
          priority: _priority,
          projectId: _projectId,
          search: _searchCtrl.text,
          limit: 'all',
        );
        final msg = await _service.sendReportEmail(
          type: _activeType,
          recipientEmail: email,
          notes: notes,
          filters: filters,
        );
        if (mounted) _showSnack(msg);
      } catch (e) {
        if (mounted) _showSnack('Email send failed: $e', isError: true);
      }
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? CeladonColors.error : CeladonColors.primary,
        content: Text(msg),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _pickSingleDate() async {
    final initial = DateTime.tryParse(_selectedDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2015),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() => _selectedDate = _fmtDate(picked));
      _loadReport(targetPage: 1);
    }
  }

  Future<void> _pickDateRange() async {
    final initialStart = DateTime.tryParse(_rangeStart) ?? DateTime(DateTime.now().year, 1, 1);
    final initialEnd = DateTime.tryParse(_rangeEnd) ?? DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: DateTime(2035),
      initialDateRange: DateTimeRange(
        start: initialStart.isAfter(initialEnd) ? initialEnd : initialStart,
        end: initialEnd,
      ),
    );
    if (picked != null) {
      setState(() {
        _rangeStart = _fmtDate(picked.start);
        _rangeEnd = _fmtDate(picked.end);
      });
      _loadReport(targetPage: 1);
    }
  }

  void _shiftMonth(int delta) {
    final parts = _selectedMonth.split('-');
    var y = int.tryParse(parts[0]) ?? DateTime.now().year;
    var m = (parts.length > 1 ? int.tryParse(parts[1]) : null) ?? DateTime.now().month;
    m += delta;
    while (m < 1) {
      m += 12;
      y -= 1;
    }
    while (m > 12) {
      m -= 12;
      y += 1;
    }
    setState(() => _selectedMonth = '$y-${m.toString().padLeft(2, '0')}');
    _loadReport(targetPage: 1);
  }

  void _shiftYear(int delta) {
    final y = (int.tryParse(_selectedYear) ?? DateTime.now().year) + delta;
    setState(() => _selectedYear = '$y');
    _loadReport(targetPage: 1);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: CeladonColors.primary,
      onRefresh: () => _loadReport(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          _buildReportTypeTabs(),
          const SizedBox(height: 12),
          _buildPeriodSelector(),
          const SizedBox(height: 10),
          _buildFilterControls(),
          const SizedBox(height: 10),
          _buildExportToolbar(),
          const SizedBox(height: 14),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator(color: CeladonColors.primary)),
            )
          else if (_error != null)
            _buildErrorCard()
          else ...[
            _buildSummarySection(),
            const SizedBox(height: 12),
            _buildActiveSubViewToggle(),
            const SizedBox(height: 10),
            _buildRecordsList(),
            const SizedBox(height: 12),
            _buildPaginationControls(),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final periodLabel = _asStr(_data['periodLabel'], 'All Historical Records');
    final earliest = _asStr(_data['earliestRecordDate']);
    return ReGenPageHeader(
      title: 'Company Historical Reports',
      subtitle: earliest.isNotEmpty ? '$periodLabel • Since $earliest' : periodLabel,
      onBack: widget.onBack,
      backTooltip: 'Back to Home',
      trailing: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        onPressed: () => _loadReport(),
        icon: const Icon(Icons.refresh_rounded, color: CeladonColors.primary, size: 22),
        tooltip: 'Refresh',
      ),
    );
  }

  Widget _buildReportTypeTabs() {
    final tabs = [
      (CompanyReportType.attendance, 'Attendance', Icons.access_time_rounded),
      (CompanyReportType.payment, 'Payments', Icons.payments_outlined),
      (CompanyReportType.generalTask, 'General Tasks', Icons.assignment_outlined),
      (CompanyReportType.project, 'Projects', Icons.folder_copy_outlined),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: tabs.map((t) {
          final active = _activeType == t.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: active,
              onSelected: (_) => _switchReportType(t.$1),
              avatar: Icon(
                t.$3,
                size: 16,
                color: active ? Colors.white : CeladonColors.primary,
              ),
              label: Text(t.$2),
              selectedColor: CeladonColors.primary,
              backgroundColor: Colors.white,
              side: BorderSide(color: active ? CeladonColors.primary : CeladonColors.border),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : CeladonColors.textPrimary,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    const periods = [
      ('all', 'All History'),
      ('day', 'Day'),
      ('week', 'Week'),
      ('month', 'Month'),
      ('year', 'Year'),
      ('range', 'Date Range'),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CeladonColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: periods.map((p) {
                final selected = _period == p.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    onTap: () {
                      setState(() => _period = p.$1);
                      _loadReport(targetPage: 1);
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected ? CeladonColors.primary : CeladonColors.inputBackground,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected ? CeladonColors.primary : CeladonColors.border,
                        ),
                      ),
                      child: Text(
                        p.$2,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: selected ? Colors.white : CeladonColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          if (_period == 'day' || _period == 'week') ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _pickSingleDate,
              icon: const Icon(Icons.calendar_today_rounded, size: 15),
              label: Text(
                _period == 'day' ? 'Selected Day: $_selectedDate' : 'Week Anchor: $_selectedDate',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ] else if (_period == 'month') ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: () => _shiftMonth(-1),
                ),
                Text(
                  'Month: $_selectedMonth',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: () => _shiftMonth(1),
                ),
              ],
            ),
          ] else if (_period == 'year') ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: () => _shiftYear(-1),
                ),
                Text(
                  'Year: $_selectedYear',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: () => _shiftYear(1),
                ),
              ],
            ),
          ] else if (_period == 'range') ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _pickDateRange,
              icon: const Icon(Icons.date_range_rounded, size: 16),
              label: Text(
                'Range: $_rangeStart  →  $_rangeEnd',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterControls() {
    final employeeRaw = _asListOfMaps(_data['employees'] ?? _data['employeeOptions']);
    final deptRaw = (_data['departments'] is List)
        ? (_data['departments'] as List).map((e) => e.toString()).toList()
        : <String>[];
    final projectOptions = _asListOfMaps(_data['projectOptions']);

    final statusOptions = _statusChoicesForType();
    final effectiveStatus = statusOptions.any((s) => s.$1 == _status) ? _status : 'all';
    final effectiveEmp = employeeRaw.any((e) => _asStr(e['userId']) == _employeeId) ? _employeeId : 'all';
    final effectiveDept = deptRaw.contains(_department) ? _department : 'all';
    final effectiveProj = projectOptions.any((p) => _asStr(p['id']) == _projectId) ? _projectId : 'all';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CeladonColors.borderLight),
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            onSubmitted: (_) => _loadReport(targetPage: 1),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: CeladonColors.inputBackground,
              hintText: 'Search employee, ID, department, task or project...',
              hintStyle: const TextStyle(fontSize: 12, color: CeladonColors.textMuted),
              prefixIcon: const Icon(Icons.search_rounded, size: 18, color: CeladonColors.primary),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward_rounded, size: 18, color: CeladonColors.primary),
                onPressed: () => _loadReport(targetPage: 1),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: CeladonColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: CeladonColors.border),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildDropdown(
                  label: 'Employee',
                  value: effectiveEmp,
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('All Employees', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ...employeeRaw.map((e) {
                      final name = _asStr(e['name'], _asStr(e['userId']));
                      final st = _asStr(e['status'], 'active');
                      final suffix = st == 'active' ? '' : ' ($st)';
                      return DropdownMenuItem(
                        value: _asStr(e['userId']),
                        child: Text('$name$suffix', maxLines: 1, overflow: TextOverflow.ellipsis),
                      );
                    }),
                  ],
                  onChanged: (v) {
                    setState(() => _employeeId = v ?? 'all');
                    _loadReport(targetPage: 1);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDropdown(
                  label: 'Department',
                  value: effectiveDept,
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('All Departments', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ...deptRaw.map((d) => DropdownMenuItem(value: d, child: Text(d, maxLines: 1, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (v) {
                    setState(() => _department = v ?? 'all');
                    _loadReport(targetPage: 1);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildDropdown(
                  label: 'Status',
                  value: effectiveStatus,
                  items: statusOptions
                      .map((s) => DropdownMenuItem(value: s.$1, child: Text(s.$2, maxLines: 1, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _status = v ?? 'all');
                    _loadReport(targetPage: 1);
                  },
                ),
              ),
              if (_activeType == CompanyReportType.generalTask ||
                  _activeType == CompanyReportType.project) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _buildDropdown(
                    label: 'Priority',
                    value: _priority,
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Priorities', maxLines: 1, overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'urgent', child: Text('Urgent', maxLines: 1, overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'high', child: Text('High', maxLines: 1, overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'medium', child: Text('Medium', maxLines: 1, overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'low', child: Text('Low', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) {
                      setState(() => _priority = v ?? 'all');
                      _loadReport(targetPage: 1);
                    },
                  ),
                ),
              ],
            ],
          ),
          if (_activeType == CompanyReportType.project && projectOptions.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildDropdown(
              label: 'Project',
              value: effectiveProj,
              items: [
                const DropdownMenuItem(value: 'all', child: Text('All Projects', maxLines: 1, overflow: TextOverflow.ellipsis)),
                ...projectOptions.map((p) => DropdownMenuItem(
                      value: _asStr(p['id']),
                      child: Text(_asStr(p['name']), maxLines: 1, overflow: TextOverflow.ellipsis),
                    )),
              ],
              onChanged: (v) {
                setState(() => _projectId = v ?? 'all');
                _loadReport(targetPage: 1);
              },
            ),
          ],
        ],
      ),
    );
  }

  List<(String, String)> _statusChoicesForType() {
    switch (_activeType) {
      case CompanyReportType.attendance:
        return const [
          ('all', 'All Statuses'),
          ('present', 'Present'),
          ('late', 'Late'),
          ('half_day', 'Half Day'),
          ('absent', 'Absent'),
          ('leave', 'Leave'),
          ('holiday', 'Holiday'),
        ];
      case CompanyReportType.payment:
        return const [
          ('all', 'All Statuses'),
          ('paid', 'Paid'),
          ('partially_paid', 'Partially Paid'),
          ('unpaid', 'Unpaid'),
          ('pending', 'Pending / Due'),
        ];
      case CompanyReportType.generalTask:
        return const [
          ('all', 'All Statuses'),
          ('completed', 'Completed'),
          ('in_progress', 'In Progress'),
          ('todo', 'To Do'),
          ('overdue', 'Overdue / Delayed'),
          ('not_completed', 'Not Completed'),
        ];
      case CompanyReportType.project:
        return const [
          ('all', 'All Statuses'),
          ('active', 'Active'),
          ('planning', 'Planning'),
          ('completed', 'Completed'),
          ('on_hold', 'On Hold'),
          ('delayed', 'Delayed'),
        ];
    }
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      items: items,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 12, color: CeladonColors.textPrimary, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        labelStyle: const TextStyle(fontSize: 11, color: CeladonColors.primary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        filled: true,
        fillColor: CeladonColors.inputBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: CeladonColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: CeladonColors.border),
        ),
      ),
    );
  }

  Widget _buildExportToolbar() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildActionButton(
          icon: Icons.table_chart_outlined,
          label: 'CSV',
          onTap: _isExporting ? null : _exportCsv,
        ),
        _buildActionButton(
          icon: Icons.grid_on_rounded,
          label: 'Excel',
          onTap: _isExporting ? null : _exportExcel,
        ),
        _buildActionButton(
          icon: Icons.print_outlined,
          label: 'Print View',
          onTap: _isExporting ? null : _openPrintPreview,
        ),
        _buildActionButton(
          icon: Icons.mail_outline_rounded,
          label: 'Email',
          onTap: _isExporting ? null : _showEmailDialog,
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15),
      label: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
      style: OutlinedButton.styleFrom(
        foregroundColor: CeladonColors.primary,
        backgroundColor: Colors.white,
        side: const BorderSide(color: CeladonColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildSummarySection() {
    late final List<(String, String, Color)> metrics;
    switch (_activeType) {
      case CompanyReportType.attendance:
        metrics = [
          ('Records', '${_data['totalRecords'] ?? 0}', CeladonColors.primary),
          ('Hours', '${_data['totalWorkingHours'] ?? 0}h', CeladonColors.primaryDark),
          ('Overtime', '${_data['totalOvertimeHours'] ?? 0}h', const Color(0xFF0369A1)),
          ('Present', '${_data['presentCount'] ?? 0}', CeladonColors.primary),
          ('Late', '${_data['lateCount'] ?? 0} (${_data['totalLateMinutes'] ?? 0}m)', const Color(0xFFD97706)),
          ('Absent / Leave', '${_data['absentCount'] ?? 0} / ${_data['leaveCount'] ?? 0}', CeladonColors.error),
        ];
        break;
      case CompanyReportType.payment:
        final pfAmt = _asNum(_data['companyOverallPfDeductions']);
        metrics = [
          ('Records', '${_data['totalEmployees'] ?? 0}', CeladonColors.primary),
          ('Net Payable', _fmtInr(_asNum(_data['companyTotalNetPayable'])), CeladonColors.primaryDark),
          ('Amount Paid', _fmtInr(_asNum(_data['companyOverallAmountPaid'])), CeladonColors.primary),
          ('Pending', _fmtInr(_asNum(_data['companyOverallPendingAmount'])), const Color(0xFFD97706)),
          ('Bonuses / OT', '${_fmtInr(_asNum(_data['companyOverallBonuses']))} / ${_fmtInr(_asNum(_data['companyOverallOvertimePay']))}', const Color(0xFF0369A1)),
          ('Deductions / PF', '${_fmtInr(_asNum(_data['companyOverallDeductions']))}${pfAmt > 0 ? ' (PF ${_fmtInr(pfAmt)})' : ''}', CeladonColors.error),
        ];
        break;
      case CompanyReportType.generalTask:
        metrics = [
          ('Total Tasks', '${_data['totalTasks'] ?? 0}', CeladonColors.primary),
          ('Completed', '${_data['totalCompleted'] ?? 0} (${_data['overallCompletionRate'] ?? 0}%)', CeladonColors.primaryDark),
          ('In Progress', '${_data['totalInProgress'] ?? 0}', const Color(0xFF0369A1)),
          ('To Do', '${_data['totalTodo'] ?? 0}', CeladonColors.textSecondary),
          ('Overdue', '${_data['totalOverdue'] ?? 0}', const Color(0xFFD97706)),
          ('Not Completed', '${_data['totalNotCompleted'] ?? 0}', CeladonColors.error),
        ];
        break;
      case CompanyReportType.project:
        metrics = [
          ('Projects', '${_data['totalProjects'] ?? 0}', CeladonColors.primary),
          ('Active', '${_data['activeProjects'] ?? 0}', const Color(0xFF0369A1)),
          ('Completed', '${_data['completedProjects'] ?? 0}', CeladonColors.primaryDark),
          ('Delayed', '${_data['delayedProjects'] ?? 0}', CeladonColors.error),
          ('Project Tasks', '${_data['completedProjectTasks'] ?? 0}/${_data['totalProjectTasks'] ?? 0}', CeladonColors.primary),
          ('Completion', '${_data['overallCompletionRate'] ?? 0}%', CeladonColors.primaryDark),
        ];
        break;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: metrics.map((item) {
            return Container(
              width: tileWidth,
              constraints: const BoxConstraints(minHeight: 62),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: CeladonColors.borderLight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, color: CeladonColors.textMuted, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: item.$3),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildActiveSubViewToggle() {
    if (_activeType == CompanyReportType.attendance) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            selected: !_showAttendanceByEmployee,
            onSelected: (_) => setState(() => _showAttendanceByEmployee = false),
            label: const Text('Daily Logs'),
          ),
          ChoiceChip(
            selected: _showAttendanceByEmployee,
            onSelected: (_) => setState(() => _showAttendanceByEmployee = true),
            label: const Text('Employee Totals (Joining Date)'),
          ),
        ],
      );
    }
    if (_activeType == CompanyReportType.payment) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            selected: !_showPaymentTransactions,
            onSelected: (_) => setState(() => _showPaymentTransactions = false),
            label: const Text('Salary Records'),
          ),
          ChoiceChip(
            selected: _showPaymentTransactions,
            onSelected: (_) => setState(() => _showPaymentTransactions = true),
            label: const Text('Transaction History'),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildRecordsList() {
    if (_activeType == CompanyReportType.attendance) {
      if (_showAttendanceByEmployee) {
        final empSummaries = _asListOfMaps(_data['employeeSummaries']);
        if (empSummaries.isEmpty) return _buildEmptyCard('No employee attendance summaries found.');
        return Column(
          children: empSummaries.map(_buildAttendanceEmployeeSummaryCard).toList(),
        );
      }
      final rows = _asListOfMaps(_data['records']);
      if (rows.isEmpty) return _buildEmptyCard('No attendance records match the selected filters.');
      return Column(children: rows.map(_buildAttendanceRecordCard).toList());
    }

    if (_activeType == CompanyReportType.payment) {
      if (_showPaymentTransactions) {
        final txs = _asListOfMaps(_data['transactions']);
        if (txs.isEmpty) return _buildEmptyCard('No payment transactions recorded in this period.');
        return Column(children: txs.map(_buildTransactionCard).toList());
      }
      final rows = _asListOfMaps(_data['records']);
      if (rows.isEmpty) return _buildEmptyCard('No salary records match the selected filters.');
      return Column(children: rows.map(_buildPaymentRecordCard).toList());
    }

    if (_activeType == CompanyReportType.generalTask) {
      final rows = _asListOfMaps(_data['records']);
      if (rows.isEmpty) return _buildEmptyCard('No general tasks match the selected filters.');
      return Column(children: rows.map(_buildTaskRecordCard).toList());
    }

    final projects = _asListOfMaps(_data['projects']);
    if (projects.isEmpty) return _buildEmptyCard('No projects match the selected filters.');
    return Column(children: projects.map(_buildProjectCard).toList());
  }

  Widget _buildAttendanceEmployeeSummaryCard(Map<String, dynamic> emp) {
    final joining = _asStr(emp['joiningDate'], 'Not set');
    final empStatus = _asStr(emp['employeeStatus'], 'active');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CeladonColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_asStr(emp['name'])} (${_asStr(emp['staffId'])})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 8),
              _statusChip(empStatus, empStatus == 'active' ? CeladonColors.primary : CeladonColors.textMuted),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_asStr(emp['department'])} • ${_asStr(emp['designation'])} • Joined: $joining',
            style: const TextStyle(fontSize: 11, color: CeladonColors.textMuted),
          ),
          const SizedBox(height: 8),
          Text(
            'Shifts: ${emp['totalShifts'] ?? 0} | Present: ${emp['presentCount'] ?? 0} | Late: ${emp['lateCount'] ?? 0} (${emp['totalLateMinutes'] ?? 0}m) | Half Day: ${emp['halfDayCount'] ?? 0} | Absent: ${emp['absentCount'] ?? 0} | Leaves: ${emp['leaveDays'] ?? 0}',
            style: const TextStyle(fontSize: 11.5, color: CeladonColors.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'Hours: ${emp['totalWorkingHours'] ?? 0}h | OT: ${emp['totalOvertimeHours'] ?? 0}h | Break Delay: ${emp['totalBreakDelayMinutes'] ?? 0}m',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: CeladonColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceRecordCard(Map<String, dynamic> r) {
    final st = _asStr(r['status'], 'present');
    final color = st == 'present'
        ? CeladonColors.primary
        : (st == 'late'
            ? const Color(0xFFD97706)
            : (st == 'leave' || st == 'holiday' ? const Color(0xFF0369A1) : CeladonColors.error));
    return InkWell(
      onTap: () => _showAttendanceDetailSheet(r),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: CeladonColors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_asStr(r['name'])} (${_asStr(r['staffId'])})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 8),
                _statusChip(st.toUpperCase(), color),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${_asStr(r['date'])} (${_asStr(r['weekday'])}) • ${_asStr(r['department'])} • Joined: ${_asStr(r['joiningDate'], '--')}',
              style: const TextStyle(fontSize: 11, color: CeladonColors.textMuted),
            ),
            const SizedBox(height: 6),
            Text(
              'In: ${_asStr(r['checkInDisplay'], '--')} • Out: ${_asStr(r['checkOutDisplay'], '--')} • Worked: ${r['workingHours'] ?? 0}h${_asNum(r['overtimeHours']) > 0 ? ' • OT +${r['overtimeHours']}h' : ''}${_asNum(r['lateMinutes']) > 0 ? ' • Late ${r['lateMinutes']}m' : ''}',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
            if (_asNum(r['breakMinutes']) > 0 || _asNum(r['casualBreakMinutes']) > 0) ...[
              const SizedBox(height: 3),
              Text(
                'Breaks: Lunch ${r['breakMinutes'] ?? 0}m • Casual ${r['casualBreakMinutes'] ?? 0}m • Delay ${r['totalBreakDelayMinutes'] ?? 0}m',
                style: const TextStyle(fontSize: 11, color: CeladonColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentRecordCard(Map<String, dynamic> r) {
    final st = _asStr(r['paymentStatus'], 'unpaid');
    final color = st == 'paid'
        ? CeladonColors.primary
        : (st == 'partially_paid' ? const Color(0xFFD97706) : CeladonColors.error);
    final rawLeaveDed = _asNum(r['unpaidLeaveDeductions']);
    final leaveDed = rawLeaveDed > 0
        ? rawLeaveDed
        : (_asNum(r['approvedLeaveDeduction']) + _asNum(r['unapprovedLeaveDeduction']));
    final lateDed = _asNum(r['lateDeduction']);
    final shortfallDed = _asNum(r['shortfallDeduction']);
    final breakDed = _asNum(r['breakDeduction']);
    final manualDed = _asNum(r['manualDeduction']);
    final pfDed = _asNum(r['pfDeduction']);
    final totalDed = _asNum(r['totalDeductions']);
    return InkWell(
      onTap: () => _showPaymentDetailSheet(r),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: CeladonColors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_asStr(r['name'])} • ${_asStr(r['salaryPeriod'] ?? r['period'])}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 8),
                _statusChip(st.replaceAll('_', ' ').toUpperCase(), color),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'ID: ${_asStr(r['staffId'])} • ${_asStr(r['department'])} • ${_asStr(r['designation'])} • Joined: ${_asStr(r['joiningDate'], '--')}',
              style: const TextStyle(fontSize: 11, color: CeladonColors.textMuted),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text('Base: ${_fmtInr(_asNum(r['baseSalary']))}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                Text('Net: ${_fmtInr(_asNum(r['totalAmount']))}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: CeladonColors.primaryDark)),
                Text('Paid: ${_fmtInr(_asNum(r['amountPaid']))}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: CeladonColors.primary)),
                Text('Due: ${_fmtInr(_asNum(r['pendingAmount']))}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFB45309))),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              'OT: ${_fmtInr(_asNum(r['overtimePay']))} • Bonus: ${_fmtInr(_asNum(r['bonus']))} • Total Ded: -${_fmtInr(totalDed)}',
              style: const TextStyle(fontSize: 11, color: CeladonColors.textSecondary, fontWeight: FontWeight.w600),
            ),
            if (leaveDed > 0 || lateDed > 0 || shortfallDed > 0 || breakDed > 0 || manualDed > 0 || pfDed > 0) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (leaveDed > 0) _statusChip('Leave -${_fmtInr(leaveDed)}', CeladonColors.error),
                  if (lateDed > 0) _statusChip('Late -${_fmtInr(lateDed)}', CeladonColors.error),
                  if (shortfallDed > 0) _statusChip('Shortfall -${_fmtInr(shortfallDed)}', CeladonColors.error),
                  if (breakDed > 0) _statusChip('Break -${_fmtInr(breakDed)}', CeladonColors.error),
                  if (manualDed > 0) _statusChip('Manual -${_fmtInr(manualDed)}', CeladonColors.error),
                  if (pfDed > 0) _statusChip('PF -${_fmtInr(pfDed)}', const Color(0xFF0369A1)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> t) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CeladonColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_asStr(t['name'])} (${_asStr(t['staffId'])})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _fmtInr(_asNum(t['amount'])),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: CeladonColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Month: ${_asStr(t['month'])} • Ref: ${_asStr(t['referenceId'])} • Method: ${_asStr(t['paymentMethod'])}',
            style: const TextStyle(fontSize: 11, color: CeladonColors.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            'Paid: ${_asStr(t['paidAt']).split('T').first} • Processed By: ${_asStr(t['processedByName'], 'Admin')}',
            style: const TextStyle(fontSize: 11, color: CeladonColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskRecordCard(Map<String, dynamic> t) {
    final isOverdue = t['isOverdue'] == true;
    final status = _asStr(t['status'], 'To Do');
    final color = status == 'Completed'
        ? CeladonColors.primary
        : (isOverdue || status == 'Not Completed' ? CeladonColors.error : const Color(0xFF0369A1));
    return InkWell(
      onTap: () => _showTaskDetailSheet(t),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: CeladonColors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _asStr(t['taskTitle']),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 8),
                _statusChip(status, color),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Assignee: ${_asStr(t['employeeName'])} (${_asStr(t['department'])}) • By: ${_asStr(t['assignorName'])} • Priority: ${_asStr(t['priority']).toUpperCase()}',
              style: const TextStyle(fontSize: 11, color: CeladonColors.textMuted),
            ),
            const SizedBox(height: 6),
            Text(
              'Created: ${_asStr(t['createdDate'], '--')} • Due: ${_asStr(t['dueDate'], '--')} • Progress: ${t['progressPercentage'] ?? 0}%${isOverdue ? ' • ${_asStr(t['overdueLabel'])}' : ''}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: isOverdue ? CeladonColors.error : CeladonColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectCard(Map<String, dynamic> p) {
    final metrics = p['taskMetrics'] is Map ? p['taskMetrics'] as Map : const {};
    final delayed = p['isDelayed'] == true;
    final st = _asStr(p['status'], 'active');
    final color = st == 'completed'
        ? CeladonColors.primary
        : (delayed ? CeladonColors.error : const Color(0xFF0369A1));
    final depts = p['departments'] is List ? (p['departments'] as List).join(', ') : '';

    return InkWell(
      onTap: () => _showProjectDetailSheet(p),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: CeladonColors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _asStr(p['name']),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 8),
                _statusChip(delayed ? 'DELAYED (${p['overdueDays']}d)' : st.toUpperCase(), color),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Manager: ${_asStr(p['projectManager'])} • Depts: ${depts.isNotEmpty ? depts : 'General'} • Priority: ${_asStr(p['priority']).toUpperCase()}',
              style: const TextStyle(fontSize: 11, color: CeladonColors.textMuted),
            ),
            const SizedBox(height: 6),
            Text(
              'Start: ${_asStr(p['startDate'], '--')} • Due: ${_asStr(p['dueDate'], '--')} • Tasks: ${metrics['completed'] ?? 0}/${metrics['total'] ?? 0} (${metrics['completionRate'] ?? 0}%)',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }

  Widget _buildEmptyCard(String msg) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CeladonColors.borderLight),
      ),
      child: Column(
        children: [
          const Icon(Icons.inbox_outlined, size: 34, color: CeladonColors.textMuted),
          const SizedBox(height: 8),
          Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: CeladonColors.textMuted, fontSize: 12.5)),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CeladonColors.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Text(_error ?? 'Error loading report', style: const TextStyle(color: CeladonColors.error, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: () => _loadReport(),
            style: ElevatedButton.styleFrom(backgroundColor: CeladonColors.primary, foregroundColor: Colors.white),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationControls() {
    final pag = _data['pagination'] is Map ? _data['pagination'] as Map : const {};
    final page = (_asNum(pag['page']).toInt()).clamp(1, 999999);
    final totalPages = (_asNum(pag['totalPages']).toInt()).clamp(1, 999999);
    final total = _asNum(pag['total']).toInt();
    if (total <= 0) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        OutlinedButton.icon(
          onPressed: page > 1 ? () => _loadReport(targetPage: page - 1) : null,
          icon: const Icon(Icons.chevron_left_rounded, size: 17),
          label: const Text('Prev', style: TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            visualDensity: VisualDensity.compact,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Page $page of $totalPages • $total total',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: CeladonColors.textSecondary),
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: page < totalPages ? () => _loadReport(targetPage: page + 1) : null,
          icon: const Icon(Icons.chevron_right_rounded, size: 17),
          label: const Text('Next', style: TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }

  void _showAttendanceDetailSheet(Map<String, dynamic> r) {
    final coords = r['locationCoords'] is Map ? r['locationCoords'] as Map : null;
    _showDetailSheet(
      title: '${_asStr(r['name'])} — ${_asStr(r['date'])}',
      rows: [
        ('Employee ID', _asStr(r['staffId'])),
        ('Department / Role', '${_asStr(r['department'])} • ${_asStr(r['designation'])}'),
        ('Joining Date', _asStr(r['joiningDate'], 'Not set')),
        ('Employee Status', _asStr(r['employeeStatus'], 'active')),
        ('Date / Weekday', '${_asStr(r['date'])} (${_asStr(r['weekday'])})'),
        ('Attendance Status', _asStr(r['status'])),
        ('Check In / Out', '${_asStr(r['checkInDisplay'], '--')}  →  ${_asStr(r['checkOutDisplay'], '--')}'),
        ('Working Hours', '${r['workingHours'] ?? 0}h'),
        ('Late / Early Out / OT', '${r['lateMinutes'] ?? 0}m late • ${r['earlyDepartureMinutes'] ?? 0}m early • ${r['overtimeHours'] ?? 0}h OT'),
        ('Lunch Break', '${_asStr(r['breakStartDisplay'], '--')} - ${_asStr(r['breakEndDisplay'], '--')} (${r['breakMinutes'] ?? 0}m, delay ${r['breakDelayMinutes'] ?? 0}m)'),
        ('Casual Break', '${_asStr(r['casualBreakStartDisplay'], '--')} - ${_asStr(r['casualBreakEndDisplay'], '--')} (${r['casualBreakMinutes'] ?? 0}m, delay ${r['casualBreakDelayMinutes'] ?? 0}m)'),
        ('Location Mode', '${_asStr(r['workMode'])} • ${_asStr(r['location'])}'),
        if (coords != null)
          ('GPS Coordinates', '${coords['latitude']}, ${coords['longitude']} (dist: ${coords['distance'] ?? '--'}m)'),
        ('Location Verified', r['locationVerified'] == true ? 'Verified' : 'Manual / Unverified'),
        ('Modified After Create', r['wasModified'] == true ? 'Yes (${_asStr(r['updatedAt'])})' : 'No'),
        if (_asStr(r['notes']).isNotEmpty) ('Notes', _asStr(r['notes'])),
      ],
    );
  }

  void _showPaymentDetailSheet(Map<String, dynamic> r) {
    final adjs = _asListOfMaps(r['adjustments']);
    final txs = _asListOfMaps(r['paymentHistory']);
    final audit = _asListOfMaps(r['auditTrail']);

    _showDetailSheet(
      title: '${_asStr(r['name'])} — ${_asStr(r['salaryPeriod'] ?? r['period'])}',
      rows: [
        ('Employee ID', _asStr(r['staffId'])),
        ('Department / Designation', '${_asStr(r['department'])} • ${_asStr(r['designation'])}'),
        ('Joining Date', _asStr(r['joiningDate'], 'Not set')),
        ('Base / Earned Salary', '${_fmtInr(_asNum(r['baseSalary']))} / ${_fmtInr(_asNum(r['earnedSalary']))}'),
        ('Overtime Pay (${r['overtimeHours'] ?? 0}h)', _fmtInr(_asNum(r['overtimePay']))),
        ('Bonuses & Incentives', _fmtInr(_asNum(r['bonus']))),
        ('Allowances', _fmtInr(_asNum(r['allowances']))),
        ('Unpaid Leave Deductions', _fmtInr(_asNum(r['unpaidLeaveDeductions']))),
        ('Late / Shortfall / Break Ded.', '${_fmtInr(_asNum(r['lateDeduction']))} / ${_fmtInr(_asNum(r['shortfallDeduction']))} / ${_fmtInr(_asNum(r['breakDeduction']))}'),
        ('PF Deduction', _asNum(r['pfDeduction']) > 0 ? _fmtInr(_asNum(r['pfDeduction'])) : 'Not configured (₹0)'),
        ('Total Deductions', _fmtInr(_asNum(r['totalDeductions']))),
        ('Net Payable', _fmtInr(_asNum(r['totalAmount'] ?? r['netSalary']))),
        ('Paid / Pending', '${_fmtInr(_asNum(r['amountPaid']))} / ${_fmtInr(_asNum(r['pendingAmount']))}'),
        ('Payment Status', _asStr(r['paymentStatus']).toUpperCase()),
        if (_asStr(r['lastPaidAt']).isNotEmpty) ('Last Payment Date', _asStr(r['lastPaidAt'])),
        ...adjs.map((a) => ('Adjustment (${_asStr(a['type'])})', '${_fmtInr(_asNum(a['amount']))} — ${_asStr(a['reason'])}')),
        ...txs.map((t) => ('Payment (${_asStr(t['paymentMethod'])})', '${_fmtInr(_asNum(t['amount']))} on ${_asStr(t['paidAt']).split('T').first} • Ref ${_asStr(t['referenceId'])}')),
        ...audit.map((a) => ('Audit: ${_asStr(a['action'])}', '${_asStr(a['performedBy'])} at ${_asStr(a['timestamp'])}')),
      ],
    );
  }

  void _showTaskDetailSheet(Map<String, dynamic> t) {
    final updates = _asListOfMaps(t['progressUpdates']);
    final history = _asListOfMaps(t['activityHistory']);
    final comp = t['completionReport'] is Map ? t['completionReport'] as Map : null;
    final ext = t['extensionRequest'] is Map ? t['extensionRequest'] as Map : null;

    _showDetailSheet(
      title: _asStr(t['taskTitle']),
      rows: [
        ('Task ID', _asStr(t['id'])),
        ('Description', _asStr(t['description'], '--')),
        ('Assigned Employee', '${_asStr(t['employeeName'])} (${_asStr(t['employeeId'])})'),
        ('Department / Assigned By', '${_asStr(t['department'])} • By ${_asStr(t['assignorName'])}'),
        ('Status / Priority', '${_asStr(t['status'])} • ${_asStr(t['priority']).toUpperCase()} (${t['progressPercentage'] ?? 0}%)'),
        ('Created / Start / Due', '${_asStr(t['createdDate'], '--')} / ${_asStr(t['startDate'], '--')} / ${_asStr(t['dueDate'], '--')}'),
        ('Completed / Working Time', '${_asStr(t['completedDate'], '--')} • ${_asStr(t['workingTime'], '--')}'),
        if (t['isOverdue'] == true) ('Overdue Duration', _asStr(t['overdueLabel'])),
        if (comp != null && _asStr(comp['reportText']).isNotEmpty)
          ('Completion Report', _asStr(comp['reportText'])),
        if (ext != null && _asStr(ext['status'], 'none') != 'none')
          ('Extension (${_asStr(ext['status'])})', '${_asStr(ext['requestedDueDate'])}: ${_asStr(ext['reason'])}'),
        ...updates.map((u) => ('Progress (${u['percentage'] ?? 0}%)', '${_asStr(u['date'])}: ${_asStr(u['updateText'])}')),
        ...history.map((h) => ('Event: ${_asStr(h['type'])}', '${_asStr(h['timestamp'])} • ${_asStr(h['detail'])}')),
      ],
    );
  }

  void _showProjectDetailSheet(Map<String, dynamic> p) {
    final contribs = _asListOfMaps(p['employeeContributions']);
    final tasks = _asListOfMaps(p['tasks']);
    final history = _asListOfMaps(p['activityHistory']);

    _showDetailSheet(
      title: _asStr(p['name']),
      rows: [
        ('Project ID', _asStr(p['id'])),
        ('Description', _asStr(p['description'], '--')),
        ('Manager / Status', '${_asStr(p['projectManager'])} • ${_asStr(p['status']).toUpperCase()}'),
        ('Start / Due Date', '${_asStr(p['startDate'], '--')} → ${_asStr(p['dueDate'], '--')}'),
        if (p['isDelayed'] == true) ('Project Delay', 'Overdue by ${p['overdueDays']} days'),
        ...contribs.map((c) => (
              'Member: ${_asStr(c['name'])} (${_asStr(c['department'])})',
              'Tasks ${c['completedTasks']}/${c['assignedTasks']} done • ${c['overdueTasks']} overdue • ${c['avgProgress']}% avg',
            )),
        ...tasks.map((t) => (
              'Task: ${_asStr(t['title'])}',
              '${_asStr(t['employeeName'])} • ${_asStr(t['status'])} • ${t['progressPercentage'] ?? 0}%',
            )),
        ...history.take(30).map((h) => ('Timeline: ${_asStr(h['type'])}', '${_asStr(h['timestamp'])} • ${_asStr(h['detail'])}')),
      ],
    );
  }

  void _showDetailSheet({required String title, required List<(String, String)> rows}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.94,
        expand: false,
        builder: (_, ctrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                controller: ctrl,
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                separatorBuilder: (_, _) => const Divider(height: 14),
                itemBuilder: (_, i) => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 135,
                      child: Text(
                        rows[i].$1,
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: CeladonColors.textMuted),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        rows[i].$2,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CeladonColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
