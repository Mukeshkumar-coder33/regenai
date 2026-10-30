import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regen_mobile/features/attendance/presentation/attendance_view.dart';
import 'package:regen_mobile/features/auth/data/user_model.dart';
import 'package:regen_mobile/features/auth/presentation/login_screen.dart';
import 'package:regen_mobile/features/calendar/presentation/calendar_view.dart';
import 'package:regen_mobile/features/company/presentation/company_dashboard_view.dart';
import 'package:regen_mobile/features/dashboard/presentation/dashboard_screen.dart';
import 'package:regen_mobile/features/dashboard/presentation/employee_dashboard_view.dart';
import 'package:regen_mobile/features/profile/presentation/profile_view.dart';
import 'package:regen_mobile/features/tasks/presentation/tasks_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('UserModel Tests', () {
    test('Correctly parses backend /api/auth/login response', () {
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
      expect(user.roleDisplayName, 'Employee');
      expect(user.authSource, 'dual:synchronized');
    });

    test('Identifies Super Admin (param) correctly', () {
      final json = {
        '_id': 'sa_01',
        'userId': 'Vyshwa',
        'username': 'Vyshwa',
        'role': 'param',
        'token': 'sa_jwt',
      };

      final user = UserModel.fromJson(json);
      expect(user.isSuperAdmin, isTrue);
      expect(user.roleDisplayName, 'Super Administrator');
    });
  });

  group('LoginScreen Tests (Matching UI Reference Screen 2)', () {
    testWidgets('Renders Brand, Email, Password, Login button, and Social SSO',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoginScreen(),
        ),
      );

      // Verify branding and subtitles
      expect(find.text('ReGen'), findsOneWidget);
      expect(find.text('Sign in to continue'), findsOneWidget);

      // Verify input fields
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);

      // Verify Remember me and Forgot Password
      expect(find.text('Remember me'), findsOneWidget);
      expect(find.text('Forgot Password?'), findsOneWidget);

      // Verify Login button
      expect(find.widgetWithText(ElevatedButton, 'Login'), findsOneWidget);

      // Verify Social login divider and sign up prompt
      expect(find.text('or continue with'), findsOneWidget);
      expect(find.text('Sign Up'), findsOneWidget);
    });

    testWidgets('Validates empty Email and Password on submission',
        (WidgetTester tester) async {
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

    testWidgets('Toggles password visibility on icon tap',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoginScreen(),
        ),
      );

      final passwordFieldFinder = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Password',
      );
      expect(passwordFieldFinder, findsOneWidget);

      TextField textField = tester.widget<TextField>(passwordFieldFinder);
      expect(textField.obscureText, isTrue);

      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pump();

      textField = tester.widget<TextField>(passwordFieldFinder);
      expect(textField.obscureText, isFalse);
    });
  });

  group('Dashboard & Sub-Screen Tests (Matching UI Reference Screens 3-8)', () {
    const testUser = UserModel(
      id: 'emp_1',
      userId: 'EMP-101',
      username: 'alex',
      name: 'Alex Johnson',
      role: 'staff',
      company: 'ReGen Technologies',
      token: 'jwt_test',
    );

    testWidgets('Screen 3: EmployeeDashboardView displays stats and tasks',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EmployeeDashboardView(user: testUser),
        ),
      );

      expect(find.text('Good Morning,'), findsOneWidget);
      expect(find.text('Alex Johnson'), findsOneWidget);
      expect(find.text('Mon, 20 Oct 2026'), findsOneWidget);
      expect(find.text('128'), findsOneWidget);
      expect(find.text('Total Employees'), findsOneWidget);
      expect(find.text("Today's Tasks"), findsOneWidget);
      expect(find.text('UI Design Review'), findsOneWidget);
    });

    testWidgets('Screen 4: AttendanceView displays check-in time and check out button',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AttendanceView(),
        ),
      );

      expect(find.text('Attendance'), findsOneWidget);
      expect(find.text('Check In'), findsOneWidget);
      expect(find.text('09:10 AM'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Check Out'), findsOneWidget);
    });

    testWidgets('Screen 5: CalendarView displays events',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CalendarView(),
        ),
      );

      expect(find.text('Calendar'), findsOneWidget);
      expect(find.text('Team Meeting'), findsOneWidget);
      expect(find.text('Project Discussion'), findsOneWidget);
      expect(find.text('Design Review'), findsOneWidget);
    });

    testWidgets('Screen 6: TasksView displays tasks and priority filters',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: TasksView(),
        ),
      );

      expect(find.text('Tasks'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('UI Design Review'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
    });

    testWidgets('Screen 7: ProfileView displays user info and Logout button',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileView(
            user: testUser,
            onLogout: () {},
          ),
        ),
      );

      expect(find.text('Alex Johnson'), findsOneWidget);
      expect(find.text('Employee'), findsOneWidget);

      // Open the navigation drawer via hamburger menu
      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      expect(find.text('My Profile'), findsOneWidget);
      expect(find.text('Attendance'), findsOneWidget);
      expect(find.text('Logout'), findsOneWidget);
    });

    testWidgets('Screen 8: CompanyDashboardView displays company name and stats',
        (WidgetTester tester) async {
      const companyUser = UserModel(
        id: 'owner_1',
        userId: 'OWN-1',
        username: 'owner',
        name: 'Company Owner',
        role: 'owner',
        company: 'ReGen Technologies',
        token: 'owner_jwt',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: CompanyDashboardView(user: companyUser),
        ),
      );

      expect(find.text('ReGen Technologies'), findsOneWidget);
      expect(find.text('128'), findsOneWidget);
      expect(find.text('Employees'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('Departments'), findsOneWidget);
      expect(find.text('Employee Management'), findsOneWidget);
    });

    testWidgets('DashboardScreen renders 4-tab bottom navigation bar',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(
            user: testUser,
            onLogout: () {},
          ),
        ),
      );

      expect(find.widgetWithText(InkWell, 'Home'), findsOneWidget);
      expect(find.widgetWithText(InkWell, 'Tasks'), findsNWidgets(2)); // Home tile + Bottom nav
      expect(find.widgetWithText(InkWell, 'Calendar'), findsOneWidget);
      expect(find.widgetWithText(InkWell, 'Profile'), findsOneWidget);
    });
  });
}
