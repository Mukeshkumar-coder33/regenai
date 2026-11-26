import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:regen_mobile/features/company/data/company_report_service.dart';
import 'package:regen_mobile/features/company/data/report_exporter.dart';
import 'package:regen_mobile/features/company/presentation/company_reports_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Company Historical Reports', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({'regen_jwt_token': 'test_tok'});
    });

    test('Query builder sets scope=general for General Tasks and all filters', () {
      final params = CompanyReportService.buildQueryParams(
        type: CompanyReportType.generalTask,
        period: 'range',
        startDate: '2025-01-01',
        endDate: '2026-11-25',
        employeeId: 'EMP01',
        department: 'Engineering',
        status: 'overdue',
        priority: 'high',
        search: 'audit',
        page: 2,
        limit: 25,
      );

      expect(params['scope'], 'general');
      expect(params['period'], 'range');
      expect(params['startDate'], '2025-01-01');
      expect(params['endDate'], '2026-11-25');
      expect(params['employeeId'], 'EMP01');
      expect(params['department'], 'Engineering');
      expect(params['status'], 'overdue');
      expect(params['priority'], 'high');
      expect(params['search'], 'audit');
      expect(params['page'], '2');
      expect(params['limit'], '25');
    });

    test('ReportExporter generates valid Excel XML and Printable HTML across report types', () {
      final attData = {
        'companyName': 'Krish Tech & Co',
        'periodLabel': 'All History (2024-01-01 to 2026-11-25)',
        'totalRecords': 1,
        'totalWorkingHours': 9.5,
        'totalOvertimeHours': 1.5,
        'presentCount': 1,
        'lateCount': 0,
        'halfDayCount': 0,
        'absentCount': 0,
        'leaveCount': 0,
        'holidayCount': 0,
        'records': [
          {
            'date': '2026-10-12',
            'weekday': 'Monday',
            'staffId': 'EMP01',
            'name': 'Arun <Lead>',
            'department': 'R&D',
            'designation': 'Engineer',
            'joiningDate': '2024-02-01',
            'status': 'present',
            'checkInDisplay': '09:25 AM',
            'checkOutDisplay': '07:55 PM',
            'workingHours': 9.5,
            'lateMinutes': 0,
            'earlyDepartureMinutes': 0,
            'overtimeHours': 1.5,
            'breakMinutes': 60,
            'casualBreakMinutes': 15,
            'totalBreakDelayMinutes': 0,
            'workMode': 'office',
            'location': 'HQ',
            'notes': 'Clean shift',
          },
        ],
      };

      final table = ReportExporter.buildTableData(CompanyReportType.attendance, attData);
      final xls = ReportExporter.buildExcelXmlContent(table);
      final html = ReportExporter.buildPrintableHtml(table);

      expect(xls, contains('<Workbook'));
      expect(xls, contains('Arun &lt;Lead&gt;'));
      expect(xls, contains('R&amp;D'));
      expect(html, contains('<table>'));
      expect(html, contains('Krish Tech &amp; Co'));
      expect(html, contains('@media print'));
    });

    testWidgets('CompanyReportsView renders 4 report tabs and loads mock historical records', (tester) async {
      final requestedPaths = <String>[];
      final mockClient = MockClient((req) async {
        requestedPaths.add(req.url.path);
        if (req.url.path.endsWith('/api/attendance/report')) {
          return http.Response(
            jsonEncode({
              'companyName': 'Test Corp',
              'period': 'all',
              'periodLabel': 'All History (2024-01-01 to 2026-11-25)',
              'earliestRecordDate': '2024-01-01',
              'totalRecords': 1,
              'totalWorkingHours': 8.5,
              'totalOvertimeHours': 0.5,
              'presentCount': 1,
              'lateCount': 0,
              'halfDayCount': 0,
              'absentCount': 0,
              'leaveCount': 0,
              'holidayCount': 0,
              'totalLateMinutes': 0,
              'employees': [
                {'userId': 'E1', 'name': 'Priya', 'status': 'active'},
                {'userId': 'E2', 'name': 'Former Staff', 'status': 'inactive'},
              ],
              'departments': ['Engineering'],
              'records': [
                {
                  'id': 'a1',
                  'date': '2024-03-10',
                  'weekday': 'Sunday',
                  'userId': 'E1',
                  'staffId': 'EMP-1',
                  'name': 'Priya',
                  'department': 'Engineering',
                  'designation': 'Developer',
                  'joiningDate': '2024-01-15',
                  'employeeStatus': 'active',
                  'status': 'present',
                  'checkInDisplay': '09:30 AM',
                  'checkOutDisplay': '06:30 PM',
                  'workingHours': 8.5,
                  'overtimeHours': 0.5,
                  'lateMinutes': 0,
                  'breakMinutes': 60,
                  'casualBreakMinutes': 10,
                  'totalBreakDelayMinutes': 0,
                  'workMode': 'office',
                  'location': 'Main Office',
                },
              ],
              'employeeSummaries': [],
              'pagination': {'page': 1, 'totalPages': 1, 'total': 1},
            }),
            200,
          );
        }
        if (req.url.path.endsWith('/api/payroll/report')) {
          return http.Response(
            jsonEncode({
              'companyName': 'Test Corp',
              'period': 'all',
              'periodLabel': 'All History',
              'totalEmployees': 1,
              'companyTotalNetPayable': 45000,
              'companyOverallAmountPaid': 45000,
              'companyOverallPendingAmount': 0,
              'companyOverallBonuses': 2000,
              'companyOverallOvertimePay': 500,
              'companyOverallDeductions': 1000,
              'companyOverallPfDeductions': 0,
              'employees': [],
              'departments': [],
              'records': [
                {
                  'id': 'p1',
                  'salaryPeriod': '2026-10',
                  'userId': 'E1',
                  'staffId': 'EMP-1',
                  'name': 'Priya',
                  'department': 'Engineering',
                  'designation': 'Developer',
                  'joiningDate': '2024-01-15',
                  'baseSalary': 44000,
                  'bonus': 2000,
                  'overtimePay': 500,
                  'unpaidLeaveDeductions': 500,
                  'totalDeductions': 1000,
                  'totalAmount': 45000,
                  'amountPaid': 45000,
                  'pendingAmount': 0,
                  'paymentStatus': 'paid',
                },
              ],
              'transactions': [],
              'pagination': {'page': 1, 'totalPages': 1, 'total': 1},
            }),
            200,
          );
        }
        if (req.url.path.endsWith('/api/tasks/report')) {
          return http.Response(
            jsonEncode({
              'companyName': 'Test Corp',
              'period': 'all',
              'periodLabel': 'All History',
              'totalTasks': 1,
              'totalCompleted': 1,
              'overallCompletionRate': 100,
              'totalInProgress': 0,
              'totalTodo': 0,
              'totalOverdue': 0,
              'totalNotCompleted': 0,
              'employeeOptions': [],
              'departments': [],
              'records': [
                {
                  'id': 't1',
                  'taskTitle': 'Audit Payroll Schema',
                  'employeeName': 'Priya',
                  'employeeId': 'EMP-1',
                  'department': 'Engineering',
                  'assignorName': 'Admin',
                  'priority': 'high',
                  'createdDate': '2026-10-01',
                  'dueDate': '2026-10-05',
                  'progressPercentage': 100,
                  'status': 'Completed',
                  'isOverdue': false,
                },
              ],
              'pagination': {'page': 1, 'totalPages': 1, 'total': 1},
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'companyName': 'Test Corp',
            'period': 'all',
            'periodLabel': 'All History',
            'totalProjects': 1,
            'activeProjects': 1,
            'completedProjects': 0,
            'delayedProjects': 0,
            'totalProjectTasks': 4,
            'completedProjectTasks': 3,
            'overallCompletionRate': 75,
            'projectOptions': [{'id': 'pr1', 'name': 'ReGen Mobile'}],
            'employees': [],
            'departments': ['Engineering'],
            'projects': [
              {
                'id': 'pr1',
                'name': 'ReGen Mobile',
                'projectManager': 'Admin',
                'status': 'active',
                'priority': 'high',
                'startDate': '2025-01-10',
                'dueDate': '2027-01-10',
                'isDelayed': false,
                'overdueDays': 0,
                'departments': ['Engineering'],
                'taskMetrics': {'total': 4, 'completed': 3, 'pending': 1, 'completionRate': 75},
                'tasks': [],
                'employeeContributions': [],
                'activityHistory': [],
              },
            ],
            'records': [],
            'pagination': {'page': 1, 'totalPages': 1, 'total': 1},
          }),
          200,
        );
      });

      final service = CompanyReportService(client: mockClient);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompanyReportsView(reportService: service),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Company Historical Reports'), findsOneWidget);
      expect(find.text('Attendance'), findsOneWidget);
      expect(find.text('Payments'), findsOneWidget);
      expect(find.text('General Tasks'), findsOneWidget);
      expect(find.text('Projects'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.textContaining('Priya (EMP-1)'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Priya (EMP-1)'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Payments'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Payments'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('Priya • 2026-10'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Priya • 2026-10'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('General Tasks'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('General Tasks'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Audit Payroll Schema'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Audit Payroll Schema'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Projects'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Projects'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('ReGen Mobile'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('ReGen Mobile'), findsOneWidget);

      expect(requestedPaths, containsAll([
        '/api/attendance/report',
        '/api/payroll/report',
        '/api/tasks/report',
        '/api/projects/report',
      ]));
    });

    testWidgets('CompanyReportsView renders on narrow 360px phone without RenderFlex overflow across tabs and toggles', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final mockClient = MockClient((req) async {
        final path = req.url.path;
        if (path.endsWith('/api/attendance/report')) {
          return http.Response(
            jsonEncode({
              'periodLabel': 'All Historical Records',
              'earliestRecordDate': '2023-01-01',
              'totalRecords': 250,
              'totalWorkingHours': 1850,
              'totalOvertimeHours': 142.5,
              'presentCount': 210,
              'lateCount': 18,
              'totalLateMinutes': 340,
              'absentCount': 12,
              'leaveCount': 10,
              'employees': [
                {'userId': 'EMP-1', 'name': 'Very Long Employee Name For Narrow Screen Check', 'status': 'active'},
              ],
              'departments': ['Research and Product Engineering Division'],
              'records': [
                {
                  'name': 'Very Long Employee Name For Narrow Screen Check',
                  'staffId': 'EMP-1001',
                  'department': 'Engineering',
                  'date': '2026-11-20',
                  'weekday': 'Friday',
                  'joiningDate': '2023-01-10',
                  'status': 'late',
                  'checkInDisplay': '10:15 AM',
                  'checkOutDisplay': '07:15 PM',
                  'workingHours': 8,
                  'lateMinutes': 45,
                  'breakMinutes': 60,
                  'casualBreakMinutes': 15,
                  'totalBreakDelayMinutes': 10,
                },
              ],
              'employeeSummaries': [
                {
                  'name': 'Very Long Employee Name For Narrow Screen Check',
                  'staffId': 'EMP-1001',
                  'department': 'Engineering',
                  'designation': 'Senior Engineer',
                  'joiningDate': '2023-01-10',
                  'employeeStatus': 'active',
                  'totalShifts': 120,
                  'presentCount': 110,
                  'lateCount': 12,
                  'totalLateMinutes': 180,
                  'halfDayCount': 2,
                  'absentCount': 5,
                  'leaveDays': 3,
                  'totalWorkingHours': 940,
                  'totalOvertimeHours': 24,
                  'totalBreakDelayMinutes': 40,
                },
              ],
              'pagination': {'page': 2, 'totalPages': 10, 'total': 250},
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response(
          jsonEncode({
            'periodLabel': 'All Historical Records',
            'totalEmployees': 12,
            'companyTotalNetPayable': 1250000,
            'companyOverallAmountPaid': 900000,
            'companyOverallPendingAmount': 350000,
            'companyOverallBonuses': 25000,
            'companyOverallOvertimePay': 12000,
            'companyOverallDeductions': 185000,
            'companyOverallPfDeductions': 18000,
            'records': [
              {
                'name': 'Chiro Kumar Long Name For Mobile Check',
                'staffId': 'KRI-882822',
                'department': 'Engineering',
                'designation': 'Developer',
                'joiningDate': '2026-10-28',
                'salaryPeriod': '2026-11',
                'baseSalary': 100000,
                'totalAmount': 25000,
                'amountPaid': 0,
                'pendingAmount': 25000,
                'overtimePay': 500,
                'bonus': 1000,
                'unpaidLeaveDeductions': 75000,
                'lateDeduction': 1200,
                'shortfallDeduction': 300,
                'breakDeduction': 0,
                'manualDeduction': 0,
                'pfDeduction': 0,
                'totalDeductions': 76500,
                'paymentStatus': 'partially_paid',
              },
            ],
            'transactions': [],
            'projects': [],
            'pagination': {'page': 1, 'totalPages': 5, 'total': 125},
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompanyReportsView(
              reportService: CompanyReportService(client: mockClient),
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Toggle Attendance Employee Totals (Joining Date) on 360px screen
      await tester.scrollUntilVisible(
        find.text('Employee Totals (Joining Date)'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Employee Totals (Joining Date)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Employee Totals (Joining Date)'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Switch to Payments tab and check deduction tags + sub-view toggle on 360px screen
      await tester.scrollUntilVisible(
        find.text('Payments'),
        -150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Payments'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Payments'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.textContaining('Leave -₹75,000'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Leave -₹75,000'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
