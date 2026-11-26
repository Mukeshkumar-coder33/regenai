import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regen_mobile/core/widgets/regen_page_header.dart';
import 'package:regen_mobile/features/auth/data/user_model.dart';
import 'package:regen_mobile/features/company/presentation/company_payroll_view.dart';
import 'package:regen_mobile/features/dashboard/data/dashboard_service.dart';
import 'package:regen_mobile/features/dashboard/presentation/employee_payroll_view.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'regen_jwt_token': 'tok'});
  });

  testWidgets('ReGenPageHeader renders canonical Calendar-aligned title & subtitle with back icon', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              child: ReGenPageHeader(
                title: 'Calendar',
                subtitle: 'View schedule, holidays and company events.',
                onBack: () => tapped = true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('View schedule, holidays and company events.'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    expect(tapped, isTrue);
  });

  testWidgets('CompanyPayrollView renders at narrow 360px phone width without RenderFlex overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: CompanyPayrollView(
          embedded: false,
          onBack: () {},
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Company Payroll'), findsOneWidget);
  });

  testWidgets('EmployeePayrollView displays dynamic Late, Break, Shortfall and Leave deductions cleanly', (tester) async {
    final mockClient = MockClient((req) async {
      if (req.url.path.contains('/api/payroll/my-records')) {
        return http.Response(
          jsonEncode({
            'payroll': {
              'month': '2026-11',
              'baseSalary': 30000,
              'earnedSalary': 27500,
              'hourlyOvertimeAddition': 500,
              'bonus': 1000,
              'lateDeduction': 400,
              'totalBreakDeduction': 20,
              'hourlyShortfallDeduction': 380,
              'approvedLeaveDeduction': 200,
              'unapprovedLeaveDeduction': 2000,
              'manualDeduction': 0,
              'totalDeductions': 3000,
              'totalAmount': 28500,
              'netPayable': 28500,
              'amountPaid': 10000,
              'pendingAmount': 18500,
              'paymentStatus': 'partially_paid',
              'dailyBreakdown': [
                {
                  'date': '2026-11-10',
                  'lateDeduction': 400,
                  'explanation': 'November 10 — Present (Late 35m: -₹400) — ₹400 deduction',
                },
              ],
            },
            'transactions': [],
            'adjustments': [],
            'pendingMonths': [],
            'totalPendingBalance': 18500,
            'history': [],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('{}', 200);
    });

    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: EmployeePayrollView(
          embedded: false,
          user: const UserModel(
            id: 'u1',
            userId: 'EMP1',
            username: 'emp1',
            name: 'Emp One',
            role: 'staff',
            token: 'tok',
          ),
          dashboardService: DashboardService(client: mockClient),
          onBack: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Payroll'), findsOneWidget);
    expect(find.text('-₹400'), findsOneWidget);
    expect(find.text('-₹20'), findsOneWidget);
    expect(find.text('-₹380'), findsOneWidget);
    expect(find.text('-₹2,200'), findsOneWidget);
    expect(find.text('-₹3,000'), findsOneWidget);
  });
}
