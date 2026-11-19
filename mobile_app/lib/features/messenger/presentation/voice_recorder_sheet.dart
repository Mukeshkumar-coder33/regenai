import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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

/// Cross-platform (Android, iOS & Web) Voice Recorder + Editable Speech-to-Text Sheet:
/// - Keeps microphone exclusively on `AudioRecorder` during recording (prevents Android
///   audio-focus conflicts with `SpeechRecognizer`).
/// - Uses `AudioEncoder.aacLc` (`.m4a`) on mobile and `AudioEncoder.opus` (`.webm`) on Web.
/// - After stopping, lets the user preview audio, dictate/edit speech-to-text, and choose:
///   **Send Voice Note**, **Send Text**, **Edit in Chat**, or **Discard**.
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
  bool _isEncoding = false;
  bool _isDictatingTranscript = false;
  int _durationSeconds = 0;
  Timer? _timer;
  String? _recordedPath;
  String? _errorText;
  StreamSubscription<void>? _completeSub;

  @override
  void initState() {
    super.initState();
    _completeSub = _previewPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlayingPreview = false);
    });
    _startRecording();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _completeSub?.cancel();
    _recorder.dispose();
    _speech.stop();
    _previewPlayer.dispose();
    _transcriptController.dispose();
    super.dispose();
  }

  Future<bool> _ensureMicPermission() async {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        if (mounted) {
          setState(() => _errorText = 'Microphone permission is required. Please allow it in device settings.');
        }
        return false;
      }
    }
    return true;
  }

  Future<void> _startRecording() async {
    if (!await _ensureMicPermission()) return;

    try {
      final hasPerm = await _recorder.hasPermission();
      if (!hasPerm) {
        if (mounted) setState(() => _errorText = 'Microphone access was denied.');
        return;
      }

      if (kIsWeb) {
        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.opus,
            bitRate: 96000,
          ),
          path: '',
        );
      } else {
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
      }

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
      final path = await _recorder.stop();
      if (mounted) {
        setState(() {
          _isRecording = false;
          _hasRecorded = path != null && path.isNotEmpty;
          _recordedPath = path;
          if (!_hasRecorded) {
            _errorText = 'No audio was captured. Please tap Retry and speak clearly.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRecording = false;
          _errorText = 'Failed to finalize recording: $e';
        });
      }
    }
  }

  Future<void> _togglePreview() async {
    if (_recordedPath == null || _recordedPath!.isEmpty) return;
    try {
      if (_isPlayingPreview) {
        await _previewPlayer.pause();
        if (mounted) setState(() => _isPlayingPreview = false);
      } else {
        if (kIsWeb || _recordedPath!.startsWith('http') || _recordedPath!.startsWith('blob:')) {
          await _previewPlayer.play(UrlSource(_recordedPath!));
        } else {
          await _previewPlayer.play(DeviceFileSource(_recordedPath!));
        }
        if (mounted) setState(() => _isPlayingPreview = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPlayingPreview = false;
          _errorText = 'Preview playback error: $e';
        });
      }
    }
  }

  Future<void> _toggleTranscriptDictation() async {
    if (_isDictatingTranscript) {
      await _speech.stop();
      if (mounted) setState(() => _isDictatingTranscript = false);
      return;
    }

    if (!await _ensureMicPermission()) return;

    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' && mounted) {
            setState(() => _isDictatingTranscript = false);
          }
        },
        onError: (err) {
          if (mounted) {
            final msg = err.errorMsg.toLowerCase();
            if (msg.contains('permission') || msg.contains('not-allowed') || msg.contains('denied')) {
              setState(() {
                _isDictatingTranscript = false;
                _errorText = 'Microphone permission denied for speech-to-text.';
              });
            } else if (!msg.contains('timeout') && !msg.contains('no_match') && !msg.contains('no-speech')) {
              setState(() {
                _isDictatingTranscript = false;
                _errorText = 'Speech-to-text: ${err.errorMsg}';
              });
            }
          }
        },
      );
      if (!available) {
        if (mounted) {
          setState(() => _errorText = 'Speech recognition is unavailable on this device/browser.');
        }
        return;
      }

      final baseText = _transcriptController.text.trim();
      setState(() {
        _isDictatingTranscript = true;
        _errorText = null;
      });
      await _speech.listen(
        onResult: (res) {
          if (!mounted) return;
          final words = res.recognizedWords.trim();
          if (words.isEmpty) return;
          final combined = baseText.isEmpty ? words : '$baseText $words';
          setState(() {
            _transcriptController.text = combined;
            _transcriptController.selection = TextSelection.fromPosition(
              TextPosition(offset: combined.length),
            );
          });
        },
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: stt.ListenMode.dictation,
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDictatingTranscript = false;
          _errorText = 'Could not start speech-to-text: $e';
        });
      }
    }
  }

  Future<void> _finishWithVoice() async {
    if (_recordedPath == null || _recordedPath!.isEmpty || _isEncoding) return;
    setState(() {
      _isEncoding = true;
      _errorText = null;
    });
    try {
      Uint8List bytes;
      String mimeType;
      String ext;

      if (kIsWeb || _recordedPath!.startsWith('blob:') || _recordedPath!.startsWith('http')) {
        final resp = await http.get(Uri.parse(_recordedPath!));
        if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) {
          throw Exception('Empty audio blob');
        }
        bytes = resp.bodyBytes;
        mimeType = resp.headers['content-type']?.split(';').first.trim() ?? 'audio/webm';
        ext = mimeType.contains('mp4') ? 'm4a' : (mimeType.contains('ogg') ? 'ogg' : 'webm');
      } else {
        final file = File(_recordedPath!);
        bytes = await file.readAsBytes();
        if (bytes.isEmpty) throw Exception('Recorded audio file is empty');
        mimeType = 'audio/mp4';
        ext = 'm4a';
      }

      final b64 = base64Encode(bytes);
      final dataUri = 'data:$mimeType;base64,$b64';

      if (!mounted) return;
      Navigator.pop(
        context,
        VoiceCaptureResult(
          action: VoiceSendAction.sendVoice,
          base64DataUri: dataUri,
          fileName: 'voice-${DateTime.now().millisecondsSinceEpoch}.$ext',
          mimeType: mimeType,
          fileSize: bytes.length,
          durationSeconds: _durationSeconds > 0 ? _durationSeconds : 1,
          transcript: _transcriptController.text.trim(),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isEncoding = false;
          _errorText = 'Failed to prepare voice message: $e';
        });
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
                    width: 42,
                    height: 42,
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
                          _isRecording ? 'Recording Voice Note...' : 'Voice Message',
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
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _errorText!,
                          style: const TextStyle(color: CeladonColors.error, fontSize: 12.5),
                        ),
                      ),
                      if (!_isRecording && !_hasRecorded)
                        TextButton(
                          onPressed: _startRecording,
                          child: const Text('Retry'),
                        ),
                    ],
                  ),
                ),

              if (_isRecording)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  decoration: BoxDecoration(
                    color: CeladonColors.background,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: CeladonColors.border),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Recording high-quality voice note...',
                        style: TextStyle(fontSize: 13, color: CeladonColors.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CeladonColors.error,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _stopRecording,
                        icon: const Icon(Icons.stop_rounded),
                        label: Text('Stop Recording (${_fmt(_durationSeconds)})'),
                      ),
                    ],
                  ),
                ),

              if (_hasRecorded && !_isRecording) ...[
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
                          size: 38,
                        ),
                        onPressed: _togglePreview,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Voice Note Ready',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                color: CeladonColors.textPrimary,
                              ),
                            ),
                            Text(
                              'Length ${_fmt(_durationSeconds)} • Tap play to preview',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: CeladonColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: _startRecording,
                        child: const Text('Re-record'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Optional Voice-to-Text box (runs cleanly when mic is not held by AudioRecorder)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Voice-to-Text (Optional)',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: CeladonColors.textPrimary,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _toggleTranscriptDictation,
                      icon: Icon(
                        _isDictatingTranscript ? Icons.stop_circle_rounded : Icons.graphic_eq_rounded,
                        size: 16,
                        color: _isDictatingTranscript ? CeladonColors.error : CeladonColors.primary,
                      ),
                      label: Text(
                        _isDictatingTranscript ? 'Stop Dictating' : 'Dictate Text',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _isDictatingTranscript ? CeladonColors.error : CeladonColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                TextField(
                  controller: _transcriptController,
                  maxLines: 2,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Tap "Dictate Text" or type to send as text instead...',
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
                const SizedBox(height: 16),

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
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CeladonColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _isEncoding ? null : _finishWithVoice,
                      icon: _isEncoding
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.mic_rounded, size: 16),
                      label: Text(_isEncoding ? 'Sending...' : 'Send Voice Note'),
                    ),
                  ],
                ),
              ],
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
