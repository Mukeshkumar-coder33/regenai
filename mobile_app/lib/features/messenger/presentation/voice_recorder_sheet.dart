import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../../core/theme/celadon_colors.dart';

/// Result returned when the user completes a voice recording + optional transcription.
enum VoiceSendAction { sendVoice, sendText, editInChat, discard }

class VoiceCaptureResult {
  final VoiceSendAction action;
  final String? base64DataUri;
  final String? fileName;
  final String? mimeType;
  final int? fileSize;
  final int durationSeconds;
  final String transcript;

  const VoiceCaptureResult({
    required this.action,
    this.base64DataUri,
    this.fileName,
    this.mimeType,
    this.fileSize,
    this.durationSeconds = 0,
    this.transcript = '',
  });
}

/// Modal Bottom Sheet matching website `VoiceConfirmDialog.jsx`:
/// 1. Records native audio (AAC `.m4a` compatible with Android, iOS & web browsers)
///    while transcribing speech live via on-device `speech_to_text`.
/// 2. After stopping, lets the user preview the audio, edit the transcribed text,
///    and choose: **Send as Voice Note**, **Send as Text**, **Edit in Chat**, or **Discard**.
class VoiceRecorderSheet extends StatefulWidget {
  const VoiceRecorderSheet({super.key});

  static Future<VoiceCaptureResult?> show(BuildContext context) {
    return showModalBottomSheet<VoiceCaptureResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: CeladonColors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const VoiceRecorderSheet(),
    );
  }

  @override
  State<VoiceRecorderSheet> createState() => _VoiceRecorderSheetState();
}

class _VoiceRecorderSheetState extends State<VoiceRecorderSheet> {
  final AudioRecorder _recorder = AudioRecorder();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final AudioPlayer _previewPlayer = AudioPlayer();
  final TextEditingController _transcriptController = TextEditingController();

