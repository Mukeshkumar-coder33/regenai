import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:regen_mobile/features/auth/data/user_model.dart';
import 'package:regen_mobile/features/auth/presentation/auth_controller.dart';
import 'package:regen_mobile/features/messenger/data/e2e_crypto_service.dart';
import 'package:regen_mobile/features/messenger/data/messenger_service.dart';
import 'package:regen_mobile/features/messenger/data/messenger_store.dart';
import 'package:regen_mobile/features/messenger/data/webrtc_call_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Role Switching State Synchronization & Isolation Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      MessengerService.clearKeysCache();
      MessengerStore.instance.reset();
    });

    test('E2eCryptoService strictly isolates keys per user; User B never steals User A key', () async {
      const convId = 'conv_99999';
      const userA = 'vyshwa';
      const userB = 'emp101';

      // 1. User A generates keypair for conversation
      final pubKeyA = await E2eCryptoService.generateKeyPair(convId, userId: userA);
      expect(pubKeyA.isNotEmpty, isTrue);

      final hasKeyA = await E2eCryptoService.hasKeyPair(convId, userId: userA);
      expect(hasKeyA, isTrue);

      // 2. User B logs in on same device for same conversation
      // User B MUST NOT have a key yet (MUST NOT steal User A's key)
      final hasKeyB = await E2eCryptoService.hasKeyPair(convId, userId: userB);
      expect(hasKeyB, isFalse);

      final privKeyB = await E2eCryptoService.getStoredPrivateKey(convId, userId: userB);
      expect(privKeyB, isNull);

      final pubKeyB = await E2eCryptoService.getStoredPublicKey(convId, userId: userB);
      expect(pubKeyB, isNull);

      // 3. User B generates distinct keypair
      final newPubKeyB = await E2eCryptoService.generateKeyPair(convId, userId: userB);
      expect(newPubKeyB.isNotEmpty, isTrue);
      expect(newPubKeyB != pubKeyA, isTrue); // Distinct keypairs
    });

    test('MessengerService.clearKeysCache purges static conversation key cache on logout', () {
      final service = MessengerService();
      service.cacheKeys('conv_test', {'user1': 'key1'});
      expect(service.getCachedKeys('conv_test'), isNotNull);
      expect(service.getCachedKeys('conv_test')!['user1'], equals('key1'));

      MessengerService.clearKeysCache();
      expect(service.getCachedKeys('conv_test'), isNull);
    });

    test('MessengerStore reinitializes when user or role changes and resets completely', () {
      const companyUser = UserModel(
        id: 'user_111',
        userId: 'vyshwa',
        username: 'vyshwa',
        name: 'Vyshwa Admin',
        role: 'company_admin',
        token: 'token_admin',
      );

      const employeeUser = UserModel(
        id: 'user_222',
        userId: 'emp_01',
        username: 'emp_01',
        name: 'John Staff',
        role: 'employee',
        token: 'token_staff',
      );

      final store = MessengerStore.instance;

      // 1. Initialize for company user
      store.initialize(companyUser);
      expect(store.currentUser?.role, equals('company_admin'));
      expect(store.currentUser?.userId, equals('vyshwa'));

      // 2. Initialize for employee user (simulating role switch)
      store.initialize(employeeUser);
      expect(store.currentUser?.role, equals('employee'));
      expect(store.currentUser?.userId, equals('emp_01'));

      // 3. Reset on logout
      store.reset();
      expect(store.currentUser, isNull);
    });

    test('AuthController.logout triggers full teardown without lingering state', () async {
      final authCtrl = AuthController();
      await authCtrl.logout();

      expect(authCtrl.currentUser, isNull);
      expect(authCtrl.errorMessage, isNull);
      expect(MessengerStore.instance.currentUser, isNull);
      expect(WebRtcCallManager.instance.callId, isNull);
    });
  });
}
