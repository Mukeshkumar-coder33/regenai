import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regen_mobile/core/widgets/celadon_button.dart';
import 'package:regen_mobile/features/auth/data/user_model.dart';
import 'package:regen_mobile/features/auth/presentation/auth_controller.dart';
import 'package:regen_mobile/features/auth/presentation/login_screen.dart';
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

  group('LoginScreen Widget Tests', () {
    testWidgets('Renders only Username, Password, and Sign In button',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoginScreen(),
        ),
      );

      // Verify header branding
      expect(find.text('ReGen'), findsOneWidget);
      // Card title and button both have "Sign In"
      expect(find.text('Sign In'), findsNWidgets(2));

      // Verify form inputs
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);

      // Verify Sign In button exists
      expect(find.widgetWithText(CeladonButton, 'Sign In'), findsOneWidget);
    });

    testWidgets('Shows validation errors when submitting empty form',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoginScreen(),
        ),
      );

      // Tap Sign In button without typing anything
      await tester.tap(find.widgetWithText(CeladonButton, 'Sign In'));
      await tester.pump();

      expect(find.text('Please enter your username'), findsOneWidget);
      expect(find.text('Please enter your password'), findsOneWidget);
    });

    testWidgets('Password visibility toggle toggles obscureText',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoginScreen(),
        ),
      );

      final passwordField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Enter your password',
      );
      expect(passwordField, findsOneWidget);

      TextField textField = tester.widget<TextField>(passwordField);
      expect(textField.obscureText, isTrue);

      // Tap the eye toggle icon
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pump();

      textField = tester.widget<TextField>(passwordField);
      expect(textField.obscureText, isFalse);
    });

    testWidgets('Shows error message when AuthController fails',
        (WidgetTester tester) async {
      final controller = AuthController();
      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(controller: controller),
        ),
      );

      // Enter valid form text to bypass client-side validation
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Enter your username or ID'),
        'test_user',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Enter your password'),
        'wrong_pwd',
      );

      await tester.tap(find.widgetWithText(CeladonButton, 'Sign In'));
      await tester.pump(); // Start async request
      await tester.pumpAndSettle(); // Settle all network timers/exceptions

      expect(controller.errorMessage, isNotNull);
    });
  });
}
