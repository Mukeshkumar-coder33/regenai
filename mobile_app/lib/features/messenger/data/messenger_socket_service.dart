import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../../../app/app_config.dart';
import '../../../core/storage/session_storage.dart';
import '../../auth/data/user_model.dart';

/// Singleton Socket.IO client connecting to the existing ReGen backend at `/ws`.
/// Reuses the exact website transport, JWT auth handshake, and event names.
class MessengerSocketService {
  MessengerSocketService._();
  static final MessengerSocketService instance = MessengerSocketService._();

  io.Socket? _socket;
  String? _activeToken;
  String? _activeUserId;
  bool _isConnected = false;

  bool get isConnected => _isConnected && (_socket?.connected ?? false);
  String? get activeUserId => _activeUserId;

  final _connectionController = StreamController<bool>.broadcast();
  final _messageChangeController = StreamController<Map<String, dynamic>>.broadcast();
  final _dmChangeController = StreamController<Map<String, dynamic>>.broadcast();
  final _dmKeyExchangeController = StreamController<Map<String, dynamic>>.broadcast();
  final _notificationController = StreamController<Map<String, dynamic>>.broadcast();
  final _presenceController = StreamController<Map<String, dynamic>>.broadcast();

  // 1:1 WebRTC signaling streams
  final _callIncomingController = StreamController<Map<String, dynamic>>.broadcast();
  final _callAcceptedController = StreamController<Map<String, dynamic>>.broadcast();
  final _callRejectedController = StreamController<Map<String, dynamic>>.broadcast();
  final _callSignalController = StreamController<Map<String, dynamic>>.broadcast();
  final _callEndedController = StreamController<Map<String, dynamic>>.broadcast();

  // Group / Team WebRTC Mesh signaling streams
  final _meetingStartedController = StreamController<Map<String, dynamic>>.broadcast();
  final _meetingUserJoinedController = StreamController<Map<String, dynamic>>.broadcast();
  final _meetingExistingUsersController = StreamController<Map<String, dynamic>>.broadcast();
  final _meetingSignalController = StreamController<Map<String, dynamic>>.broadcast();
  final _meetingUserLeftController = StreamController<Map<String, dynamic>>.broadcast();
  final _meetingErrorController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<bool> get onConnectionChange => _connectionController.stream;
  Stream<Map<String, dynamic>> get onMessageChange => _messageChangeController.stream;
  Stream<Map<String, dynamic>> get onDmChange => _dmChangeController.stream;
  Stream<Map<String, dynamic>> get onDmKeyExchange => _dmKeyExchangeController.stream;
  Stream<Map<String, dynamic>> get onNotification => _notificationController.stream;
  Stream<Map<String, dynamic>> get onPresenceUpdate => _presenceController.stream;

  Stream<Map<String, dynamic>> get onCallIncoming => _callIncomingController.stream;
  Stream<Map<String, dynamic>> get onCallAccepted => _callAcceptedController.stream;
  Stream<Map<String, dynamic>> get onCallRejected => _callRejectedController.stream;
  Stream<Map<String, dynamic>> get onCallSignal => _callSignalController.stream;
  Stream<Map<String, dynamic>> get onCallEnded => _callEndedController.stream;

  Stream<Map<String, dynamic>> get onMeetingStarted => _meetingStartedController.stream;
  Stream<Map<String, dynamic>> get onMeetingUserJoined => _meetingUserJoinedController.stream;
  Stream<Map<String, dynamic>> get onMeetingExistingUsers => _meetingExistingUsersController.stream;
  Stream<Map<String, dynamic>> get onMeetingSignal => _meetingSignalController.stream;
  Stream<Map<String, dynamic>> get onMeetingUserLeft => _meetingUserLeftController.stream;
  Stream<Map<String, dynamic>> get onMeetingError => _meetingErrorController.stream;

