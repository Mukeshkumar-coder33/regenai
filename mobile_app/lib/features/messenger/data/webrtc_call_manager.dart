import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../auth/data/user_model.dart';
import 'call_notification_service.dart';
import 'communication_diagnostics.dart';
import 'messenger_model.dart';
import 'messenger_socket_service.dart';
import 'messenger_sound_service.dart';

enum CallPhase { idle, incoming, calling, connecting, connected }

enum MeetingPhase { idle, invited, inMeeting }

class MeetingParticipantState {
  final String userId;
  final String username;
  final RTCVideoRenderer renderer;
  final bool hasVideo;
  final String connectionStatus;

  const MeetingParticipantState({
    required this.userId,
    required this.username,
    required this.renderer,
    this.hasVideo = false,
    this.connectionStatus = 'connecting',
  });

  MeetingParticipantState copyWith({bool? hasVideo, String? connectionStatus}) {
    return MeetingParticipantState(
      userId: userId,
      username: username,
      renderer: renderer,
      hasVideo: hasVideo ?? this.hasVideo,
      connectionStatus: connectionStatus ?? this.connectionStatus,
    );
  }
}

/// App-wide WebRTC Call & Group Meeting Manager (1:1 P2P + Group Mesh)
///
/// Bound at application/dashboard lifecycle level — independent of MessengerView.
/// Enforces single-instance call state, terminal call deduplication, automatic
/// call state synchronization on reconnect, and guaranteed ringtone cleanup.
class WebRtcCallManager extends ChangeNotifier {
  WebRtcCallManager._();
  static final WebRtcCallManager instance = WebRtcCallManager._();

  static const Duration _ringTimeoutDuration = Duration(seconds: 48);

