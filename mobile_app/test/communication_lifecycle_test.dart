import 'package:flutter_test/flutter_test.dart';
import 'package:regen_mobile/features/auth/data/user_model.dart';
import 'package:regen_mobile/features/dashboard/presentation/dashboard_navigation.dart';
import 'package:regen_mobile/features/messenger/data/call_notification_service.dart';
import 'package:regen_mobile/features/messenger/data/communication_diagnostics.dart';
import 'package:regen_mobile/features/messenger/data/messenger_model.dart';
import 'package:regen_mobile/features/messenger/data/messenger_sound_service.dart';
import 'package:regen_mobile/features/messenger/data/messenger_store.dart';
import 'package:regen_mobile/features/messenger/data/webrtc_call_manager.dart';
import 'package:regen_mobile/features/notifications/data/notification_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      expect(CallNotificationService.callChannelId, 'regen_incoming_calls_v2');
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
  });
}