  static Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  /// Connect (or reuse existing socket) for the authenticated ReGen user.
  Future<void> connect({required UserModel user}) async {
    // Skip real network socket connections inside Flutter widget tests
    if (WidgetsBinding.instance.runtimeType.toString().contains('Test')) return;

    final storedToken = await SessionStorage.getToken();
    final token = user.token.isNotEmpty ? user.token : (storedToken ?? '');
    if (token.isEmpty) return;

    final uid = user.userId.isNotEmpty ? user.userId : user.id;

    // Reuse active socket if token matches
    if (_socket != null && _activeToken == token && _activeUserId == uid) {
      if (!(_socket!.connected)) {
        _socket!.connect();
      }
      return;
    }

    disconnect();

    _activeToken = token;
    _activeUserId = uid;

    final options = io.OptionBuilder()
        .setPath('/ws') // Exact path used by ReGen server/socket.js & website useSocket.js
        .setTransports(['websocket', 'polling'])
        .setAuth({'token': token})
        .setQuery({'token': token})
        .enableAutoConnect()
        .enableReconnection()
        .setReconnectionDelay(1000)
        .setReconnectionDelayMax(5000)
        .setTimeout(10000)
        .build();

    final socket = io.io(AppConfig.activeBaseUrl, options);

    socket.onConnect((_) {
      _isConnected = true;
      _connectionController.add(true);
      debugPrint('[ReGen WS] connected as $uid');
    });

    socket.onDisconnect((reason) {
      _isConnected = false;
      _connectionController.add(false);
      debugPrint('[ReGen WS] disconnected: $reason');
    });

    socket.onConnectError((err) {
      _isConnected = false;
      _connectionController.add(false);
      debugPrint('[ReGen WS] connect error: $err');
    });

    // Messaging & Notifications
    socket.on('message:change', (d) => _messageChangeController.add(_asMap(d)));
    socket.on('dm:change', (d) => _dmChangeController.add(_asMap(d)));
    socket.on('dm:key-exchange', (d) => _dmKeyExchangeController.add(_asMap(d)));
    socket.on('notification:new', (d) => _notificationController.add(_asMap(d)));
    socket.on('presence:update', (d) => _presenceController.add(_asMap(d)));

    // 1:1 WebRTC Call Signaling
    socket.on('call:incoming', (d) => _callIncomingController.add(_asMap(d)));
    socket.on('call:accepted', (d) => _callAcceptedController.add(_asMap(d)));
    socket.on('call:rejected', (d) => _callRejectedController.add(_asMap(d)));
    socket.on('call:signal', (d) => _callSignalController.add(_asMap(d)));
    socket.on('call:ended', (d) => _callEndedController.add(_asMap(d)));

    // Group / Team Meeting WebRTC Mesh Signaling
    socket.on('meeting:started', (d) => _meetingStartedController.add(_asMap(d)));
    socket.on('meeting:user-joined', (d) => _meetingUserJoinedController.add(_asMap(d)));
    socket.on('meeting:existing-users', (d) => _meetingExistingUsersController.add(_asMap(d)));
    socket.on('meeting:signal', (d) => _meetingSignalController.add(_asMap(d)));
    socket.on('meeting:user-left', (d) => _meetingUserLeftController.add(_asMap(d)));
    socket.on('meeting:error', (d) => _meetingErrorController.add(_asMap(d)));

    _socket = socket;
  }

  /// Ensure socket reconnects when returning from background.
  void ensureConnected() {
    if (_socket != null && !(_socket!.connected)) {
      _socket!.connect();
    }
  }

  void emit(String event, Map<String, dynamic> payload) {
    _socket?.emit(event, payload);
  }

  Future<dynamic> emitWithAck(
    String event,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (_socket == null) return null;
    final completer = Completer<dynamic>();
    _socket!.emitWithAck(event, payload, ack: (response) {
      if (!completer.isCompleted) {
        completer.complete(response);
      }
    });
    return completer.future.timeout(timeout, onTimeout: () => null);
  }

  void disconnect() {
    if (_socket != null) {
      try {
        _socket!.clearListeners();
        _socket!.disconnect();
        _socket!.dispose();
      } catch (_) {}
      _socket = null;
    }
    _activeToken = null;
    _activeUserId = null;
    _isConnected = false;
    _connectionController.add(false);
  }
}

