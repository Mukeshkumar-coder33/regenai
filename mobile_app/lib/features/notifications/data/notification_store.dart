import 'dart:async';
import 'package:flutter/widgets.dart';
import '../../auth/data/user_model.dart';
import '../../messenger/data/messenger_socket_service.dart';
import 'notification_model.dart';
import 'notification_service.dart';

/// App-wide synchronized Notification Store.
///
/// Keeps notification list and unread count badge synchronized across all dashboards,
/// sockets, reconnects, reads, deletions, clear-all actions, and account switches.
class NotificationStore extends ChangeNotifier {
  NotificationStore._();
  static final NotificationStore instance = NotificationStore._();

  final NotificationService _service = NotificationService();
  final List<NotificationModel> _items = [];
  final List<StreamSubscription<dynamic>> _subs = [];
  String? _activeUserId;
  bool _listenersAttached = false;
  bool _refreshInFlight = false;

  List<NotificationModel> get items => List.unmodifiable(_items);
  int get unreadCount => _items.where((n) => !n.read).length;

  void init(UserModel user) {
    final uid = user.userId.isNotEmpty ? user.userId : user.id;
    if (uid.isEmpty) return;
    if (_activeUserId != null && _activeUserId != uid) {
      _items.clear();
      notifyListeners();
    }
    _activeUserId = uid;
    _attachSocketListeners();
    if (!WidgetsBinding.instance.runtimeType.toString().contains('Test')) {
      unawaited(refresh());
    }
  }

  void _attachSocketListeners() {
    if (_listenersAttached) return;
    _listenersAttached = true;
    final socket = MessengerSocketService.instance;
    _subs.addAll([
      socket.onNotification.listen(ingestRawNotification),
      socket.onNotificationRead.listen(applyReadEvent),
      socket.onNotificationReadAll.listen((_) => applyReadAllEvent()),
      socket.onNotificationClearAll.listen((_) => applyClearAllEvent()),
      socket.onNotificationChange.listen(applyChangeEvent),
      socket.onConnectionChange.listen((connected) {
        if (connected && _activeUserId != null) {
          unawaited(refresh());
        }
      }),
    ]);
  }

  Future<void> refresh() async {
    final uid = _activeUserId;
    if (uid == null || uid.isEmpty || _refreshInFlight) return;
    _refreshInFlight = true;
    try {
      final fetched = await _service.getUserNotifications(uid);
      setFromList(fetched);
    } finally {
      _refreshInFlight = false;
    }
  }

  void setFromList(List<NotificationModel> fetched) {
    final byId = <String, NotificationModel>{};
    for (final n in fetched) {
      final key = n.id.isNotEmpty ? n.id : (n.mongoId ?? '');
      if (key.isEmpty) continue;
      byId[key] = n;
    }
    _items
      ..clear()
      ..addAll(byId.values);
    notifyListeners();
  }

  void ingestRawNotification(Map<String, dynamic> raw) {
    final incoming = NotificationModel.fromJson(raw);
    if (incoming.id.isEmpty) return;
    _items.removeWhere(
      (n) => n.id == incoming.id || (incoming.mongoId != null && n.mongoId == incoming.mongoId),
    );
    _items.insert(0, incoming);
    notifyListeners();
  }

  void applyReadEvent(Map<String, dynamic> raw) {
    final targetId = (raw['id'] ?? raw['_id'] ?? '').toString();
    if (targetId.isEmpty) return;
    bool changed = false;
    for (final n in _items) {
      if ((n.id == targetId || n.mongoId == targetId) && !n.read) {
        n.read = true;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  void applyReadAllEvent() {
    bool changed = false;
    for (final n in _items) {
      if (!n.read) {
        n.read = true;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  void applyClearAllEvent() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
  }

  void applyChangeEvent(Map<String, dynamic> raw) {
    final targetId = (raw['id'] ?? raw['_id'] ?? '').toString();
    if (targetId.isEmpty) return;
    if (raw['deleted'] == true) {
      final before = _items.length;
      _items.removeWhere((n) => n.id == targetId || n.mongoId == targetId);
      if (_items.length != before) notifyListeners();
      return;
    }
    ingestRawNotification(raw);
  }

  Future<void> markAsRead(NotificationModel notif) async {
    if (!notif.read) {
      notif.read = true;
      for (final n in _items) {
        if (n.id == notif.id || (notif.mongoId != null && n.mongoId == notif.mongoId)) {
          n.read = true;
        }
      }
      notifyListeners();
    }
    await _service.markAsRead(notif.id, mongoId: notif.mongoId).catchError((_) => false);
  }

  Future<void> markAllAsRead([String? userIdOverride]) async {
    final uid = (userIdOverride != null && userIdOverride.isNotEmpty)
        ? userIdOverride
        : (_activeUserId ?? '');
    applyReadAllEvent();
    if (uid.isNotEmpty) {
      await _service.markAllAsRead(uid).catchError((_) => false);
    }
  }

  Future<void> deleteNotification(String id) async {
    if (id.isEmpty) return;
    _items.removeWhere((n) => n.id == id || n.mongoId == id);
    notifyListeners();
    await _service.deleteNotification(id).catchError((_) => false);
  }

  Future<void> clearAll([String? userIdOverride]) async {
    final uid = (userIdOverride != null && userIdOverride.isNotEmpty)
        ? userIdOverride
        : (_activeUserId ?? '');
    applyClearAllEvent();
    if (uid.isNotEmpty) {
      await _service.clearAll(uid).catchError((_) => false);
    }
  }

  void reset() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _listenersAttached = false;
    _activeUserId = null;
    _items.clear();
    notifyListeners();
  }
}
