import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regen_mobile/features/attendance/data/attendance_model.dart';
import 'package:regen_mobile/features/attendance/data/attendance_report_model.dart';
import 'package:regen_mobile/features/attendance/data/work_schedule_model.dart';
import 'package:regen_mobile/features/attendance/presentation/attendance_view.dart';
import 'package:regen_mobile/features/auth/data/auth_service.dart';
import 'package:regen_mobile/features/auth/data/user_model.dart';
import 'package:regen_mobile/features/auth/presentation/login_screen.dart';
import 'package:regen_mobile/features/calendar/data/holiday_model.dart';
import 'package:regen_mobile/features/calendar/presentation/calendar_view.dart';
import 'package:regen_mobile/features/company/data/company_model.dart';
import 'package:regen_mobile/features/company/presentation/company_dashboard_view.dart';
import 'package:regen_mobile/features/dashboard/data/dashboard_service.dart';
import 'package:regen_mobile/features/dashboard/data/leave_model.dart';
import 'package:regen_mobile/features/dashboard/presentation/dashboard_screen.dart';
import 'package:regen_mobile/features/dashboard/presentation/employee_dashboard_view.dart';
import 'package:regen_mobile/features/superadmin/presentation/superadmin_dashboard_view.dart';
import 'package:regen_mobile/features/tasks/data/task_model.dart';
import 'package:regen_mobile/features/tasks/data/project_model.dart';
import 'package:regen_mobile/features/tasks/presentation/tasks_view.dart';
import 'package:regen_mobile/features/profile/presentation/profile_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockDashboardService extends DashboardService {
  @override
  Future<List<CompanyModel>> getCompanies({bool isSuperAdmin = false}) async {
    if (isSuperAdmin) {
      return const [
        CompanyModel(id: 'c1', name: 'krish', city: 'Chennai', status: 'active'),
        CompanyModel(id: 'c2', name: 'Zevox Medice', city: 'Madurai', status: 'active'),
        CompanyModel(id: 'c3', name: 'krish Tech Computer', city: 'Coimbatore', status: 'active'),
      ];
    }
    return const [
      CompanyModel(id: 'c3', name: 'krish Tech Computer', city: 'Coimbatore', status: 'active'),
    ];
  }

  @override
  Future<List<UserModel>> getUsers({bool isSuperAdmin = false}) async {
    if (isSuperAdmin) {
      return const [
        UserModel(id: 'u1', userId: 'Vyshwa', username: 'Vyshwa', name: 'Vyshwa', role: 'owner', token: 't1', department: 'Operations'),
        UserModel(id: 'u2', userId: 'Ram', username: 'Ram', name: 'Ram', role: 'staff', token: 't2', department: 'Tech'),
      ];
    }
    return const [
      UserModel(id: 'u1', userId: 'Vyshwa', username: 'Vyshwa', name: 'Vyshwa', role: 'owner', token: 't1', department: 'Operations'),
      UserModel(id: 'u2', userId: 'Eswaran', username: 'eswaran', name: 'eswaran M', role: 'staff', token: 't2', department: 'Operations'),
    ];
  }

  @override
  Future<List<TaskModel>> getTasks() async {
    return [
      const TaskModel(id: 't1', title: 'UI Design Review', priority: 'High', status: 'pending', dueDate: '2026-10-30'),
    ];
  }

  @override
  Future<List<AttendanceModel>> getAttendance() async {
    return [
      const AttendanceModel(id: 'a1', userId: 'u2', date: '2026-10-29', checkIn: '09:10 AM', status: 'present'),
    ];
  }

  @override
  Future<List<LeaveModel>> getLeaves() async {
    return [];
  }
}

class MockAuthService extends AuthService {
  @override
  Future<UserModel> switchToSuperAdmin() async {
    return const UserModel(
      id: 'sa_1',
      userId: 'Vyshwa',
      username: 'Vyshwa',
      name: 'Vyshwa',
      role: 'param',
      company: 'ReGen Central',
      token: 'jwt_param',
    );
  }

