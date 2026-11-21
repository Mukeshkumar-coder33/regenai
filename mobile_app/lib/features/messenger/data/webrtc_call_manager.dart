import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../auth/data/user_model.dart';
import 'call_notification_service.dart';
import 'messenger_model.dart';
import 'messenger_socket_service.dart';

enum CallPhase { idle, incoming, calling, connected }
enum MeetingPhase { idle, invited, inMeeting }

class MeetingParticipantState {
  final String userId;
  final String username;
  final RTCVideoRenderer renderer;
  final bool hasVideo;
  final String connectionStatus; // 'connecting' | 'connected' | 'disconnected'

  const MeetingParticipantState({
    required this.userId,
    required this.username,
    required this.renderer,
    this.hasVideo = false,
    this.connectionStatus = 'connecting',
  });

  MeetingParticipantState copyWith({
    bool? hasVideo,
    String? connectionStatus,
  }) {
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
/// Mirrors website `frontend/src/components/CallManager.jsx` and `server/socket.js`
/// event-for-event so Android, iOS, and Web users can call each other seamlessly.
class WebRtcCallManager extends ChangeNotifier {
  WebRtcCallManager._();
  static final WebRtcCallManager instance = WebRtcCallManager._();

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

  static String formatDuration(int totalSeconds) {
    final mins = totalSeconds ~/ 60;
    final secs = totalSeconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void bindUser(UserModel user) {
    _currentUser = user;
    if (_listenersAttached) return;
    _listenersAttached = true;

    final socket = MessengerSocketService.instance;
    _subs.addAll([
      socket.onCallIncoming.listen(_handleIncomingCall),
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
  }

  void clearStatusMessage() {
    if (_statusMessage != null) {
      _statusMessage = null;
      notifyListeners();
    }
  }

  /// Request microphone (and camera if video) runtime permissions on Android/iOS.
  Future<({bool granted, bool videoAllowed, String? error})> _requestMediaPermissions({
    required bool requireVideo,
  }) async {
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
          error: 'Microphone permission is required to make calls.'
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
        // Audio-only fallback when camera is unavailable
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
      _statusMessage = 'Connecting to real-time server... please try again in a moment.';
      notifyListeners();
      socket.ensureConnected();
      return;
    }
    if (_callPhase != CallPhase.idle || _meetingPhase == MeetingPhase.inMeeting) {
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

      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }

      pc.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          _remoteRenderer?.srcObject = event.streams.first;
          notifyListeners();
        }
      };

      final newCallId = 'call-${DateTime.now().millisecondsSinceEpoch}';
      pc.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate != null) {
          socket.emit('call:signal', {
            'targetUserId': recipientId,
            'signal': {
              'candidate': {
                'candidate': candidate.candidate,
                'sdpMid': candidate.sdpMid,
                'sdpMLineIndex': candidate.sdpMLineIndex,
              }
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
      await _setAudioOutput(speaker: _isSpeakerOn);
      notifyListeners();

      socket.emit('call:initiate', {
        'callId': newCallId,
        'recipientId': recipientId,
        'mediaType': _callMediaType,
        'offer': {'sdp': offer.sdp, 'type': offer.type},
      });
    } catch (e) {
      _statusMessage = 'Unable to start call: $e';
      await _cleanupCall();
    }
  }

  Future<void> acceptIncomingCall() async {
    if (_callPhase != CallPhase.incoming || _callId == null || _peerId == null) return;
    final socket = MessengerSocketService.instance;
    await CallNotificationService.instance.cancelCallNotification(_callId!);
    await CallNotificationService.instance.cancelAllCallNotifications();

    final wantVideo = _callMediaType == 'video';
    final perm = await _requestMediaPermissions(requireVideo: wantVideo);
    if (!perm.granted) {
      _statusMessage = perm.error;
      rejectIncomingCall();
      return;
    }

    try {
      Map<String, dynamic>? offer = _pendingOffer;
      if (offer == null) {
        final active = await socket.emitWithAck('call:get-active', {'callId': _callId});
        if (active is Map && active['offer'] is Map) {
          offer = Map<String, dynamic>.from(active['offer'] as Map);
        }
      }
      if (offer == null) {
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

      final pc = await createPeerConnection(_iceConfig);
      _peerConnection = pc;

      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }

      pc.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          _remoteRenderer?.srcObject = event.streams.first;
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
              }
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

      for (final c in List<RTCIceCandidate>.from(_pendingCandidates)) {
        await pc.addCandidate(c);
      }
      _pendingCandidates.clear();

      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);

      socket.emit('call:accept', {
        'callId': _callId,
        'callerId': _peerId,
        'answer': {'sdp': answer.sdp, 'type': answer.type},
      });

      _isMuted = false;
      _isVideoOff = !effectiveVideo;
      _isSpeakerOn = effectiveVideo;
      _callPhase = CallPhase.connected;
      _startCallDurationTimer();
      await _setAudioOutput(speaker: _isSpeakerOn);
      notifyListeners();
    } catch (e) {
      _statusMessage = 'Failed to accept call: $e';
      await _cleanupCall();
    }
  }

  Future<void> rejectIncomingCall({String reason = 'declined'}) async {
    if (_callId != null && _peerId != null) {
      await CallNotificationService.instance.cancelCallNotification(_callId!);
      await CallNotificationService.instance.cancelAllCallNotifications();
      MessengerSocketService.instance.emit('call:reject', {
        'callId': _callId,
        'callerId': _peerId,
        'reason': reason,
      });
    }
    await _cleanupCall();
  }

  Future<void> endCall() async {
    if (_callId != null && _peerId != null) {
      await CallNotificationService.instance.cancelCallNotification(_callId!);
      await CallNotificationService.instance.cancelAllCallNotifications();
      MessengerSocketService.instance.emit('call:end', {
        'callId': _callId,
        'targetUserId': _peerId,
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

  Future<void> _cleanupCall() async {
    _callTimer?.cancel();
    _callTimer = null;
    if (_callId != null) {
      await CallNotificationService.instance.cancelCallNotification(_callId!);
    }
    await CallNotificationService.instance.cancelAllCallNotifications();

    try {
      _localStream?.getTracks().forEach((t) => t.stop());
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;

    try {
      await _peerConnection?.close();
    } catch (_) {}
    _peerConnection = null;
    _pendingCandidates.clear();

    try {
      await _localRenderer?.dispose();
    } catch (_) {}
    _localRenderer = null;

    try {
      await _remoteRenderer?.dispose();
    } catch (_) {}
    _remoteRenderer = null;

    _callPhase = CallPhase.idle;
    _callId = null;
    _peerId = null;
    _peerName = null;
    _pendingOffer = null;
    _isMuted = false;
    _isVideoOff = false;
    _isSpeakerOn = false;
    _callDurationSeconds = 0;
    notifyListeners();
  }

  // ── 1:1 Socket Handlers ────────────────────────────────────────
  void _handleIncomingCall(Map<String, dynamic> data) {
    final incoming = IncomingCallPayload.fromMap(data);
    if (incoming.callId.isEmpty || incoming.callerId.isEmpty) return;

    if (_callPhase != CallPhase.idle || _meetingPhase == MeetingPhase.inMeeting) {
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
    notifyListeners();

    CallNotificationService.instance.showIncomingCallNotification(
      callId: incoming.callId,
      callerName: incoming.callerName,
      mediaType: incoming.mediaType,
    );
  }

  Future<void> _handleCallAccepted(Map<String, dynamic> data) async {
    if (_peerConnection == null) return;
    final rawAnswer = data['answer'];
    if (rawAnswer is! Map) return;
    try {
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(
          rawAnswer['sdp']?.toString(),
          rawAnswer['type']?.toString() ?? 'answer',
        ),
      );
      for (final c in List<RTCIceCandidate>.from(_pendingCandidates)) {
        await _peerConnection!.addCandidate(c);
      }
      _pendingCandidates.clear();
      _callPhase = CallPhase.connected;
      _startCallDurationTimer();
      notifyListeners();
    } catch (e) {
      _statusMessage = 'WebRTC handshake error: $e';
      await _cleanupCall();
    }
  }

  Future<void> _handleCallRejected(Map<String, dynamic> data) async {
    final reason = (data['reason'] ?? 'declined').toString();
    _statusMessage = reason == 'busy'
        ? '${_peerName ?? 'User'} is on another call'
        : 'Call $reason';
    await _cleanupCall();
  }

  Future<void> _handleCallSignal(Map<String, dynamic> data) async {
    final signal = data['signal'];
    if (signal is! Map) return;
    final rawCand = signal['candidate'];
    if (rawCand is! Map) return;

    final candidate = RTCIceCandidate(
      rawCand['candidate']?.toString(),
      rawCand['sdpMid']?.toString(),
      rawCand['sdpMLineIndex'] is int ? rawCand['sdpMLineIndex'] as int : null,
    );

    if (_peerConnection != null && _callPhase == CallPhase.connected) {
      try {
        await _peerConnection!.addCandidate(candidate);
      } catch (_) {}
    } else {
      _pendingCandidates.add(candidate);
    }
  }

  Future<void> _handleCallEnded(Map<String, dynamic> data) async {
    _statusMessage = 'Call ended';
    await _cleanupCall();
  }

  Future<void> _handleCallCancelled(Map<String, dynamic> data) async {
    final cancelledCallId = data['callId']?.toString();
    if (_callId != null && cancelledCallId != null && _callId != cancelledCallId) {
      return;
    }
    _statusMessage = 'Call cancelled by caller';
    await _cleanupCall();
  }

  // ═══════════════════════════════════════════════════════════════
  // GROUP VOICE & VIDEO CALLS (WEBRTC MESH — EXACT WEBSITE PROTOCOL)
  // ═══════════════════════════════════════════════════════════════

  Future<void> startGroupMeeting({
    required String title,
    String mediaType = 'video',
    String? conversationId,
    List<String>? participantIds,
  }) async {
    final socket = MessengerSocketService.instance;
    if (!socket.isConnected) {
      _statusMessage = 'Connecting to real-time server... please try again.';
      notifyListeners();
      socket.ensureConnected();
      return;
    }

    final meetingId = 'meeting-${DateTime.now().millisecondsSinceEpoch}';
    socket.emit('meeting:start', {
      'meetingId': meetingId,
      'title': title,
      'mediaType': mediaType,
      if (conversationId != null && conversationId.isNotEmpty) 'conversationId': conversationId,
      if (participantIds != null && participantIds.isNotEmpty) 'participantIds': participantIds,
    });

    await joinGroupMeeting(
      MeetingInvitePayload(
        meetingId: meetingId,
        title: title,
        hostId: _myUserId,
        hostName: _myDisplayName,
        mediaType: mediaType,
        conversationId: conversationId,
      ),
    );
  }

  Future<void> joinGroupMeeting(MeetingInvitePayload invite) async {
    final socket = MessengerSocketService.instance;
    if (!socket.isConnected) {
      _statusMessage = 'Real-time connection unavailable.';
      notifyListeners();
      return;
    }
    await CallNotificationService.instance.cancelCallNotification(invite.meetingId);

    final wantVideo = invite.mediaType == 'video';
    final perm = await _requestMediaPermissions(requireVideo: wantVideo);
    if (!perm.granted) {
      _statusMessage = perm.error;
      _meetingPhase = MeetingPhase.idle;
      _activeMeeting = null;
      notifyListeners();
      return;
    }

    try {
      final effectiveVideo = wantVideo && perm.videoAllowed;
      final stream = await _openLocalMediaStream(video: effectiveVideo);
      _localStream = stream;

      _meetingLocalRenderer = RTCVideoRenderer();
      await _meetingLocalRenderer!.initialize();
      _meetingLocalRenderer!.srcObject = stream;

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
    } catch (e) {
      _statusMessage = 'Could not join group call: $e';
      await leaveGroupMeeting();
    }
  }

  void dismissMeetingInvite() {
    if (_activeMeeting != null) {
      CallNotificationService.instance.cancelCallNotification(_activeMeeting!.meetingId);
    }
    _activeMeeting = null;
    _meetingPhase = MeetingPhase.idle;
    notifyListeners();
  }

  Future<void> leaveGroupMeeting() async {
    _meetingTimer?.cancel();
    _meetingTimer = null;

    if (_activeMeeting != null) {
      await CallNotificationService.instance.cancelCallNotification(_activeMeeting!.meetingId);
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
      final label = state == RTCPeerConnectionState.RTCPeerConnectionStateConnected
          ? 'connected'
          : (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
                  state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected)
              ? 'disconnected'
              : 'connecting';
      _meetingParticipants[peerUserId] = existing.copyWith(connectionStatus: label);
      notifyListeners();
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
            }
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
    if (invite.meetingId.isEmpty || invite.hostId == _myUserId) return;
    if (_meetingPhase == MeetingPhase.inMeeting || _callPhase != CallPhase.idle) return;

    _activeMeeting = invite;
    _meetingPhase = MeetingPhase.invited;
    notifyListeners();

    CallNotificationService.instance.showIncomingCallNotification(
      callId: invite.meetingId,
      callerName: invite.hostName,
      mediaType: invite.mediaType,
      isMeeting: true,
    );
  }

  Future<void> _handleMeetingUserJoined(Map<String, dynamic> data) async {
    if (_meetingPhase != MeetingPhase.inMeeting || _activeMeeting == null) return;
    final joinedId = (data['userId'] ?? '').toString();
    if (joinedId.isEmpty || joinedId == _myUserId) return;
    final info = data['userInfo'] is Map ? data['userInfo'] as Map : const {};
    final username = (info['username'] ?? joinedId).toString();

    await _createMeetingPeer(
      peerUserId: joinedId,
      peerUsername: username,
      isInitiator: true,
      meetingId: _activeMeeting!.meetingId,
    );
  }

  Future<void> _handleMeetingExistingUsers(Map<String, dynamic> data) async {
    if (_meetingPhase != MeetingPhase.inMeeting || _activeMeeting == null) return;
    final users = data['users'] as List<dynamic>? ?? const [];
    for (final raw in users) {
      if (raw is! Map) continue;
      final uid = (raw['userId'] ?? '').toString();
      final uname = (raw['username'] ?? uid).toString();
      if (uid.isEmpty || uid == _myUserId) continue;
      await _createMeetingPeer(
        peerUserId: uid,
        peerUsername: uname,
        isInitiator: true,
        meetingId: _activeMeeting!.meetingId,
      );
    }
  }

  Future<void> _handleMeetingSignal(Map<String, dynamic> data) async {
    if (_meetingPhase != MeetingPhase.inMeeting || _activeMeeting == null) return;
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
      await pc.setRemoteDescription(
        RTCSessionDescription(rawOffer['sdp']?.toString(), rawOffer['type']?.toString() ?? 'offer'),
      );
      for (final c in List<RTCIceCandidate>.from(_pendingMeetingCandidates[fromUserId] ?? const [])) {
        await pc.addCandidate(c);
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
        RTCSessionDescription(rawAnswer['sdp']?.toString(), rawAnswer['type']?.toString() ?? 'answer'),
      );
      for (final c in List<RTCIceCandidate>.from(_pendingMeetingCandidates[fromUserId] ?? const [])) {
        await pc.addCandidate(c);
      }
      _pendingMeetingCandidates[fromUserId] = [];
    } else if (type == 'candidate') {
      final rawCand = signal['candidate'];
      if (rawCand is! Map) return;
      final candidate = RTCIceCandidate(
        rawCand['candidate']?.toString(),
        rawCand['sdpMid']?.toString(),
        rawCand['sdpMLineIndex'] is int ? rawCand['sdpMLineIndex'] as int : null,
      );
      final pc = _meetingPeers[fromUserId];
      if (pc != null) {
        try {
          await pc.addCandidate(candidate);
        } catch (_) {
          (_pendingMeetingCandidates[fromUserId] ??= []).add(candidate);
        }
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

  /// Tear down active sessions on user logout.
  Future<void> resetOnLogout() async {
    await _cleanupCall();
    await leaveGroupMeeting();
    _currentUser = null;
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

