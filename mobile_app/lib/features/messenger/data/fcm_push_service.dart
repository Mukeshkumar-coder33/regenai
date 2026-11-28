import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../../../app/app_config.dart';
import '../../../core/storage/session_storage.dart';
import '../../auth/data/user_model.dart';
import '../../dashboard/presentation/dashboard_navigation.dart';
import 'call_notification_service.dart';
import 'communication_diagnostics.dart';
import 'messenger_service.dart';
import 'messenger_socket_service.dart';
import 'webrtc_call_manager.dart';

/// Top-level background/terminated FCM handler executed in Android's background isolate.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await FcmPushService.ensureFirebaseInitialized();
    await CallNotificationService.instance.initialize(isBackgroundIsolate: true);
    await NotificationPreferences.instance.ensureLoaded();

    final data = message.data;
    final type = (data['type'] ?? '').toString();
    final callId = (data['callId'] ?? data['meetingId'] ?? '').toString();
    final callerName = (data['callerName'] ?? data['title'] ?? 'Someone').toString();
    final callerId = (data['callerId'] ?? data['senderId'] ?? '').toString();
    final mediaType = (data['mediaType'] ?? (type == 'video_call' ? 'video' : 'voice')).toString();

    if (type == 'voice_call' || type == 'video_call' || type == 'team_meeting') {
      if (callId.isNotEmpty) {
        // Skip expired wakeup packets older than 50s
        final sentAtMs = int.tryParse((data['sentAt'] ?? '').toString());
        if (sentAtMs != null &&
            DateTime.now().millisecondsSinceEpoch - sentAtMs > 50000) {
          return;
        }
        await CallNotificationService.instance.showIncomingCallNotification(
          callId: callId,
          callerId: callerId,
          callerName: callerName,
          mediaType: mediaType,
          isMeeting: type == 'team_meeting',
          silent: false,
        );
      }
      return;
    }

    if (type == 'call_cancelled' || type == 'call_ended') {
      if (callId.isNotEmpty) {
        await CallNotificationService.instance.cancelCallNotification(callId);
      }
      return;
    }

    if (type == 'missed_call') {
      if (callId.isNotEmpty) {
        await CallNotificationService.instance.cancelCallNotification(callId);
      }
      if (message.notification == null) {
        await CallNotificationService.instance.showMissedCallNotification(
          id: (data['notificationId'] ?? (callId.isNotEmpty ? callId : '${DateTime.now().millisecondsSinceEpoch}')).toString(),
          callId: callId,
          callerName: callerName,
          mediaType: mediaType,
          conversationId: data['conversationId']?.toString(),
        );
      }
      return;
    }

    if (message.notification == null && type.isNotEmpty) {
      if (!NotificationPreferences.instance.isPushEnabled) return;
      if (type == 'project_task' && !NotificationPreferences.instance.isTaskRemindersEnabled) {
        return;
      }
      final msgId = (data['notificationId'] ?? message.messageId ?? DateTime.now().millisecondsSinceEpoch).toString();
      final resolvedTitle = (data['title'] ?? data['senderName'] ?? message.notification?.title ?? 'ReGen Alert').toString();
      final rawBody = (data['body'] ?? data['message'] ?? message.notification?.body ?? '').toString().trim();
      final resolvedBody = rawBody.isNotEmpty
          ? rawBody
          : (type.isNotEmpty ? '${type.replaceAll('_', ' ')} update' : 'Tap to view in ReGen');
      await CallNotificationService.instance.showMessageNotification(
        id: msgId,
        senderName: resolvedTitle,
        preview: resolvedBody,
        conversationId: data['conversationId']?.toString(),
        notificationType: type,
      );
    }
  } catch (e) {
    debugPrint('[FCM Background] error: $e');
  }
}

/// Manages Firebase Cloud Messaging initialization, token registration/refresh,
/// foreground fallback delivery, and background notification wakeup routing.
class FcmPushService {
  FcmPushService._();
  static final FcmPushService instance = FcmPushService._();

