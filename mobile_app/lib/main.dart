import 'dart:async';
import 'package:flutter/material.dart';
import 'app/app.dart';
import 'app/app_config.dart';
import 'features/dashboard/presentation/dashboard_navigation.dart';
import 'features/messenger/data/call_notification_service.dart';
import 'features/messenger/data/communication_diagnostics.dart';
import 'features/messenger/data/fcm_push_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationPreferences.instance.ensureLoaded();
  // Load persisted server preferences immediately without blocking frame 1 on LAN timeouts.
  await AppConfig.initCustomUrl(autoProbe: false);
  unawaited(AppConfig.resolveBestBackend());
  unawaited(FcmPushService.registerBackgroundHandlerEarly());
  await CallNotificationService.instance.initialize(
    onTap: (payload) {
      DashboardNavigation.handleNotificationTap(payload);
    },
  );
  runApp(const ReGenApp());
}
