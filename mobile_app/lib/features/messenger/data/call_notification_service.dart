import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../auth/data/user_model.dart';
import 'messenger_service.dart';

/// Mobile Call & Message Notification Service (Android & iOS)
///
/// - Configures high-priority Android incoming call channel (full-screen intent + sound/vibration)
///   and standard message notification channel.
/// - Configures iOS Darwin alert/sound/badge notifications.
/// - Provides ready-to-wire FCM / APNs / CallKit push token registration hook
///   (`registerExternalPushToken`) backed by `POST /api/notifications/device-token`.
class CallNotificationService {
  CallNotificationService._();
  static final CallNotificationService instance = CallNotificationService._();

  static const String callChannelId = 'regen_incoming_calls';
  static const String callChannelName = 'Incoming Voice & Video Calls';
  static const String messageChannelId = 'regen_messages';
  static const String messageChannelName = 'ReGen Messenger Messages';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  void Function(Map<String, dynamic> payload)? onNotificationTapped;

  bool get _isMobilePlatform =>
      !kIsWeb &&
      !WidgetsBinding.instance.runtimeType.toString().contains('Test') &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> initialize({
    void Function(Map<String, dynamic> payload)? onTap,
  }) async {
    onNotificationTapped = onTap;
    if (_initialized || !_isMobilePlatform) return;

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
          if (response.payload != null && response.payload!.isNotEmpty) {
            try {
              final decoded = jsonDecode(response.payload!) as Map<String, dynamic>;
              onNotificationTapped?.call(decoded);
            } catch (_) {}
          }
        },
      );

      // Request Android 13+ notification permission if applicable
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();

      _initialized = true;
    } catch (e) {
      debugPrint('[CallNotificationService] init skipped/failed: $e');
    }
  }

  /// Display a high-priority incoming call notification (with Android full-screen intent).
  Future<void> showIncomingCallNotification({
    required String callId,
    required String callerName,
    required String mediaType,
    bool isMeeting = false,
  }) async {
    if (!_initialized || !_isMobilePlatform) return;
    try {
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          callChannelId,
          callChannelName,
          channelDescription: 'Real-time incoming voice and video calls from ReGen Messenger',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
          fullScreenIntent: true,
          ongoing: true,
          autoCancel: false,
          playSound: true,
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 1000, 1000, 1000, 1000, 1000]),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      );

      final title = isMeeting
          ? 'Group ${mediaType == 'voice' ? 'Voice' : 'Video'} Call'
          : 'Incoming ${mediaType == 'video' ? 'Video' : 'Voice'} Call';

      await _plugin.show(
        id: callId.hashCode & 0x7FFFFFFF,
        title: title,
        body: isMeeting ? '$callerName started a group call' : '$callerName is calling you...',
        notificationDetails: details,
        payload: jsonEncode({
          'type': isMeeting ? 'meeting' : 'call',
          'callId': callId,
          'mediaType': mediaType,
        }),
      );
    } catch (e) {
      debugPrint('[CallNotificationService] showIncomingCall error: $e');
    }
  }

  Future<void> cancelCallNotification(String callId) async {
    if (!_initialized || !_isMobilePlatform) return;
    try {
      await _plugin.cancel(id: callId.hashCode & 0x7FFFFFFF);
    } catch (_) {}
  }

  Future<void> showMessageNotification({
    required String id,
    required String senderName,
    required String preview,
    String? conversationId,
  }) async {
    if (!_initialized || !_isMobilePlatform) return;
    try {
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          messageChannelId,
          messageChannelName,
          channelDescription: 'New text and voice messages in ReGen Messenger',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
        ),
      );

      await _plugin.show(
        id: id.hashCode & 0x7FFFFFFF,
        title: senderName,
        body: preview,
        notificationDetails: details,
        payload: jsonEncode({
          'type': 'message',
          'conversationId': ?conversationId,
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
    if (!_initialized || !_isMobilePlatform) return;
    try {
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'regen_tasks',
          'Task Reminders & Alerts',
          channelDescription: 'Daily alerts for tasks assigned or needing completion',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
        ),
      );

      await _plugin.show(
        id: id.hashCode & 0x7FFFFFFF,
        title: title,
        body: body,
        notificationDetails: details,
        payload: jsonEncode({
          'type': 'task_alert',
        }),
      );
    } catch (_) {}
  }

  /// Ready-to-wire FCM / APNs / VoIP PushKit token registration with ReGen backend.
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
}
