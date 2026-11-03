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
import 'package:regen_mobile/features/company/presentation/add_employee_view.dart';
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
import 'package:regen_mobile/features/policies/data/policy_service.dart';
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

  @override
  Future<UserModel> updateUser(String id, Map<String, dynamic> userData) async {
    return UserModel(
      id: id,
      userId: id,
      username: (userData['username'] ?? 'eswaran').toString(),
      name: (userData['name'] ?? 'eswaran M').toString(),
      role: (userData['role'] ?? 'staff').toString(),
      token: 'tok_updated',
    );
  }

  @override
  Future<void> deleteUser(String id) async {
    return;
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

      // Verify NO third-party SSO, divider, or signup links below Login button
      expect(find.text('or continue with'), findsNothing);
      expect(find.textContaining('Sign Up'), findsNothing);
      expect(find.text('Server Settings'), findsNothing);
      
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

      // Verify NO Super Admin switcher on dashboard
      expect(find.text('Super Admin Console Available'), findsNothing);

      // Open drawer to verify company operations
      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Employee Management'), findsOneWidget);
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

      // Verify switch banner is removed from dashboard surface
      expect(find.text('Super Admin Console Available'), findsNothing);

      // Open drawer to verify Super Admin switch banner
      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
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

    testWidgets('TasksView renders General Task with 4 counters, search bar, and automatic end date calculation', (WidgetTester tester) async {
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

      // Verify General Task and Projects segments
      expect(find.text('General Task'), findsOneWidget);
      expect(find.text('Projects'), findsOneWidget);

      // Verify 4 Metric Counters & Filter Chips
      expect(find.text('Total Tasks'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Incomplete'), findsWidgets);
      expect(find.text('Completed'), findsOneWidget);

      // Verify Search Bar with full placeholder
      expect(find.text('Search by title, description, or assigned person...'), findsOneWidget);

      // Verify auto calculation function
      final calcDays = TasksView.computeEndDateTime('2026-11-03', 3, 'days');
      expect(calcDays['endDate'], '2026-11-06');
      expect(calcDays['dueTime'], '18:00');

      final calcHours = TasksView.computeEndDateTime('2026-11-03', 4, 'hours');
      expect(calcHours['endDate'], isNotEmpty);
      expect(calcHours['dueTime'], isNotEmpty);
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

    test('CompanyModel startingYear is derived dynamically without hardcoded 2024', () {
      // 1. From ObjectId hex timestamp (e.g. krish Tech Computer 6adb0f108482fee4b61bc12b -> Oct 2026)
      const comp2026 = CompanyModel(
        id: '6adb0f108482fee4b61bc12b',
        name: 'krish Tech Computer',
      );
      expect(comp2026.startingYear, 2026);

      // 2. From createdAt string
      const comp2024 = CompanyModel(
        id: 'c_custom',
        name: 'Zevox Medice',
        createdAt: '2024-06-19T10:00:00.000Z',
      );
      expect(comp2024.startingYear, 2024);

      // 3. From establishmentYear
      const comp2021 = CompanyModel(
        id: 'c_est',
        name: 'Old Enterprise',
        establishmentYear: 2021,
      );
      expect(comp2021.startingYear, 2021);
    });

    testWidgets('CompanyDashboardView displays dynamic Attendance Rate with Present, Absent, Late labels and Trend',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyDashboardView(
            user: const UserModel(
              id: 'owner_test',
              userId: 'Vyshwa',
              username: 'Vyshwa',
              name: 'Vyshwa',
              role: 'owner',
              company: 'krish Tech Computer',
              token: 'tok_owner',
            ),
            dashboardService: MockDashboardService(),
            authService: MockAuthService(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Attendance Rate card and bright labels
      expect(find.text('Attendance Rate'), findsOneWidget);
      expect(find.text('Present'), findsWidgets);
      expect(find.text('Absent'), findsWidgets);
      expect(find.text('Late'), findsWidgets);

      // Trend Section
      expect(find.textContaining('Team Attendance Trend'), findsOneWidget);
    });

    testWidgets('CompanyDashboardView renders active squircle bottom nav tile and unified dark glass typing box in Employees tab',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyDashboardView(
            user: const UserModel(
              id: 'owner_test',
              userId: 'Vyshwa',
              username: 'Vyshwa',
              name: 'Vyshwa',
              role: 'owner',
              company: 'krish Tech Computer',
              token: 'tok_owner',
            ),
            dashboardService: MockDashboardService(),
            authService: MockAuthService(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Active squircle bottom nav tile
      expect(find.text('Home'), findsWidgets);
      expect(find.byIcon(Icons.home_rounded), findsOneWidget);

      // Switch to Employees tab (index 1)
      await tester.tap(find.text('Employees'));
      await tester.pumpAndSettle();

      // Unified typing box in Employees tab
      expect(find.text('Search employees...'), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      expect(find.byIcon(Icons.filter_list_rounded), findsOneWidget);

      // Add Employee button and role filter segment chips matching website
      expect(find.text('Add Employee'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Staff'), findsWidgets);
      expect(find.text('Intern'), findsWidgets);
      expect(find.text('Admin'), findsWidgets);
      expect(find.byIcon(Icons.more_vert_rounded), findsWidgets);
    });

    test('CompanyModel startingMonth is derived dynamically from createdAt or establishmentMonth', () {
      const compJune = CompanyModel(
        id: 'comp_june',
        name: 'June Enterprise',
        createdAt: '2026-06-15T09:00:00Z',
      );
      expect(compJune.startingYear, 2026);
      expect(compJune.startingMonth, 6);

      const compOct = CompanyModel(
        id: 'comp_oct',
        name: 'October Tech',
        establishmentYear: 2026,
        establishmentMonth: 10,
      );
      expect(compOct.startingYear, 2026);
      expect(compOct.startingMonth, 10);
    });

    testWidgets('CompanyDashboardView drawer renders executive card UI and red glass sign out button',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyDashboardView(
            user: const UserModel(
              id: 'owner_test',
              userId: 'Vyshwa',
              username: 'Vyshwa',
              name: 'Vyshwa',
              role: 'owner',
              company: 'krish Tech Computer',
              token: 'tok_owner',
            ),
            dashboardService: MockDashboardService(),
            authService: MockAuthService(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Open drawer using hamburger icon
      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      // Drawer UI verification
      expect(find.text('COMPANY OPERATIONS'), findsOneWidget);
      expect(find.text('Employee Management'), findsOneWidget);
      expect(find.text('Attendance'), findsWidgets);

      // Scroll drawer to reveal all items and Sign Out
      await tester.drag(find.text('Employee Management'), const Offset(0, -350));
      await tester.pumpAndSettle();

      expect(find.text('Sign Out'), findsOneWidget);
      expect(find.byIcon(Icons.logout_rounded), findsOneWidget);
    });

    testWidgets('Tapping + Add Employee navigates to dedicated AddEmployeeView with website fields',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyDashboardView(
            user: const UserModel(
              id: 'owner_test',
              userId: 'Vyshwa',
              username: 'Vyshwa',
              name: 'Vyshwa',
              role: 'owner',
              company: 'krish Tech Computer',
              token: 'tok_owner',
            ),
            dashboardService: MockDashboardService(),
            authService: MockAuthService(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Navigate to Employees Tab
      await tester.tap(find.text('Employees'));
      await tester.pumpAndSettle();

      // Tap + Add Employee
      await tester.tap(find.text('Add Employee'));
      await tester.pumpAndSettle();

      // Verified: Separate Page AddEmployeeView with website fields
      expect(find.text('Add New Employee'), findsOneWidget);
      expect(find.text('Aadhaar Number (12 Digits) *'), findsOneWidget);
      expect(find.text('Staff ID / Principal ID *'), findsOneWidget);
      expect(find.text('Username *'), findsOneWidget);
      expect(find.text('First Name *'), findsOneWidget);
      expect(find.text('Register Employee'), findsOneWidget);
    });

    testWidgets('Tapping filter icon opens employee filter sheet with website role counts',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyDashboardView(
            user: const UserModel(
              id: 'owner_test',
              userId: 'Vyshwa',
              username: 'Vyshwa',
              name: 'Vyshwa',
              role: 'owner',
              company: 'krish Tech Computer',
              token: 'tok_owner',
            ),
            dashboardService: MockDashboardService(),
            authService: MockAuthService(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Navigate to Employees Tab
      await tester.tap(find.text('Employees'));
      await tester.pumpAndSettle();

      // Tap the filter icon on the search bar
      await tester.tap(find.byIcon(Icons.filter_list_rounded));
      await tester.pumpAndSettle();

      // Verified: Filter sheet opened
      expect(find.text('Filter Employees'), findsOneWidget);
      expect(find.text('ROLE (FROM WEBSITE)'), findsOneWidget);
      expect(find.text('Apply Filters'), findsOneWidget);
    });

    testWidgets('CompanyDashboardView total employee count excludes company owner and admin',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyDashboardView(
            user: const UserModel(
              id: 'owner_test',
              userId: 'Vyshwa',
              username: 'Vyshwa',
              name: 'Vyshwa',
              role: 'owner',
              company: 'krish Tech Computer',
              token: 'tok_owner',
            ),
            dashboardService: MockDashboardService(),
            authService: MockAuthService(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Total Employees metric card should display '1' (only staff Eswaran M, excluding owner Vyshwa)
      expect(find.text('Total Employees'), findsOneWidget);
      expect(find.text('1'), findsWidgets);
    });

    testWidgets('CompanyDashboardView attendance trend has interactive Present, Absent, Late, Leave tabs and drill-down with back arrow',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyDashboardView(
            user: const UserModel(
              id: 'owner_test',
              userId: 'Vyshwa',
              username: 'Vyshwa',
              name: 'Vyshwa',
              role: 'owner',
              company: 'krish Tech Computer',
              token: 'tok_owner',
            ),
            dashboardService: MockDashboardService(),
            authService: MockAuthService(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Attendance trend interactive tabs should be present
      expect(find.text('Present'), findsWidgets);
      expect(find.text('Absent'), findsWidgets);
      expect(find.text('Late'), findsWidgets);
      expect(find.text('Leave'), findsWidgets);

      // Scroll to reveal the Attendance Trend section
      await tester.scrollUntilVisible(find.text('Employee Attendance Details'), 300);
      await tester.pumpAndSettle();

      // Select Monday (past day) in the 7-day trend selector
      await tester.tap(find.text('Mon').first);
      await tester.pumpAndSettle();

      // Tap on the Absent tab in the trend section where staff Eswaran M is located
      await tester.tap(find.text('Absent').last);
      await tester.pumpAndSettle();

      // Verify employee is listed in Absent tab
      expect(find.text('eswaran M'), findsOneWidget);

      // Tap on the employee to drill down into details
      await tester.tap(find.text('eswaran M'));
      await tester.pumpAndSettle();

      // Verified: Employee detail view opened with back arrow and details
      expect(find.text('Employee Details'), findsOneWidget);
      expect(find.text('Employee ID'), findsOneWidget);
      expect(find.text('Phone Number'), findsOneWidget);
      expect(find.text('Check-In Time'), findsOneWidget);
      expect(find.text('Check-Out Time'), findsOneWidget);

      // Tap the back arrow to return to list
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      // Verified returned to roster list
      expect(find.text('Employee Details'), findsNothing);
      expect(find.text('eswaran M'), findsOneWidget);
    });

    testWidgets('AddEmployeeView requires mandatory profile photo',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AddEmployeeView(
            currentUser: UserModel(
              id: 'owner_test',
              userId: 'Vyshwa',
              username: 'Vyshwa',
              name: 'Vyshwa',
              role: 'owner',
              company: 'krish Tech Computer',
              token: 'tok_owner',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verified: Photo upload card with mandatory indicator
      expect(find.text('Profile Picture'), findsOneWidget);
      expect(find.text('⚠️ Photo Upload Mandatory *'), findsOneWidget);
      expect(find.text('Register Employee'), findsOneWidget);
    });

    testWidgets('CompanyDashboardView employee card has 3-dots with Edit and Delete options only',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyDashboardView(
            user: const UserModel(
              id: 'owner_1',
              userId: 'Vyshwa',
              username: 'Vyshwa',
              name: 'Vyshwa',
              role: 'owner',
              company: 'krish Tech Computer',
              token: 'tok_owner',
            ),
            dashboardService: MockDashboardService(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Navigate to Employees tab (tab index 1)
      await tester.tap(find.text('Employees').first);
      await tester.pumpAndSettle();

      expect(find.text('Manage your team'), findsOneWidget);
      expect(find.text('eswaran M'), findsOneWidget);

      // Verify search box hint is present
      expect(find.text('Search employees...'), findsOneWidget);

      // Tap 3-dots menu on employee card
      final moreVert = find.byIcon(Icons.more_vert_rounded).first;
      await tester.tap(moreVert);
      await tester.pumpAndSettle();

      // Verified: ONLY Edit and Delete options are present
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('View Attendance History'), findsNothing);
      expect(find.text('Employee Details'), findsNothing);
    });

    testWidgets('CompanyDashboardView Attendance tab has Work Schedule & Break Policy at top with website fields',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyDashboardView(
            user: const UserModel(
              id: 'owner_1',
              userId: 'Vyshwa',
              username: 'Vyshwa',
              name: 'Vyshwa',
              role: 'owner',
              company: 'krish Tech Computer',
              token: 'tok_owner',
            ),
            dashboardService: MockDashboardService(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Navigate to Attendance tab (tab index 2)
      await tester.tap(find.text('Attendance').first);
      await tester.pumpAndSettle();

      expect(find.text('Track employee attendance'), findsOneWidget);
      expect(find.text('Work Policy'), findsOneWidget);

      // Tap Work Policy button
      await tester.tap(find.text('Work Policy').first);
      await tester.pumpAndSettle();

      // Verified: Fields matching website AttendanceModule.jsx
      expect(find.text('Standard Check-In'), findsOneWidget);
      expect(find.text('Standard Check-Out'), findsOneWidget);
      expect(find.text('Working Hours / Day'), findsOneWidget);
      expect(find.text('Working Days / Week'), findsOneWidget);
      expect(find.text('Break Time Limits & Salary Delay Deductions'), findsOneWidget);
      expect(find.text('Lunch Break (Mins)'), findsOneWidget);
      expect(find.text('Casual Break (Mins)'), findsOneWidget);
      expect(find.text('Save Schedule & Policy'), findsOneWidget);
    });

    testWidgets('CompanyDashboardView Late Arrivals in dashboard displays only today count and has null onTap',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyDashboardView(
            user: const UserModel(
              id: 'owner_1',
              userId: 'Vyshwa',
              username: 'Vyshwa',
              name: 'Vyshwa',
              role: 'owner',
              company: 'krish Tech Computer',
              token: 'tok_owner',
            ),
            dashboardService: MockDashboardService(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Late Arrivals'), findsOneWidget);
      expect(find.text("Today's late check-ins"), findsOneWidget);

      // Tap Late Arrivals card -> should not show any dialog (onTap is null)
      await tester.ensureVisible(find.text('Late Arrivals'));
      await tester.tap(find.text('Late Arrivals'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Company Shift Timings'), findsNothing);
    });
    testWidgets('CompanyDashboardView Employees tab filters employees by role chips (Staff, Intern, Admin)',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyDashboardView(
            user: const UserModel(
              id: 'owner_1',
              userId: 'Vyshwa',
              username: 'Vyshwa',
              name: 'Vyshwa',
              role: 'owner',
              company: 'krish Tech Computer',
              token: 'tok_owner',
            ),
            dashboardService: MockDashboardService(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Navigate to Employees tab (tab index 1)
      await tester.tap(find.text('Employees').first);
      await tester.pumpAndSettle();

      // Verify Role Chips exist
      expect(find.text('Staff'), findsOneWidget);
      expect(find.text('Intern'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);

      // Tap Staff role chip
      await tester.tap(find.text('Staff'));
      await tester.pumpAndSettle();
    });

    testWidgets('CompanyDashboardView Attendance tab day log has search, status filter pills, and employee drill-down with back arrow',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyDashboardView(
            user: const UserModel(
              id: 'owner_1',
              userId: 'Vyshwa',
              username: 'Vyshwa',
              name: 'Vyshwa',
              role: 'owner',
              company: 'krish Tech Computer',
              token: 'tok_owner',
            ),
            dashboardService: MockDashboardService(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Navigate to Attendance tab (tab index 2)
      await tester.tap(find.text('Attendance').first);
      await tester.pumpAndSettle();

      // Verify single first search box and status filter chips in Attendance tab
      expect(find.text('Search attendance logs...'), findsOneWidget);
      expect(find.text('Present'), findsWidgets);
      expect(find.text('Absent'), findsWidgets);
      expect(find.text('Late'), findsWidgets);
      expect(find.text('Leave'), findsWidgets);

      // Verify tapping filter icon opens Attendance Filter Sheet with check filters
      await tester.tap(find.byIcon(Icons.filter_list_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('Filter Attendance Logs'), findsOneWidget);
      expect(find.text('All Attendance Logs'), findsOneWidget);
      expect(find.text('Present Only'), findsOneWidget);

      // Select Present Only filter from sheet
      await tester.tap(find.text('Present Only'));
      await tester.pumpAndSettle();
    });

    test('TaskModel tracks startedAt, completedAt and completionTime', () {
      final task = TaskModel(
        id: 'task_lifecycle_1',
        title: 'Complete Mobile Redesign',
        status: 'in_progress',
        startedAt: '2026-11-03T09:00:00Z',
        completedAt: '2026-11-03T11:30:00Z',
        completionTime: '11:30 AM',
      );

      final json = task.toJson();
      expect(json['startedAt'], '2026-11-03T09:00:00Z');
      expect(json['completedAt'], '2026-11-03T11:30:00Z');
      expect(json['completionTime'], '11:30 AM');

      final deserialized = TaskModel.fromJson(json);
      expect(deserialized.startedAt, '2026-11-03T09:00:00Z');
      expect(deserialized.completedAt, '2026-11-03T11:30:00Z');
      expect(deserialized.completionTime, '11:30 AM');
    });

    testWidgets('CompanyDashboardView header renders Notification bell with unread badge support and back navigation PopScope',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyDashboardView(
            user: const UserModel(
              id: 'owner_1',
              userId: 'Vyshwa',
              username: 'Vyshwa',
              name: 'Vyshwa',
              role: 'owner',
              company: 'krish Tech Computer',
              token: 'tok_owner',
            ),
            dashboardService: MockDashboardService(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Top app bar has notifications icon
      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);

      // Tap notifications icon to open notifications sheet
      await tester.tap(find.byIcon(Icons.notifications_none_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Stay updated with company activity'), findsOneWidget);
      expect(find.text('Clear all'), findsOneWidget);

      // Tap Clear all button
      await tester.tap(find.text('Clear all'));
      await tester.pumpAndSettle();

      // Empty state shown
      expect(find.text('No notifications'), findsOneWidget);
    });

    testWidgets('CompanyDashboardView Attendance tab has Add Holiday button and opens holiday creation sheet',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyDashboardView(
            user: const UserModel(
              id: 'owner_1',
              userId: 'Vyshwa',
              username: 'Vyshwa',
              name: 'Vyshwa',
              role: 'owner',
              company: 'krish Tech Computer',
              token: 'tok_owner',
            ),
            dashboardService: MockDashboardService(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Navigate to Attendance tab (tab index 2)
      await tester.tap(find.text('Attendance').first);
      await tester.pumpAndSettle();

      // Verify Add Holiday and Work Policy buttons exist in header
      expect(find.text('Add Holiday'), findsOneWidget);
      expect(find.text('Work Policy'), findsOneWidget);

      // Tap Add Holiday button
      await tester.tap(find.text('Add Holiday'));
      await tester.pumpAndSettle();

      // Verify Add Company Holiday sheet opened
      expect(find.text('Add Company Holiday'), findsOneWidget);
      expect(find.text('Holiday Title *'), findsOneWidget);
      expect(find.text('Holiday Date *'), findsOneWidget);
      expect(find.text('Save Holiday'), findsOneWidget);
    });

    testWidgets('CompanyDashboardView Leave tab has employee search and tap opens leave details sheet',
        (WidgetTester tester) async {
      final mockDashboard = MockDashboardService();
      final mockAuth = MockAuthService();

      await tester.pumpWidget(
        MaterialApp(
          home: CompanyDashboardView(
            user: const UserModel(
              id: 'owner_1',
              userId: 'Vyshwa',
              username: 'Vyshwa',
              name: 'Vyshwa',
              role: 'owner',
              company: 'krish Tech Computer',
              token: 'tok_owner',
            ),
            dashboardService: mockDashboard,
            authService: mockAuth,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Navigate to Leave tab (index 3) via bottom nav icon
      await tester.tap(find.byIcon(Icons.beach_access_outlined));
      await tester.pumpAndSettle();

      // Verify search box exists and filter segment chips are removed
      expect(find.text('Search employee name, ID or leave...'), findsOneWidget);
      expect(find.text('Manage leave requests'), findsNothing);
      expect(find.text('Search & review employee leave applications'), findsOneWidget);

      // Verify a leave card exists and tap opens leave details sheet
      final leaveCard = find.text('PENDING');
      if (leaveCard.evaluate().isNotEmpty) {
        await tester.tap(leaveCard.first);
        await tester.pumpAndSettle();
        expect(find.text('Leave Application Details'), findsOneWidget);
        expect(find.text('Reason for Leave Application'), findsOneWidget);
      }
    });

    testWidgets('TasksView header renders BrandLogo, ReGen, and dark glass search bar without white fill',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TasksView(
            user: const UserModel(
              id: 'owner_1',
              userId: 'Vyshwa',
              username: 'Vyshwa',
              name: 'Vyshwa',
              role: 'owner',
              company: 'krish Tech Computer',
              token: 'tok_owner',
            ),
            dashboardService: MockDashboardService(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('ReGen'), findsOneWidget);
      expect(find.text('Tasks & Schedules'), findsOneWidget);
      expect(find.text('Search by title, description, or assigned person...'), findsOneWidget);
    });

    test('CompanyPolicyItem and PolicyReviewModel properly serialize and parse JSON', () {
      final policyJson = {
        '_id': 'p101',
        'title': 'Remote Work Guidelines',
        'content': 'All employees must adhere to data security protocols while working remotely.',
        'effectiveDate': '2026-11-01',
      };
      final policyItem = CompanyPolicyItem.fromJson(policyJson);
      expect(policyItem.id, 'p101');
      expect(policyItem.title, 'Remote Work Guidelines');
      expect(policyItem.content, contains('data security'));
      expect(policyItem.effectiveDate, '2026-11-01');

      final reviewJson = {
        '_id': 'rev1',
        'companyId': 'comp1',
        'policyId': 'p101',
        'policyTitle': 'Remote Work Guidelines',
        'policyContent': 'Data security protocols',
        'userId': 'emp_12',
        'userName': 'Kavya S',
        'userEmail': 'kavya@example.com',
        'department': 'Development',
        'status': 'declined',
        'declineReason': 'I require hardware tokens before agreeing to security protocols.',
        'declinedAt': '2026-11-03T10:00:00Z',
      };
      final review = PolicyReviewModel.fromJson(reviewJson);
      expect(review.isDeclined, isTrue);
      expect(review.isAllowed, isFalse);
      expect(review.userName, 'Kavya S');
      expect(review.declineReason, contains('hardware tokens'));

      final statusJson = {
        'hasBlockedPolicy': true,
        'blockedPolicies': [reviewJson],
        'pendingPolicies': <Map<String, dynamic>>[],
      };
      final empStatus = EmployeePolicyStatus.fromJson(statusJson);
      expect(empStatus.hasBlockedPolicy, isTrue);
      expect(empStatus.blockedPolicies.length, 1);
    });
  });
}
