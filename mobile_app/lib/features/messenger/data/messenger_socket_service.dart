import 'dart:async';
import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../../../app/app_config.dart';
import '../../../core/storage/session_storage.dart';
import '../../../core/utils/json_normalizer.dart';
import '../../auth/data/user_model.dart';
import 'communication_diagnostics.dart';

/// Singleton Socket.IO client connecting to the existing ReGen backend at `/ws`.
/// Reuses the website transport, JWT auth handshake, and event protocol.
/// Independent of individual UI modules/tabs: lives for the full authenticated session.
class MessengerSocketService {
  MessengerSocketService._() {
    AppConfig.baseUrlNotifier.addListener(_onBaseUrlChanged);
  }
  static final MessengerSocketService instance = MessengerSocketService._();

  static const String _prefDeviceIdKey = 'regen_device_session_id';

  void _onBaseUrlChanged() {
    if (_socket != null && _activeServerUrl != null && _activeServerUrl != AppConfig.socketBaseUrl) {
      CommunicationDiagnostics.instance.log('socket:server_changed', {
        'from': _activeServerUrl,
        'to': AppConfig.socketBaseUrl,
      });
      reconnectForServerChange();
    }
  }

  io.Socket? _socket;
  String? _activeServerUrl;
  String? _activeToken;
  String? _activeUserId;
  String? _deviceId;
  bool _isConnected = false;
  bool _isConnecting = false;
  String? _activeConversationId;
  Future<void>? _connectInFlight;

  bool get isConnected => _isConnected && (_socket?.connected ?? false);
  bool get isConnecting => _isConnecting;
  String? get activeServerUrl => _activeServerUrl;
  String? get activeUserId => _activeUserId;
  String? get deviceId => _deviceId;
  String? get activeConversationId => _activeConversationId;

  bool isConversationActive(String? convId) =>
      convId != null && _activeConversationId != null && _activeConversationId == convId;

  void setActiveConversation(String? convId) {
    _activeConversationId = convId;
    if (convId != null && convId.isNotEmpty) {
      emit('dm:join-conversation', {'conversationId': convId});
    } else {
      emit('dm:leave-conversation', {});
    }
  }

  final _connectionController = StreamController<bool>.broadcast();
  final _authInvalidatedController = StreamController<String>.broadcast();
  final _messageChangeController = StreamController<Map<String, dynamic>>.broadcast();
  final _dmChangeController = StreamController<Map<String, dynamic>>.broadcast();
  final _dmKeyExchangeController = StreamController<Map<String, dynamic>>.broadcast();
  final _notificationController = StreamController<Map<String, dynamic>>.broadcast();
  final _notificationReadController = StreamController<Map<String, dynamic>>.broadcast();
  final _notificationReadAllController = StreamController<Map<String, dynamic>>.broadcast();
  final _notificationClearAllController = StreamController<Map<String, dynamic>>.broadcast();
  final _notificationChangeController = StreamController<Map<String, dynamic>>.broadcast();
  final _taskChangeController = StreamController<Map<String, dynamic>>.broadcast();
  final _presenceController = StreamController<Map<String, dynamic>>.broadcast();
  final _presenceSnapshotController = StreamController<Map<String, dynamic>>.broadcast();

  // 1:1 WebRTC signaling streams
  final _callIncomingController = StreamController<Map<String, dynamic>>.broadcast();
  final _callStateController = StreamController<Map<String, dynamic>>.broadcast();
  final _callAcceptedController = StreamController<Map<String, dynamic>>.broadcast();
  final _callRejectedController = StreamController<Map<String, dynamic>>.broadcast();
  final _callCancelledController = StreamController<Map<String, dynamic>>.broadcast();
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
  Stream<String> get onAuthInvalidated => _authInvalidatedController.stream;
  Stream<Map<String, dynamic>> get onMessageChange => _messageChangeController.stream;
  Stream<Map<String, dynamic>> get onDmChange => _dmChangeController.stream;
  Stream<Map<String, dynamic>> get onDmKeyExchange => _dmKeyExchangeController.stream;
  Stream<Map<String, dynamic>> get onNotification => _notificationController.stream;
  Stream<Map<String, dynamic>> get onNotificationRead => _notificationReadController.stream;
  Stream<Map<String, dynamic>> get onNotificationReadAll => _notificationReadAllController.stream;
  Stream<Map<String, dynamic>> get onNotificationClearAll => _notificationClearAllController.stream;
  Stream<Map<String, dynamic>> get onNotificationChange => _notificationChangeController.stream;
  Stream<Map<String, dynamic>> get onTaskChange => _taskChangeController.stream;
  Stream<Map<String, dynamic>> get onPresenceUpdate => _presenceController.stream;
  Stream<Map<String, dynamic>> get onPresenceSnapshot => _presenceSnapshotController.stream;