  static const Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ],
  };

  UserModel? _currentUser;
  bool _listenersAttached = false;
  final List<StreamSubscription<dynamic>> _subs = [];
  final Set<String> _handledTerminalCallIds = <String>{};

  // ── 1-to-1 Call State ──────────────────────────────────────────
  CallPhase _callPhase = CallPhase.idle;
  String? _callId;
  String? _peerId;
  String? _peerName;
  String _callMediaType = 'voice';
  Map<String, dynamic>? _pendingOffer;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isVideoOff = false;
  int _callDurationSeconds = 0;
  String? _statusMessage;
  Timer? _callTimer;
  Timer? _ringTimeoutTimer;
  bool _isAccepting = false;
  bool _remoteDescriptionSet = false;
  String? _appliedAnswerCallId;
  String? _applyingAnswerCallId;

  @visibleForTesting
  static bool Function()? foregroundCheckOverride;

  bool get isForegroundResumed {
    if (foregroundCheckOverride != null) return foregroundCheckOverride!();
    if (kIsWeb) return true;
    return WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  bool isCallLocallyAcceptedOrActive(String cid) {
    if (cid.isEmpty || _callId != cid) return false;
    return _isAccepting ||
        _callPhase == CallPhase.connecting ||
        _callPhase == CallPhase.connected;
  }

  MediaStream? _localStream;
  RTCPeerConnection? _peerConnection;
  final List<RTCIceCandidate> _pendingCandidates = [];
  RTCVideoRenderer? _localRenderer;
  RTCVideoRenderer? _remoteRenderer;

  // ── Group Meeting (WebRTC Mesh) State ──────────────────────────
  MeetingPhase _meetingPhase = MeetingPhase.idle;
  MeetingInvitePayload? _activeMeeting;
  bool _meetingMuted = false;
  bool _meetingSpeakerOn = true;
  bool _meetingVideoOff = false;
  int _meetingDurationSeconds = 0;
  Timer? _meetingTimer;

  final Map<String, RTCPeerConnection> _meetingPeers = {};
  final Map<String, List<RTCIceCandidate>> _pendingMeetingCandidates = {};
  final Map<String, MeetingParticipantState> _meetingParticipants = {};
  final Set<String> _remoteMeetingDescSet = <String>{};
  final Set<String> _handledTerminalMeetingIds = <String>{};
  RTCVideoRenderer? _meetingLocalRenderer;

  // Public getters
  CallPhase get callPhase => _callPhase;
  String? get callId => _callId;
  String? get peerId => _peerId;
  String? get peerName => _peerName;
  String get callMediaType => _callMediaType;
  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isVideoOff => _isVideoOff;
  int get callDurationSeconds => _callDurationSeconds;
  String? get statusMessage => _statusMessage;
  RTCVideoRenderer? get localRenderer => _localRenderer;
  RTCVideoRenderer? get remoteRenderer => _remoteRenderer;

  MeetingPhase get meetingPhase => _meetingPhase;
  MeetingInvitePayload? get activeMeeting => _activeMeeting;
  bool get meetingMuted => _meetingMuted;
  bool get meetingSpeakerOn => _meetingSpeakerOn;
  bool get meetingVideoOff => _meetingVideoOff;
  int get meetingDurationSeconds => _meetingDurationSeconds;
  List<MeetingParticipantState> get meetingParticipants =>
      _meetingParticipants.values.toList();
  RTCVideoRenderer? get meetingLocalRenderer => _meetingLocalRenderer;

  String get _myUserId {
    final u = _currentUser;
    if (u == null) return '';
    return u.userId.isNotEmpty ? u.userId : u.id;
  }

  String get _myDisplayName {
    final u = _currentUser;
    if (u == null) return 'Me';
    return u.name.isNotEmpty ? u.name : u.username;
  }

  bool _isMyUser(String? rawId) {
    final normalized = (rawId ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return false;
    final u = _currentUser;
    if (u == null) return normalized == _myUserId.trim().toLowerCase();
    return normalized == u.userId.trim().toLowerCase() ||
        normalized == u.id.trim().toLowerCase() ||
        normalized == u.username.trim().toLowerCase();
  }

  static String formatDuration(int totalSeconds) {
    final mins = totalSeconds ~/ 60;
    final secs = totalSeconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _markCallTerminal(String? callId) {
    if (callId == null || callId.isEmpty) return;
    _handledTerminalCallIds.add(callId);
    if (_handledTerminalCallIds.length > 250) {
      _handledTerminalCallIds.remove(_handledTerminalCallIds.first);
    }
  }

  void bindUser(UserModel user) {
    final prevUid = _myUserId;
    final nextUid = user.userId.isNotEmpty ? user.userId : user.id;
    _currentUser = user;

    if (prevUid.isNotEmpty && prevUid != nextUid) {
      _cleanupCall();
      leaveGroupMeeting();
      _handledTerminalCallIds.clear();
    }

    if (_listenersAttached) return;
    _listenersAttached = true;

    final socket = MessengerSocketService.instance;
    _subs.addAll([
      socket.onConnectionChange.listen(_handleSocketConnectionChange),
      socket.onCallIncoming.listen(_handleIncomingCall),
      socket.onCallState.listen(_handleCallState),
      socket.onCallAccepted.listen(_handleCallAccepted),
      socket.onCallRejected.listen(_handleCallRejected),
      socket.onCallCancelled.listen(_handleCallCancelled),
      socket.onCallSignal.listen(_handleCallSignal),
      socket.onCallEnded.listen(_handleCallEnded),
      socket.onMeetingStarted.listen(_handleMeetingStarted),
      socket.onMeetingUserJoined.listen(_handleMeetingUserJoined),
      socket.onMeetingExistingUsers.listen(_handleMeetingExistingUsers),
      socket.onMeetingSignal.listen(_handleMeetingSignal),
      socket.onMeetingUserLeft.listen(_handleMeetingUserLeft),
      socket.onMeetingError.listen(_handleMeetingError),
    ]);
    CommunicationDiagnostics.instance.log('call_mgr:bound', {'userId': nextUid});
  }

  void _handleSocketConnectionChange(bool connected) {
    if (!connected) return;
    // Sync authoritative call state immediately whenever socket connects/reconnects
    final currentCid = _callId;
    if (currentCid != null) {
      unawaited(_recoverAcceptedCallViaSync(currentCid));
    } else {
      MessengerSocketService.instance.emitWithAck('call:sync', {});
    }
  }

  Future<void> _recoverAcceptedCallViaSync(String currentCid) async {
    final resp = await MessengerSocketService.instance
        .emitWithAck('call:sync', {'callId': currentCid});
    if (resp is! Map || _callId != currentCid) return;
    final state = (resp['state'] ?? '').toString();
    if (['rejected', 'cancelled', 'missed', 'ended', 'failed'].contains(state)) {
      CommunicationDiagnostics.instance.log('call_mgr:sync_cleanup_stale', {
        'callId': currentCid,
        'serverState': state,
      });
      _markCallTerminal(currentCid);
      await _cleanupCall();
      return;
    }
    if (state == 'accepted' &&
        (_callPhase == CallPhase.calling || _callPhase == CallPhase.connecting)) {
      if (_callPhase == CallPhase.calling) {
        _ringTimeoutTimer?.cancel();
        _callPhase = CallPhase.connecting;
        notifyListeners();
      }
      if (resp['answer'] is Map && !_remoteDescriptionSet) {
        await _handleCallAccepted(Map<String, dynamic>.from(resp));
      } else if (_remoteDescriptionSet && resp['recipientCandidates'] is List) {
        await _absorbBufferedCandidates(resp['recipientCandidates']);
      }
    }
  }

  Future<void> _absorbBufferedCandidates(dynamic rawCandidates) async {
    if (rawCandidates is! List) return;
    for (final item in rawCandidates) {
      if (item is! Map) continue;
      final candidate = RTCIceCandidate(
        item['candidate']?.toString(),
        item['sdpMid']?.toString(),
        item['sdpMLineIndex'] is int ? item['sdpMLineIndex'] as int : null,
      );
      if (_peerConnection != null && _remoteDescriptionSet) {
        try {
          await _peerConnection!.addCandidate(candidate);
        } catch (_) {}
      } else {
        _pendingCandidates.add(candidate);
      }
    }
  }

  void _promoteToConnectedIfReady(String callId, {String source = 'ice'}) {
    if (_callId != callId) return;
    if (_callPhase == CallPhase.connected) return;
    if (_callPhase != CallPhase.connecting && _callPhase != CallPhase.calling) return;
    _ringTimeoutTimer?.cancel();
    _callPhase = CallPhase.connected;
    if (_callTimer == null) {
      _startCallDurationTimer();
    }
    CommunicationDiagnostics.instance.log('call_mgr:connected', {
      'callId': callId,
      'source': source,
    });
    notifyListeners();
  }

  void _attachPeerConnectionStateListeners(RTCPeerConnection pc, String callId) {
    pc.onConnectionState = (RTCPeerConnectionState state) {
      if (_callId != callId) return;
      CommunicationDiagnostics.instance.log('call_mgr:pc_state', {
        'callId': callId,
        'state': state.name,
      });
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _promoteToConnectedIfReady(callId, source: 'pc_connected');
      }
    };
    pc.onIceConnectionState = (RTCIceConnectionState state) {
      if (_callId != callId) return;
      CommunicationDiagnostics.instance.log('call_mgr:ice_state', {
        'callId': callId,
        'state': state.name,
      });
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _promoteToConnectedIfReady(callId, source: state.name);
      }
    };
  }

  void clearStatusMessage() {
    if (_statusMessage != null) {
      _statusMessage = null;
      notifyListeners();
    }
  }

  Future<({bool granted, bool videoAllowed, String? error})>
  _requestMediaPermissions({required bool requireVideo}) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return (granted: true, videoAllowed: requireVideo, error: null);
    }
    try {
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        return (
          granted: false,
          videoAllowed: false,
          error: 'Microphone permission is required to make calls.',
        );
      }
      if (!requireVideo) {
        return (granted: true, videoAllowed: false, error: null);
      }
      final camStatus = await Permission.camera.request();
      if (!camStatus.isGranted) {
        return (granted: true, videoAllowed: false, error: null);
      }
      return (granted: true, videoAllowed: true, error: null);
    } catch (_) {
      return (granted: true, videoAllowed: requireVideo, error: null);
    }
  }

  Future<MediaStream> _openLocalMediaStream({required bool video}) async {
    try {
      return await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': video
            ? {
                'facingMode': 'user',
                'width': {'ideal': 640},
                'height': {'ideal': 480},
              }
            : false,
      });
    } catch (_) {
      if (video) {
        return await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': false,
        });
      }
      rethrow;
    }
  }

  Future<void> _setAudioOutput({required bool speaker}) async {
    try {
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        await Helper.setSpeakerphoneOn(speaker);
      }
    } catch (_) {}
  }

  void _startRingTimeoutWatchdog(String callId) {
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = Timer(_ringTimeoutDuration, () async {
      if (_callId != callId) return;
      if (_callPhase != CallPhase.incoming && _callPhase != CallPhase.calling) {
        return;
      }
      CommunicationDiagnostics.instance.log('call_mgr:local_timeout', {
        'callId': callId,
        'phase': _callPhase.name,
      });
      if (_callPhase == CallPhase.calling) {
        await endCall();
      } else {
        _markCallTerminal(callId);
        _statusMessage = 'Missed call from ${_peerName ?? 'Someone'}';
        await _cleanupCall();
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // 1-TO-1 VOICE & VIDEO CALLS
  // ═══════════════════════════════════════════════════════════════

  Future<void> startCall({
    required String recipientId,
    required String recipientName,
    String mediaType = 'voice',
  }) async {
    final socket = MessengerSocketService.instance;
    if (!socket.isConnected) {
      final connected = await socket.waitUntilConnected(
        timeout: const Duration(seconds: 4),
      );
      if (!connected) {
        _statusMessage = 'Real-time server unavailable. Check internet connection.';
        notifyListeners();
        return;
      }
    }
    if (_callPhase != CallPhase.idle ||
        _meetingPhase == MeetingPhase.inMeeting) {
      _statusMessage = 'You are already in an active call.';
      notifyListeners();
      return;
    }

    final wantVideo = mediaType == 'video';
    final perm = await _requestMediaPermissions(requireVideo: wantVideo);
    if (!perm.granted) {
      _statusMessage = perm.error;
      notifyListeners();
      return;
    }

    try {
      final effectiveVideo = wantVideo && perm.videoAllowed;
      final stream = await _openLocalMediaStream(video: effectiveVideo);
      _localStream = stream;

      _localRenderer = RTCVideoRenderer();
      _remoteRenderer = RTCVideoRenderer();
      await _localRenderer!.initialize();
      await _remoteRenderer!.initialize();
      _localRenderer!.srcObject = stream;

      final pc = await createPeerConnection(_iceConfig);
      _peerConnection = pc;
      _pendingCandidates.clear();
      _remoteDescriptionSet = false;
      _appliedAnswerCallId = null;

      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }

      final newCallId = 'call-${DateTime.now().millisecondsSinceEpoch}';
      _attachPeerConnectionStateListeners(pc, newCallId);

      pc.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          _remoteRenderer?.srcObject = event.streams.first;
        }
        if (_remoteDescriptionSet) {
          _promoteToConnectedIfReady(newCallId, source: 'on_track');
        } else {
          notifyListeners();
        }
      };

      pc.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate != null) {
          socket.emit('call:signal', {
            'targetUserId': recipientId,
            'signal': {
              'candidate': {
                'candidate': candidate.candidate,
                'sdpMid': candidate.sdpMid,
                'sdpMLineIndex': candidate.sdpMLineIndex,
              },
            },
            'callId': newCallId,
          });
        }
      };

      final offer = await pc.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': effectiveVideo,
      });
      await pc.setLocalDescription(offer);

      _callId = newCallId;
      _peerId = recipientId;
      _peerName = recipientName;
      _callMediaType = effectiveVideo ? 'video' : 'voice';
      _isMuted = false;
      _isVideoOff = !effectiveVideo;
      _isSpeakerOn = effectiveVideo;
      _callPhase = CallPhase.calling;
      _statusMessage = null;
      _startRingTimeoutWatchdog(newCallId);
      await _setAudioOutput(speaker: _isSpeakerOn);
      notifyListeners();

      CommunicationDiagnostics.instance.log('call_mgr:outgoing_start', {
        'callId': newCallId,
        'recipientId': recipientId,
        'mediaType': _callMediaType,
      });

      final initAck = await socket.emitWithAck('call:initiate', {
        'callId': newCallId,
        'recipientId': recipientId,
        'mediaType': _callMediaType,
        'offer': {'sdp': offer.sdp, 'type': offer.type},
      });
      if (_callId == newCallId && initAck is Map && initAck['ok'] == false) {
        final reason = (initAck['reason'] ?? 'failed').toString();
        _markCallTerminal(newCallId);
        _statusMessage = reason == 'busy'
            ? '$recipientName is on another call'
            : 'Unable to connect call ($reason).';
        await _cleanupCall();
      }
    } catch (e) {
      _statusMessage = 'Unable to start call: $e';
      await _cleanupCall();
    }
  }

  /// Triggered from FCM push / Android notification tap / Accept action button
  /// when app was backgrounded, locked, or freshly launched.
  Future<void> handleExternalCallWakeup({
    required String callId,
    String? callerId,
    String? callerName,
    String mediaType = 'voice',
    bool autoAccept = false,
  }) async {
    if (callId.isEmpty || _handledTerminalCallIds.contains(callId)) {
      await CallNotificationService.instance.cancelCallNotification(callId);
      await MessengerSoundService.instance.stopRingtone(reason: 'external_terminal');
      return;
    }

    CommunicationDiagnostics.instance.log('call_mgr:external_wakeup', {
      'callId': callId,
      'autoAccept': autoAccept,
    });

    final socket = MessengerSocketService.instance;
    await socket.waitUntilConnected(timeout: const Duration(seconds: 5));

    final active = await socket.emitWithAck('call:get-active', {'callId': callId});
    if (active is! Map || active['offer'] is! Map) {
      CommunicationDiagnostics.instance.log('call_mgr:external_wakeup_expired', {'callId': callId});
      _markCallTerminal(callId);
      await CallNotificationService.instance.cancelCallNotification(callId);
      await MessengerSoundService.instance.stopRingtone(reason: 'wakeup_expired');
      if (_callId == callId) {
        await _cleanupCall();
      }
      return;
    }

    final resolvedCallerId = (active['callerId'] ?? callerId ?? '').toString();
    final resolvedCallerName = (active['callerName'] ?? callerName ?? 'Colleague').toString();
    final resolvedMedia = (active['mediaType'] ?? mediaType).toString();
    final resolvedOffer = Map<String, dynamic>.from(active['offer'] as Map);

    if (_callPhase == CallPhase.idle) {
      _handleIncomingCall({
        'callId': callId,
        'callerId': resolvedCallerId,
        'callerName': resolvedCallerName,
        'mediaType': resolvedMedia,
        'offer': resolvedOffer,
      });
    } else if (_callId == callId && _pendingOffer == null) {
      _pendingOffer = resolvedOffer;
    }

    if (active['callerCandidates'] is List) {
      await _absorbBufferedCandidates(active['callerCandidates']);
    }

    if (autoAccept && _callId == callId && _callPhase == CallPhase.incoming) {
      await acceptIncomingCall();
    }
  }

  Future<void> handleExternalCallCancelled(String callId, {String reason = ''}) async {
    if (callId.isEmpty) return;
    await CallNotificationService.instance.cancelCallNotification(callId);
    if (reason == 'accepted_elsewhere' && isCallLocallyAcceptedOrActive(callId)) {
      CommunicationDiagnostics.instance.log('call_mgr:ignored_accepted_elsewhere', {
        'callId': callId,
        'phase': _callPhase.name,
      });
      return;
    }
    _markCallTerminal(callId);
    if (_callId == callId) {
      await _cleanupCall();
    } else {
      await MessengerSoundService.instance.stopRingtone(reason: 'fcm_cancelled');
    }
  }

  /// Triggered from FCM push / Android notification tap for group calls in background or terminated state.
  Future<void> handleExternalMeetingWakeup({
    required String meetingId,
    String title = 'Group Call',
    String? hostId,
    String hostName = 'Colleague',
    String mediaType = 'video',
    String? conversationId,
    bool autoJoin = false,
  }) async {
    if (meetingId.isEmpty) return;
    if (_activeMeeting?.meetingId == meetingId &&
        (_meetingPhase == MeetingPhase.inMeeting || _meetingPhase == MeetingPhase.invited)) {
      if (autoJoin && _meetingPhase == MeetingPhase.invited && _activeMeeting != null) {
        await joinGroupMeeting(_activeMeeting!);
      }
      return;
    }

    final socket = MessengerSocketService.instance;
    await socket.waitUntilConnected(timeout: const Duration(seconds: 5));
    final active = await socket.emitWithAck('meeting:get-active', {'meetingId': meetingId});
    if (active is! Map) {
      await CallNotificationService.instance.cancelCallNotification(meetingId);
      await MessengerSoundService.instance.stopRingtone(reason: 'meeting_expired');
      return;
    }

    final invite = MeetingInvitePayload(
      meetingId: meetingId,
      title: (active['title'] ?? title).toString(),
      hostId: (active['hostId'] ?? hostId ?? '').toString(),
      hostName: (active['hostName'] ?? hostName).toString(),
      mediaType: (active['mediaType'] ?? mediaType).toString(),
      conversationId: active['conversationId']?.toString() ?? conversationId,
    );

    if (autoJoin) {
      await joinGroupMeeting(invite);
      return;
    }
    if (_callPhase == CallPhase.idle && _meetingPhase == MeetingPhase.idle) {
      _activeMeeting = invite;
      _meetingPhase = MeetingPhase.invited;
      notifyListeners();
    }
  }

  Future<void> rejectExternalMeeting(String meetingId) async {
    if (meetingId.isEmpty) return;
    await MessengerSoundService.instance.stopRingtone(reason: 'meeting_declined');
    await CallNotificationService.instance.cancelCallNotification(meetingId);
    if (_activeMeeting?.meetingId == meetingId && _meetingPhase == MeetingPhase.invited) {
      _activeMeeting = null;
      _meetingPhase = MeetingPhase.idle;
      notifyListeners();
    }
  }

  Future<void> rejectExternalCall({required String callId, String? callerId}) async {
    if (callId.isEmpty) return;
    _markCallTerminal(callId);
    await MessengerSoundService.instance.stopRingtone(reason: 'notif_decline');
    await CallNotificationService.instance.cancelCallNotification(callId);
    if (_callId == callId) {
      await rejectIncomingCall();
      return;
    }
    final socket = MessengerSocketService.instance;
    if (!socket.isConnected) {
      await socket.waitUntilConnected(timeout: const Duration(seconds: 3));
    }
    if (callerId != null && callerId.isNotEmpty) {
      socket.emit('call:reject', {
        'callId': callId,
        'callerId': callerId,
        'reason': 'declined',
      });
    }
  }

  Future<void> acceptIncomingCall() async {
    if (_isAccepting) return;
    _isAccepting = true;
    final currentCidForStop = _callId;
    await MessengerSoundService.instance.stopRingtone(
      reason: 'accepted',
      suppressCallId: currentCidForStop,
    );
    _ringTimeoutTimer?.cancel();

    try {
      if (_callPhase != CallPhase.incoming ||
          _callId == null ||
          _peerId == null) {
        return;
      }
      final currentCallId = _callId!;
      final socket = MessengerSocketService.instance;
      await CallNotificationService.instance.cancelCallNotification(currentCallId);
      await CallNotificationService.instance.cancelAllCallNotifications();

      if (!socket.isConnected) {
        await socket.waitUntilConnected(timeout: const Duration(seconds: 4));
      }

      final wantVideo = _callMediaType == 'video';
      final perm = await _requestMediaPermissions(requireVideo: wantVideo);
      if (!perm.granted) {
        _statusMessage = perm.error;
        await rejectIncomingCall();
        return;
      }

      Map<String, dynamic>? offer = _pendingOffer;
      List<dynamic>? bufferedCallerCands;
      if (offer == null || _pendingCandidates.isEmpty) {
        final active = await socket.emitWithAck('call:get-active', {
          'callId': currentCallId,
        });
        if (active is Map) {
          if (offer == null && active['offer'] is Map) {
            offer = Map<String, dynamic>.from(active['offer'] as Map);
          }
          if (active['callerCandidates'] is List) {
            bufferedCallerCands = active['callerCandidates'] as List;
          }
        }
      }
      if (offer == null) {
        _markCallTerminal(currentCallId);
        _statusMessage = 'Call expired before connection.';
        await _cleanupCall();
        return;
      }

      final effectiveVideo = wantVideo && perm.videoAllowed;
      final stream = await _openLocalMediaStream(video: effectiveVideo);
      _localStream = stream;

      _localRenderer = RTCVideoRenderer();
      _remoteRenderer = RTCVideoRenderer();
      await _localRenderer!.initialize();
      await _remoteRenderer!.initialize();
      _localRenderer!.srcObject = stream;

      _isMuted = false;
      _isVideoOff = !effectiveVideo;
      _isSpeakerOn = effectiveVideo;
      _callPhase = CallPhase.connecting;
      await _setAudioOutput(speaker: _isSpeakerOn);
      notifyListeners();

      final pc = await createPeerConnection(_iceConfig);
      _peerConnection = pc;
      _remoteDescriptionSet = false;
      _attachPeerConnectionStateListeners(pc, currentCallId);

      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }

      pc.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          _remoteRenderer?.srcObject = event.streams.first;
        }
        if (_remoteDescriptionSet) {
          _promoteToConnectedIfReady(currentCallId, source: 'on_track');
        } else {
          notifyListeners();
        }
      };

      pc.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate != null && _peerId != null && _callId != null) {
          socket.emit('call:signal', {
            'targetUserId': _peerId,
            'signal': {
              'candidate': {
                'candidate': candidate.candidate,
                'sdpMid': candidate.sdpMid,
                'sdpMLineIndex': candidate.sdpMLineIndex,
              },
            },
            'callId': _callId,
          });
        }
      };

      await pc.setRemoteDescription(
        RTCSessionDescription(
          offer['sdp']?.toString(),
          offer['type']?.toString() ?? 'offer',
        ),
      );
      _remoteDescriptionSet = true;

      if (bufferedCallerCands != null) {
        await _absorbBufferedCandidates(bufferedCallerCands);
      }
      for (final c in List<RTCIceCandidate>.from(_pendingCandidates)) {
        try {
          await pc.addCandidate(c);
        } catch (_) {}
      }
      _pendingCandidates.clear();

      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);

      final acceptAck = await socket.emitWithAck('call:accept', {
        'callId': currentCallId,
        'callerId': _peerId,
        'deviceId': socket.deviceId ?? '',
        'answer': {'sdp': answer.sdp, 'type': answer.type},
      });
      if (acceptAck is Map && acceptAck['ok'] == false) {
        _markCallTerminal(currentCallId);
        _statusMessage = 'Call ended before answer completed.';
        await _cleanupCall();
        return;
      }

      final connState = pc.connectionState;
      final iceState = pc.iceConnectionState;
      if (connState == RTCPeerConnectionState.RTCPeerConnectionStateConnected ||
          iceState == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          iceState == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _promoteToConnectedIfReady(currentCallId, source: 'accept_ready');
      }

      CommunicationDiagnostics.instance.log('call_mgr:accepted', {'callId': currentCallId});
    } catch (e) {
      _statusMessage = 'Failed to accept call: $e';
      await _cleanupCall();
    } finally {
      _isAccepting = false;
    }
  }

  Future<void> rejectIncomingCall({String reason = 'declined'}) async {
    final cid = _callId;
    final pid = _peerId;
    _markCallTerminal(cid);
    await MessengerSoundService.instance.stopRingtone(reason: reason, suppressCallId: cid);
    if (cid != null && pid != null) {
      await CallNotificationService.instance.cancelCallNotification(cid);
      await CallNotificationService.instance.cancelAllCallNotifications();
      MessengerSocketService.instance.emit('call:reject', {
        'callId': cid,
        'callerId': pid,
        'reason': reason,
      });
    }
    await _cleanupCall();
  }

  Future<void> endCall() async {
    final cid = _callId;
    final pid = _peerId;
    _markCallTerminal(cid);
    await MessengerSoundService.instance.stopRingtone(reason: 'hangup', suppressCallId: cid);
    if (cid != null && pid != null) {
      await CallNotificationService.instance.cancelCallNotification(cid);
      await CallNotificationService.instance.cancelAllCallNotifications();
      MessengerSocketService.instance.emit('call:end', {
        'callId': cid,
        'targetUserId': pid,
      });
    }
    await _cleanupCall();
  }

  void toggleMute() {
    if (_localStream == null) return;
    final audioTracks = _localStream!.getAudioTracks();
    if (audioTracks.isEmpty) return;
    _isMuted = !_isMuted;
    for (final t in audioTracks) {
      t.enabled = !_isMuted;
    }
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    _isSpeakerOn = !_isSpeakerOn;
    await _setAudioOutput(speaker: _isSpeakerOn);
    notifyListeners();
  }

  void toggleVideo() {
    if (_localStream == null) return;
    final videoTracks = _localStream!.getVideoTracks();
    if (videoTracks.isEmpty) return;
    _isVideoOff = !_isVideoOff;
    for (final t in videoTracks) {
      t.enabled = !_isVideoOff;
    }
    notifyListeners();
  }

  Future<void> switchCamera() async {
    if (_localStream == null) return;
    final videoTracks = _localStream!.getVideoTracks();
    if (videoTracks.isEmpty) return;
    try {
      await Helper.switchCamera(videoTracks.first);
    } catch (_) {}
  }

  void _startCallDurationTimer() {
    _callTimer?.cancel();
    _callDurationSeconds = 0;
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _callDurationSeconds++;
      notifyListeners();
    });
  }

  Future<void> _cleanupCall({String? expectedCallId}) async {
    final activeCallId = _callId;
    if (expectedCallId != null &&
        activeCallId != null &&
        activeCallId != expectedCallId) {
      return;
    }

    final streamToDispose = _localStream;
    final pcToClose = _peerConnection;
    final localRendererToDispose = _localRenderer;
    final remoteRendererToDispose = _remoteRenderer;

    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = null;
    _callTimer?.cancel();
    _callTimer = null;

    // Reset state synchronously BEFORE awaits so a newly arriving call cannot be
    // clobbered when closing older WebRTC tracks/renderers finishes asynchronously.
    _localStream = null;
    _peerConnection = null;
    _localRenderer = null;
    _remoteRenderer = null;
    _pendingCandidates.clear();
    _callPhase = CallPhase.idle;
    _callId = null;
    _peerId = null;
    _peerName = null;
    _pendingOffer = null;
    _remoteDescriptionSet = false;
    _appliedAnswerCallId = null;
    if (expectedCallId == null || _applyingAnswerCallId == expectedCallId) {
      _applyingAnswerCallId = null;
    }
    _isMuted = false;
    _isVideoOff = false;
    _isSpeakerOn = false;
    _callDurationSeconds = 0;
    notifyListeners();

    await MessengerSoundService.instance.stopRingtone(
      reason: 'cleanup',
      suppressCallId: expectedCallId ?? activeCallId,
    );
    if (activeCallId != null) {
      await CallNotificationService.instance.cancelCallNotification(activeCallId);
    }
    await CallNotificationService.instance.cancelAllCallNotifications();

    try {
      streamToDispose?.getTracks().forEach((t) => t.stop());
      await streamToDispose?.dispose();
    } catch (_) {}

    try {
      await pcToClose?.close();
    } catch (_) {}

    try {
      await localRendererToDispose?.dispose();
    } catch (_) {}

    try {
      await remoteRendererToDispose?.dispose();
    } catch (_) {}
  }

  // ── 1:1 Socket Handlers ────────────────────────────────────────
  void _handleIncomingCall(Map<String, dynamic> data) {
    final incoming = IncomingCallPayload.fromMap(data);
    if (incoming.callId.isEmpty || incoming.callerId.isEmpty) return;

    // Ignore stale/duplicate events for already-terminal calls
    if (_handledTerminalCallIds.contains(incoming.callId)) {
      CommunicationDiagnostics.instance.log('call_mgr:ignored_terminal_incoming', {
        'callId': incoming.callId,
      });
      return;
    }

    // Deduplicate identical callId delivered across Socket + FCM or reconnect sync
    if (_callId == incoming.callId) {
      if (_pendingOffer == null && incoming.offer != null) {
        _pendingOffer = incoming.offer;
      }
      return;
    }

    if (_callPhase != CallPhase.idle ||
        _meetingPhase == MeetingPhase.inMeeting) {
      MessengerSocketService.instance.emit('call:reject', {
        'callId': incoming.callId,
        'callerId': incoming.callerId,
        'reason': 'busy',
      });
      return;
    }

    _callId = incoming.callId;
    _peerId = incoming.callerId;
    _peerName = incoming.callerName;
    _callMediaType = incoming.mediaType;
    _pendingOffer = incoming.offer;
    _callPhase = CallPhase.incoming;
    _statusMessage = null;
    _startRingTimeoutWatchdog(incoming.callId);
    notifyListeners();

    // Inform backend immediately that receiver is ringing
    MessengerSocketService.instance.emit('call:ringing', {'callId': incoming.callId});

    // Start in-app looping ringtone; only show OS tray notification when app is not actively resumed in foreground
    MessengerSoundService.instance.startIncomingCallRingtone(callId: incoming.callId);
    if (!isForegroundResumed) {
      CallNotificationService.instance.showIncomingCallNotification(
        callId: incoming.callId,
        callerId: incoming.callerId,
        callerName: incoming.callerName,
        mediaType: incoming.mediaType,
        silent: true,
      );
    }
  }

  Future<void> _handleCallState(Map<String, dynamic> data) async {
    final cid = (data['callId'] ?? '').toString();
    final state = (data['state'] ?? '').toString();
    if (cid.isEmpty || cid != _callId) return;

    if (state == 'accepted') {
      if (_callPhase == CallPhase.incoming && !_isAccepting) {
        // Accepted on another device of the same user -> stop ringing here immediately!
        _markCallTerminal(cid);
        await _cleanupCall();
        return;
      }
      if (_callPhase == CallPhase.calling || _callPhase == CallPhase.connecting) {
        await MessengerSoundService.instance.stopRingtone(
          reason: 'peer_accepted',
          suppressCallId: cid,
        );
        _ringTimeoutTimer?.cancel();
        if (_callPhase == CallPhase.calling) {
          _callPhase = CallPhase.connecting;
          notifyListeners();
        }
        if (!_remoteDescriptionSet &&
            _appliedAnswerCallId != cid &&
            _applyingAnswerCallId != cid &&
            data['answer'] is Map) {
          await _handleCallAccepted(data);
        } else if (!_remoteDescriptionSet &&
            _appliedAnswerCallId != cid &&
            _applyingAnswerCallId != cid) {
          unawaited(_recoverAcceptedCallViaSync(cid));
        }
        return;
      }
    }

    if (['rejected', 'cancelled', 'missed', 'ended', 'failed'].contains(state)) {
      _markCallTerminal(cid);
      final wasIncoming = _callPhase == CallPhase.incoming;
      final callerId = _peerId;
      final callerName = _peerName ?? 'Someone';
      final mediaType = _callMediaType;
      await _cleanupCall(expectedCallId: cid);
      if (wasIncoming && state == 'missed') {
        await MessengerSoundService.instance.playMissedCallTone();
        await CallNotificationService.instance.showMissedCallNotification(
          id: 'missed-$cid',
          callId: cid,
          callerId: callerId,
          callerName: callerName,
          mediaType: mediaType,
        );
      }
    }
  }

  /// Seed an outgoing call in `calling` state for isolated signaling/SDP unit tests.
  @visibleForTesting
  void seedOutgoingCallForTest({
    required String callId,
    required RTCPeerConnection peerConnection,
    String peerId = 'peer-test',
  }) {
    _handledTerminalCallIds.remove(callId);
    _callId = callId;
    _peerId = peerId;
    _peerName = 'Test Peer';
    _callMediaType = 'voice';
    _callPhase = CallPhase.calling;
    _peerConnection = peerConnection;
    _remoteDescriptionSet = false;
    _appliedAnswerCallId = null;
    _applyingAnswerCallId = null;
  }

  /// Expose answer handling for deterministic race-condition tests.
  @visibleForTesting
  Future<void> debugHandleCallAcceptedForTest(Map<String, dynamic> data) =>
      _handleCallAccepted(data);

  /// Expose state event handling for deterministic race-condition tests.
  @visibleForTesting
  Future<void> debugHandleCallStateForTest(Map<String, dynamic> data) =>
      _handleCallState(data);

  Future<void> _handleCallAccepted(Map<String, dynamic> data) async {
    final cid = data['callId']?.toString();
    final targetCallId = (cid != null && cid.isNotEmpty) ? cid : _callId;
    if (targetCallId == null || targetCallId.isEmpty) return;
    if (_callId != null && cid != null && cid != _callId) return;
    if (_handledTerminalCallIds.contains(targetCallId)) return;
    if (_appliedAnswerCallId == targetCallId ||
        _applyingAnswerCallId == targetCallId ||
        _remoteDescriptionSet) {
      return;
    }

    final pc = _peerConnection;
    if (pc == null) return;
    final rawAnswer = data['answer'];
    if (rawAnswer is! Map) return;
    final answerSdp = rawAnswer['sdp']?.toString() ?? '';
    if (answerSdp.isEmpty) return;

    // Acquire synchronous per-call lock BEFORE first await so back-to-back
    // `call:accepted` and `call:state:accepted` events never race setRemoteDescription.
    _applyingAnswerCallId = targetCallId;
    try {
      await MessengerSoundService.instance.stopRingtone(
        reason: 'peer_accepted',
        suppressCallId: targetCallId,
      );
      _ringTimeoutTimer?.cancel();

      if (_peerConnection == null ||
          !identical(_peerConnection, pc) ||
          _callId != targetCallId ||
          _handledTerminalCallIds.contains(targetCallId) ||
          _remoteDescriptionSet ||
          _appliedAnswerCallId == targetCallId) {
        return;
      }

      if (_callPhase == CallPhase.calling) {
        _callPhase = CallPhase.connecting;
        notifyListeners();
      }

      RTCSignalingState? signalingState;
      try {
        signalingState = await pc.getSignalingState();
      } catch (_) {
        signalingState = pc.signalingState;
      }
      if (signalingState == RTCSignalingState.RTCSignalingStateStable) {
        _remoteDescriptionSet = true;
        _appliedAnswerCallId = targetCallId;
        if (data['recipientCandidates'] is List) {
          await _absorbBufferedCandidates(data['recipientCandidates']);
        }
        notifyListeners();
        return;
      }
      if (signalingState == RTCSignalingState.RTCSignalingStateClosed) {
        return;
      }

      await pc.setRemoteDescription(
        RTCSessionDescription(
          answerSdp,
          rawAnswer['type']?.toString() ?? 'answer',
        ),
      );
      if (!identical(_peerConnection, pc) ||
          _callId != targetCallId ||
          _handledTerminalCallIds.contains(targetCallId)) {
        return;
      }

      _remoteDescriptionSet = true;
      _appliedAnswerCallId = targetCallId;
      _statusMessage = null;
      if (data['recipientCandidates'] is List) {
        await _absorbBufferedCandidates(data['recipientCandidates']);
      }
      for (final c in List<RTCIceCandidate>.from(_pendingCandidates)) {
        if (!identical(_peerConnection, pc)) break;
        try {
          await pc.addCandidate(c);
        } catch (_) {}
      }
      _pendingCandidates.clear();
      final connState = pc.connectionState;
      final iceState = pc.iceConnectionState;
      if (connState == RTCPeerConnectionState.RTCPeerConnectionStateConnected ||
          iceState == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          iceState == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _promoteToConnectedIfReady(_callId ?? targetCallId, source: 'answer_ready');
      } else {
        notifyListeners();
      }
    } catch (e) {
      if (!identical(_peerConnection, pc) ||
          _callId != targetCallId ||
          _handledTerminalCallIds.contains(targetCallId)) {
        return;
      }
      if (pc.signalingState == RTCSignalingState.RTCSignalingStateStable) {
        _remoteDescriptionSet = true;
        _appliedAnswerCallId = targetCallId;
        notifyListeners();
        return;
      }
      _statusMessage = 'WebRTC handshake error: $e';
      await _cleanupCall(expectedCallId: targetCallId);
    } finally {
      if (_applyingAnswerCallId == targetCallId) {
        _applyingAnswerCallId = null;
      }
    }
  }

  Future<void> _handleCallRejected(Map<String, dynamic> data) async {
    final cid = data['callId']?.toString();
    if (_callId != null && cid != null && cid != _callId) return;
    _markCallTerminal(cid);
    final reason = (data['reason'] ?? 'declined').toString();
    _statusMessage = reason == 'busy'
        ? '${_peerName ?? 'User'} is on another call'
        : 'Call $reason';
    await _cleanupCall();
  }

  Future<void> _handleCallSignal(Map<String, dynamic> data) async {
    final cid = data['callId']?.toString();
    if (_callId != null && cid != null && cid != _callId) return;

    final signal = data['signal'];
    if (signal is! Map) return;
    final rawCand = signal['candidate'];
    if (rawCand is! Map) return;

    final candidate = RTCIceCandidate(
      rawCand['candidate']?.toString(),
      rawCand['sdpMid']?.toString(),
      rawCand['sdpMLineIndex'] is int ? rawCand['sdpMLineIndex'] as int : null,
    );

    if (_peerConnection != null && _remoteDescriptionSet) {
      try {
        await _peerConnection!.addCandidate(candidate);
      } catch (_) {}
    } else {
      _pendingCandidates.add(candidate);
    }
  }

  Future<void> _handleCallEnded(Map<String, dynamic> data) async {
    final endedCallId = data['callId']?.toString();
    if (_callId != null && endedCallId != null && _callId != endedCallId) return;
    _markCallTerminal(endedCallId ?? _callId);

    await MessengerSoundService.instance.stopRingtone(
      reason: 'call_ended',
      suppressCallId: endedCallId ?? _callId,
    );
    final wasIncoming = _callPhase == CallPhase.incoming;
    final callerId = _peerId;
    final callerName = _peerName ?? 'Someone';
    final mediaType = _callMediaType;
    final callId = _callId ?? endedCallId;
    if (_callId != null) {
      _statusMessage = wasIncoming ? 'Missed call from $callerName' : 'Call ended';
    }
    await _cleanupCall(expectedCallId: callId);
    if (wasIncoming && callId != null) {
      await MessengerSoundService.instance.playMissedCallTone();
      await CallNotificationService.instance.showMissedCallNotification(
        id: 'missed-$callId',
        callId: callId,
        callerId: callerId,
        callerName: callerName,
        mediaType: mediaType,
      );
    }
  }

  Future<void> _handleCallCancelled(Map<String, dynamic> data) async {
    final cancelledCallId = data['callId']?.toString();
    if (_callId != null &&
        cancelledCallId != null &&
        _callId != cancelledCallId) {
      return;
    }
    _markCallTerminal(cancelledCallId ?? _callId);
    await MessengerSoundService.instance.stopRingtone(
      reason: 'call_cancelled',
      suppressCallId: cancelledCallId ?? _callId,
    );
    final wasIncoming = _callPhase == CallPhase.incoming;
    final callerId = _peerId;
    final callerName = _peerName ?? 'Someone';
    final mediaType = _callMediaType;
    final callId = _callId ?? cancelledCallId;
    if (_callId != null) {
      _statusMessage = 'Missed call from $callerName';
    }
    await _cleanupCall(expectedCallId: callId);
    if (wasIncoming && callId != null) {
      await MessengerSoundService.instance.playMissedCallTone();
      await CallNotificationService.instance.showMissedCallNotification(
        id: 'missed-$callId',
        callId: callId,
        callerId: callerId,
        callerName: callerName,
        mediaType: mediaType,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // GROUP VOICE & VIDEO CALLS
  // ═══════════════════════════════════════════════════════════════

  Future<void> startGroupMeeting({
    required String title,
    String mediaType = 'video',
    String? conversationId,
    List<String>? participantIds,
  }) async {
    final socket = MessengerSocketService.instance;
    if (!socket.isConnected) {
      final ok = await socket.waitUntilConnected(timeout: const Duration(seconds: 4));
      if (!ok) {
        _statusMessage = 'Real-time server unavailable. Check internet connection.';
        notifyListeners();
        return;
      }
    }

    final meetingId = 'meeting-${DateTime.now().millisecondsSinceEpoch}';
    final joined = await joinGroupMeeting(
      MeetingInvitePayload(
        meetingId: meetingId,
        title: title,
        hostId: _myUserId,
        hostName: _myDisplayName,
        mediaType: mediaType,
        conversationId: conversationId,
      ),
    );
    if (!joined) return;

    // Emit invite only AFTER host camera/mic + MeetingPhase.inMeeting are ready so early joiners are never missed
    socket.emit('meeting:start', {
      'meetingId': meetingId,
      'title': title,
      'mediaType': mediaType,
      if (conversationId != null && conversationId.isNotEmpty)
        'conversationId': conversationId,
      if (participantIds != null && participantIds.isNotEmpty)
        'participantIds': participantIds,
    });
  }

  Future<bool> joinGroupMeeting(MeetingInvitePayload invite) async {
    final socket = MessengerSocketService.instance;
    if (!socket.isConnected) {
      final ok = await socket.waitUntilConnected(timeout: const Duration(seconds: 4));
      if (!ok) {
        _statusMessage = 'Real-time connection unavailable.';
        notifyListeners();
        return false;
      }
    }
    _handledTerminalMeetingIds.add(invite.meetingId);
    await MessengerSoundService.instance.stopRingtone(
      reason: 'join_meeting',
      suppressCallId: invite.meetingId,
    );
    await CallNotificationService.instance.cancelCallNotification(
      invite.meetingId,
    );

    final wantVideo = invite.mediaType == 'video';
    final perm = await _requestMediaPermissions(requireVideo: wantVideo);
    if (!perm.granted) {
      _statusMessage = perm.error;
      _meetingPhase = MeetingPhase.idle;
      _activeMeeting = null;
      notifyListeners();
      return false;
    }

    try {
      final effectiveVideo = wantVideo && perm.videoAllowed;
      final stream = await _openLocalMediaStream(video: effectiveVideo);
      _localStream = stream;

      _meetingLocalRenderer = RTCVideoRenderer();
      await _meetingLocalRenderer!.initialize();
      _meetingLocalRenderer!.srcObject = stream;

      _remoteMeetingDescSet.clear();
      _activeMeeting = invite;
      _meetingMuted = false;
      _meetingVideoOff = !effectiveVideo;
      _meetingSpeakerOn = true;
      _meetingPhase = MeetingPhase.inMeeting;
      _meetingDurationSeconds = 0;
      _meetingTimer?.cancel();
      _meetingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _meetingDurationSeconds++;
        notifyListeners();
      });
      await _setAudioOutput(speaker: true);

      socket.emit('meeting:join', {
        'meetingId': invite.meetingId,
        'userInfo': {'userId': _myUserId, 'username': _myDisplayName},
      });
      notifyListeners();
      return true;
    } catch (e) {
      _statusMessage = 'Could not join group call: $e';
      await leaveGroupMeeting();
      return false;
    }
  }

  void dismissMeetingInvite() {
    final mid = _activeMeeting?.meetingId;
    if (mid != null && mid.isNotEmpty) {
      _handledTerminalMeetingIds.add(mid);
    }
    MessengerSoundService.instance.stopRingtone(
      reason: 'dismiss_meeting',
      suppressCallId: mid,
    );
    if (_activeMeeting != null) {
      CallNotificationService.instance.cancelCallNotification(
        _activeMeeting!.meetingId,
      );
    }
    _activeMeeting = null;
    _meetingPhase = MeetingPhase.idle;
    notifyListeners();
  }

  Future<void> leaveGroupMeeting() async {
    final mid = _activeMeeting?.meetingId;
    if (mid != null && mid.isNotEmpty) {
      _handledTerminalMeetingIds.add(mid);
    }
    await MessengerSoundService.instance.stopRingtone(
      reason: 'leave_meeting',
      suppressCallId: mid,
    );
    _meetingTimer?.cancel();
    _meetingTimer = null;

    if (_activeMeeting != null) {
      await CallNotificationService.instance.cancelCallNotification(
        _activeMeeting!.meetingId,
      );
      MessengerSocketService.instance.emit('meeting:leave', {
        'meetingId': _activeMeeting!.meetingId,
      });
    }

    for (final pc in _meetingPeers.values) {
      try {
        await pc.close();
      } catch (_) {}
    }
    _meetingPeers.clear();
    _pendingMeetingCandidates.clear();
    _remoteMeetingDescSet.clear();

    for (final p in _meetingParticipants.values) {
      try {
        await p.renderer.dispose();
      } catch (_) {}
    }
    _meetingParticipants.clear();

    try {
      _localStream?.getTracks().forEach((t) => t.stop());
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;

    try {
      await _meetingLocalRenderer?.dispose();
    } catch (_) {}
    _meetingLocalRenderer = null;

    _activeMeeting = null;
    _meetingPhase = MeetingPhase.idle;
    _meetingDurationSeconds = 0;
    notifyListeners();
  }

  void toggleMeetingMute() {
    if (_localStream == null) return;
    _meetingMuted = !_meetingMuted;
    for (final t in _localStream!.getAudioTracks()) {
      t.enabled = !_meetingMuted;
    }
    notifyListeners();
  }

  void toggleMeetingVideo() {
    if (_localStream == null) return;
    _meetingVideoOff = !_meetingVideoOff;
    for (final t in _localStream!.getVideoTracks()) {
      t.enabled = !_meetingVideoOff;
    }
    notifyListeners();
  }

  Future<void> toggleMeetingSpeaker() async {
    _meetingSpeakerOn = !_meetingSpeakerOn;
    await _setAudioOutput(speaker: _meetingSpeakerOn);
    notifyListeners();
  }

  Future<RTCPeerConnection> _createMeetingPeer({
    required String peerUserId,
    required String peerUsername,
    required bool isInitiator,
    required String meetingId,
  }) async {
    if (_meetingPeers.containsKey(peerUserId)) {
      return _meetingPeers[peerUserId]!;
    }

    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    _meetingParticipants[peerUserId] = MeetingParticipantState(
      userId: peerUserId,
      username: peerUsername,
      renderer: renderer,
      hasVideo: false,
      connectionStatus: 'connecting',
    );
    notifyListeners();

    final pc = await createPeerConnection(_iceConfig);
    _meetingPeers[peerUserId] = pc;
    _pendingMeetingCandidates[peerUserId] = [];

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
      }
    }

    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        final remoteStream = event.streams.first;
        final existing = _meetingParticipants[peerUserId];
        if (existing != null) {
          existing.renderer.srcObject = remoteStream;
          _meetingParticipants[peerUserId] = existing.copyWith(
            hasVideo: remoteStream.getVideoTracks().isNotEmpty,
            connectionStatus: 'connected',
          );
          notifyListeners();
        }
      }
    };

    pc.onConnectionState = (RTCPeerConnectionState state) {
      final existing = _meetingParticipants[peerUserId];
      if (existing == null) return;
      final label =
          state == RTCPeerConnectionState.RTCPeerConnectionStateConnected
          ? 'connected'
          : (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
                state ==
                    RTCPeerConnectionState.RTCPeerConnectionStateDisconnected)
          ? 'disconnected'
          : 'connecting';
      _meetingParticipants[peerUserId] = existing.copyWith(
        connectionStatus: label,
      );
      notifyListeners();
    };
    pc.onIceConnectionState = (RTCIceConnectionState state) {
      final existing = _meetingParticipants[peerUserId];
      if (existing == null) return;
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _meetingParticipants[peerUserId] = existing.copyWith(
          connectionStatus: 'connected',
        );
        notifyListeners();
      }
    };

    pc.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null) {
        MessengerSocketService.instance.emit('meeting:signal', {
          'targetUserId': peerUserId,
          'signal': {
            'type': 'candidate',
            'candidate': {
              'candidate': candidate.candidate,
              'sdpMid': candidate.sdpMid,
              'sdpMLineIndex': candidate.sdpMLineIndex,
            },
          },
          'meetingId': meetingId,
        });
      }
    };

    if (isInitiator) {
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      MessengerSocketService.instance.emit('meeting:signal', {
        'targetUserId': peerUserId,
        'signal': {
          'type': 'offer',
          'offer': {'sdp': offer.sdp, 'type': offer.type},
        },
        'meetingId': meetingId,
      });
    }

    return pc;
  }

  void _handleMeetingStarted(Map<String, dynamic> data) {
    final invite = MeetingInvitePayload.fromMap(data);
    if (invite.meetingId.isEmpty || _isMyUser(invite.hostId)) return;
    if (_handledTerminalMeetingIds.contains(invite.meetingId)) return;
    if (_activeMeeting?.meetingId == invite.meetingId) return;
    if (_meetingPhase == MeetingPhase.inMeeting ||
        _callPhase != CallPhase.idle) {
      return;
    }

    _activeMeeting = invite;
    _meetingPhase = MeetingPhase.invited;
    notifyListeners();

    MessengerSoundService.instance.startIncomingCallRingtone(callId: invite.meetingId);
    if (!isForegroundResumed) {
      CallNotificationService.instance.showIncomingCallNotification(
        callId: invite.meetingId,
        callerId: invite.hostId,
        callerName: invite.hostName,
        mediaType: invite.mediaType,
        isMeeting: true,
        silent: true,
      );
    }
  }

  Future<void> _handleMeetingUserJoined(Map<String, dynamic> data) async {
    if (_meetingPhase != MeetingPhase.inMeeting || _activeMeeting == null) {
      return;
    }
    final joinedId = (data['userId'] ?? '').toString();
    if (joinedId.isEmpty || joinedId == _myUserId) return;
    final info = data['userInfo'] is Map ? data['userInfo'] as Map : const {};
    final username = (info['username'] ?? joinedId).toString();

    // Deterministic glare-free initiator: lower userId always sends the offer
    final shouldInitiate = _myUserId.compareTo(joinedId) < 0;
    await _createMeetingPeer(
      peerUserId: joinedId,
      peerUsername: username,
      isInitiator: shouldInitiate,
      meetingId: _activeMeeting!.meetingId,
    );
  }

  Future<void> _handleMeetingExistingUsers(Map<String, dynamic> data) async {
    if (_meetingPhase != MeetingPhase.inMeeting || _activeMeeting == null) {
      return;
    }
    final users = data['users'] as List<dynamic>? ?? const [];
    for (final raw in users) {
      if (raw is! Map) continue;
      final uid = (raw['userId'] ?? '').toString();
      final uname = (raw['username'] ?? uid).toString();
      if (uid.isEmpty || uid == _myUserId) continue;
      // Deterministic glare-free initiator: lower userId always sends the offer
      final shouldInitiate = _myUserId.compareTo(uid) < 0;
      await _createMeetingPeer(
        peerUserId: uid,
        peerUsername: uname,
        isInitiator: shouldInitiate,
        meetingId: _activeMeeting!.meetingId,
      );
    }
  }

  Future<void> _handleMeetingSignal(Map<String, dynamic> data) async {
    if (_meetingPhase != MeetingPhase.inMeeting || _activeMeeting == null) {
      return;
    }
    final fromUserId = (data['fromUserId'] ?? '').toString();
    final fromUsername = (data['fromUsername'] ?? fromUserId).toString();
    final signal = data['signal'];
    if (fromUserId.isEmpty || signal is! Map) return;

    final type = (signal['type'] ?? '').toString();

    if (type == 'offer') {
      final rawOffer = signal['offer'];
      if (rawOffer is! Map) return;
      final pc = await _createMeetingPeer(
        peerUserId: fromUserId,
        peerUsername: fromUsername,
        isInitiator: false,
        meetingId: _activeMeeting!.meetingId,
      );
      if (pc.signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
        // Ignore colliding offer if we are the designated initiator (lower userId), else rollback cleanly
        if (_myUserId.compareTo(fromUserId) < 0) return;
        try {
          await pc.setLocalDescription(RTCSessionDescription('', 'rollback'));
        } catch (_) {}
      }
      await pc.setRemoteDescription(
        RTCSessionDescription(
          rawOffer['sdp']?.toString(),
          rawOffer['type']?.toString() ?? 'offer',
        ),
      );
      _remoteMeetingDescSet.add(fromUserId);
      for (final c in List<RTCIceCandidate>.from(
        _pendingMeetingCandidates[fromUserId] ?? const [],
      )) {
        try {
          await pc.addCandidate(c);
        } catch (_) {}
      }
      _pendingMeetingCandidates[fromUserId] = [];

      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      MessengerSocketService.instance.emit('meeting:signal', {
        'targetUserId': fromUserId,
        'signal': {
          'type': 'answer',
          'answer': {'sdp': answer.sdp, 'type': answer.type},
        },
        'meetingId': _activeMeeting!.meetingId,
      });
    } else if (type == 'answer') {
      final rawAnswer = signal['answer'];
      final pc = _meetingPeers[fromUserId];
      if (pc == null || rawAnswer is! Map) return;
      await pc.setRemoteDescription(
        RTCSessionDescription(
          rawAnswer['sdp']?.toString(),
          rawAnswer['type']?.toString() ?? 'answer',
        ),
      );
      _remoteMeetingDescSet.add(fromUserId);
      for (final c in List<RTCIceCandidate>.from(
        _pendingMeetingCandidates[fromUserId] ?? const [],
      )) {
        try {
          await pc.addCandidate(c);
        } catch (_) {}
      }
      _pendingMeetingCandidates[fromUserId] = [];
    } else if (type == 'candidate') {
      final rawCand = signal['candidate'];
      if (rawCand is! Map) return;
      final candidate = RTCIceCandidate(
        rawCand['candidate']?.toString(),
        rawCand['sdpMid']?.toString(),
        rawCand['sdpMLineIndex'] is int
            ? rawCand['sdpMLineIndex'] as int
            : null,
      );
      final pc = _meetingPeers[fromUserId];
      if (pc != null && _remoteMeetingDescSet.contains(fromUserId)) {
        try {
          await pc.addCandidate(candidate);
        } catch (_) {}
      } else {
        (_pendingMeetingCandidates[fromUserId] ??= []).add(candidate);
      }
    }
  }

  Future<void> _handleMeetingUserLeft(Map<String, dynamic> data) async {
    final leftId = (data['userId'] ?? '').toString();
    if (leftId.isEmpty) return;

    final pc = _meetingPeers.remove(leftId);
    try {
      await pc?.close();
    } catch (_) {}
    _pendingMeetingCandidates.remove(leftId);

    final participant = _meetingParticipants.remove(leftId);
    try {
      await participant?.renderer.dispose();
    } catch (_) {}

    notifyListeners();
  }

  void _handleMeetingError(Map<String, dynamic> data) {
    _statusMessage = (data['message'] ?? 'Meeting access denied').toString();
    leaveGroupMeeting();
  }

  /// Tear down active call state & listeners on user logout or account switch.
  Future<void> resetOnLogout() async {
    await _cleanupCall();
    await leaveGroupMeeting();
    _handledTerminalCallIds.clear();
    _handledTerminalMeetingIds.clear();
    _remoteMeetingDescSet.clear();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _listenersAttached = false;
    _currentUser = null;
    CommunicationDiagnostics.instance.log('call_mgr:reset_logout');
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    super.dispose();
  }
}
