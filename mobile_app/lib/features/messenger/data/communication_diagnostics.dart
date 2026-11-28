import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted notification preferences respected across foreground, local,
/// and FCM notifications + ringtones.
class NotificationPreferences {
  NotificationPreferences._();
  static final NotificationPreferences instance = NotificationPreferences._();

  static const String _prefPushKey = 'regen_notif_push_enabled';
  static const String _prefSoundKey = 'regen_notif_sound_enabled';
  static const String _prefTaskRemindersKey = 'regen_notif_task_reminders';
  static const String _prefEmailAlertsKey = 'regen_notif_email_alerts';

  bool _loaded = false;
  bool _pushEnabled = true;
  bool _soundEnabled = true;
  bool _taskRemindersEnabled = true;
  bool _emailAlertsEnabled = true;

  bool get isPushEnabled => _pushEnabled;
  bool get isSoundEnabled => _soundEnabled;
  bool get isTaskRemindersEnabled => _taskRemindersEnabled;
  bool get isEmailAlertsEnabled => _emailAlertsEnabled;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _pushEnabled = prefs.getBool(_prefPushKey) ?? true;
      _soundEnabled = prefs.getBool(_prefSoundKey) ?? true;
      _taskRemindersEnabled = prefs.getBool(_prefTaskRemindersKey) ?? true;
      _emailAlertsEnabled = prefs.getBool(_prefEmailAlertsKey) ?? true;
      _loaded = true;
    } catch (_) {}
  }

  Future<void> setPushEnabled(bool val) async {
    _pushEnabled = val;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefPushKey, val);
    } catch (_) {}
  }

  Future<void> setSoundEnabled(bool val) async {
    _soundEnabled = val;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefSoundKey, val);
    } catch (_) {}
  }

  Future<void> setTaskRemindersEnabled(bool val) async {
    _taskRemindersEnabled = val;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefTaskRemindersKey, val);
    } catch (_) {}
  }

  Future<void> setEmailAlertsEnabled(bool val) async {
    _emailAlertsEnabled = val;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefEmailAlertsKey, val);
    } catch (_) {}
  }
}

/// Redacted structured communication & call diagnostic log buffer.
/// Never records JWT tokens, passwords, or private message contents.
class CommunicationDiagnostics {
  CommunicationDiagnostics._();
  static final CommunicationDiagnostics instance = CommunicationDiagnostics._();

  static const int _maxEvents = 200;
  static const Set<String> _sensitiveKeys = {
    'token',
    'password',
    'secret',
    'authorization',
    'offer',
    'answer',
    'sdp',
    'content',
    'decryptedcontent',
  };

  final ListQueue<Map<String, dynamic>> _events = ListQueue<Map<String, dynamic>>();

  List<Map<String, dynamic>> get recentEvents => _events.toList(growable: false);

  void log(String event, [Map<String, dynamic> meta = const {}]) {
    final sanitized = <String, dynamic>{};
    meta.forEach((k, v) {
      if (_sensitiveKeys.contains(k.toLowerCase())) {
        sanitized[k] = '[REDACTED]';
      } else {
        sanitized[k] = v;
      }
    });

    final entry = <String, dynamic>{
      'ts': DateTime.now().toIso8601String(),
      'event': event,
      ...sanitized,
    };

    _events.addFirst(entry);
    while (_events.length > _maxEvents) {
      _events.removeLast();
    }

    if (kDebugMode) {
      final details = sanitized.entries.map((e) => '${e.key}=${e.value}').join(' ');
      debugPrint('[ReGenComm] $event${details.isNotEmpty ? ' | $details' : ''}');
    }
  }

  void clear() => _events.clear();
}