  bool _isRecording = false;
  bool _hasRecorded = false;
  bool _isPlayingPreview = false;
  int _durationSeconds = 0;
  Timer? _timer;
  String? _recordedFilePath;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _previewPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlayingPreview = false);
    });
    _startRecording();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    _speech.stop();
    _previewPlayer.dispose();
    _transcriptController.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        final mic = await Permission.microphone.request();
        if (!mic.isGranted) {
          if (mounted) {
            setState(() => _errorText = 'Microphone permission is required to record voice notes.');
          }
          return;
        }
      }

      if (!await _recorder.hasPermission()) {
        if (mounted) {
          setState(() => _errorText = 'Microphone access was denied.');
        }
        return;
      }

      final dir = await getTemporaryDirectory();
      final outPath = '${dir.path}/regen_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
          sampleRate: 44100,
        ),
        path: outPath,
      );

      // Start parallel speech-to-text transcription when supported on device
      try {
        final sttReady = await _speech.initialize();
        if (sttReady) {
          await _speech.listen(
            onResult: (res) {
              if (mounted && res.recognizedWords.isNotEmpty) {
                setState(() {
                  _transcriptController.text = res.recognizedWords;
                });
              }
            },
            listenOptions: stt.SpeechListenOptions(
              partialResults: true,
              listenMode: stt.ListenMode.dictation,
            ),
          );
        }
      } catch (_) {}

      _durationSeconds = 0;
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _durationSeconds++);
      });

      if (mounted) {
        setState(() {
          _isRecording = true;
          _hasRecorded = false;
          _errorText = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorText = 'Could not start recording: $e');
      }
    }
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    try {
      await _speech.stop();
    } catch (_) {}

    try {
      final path = await _recorder.stop();
      if (mounted) {
        setState(() {
          _isRecording = false;
          _hasRecorded = path != null && path.isNotEmpty;
          _recordedFilePath = path;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRecording = false;
          _errorText = 'Failed to finalize audio: $e';
        });
      }
    }
  }

  Future<void> _togglePreview() async {
    if (_recordedFilePath == null) return;
    if (_isPlayingPreview) {
      await _previewPlayer.pause();
      if (mounted) setState(() => _isPlayingPreview = false);
    } else {
      await _previewPlayer.play(DeviceFileSource(_recordedFilePath!));
      if (mounted) setState(() => _isPlayingPreview = true);
    }
  }

  Future<void> _finishWithVoice() async {
    if (_recordedFilePath == null) return;
    try {
      final file = File(_recordedFilePath!);
      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);
      final dataUri = 'data:audio/mp4;base64,$b64';
      if (!mounted) return;
      Navigator.pop(
        context,
        VoiceCaptureResult(
          action: VoiceSendAction.sendVoice,
          base64DataUri: dataUri,
          fileName: 'voice-${DateTime.now().millisecondsSinceEpoch}.m4a',
          mimeType: 'audio/mp4',
          fileSize: bytes.length,
          durationSeconds: _durationSeconds,
          transcript: _transcriptController.text.trim(),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _errorText = 'Failed to encode voice note: $e');
      }
    }
  }

  String _fmt(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final text = _transcriptController.text.trim();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 16, 18, 18 + bottomInset),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _isRecording
                          ? CeladonColors.error.withValues(alpha: 0.14)
                          : CeladonColors.softMint,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.mic_rounded,
                      color: _isRecording ? CeladonColors.error : CeladonColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isRecording ? 'Recording Voice Note...' : 'Voice Recording Ready',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: CeladonColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Duration: ${_fmt(_durationSeconds)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: CeladonColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(
                      context,
                      const VoiceCaptureResult(action: VoiceSendAction.discard),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              if (_errorText != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: CeladonColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _errorText!,
                    style: const TextStyle(color: CeladonColors.error, fontSize: 12.5),
                  ),
                ),

              if (_isRecording) ...[
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                  decoration: BoxDecoration(
                    color: CeladonColors.background,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: CeladonColors.border),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Speak clearly — recording audio & transcribing live',
                        style: TextStyle(fontSize: 12.5, color: CeladonColors.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CeladonColors.error,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _stopRecording,
                        icon: const Icon(Icons.stop_rounded),
                        label: Text('Stop Recording (${_fmt(_durationSeconds)})'),
                      ),
                    ],
                  ),
                ),
              ],

              if (_hasRecorded) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: CeladonColors.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: CeladonColors.border),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _isPlayingPreview
                              ? Icons.pause_circle_filled_rounded
                              : Icons.play_circle_filled_rounded,
                          color: CeladonColors.primary,
                          size: 36,
                        ),
                        onPressed: _togglePreview,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Audio Preview',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: CeladonColors.textPrimary,
                              ),
                            ),
                            Text(
                              'Length ${_fmt(_durationSeconds)} • AAC/M4A',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: CeladonColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Editable speech-to-text transcript box (parity with VoiceConfirmDialog)
              const Text(
                'Transcribed Text (Editable before sending)',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: CeladonColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _transcriptController,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Spoken words appear here. You can edit before sending...',
                  hintStyle: const TextStyle(fontSize: 12.5, color: CeladonColors.textSecondary),
                  filled: true,
                  fillColor: CeladonColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: CeladonColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: CeladonColors.border),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              if (!_isRecording)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(
                        context,
                        const VoiceCaptureResult(action: VoiceSendAction.discard),
                      ),
                      child: const Text('Discard', style: TextStyle(color: CeladonColors.error)),
                    ),
                    if (text.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => Navigator.pop(
                          context,
                          VoiceCaptureResult(
                            action: VoiceSendAction.editInChat,
                            transcript: text,
                            durationSeconds: _durationSeconds,
                          ),
                        ),
                        icon: const Icon(Icons.edit_rounded, size: 16),
                        label: const Text('Edit in Chat'),
                      ),
                    if (text.isNotEmpty)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CeladonColors.primaryDark,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(
                          context,
                          VoiceCaptureResult(
                            action: VoiceSendAction.sendText,
                            transcript: text,
                            durationSeconds: _durationSeconds,
                          ),
                        ),
                        icon: const Icon(Icons.send_rounded, size: 16),
                        label: const Text('Send Text'),
                      ),
                    if (_hasRecorded)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CeladonColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _finishWithVoice,
                        icon: const Icon(Icons.mic_rounded, size: 16),
                        label: const Text('Send Voice Note'),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline audio player widget rendered inside Team & Direct/Group voice message bubbles.
class VoiceMessagePlayer extends StatefulWidget {
  final String audioUrl;
  final bool isMine;
  final int? durationSeconds;

  const VoiceMessagePlayer({
    super.key,
    required this.audioUrl,
    required this.isMine,
    this.durationSeconds,
  });

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (widget.durationSeconds != null && widget.durationSeconds! > 0) {
      _duration = Duration(seconds: widget.durationSeconds!);
    }
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (widget.audioUrl.isEmpty) return;
    try {
      if (_isPlaying) {
        await _player.pause();
        if (mounted) setState(() => _isPlaying = false);
      } else {
        if (widget.audioUrl.startsWith('data:')) {
          final comma = widget.audioUrl.indexOf(',');
          if (comma > 0) {
            final bytes = base64Decode(widget.audioUrl.substring(comma + 1));
            await _player.play(BytesSource(bytes));
          }
        } else {
          await _player.play(UrlSource(widget.audioUrl));
        }
        if (mounted) setState(() => _isPlaying = true);
      }
    } catch (_) {
      if (mounted) setState(() => _isPlaying = false);
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.isMine ? Colors.white : CeladonColors.primary;
    final sub = widget.isMine ? Colors.white70 : CeladonColors.textSecondary;
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: widget.isMine
            ? Colors.white.withValues(alpha: 0.14)
            : CeladonColors.softMint.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _togglePlay,
            child: Icon(
              _isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
              color: fg,
              size: 32,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 118,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(4),
                  backgroundColor: fg.withValues(alpha: 0.25),
                  valueColor: AlwaysStoppedAnimation<Color>(fg),
                ),
                const SizedBox(height: 4),
                Text(
                  _isPlaying ? _fmt(_position) : _fmt(_duration),
                  style: TextStyle(fontSize: 10, color: sub, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

