import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../auth/data/user_model.dart';
import 'communication_diagnostics.dart';
import 'messenger_service.dart';

/// Top-level background notification action handler required when the user taps
/// notification action buttons (e.g. Decline) while the app UI isolate is terminated.
@pragma('vm:entry-point')
Future<void> onBackgroundNotificationResponse(NotificationResponse response) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    final rawPayload = response.payload;
    if (rawPayload != null && rawPayload.isNotEmpty) {
      final decoded = jsonDecode(rawPayload) as Map<String, dynamic>;
      final callId = (decoded['callId'] ?? decoded['meetingId'] ?? '').toString();
      if (callId.isNotEmpty) {
        final plugin = FlutterLocalNotificationsPlugin();
        const settings = InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        );
        await plugin.initialize(settings: settings);
        await plugin.cancel(id: callId.hashCode & 0x7FFFFFFF);
        await plugin.cancel(id: ('call:$callId').hashCode & 0x7FFFFFFF);
        await plugin.cancel(id: 0, tag: 'call:$callId');
      }
      if (response.actionId != null && response.actionId!.isNotEmpty) {
        decoded['actionId'] = response.actionId;
      }
      CallNotificationService.instance.queueBackgroundResponseForTestOrLaunch(decoded);
    }
  } catch (_) {}
}

/// Mobile Call & Message Notification Service (Android & iOS)
///
/// - Configures dedicated Android notification channels:
///   1. `regen_incoming_calls_v3`: Background/terminated incoming calls (max priority, looping ringtone WAV `FLAG_INSISTENT`, vibration, fullScreenIntent)
///   2. `regen_incoming_calls_silent_v2`: Foreground heads-up calls (`playSound: false` so it never overlaps MessengerSoundService ringtone)
///   3. `regen_messages_v2`: Messages (respects message/sound settings)
///   4. `regen_missed_calls_v2`: Missed call alerts
/// - Provides Accept & Decline Android notification actions directly on incoming calls.
/// - Deduplicates notifications across Socket.IO + FCM by sharing exact Android `(tag, id: 0)` slots.
class CallNotificationService {
  CallNotificationService._();
  static final CallNotificationService instance = CallNotificationService._();

  static const String callChannelId = 'regen_incoming_calls_v3';
  static const String legacyCallChannelId = 'regen_incoming_calls_v2';
  static const String callChannelName = 'Incoming Voice & Video Calls';
  static const String callSilentChannelId = 'regen_incoming_calls_silent_v2';
  static const String callSilentChannelName = 'Incoming Calls (In-App Ringtone)';
  static const String messageChannelId = 'regen_messages_v2';
  static const String messageChannelName = 'ReGen Messages';
  static const String missedCallChannelId = 'regen_missed_calls_v2';
  static const String missedCallChannelName = 'Missed Calls';
  static const String ringtoneRawResource = 'regen_ringtone';
  static const int flagInsistent = 4; // Android Notification.FLAG_INSISTENT

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _channelsInitialized = false;
  final Set<String> _activeCallNotificationIds = <String>{};
  final Set<String> _recentDedupIds = <String>{};
  void Function(Map<String, dynamic> payload)? onNotificationTapped;
  Map<String, dynamic>? _launchPayload;

  bool get _isMobilePlatform =>
      !kIsWeb &&
      !WidgetsBinding.instance.runtimeType.toString().contains('Test') &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool _rememberOnce(String dedupKey) {
    if (_recentDedupIds.contains(dedupKey)) return false;
    _recentDedupIds.add(dedupKey);
    if (_recentDedupIds.length > 300) {
      _recentDedupIds.remove(_recentDedupIds.first);
    }
    return true;
  }

  /// Record a deduplication key and return whether it is new (exposed for regression tests).
  @visibleForTesting
  bool rememberNotificationOnceForTest(String dedupKey) => _rememberOnce(dedupKey);

  /// Reset in-memory deduplication state between tests.
  @visibleForTesting
  void resetDedupForTest() {
    _activeCallNotificationIds.clear();
    _recentDedupIds.clear();
    _launchPayload = null;
  }

  void queueBackgroundResponseForTestOrLaunch(Map<String, dynamic> payload) {
    _launchPayload = payload;
  }

