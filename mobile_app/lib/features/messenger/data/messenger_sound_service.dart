import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'communication_diagnostics.dart';

/// App-wide Audio & Ringtone Service for ReGen Messenger
///
/// Centralized ringtone & alert player using Android ringtone/notification
/// AudioContext so incoming calls ring cleanly while preventing duplicate
/// ringtone instances or timers.
class MessengerSoundService {
  MessengerSoundService._();
  static final MessengerSoundService instance = MessengerSoundService._();

  AudioPlayer? _ringtonePlayer;
  AudioPlayer? _effectsPlayer;

  bool _isRinging = false;
  String? _activeCallId;
  Timer? _ringtoneLoopTimer;

  static Uint8List? _cachedRingtoneWav;
  static Uint8List? _cachedMessagePingWav;
  static Uint8List? _cachedMissedCallWav;

  bool get isRinging => _isRinging;
  String? get activeRingtoneCallId => _activeCallId;

  AudioPlayer? _getRingtonePlayer() {
    if (WidgetsBinding.instance.runtimeType.toString().contains('Test')) return null;
    try {
      if (_ringtonePlayer == null) {
        final player = AudioPlayer();
        player.setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              isSpeakerphoneOn: true,
              stayAwake: true,
              contentType: AndroidContentType.sonification,
              usageType: AndroidUsageType.notificationRingtone,
              audioFocus: AndroidAudioFocus.gainTransient,
            ),
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.playback,
              options: const {AVAudioSessionOptions.mixWithOthers},
            ),
          ),
        );
        _ringtonePlayer = player;
      }
      return _ringtonePlayer;
    } catch (_) {
      return null;
    }
  }

  AudioPlayer? _getEffectsPlayer() {
    if (WidgetsBinding.instance.runtimeType.toString().contains('Test')) return null;
    try {
      if (_effectsPlayer == null) {
        final player = AudioPlayer();
        player.setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              isSpeakerphoneOn: false,
              stayAwake: false,
              contentType: AndroidContentType.sonification,
              usageType: AndroidUsageType.notificationEvent,
              audioFocus: AndroidAudioFocus.gainTransientMayDuck,
            ),
          ),
        );
        _effectsPlayer = player;
      }
      return _effectsPlayer;
    } catch (_) {
      return null;
    }
  }

  /// Start playing the incoming call ringtone on repeat for [callId].
  /// Safe against duplicate calls: never starts two parallel ringtones.
  Future<void> startIncomingCallRingtone({String? callId}) async {
    await NotificationPreferences.instance.ensureLoaded();
    if (_isRinging) {
      if (callId != null && _activeCallId == callId) return;
      return;
    }

    _isRinging = true;
    _activeCallId = callId;
    CommunicationDiagnostics.instance.log('ringtone:start', {'callId': callId ?? 'unknown'});

    try {
      final player = _getRingtonePlayer();
      if (player == null) return;
      await player.setReleaseMode(ReleaseMode.stop);
      final wav = _getRingtoneWav();

      await player.play(BytesSource(wav));

      _ringtoneLoopTimer?.cancel();
      _ringtoneLoopTimer = Timer.periodic(const Duration(milliseconds: 3400), (timer) async {
        if (!_isRinging) {
          timer.cancel();
          return;
        }
        try {
          await player.play(BytesSource(wav));
        } catch (_) {}
      });
    } catch (e) {
      CommunicationDiagnostics.instance.log('ringtone:error', {'error': e.toString()});
    }
  }

  /// Immediately stops any active call ringtone.
  Future<void> stopRingtone({String? reason}) async {
    final wasRinging = _isRinging;
    final prevCallId = _activeCallId;
    _isRinging = false;
    _activeCallId = null;
    _ringtoneLoopTimer?.cancel();
    _ringtoneLoopTimer = null;
    try {
      await _ringtonePlayer?.stop();
    } catch (_) {}
    if (wasRinging) {
      CommunicationDiagnostics.instance.log('ringtone:stop', {
        'callId': prevCallId ?? '',
        'reason': reason ?? 'stopped',
      });
    }
  }

  /// Play a crisp message chime while respecting sound preferences.
  Future<void> playMessageReceivedTone() async {
    await NotificationPreferences.instance.ensureLoaded();
    if (!NotificationPreferences.instance.isPushEnabled ||
        !NotificationPreferences.instance.isSoundEnabled) {
      return;
    }
    try {
      final player = _getEffectsPlayer();
      if (player == null) return;
      final wav = _getMessagePingWav();
      await player.play(BytesSource(wav));
    } catch (_) {}
  }

  /// Play a missed call chime while respecting sound preferences.
  Future<void> playMissedCallTone() async {
    await NotificationPreferences.instance.ensureLoaded();
    if (!NotificationPreferences.instance.isSoundEnabled) return;
    try {
      final player = _getEffectsPlayer();
      if (player == null) return;
      final wav = _getMissedCallWav();
      await player.play(BytesSource(wav));
    } catch (_) {}
  }

  void dispose() {
    stopRingtone(reason: 'dispose');
    try {
      _ringtonePlayer?.dispose();
      _effectsPlayer?.dispose();
    } catch (_) {}
    _ringtonePlayer = null;
    _effectsPlayer = null;
  }

  static Uint8List _getRingtoneWav() {
    if (_cachedRingtoneWav != null) return _cachedRingtoneWav!;
    const sampleRate = 22050;
    const durationSeconds = 2.2;
    const numSamples = (sampleRate * durationSeconds) ~/ 1;
    final pcm = Int16List(numSamples);

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final isBurst = (t >= 0.0 && t <= 0.8) || (t >= 1.0 && t <= 1.8);
      if (isBurst) {
        final s1 = sin(2 * pi * 440 * t);
        final s2 = sin(2 * pi * 480 * t);
        final envelope = min(1.0, (t % 1.0) * 10) * max(0.0, 1.0 - ((t % 1.0) - 0.7) * 10);
        pcm[i] = ((s1 + s2) * 0.45 * envelope * 32767).toInt().clamp(-32768, 32767);
      } else {
        pcm[i] = 0;
      }
    }

    _cachedRingtoneWav = _buildWavHeader(pcm, sampleRate);
    return _cachedRingtoneWav!;
  }

  static Uint8List _getMessagePingWav() {
    if (_cachedMessagePingWav != null) return _cachedMessagePingWav!;
    const sampleRate = 22050;
    const durationSeconds = 0.35;
    const numSamples = (sampleRate * durationSeconds) ~/ 1;
    final pcm = Int16List(numSamples);

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      double sampleVal;
      if (t < 0.12) {
        sampleVal = sin(2 * pi * 880 * t) * exp(-t * 22);
      } else {
        final t2 = t - 0.12;
        sampleVal = sin(2 * pi * 1320 * t2) * exp(-t2 * 18);
      }
      pcm[i] = (sampleVal * 0.85 * 32767).toInt().clamp(-32768, 32767);
    }

    _cachedMessagePingWav = _buildWavHeader(pcm, sampleRate);
    return _cachedMessagePingWav!;
  }

  static Uint8List _getMissedCallWav() {
    if (_cachedMissedCallWav != null) return _cachedMissedCallWav!;
    const sampleRate = 22050;
    const durationSeconds = 0.6;
    const numSamples = (sampleRate * durationSeconds) ~/ 1;
    final pcm = Int16List(numSamples);

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      double freq = 987.77;
      double localT = t;
      if (t >= 0.2 && t < 0.4) {
        freq = 783.99;
        localT = t - 0.2;
      } else if (t >= 0.4) {
        freq = 659.25;
        localT = t - 0.4;
      }
      pcm[i] = (sin(2 * pi * freq * localT) * exp(-localT * 12) * 0.75 * 32767).toInt().clamp(-32768, 32767);
    }

    _cachedMissedCallWav = _buildWavHeader(pcm, sampleRate);
    return _cachedMissedCallWav!;
  }

  static Uint8List _buildWavHeader(Int16List pcmSamples, int sampleRate) {
    final byteDataSize = pcmSamples.length * 2;
    final totalSize = 44 + byteDataSize;
    final buffer = Uint8List(totalSize);
    final view = ByteData.view(buffer.buffer);

    buffer.setRange(0, 4, 'RIFF'.codeUnits);
    view.setUint32(4, totalSize - 8, Endian.little);
    buffer.setRange(8, 12, 'WAVE'.codeUnits);
    buffer.setRange(12, 16, 'fmt '.codeUnits);
    view.setUint32(16, 16, Endian.little);
    view.setUint16(20, 1, Endian.little);
    view.setUint16(22, 1, Endian.little);
    view.setUint32(24, sampleRate, Endian.little);
    view.setUint32(28, sampleRate * 2, Endian.little);
    view.setUint16(32, 2, Endian.little);
    view.setUint16(34, 16, Endian.little);
    buffer.setRange(36, 40, 'data'.codeUnits);
    view.setUint32(40, byteDataSize, Endian.little);

    final pcmBytes = Uint8List.view(pcmSamples.buffer);
    buffer.setRange(44, totalSize, pcmBytes);
    return buffer;
  }
}
