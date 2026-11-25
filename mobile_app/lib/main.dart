import 'package:flutter/material.dart';
import 'app/app.dart';
import 'features/dashboard/presentation/dashboard_navigation.dart';
import 'features/messenger/data/call_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CallNotificationService.instance.initialize(
    onTap: (payload) {
      DashboardNavigation.handleNotificationTap(payload);
    },
  );
  runApp(const ReGenApp());
}
