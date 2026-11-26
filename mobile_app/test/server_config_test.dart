import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:regen_mobile/app/app_config.dart';
import 'package:regen_mobile/core/storage/session_storage.dart';
import 'package:regen_mobile/features/auth/data/auth_service.dart';
import 'package:regen_mobile/features/auth/data/user_model.dart';
import 'package:regen_mobile/features/profile/presentation/settings_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AppConfig Dual-Environment Auto & Manual Switching', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AppConfig.resetForTest();
    });

    test('Auto mode picks Local LAN backend when /api/health responds 200 ok', () async {
      final mockClient = MockClient((req) async {
        if (req.url.toString() == 'http://192.168.1.38:5006/api/health') {
          return http.Response(
            jsonEncode({'status': 'ok', 'service': 'regen-backend', 'mongoConnected': true}),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      await AppConfig.initCustomUrl(probeClient: mockClient);
      expect(AppConfig.serverEnvironment, ServerEnvironment.auto);
      expect(AppConfig.isAutoMode, isTrue);
      expect(AppConfig.isCurrentlyUsingLocal, isTrue);
      expect(AppConfig.activeBaseUrl, 'http://192.168.1.38:5006');
      expect(AppConfig.socketBaseUrl, 'http://192.168.1.38:5006');
    });

    test('Auto mode falls back to https://regen.krishub.in without :5006 when local unreachable', () async {
      final mockClient = MockClient((req) async {
        throw Exception('Connection refused');
      });

      await AppConfig.initCustomUrl(probeClient: mockClient);
      expect(AppConfig.serverEnvironment, ServerEnvironment.auto);
      expect(AppConfig.isCurrentlyUsingLocal, isFalse);
      expect(AppConfig.activeBaseUrl, 'https://regen.krishub.in');
      expect(AppConfig.socketBaseUrl, 'https://regen.krishub.in');
      expect(AppConfig.activeBaseUrl.contains(':5006'), isFalse);
      expect(AppConfig.loginUrl, 'https://regen.krishub.in/api/auth/login');
    });

    test('Runtime failover switches from local backend to public server when local drops', () async {
      var localUp = true;
      final mockClient = MockClient((req) async {
        if (localUp && req.url.host == '192.168.1.38') {
          return http.Response(jsonEncode({'status': 'ok'}), 200);
        }
        throw Exception('Local server down');
      });

      await AppConfig.resetForTest(probeClient: mockClient);
      await AppConfig.initCustomUrl(probeClient: mockClient);
      expect(AppConfig.activeBaseUrl, 'http://192.168.1.38:5006');

      localUp = false;
      final switched = await AppConfig.handleConnectionErrorFailover(client: mockClient);
      expect(switched, isTrue);
      expect(AppConfig.activeBaseUrl, 'https://regen.krishub.in');
    });

    test('resolveMediaUrl rewrites relative and stale host paths to active backend cleanly', () async {
      await AppConfig.useCompanyServer();
      expect(
        AppConfig.resolveMediaUrl('/uploads/doc.pdf'),
        'https://regen.krishub.in/uploads/doc.pdf',
      );
      expect(
        AppConfig.resolveMediaUrl('http://192.168.1.38:5006/assets/profiles/a.png'),
        'https://regen.krishub.in/assets/profiles/a.png',
      );
      expect(
        AppConfig.resolveMediaUrl('https://api.dicebear.com/7.x/avataaars/svg?seed=x'),
        'https://api.dicebear.com/7.x/avataaars/svg?seed=x',
      );

      await AppConfig.useLocalServer(localUrlOrIp: '192.168.1.38');
      expect(
        AppConfig.resolveMediaUrl('https://regen.krishub.in/assets/logo.png'),
        'http://192.168.1.38:5006/assets/logo.png',
      );
    });

    test('Manual Company & Local overrides persist and normalize properly', () async {
      await AppConfig.useLocalServer(localUrlOrIp: '192.168.1.55');
      expect(AppConfig.activeBaseUrl, 'http://192.168.1.55:5006');

      await AppConfig.initCustomUrl(autoProbe: false);
      expect(AppConfig.serverEnvironment, ServerEnvironment.local);
      expect(AppConfig.activeBaseUrl, 'http://192.168.1.55:5006');

      await AppConfig.useCompanyServer();
      expect(AppConfig.activeBaseUrl, 'https://regen.krishub.in');

      expect(
        AppConfig.normalizeServerUrl('https://regen.krishub.in:5006/'),
        'https://regen.krishub.in',
      );
      expect(
        AppConfig.normalizeLocalUrl('http://192.168.1.38:5006/'),
        'http://192.168.1.38:5006',
      );
    });

    testWidgets('SettingsView displays Auto, Company Server, and Local Server options', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await AppConfig.initCustomUrl(autoProbe: false);

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsView(
            user: const UserModel(
              id: 'u1',
              userId: 'EMP1',
              username: 'emp1',
              name: 'Employee One',
              role: 'staff',
              token: 'tok',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Server Connection'), findsOneWidget);
      expect(find.text('Auto (Recommended)'), findsOneWidget);
      expect(find.text('Company Server'), findsOneWidget);
      expect(find.text('Local Server'), findsOneWidget);
      expect(find.text('https://regen.krishub.in'), findsOneWidget);
    });

    test('Startup init(autoProbe: false) is non-blocking and cooldown avoids duplicate probes', () async {
      var probeCalls = 0;
      final mockClient = MockClient((req) async {
        if (req.url.path == '/api/health') {
          probeCalls++;
        }
        throw Exception('LAN unreachable');
      });

      await AppConfig.resetForTest(probeClient: mockClient);
      await AppConfig.initCustomUrl(autoProbe: false, probeClient: mockClient);
      expect(probeCalls, 0);
      expect(AppConfig.activeBaseUrl, 'https://regen.krishub.in');

      await AppConfig.resolveBestBackend(client: mockClient);
      expect(probeCalls, 1);

      // Repeated Splash/Login init calls within cooldown reuse result instead of re-stalling
      await AppConfig.initCustomUrl(probeClient: mockClient);
      await AppConfig.resolveBestBackend(client: mockClient);
      expect(probeCalls, 1);
    });

    test('SessionStorage detects cross-server token mismatch when switching Local <-> Company', () async {
      await AppConfig.useLocalServer(localUrlOrIp: '192.168.1.38');
      const user = UserModel(
        id: 'u1',
        userId: 'EMP1',
        username: 'emp1',
        name: 'Employee One',
        role: 'staff',
        token: 'local_jwt_token',
      );
      await SessionStorage.saveSession(user);
      expect(await SessionStorage.getSessionServerUrl(), 'http://192.168.1.38:5006');
      expect(await SessionStorage.isSessionValidForCurrentServer(), isTrue);

      await AppConfig.useCompanyServer();
      expect(await SessionStorage.isSessionValidForCurrentServer(), isFalse);
    });

    test('AuthService surfaces 403 server message on JSON and proxy responses cleanly', () async {
      await AppConfig.useCompanyServer();
      final json403Client = MockClient((req) async {
        return http.Response(
          jsonEncode({'message': 'Your account is blocked', 'code': 'USER_SUSPENDED'}),
          403,
        );
      });

      final auth = AuthService(client: json403Client);
      await expectLater(
        () => auth.login(username: 'emp1', password: 'secret'),
        throwsA(
          isA<AuthException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.code, 'code', 'USER_SUSPENDED')
              .having((e) => e.message, 'message', 'Your account is blocked'),
        ),
      );

      final html403Client = MockClient((req) async {
        return http.Response('<html>403 Forbidden</html>', 403);
      });
      final authHtml = AuthService(client: html403Client);
      await expectLater(
        () => authHtml.login(username: 'emp1', password: 'secret'),
        throwsA(
          isA<AuthException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.message, 'message', contains('HTTP 403')),
        ),
      );
    });
  });
}