  @override
  Future<UserModel> switchToEms() async {
    return const UserModel(
      id: 'owner_1',
      userId: 'Vyshwa',
      username: 'Vyshwa',
      name: 'Vyshwa',
      role: 'owner',
      company: 'krish Tech Computer',
      token: 'jwt_owner',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('UserModel Role & Architecture Tests', () {
    test('Correctly parses backend employee response', () {
      final json = {
        '_id': '6ad0b21002fc610e0ba4d5fe',
        'userId': 'KRI-112',
        'username': 'ramkumar',
        'name': 'Ram Kumar',
        'role': 'staff',
        'companyId': '6ad0b21002fc610e0ba4d5fe',
        'company': 'krish Tech Computer',
        'token': 'mock_jwt_token',
        'authSource': 'dual:synchronized',
        'mustChangePassword': false,
      };

      final user = UserModel.fromJson(json);

      expect(user.id, '6ad0b21002fc610e0ba4d5fe');
      expect(user.userId, 'KRI-112');
      expect(user.username, 'ramkumar');
      expect(user.role, 'staff');
      expect(user.isEmployee, isTrue);
      expect(user.isSuperAdmin, isFalse);
      expect(user.isCompanyAdmin, isFalse);
      expect(user.canSwitchToSuperAdmin, isFalse);
      expect(user.roleDisplayName, 'Employee');
    });

    test('Identifies Super Admin (param) and Vyshwa mode switching capability', () {
      final paramUser = UserModel.fromJson({
        '_id': 'sa_01',
        'userId': 'sa_param',
        'username': 'superadmin',
        'role': 'param',
        'token': 'sa_jwt',
      });
      expect(paramUser.isSuperAdmin, isTrue);
      expect(paramUser.canSwitchToSuperAdmin, isTrue);
      expect(paramUser.roleDisplayName, 'Super Administrator');

      final vyshwaOwner = UserModel.fromJson({
        '_id': 'vys_01',
        'userId': 'Vyshwa',
        'username': 'Vyshwa',
        'role': 'owner',
        'company': 'krish Tech Computer',
        'token': 'vys_jwt',
      });
      expect(vyshwaOwner.isCompanyAdmin, isTrue);
      expect(vyshwaOwner.isSuperAdmin, isFalse);
      expect(vyshwaOwner.canSwitchToSuperAdmin, isTrue);

      final regularOwner = UserModel.fromJson({
        '_id': 'owner_02',
        'userId': 'zevoxmedice_8cb4',
        'username': 'zevoxmedice_8cb4',
        'role': 'owner',
        'company': 'Zevox Medice',
        'token': 'zev_jwt',
      });
      expect(regularOwner.isCompanyAdmin, isTrue);
      expect(regularOwner.canSwitchToSuperAdmin, isFalse);
    });
  });

  group('Module 1: Login Screen Tests (Matching Website)', () {
    testWidgets('Renders Brand, User ID, Password, Remember me, and Login button',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoginScreen(),
        ),
      );

      // Verify branding and titles
      expect(find.text('ReGen'), findsOneWidget);
      expect(find.text('Sign in to continue'), findsOneWidget);

      // Verify fields
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Remember me'), findsOneWidget);

      // Verify Login button
      expect(find.widgetWithText(ElevatedButton, 'Login'), findsOneWidget);

      // Verify NO third-party SSO or signup links
      expect(find.text('or continue with'), findsOneWidget);
      expect(find.textContaining('Sign Up'), findsWidgets);
      
    });

    testWidgets('Validates empty User ID and Password', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoginScreen(),
        ),
      );

      await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
      await tester.pump();