  Stream<Map<String, dynamic>> get onCallIncoming => _callIncomingController.stream;
  Stream<Map<String, dynamic>> get onCallState => _callStateController.stream;
  Stream<Map<String, dynamic>> get onCallAccepted => _callAcceptedController.stream;
  Stream<Map<String, dynamic>> get onCallRejected => _callRejectedController.stream;
  Stream<Map<String, dynamic>> get onCallCancelled => _callCancelledController.stream;
  Stream<Map<String, dynamic>> get onCallSignal => _callSignalController.stream;
  Stream<Map<String, dynamic>> get onCallEnded => _callEndedController.stream;

  Stream<Map<String, dynamic>> get onMeetingStarted => _meetingStartedController.stream;
  Stream<Map<String, dynamic>> get onMeetingUserJoined => _meetingUserJoinedController.stream;
  Stream<Map<String, dynamic>> get onMeetingExistingUsers => _meetingExistingUsersController.stream;
  Stream<Map<String, dynamic>> get onMeetingSignal => _meetingSignalController.stream;
  Stream<Map<String, dynamic>> get onMeetingUserLeft => _meetingUserLeftController.stream;
  Stream<Map<String, dynamic>> get onMeetingError => _meetingErrorController.stream;

  static Map<String, dynamic> _asMap(dynamic data) => normalizeJsonMap(data);

  Future<String> _getOrCreateDeviceId() async {
    if (_deviceId != null && _deviceId!.isNotEmpty) return _deviceId!;
    try {
      final prefs = await SharedPreferences.getInstance();
      var existing = prefs.getString(_prefDeviceIdKey);
      if (existing == null || existing.isEmpty) {
        final rand = Random.secure().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
        existing = 'mob-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-$rand';
        await prefs.setString(_prefDeviceIdKey, existing);
      }
      _deviceId = existing;
      return existing;
    } catch (_) {
      _deviceId ??= 'mob-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
      return _deviceId!;
    }
  }

