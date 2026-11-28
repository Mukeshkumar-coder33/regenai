import 'package:flutter/foundation.dart';
import '../../messenger/data/webrtc_call_manager.dart';

/// Central navigation coordinator for routing notifications (both in-app banners,
/// local notifications, and FCM wakeup payloads) to the correct handler or page.
class DashboardNavigation {
  DashboardNavigation._();

  static void Function(String pageId)? navigateToPage;
  static String? pendingTargetPage;

  static void handleNotificationTap(Map<String, dynamic> payload) {
    debugPrint('[DashboardNavigation] Routing notification: $payload');
    final type = (payload['type'] ?? '').toString();
    final target = (payload['target'] ?? '').toString();
    final actionId = (payload['actionId'] ?? '').toString();
    final callId = (payload['callId'] ?? '').toString();
    final meetingId = (payload['meetingId'] ?? callId).toString();
    final callerId = (payload['callerId'] ?? payload['senderId'] ?? '').toString();
    final callerName = (payload['callerName'] ?? payload['senderName'] ?? 'Colleague').toString();
    final mediaType = (payload['mediaType'] ?? (type == 'video_call' ? 'video' : 'voice')).toString();

    if ((type == 'call' || type == 'voice_call' || type == 'video_call') &&
        callId.isNotEmpty) {
      if (actionId == 'decline_call') {
        WebRtcCallManager.instance.rejectExternalCall(
          callId: callId,
          callerId: callerId.isNotEmpty ? callerId : null,
        );
        return;
      }
      WebRtcCallManager.instance.handleExternalCallWakeup(
        callId: callId,
        callerId: callerId.isNotEmpty ? callerId : null,
        callerName: callerName,
        mediaType: mediaType,
        autoAccept: actionId == 'accept_call',
      );
      return;
    }

    if ((type == 'team_meeting' || type == 'meeting') && meetingId.isNotEmpty) {
      if (actionId == 'decline_call') {
        WebRtcCallManager.instance.rejectExternalMeeting(meetingId);
        return;
      }
      WebRtcCallManager.instance.handleExternalMeetingWakeup(
        meetingId: meetingId,
        title: (payload['title'] ?? callerName).toString(),
        hostId: callerId.isNotEmpty ? callerId : null,
        hostName: callerName,
        mediaType: mediaType,
        conversationId: payload['conversationId']?.toString(),
        autoJoin: actionId == 'accept_call',
      );
      return;
    }

    String pageId = 'messenger';
    if (type.contains('task') || target.contains('task')) {
      pageId = 'tasks';
    } else if (type == 'leave' || target == 'leave') {
      pageId = 'leave';
    } else if (type == 'payroll' ||
        type == 'payment' ||
        type == 'bonus' ||
        type == 'deduction') {
      pageId = 'payroll';
    } else if (type == 'attendance' || target == 'attendance') {
      pageId = 'attendance';
    } else if (type == 'calendar' || type == 'holiday' || target == 'calendar') {
      pageId = 'calendar';
    } else if (type == 'policy' || type == 'project' || type == 'scrum') {
      pageId = 'home';
    }

    if (navigateToPage != null) {
      navigateToPage!(pageId);
    } else {
      pendingTargetPage = pageId;
    }
  }
}