  /// Build incoming call Android details for inspection in unit tests and notification posting.
  @visibleForTesting
  static AndroidNotificationDetails buildIncomingCallAndroidDetails({
    bool silent = false,
  }) {
    final effectiveChannelId = silent ? callSilentChannelId : callChannelId;
    final effectiveChannelName = silent ? callSilentChannelName : callChannelName;
    return AndroidNotificationDetails(
      effectiveChannelId,
      effectiveChannelName,
      channelDescription:
          'Real-time incoming voice and video calls from ReGen Messenger',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.call,
      audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
      visibility: NotificationVisibility.public,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      playSound: !silent,
      sound: silent ? null : const RawResourceAndroidNotificationSound(ringtoneRawResource),
      additionalFlags: silent ? null : Int32List.fromList(<int>[flagInsistent]),
      enableVibration: true,
      timeoutAfter: 46000,
      vibrationPattern: Int64List.fromList([0, 1000, 800, 1000, 800, 1000]),
      actions: const [
        AndroidNotificationAction(
          'accept_call',
          'Accept',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          'decline_call',
          'Decline',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );
  }

  Map<String, dynamic>? takePendingLaunchPayload() {
    final p = _launchPayload;
    _launchPayload = null;
    return p;
  }

  Future<void> initialize({
    void Function(Map<String, dynamic> payload)? onTap,
    bool isBackgroundIsolate = false,
  }) async {
    // Only replace tap handler when explicitly provided (prevents secondary callers wiping it!)
    if (onTap != null) {
      onNotificationTapped = onTap;
    }
    if (!_isMobilePlatform) return;
    if (isBackgroundIsolate && _channelsInitialized) return;
    if (!isBackgroundIsolate && _initialized) return;

    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const settings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
      );

      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (response) {
          _dispatchNotificationResponse(response);
        },
        onDidReceiveBackgroundNotificationResponse: onBackgroundNotificationResponse,
      );

      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      const callChannel = AndroidNotificationChannel(
        callChannelId,
        callChannelName,
        description: 'Real-time incoming voice and video calls when app is backgrounded or terminated',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(ringtoneRawResource),
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
      );

      const callSilentChannel = AndroidNotificationChannel(
        callSilentChannelId,
        callSilentChannelName,
        description: 'Visual incoming call notification when in-app ringtone is active',
        importance: Importance.max,
        playSound: false,
        enableVibration: true,
      );

      const messageChannel = AndroidNotificationChannel(
        messageChannelId,
        messageChannelName,
        description: 'New text and voice messages in ReGen Messenger',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.notification,
      );

      const missedCallChannel = AndroidNotificationChannel(
        missedCallChannelId,
        missedCallChannelName,
        description: 'Missed voice and video calls in ReGen Messenger',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.notification,
      );

      await androidImpl?.createNotificationChannel(callChannel);
      await androidImpl?.createNotificationChannel(callSilentChannel);
      await androidImpl?.createNotificationChannel(messageChannel);
      await androidImpl?.createNotificationChannel(missedCallChannel);
      _channelsInitialized = true;

      if (!isBackgroundIsolate) {
        // Capture cold-start notification launch payload only when an Activity exists
        try {
          final details = await _plugin.getNotificationAppLaunchDetails();
          if (details != null && details.didNotificationLaunchApp && details.notificationResponse != null) {
            final parsed = _parseResponse(details.notificationResponse!);
            if (parsed != null) {
              _launchPayload = parsed;
              if (onNotificationTapped != null) {
                final p = takePendingLaunchPayload();
                if (p != null) onNotificationTapped!(p);
              }
            }
          }
        } catch (_) {}

        try {
          await androidImpl?.requestNotificationsPermission();
          await androidImpl?.requestFullScreenIntentPermission();
        } catch (_) {}
      }

      _initialized = true;
      CommunicationDiagnostics.instance.log('notif:initialized', {
        'background': isBackgroundIsolate,
      });
    } catch (e) {
      CommunicationDiagnostics.instance.log('notif:init_failed', {'error': e.toString()});
    }
  }

  Map<String, dynamic>? _parseResponse(NotificationResponse response) {
    if (response.payload == null || response.payload!.isEmpty) return null;
    try {
      final decoded = jsonDecode(response.payload!) as Map<String, dynamic>;
      if (response.actionId != null && response.actionId!.isNotEmpty) {
        decoded['actionId'] = response.actionId;
      }
      return decoded;
    } catch (_) {
      return null;
    }
  }

  void _dispatchNotificationResponse(NotificationResponse response) {
    final decoded = _parseResponse(response);
    if (decoded == null) return;
    CommunicationDiagnostics.instance.log('notif:tapped', {
      'type': decoded['type'],
      'callId': decoded['callId'] ?? '',
      'actionId': decoded['actionId'] ?? '',
    });
    if (onNotificationTapped != null) {
      onNotificationTapped!(decoded);
    } else {
      _launchPayload = decoded;
    }
  }

  /// Display a high-priority incoming call notification (with Android full-screen intent & Accept/Decline actions).
  /// Pass [silent] = true when in-app ringtone via MessengerSoundService owns the audio stream.
  Future<void> showIncomingCallNotification({
    required String callId,
    required String callerName,
    required String mediaType,
    String? callerId,
    bool isMeeting = false,
    bool silent = false,
  }) async {
    if (!_initialized || !_isMobilePlatform) return;
    if (_activeCallNotificationIds.contains(callId)) return;
    _activeCallNotificationIds.add(callId);

    try {
      final details = NotificationDetails(
        android: buildIncomingCallAndroidDetails(silent: silent),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: !silent,
          presentBadge: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      );

      final title = isMeeting
          ? 'Group ${mediaType == 'voice' ? 'Voice' : 'Video'} Call'
          : 'Incoming ${mediaType == 'video' ? 'Video' : 'Voice'} Call';

      await _plugin.show(
        id: _notifIntId('call:$callId'),
        title: title,
        body: isMeeting ? '$callerName started a group call' : '$callerName is calling you...',
        notificationDetails: details,
        payload: jsonEncode({
          'type': isMeeting ? 'team_meeting' : 'call',
          'callId': callId,
          if (isMeeting) 'meetingId': callId,
          'callerId': callerId ?? '',
          'callerName': callerName,
          'mediaType': mediaType,
        }),
      );
      CommunicationDiagnostics.instance.log('notif:call_shown', {'callId': callId, 'silent': silent});
    } catch (e) {
      CommunicationDiagnostics.instance.log('notif:call_error', {'callId': callId, 'error': e.toString()});
    }
  }

  static int _notifIntId(String key) => key.hashCode & 0x7FFFFFFF;

  Future<void> cancelCallNotification(String callId) async {
    _activeCallNotificationIds.remove(callId);
    if (!_initialized || !_isMobilePlatform) return;
    try {
      await _plugin.cancel(id: _notifIntId('call:$callId'));
      await _plugin.cancel(id: 0, tag: 'call:$callId');
      // Backward compatibility for legacy unprefixed ID
      await _plugin.cancel(id: callId.hashCode & 0x7FFFFFFF);
    } catch (_) {}
  }

  /// Cancels ONLY active incoming call notifications across isolates (never wipes message/task alerts!).
  Future<void> cancelAllCallNotifications() async {
    final ids = List<String>.from(_activeCallNotificationIds);
    _activeCallNotificationIds.clear();
    if (!_initialized || !_isMobilePlatform) return;
    for (final callId in ids) {
      try {
        await _plugin.cancel(id: _notifIntId('call:$callId'));
        await _plugin.cancel(id: 0, tag: 'call:$callId');
        await _plugin.cancel(id: callId.hashCode & 0x7FFFFFFF);
      } catch (_) {}
    }
    try {
      final active = await _plugin.getActiveNotifications();
      for (final notif in active) {
        if (notif.channelId == callChannelId ||
            notif.channelId == legacyCallChannelId ||
            notif.channelId == callSilentChannelId) {
          if (notif.id != null) {
            await _plugin.cancel(id: notif.id!, tag: notif.tag);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> showMessageNotification({
    required String id,
    required String senderName,
    required String preview,
    String? senderId,
    String? conversationId,
    String notificationType = 'message',
  }) async {
    await NotificationPreferences.instance.ensureLoaded();
    if (!NotificationPreferences.instance.isPushEnabled) return;
    if (notificationType == 'project_task' &&
        !NotificationPreferences.instance.isTaskRemindersEnabled) {
      return;
    }
    if (!_rememberOnce('msg:$id')) return;
    if (!_initialized || !_isMobilePlatform) return;
    try {
      final playSound = NotificationPreferences.instance.isSoundEnabled;
      final useTag = defaultTargetPlatform == TargetPlatform.android;
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          messageChannelId,
          messageChannelName,
          channelDescription: 'New text, voice, task and approval notifications in ReGen',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
          visibility: NotificationVisibility.public,
          onlyAlertOnce: true,
          autoCancel: true,
          playSound: playSound,
          enableVibration: true,
          tag: id,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: playSound,
          presentBadge: true,
        ),
      );

      // Share `(id: 0, tag: id)` on Android so OS-rendered FCM and local fallback never duplicate.
      await _plugin.show(
        id: useTag ? 0 : _notifIntId('msg:$id'),
        title: senderName,
        body: preview,
        notificationDetails: details,
        payload: jsonEncode({
          'type': notificationType,
          'conversationId': conversationId ?? '',
          'senderId': senderId ?? '',
          'senderName': senderName,
          'notificationId': id,
        }),
      );
      CommunicationDiagnostics.instance.log('notif:message_shown', {'id': id, 'type': notificationType});
    } catch (_) {}
  }

  /// Display a deduplicated missed call notification when caller hangs up/times out.
  Future<void> showMissedCallNotification({
    required String id,
    required String callerName,
    String? callerId,
    String mediaType = 'voice',
    String? conversationId,
    String? callId,
  }) async {
    final normalizedCallId = (callId ?? '').trim();
    final dedupKey = 'missed:${normalizedCallId.isNotEmpty ? normalizedCallId : id}';
    if (!_rememberOnce(dedupKey)) return;
    if (!_initialized || !_isMobilePlatform) return;
    try {
      final tagId = normalizedCallId.isNotEmpty
          ? (id.startsWith('missed-') ? id : 'missed-$normalizedCallId')
          : id;
      final useTag = defaultTargetPlatform == TargetPlatform.android;
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          missedCallChannelId,
          missedCallChannelName,
          channelDescription: 'Missed voice and video calls in ReGen Messenger',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.missedCall,
          visibility: NotificationVisibility.public,
          onlyAlertOnce: true,
          autoCancel: true,
          playSound: true,
          enableVibration: true,
          tag: tagId,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
          interruptionLevel: InterruptionLevel.active,
        ),
      );

      await _plugin.show(
        id: useTag ? 0 : _notifIntId(dedupKey),
        title: 'Missed ${mediaType == 'video' ? 'Video' : 'Voice'} Call',
        body: '$callerName called you',
        notificationDetails: details,
        payload: jsonEncode({
          'type': 'missed_call',
          'notificationId': tagId,
          'callerId': callerId ?? '',
          'callerName': callerName,
          'conversationId': conversationId ?? '',
          'callId': normalizedCallId,
          'mediaType': mediaType,
        }),
      );
    } catch (_) {}
  }

  /// Display a high-priority task reminder or daily alert notification.
  Future<void> showTaskAlert({
    required String id,
    required String title,
    required String body,
  }) async {
    await NotificationPreferences.instance.ensureLoaded();
    if (!NotificationPreferences.instance.isPushEnabled ||
        !NotificationPreferences.instance.isTaskRemindersEnabled) {
      return;
    }
    if (!_rememberOnce('task:$id')) return;
    if (!_initialized || !_isMobilePlatform) return;
    try {
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          'regen_tasks',
          'Task Reminders & Alerts',
          channelDescription: 'Daily alerts for tasks assigned or needing completion',
          importance: Importance.high,
          priority: Priority.high,
          playSound: NotificationPreferences.instance.isSoundEnabled,
          enableVibration: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
        ),
      );

      await _plugin.show(
        id: _notifIntId('task:$id'),
        title: title,
        body: body,
        notificationDetails: details,
        payload: jsonEncode({'type': 'task_alert'}),
      );
    } catch (_) {}
  }

  /// Wire FCM / APNs token registration with ReGen backend.
  Future<bool> registerExternalPushToken({
    required UserModel user,
    required String token,
    MessengerService? service,
  }) async {
    final platform = defaultTargetPlatform == TargetPlatform.iOS
        ? 'ios'
        : (kIsWeb ? 'web' : 'android');
    return (service ?? MessengerService()).registerDeviceToken(
      user: user,
      token: token,
      platform: platform,
    );
  }

  /// Cancels all active and scheduled notifications on explicit logout or account switch.
  Future<void> cancelAll() async {
    _activeCallNotificationIds.clear();
    _recentDedupIds.clear();
    if (!_initialized || !_isMobilePlatform) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}
