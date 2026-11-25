import 'package:flutter/foundation.dart';

/// Central navigation coordinator for routing notifications (both in-app banners
/// and system device notification tray taps) to the correct page in ReGen.
class DashboardNavigation {
  DashboardNavigation._();

  static void Function(String pageId)? navigateToPage;
  static String? pendingTargetPage;

  static void handleNotificationTap(Map<String, dynamic> payload) {
    debugPrint('[DashboardNavigation] Routing notification: $payload');
    final type = (payload['type'] ?? '').toString();
    final target = (payload['target'] ?? '').toString();

    String pageId = 'messenger';
    if (type.contains('task') || target.contains('task')) {
      pageId = 'tasks';
    } else if (type == 'attendance' || target == 'attendance') {
      pageId = 'attendance';
    } else if (type == 'calendar' || target == 'calendar') {
      pageId = 'calendar';
    }

    if (navigateToPage != null) {
      navigateToPage!(pageId);
    } else {
      pendingTargetPage = pageId;
    }
  }
}
