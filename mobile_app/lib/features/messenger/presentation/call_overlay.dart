import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../dashboard/presentation/dashboard_navigation.dart';
import '../data/call_notification_service.dart';
import '../data/communication_diagnostics.dart';
import '../data/messenger_socket_service.dart';
import '../data/messenger_sound_service.dart';
import '../data/webrtc_call_manager.dart';

/// App-wide overlay mounted in DashboardScreen to display incoming/active
/// 1-to-1 Voice/Video Calls, Group Voice/Video Meetings, and instant live
/// real-time notifications across all roles.
class CallOverlay extends StatefulWidget {
  final Widget child;
  final VoidCallback? onOpenMessenger;

  const CallOverlay({
    super.key,
    required this.child,
    this.onOpenMessenger,
  });

  @override
  State<CallOverlay> createState() => _CallOverlayState();
}

class _CallOverlayState extends State<CallOverlay> {
  final WebRtcCallManager _manager = WebRtcCallManager.instance;
  String? _lastShownStatus;

  // Live top banner for immediate real-time notifications (messages, calls, events)
  StreamSubscription<Map<String, dynamic>>? _notifSub;
  Map<String, dynamic>? _liveBanner;
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    _manager.addListener(_onManagerChanged);
    _notifSub = MessengerSocketService.instance.onNotification.listen(_handleIncomingNotification);
  }

  @override
  void dispose() {
    _manager.removeListener(_onManagerChanged);
    _notifSub?.cancel();
    _bannerTimer?.cancel();
    super.dispose();
  }

  void _handleIncomingNotification(Map<String, dynamic> notif) {
    if (!mounted) return;
    final type = (notif['type'] ?? 'general').toString();
    final title = (notif['title'] ?? notif['senderName'] ?? 'New Notification').toString();
    final body = (notif['message'] ?? '').toString();
    final id = (notif['id'] ?? notif['_id'] ?? DateTime.now().millisecondsSinceEpoch).toString();
    final convId = notif['conversationId']?.toString();
    final senderId = notif['senderId']?.toString() ?? '';
    final targetUserId = (notif['userId'] ?? '').toString();
    final activeUid = MessengerSocketService.instance.activeUserId;

    // Never notify ourselves
    if (senderId.isNotEmpty && activeUid != null && senderId == activeUid) {
      return;
    }

    // Never notify if explicitly addressed to another user
    if (targetUserId.isNotEmpty && activeUid != null && targetUserId != activeUid) {
      return;
    }

    // Suppress notification if user is actively viewing this conversation in Messenger
    if (convId != null && MessengerSocketService.instance.isConversationActive(convId)) {
      return;
    }

    // Respect user notification settings before displaying alerts or playing sounds
    if (type == 'project_task' && !NotificationPreferences.instance.isTaskRemindersEnabled) {
      return;
    }

    // Ignore call/meeting control alerts here — WebRtcCallManager renders dedicated call/meeting UI
    if (const {
      'voice_call',
      'video_call',
      'team_meeting',
      'call',
      'meeting',
      'call_cancelled',
      'call_ended',
    }.contains(type)) {
      return;
    }

    // Play in-app sound & only show Android system tray notification when app is not actively resumed
    // (avoids duplicate tray + in-app alerts in foreground per Section 8A).
    final isForegroundResumed = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    final callId = notif['callId']?.toString();
    final effectiveSenderId =
        senderId.isNotEmpty ? senderId : (notif['callerId'] ?? '').toString();
    final callerName = (notif['senderName'] ?? notif['callerName'] ?? title).toString();
    if (type == 'missed_call') {
      if (isForegroundResumed) {
        MessengerSoundService.instance.playMissedCallTone();
      }
      final cid = (callId != null && callId.isNotEmpty) ? callId : id;
      CallNotificationService.instance.showMissedCallNotification(
        id: cid.startsWith('missed-') ? cid : 'missed-$cid',
        callId: cid,
        callerId: effectiveSenderId,
        callerName: callerName,
        mediaType: notif['mediaType']?.toString() ?? 'voice',
        conversationId: convId,
      );
    } else {
      if (!NotificationPreferences.instance.isPushEnabled) return;
      if (isForegroundResumed) {
        MessengerSoundService.instance.playMessageReceivedTone();
      } else {
        CallNotificationService.instance.showMessageNotification(
          id: id,
          senderId: effectiveSenderId,
          senderName: title,
          preview: body.isNotEmpty ? body : 'You have a new update',
          conversationId: convId,
          notificationType: type,
        );
      }
    }

    // Immediately slide down an in-app real-time alert banner across Android, iOS & Web
    _bannerTimer?.cancel();
    setState(() {
      _liveBanner = {
        'id': id,
        'notificationId': id,
        'type': type,
        'title': title,
        'message': body,
        'conversationId': convId,
        'senderId': effectiveSenderId,
        'callerId': effectiveSenderId,
        'senderName': callerName,
        'callId': callId ?? '',
      };
    });
    _bannerTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _liveBanner = null);
    });
  }

  void _onManagerChanged() {
    if (!mounted) return;
    final status = _manager.statusMessage;
    if (status != null && status.isNotEmpty && status != _lastShownStatus) {
      _lastShownStatus = status;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: CeladonColors.primaryDark,
            content: Text(status, style: const TextStyle(color: Colors.white)),
          ),
        );
        _manager.clearStatusMessage();
        _lastShownStatus = null;
      });
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_liveBanner != null &&
            _manager.callPhase == CallPhase.idle &&
            _manager.meetingPhase == MeetingPhase.idle)
          _buildLiveNotificationBanner(_liveBanner!),
        if (_manager.callPhase == CallPhase.incoming) _buildIncomingCallOverlay(),
        if (_manager.callPhase == CallPhase.calling) _buildOutgoingCallOverlay(),
        if (_manager.callPhase == CallPhase.connecting ||
            _manager.callPhase == CallPhase.connected)
          _buildActiveCallOverlay(),
        if (_manager.meetingPhase == MeetingPhase.invited) _buildMeetingInviteOverlay(),
        if (_manager.meetingPhase == MeetingPhase.inMeeting) _buildActiveMeetingOverlay(),
      ],
    );
  }

  Widget _buildLiveNotificationBanner(Map<String, dynamic> notif) {
    final type = (notif['type'] ?? 'general').toString();
    final title = (notif['title'] ?? 'Notification').toString();
    final message = (notif['message'] ?? '').toString();
    final isMsg = type == 'text_message' ||
        type == 'voice_message' ||
        type == 'voice_call' ||
        type == 'video_call' ||
        type == 'team_meeting';

    IconData icon = Icons.notifications_active_rounded;
    if (type == 'voice_message') {
      icon = Icons.mic_rounded;
    } else if (type == 'text_message') {
      icon = Icons.chat_bubble_rounded;
    } else if (type == 'voice_call') {
      icon = Icons.phone_in_talk_rounded;
    } else if (type == 'video_call') {
      icon = Icons.videocam_rounded;
    } else if (type == 'team_meeting') {
      icon = Icons.groups_rounded;
    }

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Material(
            color: const Color(0xFF132620),
            elevation: 8,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                _bannerTimer?.cancel();
                final currentBanner = _liveBanner;
                setState(() => _liveBanner = null);
                if (currentBanner != null) {
                  DashboardNavigation.handleNotificationTap(currentBanner);
                }
                if (isMsg) widget.onOpenMessenger?.call();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: CeladonColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                            ),
                          ),
                          if (message.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 18),
                      onPressed: () {
                        _bannerTimer?.cancel();
                        setState(() => _liveBanner = null);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _initials(String? name) {
    final s = (name ?? '').trim();
    if (s.isEmpty) return 'U';
    final parts = s.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return s.substring(0, s.length >= 2 ? 2 : 1).toUpperCase();
  }

  Widget _buildIncomingCallOverlay() {
    final isVideo = _manager.callMediaType == 'video';
    return Positioned.fill(
      child: Material(
        color: const Color(0xE60B1713),
        child: SafeArea(
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF132620),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0x33FFFFFF)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: CeladonColors.primary.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      isVideo ? 'Incoming Video Call' : 'Incoming Voice Call',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  CircleAvatar(
                    radius: 46,
                    backgroundColor: CeladonColors.primary,
                    child: Text(
                      _initials(_manager.peerName),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _manager.peerName ?? 'Colleague',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'is calling you via ReGen Messenger...',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _callActionCircle(
                        icon: Icons.call_end_rounded,
                        label: 'Decline',
                        bg: CeladonColors.error,
                        onTap: () => _manager.rejectIncomingCall(),
                      ),
                      _callActionCircle(
                        icon: isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                        label: 'Accept',
                        bg: const Color(0xFF16A34A),
                        onTap: () => _manager.acceptIncomingCall(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOutgoingCallOverlay() {
    final isVideo = _manager.callMediaType == 'video';
    return Positioned.fill(
      child: Material(
        color: const Color(0xF50B1713),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(height: 36),
              Column(
                children: [
                  CircleAvatar(
                    radius: 52,
                    backgroundColor: CeladonColors.primary,
                    child: Text(
                      _initials(_manager.peerName),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _manager.peerName ?? 'Colleague',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Calling (${isVideo ? 'Video' : 'Voice'}) • Ringing...',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 42),
                child: _callActionCircle(
                  icon: Icons.call_end_rounded,
                  label: 'Cancel',
                  bg: CeladonColors.error,
                  onTap: () => _manager.endCall(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveCallOverlay() {
    final isVideo = _manager.callMediaType == 'video';
    return Positioned.fill(
      child: Material(
        color: const Color(0xFF0A1411),
        child: SafeArea(
          child: Stack(
            children: [
              // Remote video or voice avatar
              Positioned.fill(
                child: isVideo && _manager.remoteRenderer != null
                    ? RTCVideoView(
                        _manager.remoteRenderer!,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 58,
                            backgroundColor: CeladonColors.primary,
                            child: Text(
                              _initials(_manager.peerName),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 34,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            _manager.peerName ?? 'Colleague',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _manager.callPhase == CallPhase.connecting
                                ? 'Connecting...'
                                : 'Connected • ${WebRtcCallManager.formatDuration(_manager.callDurationSeconds)}',
                            style: TextStyle(
                              color: _manager.callPhase == CallPhase.connecting
                                  ? const Color(0xFFFCD34D)
                                  : const Color(0xFF6EE7B7),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),

              // Top status pill
              Positioned(
                top: 14,
                left: 16,
                right: 16,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.circle, color: Color(0xFF22C55E), size: 9),
                          const SizedBox(width: 8),
                          Text(
                            _manager.peerName ?? 'Call',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _manager.callPhase == CallPhase.connecting
                                ? 'Connecting...'
                                : WebRtcCallManager.formatDuration(_manager.callDurationSeconds),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Local PiP preview for video calls
              if (isVideo && _manager.localRenderer != null)
                Positioned(
                  right: 16,
                  bottom: 118,
                  width: 112,
                  height: 152,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        border: Border.all(color: Colors.white30, width: 1.5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: _manager.isVideoOff
                          ? const Center(
                              child: Icon(Icons.videocam_off_rounded, color: Colors.white70),
                            )
                          : RTCVideoView(
                              _manager.localRenderer!,
                              mirror: true,
                              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                            ),
                    ),
                  ),
                ),

              // Bottom call controls bar
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _controlIcon(
                        icon: _manager.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        active: _manager.isMuted,
                        onTap: _manager.toggleMute,
                      ),
                      _controlIcon(
                        icon: _manager.isSpeakerOn
                            ? Icons.volume_up_rounded
                            : Icons.hearing_rounded,
                        active: _manager.isSpeakerOn,
                        activeColor: CeladonColors.primary,
                        onTap: _manager.toggleSpeaker,
                      ),
                      if (isVideo) ...[
                        _controlIcon(
                          icon: _manager.isVideoOff
                              ? Icons.videocam_off_rounded
                              : Icons.videocam_rounded,
                          active: _manager.isVideoOff,
                          onTap: _manager.toggleVideo,
                        ),
                        _controlIcon(
                          icon: Icons.cameraswitch_rounded,
                          active: false,
                          onTap: _manager.switchCamera,
                        ),
                      ],
                      GestureDetector(
                        onTap: _manager.endCall,
                        child: Container(
                          width: 54,
                          height: 54,
                          decoration: const BoxDecoration(
                            color: CeladonColors.error,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 26),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMeetingInviteOverlay() {
    final invite = _manager.activeMeeting;
    if (invite == null) return const SizedBox.shrink();
    final isVideo = invite.mediaType == 'video';
    return Positioned.fill(
      child: Material(
        color: const Color(0xD90B1713),
        child: SafeArea(
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF132620),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: const Color(0x33FFFFFF)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: CeladonColors.primary.withValues(alpha: 0.35),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isVideo ? Icons.video_call_rounded : Icons.groups_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    invite.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${invite.hostName} started a group ${isVideo ? 'video' : 'voice'} call',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _callActionCircle(
                        icon: Icons.close_rounded,
                        label: 'Dismiss',
                        bg: Colors.white24,
                        onTap: _manager.dismissMeetingInvite,
                      ),
                      _callActionCircle(
                        icon: isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                        label: 'Join',
                        bg: const Color(0xFF16A34A),
                        onTap: () => _manager.joinGroupMeeting(invite),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveMeetingOverlay() {
    final meeting = _manager.activeMeeting;
    final participants = _manager.meetingParticipants;
    final isVideo = (meeting?.mediaType ?? 'video') == 'video';

    return Positioned.fill(
      child: Material(
        color: const Color(0xFF0A1411),
        child: SafeArea(
          child: Column(
            children: [
              // Meeting top bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: Row(
                  children: [
                    const Icon(Icons.circle, color: Color(0xFF22C55E), size: 10),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            meeting?.title ?? 'Group Call',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${participants.length + 1} participant${participants.isEmpty ? '' : 's'} • ${WebRtcCallManager.formatDuration(_manager.meetingDurationSeconds)}',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        backgroundColor: CeladonColors.error,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _manager.leaveGroupMeeting,
                      icon: const Icon(Icons.call_end_rounded, size: 16),
                      label: const Text('Leave', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),

              // Participant grid
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(14),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: participants.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _meetingTile(
                        name: 'You',
                        status: 'connected',
                        muted: _manager.meetingMuted,
                        showVideo: isVideo &&
                            !_manager.meetingVideoOff &&
                            _manager.meetingLocalRenderer != null,
                        renderer: _manager.meetingLocalRenderer,
                        mirror: true,
                      );
                    }
                    final p = participants[index - 1];
                    return _meetingTile(
                      name: p.username,
                      status: p.connectionStatus,
                      muted: false,
                      showVideo: isVideo && p.hasVideo,
                      renderer: p.renderer,
                      mirror: false,
                    );
                  },
                ),
              ),

              // Controls bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _controlIcon(
                        icon: _manager.meetingMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        active: _manager.meetingMuted,
                        onTap: _manager.toggleMeetingMute,
                      ),
                      _controlIcon(
                        icon: _manager.meetingSpeakerOn
                            ? Icons.volume_up_rounded
                            : Icons.hearing_rounded,
                        active: _manager.meetingSpeakerOn,
                        activeColor: CeladonColors.primary,
                        onTap: _manager.toggleMeetingSpeaker,
                      ),
                      if (isVideo) ...[
                        _controlIcon(
                          icon: _manager.meetingVideoOff
                              ? Icons.videocam_off_rounded
                              : Icons.videocam_rounded,
                          active: _manager.meetingVideoOff,
                          onTap: _manager.toggleMeetingVideo,
                        ),
                        _controlIcon(
                          icon: Icons.cameraswitch_rounded,
                          active: false,
                          onTap: _manager.switchCamera,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meetingTile({
    required String name,
    required String status,
    required bool muted,
    required bool showVideo,
    required RTCVideoRenderer? renderer,
    required bool mirror,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF152922),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showVideo && renderer != null)
            RTCVideoView(
              renderer,
              mirror: mirror,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            Center(
              child: CircleAvatar(
                radius: 32,
                backgroundColor: CeladonColors.primary,
                child: Text(
                  _initials(name),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
              ),
            ),
          Positioned(
            left: 8,
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 7,
                    color: status == 'connected'
                        ? const Color(0xFF22C55E)
                        : (status == 'disconnected' ? CeladonColors.error : Colors.amber),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (muted) const Icon(Icons.mic_off_rounded, color: Colors.redAccent, size: 13),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _callActionCircle({
    required IconData icon,
    required String label,
    required Color bg,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _controlIcon({
    required IconData icon,
    required bool active,
    Color activeColor = CeladonColors.error,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: active ? activeColor : Colors.white12,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

