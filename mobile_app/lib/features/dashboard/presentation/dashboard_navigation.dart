import 'package:flutter/foundation.dart';
import '../../messenger/data/call_notification_service.dart';
import '../../messenger/data/webrtc_call_manager.dart';

/// Central navigation coordinator for routing notifications (both in-app banners,
/// local notifications, and FCM wakeup payloads) to the correct handler, page,
/// and deep-linked Messenger conversation across all dashboard roles and app states.
class DashboardNavigation {
  DashboardNavigation._();

  static void Function(String pageId)? navigateToPage;
  static Future<void> Function(Map<String, dynamic> payload)? onOpenConversation;
  static String? pendingTargetPage;
  static Map<String, dynamic>? pendingConversationPayload;
  static final Map<String, DateTime> _recentTapTimestamps = <String, DateTime>{};

  @visibleForTesting
  static void resetForTest() {
    navigateToPage = null;
    onOpenConversation = null;
    pendingTargetPage = null;
    pendingConversationPayload = null;
    _recentTapTimestamps.clear();
  }

  /// Consume any queued deep-linked Messenger conversation payload (after mount/login).
  static Map<String, dynamic>? takePendingConversationPayload() {
    final p = pendingConversationPayload;
    pendingConversationPayload = null;
    return p;
  }

  /// Resolve canonical dashboard page ID for any notification payload.
  static String resolvePageIdForPayload(Map<String, dynamic> payload) {
    final type = (payload['type'] ?? '').toString().toLowerCase().trim();
    final target = (payload['target'] ?? '').toString().toLowerCase().trim();
    final conversationId = (payload['conversationId'] ?? '').toString().trim();

    if (conversationId.isNotEmpty ||
        type == 'missed_call' ||
        type == 'text_message' ||
        type == 'voice_message' ||
        type == 'message' ||
        type == 'dm' ||
        type == 'team_message' ||
        target.contains('messenger') ||
        target.contains('chat')) {
      return 'messenger';
    }
    if (type.contains('task') || target.contains('task')) {
      return 'tasks';
    }
    if (type == 'leave' || target == 'leave') {
      return 'leave';
    }
    if (type == 'payroll' ||
        type == 'payment' ||
        type == 'bonus' ||
        type == 'deduction') {
      return 'payroll';
    }
    if (type == 'attendance' || target == 'attendance') {
      return 'attendance';
    }
    if (type == 'calendar' || type == 'holiday' || target == 'calendar') {
      return 'calendar';
    }
    if (type == 'policy' || type == 'project' || type == 'scrum') {
      return 'home';
    }
    return 'messenger';
  }

  static bool _shouldDeduplicateTap(Map<String, dynamic> payload) {
    final type = (payload['type'] ?? '').toString();
    final actionId = (payload['actionId'] ?? '').toString();
    final notifId = (payload['notificationId'] ?? payload['id'] ?? '').toString();
    final callId = (payload['callId'] ?? payload['meetingId'] ?? '').toString();
    final convId = (payload['conversationId'] ?? '').toString();
    final senderId = (payload['callerId'] ?? payload['senderId'] ?? '').toString();
    final key = notifId.isNotEmpty
        ? 'n:$notifId:$actionId'
        : 'p:$type:$callId:$convId:$senderId:$actionId';
    final now = DateTime.now();
    _recentTapTimestamps.removeWhere((_, ts) => now.difference(ts).inSeconds > 10);
    final prev = _recentTapTimestamps[key];
    if (prev != null && now.difference(prev).inMilliseconds < 2500) {
      return true;
    }
    _recentTapTimestamps[key] = now;
    return false;
  }

  static void handleNotificationTap(Map<String, dynamic> payload) {
    final normalized = Map<String, dynamic>.from(payload);
    debugPrint('[DashboardNavigation] Routing notification: $normalized');
    if (_shouldDeduplicateTap(normalized)) {
      return;
    }

    final type = (normalized['type'] ?? '').toString();
    final actionId = (normalized['actionId'] ?? '').toString();
    final callId = (normalized['callId'] ?? '').toString();
    final meetingId = (normalized['meetingId'] ?? callId).toString();
    final callerId =
        (normalized['callerId'] ?? normalized['senderId'] ?? '').toString();
    final callerName =
        (normalized['callerName'] ?? normalized['senderName'] ?? 'Colleague')
            .toString();
    final mediaType =
        (normalized['mediaType'] ?? (type == 'video_call' ? 'video' : 'voice'))
            .toString();

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
        title: (normalized['title'] ?? callerName).toString(),
        hostId: callerId.isNotEmpty ? callerId : null,
        hostName: callerName,
        mediaType: mediaType,
        conversationId: normalized['conversationId']?.toString(),
        autoJoin: actionId == 'accept_call',
      );
      return;
    }

    if (type == 'missed_call' && callId.isNotEmpty) {
      CallNotificationService.instance.cancelCallNotification(callId);
    }

    final pageId = resolvePageIdForPayload(normalized);
    final conversationId = (normalized['conversationId'] ?? '').toString().trim();
    final peerId = (normalized['callerId'] ?? normalized['senderId'] ?? '')
        .toString()
        .trim();
    final isMessengerDeepLink =
        pageId == 'messenger' && (conversationId.isNotEmpty || peerId.isNotEmpty || type == 'missed_call');

    if (isMessengerDeepLink) {
      pendingConversationPayload = normalized;
    } else {
      pendingConversationPayload = null;
    }

    if (navigateToPage != null) {
      pendingTargetPage = null;
      navigateToPage!(pageId);
      if (isMessengerDeepLink && onOpenConversation != null) {
        final toOpen = takePendingConversationPayload();
        if (toOpen != null) {
          onOpenConversation!(toOpen);
        }
      }
    } else {
      pendingTargetPage = pageId;
    }
  }
}