      expect(find.text('Please enter your email or username'), findsOneWidget);
      expect(find.text('Please enter your password'), findsOneWidget);
    });
  });

  group('Module 2: Role-Based Dashboard Tests', () {
    const staffUser = UserModel(
      id: 'emp_1',
      userId: 'EMP-101',
      username: 'ram',
      name: 'Ram',
      role: 'staff',
      company: 'krish',
      token: 'jwt_ram',
    );

    const regularOwnerUser = UserModel(
      id: 'owner_1',
      userId: 'zevoxmedice_8cb4',
      username: 'zevoxmedice_8cb4',
      name: 'Zevox Medice',
      role: 'owner',
      company: 'Zevox Medice',
      token: 'jwt_zevox',
    );

    const vyshwaOwnerUser = UserModel(
      id: 'vys_1',
      userId: 'Vyshwa',
      username: 'Vyshwa',
      name: 'Vyshwa',
      role: 'owner',
      company: 'krish Tech Computer',
      token: 'jwt_vyshwa',
    );

    const superAdminUser = UserModel(
      id: 'sa_1',
      userId: 'Vyshwa',
      username: 'Vyshwa',
      name: 'Vyshwa',
      role: 'param',
      company: 'ReGen Central',
      token: 'jwt_param',
    );

    testWidgets('Situation A: EmployeeDashboardView displays employee info and dynamic tasks',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EmployeeDashboardView(
            user: staffUser,
            dashboardService: MockDashboardService(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('Ram'), findsWidgets);
      expect(find.text("Today's Tasks"), findsOneWidget);
      expect(find.text('UI Design Review'), findsOneWidget);
    });

    testWidgets('Situation B: Regular Company Owner Dashboard displays company metrics without SuperAdmin switch',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyDashboardView(
            user: regularOwnerUser,
            dashboardService: MockDashboardService(),
            authService: MockAuthService(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('krish Tech Computer'), findsOneWidget);
      expect(find.text('2'), findsWidgets); // 2 users
      expect(find.text('Employees'), findsOneWidget);
      expect(find.text('Departments'), findsOneWidget);
      expect(find.text('Employee Management'), findsOneWidget);

      // Verify NO Super Admin switcher
      expect(find.text('Super Admin Console Available'), findsNothing);
    });

    testWidgets('Situation C: Vyshwa Company Dashboard displays SuperAdmin switch banner',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyDashboardView(
            user: vyshwaOwnerUser,
            dashboardService: MockDashboardService(),
            authService: MockAuthService(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('krish Tech Computer'), findsOneWidget);
      expect(find.text('Super Admin Console Available'), findsOneWidget);
      expect(find.text('Switch to Super Admin Console'), findsOneWidget);
    });

    testWidgets('Situation D: SuperAdminDashboardView displays platform console and switch to EMS',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SuperAdminDashboardView(
            user: superAdminUser,
            dashboardService: MockDashboardService(),
            authService: MockAuthService(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('ReGen Central Console'), findsOneWidget);
      expect(find.text('Switch to Company Workspace'), findsOneWidget);
      expect(find.text('Total Tenants'), findsOneWidget);
      expect(find.text('Global Users'), findsOneWidget);
    });

    testWidgets('DashboardScreen router correctly dispatches by user role',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(
            user: staffUser,
            onLogout: () {},
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify bottom navigation bar
      expect(find.widgetWithText(InkWell, 'Home'), findsOneWidget);
      expect(find.widgetWithText(InkWell, 'Tasks'), findsWidgets);
      expect(find.widgetWithText(InkWell, 'Calendar'), findsOneWidget);
      expect(find.widgetWithText(InkWell, 'Profile'), findsOneWidget);
    });
  });

  group('Milestone 3: Attendance, Geofencing, Breaks & Calendar Tests', () {
    test('AttendanceModel parses live MongoDB document with break and GPS coords', () {
      final doc = {
        '_id': '672049abc123456789012345',
        'id': 'att_101',
        'companyId': '671fc68f9b7c89f548074da8',
        'userId': 'Ram',
        'date': '2026-10-29',
        'status': 'present',
        'checkIn': '2026-10-29T09:10:00.000Z',
        'checkOut': '2026-10-29T18:15:00.000Z',
        'activeBreakType': 'official',
        'breakStart': '2026-10-29T13:00:00.000Z',
        'breakEnd': '2026-10-29T13:50:00.000Z',
        'breakMinutes': 50,
        'breakDelayMinutes': 0,
        'locationCoords': {
          'latitude': 11.011339,
          'longitude': 76.946477,
          'accuracy': 2.5,
          'distance': 3.2,
        },
      };

      final att = AttendanceModel.fromJson(doc);

      expect(att.id, 'att_101');
      expect(att.userId, 'Ram');
      expect(att.date, '2026-10-29');
      expect(att.status, 'present');
      expect(att.isPresent, isTrue);
      expect(att.isCheckedIn, isTrue);
      expect(att.isCheckedOut, isTrue);
      expect(att.activeBreakType, 'official');
      expect(att.isOnOfficialBreak, isTrue);
      expect(att.isOnBreak, isTrue);
      expect(att.breakMinutes, 50);
      expect(att.latitude, 11.011339);
      expect(att.longitude, 76.946477);
      expect(att.distance, 3.2);
    });

    test('WorkScheduleModel parses shift timings and computes weekly off days', () {
      final json = {
        'checkInTime': '09:30',
        'checkOutTime': '18:30',
        'workingHoursPerDay': 8,
        'workingDaysPerWeek': 5,
        'breakTime': 60,
        'casualBreakTime': 15,
        'weeklyOffDays': [0, 6],
      };

      final schedule = WorkScheduleModel.fromJson(json);

      expect(schedule.checkInTime, '09:30');
      expect(schedule.checkOutTime, '18:30');
      expect(schedule.workingHoursPerDay, 8);
      expect(schedule.breakTime, 60);
      expect(schedule.casualBreakTime, 15);

      // 2026-11-01 is Sunday (weekday 7 in Dart, 0 in MongoDB)
      final sunday = DateTime(2026, 11, 1);
      expect(schedule.isWeeklyOff(sunday), isTrue);

      // 2026-11-02 is Monday (weekday 1)
      final monday = DateTime(2026, 11, 2);
      expect(schedule.isWeeklyOff(monday), isFalse);

      final outJson = schedule.toJson();
      expect(outJson['checkInTime'], '09:30');
      expect(outJson['breakTime'], 60);
    });

    test('HolidayModel and AttendanceReportModel correctly map API responses', () {
      final holiday = HolidayModel.fromJson({
        'id': 'h1',
        'name': 'Deepavali',
        'date': '2026-11-08',
      });
      expect(holiday.name, 'Deepavali');
      expect(holiday.date, '2026-11-08');

      final report = AttendanceReportModel.fromJson({
        'companyName': 'krish Tech Computer',
        'period': 'month',
        'periodLabel': 'October 2026',
        'totalRecords': 22,
        'uniqueEmployees': 3,
        'totalWorkingHours': 176.0,
        'averageDailyHours': 8.0,
        'presentCount': 20,
        'lateCount': 2,
        'absentCount': 0,
        'records': [
          {'id': 'r1', 'userId': 'Ram', 'date': '2026-10-29', 'status': 'present'},
        ],
      });

      expect(report.companyName, 'krish Tech Computer');
      expect(report.totalRecords, 22);
      expect(report.totalWorkingHours, 176.0);
      expect(report.presentCount, 20);
      expect(report.records.length, 1);
      expect(report.records.first.userId, 'Ram');
    });

    testWidgets('AttendanceView renders header, segment pills, and calendar structure',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AttendanceView(),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Attendance'), findsOneWidget);
      expect(find.text('Month'), findsOneWidget);
      expect(find.text('Week'), findsOneWidget);
      expect(find.text('List'), findsOneWidget);
      expect(find.text('Check In'), findsWidgets);
    });

    testWidgets('CalendarView renders header, month controls, and Floating Action Button',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CalendarView(),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Calendar'), findsOneWidget);
      expect(find.text('Month'), findsOneWidget);
      expect(find.text('Week'), findsOneWidget);
      
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });
  });

  group('Milestone 3 Extension: Tasks, Projects, and Logout Tests', () {
    test('ProjectModel and TaskModel correctly map MongoDB JSON', () {
      final proj = ProjectModel.fromJson({
        '_id': 'p101',
        'name': 'ERP Redesign',
        'description': 'Revamp corporate portal',
        'status': 'in_progress',
        'priority': 'urgent',
        'startDate': '2026-10-01',
        'dueDate': '2026-11-15',
      });

      expect(proj.id, 'p101');
      expect(proj.name, 'ERP Redesign');
      expect(proj.status, 'in_progress');
      expect(proj.priority, 'urgent');

      final task = TaskModel.fromJson({
        '_id': 't202',
        'title': 'Design Database Schemas',
        'description': 'Setup MongoDB collections',
        'priority': 'high',
        'status': 'todo',
        'dueDate': '2026-11-05',
        'projectId': 'p101',
        'projectName': 'ERP Redesign',
      });

      expect(task.id, 't202');
      expect(task.title, 'Design Database Schemas');
      expect(task.isProjectTask, isTrue);
      expect(task.projectName, 'ERP Redesign');
    });

    testWidgets('TasksView renders segment filters and FAB', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TasksView(
            user: const UserModel(
              id: 'owner_1',
              userId: 'Vyshwa',
              username: 'Vyshwa',
              name: 'Vyshwa',
              role: 'owner',
              company: 'krish',
              token: 'tok',
            ),
            dashboardService: MockDashboardService(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Tasks & Schedules'), findsOneWidget);
      expect(find.textContaining('All'), findsOneWidget);
      expect(find.textContaining('Active'), findsOneWidget);
      expect(find.textContaining('Done'), findsOneWidget);
      expect(find.textContaining('Projects'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('ProfileView renders logout button and triggers confirmation', (WidgetTester tester) async {
      bool logoutCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileView(
            user: const UserModel(
              id: 'u1',
              userId: 'Ram',
              username: 'Ram',
              name: 'Ram',
              role: 'staff',
              token: 'mock_token',
            ),
            onLogout: () {
              logoutCalled = true;
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      final logoutBtn = find.text('Log Out of Account');
      expect(logoutBtn, findsOneWidget);

      await tester.ensureVisible(logoutBtn);
      await tester.tap(logoutBtn);
      await tester.pumpAndSettle();

      expect(find.text('Confirm Logout'), findsOneWidget);
      expect(find.text('Are you sure you want to log out of your ReGen account?'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Log Out'));
      await tester.pumpAndSettle();

      expect(logoutCalled, isTrue);
    });

    testWidgets('Role Separation: Employee TasksView hides FAB, EmployeeDashboardView renders personal metrics',
        (WidgetTester tester) async {
      // 1. Verify Employee TasksView hides FAB
      await tester.pumpWidget(
        MaterialApp(
          home: TasksView(
            user: const UserModel(
              id: 'emp_1',
              userId: 'EMP-101',
              username: 'ram',
              name: 'Ram',
              role: 'staff',
              token: 'tok_ram',
            ),
            dashboardService: MockDashboardService(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Tasks & Schedules'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);

      // 2. Verify EmployeeDashboardView displays personal metrics & no company totals
      await tester.pumpWidget(
        MaterialApp(
          home: EmployeeDashboardView(
            user: const UserModel(
              id: 'emp_1',
              userId: 'EMP-101',
              username: 'ram',
              name: 'Ram',
              role: 'staff',
              token: 'tok_ram',
            ),
            dashboardService: MockDashboardService(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Attendance Rate'), findsOneWidget);
      expect(find.text('My Projects'), findsOneWidget);
      expect(find.text('Summary'), findsOneWidget);
      expect(find.text('Total Registered Employees'), findsNothing);
    });
  });
}
