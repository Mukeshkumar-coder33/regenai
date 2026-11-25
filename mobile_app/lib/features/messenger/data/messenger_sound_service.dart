import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// App-wide Audio & Ringtone Service for ReGen Messenger
///
/// Provides in-app ringtones (similar to WhatsApp incoming call tone)
/// and notification sounds (message ping, missed call chime).
/// Generates offline PCM audio buffers on-the-fly, requiring zero external
/// assets or network connectivity.
class MessengerSoundService {
  MessengerSoundService._();
  static final MessengerSoundService instance = MessengerSoundService._();

  AudioPlayer? _ringtonePlayer;
  AudioPlayer? _effectsPlayer;

  AudioPlayer? _getRingtonePlayer() {
    if (WidgetsBinding.instance.runtimeType.toString().contains('Test')) return null;
    try {
      _ringtonePlayer ??= AudioPlayer();
      return _ringtonePlayer;
    } catch (_) {
      return null;
    }
  }

  AudioPlayer? _getEffectsPlayer() {
    if (WidgetsBinding.instance.runtimeType.toString().contains('Test')) return null;
    try {
      _effectsPlayer ??= AudioPlayer();
      return _effectsPlayer;
    } catch (_) {
      return null;
    }
  }

  bool _isRinging = false;
  Timer? _ringtoneLoopTimer;

  static Uint8List? _cachedRingtoneWav;
  static Uint8List? _cachedMessagePingWav;
  static Uint8List? _cachedMissedCallWav;

  bool get isRinging => _isRinging;

  /// Start playing the incoming call ringtone on repeat.
  /// Stops automatically when [stopRingtone] is called.
  Future<void> startIncomingCallRingtone() async {
    if (_isRinging) return;
    _isRinging = true;

    try {
      final player = _getRingtonePlayer();
      if (player == null) return;
      await player.setReleaseMode(ReleaseMode.stop);
      final wav = _getRingtoneWav();

      // Play immediately
      await player.play(BytesSource(wav));

      // Loop cadence: play 2.2s burst followed by 1.2s silence (classic WhatsApp/phone cadence)
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
      debugPrint('[MessengerSoundService] startIncomingCallRingtone error: $e');
    }
  }

  /// Immediately stops any active call ringtone.
  /// MUST be called when attending, answering, declining, or cancelling calls.
  Future<void> stopRingtone() async {
    _isRinging = false;
    _ringtoneLoopTimer?.cancel();
    _ringtoneLoopTimer = null;
    try {
      await _ringtonePlayer?.stop();
    } catch (_) {}
  }

  /// Play a quick pleasant in-app WhatsApp-like message received chime (dual tone ding-dong).
  Future<void> playMessageReceivedTone() async {
    try {
      final player = _getEffectsPlayer();
      if (player == null) return;
      final wav = _getMessagePingWav();
      await player.play(BytesSource(wav));
    } catch (_) {}
  }

  /// Play a missed call alert sound.
  Future<void> playMissedCallTone() async {
    try {
      final player = _getEffectsPlayer();
      if (player == null) return;
      final wav = _getMissedCallWav();
      await player.play(BytesSource(wav));
    } catch (_) {}
  }

  void dispose() {
    stopRingtone();
    try {
      _ringtonePlayer?.dispose();
      _effectsPlayer?.dispose();
    } catch (_) {}
    _ringtonePlayer = null;
    _effectsPlayer = null;
  }

  // ─────────────────────────────────────────────────────────────
  // WAV PCM Audio Synthesis Helpers (Zero Assets Required)
  // ─────────────────────────────────────────────────────────────

