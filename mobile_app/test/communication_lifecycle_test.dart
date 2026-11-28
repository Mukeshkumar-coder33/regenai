import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:regen_mobile/app/app_config.dart';
import 'package:regen_mobile/core/utils/json_normalizer.dart';
import 'package:regen_mobile/features/auth/data/user_model.dart';
import 'package:regen_mobile/features/dashboard/data/dashboard_service.dart';
import 'package:regen_mobile/features/dashboard/presentation/dashboard_navigation.dart';
import 'package:regen_mobile/features/messenger/data/call_notification_service.dart';
import 'package:regen_mobile/features/messenger/data/communication_diagnostics.dart';
import 'package:regen_mobile/features/messenger/data/e2e_crypto_service.dart';
import 'package:regen_mobile/features/messenger/data/media_download_service.dart';
import 'package:regen_mobile/features/messenger/data/messenger_model.dart';
import 'package:regen_mobile/features/messenger/data/messenger_service.dart';
import 'package:regen_mobile/features/messenger/data/messenger_socket_service.dart';
import 'package:regen_mobile/features/messenger/data/messenger_sound_service.dart';
import 'package:regen_mobile/features/messenger/data/messenger_store.dart';
import 'package:regen_mobile/features/messenger/data/webrtc_call_manager.dart';
import 'package:regen_mobile/features/messenger/presentation/call_overlay.dart';
import 'package:regen_mobile/features/messenger/presentation/messenger_view.dart';
import 'package:regen_mobile/features/notifications/data/notification_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeLiveMessengerService extends MessengerService {
  final List<DmConversationModel> conversations;
  final List<MessengerContactModel> contacts;
  final List<DirectMessageModel> serverMessages;
  final Map<String, Map<String, String>> storedPubKeys = {};
  final Map<String, ({String? privateKey, String? publicKey})> storedMyKeys = {};
  int markReadCalls = 0;

  _FakeLiveMessengerService({
    required this.conversations,
    required this.contacts,
    required this.serverMessages,
  });

  @override
  Future<List<TeamMessageModel>> getTeamMessages({required UserModel user}) async => const [];

  @override
  Future<List<DmConversationModel>> getConversations({required UserModel user}) async =>
      conversations;

  @override
  Future<List<MessengerContactModel>> getAuthorizedContacts({required UserModel user}) async =>
      contacts;

  @override
  Future<List<DirectMessageModel>> getDirectMessages({
    required UserModel user,
    required String conversationId,
  }) async =>
      List<DirectMessageModel>.from(serverMessages);

  @override
  Future<DirectMessageModel?> sendDirectMessage({
    required UserModel user,
    required String conversationId,
    required String content,
    bool isVoice = false,
    bool encrypted = false,
    String iv = '',
    List<Map<String, dynamic>>? attachments,
  }) async {
    final msg = DirectMessageModel(
      id: 'srv-msg-${DateTime.now().microsecondsSinceEpoch}',
      conversationId: conversationId,
      senderId: user.userId,
      senderName: user.name,
      content: content,
      iv: iv,
      encrypted: encrypted,
      timestamp: DateTime.now().toIso8601String(),
      readBy: [user.userId],
    );
    serverMessages.add(msg);
    return msg;
  }

  @override
  Future<bool> markConversationRead({
    required UserModel user,
    required String conversationId,
  }) async {
    markReadCalls++;
    return true;
  }

  @override
  Future<({String? privateKey, String? publicKey})> getUserConversationKey({
    required UserModel user,
    required String conversationId,
  }) async =>
      storedMyKeys[conversationId] ?? (privateKey: null, publicKey: null);

  @override
  Future<bool> storeUserConversationKey({
    required UserModel user,
    required String conversationId,
    required String privateKeyJwkJson,
    required String publicKeyJwkJson,
  }) async {
    storedMyKeys[conversationId] = (privateKey: privateKeyJwkJson, publicKey: publicKeyJwkJson);
    storedPubKeys.putIfAbsent(conversationId, () => {})[user.userId] = publicKeyJwkJson;
    return true;
  }

  @override
  Future<bool> storePublicKey({
    required UserModel user,
    required String conversationId,
    required String publicKeyJwkJson,
  }) async {
    storedPubKeys.putIfAbsent(conversationId, () => {})[user.userId] = publicKeyJwkJson;
    return true;
  }

  @override
  Future<Map<String, String>> getConversationKeys({
    required UserModel user,
    required String conversationId,
  }) async =>
      storedPubKeys[conversationId] ?? const {};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Always-Ready Communication Lifecycle & Preferences', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await WebRtcCallManager.instance.resetOnLogout();
    });

    test('NotificationPreferences persists toggles across reload', () async {
      final prefs = NotificationPreferences.instance;
      await prefs.ensureLoaded();
      expect(prefs.isPushEnabled, isTrue);
      expect(prefs.isSoundEnabled, isTrue);
      expect(prefs.isTaskRemindersEnabled, isTrue);
      expect(prefs.isEmailAlertsEnabled, isTrue);

      await prefs.setPushEnabled(false);
      await prefs.setSoundEnabled(false);
      await prefs.setTaskRemindersEnabled(false);
      await prefs.setEmailAlertsEnabled(false);

      expect(prefs.isPushEnabled, isFalse);
      expect(prefs.isSoundEnabled, isFalse);
      expect(prefs.isTaskRemindersEnabled, isFalse);
      expect(prefs.isEmailAlertsEnabled, isFalse);

      final raw = await SharedPreferences.getInstance();
      expect(raw.getBool('regen_notif_push_enabled'), isFalse);
      expect(raw.getBool('regen_notif_sound_enabled'), isFalse);
      expect(raw.getBool('regen_notif_task_reminders'), isFalse);
      expect(raw.getBool('regen_notif_email_alerts'), isFalse);

      await prefs.setPushEnabled(true);
      await prefs.setSoundEnabled(true);
    });

    test('CallNotificationService separates silent/audible channels & preserves onTap', () async {
      expect(CallNotificationService.callChannelId, 'regen_incoming_calls_v3');
      expect(CallNotificationService.callSilentChannelId, 'regen_incoming_calls_silent_v2');
      expect(CallNotificationService.messageChannelId, 'regen_messages_v2');
      expect(CallNotificationService.missedCallChannelId, 'regen_missed_calls_v2');

      Map<String, dynamic>? tappedPayload;
      await CallNotificationService.instance.initialize(
        onTap: (payload) => tappedPayload = payload,
      );
      // Secondary initialization without onTap MUST NOT wipe existing tap handler
      await CallNotificationService.instance.initialize();
      expect(CallNotificationService.instance.onNotificationTapped, isNotNull);

      CallNotificationService.instance.onNotificationTapped!({'type': 'voice_call', 'callId': 'c-1'});
      expect(tappedPayload?['callId'], 'c-1');
    });

    test('MessengerSoundService deduplicates active call ringtone & stops cleanly', () async {
      final sound = MessengerSoundService.instance;
      await NotificationPreferences.instance.setSoundEnabled(true);

      await sound.startIncomingCallRingtone(callId: 'ring-1');
      expect(sound.isRinging, isTrue);
      expect(sound.activeRingtoneCallId, 'ring-1');

      // Calling again with same callId does not reset or double-ring
      await sound.startIncomingCallRingtone(callId: 'ring-1');
      expect(sound.activeRingtoneCallId, 'ring-1');

      await sound.stopRingtone(reason: 'accepted');
      expect(sound.isRinging, isFalse);
      expect(sound.activeRingtoneCallId, isNull);
    });

    test('WebRtcCallManager binds user cleanly, clears state on logout & handles external cancel', () async {
      final manager = WebRtcCallManager.instance;
      final userA = UserModel(
        id: 'u-a',
        userId: 'u-a',
        username: 'usera',
        name: 'User A',
        role: 'staff',
        token: 'tok-a',
      );
      final userB = UserModel(
        id: 'u-b',
        userId: 'u-b',
        username: 'userb',
        name: 'User B',
        role: 'admin',
        token: 'tok-b',
      );

      manager.bindUser(userA);
      expect(manager.callPhase, CallPhase.idle);

      // Account switch must reset previous session call tracking cleanly
      manager.bindUser(userB);
      expect(manager.callPhase, CallPhase.idle);

      // Terminal cancellation clears ringtone & keeps callPhase idle
      await MessengerSoundService.instance.startIncomingCallRingtone(callId: 'ext-1');
      await manager.handleExternalCallCancelled('ext-1');
      expect(MessengerSoundService.instance.isRinging, isFalse);
      expect(manager.callPhase, CallPhase.idle);

      // Multiple sequential logout/reset cycles leave clean state
      for (var i = 0; i < 5; i++) {
        await manager.resetOnLogout();
        expect(manager.callPhase, CallPhase.idle);
      }
    });

    test('CommunicationDiagnostics logs bounded events with token redaction', () {
      final diag = CommunicationDiagnostics.instance;
      diag.log('test:token_check', {'userId': 'u-1', 'token': 'super-secret-jwt'});
      final recent = diag.recentEvents;
      expect(recent.isNotEmpty, isTrue);
      expect(recent.first['event'], 'test:token_check');
      expect(recent.first['token'], '[REDACTED]');
    });

    test('DashboardNavigation routes all notification types cleanly', () {
      String? routed;
      DashboardNavigation.navigateToPage = (page) => routed = page;

      DashboardNavigation.handleNotificationTap({'type': 'project_task'});
      expect(routed, 'tasks');

      DashboardNavigation.handleNotificationTap({'type': 'leave'});
      expect(routed, 'leave');

      DashboardNavigation.handleNotificationTap({'type': 'payroll'});
      expect(routed, 'payroll');

      DashboardNavigation.handleNotificationTap({'type': 'attendance'});
      expect(routed, 'attendance');

      DashboardNavigation.handleNotificationTap({'type': 'text_message'});
      expect(routed, 'messenger');

      DashboardNavigation.navigateToPage = null;
    });

    test('MessengerStore reducer syncs online users snapshot immediately', () {
      final initial = MessengerState.initial();
      final next = messengerReducer(
        initial,
        const SyncOnlineUsersAction({'U-1', 'u-2'}),
      );
      expect(next.isUserOnline('u-1'), isTrue);
      expect(next.isUserOnline('u-2'), isTrue);
      expect(next.isUserOnline('u-3'), isFalse);
    });

    test('CallPhase includes connecting and CallNotificationService supports background init', () async {
      expect(CallPhase.values.contains(CallPhase.connecting), isTrue);
      await CallNotificationService.instance.initialize(isBackgroundIsolate: true);
      WebRtcCallManager.foregroundCheckOverride = () => true;
      expect(WebRtcCallManager.instance.isForegroundResumed, isTrue);
      WebRtcCallManager.foregroundCheckOverride = () => false;
      expect(WebRtcCallManager.instance.isForegroundResumed, isFalse);
      WebRtcCallManager.foregroundCheckOverride = null;
    });

    test('DashboardNavigation routes team_meeting notifications for wakeup & decline', () {
      DashboardNavigation.handleNotificationTap({
        'type': 'team_meeting',
        'meetingId': 'mtg-test-99',
        'callerName': 'Priya',
        'actionId': 'decline_call',
      });
      expect(WebRtcCallManager.instance.meetingPhase, MeetingPhase.idle);
    });

    test('NotificationStore synchronizes unread badges across arrivals, reads, deletes, clears, and account switches', () {
      final store = NotificationStore.instance;
      store.reset();
      expect(store.unreadCount, 0);

      store.ingestRawNotification({
        'id': 'n-1',
        'userId': 'u-1',
        'title': 'Arun sent a video',
        'message': 'Check this site walkthrough',
        'type': 'text_message',
        'read': false,
        'createdAt': '2026-11-28T10:00:00.000Z',
      });
      store.ingestRawNotification({
        'id': 'n-2',
        'userId': 'u-1',
        'title': 'Leave Approved',
        'message': '2 days casual leave approved',
        'type': 'leave',
        'read': false,
        'createdAt': '2026-11-28T10:01:00.000Z',
      });
      // Duplicate id must NOT double-count
      store.ingestRawNotification({
        'id': 'n-2',
        'userId': 'u-1',
        'title': 'Leave Approved',
        'message': '2 days casual leave approved',
        'type': 'leave',
        'read': false,
      });
      expect(store.items.length, 2);
      expect(store.unreadCount, 2);

      // Single read updates badge immediately
      store.applyReadEvent({'id': 'n-1', 'read': true});
      expect(store.unreadCount, 1);

      // Deleted notification change event removes item and updates badge
      store.applyChangeEvent({'id': 'n-2', 'deleted': true});
      expect(store.items.length, 1);
      expect(store.unreadCount, 0);

      // Unread -> markAll -> clearAll
      store.ingestRawNotification({
        'id': 'n-3',
        'userId': 'u-1',
        'title': 'Task Assigned',
        'message': 'Prepare Q4 report',
        'type': 'project_task',
        'read': false,
      });
      expect(store.unreadCount, 1);
      store.applyReadAllEvent();
      expect(store.unreadCount, 0);
      store.applyClearAllEvent();
      expect(store.items.isEmpty, isTrue);

      store.reset();
    });

    test('DirectMessageModel parses video and voice attachments cleanly', () {
      final msg = DirectMessageModel.fromJson({
        '_id': 'dm-att-1',
        'conversationId': 'conv-1',
        'senderId': 'u-1',
        'senderName': 'Arun',
        'content': '🎥 Video message',
        'attachments': [
          {
            'path': '/assets/dm-video-123.mp4',
            'name': 'site.mp4',
            'type': 'video/mp4',
            'size': 2048000,
          },
          {
            'path': '/assets/dm-voice-456.m4a',
            'name': 'voice.m4a',
            'type': 'audio/mp4',
            'size': 32000,
            'duration': 5,
          },
        ],
      });
      expect(msg.attachments.length, 2);
      expect(msg.attachments[0].isVideo, isTrue);
      expect(msg.attachments[1].isAudio, isTrue);
    });

    test('normalizeJsonMap converts nested Socket.IO maps recursively and MessengerStore appends incoming message', () async {
      final raw = <dynamic, dynamic>{
        'action': 'create',
        'conversationId': 'conv-rt-1',
        'message': <dynamic, dynamic>{
          '_id': 'msg-rt-1',
          'conversationId': 'conv-rt-1',
          'senderId': 'peer-1',
          'senderName': 'Arun',
          'content': 'Live hello',
          'readBy': <dynamic>['peer-1'],
          'timestamp': '2026-11-28T12:00:00.000Z',
        },
      };
      final normalized = normalizeJsonMap(raw);
      expect(normalized['message'], isA<Map<String, dynamic>>());

      final store = MessengerStore.instance;
      store.reset();
      store.init(UserModel(
        id: 'me-1',
        userId: 'me-1',
        username: 'me',
        name: 'Me',
        role: 'staff',
        token: 'tok-me',
      ));
      await store.dispatch(const OpenConversationAction('conv-rt-1'));
      final parsed = DirectMessageModel.fromJson(normalized['message'] as Map<String, dynamic>);
      await store.dispatch(ReceiveSocketMessageAction(parsed));

      expect(store.state.activeMessages.any((m) => m.id == 'msg-rt-1' && m.content == 'Live hello'), isTrue);
      store.reset();
    });

    test('MessengerSoundService suppresses replay of stopped/accepted call ringtones', () async {
      final sound = MessengerSoundService.instance;
      await NotificationPreferences.instance.setSoundEnabled(true);

      await sound.startIncomingCallRingtone(callId: 'sup-call-1');
      expect(sound.isRinging, isTrue);

      await sound.stopRingtone(reason: 'accepted', suppressCallId: 'sup-call-1');
      expect(sound.isRinging, isFalse);

      // Late duplicate push for the same accepted call must NOT restart ringing
      await sound.startIncomingCallRingtone(callId: 'sup-call-1');
      expect(sound.isRinging, isFalse);
    });

    test('MediaDownloadService resolves authenticated DM URL, MIME types, and safe filenames', () {
      final secureUrl = MediaDownloadService.buildSecureDownloadUrl('/assets/dm-video-12345.mp4');
      expect(secureUrl, '${AppConfig.activeBaseUrl}/api/dm/media/dm-video-12345.mp4?download=1');

      expect(MediaDownloadService.inferMimeType('photo.png'), 'image/png');
      expect(MediaDownloadService.inferMimeType('clip.mp4'), 'video/mp4');
      expect(MediaDownloadService.inferMimeType('report.pdf'), 'application/pdf');
      expect(
        MediaDownloadService.inferMimeType('spec.docx'),
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );
      expect(
        MediaDownloadService.inferMimeType('sheet.xlsx'),
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      expect(
        MediaDownloadService.inferMimeType('deck.pptx'),
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      );
      expect(MediaDownloadService.inferMimeType('notes.txt'), 'text/plain');
      expect(
        MediaDownloadService.sanitizeSafeFilename('Q4 Report (Final)/..pdf'),
        'Q4_Report_(Final)_.pdf',
      );
    });

    test('normalizeJsonMap unwraps Socket.IO connectionStateRecovery List envelopes', () {
      final listEnvelope = <dynamic>[
        <dynamic, dynamic>{
          'action': 'create',
          'conversationId': 'conv-wire-1',
          'message': <dynamic, dynamic>{
            '_id': 'msg-wire-1',
            'conversationId': 'conv-wire-1',
            'senderId': 'chrome-user',
            'content': 'Wire list envelope check',
            'readBy': <dynamic>['chrome-user'],
          },
        },
        'Q8YF_ok',
      ];
      final normalized = normalizeJsonMap(listEnvelope);
      expect(normalized['action'], 'create');
      expect(normalized['conversationId'], 'conv-wire-1');
      expect(normalized['message'], isA<Map<String, dynamic>>());
      expect((normalized['message'] as Map<String, dynamic>)['content'], 'Wire list envelope check');
    });

    testWidgets(
      'MessengerView live-renders Chrome Socket.IO List-wrapped messages without reopening chat and updates grey->blue ticks',
      (WidgetTester tester) async {
        const flutterUser = UserModel(
          id: 'mongo-fl-1',
          userId: 'USR-FLUTTER',
          username: 'flutter_user',
          name: 'Flutter User',
          role: 'staff',
          companyId: 'co-1',
          token: 'tok-fl',
        );
        const convId = 'conv-live-chrome-flutter';
        final fakeSvc = _FakeLiveMessengerService(
          conversations: const [
            DmConversationModel(
              conversationId: convId,
              participants: ['USR-CHROME', 'USR-FLUTTER'],
              otherUserId: 'USR-CHROME',
              otherUserName: 'Chrome User',
              otherUserOnline: true,
              lastMessage: 'Initial msg',
              unreadCount: 1,
            ),
          ],
          contacts: const [
            MessengerContactModel(
              id: 'mongo-ch-1',
              userId: 'USR-CHROME',
              username: 'chrome_user',
              name: 'Chrome User',
              role: 'owner',
              companyId: 'co-1',
              online: true,
            ),
          ],
          serverMessages: [
            DirectMessageModel(
              id: 'msg-init-1',
              conversationId: convId,
              senderId: 'USR-CHROME',
              senderName: 'Chrome User',
              content: 'Initial hello',
              timestamp: '2026-11-28T12:00:00.000Z',
              readBy: const ['USR-CHROME'],
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MessengerView(
              user: flutterUser,
              messengerService: fakeSvc,
              dashboardService: DashboardService(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open conversation on Flutter without leaving afterwards
        await tester.tap(find.text('Chrome User'));
        await tester.pumpAndSettle();
        expect(find.text('Initial hello'), findsOneWidget);
        expect(fakeSvc.markReadCalls, greaterThanOrEqualTo(1));

        // Simulate Chrome sending a message over Socket.IO with recovery offset List wrapper
        MessengerSocketService.instance.debugInjectRawEvent('dm:change', <dynamic>[
          <dynamic, dynamic>{
            'action': 'create',
            'conversationId': convId,
            'senderId': 'USR-CHROME',
            'message': <dynamic, dynamic>{
              '_id': 'msg-chrome-live-1',
              'conversationId': convId,
              'senderId': 'USR-CHROME',
              'senderName': 'Chrome User',
              'content': 'Instant from Chrome without reopen',
              'timestamp': '2026-11-28T12:05:00.000Z',
              'readBy': <dynamic>['USR-CHROME'],
            },
          },
          'Q8YF_ok',
        ]);
        await tester.pumpAndSettle();

        expect(find.text('Instant from Chrome without reopen'), findsOneWidget);

        // Duplicate delivery must NOT create a duplicate message bubble
        MessengerSocketService.instance.debugInjectRawEvent('dm:change', <dynamic>[
          <dynamic, dynamic>{
            'action': 'create',
            'conversationId': convId,
            'message': <dynamic, dynamic>{
              '_id': 'msg-chrome-live-1',
              'conversationId': convId,
              'senderId': 'USR-CHROME',
              'content': 'Instant from Chrome without reopen',
              'timestamp': '2026-11-28T12:05:00.000Z',
              'readBy': <dynamic>['USR-CHROME'],
            },
          },
          'Q8YF_dup',
        ]);
        await tester.pumpAndSettle();
        expect(find.text('Instant from Chrome without reopen'), findsOneWidget);

        // REST reconnect refresh with slightly older snapshot must preserve incoming socket message
        MessengerSocketService.instance.debugInjectRawEvent('connection', true);
        await tester.pumpAndSettle();
        expect(find.text('Instant from Chrome without reopen'), findsOneWidget);

        // Flutter user replies -> shows grey ticks first, then turns blue (0xFF38BDF8) on dm:change read
        await tester.enterText(find.byType(TextField).last, 'Reply from Flutter APK');
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pumpAndSettle();
        expect(find.text('Reply from Flutter APK'), findsOneWidget);

        // Confirm no blue tick before Chrome reads
        final preReadBlueTicks = tester.widgetList<Icon>(find.byIcon(Icons.done_all_rounded))
            .where((ic) => ic.color == const Color(0xFF38BDF8))
            .length;
        expect(preReadBlueTicks, 0);

        // Emit Chrome read receipt wrapped in Socket.IO List recovery envelope
        MessengerSocketService.instance.debugInjectRawEvent('dm:change', <dynamic>[
          <dynamic, dynamic>{
            'action': 'read',
            'conversationId': convId,
            'userId': 'USR-CHROME',
            'readBy': <dynamic>['USR-CHROME'],
          },
          'Q8YF_rd',
        ]);
        await tester.pumpAndSettle();

        final postReadBlueTicks = tester.widgetList<Icon>(find.byIcon(Icons.done_all_rounded))
            .where((ic) => ic.color == const Color(0xFF38BDF8))
            .length;
        expect(postReadBlueTicks, 1);

        // E2E encrypted Chrome message decrypts live using shared key
        const e2eConv = 'conv-e2e-check';
        final chromePub = await E2eCryptoService.generateKeyPair(e2eConv, userId: 'chrome-e2e');
        final flutterPub = await E2eCryptoService.generateKeyPair(e2eConv, userId: 'USR-FLUTTER');
        final senderShared = await E2eCryptoService.deriveSharedKey(e2eConv, flutterPub, userId: 'chrome-e2e');
        final recvShared = await E2eCryptoService.deriveSharedKey(e2eConv, chromePub, userId: 'USR-FLUTTER');
        expect(senderShared, isNotNull);
        expect(recvShared, isNotNull);
        final cipher = await E2eCryptoService.encryptMessage(senderShared!, 'Secret live check');
        final decrypted = await E2eCryptoService.decryptMessage(recvShared!, cipher.ciphertext, cipher.iv);
        expect(decrypted, 'Secret live check');
      },
    );

    testWidgets('CallOverlay suppresses generic banner for call and meeting control notifications', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CallOverlay(
              child: Center(child: Text('App Home')),
            ),
          ),
        ),
      );

      MessengerSocketService.instance.debugInjectRawEvent('notification:new', <dynamic>[
        <dynamic, dynamic>{
          'id': 'call-notif-suppress-1',
          'userId': 'USR-FLUTTER',
          'senderId': 'USR-CHROME',
          'title': 'Incoming Video Call',
          'message': 'Chrome User is calling you...',
          'type': 'video_call',
          'callId': 'call-suppress-1',
        },
        'Q8YF_c1',
      ]);
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Chrome User is calling you...'), findsNothing);
    });

    test('WebRtcCallManager unwraps List<dynamic> Socket.IO envelopes for incoming, accept/state, cancel, and meeting host alias', () async {
      const me = UserModel(
        id: 'mongo-recv-1',
        userId: 'USR-RECV',
        username: 'recv_alias',
        name: 'Receiver',
        role: 'staff',
        token: 'tok-recv',
      );
      WebRtcCallManager.instance.bindUser(me);
      WebRtcCallManager.foregroundCheckOverride = () => true;

      // Incoming call delivered as Socket.IO List envelope [payloadMap, offset]
      MessengerSocketService.instance.debugInjectRawEvent('call:incoming', <dynamic>[
        <dynamic, dynamic>{
          'callId': 'call-env-1',
          'callerId': 'USR-CALLER',
          'callerName': 'Arun',
          'mediaType': 'video',
        },
        'Q8YF_in',
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(WebRtcCallManager.instance.callPhase, CallPhase.incoming);
      expect(WebRtcCallManager.instance.callId, 'call-env-1');
      expect(WebRtcCallManager.instance.callMediaType, 'video');

      // Cancelled delivered as Socket.IO List envelope stops ringtone & resets phase
      MessengerSocketService.instance.debugInjectRawEvent('call:cancelled', <dynamic>[
        <dynamic, dynamic>{'callId': 'call-env-1', 'reason': 'cancelled'},
        'Q8YF_cn',
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(WebRtcCallManager.instance.callPhase, CallPhase.idle);
      expect(MessengerSoundService.instance.isRinging, isFalse);

      // Group meeting invite from own username alias must be ignored
      MessengerSocketService.instance.debugInjectRawEvent('meeting:started', <dynamic>[
        <dynamic, dynamic>{
          'meetingId': 'mtg-self-alias-1',
          'hostId': 'recv_alias',
          'hostName': 'Receiver',
          'title': 'Team Sync',
          'mediaType': 'video',
        },
        'Q8YF_m1',
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(WebRtcCallManager.instance.meetingPhase, MeetingPhase.idle);

      WebRtcCallManager.foregroundCheckOverride = null;
    });

    test('WebRtcCallManager prevents InvalidStateError on concurrent call:accepted and call:state(accepted)', () async {
      final pc = _FakePeerConnection();
      WebRtcCallManager.instance.seedOutgoingCallForTest(
        callId: 'call-sdp-race-1',
        peerConnection: pc,
      );

      final acceptedPayload = <String, dynamic>{
        'callId': 'call-sdp-race-1',
        'answer': <String, dynamic>{'type': 'answer', 'sdp': 'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'},
        'recipientCandidates': <dynamic>[],
      };
      final statePayload = <String, dynamic>{
        'callId': 'call-sdp-race-1',
        'state': 'accepted',
        'answer': <String, dynamic>{'type': 'answer', 'sdp': 'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'},
      };

      // Dispatch both signaling events concurrently before awaiting either
      await Future.wait([
        WebRtcCallManager.instance.debugHandleCallAcceptedForTest(acceptedPayload),
        WebRtcCallManager.instance.debugHandleCallStateForTest(statePayload),
      ]);

      expect(pc.setRemoteDescriptionCalls, 1);
      expect(WebRtcCallManager.instance.callPhase, CallPhase.connecting);
      expect(WebRtcCallManager.instance.callId, 'call-sdp-race-1');
      expect(WebRtcCallManager.instance.statusMessage, isNull);

      // Clean up test call state safely
      await WebRtcCallManager.instance.debugHandleCallStateForTest({
        'callId': 'call-sdp-race-1',
        'state': 'ended',
      });
      expect(WebRtcCallManager.instance.callPhase, CallPhase.idle);
    });

    test('CallNotificationService uses looping raw ringtone (FLAG_INSISTENT) when terminated and deduplicates media/missed IDs', () {
      final audibleDetails = CallNotificationService.buildIncomingCallAndroidDetails(silent: false);
      expect(audibleDetails.channelId, 'regen_incoming_calls_v3');
      expect(audibleDetails.playSound, isTrue);
      expect(audibleDetails.sound, isA<RawResourceAndroidNotificationSound>());
      expect((audibleDetails.sound as RawResourceAndroidNotificationSound).sound, 'regen_ringtone');
      expect(audibleDetails.additionalFlags, contains(CallNotificationService.flagInsistent));
      expect(audibleDetails.fullScreenIntent, isTrue);
      expect(audibleDetails.ongoing, isTrue);
      expect(audibleDetails.actions?.map((a) => a.id), containsAll(['accept_call', 'decline_call']));

      final silentDetails = CallNotificationService.buildIncomingCallAndroidDetails(silent: true);
      expect(silentDetails.channelId, 'regen_incoming_calls_silent_v2');
      expect(silentDetails.playSound, isFalse);
      expect(silentDetails.additionalFlags, isNull);

      CallNotificationService.instance.resetDedupForTest();
      expect(CallNotificationService.instance.rememberNotificationOnceForTest('msg:dm-media-1-u2'), isTrue);
      expect(CallNotificationService.instance.rememberNotificationOnceForTest('msg:dm-media-1-u2'), isFalse);
      expect(CallNotificationService.instance.rememberNotificationOnceForTest('missed:call-99'), isTrue);
      expect(CallNotificationService.instance.rememberNotificationOnceForTest('missed:call-99'), isFalse);
      CallNotificationService.instance.resetDedupForTest();
    });

    testWidgets('DashboardNavigation routes missed_call and media taps through login directly into MessengerView conversation', (tester) async {
      DashboardNavigation.resetForTest();
      final me = const UserModel(
        id: 'mongo-me-nav',
        userId: 'USR-NAV-ME',
        username: 'nav_me',
        name: 'Nav Me',
        role: 'owner',
        token: 'tok-nav',
      );
      final targetConv = const DmConversationModel(
        conversationId: 'conv-nav-42',
        participants: ['USR-NAV-ME', 'USR-NAV-PEER'],
        isGroup: false,
        name: '',
        scope: 'company',
        createdBy: 'USR-NAV-ME',
        otherUserId: 'USR-NAV-PEER',
        otherUserName: 'Priya Sharma',
        otherUserRole: 'staff',
        otherUserOnline: true,
        lastMessage: 'Missed voice call',
        lastTimestamp: '2026-11-28T11:00:00.000Z',
      );
      final fakeService = _FakeLiveMessengerService(
        conversations: [targetConv],
        contacts: const [
          MessengerContactModel(
            id: 'mongo-peer-nav',
            userId: 'USR-NAV-PEER',
            username: 'priya',
            name: 'Priya Sharma',
            role: 'staff',
            online: true,
          ),
        ],
        serverMessages: [
          DirectMessageModel(
            id: 'dm-nav-1',
            conversationId: 'conv-nav-42',
            senderId: 'USR-NAV-PEER',
            senderName: 'Priya Sharma',
            content: 'Photo attached for verification',
            timestamp: '2026-11-28T11:00:00.000Z',
            readBy: const ['USR-NAV-PEER'],
          ),
        ],
      );

      // Simulate terminated notification tap arriving before dashboard/login finishes
      DashboardNavigation.handleNotificationTap({
        'type': 'missed_call',
        'notificationId': 'missed-call-nav-42',
        'callId': 'call-nav-42',
        'callerId': 'USR-NAV-PEER',
        'callerName': 'Priya Sharma',
        'conversationId': 'conv-nav-42',
      });
      // Immediate duplicate launch tap must be deduplicated cleanly
      DashboardNavigation.handleNotificationTap({
        'type': 'missed_call',
        'notificationId': 'missed-call-nav-42',
        'callId': 'call-nav-42',
        'callerId': 'USR-NAV-PEER',
        'callerName': 'Priya Sharma',
        'conversationId': 'conv-nav-42',
      });

      expect(DashboardNavigation.pendingTargetPage, 'messenger');
      expect(DashboardNavigation.pendingConversationPayload?['conversationId'], 'conv-nav-42');

      String? navigatedPage;
      DashboardNavigation.navigateToPage = (p) => navigatedPage = p;
      // Consume pendingTargetPage as DashboardScreen / CompanyDashboardView initState does
      final pendingPage = DashboardNavigation.pendingTargetPage;
      DashboardNavigation.pendingTargetPage = null;
      expect(pendingPage, 'messenger');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessengerView(
              user: me,
              embedded: true,
              messengerService: fakeService,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify MessengerView automatically opened target conversation without extra user taps
      expect(find.text('Photo attached for verification'), findsOneWidget);
      expect(navigatedPage, isNull);
      DashboardNavigation.resetForTest();
    });

    test('DashboardNavigation defers cold-start call Accept until user bound and honors persisted background Reject', () async {
      await WebRtcCallManager.instance.resetOnLogout();
      DashboardNavigation.resetForTest();
      expect(WebRtcCallManager.instance.hasBoundUser, isFalse);

      DashboardNavigation.handleNotificationTap({
        'type': 'voice_call',
        'callId': 'call-cold-accept-1',
        'callerId': 'USR-CALLER-1',
        'callerName': 'Kiran',
        'mediaType': 'voice',
        'actionId': 'accept_call',
      });

      expect(DashboardNavigation.pendingCallWakeupPayload?['callId'], 'call-cold-accept-1');
      expect(DashboardNavigation.pendingCallWakeupPayload?['actionId'], 'accept_call');

      // Persist a background notification Decline decision and ensure wakeup stays blocked
      await CallNotificationService.persistRejectedCallId('call-bg-declined-99');
      expect(await CallNotificationService.isCallIdRejected('call-bg-declined-99'), isTrue);

      const boundUser = UserModel(
        id: 'mongo-cold-u1',
        userId: 'USR-COLD-1',
        username: 'cold_u1',
        name: 'Cold User',
        role: 'staff',
        token: 'tok-cold-1',
      );
      WebRtcCallManager.instance.bindUser(boundUser);
      expect(WebRtcCallManager.instance.hasBoundUser, isTrue);

      await WebRtcCallManager.instance.handleExternalCallWakeup(
        callId: 'call-bg-declined-99',
        callerId: 'USR-CALLER-1',
        callerName: 'Kiran',
        autoAccept: true,
      );
      expect(WebRtcCallManager.instance.callPhase, CallPhase.idle);

      DashboardNavigation.flushPendingCallWakeup();
      expect(DashboardNavigation.pendingCallWakeupPayload, isNull);
      DashboardNavigation.resetForTest();
    });

    testWidgets('Team Channel prevents duplicate message rendering when HTTP response, Socket message:change, and REST refresh overlap', (tester) async {
      const staffUser = UserModel(
        id: 'mongo-team-u1',
        userId: 'USR-TEAM-1',
        username: 'team_u1',
        name: 'Ananya',
        role: 'staff',
        companyId: 'co-team-1',
        token: 'tok-team-1',
      );
      final teamSvc = _FakeTeamChannelMessengerService();

      await tester.pumpWidget(
        MaterialApp(
          home: MessengerView(
            user: staffUser,
            messengerService: teamSvc,
            dashboardService: DashboardService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Team Channel tab
      await tester.tap(find.text('Team Channel'));
      await tester.pumpAndSettle();

      // Enter & send message; _FakeTeamChannelMessengerService emits message:change BEFORE returning HTTP response
      await tester.enterText(find.byType(TextField).last, 'Team meeting starting at 4 PM');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      // Inject duplicate socket message:change packets (reconnect / multi-room replay)
      final created = teamSvc.persistedTeamMessages.first;
      MessengerSocketService.instance.debugInjectRawEvent('message:change', {
        'action': 'create',
        'id': created.messageId,
        'message': {
          '_id': created.id,
          'messageId': created.messageId,
          'senderId': created.senderId,
          'senderName': created.senderName,
          'content': created.content,
          'timestamp': created.timestamp,
        },
      });
      await tester.pumpAndSettle();

      // Simulate reconnect REST history refresh
      MessengerSocketService.instance.debugInjectRawEvent('connection', true);
      await tester.pumpAndSettle();

      expect(find.text('Team meeting starting at 4 PM'), findsOneWidget);
      expect(teamSvc.persistedTeamMessages.length, 1);
    });
  });
}

class _FakeTeamChannelMessengerService extends _FakeLiveMessengerService {
  final List<TeamMessageModel> persistedTeamMessages = [];

  _FakeTeamChannelMessengerService()
      : super(
          conversations: const [],
          contacts: const [],
          serverMessages: const [],
        );

  @override
  Future<List<TeamMessageModel>> getTeamMessages({required UserModel user}) async =>
      List<TeamMessageModel>.from(persistedTeamMessages);

  @override
  Future<TeamMessageModel?> sendTeamMessage({
    required UserModel user,
    required String content,
    List<Map<String, dynamic>>? attachments,
    String? clientMessageId,
  }) async {
    final msgId = clientMessageId ?? 'msg-team-fixed-101';
    final serverJson = <String, dynamic>{
      '_id': 'mongo-team-msg-101',
      'messageId': msgId,
      'id': msgId,
      'senderId': user.userId,
      'senderName': user.name,
      'content': content,
      'timestamp': '2026-11-28T16:00:00.000Z',
    };
    final model = TeamMessageModel.fromJson(serverJson);
    persistedTeamMessages.add(model);

    // Reproduce exact server race: emit Socket.IO `message:change` BEFORE HTTP 201 returns to sender!
    MessengerSocketService.instance.debugInjectRawEvent('message:change', {
      'action': 'create',
      'id': msgId,
      'message': serverJson,
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return model;
  }
}

class _FakePeerConnection extends Fake implements RTCPeerConnection {
  RTCSignalingState _state = RTCSignalingState.RTCSignalingStateHaveLocalOffer;
  int setRemoteDescriptionCalls = 0;

  @override
  RTCSignalingState? get signalingState => _state;

  @override
  Future<RTCSignalingState> getSignalingState() async => _state;

  @override
  RTCPeerConnectionState? get connectionState =>
      RTCPeerConnectionState.RTCPeerConnectionStateConnecting;

  @override
  RTCIceConnectionState? get iceConnectionState =>
      RTCIceConnectionState.RTCIceConnectionStateChecking;

  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    setRemoteDescriptionCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (_state == RTCSignalingState.RTCSignalingStateStable) {
      throw Exception("InvalidStateError: Failed to execute 'setRemoteDescription': Called in wrong state: stable");
    }
    _state = RTCSignalingState.RTCSignalingStateStable;
  }

  @override
  Future<void> addCandidate(RTCIceCandidate candidate) async {}

  @override
  Future<void> close() async {
    _state = RTCSignalingState.RTCSignalingStateClosed;
  }
}
