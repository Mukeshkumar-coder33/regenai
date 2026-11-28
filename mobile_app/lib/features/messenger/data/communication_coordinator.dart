import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../../../app/app_config.dart';
import '../../../core/storage/session_storage.dart';
import '../../auth/data/user_model.dart';
import '../../dashboard/presentation/dashboard_navigation.dart';
import '../../notifications/data/notification_store.dart';
import 'call_notification_service.dart';
import 'communication_diagnostics.dart';
import 'fcm_push_service.dart';
import 'messenger_service.dart';
import 'messenger_socket_service.dart';
import 'messenger_store.dart';
import 'webrtc_call_manager.dart';

/// App-Wide Always-Available Communication Lifecycle Coordinator.
///
/// Replaces per-screen socket management with one centralized singleton that:
/// - Lives independently of MessengerView or Dashboard tab changes.
/// - Eagerly initializes CallManager, Notifications, MessengerStore, Socket.IO, and FCM.
/// - Watches app resume & network interface changes (Wi-Fi <-> Mobile Data) to
///   re-probe local vs public backend and automatically reconnect/resync calls & messages.
/// - Cleanly tears down everything on logout, account switch, or JWT invalidation.
class CommunicationCoordinator with WidgetsBindingObserver {
  CommunicationCoordinator._();
  static final CommunicationCoordinator instance = CommunicationCoordinator._();

  bool _observerAttached = false;
  UserModel? _activeUser;
  String? _lastNetworkSignature;
  Timer? _networkWatchTimer;
  StreamSubscription<String>? _authInvalidSub;
  Future<void> Function()? _onSessionExpiredCallback;

  UserModel? get activeUser => _activeUser;

  bool get _isTestEnv =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  /// Initialize real-time calls, messaging, notifications & FCM for [user].
  Future<void> initializeForUser(
    UserModel user, {
    Future<void> Function()? onSessionInvalidated,
  }) async {
    if (onSessionInvalidated != null) {
      _onSessionExpiredCallback = onSessionInvalidated;
    }

    final prevUid = _activeUser == null
        ? ''
        : (_activeUser!.userId.isNotEmpty ? _activeUser!.userId : _activeUser!.id);
    final nextUid = user.userId.isNotEmpty ? user.userId : user.id;

    if (prevUid.isNotEmpty && prevUid != nextUid) {
      await _cleanupForAccountSwitch();
    }

    _activeUser = user;
    await NotificationPreferences.instance.ensureLoaded();

    // 1. Bind global WebRTC CallManager, MessengerStore & NotificationStore immediately (no MessengerView required!)
    WebRtcCallManager.instance.bindUser(user);
    MessengerStore.instance.init(user);
    NotificationStore.instance.init(user);

    // 2. Initialize notifications without wiping existing tap handlers
    await CallNotificationService.instance.initialize(
      onTap: (payload) => DashboardNavigation.handleNotificationTap(payload),
    );

    if (_isTestEnv) return;

    // 3. Attach single global app lifecycle & auth invalidation listeners
    if (!_observerAttached) {
      WidgetsBinding.instance.addObserver(this);
      _observerAttached = true;
    }
    _authInvalidSub ??=
        MessengerSocketService.instance.onAuthInvalidated.listen((reason) async {
      CommunicationDiagnostics.instance.log('coord:auth_invalidated', {'reason': reason});
      if (_onSessionExpiredCallback != null) {
        await _onSessionExpiredCallback!();
      }
    });

    // 4. Connect Socket.IO & initialize FCM token sync
    await MessengerSocketService.instance.connect(user: user);
    unawaited(FcmPushService.instance.initializeForUser(user));

    // 5. Consume any notification payload that cold-launched the app
    final launchPayload = CallNotificationService.instance.takePendingLaunchPayload();
    if (launchPayload != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        DashboardNavigation.handleNotificationTap(launchPayload);
      });
    }

    // 6. Start lightweight adaptive network-interface monitor for Wi-Fi <-> Mobile Data transitions
    _startNetworkMonitor();
    CommunicationDiagnostics.instance.log('coord:initialized', {
      'userId': nextUid,
      'role': user.role,
      'server': AppConfig.activeBaseUrl,
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_activeUser == null || _isTestEnv) return;
    if (state == AppLifecycleState.resumed) {
      CommunicationDiagnostics.instance.log('coord:app_resumed');
      unawaited(_recoverAfterConnectivityOrResume(forceProbe: true));
    }
  }

  void _startNetworkMonitor() {
    _networkWatchTimer?.cancel();
    if (kIsWeb || _isTestEnv) return;
    unawaited(_refreshNetworkSignature());
    _networkWatchTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      if (_activeUser == null) return;
      final changed = await _refreshNetworkSignature();
      if (changed || !MessengerSocketService.instance.isConnected) {
        await _recoverAfterConnectivityOrResume(forceProbe: changed);
      }
    });
  }

  Future<bool> _refreshNetworkSignature() async {
    if (kIsWeb) return false;
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.any,
      );
      final parts = interfaces
          .map((iface) =>
              '${iface.name}:${iface.addresses.map((a) => a.address).join(",")}')
          .toList()
        ..sort();
      final sig = parts.join('|');
      final changed = _lastNetworkSignature != null && _lastNetworkSignature != sig;
      _lastNetworkSignature = sig;
      if (changed) {
        CommunicationDiagnostics.instance.log('coord:network_changed', {'sig': sig});
      }
      return changed;
    } catch (_) {
      return false;
    }
  }

  Future<void> _recoverAfterConnectivityOrResume({bool forceProbe = false}) async {
    try {
      await AppConfig.resolveBestBackend(forceProbe: forceProbe);
      final sameServer = await SessionStorage.isSessionValidForCurrentServer();
      if (!sameServer) {
        CommunicationDiagnostics.instance.log('coord:server_session_mismatch');
        if (_onSessionExpiredCallback != null) {
          await _onSessionExpiredCallback!();
        }
        return;
      }
      await MessengerSocketService.instance.ensureConnected();
      await FcmPushService.instance.resyncTokenIfNeeded();
      await NotificationStore.instance.refresh();
    } catch (e) {
      CommunicationDiagnostics.instance.log('coord:recover_error', {'error': e.toString()});
    }
  }

  Future<void> _cleanupForAccountSwitch() async {
    await FcmPushService.instance.unregisterOnLogout();
    await WebRtcCallManager.instance.resetOnLogout();
    MessengerSocketService.instance.disconnect();
    MessengerStore.instance.reset();
    NotificationStore.instance.reset();
    MessengerService.clearKeysCache();
    await CallNotificationService.instance.cancelAll();
  }

  /// Complete teardown on explicit user logout or session expiry.
  Future<void> shutdownOnLogout() async {
    _networkWatchTimer?.cancel();
    _networkWatchTimer = null;
    _lastNetworkSignature = null;
    _activeUser = null;
    _onSessionExpiredCallback = null;

    await _cleanupForAccountSwitch();

    if (_observerAttached) {
      WidgetsBinding.instance.removeObserver(this);
      _observerAttached = false;
    }
    await _authInvalidSub?.cancel();
    _authInvalidSub = null;
    CommunicationDiagnostics.instance.log('coord:shutdown_logout');
  }
}