  /// Connect (or reuse existing socket) for the authenticated ReGen user.
  Future<void> connect({required UserModel user}) async {
    if (WidgetsBinding.instance.runtimeType.toString().contains('Test')) return;

    if (_connectInFlight != null) {
      await _connectInFlight;
    }

    final future = _connectInternal(user);
    _connectInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_connectInFlight, future)) {
        _connectInFlight = null;
      }
    }
  }

  Future<void> _connectInternal(UserModel user) async {
    final storedToken = await SessionStorage.getToken();
    final token = user.token.isNotEmpty ? user.token : (storedToken ?? '');
    if (token.isEmpty) return;

    final uid = user.userId.isNotEmpty ? user.userId : user.id;
    final targetServerUrl = AppConfig.socketBaseUrl;
    final devId = await _getOrCreateDeviceId();

    // Reuse active socket only when server URL, token, and user ID all match
    if (_socket != null &&
        _activeServerUrl == targetServerUrl &&
        _activeToken == token &&
        _activeUserId == uid) {
      if (!(_socket!.connected)) {
        _isConnecting = true;
        _socket!.connect();
      }
      return;
    }

    _disposeRawSocketOnly();

    _activeServerUrl = targetServerUrl;
    _activeToken = token;
    _activeUserId = uid;
    _isConnecting = true;

    CommunicationDiagnostics.instance.log('socket:connect_attempt', {
      'userId': uid,
      'server': targetServerUrl,
      'deviceId': devId,
    });

    final options = io.OptionBuilder()
        .setPath('/ws')
        .setTransports(['websocket', 'polling'])
        .setAuth({'token': token, 'deviceId': devId})
        .setQuery({'token': token})
        .enableAutoConnect()
        .enableReconnection()
        .enableForceNewConnection()
        .setReconnectionAttempts(999999)
        .setReconnectionDelay(1000)
        .setReconnectionDelayMax(6000)
        .setTimeout(10000)
        .build();

    final socket = io.io(targetServerUrl, options);

    socket.onConnect((_) {
      _isConnected = true;
      _isConnecting = false;
      _connectionController.add(true);
      CommunicationDiagnostics.instance.log('socket:connected', {
        'userId': uid,
        'server': targetServerUrl,
        'socketId': socket.id ?? '',
        'deviceId': devId,
      });
      if (_activeConversationId != null && _activeConversationId!.isNotEmpty) {
        socket.emit('dm:join-conversation', {'conversationId': _activeConversationId});
      }
    });

    socket.onDisconnect((reason) {
      _isConnected = false;
      _isConnecting = false;
      _connectionController.add(false);
      CommunicationDiagnostics.instance.log('socket:disconnected', {
        'userId': uid,
        'reason': reason?.toString() ?? 'unknown',
      });
    });

    socket.onReconnect((attempt) {
      _isConnected = true;
      _isConnecting = false;
      _connectionController.add(true);
      CommunicationDiagnostics.instance.log('socket:reconnected', {
        'userId': uid,
        'attempt': attempt?.toString() ?? '',
      });
      if (_activeConversationId != null && _activeConversationId!.isNotEmpty) {
        socket.emit('dm:join-conversation', {'conversationId': _activeConversationId});
      }
    });

    socket.onReconnectAttempt((attempt) {
      _isConnecting = true;
      CommunicationDiagnostics.instance.log('socket:reconnect_attempt', {
        'userId': uid,
        'attempt': attempt?.toString() ?? '',
      });
    });

    socket.onConnectError((err) {
      _isConnected = false;
      _isConnecting = false;
      _connectionController.add(false);
      final errStr = err?.toString() ?? 'unknown';
      CommunicationDiagnostics.instance.log('socket:connect_error', {
        'userId': uid,
        'server': targetServerUrl,
        'error': errStr,
      });

      final lowerErr = errStr.toLowerCase();
      if (lowerErr.contains('invalid token') ||
          lowerErr.contains('session expired') ||
          lowerErr.contains('account suspended') ||
          lowerErr.contains('authentication required') ||
          lowerErr.contains('invalid session')) {
        // Stop reconnecting with an invalid/revoked JWT and notify coordinator cleanly
        _disposeRawSocketOnly();
        _authInvalidatedController.add(errStr);
        return;
      }

      if (AppConfig.isAutoMode && AppConfig.isCurrentlyUsingLocal) {
        AppConfig.handleConnectionErrorFailover();
      }
    });

    // Messaging, Tasks & Notifications
    socket.on('message:change', (d) => _messageChangeController.add(_asMap(d)));
    socket.on('dm:change', (d) {
      final mapped = _asMap(d);
      CommunicationDiagnostics.instance.log('socket:dm_change', {
        'action': mapped['action'] ?? '',
        'conversationId': mapped['conversationId'] ?? '',
      });
      _dmChangeController.add(mapped);
    });
    socket.on('dm:key-exchange', (d) => _dmKeyExchangeController.add(_asMap(d)));
    socket.on('notification:new', (d) => _notificationController.add(_asMap(d)));
    socket.on('notification:read', (d) => _notificationReadController.add(_asMap(d)));
    socket.on('notification:read_all', (d) => _notificationReadAllController.add(_asMap(d)));
    socket.on('notification:clear_all', (d) => _notificationClearAllController.add(_asMap(d)));
    socket.on('notification:change', (d) => _notificationChangeController.add(_asMap(d)));
    socket.on('task:change', (d) => _taskChangeController.add(_asMap(d)));
    socket.on('presence:update', (d) => _presenceController.add(_asMap(d)));
    socket.on('presence:snapshot', (d) => _presenceSnapshotController.add(_asMap(d)));

    // 1:1 WebRTC Call Signaling
    socket.on('call:incoming', (d) {
      final mapped = _asMap(d);
      CommunicationDiagnostics.instance.log('socket:call_incoming', {
        'callId': mapped['callId'] ?? '',
        'correlationId': mapped['correlationId'] ?? '',
      });
      _callIncomingController.add(mapped);
    });
    socket.on('call:state', (d) {
      final mapped = _asMap(d);
      CommunicationDiagnostics.instance.log('socket:call_state', {
        'callId': mapped['callId'] ?? '',
        'state': mapped['state'] ?? '',
      });
      _callStateController.add(mapped);
    });
    socket.on('call:accepted', (d) => _callAcceptedController.add(_asMap(d)));
    socket.on('call:rejected', (d) => _callRejectedController.add(_asMap(d)));
    socket.on('call:cancelled', (d) => _callCancelledController.add(_asMap(d)));
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

  /// Wait briefly for an active or in-progress socket connection to settle before signaling.
  Future<bool> waitUntilConnected({Duration timeout = const Duration(seconds: 4)}) async {
    if (isConnected) return true;
    if (WidgetsBinding.instance.runtimeType.toString().contains('Test')) return false;

    await ensureConnected();
    if (isConnected) return true;

    final completer = Completer<bool>();
    late StreamSubscription<bool> sub;
    sub = onConnectionChange.listen((connected) {
      if (connected && !completer.isCompleted) {
        completer.complete(true);
      }
    });

    try {
      return await completer.future.timeout(timeout, onTimeout: () => isConnected);
    } finally {
      await sub.cancel();
    }
  }

  /// Ensure socket connects cleanly using the currently selected server.
  Future<void> ensureConnected({bool forceNew = false}) async {
    if (WidgetsBinding.instance.runtimeType.toString().contains('Test')) return;
    final targetServerUrl = AppConfig.socketBaseUrl;
    if (_socket == null || _activeServerUrl != targetServerUrl || forceNew) {
      final savedUser = await SessionStorage.getUserSession();
      _disposeRawSocketOnly();
      if (savedUser != null && savedUser.token.isNotEmpty) {
        await connect(user: savedUser);
      }
      return;
    }
    if (!(_socket!.connected)) {
      _isConnecting = true;
      _socket!.connect();
    }
  }

  /// Force reconnection against [AppConfig.socketBaseUrl] without duplicating sockets.
  Future<void> reconnectForServerChange({UserModel? user}) async {
    _disposeRawSocketOnly();
    final activeUser = user ?? await SessionStorage.getUserSession();
    if (activeUser != null && activeUser.token.isNotEmpty) {
      await connect(user: activeUser);
    }
  }

  void emit(String event, Map<String, dynamic> payload) {
    _socket?.emit(event, payload);
  }

  @visibleForTesting
  void debugInjectRawEvent(String event, dynamic raw) {
    switch (event) {
      case 'connection':
        final connected = raw == true;
        _isConnected = connected;
        _connectionController.add(connected);
        break;
      case 'dm:change':
        _dmChangeController.add(_asMap(raw));
        break;
      case 'message:change':
        _messageChangeController.add(_asMap(raw));
        break;
      case 'notification:new':
        _notificationController.add(_asMap(raw));
        break;
      case 'call:incoming':
        _callIncomingController.add(_asMap(raw));
        break;
      case 'call:state':
        _callStateController.add(_asMap(raw));
        break;
      case 'call:accepted':
        _callAcceptedController.add(_asMap(raw));
        break;
      case 'call:cancelled':
        _callCancelledController.add(_asMap(raw));
        break;
      case 'call:ended':
        _callEndedController.add(_asMap(raw));
        break;
      case 'meeting:started':
        _meetingStartedController.add(_asMap(raw));
        break;
    }
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
        if (response == null) {
          completer.complete(null);
        } else if (response is Map || (response is List && response.any((e) => e is Map))) {
          final normalized = _asMap(response);
          completer.complete(normalized.isNotEmpty ? normalized : response);
        } else {
          completer.complete(response);
        }
      }
    });
    return completer.future.timeout(timeout, onTimeout: () => null);
  }

  void _disposeRawSocketOnly() {
    if (_socket != null) {
      try {
        _socket!.clearListeners();
        _socket!.disconnect();
        _socket!.dispose();
      } catch (_) {}
      _socket = null;
    }
    _isConnected = false;
    _isConnecting = false;
    _connectionController.add(false);
  }

  void disconnect() {
    _disposeRawSocketOnly();
    _activeServerUrl = null;
    _activeToken = null;
    _activeUserId = null;
    _activeConversationId = null;
    CommunicationDiagnostics.instance.log('socket:disconnected_explicit');
  }
}