  /// Synthesizes a pleasant dual-frequency phone ring cadence (440Hz + 480Hz)
  static Uint8List _getRingtoneWav() {
    if (_cachedRingtoneWav != null) return _cachedRingtoneWav!;

    const sampleRate = 22050;
    const durationSeconds = 2.2;
    const numSamples = (sampleRate * durationSeconds) ~/ 1;

    final pcm = Int16List(numSamples);

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      // 2 bursts: 0.0-0.8s on, 0.8-1.0s off, 1.0-1.8s on, 1.8-2.2s off
      final isBurst = (t >= 0.0 && t <= 0.8) || (t >= 1.0 && t <= 1.8);
      if (isBurst) {
        // Dual tone (standard US/WhatsApp phone ring frequencies: 440 Hz & 480 Hz)
        final s1 = sin(2 * pi * 440 * t);
        final s2 = sin(2 * pi * 480 * t);
        final envelope = min(1.0, (t % 1.0) * 10) * max(0.0, 1.0 - ((t % 1.0) - 0.7) * 10);
        final sample = ((s1 + s2) * 0.45 * envelope * 32767).toInt().clamp(-32768, 32767);
        pcm[i] = sample;
      } else {
        pcm[i] = 0;
      }
    }

    _cachedRingtoneWav = _buildWavHeader(pcm, sampleRate);
    return _cachedRingtoneWav!;
  }

  /// Synthesizes a crisp WhatsApp-style notification ding (two bright notes: 880Hz then 1320Hz)
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
        final env = exp(-t * 22);
        sampleVal = sin(2 * pi * 880 * t) * env;
      } else {
        final t2 = t - 0.12;
        final env = exp(-t2 * 18);
        sampleVal = sin(2 * pi * 1320 * t2) * env;
      }
      pcm[i] = (sampleVal * 0.85 * 32767).toInt().clamp(-32768, 32767);
    }

    _cachedMessagePingWav = _buildWavHeader(pcm, sampleRate);
    return _cachedMessagePingWav!;
  }

  /// Synthesizes a gentle missed-call alert chime (3 descending notes)
  static Uint8List _getMissedCallWav() {
    if (_cachedMissedCallWav != null) return _cachedMissedCallWav!;

    const sampleRate = 22050;
    const durationSeconds = 0.6;
    const numSamples = (sampleRate * durationSeconds) ~/ 1;

    final pcm = Int16List(numSamples);

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      double freq = 987.77; // B5
      double localT = t;
      if (t >= 0.2 && t < 0.4) {
        freq = 783.99; // G5
        localT = t - 0.2;
      } else if (t >= 0.4) {
        freq = 659.25; // E5
        localT = t - 0.4;
      }
      final env = exp(-localT * 12);
      final s = sin(2 * pi * freq * localT) * env;
      pcm[i] = (s * 0.75 * 32767).toInt().clamp(-32768, 32767);
    }

    _cachedMissedCallWav = _buildWavHeader(pcm, sampleRate);
    return _cachedMissedCallWav!;
  }

  /// Creates a standard 44-byte RIFF WAV header for 16-bit mono PCM data
  static Uint8List _buildWavHeader(Int16List pcmSamples, int sampleRate) {
    final byteDataSize = pcmSamples.length * 2;
    final totalSize = 44 + byteDataSize;
    final buffer = Uint8List(totalSize);
    final view = ByteData.view(buffer.buffer);

    // "RIFF"
    buffer.setRange(0, 4, 'RIFF'.codeUnits);
    view.setUint32(4, totalSize - 8, Endian.little);
    // "WAVE"
    buffer.setRange(8, 12, 'WAVE'.codeUnits);
    // "fmt "
    buffer.setRange(12, 16, 'fmt '.codeUnits);
    view.setUint32(16, 16, Endian.little); // Subchunk1Size
    view.setUint16(20, 1, Endian.little); // AudioFormat = 1 (PCM)
    view.setUint16(22, 1, Endian.little); // NumChannels = 1 (Mono)
    view.setUint32(24, sampleRate, Endian.little); // SampleRate
    view.setUint32(28, sampleRate * 2, Endian.little); // ByteRate
    view.setUint16(32, 2, Endian.little); // BlockAlign = 2
    view.setUint16(34, 16, Endian.little); // BitsPerSample = 16
    // "data"
    buffer.setRange(36, 40, 'data'.codeUnits);
    view.setUint32(40, byteDataSize, Endian.little);

    // Copy PCM bytes
    final pcmBytes = Uint8List.view(pcmSamples.buffer);
    buffer.setRange(44, totalSize, pcmBytes);

    return buffer;
  }
}