  static bool _firebaseAvailable = false;
  static bool _firebaseInitAttempted = false;

  bool _listenersBound = false;
  String? _currentToken;
  String? _registeredUserId;
  UserModel? _activeUser;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundMsgSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;

  bool get isFirebaseAvailable => _firebaseAvailable;
  String? get currentToken => _currentToken;

  static bool get _isSupportedMobile =>
      !kIsWeb &&
      !WidgetsBinding.instance.runtimeType.toString().contains('Test') &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<bool> ensureFirebaseInitialized() async {
    if (_firebaseAvailable) return true;
    if (!_isSupportedMobile) return false;
    if (_firebaseInitAttempted) return _firebaseAvailable;
    _firebaseInitAttempted = true;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _firebaseAvailable = Firebase.apps.isNotEmpty;
      CommunicationDiagnostics.instance.log('fcm:firebase_init', {
        'available': _firebaseAvailable,
      });
    } catch (e) {
      // Happens cleanly when google-services.json is not yet placed in android/app/
      _firebaseAvailable = false;
      CommunicationDiagnostics.instance.log('fcm:firebase_not_configured', {
        'reason': e.toString(),
      });
    }
    return _firebaseAvailable;
  }

  /// Register background handler early in main().
  static Future<void> registerBackgroundHandlerEarly() async {
    final ready = await ensureFirebaseInitialized();
    if (!ready) return;
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (_) {}
  }

  /// Bind FCM listeners, obtain device token, and sync it with ReGen backend for [user].
  Future<void> initializeForUser(UserModel user) async {
    _activeUser = user;
    if (!_isSupportedMobile) return;

    final ready = await ensureFirebaseInitialized();
    if (!ready) return;

    try {
      final messaging = FirebaseMessaging.instance;

      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (!_listenersBound) {
        _listenersBound = true;
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

        _tokenRefreshSub = messaging.onTokenRefresh.listen((newToken) async {
          _currentToken = newToken;
          CommunicationDiagnostics.instance.log('fcm:token_refreshed');
          final u = _activeUser ?? await SessionStorage.getUserSession();
          if (u != null && u.token.isNotEmpty) {
            await _syncTokenToBackend(u, newToken);
          }
        });

        _foregroundMsgSub = FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
        _openedAppSub = FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationOpen);

        final initialMessage = await messaging.getInitialMessage();
        if (initialMessage != null) {
          _handleNotificationOpen(initialMessage);
        }
      }

      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        _currentToken = token;
        await _syncTokenToBackend(user, token);
      }
    } catch (e) {
      CommunicationDiagnostics.instance.log('fcm:init_error', {'error': e.toString()});
    }
  }

  Future<void> _syncTokenToBackend(UserModel user, String token) async {
    final uid = user.userId.isNotEmpty ? user.userId : user.id;
    await AppConfig.ensureReadyForRequest();
    final ok = await CallNotificationService.instance.registerExternalPushToken(
      user: user,
      token: token,
    );
    if (ok) {
      _registeredUserId = uid;
    }
    CommunicationDiagnostics.instance.log('fcm:token_register', {
      'userId': uid,
      'success': ok,
      'server': AppConfig.activeBaseUrl,
    });
  }

  Future<void> resyncTokenIfNeeded() async {
    if (!_isSupportedMobile || !_firebaseAvailable) return;
    final user = _activeUser;
    if (user == null || user.token.isEmpty) return;
    final uid = user.userId.isNotEmpty ? user.userId : user.id;
    if (_currentToken != null && _currentToken!.isNotEmpty && _registeredUserId != uid) {
      await _syncTokenToBackend(user, _currentToken!);
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final data = message.data;
    final type = (data['type'] ?? '').toString();
    final callId = (data['callId'] ?? data['meetingId'] ?? '').toString();
    final correlationId = (data['correlationId'] ?? '').toString();

    CommunicationDiagnostics.instance.log('fcm:foreground_received', {
      'type': type,
      'callId': callId,
      'correlationId': correlationId,
    });

    if (type == 'voice_call' || type == 'video_call') {
      if (callId.isEmpty) return;
      // Fallback wakeup if socket packet hasn't arrived yet
      WebRtcCallManager.instance.handleExternalCallWakeup(
        callId: callId,
        callerId: data['callerId']?.toString(),
        callerName: (data['callerName'] ?? 'Colleague').toString(),
        mediaType: (data['mediaType'] ?? (type == 'video_call' ? 'video' : 'voice')).toString(),
        autoAccept: false,
      );
      return;
    }

    if (type == 'team_meeting' || type == 'meeting') {
      if (callId.isEmpty) return;
      WebRtcCallManager.instance.handleExternalMeetingWakeup(
        meetingId: callId,
        title: (data['title'] ?? data['callerName'] ?? 'Group Call').toString(),
        hostId: data['callerId']?.toString(),
        hostName: (data['callerName'] ?? 'Colleague').toString(),
        mediaType: (data['mediaType'] ?? 'video').toString(),
        conversationId: data['conversationId']?.toString(),
        autoJoin: false,
      );
      return;
    }

    if (type == 'call_cancelled' || type == 'call_ended') {
      if (callId.isNotEmpty) {
        final reason = (data['reason'] ?? '').toString();
        WebRtcCallManager.instance.handleExternalCallCancelled(
          callId,
          reason: reason,
        );
      }
      return;
    }

    // Fallback notification delivery when Socket.IO is temporarily disconnected
    // (When Socket.IO IS connected, CallOverlay renders the foreground banner + sound without duplicating tray alerts)
    if (!MessengerSocketService.instance.isConnected) {
      final notifId = (data['notificationId'] ?? message.messageId ?? DateTime.now().millisecondsSinceEpoch).toString();
      if (type == 'missed_call') {
        CallNotificationService.instance.showMissedCallNotification(
          id: callId.isNotEmpty ? callId : notifId,
          callId: callId,
          callerName: (data['callerName'] ?? 'Someone').toString(),
          mediaType: (data['mediaType'] ?? 'voice').toString(),
          conversationId: data['conversationId']?.toString(),
        );
      } else if (type.isNotEmpty) {
        final convId = data['conversationId']?.toString();
        if (convId != null &&
            convId.isNotEmpty &&
            MessengerSocketService.instance.isConversationActive(convId)) {
          return;
        }
        final rawPreview = (data['body'] ?? data['message'] ?? message.notification?.body ?? '').toString().trim();
        final resolvedPreview = rawPreview.isNotEmpty
            ? rawPreview
            : '${type.replaceAll('_', ' ')} update';
        CallNotificationService.instance.showMessageNotification(
          id: notifId,
          senderName: (data['title'] ?? data['senderName'] ?? message.notification?.title ?? 'ReGen Alert').toString(),
          preview: resolvedPreview,
          conversationId: convId,
          notificationType: type,
        );
      }
    }
  }

  void _handleNotificationOpen(RemoteMessage message) {
    final data = Map<String, dynamic>.from(message.data);
    CommunicationDiagnostics.instance.log('fcm:opened_from_push', {
      'type': data['type'] ?? '',
      'callId': data['callId'] ?? '',
    });
    DashboardNavigation.handleNotificationTap(data);
  }

  /// Remove device push token from backend on logout or account switch.
  Future<void> unregisterOnLogout() async {
    final user = _activeUser;
    final token = _currentToken;
    _registeredUserId = null;
    _activeUser = null;
    if (user != null && token != null && token.isNotEmpty) {
      try {
        await MessengerService().unregisterDeviceToken(user: user, token: token);
        CommunicationDiagnostics.instance.log('fcm:token_unregistered');
      } catch (_) {}
    }
  }

  void disposeListeners() {
    _tokenRefreshSub?.cancel();
    _foregroundMsgSub?.cancel();
    _openedAppSub?.cancel();
    _tokenRefreshSub = null;
    _foregroundMsgSub = null;
    _openedAppSub = null;
    _listenersBound = false;
  }
}
