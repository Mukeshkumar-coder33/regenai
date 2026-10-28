import 'package:flutter_test/flutter_test.dart';
import 'package:regen_mobile/app/app.dart';

void main() {
  testWidgets('ReGenApp launches and renders SplashScreen with Celadon branding',
      (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ReGenApp());

    // Verify that the title ReGen is present.
    expect(find.text('ReGen'), findsOneWidget);

    // Verify that the workforce subtitle is present.
    expect(
      find.text('Workforce & Office Management System'),
      findsOneWidget,
    );

    // Verify the version string is present.
    expect(
      find.text('v1.0.0 • ReGen Enterprise'),
      findsOneWidget,
    );

    // Advance animation
    await tester.pump(const Duration(milliseconds: 600));

    // Verify initializing indicator text
    expect(find.text('Initializing workspace...'), findsOneWidget);
  });
}
