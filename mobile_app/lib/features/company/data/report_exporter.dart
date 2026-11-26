import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'company_report_service.dart';

/// Structured tabular representation shared across CSV, Excel, and Print export.
class ReportTableData {
  final String title;
  final String companyName;
  final String periodLabel;
  final List<String> summaryLines;
  final List<String> headers;
  final List<List<String>> rows;

  const ReportTableData({
    required this.title,
    required this.companyName,
    required this.periodLabel,
    required this.summaryLines,
    required this.headers,
    required this.rows,
  });
}

/// Handles CSV, Microsoft Excel SpreadsheetML (.xls), and Print-ready HTML export
/// cleanly on Android & Windows without extra third-party binary packages.
abstract final class ReportExporter {
  static String _xmlEscape(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static String _htmlEscape(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  /// Extracts uniform structured table data for any of the 4 report types.
  static ReportTableData buildTableData(
    CompanyReportType type,
    Map<String, dynamic> data,
  ) {
    final companyName = (data['companyName'] ?? 'Company').toString();
    final periodLabel = (data['periodLabel'] ?? 'All History').toString();
    final rawRecords = data['records'] is List ? data['records'] as List : const [];
    final records = rawRecords.whereType<Map<String, dynamic>>().toList();

    switch (type) {
      case CompanyReportType.attendance:
        return ReportTableData(
          title: 'Attendance Report',
          companyName: companyName,
          periodLabel: periodLabel,
          summaryLines: [
            'Total Records: ${data['totalRecords'] ?? records.length}',
            'Total Hours: ${data['totalWorkingHours'] ?? 0}h',
            'Overtime: ${data['totalOvertimeHours'] ?? 0}h',
            'Present: ${data['presentCount'] ?? 0} | Late: ${data['lateCount'] ?? 0} | Half Day: ${data['halfDayCount'] ?? 0} | Absent: ${data['absentCount'] ?? 0}',
            'Leaves: ${data['leaveCount'] ?? 0} | Holidays: ${data['holidayCount'] ?? 0}',
          ],
          headers: const [
            'Date', 'Weekday', 'Employee ID', 'Name', 'Department', 'Designation',
            'Joining Date', 'Status', 'Check In', 'Check Out', 'Hours', 'Late (m)',
            'Early Out (m)', 'OT (h)', 'Lunch Break (m)', 'Casual Break (m)',
            'Break Delay (m)', 'Mode', 'Location', 'Notes',
          ],
          rows: records.map((r) => [
            (r['date'] ?? '').toString(),
            (r['weekday'] ?? '').toString(),
            (r['staffId'] ?? r['userId'] ?? '').toString(),
            (r['name'] ?? '').toString(),
            (r['department'] ?? '').toString(),
            (r['designation'] ?? '').toString(),
            (r['joiningDate'] ?? '').toString(),
            (r['status'] ?? '').toString(),
            (r['checkInDisplay'] ?? '--').toString(),
            (r['checkOutDisplay'] ?? '--').toString(),
            (r['workingHours'] ?? 0).toString(),
            (r['lateMinutes'] ?? 0).toString(),
            (r['earlyDepartureMinutes'] ?? 0).toString(),
            (r['overtimeHours'] ?? 0).toString(),
            (r['breakMinutes'] ?? 0).toString(),
            (r['casualBreakMinutes'] ?? 0).toString(),
            (r['totalBreakDelayMinutes'] ?? 0).toString(),
            (r['workMode'] ?? '').toString(),
            (r['location'] ?? '').toString(),
            (r['notes'] ?? '').toString(),
          ]).toList(),
        );

      case CompanyReportType.payment:
        return ReportTableData(
          title: 'Payment & Payroll Report',
          companyName: companyName,
          periodLabel: periodLabel,
          summaryLines: [
            'Records: ${data['totalEmployees'] ?? records.length} (Paid: ${data['fullyPaidEmployees'] ?? 0}, Pending: ${data['pendingEmployees'] ?? 0})',
            'Base Salary: INR ${data['companyOverallBaseSalary'] ?? 0}',
            'Net Payable: INR ${data['companyTotalNetPayable'] ?? 0}',
            'Paid: INR ${data['companyOverallAmountPaid'] ?? 0} | Pending: INR ${data['companyOverallPendingAmount'] ?? 0}',
            'Bonuses: INR ${data['companyOverallBonuses'] ?? 0} | Deductions: INR ${data['companyOverallDeductions'] ?? 0}',
          ],
          headers: const [
            'Period', 'Employee ID', 'Name', 'Department', 'Designation',
            'Joining Date', 'Base Salary', 'Overtime Pay', 'Bonus',
            'Unpaid Leave Ded.', 'Other Deductions', 'PF Ded.', 'Total Deductions',
            'Net Payable', 'Amount Paid', 'Pending', 'Status', 'Last Paid',
          ],
          rows: records.map((r) {
            final totalDed = (num.tryParse('${r['totalDeductions'] ?? 0}') ?? 0);
            final leaveDed = (num.tryParse('${r['unpaidLeaveDeductions'] ?? 0}') ?? 0);
            final pfDed = (num.tryParse('${r['pfDeduction'] ?? 0}') ?? 0);
            final otherDed = (totalDed - leaveDed - pfDed).clamp(0, double.infinity);
            return [
              (r['salaryPeriod'] ?? r['period'] ?? '').toString(),
              (r['staffId'] ?? r['userId'] ?? '').toString(),
              (r['name'] ?? '').toString(),
              (r['department'] ?? '').toString(),
              (r['designation'] ?? '').toString(),
              (r['joiningDate'] ?? '').toString(),
              (r['baseSalary'] ?? 0).toString(),
              (r['overtimePay'] ?? 0).toString(),
              (r['bonus'] ?? 0).toString(),
              leaveDed.toStringAsFixed(2),
              otherDed.toStringAsFixed(2),
              pfDed.toStringAsFixed(2),
              totalDed.toStringAsFixed(2),
              (r['totalAmount'] ?? r['netSalary'] ?? 0).toString(),
              (r['amountPaid'] ?? 0).toString(),
              (r['pendingAmount'] ?? 0).toString(),
              (r['paymentStatus'] ?? 'unpaid').toString(),
              (r['lastPaidAt'] ?? '').toString().split('T').first,
            ];
          }).toList(),
        );

      case CompanyReportType.generalTask:
        return ReportTableData(
          title: 'General Task Report',
          companyName: companyName,
          periodLabel: periodLabel,
          summaryLines: [
            'Total Tasks: ${data['totalTasks'] ?? records.length}',
            'Completed: ${data['totalCompleted'] ?? 0} (${data['overallCompletionRate'] ?? 0}%)',
            'In Progress: ${data['totalInProgress'] ?? 0} | To Do: ${data['totalTodo'] ?? 0}',
            'Overdue: ${data['totalOverdue'] ?? 0} | Not Completed: ${data['totalNotCompleted'] ?? 0}',
          ],
          headers: const [
            'Task ID', 'Task Name', 'Description', 'Employee', 'Employee ID',
            'Department', 'Assigned By', 'Priority', 'Progress %', 'Created Date',
            'Due Date', 'Completed Date', 'Working Time', 'Status', 'Overdue',
          ],
          rows: records.map((r) => [
            (r['id'] ?? '').toString(),
            (r['taskTitle'] ?? r['title'] ?? '').toString(),
            (r['description'] ?? '').toString(),
            (r['employeeName'] ?? '').toString(),
            (r['employeeId'] ?? '').toString(),
            (r['department'] ?? '').toString(),
            (r['assignorName'] ?? '').toString(),
            (r['priority'] ?? 'medium').toString(),
            '${r['progressPercentage'] ?? 0}%',
            (r['createdDate'] ?? '').toString(),
            (r['dueDate'] ?? '').toString(),
            (r['completedDate'] ?? '').toString(),
            (r['workingTime'] ?? '').toString(),
            (r['status'] ?? '').toString(),
            (r['overdueLabel'] ?? '').toString().isNotEmpty ? (r['overdueLabel'] ?? '').toString() : 'On Time',
          ]).toList(),
        );

      case CompanyReportType.project:
        final projectList = (data['projects'] is List ? data['projects'] as List : records)
            .whereType<Map<String, dynamic>>()
            .toList();
        return ReportTableData(
          title: 'Project Report',
          companyName: companyName,
          periodLabel: periodLabel,
          summaryLines: [
            'Total Projects: ${data['totalProjects'] ?? projectList.length}',
            'Active: ${data['activeProjects'] ?? 0} | Completed: ${data['completedProjects'] ?? 0} | Delayed: ${data['delayedProjects'] ?? 0}',
            'Project Tasks Completed: ${data['completedProjectTasks'] ?? 0} / ${data['totalProjectTasks'] ?? 0} (${data['overallCompletionRate'] ?? 0}%)',
          ],
          headers: const [
            'Project ID', 'Project Name', 'Manager', 'Departments', 'Team Size',
            'Start Date', 'Due Date', 'Status', 'Priority', 'Delayed',
            'Overdue Days', 'Total Tasks', 'Completed', 'Pending', 'Progress %',
          ],
          rows: projectList.map((p) {
            final metrics = p['taskMetrics'] is Map ? p['taskMetrics'] as Map : const {};
            final depts = p['departments'] is List
                ? (p['departments'] as List).join(', ')
                : (p['departments'] ?? '').toString();
            final teamSize = p['assignedEmployees'] is List
                ? (p['assignedEmployees'] as List).length
                : (p['teamCount'] ?? 0);
            final totalTasks = metrics['total'] ?? p['totalTasks'] ?? 0;
            final completedTasks = metrics['completed'] ?? p['completedTasks'] ?? 0;
            final pendingTasks = metrics['pending'] ?? p['pendingTasks'] ?? 0;
            final compRate = metrics['completionRate'] ?? p['completionRate'] ?? 0;
            return [
              (p['id'] ?? '').toString(),
              (p['name'] ?? '').toString(),
              (p['projectManager'] ?? p['createdBy'] ?? '').toString(),
              depts.isNotEmpty ? depts : 'General',
              teamSize.toString(),
              (p['startDate'] ?? '').toString(),
              (p['dueDate'] ?? '').toString(),
              (p['status'] ?? '').toString(),
              (p['priority'] ?? 'medium').toString(),
              p['isDelayed'] == true ? 'Yes' : 'No',
              (p['overdueDays'] ?? 0).toString(),
              totalTasks.toString(),
              completedTasks.toString(),
              pendingTasks.toString(),
              '$compRate%',
            ];
          }).toList(),
        );
    }
  }

  /// Generates Excel 2003 SpreadsheetML (.xls) XML string cleanly.
  static String buildExcelXmlContent(ReportTableData table) {
    final sb = StringBuffer();
    sb.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    sb.writeln('<?mso-application progid="Excel.Sheet"?>');
    sb.writeln('<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"');
    sb.writeln(' xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">');
    sb.writeln(' <Styles>');
    sb.writeln('  <Style ss:ID="Title"><Font ss:Bold="1" ss:Size="13"/></Style>');
    sb.writeln('  <Style ss:ID="Header"><Font ss:Bold="1" ss:Color="#FFFFFF"/><Interior ss:Color="#1B7A4A" ss:Pattern="Solid"/></Style>');
    sb.writeln('  <Style ss:ID="Meta"><Font ss:Italic="1" ss:Color="#4B5563"/></Style>');
    sb.writeln(' </Styles>');
    sb.writeln(' <Worksheet ss:Name="Report">');
    sb.writeln('  <Table>');
    sb.writeln('   <Row><Cell ss:StyleID="Title"><Data ss:Type="String">${_xmlEscape('${table.companyName} - ${table.title}')}</Data></Cell></Row>');
    sb.writeln('   <Row><Cell ss:StyleID="Meta"><Data ss:Type="String">${_xmlEscape('Period: ${table.periodLabel} | Generated: ${DateTime.now().toIso8601String()}')}</Data></Cell></Row>');
    for (final line in table.summaryLines) {
      sb.writeln('   <Row><Cell ss:StyleID="Meta"><Data ss:Type="String">${_xmlEscape(line)}</Data></Cell></Row>');
    }
    sb.writeln('   <Row/>');
    sb.write('   <Row>');
    for (final h in table.headers) {
      sb.write('<Cell ss:StyleID="Header"><Data ss:Type="String">${_xmlEscape(h)}</Data></Cell>');
    }
    sb.writeln('</Row>');
    for (final row in table.rows) {
      sb.write('   <Row>');
      for (final cell in row) {
        final asNum = num.tryParse(cell);
        if (asNum != null && !cell.startsWith('0') && !cell.contains('-')) {
          sb.write('<Cell><Data ss:Type="Number">$asNum</Data></Cell>');
        } else {
          sb.write('<Cell><Data ss:Type="String">${_xmlEscape(cell)}</Data></Cell>');
        }
      }
      sb.writeln('</Row>');
    }
    sb.writeln('  </Table>');
    sb.writeln(' </Worksheet>');
    sb.writeln('</Workbook>');
    return sb.toString();
  }

  /// Generates clean print-friendly HTML document with `@media print` styling.
  static String buildPrintableHtml(ReportTableData table) {
    final headersHtml = table.headers.map((h) => '<th>${_htmlEscape(h)}</th>').join();
    final rowsHtml = table.rows
        .map((r) => '<tr>${r.map((c) => '<td>${_htmlEscape(c)}</td>').join()}</tr>')
        .join('\n');
    final summaryHtml = table.summaryLines
        .map((s) => '<div class="kpi">${_htmlEscape(s)}</div>')
        .join('\n');

    return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>${_htmlEscape('${table.companyName} - ${table.title}')}</title>
  <style>
    body { font-family: Arial, sans-serif; color: #111827; margin: 24px; font-size: 12px; }
    h1 { color: #0b5d3b; margin: 0 0 4px; font-size: 20px; }
    .meta { color: #4b5563; margin-bottom: 12px; }
    .summary { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 16px; }
    .kpi { background: #ecfdf5; border: 1px solid #a7f3d0; padding: 6px 10px; border-radius: 6px; font-weight: 600; }
    table { width: 100%; border-collapse: collapse; margin-top: 8px; }
    th { background: #0b5d3b; color: #ffffff; text-align: left; padding: 7px 8px; border: 1px solid #d1d5db; font-size: 11px; }
    td { padding: 6px 8px; border: 1px solid #e5e7eb; font-size: 11px; vertical-align: top; }
    tr:nth-child(even) td { background: #f9fafb; }
    @media print { body { margin: 8mm; } }
  </style>
</head>
<body>
  <h1>${_htmlEscape(table.companyName)} — ${_htmlEscape(table.title)}</h1>
  <div class="meta">Period: ${_htmlEscape(table.periodLabel)} • Generated: ${_htmlEscape(DateTime.now().toString())}</div>
  <div class="summary">$summaryHtml</div>
  <table>
    <thead><tr>$headersHtml</tr></thead>
    <tbody>$rowsHtml</tbody>
  </table>
</body>
</html>''';
  }

  /// Writes text content with UTF-8 BOM (for CSV/Excel/HTML) to device storage cleanly.
  static Future<String> saveReportFile({
    required String filenamePrefix,
    required String extension,
    required String content,
    bool includeUtf8Bom = true,
  }) async {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      await [Permission.storage].request();
    }

    String targetDir;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (await downloadDir.exists()) {
        targetDir = downloadDir.path;
      } else {
        final extDir = await getExternalStorageDirectory();
        targetDir = extDir?.path ?? (await getApplicationDocumentsDirectory()).path;
      }
    } else if (!kIsWeb) {
      final downloads = await getDownloadsDirectory();
      targetDir = downloads?.path ?? (await getApplicationDocumentsDirectory()).path;
    } else {
      throw UnsupportedError('File write unsupported on Web without anchor trigger');
    }

    final safePrefix = filenamePrefix.replaceAll(RegExp(r'[^\w\.\-]'), '_');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('$targetDir/${safePrefix}_$stamp.$extension');

    final bytes = <int>[
      if (includeUtf8Bom) ...[0xEF, 0xBB, 0xBF],
      ...utf8.encode(content),
    ];
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
