import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import '../../../core/theme/celadon_colors.dart';
import '../data/messenger_model.dart';

enum MediaAttachKind { photo, video, document }

class PickedMediaAttachment {
  final String name;
  final String mimeType;
  final Uint8List bytes;
  final MediaAttachKind kind;
  final String caption;

  const PickedMediaAttachment({
    required this.name,
    required this.mimeType,
    required this.bytes,
    required this.kind,
    this.caption = '',
  });

  int get sizeBytes => bytes.length;

  String get dataUri => 'data:$mimeType;base64,${base64Encode(bytes)}';

  String get defaultMessageText {
    if (caption.trim().isNotEmpty) return caption.trim();
    switch (kind) {
      case MediaAttachKind.video:
        return '🎥 Video message';
      case MediaAttachKind.photo:
        return '📷 Photo';
      case MediaAttachKind.document:
        return '📎 $name';
    }
  }

  Map<String, dynamic> toBackendAttachment() {
    final uri = dataUri;
    return {
      'name': name,
      'type': mimeType,
      'size': sizeBytes,
      'data': uri,
      'path': uri,
    };
  }
}

/// Helper utility to record video or pick local photo / video / document
/// and confirm with an optional caption before sending to ReGen backend.
class MessengerMediaPicker {
  static final ImagePicker _picker = ImagePicker();
  static const int _maxVideoBytes = 20 * 1024 * 1024; // 20 MB (fits 50MB base64 JSON limit)
  static const int _maxFileBytes = 10 * 1024 * 1024; // 10 MB

  static String _mimeFromFilename(String name, MediaAttachKind fallbackKind) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.txt')) return 'text/plain';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.ppt')) return 'application/vnd.ms-powerpoint';
    if (lower.endsWith('.pptx')) {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
    if (lower.endsWith('.zip')) return 'application/zip';

    switch (fallbackKind) {
      case MediaAttachKind.photo:
        return 'image/jpeg';
      case MediaAttachKind.video:
        return 'video/mp4';
      case MediaAttachKind.document:
        return 'application/octet-stream';
    }
  }

  static Future<bool> _ensureCameraAndMicPermissions(BuildContext context) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return true;
    }
    final cam = await Permission.camera.request();
    final mic = await Permission.microphone.request();
    if (!cam.isGranted || !mic.isGranted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: CeladonColors.error,
            content: Text('Camera and microphone permissions are required to record video.'),
          ),
        );
      }
      return false;
    }
    return true;
  }

  static void _showError(BuildContext context, String msg) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: CeladonColors.error, content: Text(msg)),
    );
  }

  /// Opens camera to record video (Android, iOS & Web) so tapping
  /// the camera icon ALWAYS opens the camera immediately instead of documents.
  static Future<PickedMediaAttachment?> recordVideo(BuildContext context) async {
    if (!await _ensureCameraAndMicPermissions(context)) return null;
    if (!context.mounted) return null;

    if (kIsWeb) {
      return showDialog<PickedMediaAttachment>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const LiveVideoRecorderDialog(),
      );
    }

    try {
      final XFile? file = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 2),
      );
      if (file == null || !context.mounted) return null;

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        if (context.mounted) {
          _showError(context, 'Recorded video was empty. Please try again.');
        }
        return null;
      }
      if (bytes.length > _maxVideoBytes) {
        if (context.mounted) {
          _showError(context, 'Video exceeds 20 MB limit. Please record a shorter clip.');
        }
        return null;
      }

      final name = file.name.isNotEmpty
          ? file.name
          : 'video-${DateTime.now().millisecondsSinceEpoch}.mp4';
      final mime = _mimeFromFilename(name, MediaAttachKind.video);

      if (!context.mounted) return null;
      return await _showPreviewConfirmSheet(
        context,
        PickedMediaAttachment(
          name: name,
          mimeType: mime,
          bytes: bytes,
          kind: MediaAttachKind.video,
        ),
      );
    } catch (e) {
      if (context.mounted) {
        // Fallback to in-app dialog if native camera pick fails
        return showDialog<PickedMediaAttachment>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const LiveVideoRecorderDialog(),
        );
      }
      return null;
    }
  }

  /// Pick a photo from local gallery (or camera).
  static Future<PickedMediaAttachment?> pickPhoto(
    BuildContext context, {
    ImageSource source = ImageSource.gallery,
  }) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (file == null || !context.mounted) return null;

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      if (bytes.length > _maxFileBytes) {
        if (context.mounted) _showError(context, 'Photo exceeds 10 MB limit.');
        return null;
      }
      final name = file.name.isNotEmpty
          ? file.name
          : 'photo-${DateTime.now().millisecondsSinceEpoch}.jpg';
      final mime = _mimeFromFilename(name, MediaAttachKind.photo);

      if (!context.mounted) return null;
      return await _showPreviewConfirmSheet(
        context,
        PickedMediaAttachment(
          name: name,
          mimeType: mime,
          bytes: bytes,
          kind: MediaAttachKind.photo,
        ),
      );
    } catch (e) {
      if (context.mounted) _showError(context, 'Could not pick photo: $e');
      return null;
    }
  }

  /// Pick a video from local device storage/gallery.
  static Future<PickedMediaAttachment?> pickVideo(BuildContext context) async {
    try {
      final XFile? file = await _picker.pickVideo(source: ImageSource.gallery);
      if (file == null || !context.mounted) return null;

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      if (bytes.length > _maxVideoBytes) {
        if (context.mounted) _showError(context, 'Video exceeds 20 MB limit.');
        return null;
      }
      final rawName = file.name.isNotEmpty
          ? file.name
          : 'video-${DateTime.now().millisecondsSinceEpoch}.mp4';
      final name = rawName.toLowerCase().contains('video') ? rawName : 'video-$rawName';
      final mime = _mimeFromFilename(name, MediaAttachKind.video);

      if (!context.mounted) return null;
      return await _showPreviewConfirmSheet(
        context,
        PickedMediaAttachment(
          name: name,
          mimeType: mime,
          bytes: bytes,
          kind: MediaAttachKind.video,
        ),
      );
    } catch (e) {
      if (context.mounted) _showError(context, 'Could not pick video: $e');
      return null;
    }
  }

  /// Pick a local document (PDF, DOC, DOCX, XLS, XLSX, PPT, TXT, CSV, ZIP, etc.).
  static Future<PickedMediaAttachment?> pickDocument(BuildContext context) async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'pdf',
          'doc',
          'docx',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
          'txt',
          'csv',
          'zip',
          'rar',
          'png',
          'jpg',
          'jpeg',
        ],
      );
      if (files.isEmpty || !context.mounted) return null;

      final picked = files.first;
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty) return null;
      if (bytes.length > _maxFileBytes) {
        if (context.mounted) _showError(context, 'Document exceeds 10 MB limit.');
        return null;
      }

      final name = picked.name.isNotEmpty
          ? picked.name
          : 'document-${DateTime.now().millisecondsSinceEpoch}.pdf';
      final isImg = RegExp(r'\.(png|jpe?g|gif|webp)$', caseSensitive: false).hasMatch(name);
      final kind = isImg ? MediaAttachKind.photo : MediaAttachKind.document;
      final mime = _mimeFromFilename(name, kind);

      if (!context.mounted) return null;
      return await _showPreviewConfirmSheet(
        context,
        PickedMediaAttachment(
          name: name,
          mimeType: mime,
          bytes: bytes,
          kind: kind,
        ),
      );
    } catch (e) {
      if (context.mounted) _showError(context, 'Could not pick document: $e');
      return null;
    }
  }

  /// Opens the sleek Attachment Bottom Sheet (Record Video, Photo, Video, Document).
  static Future<PickedMediaAttachment?> showAttachPickerSheet(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: CeladonColors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Share Media & Files',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: CeladonColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _attachTile(
                    icon: Icons.photo_library_rounded,
                    label: 'Photo',
                    color: const Color(0xFF1B5E4B),
                    onTap: () => Navigator.pop(ctx, 'photo'),
                  ),
                  _attachTile(
                    icon: Icons.video_library_rounded,
                    label: 'Video',
                    color: const Color(0xFF7C3AED),
                    onTap: () => Navigator.pop(ctx, 'video'),
                  ),
                  _attachTile(
                    icon: Icons.description_rounded,
                    label: 'Document',
                    color: const Color(0xFF2563EB),
                    onTap: () => Navigator.pop(ctx, 'document'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (choice == null || !context.mounted) return null;
    switch (choice) {
      case 'photo':
        return pickPhoto(context);
      case 'video':
        return pickVideo(context);
      case 'document':
        return pickDocument(context);
      default:
        return null;
    }
  }

  static Widget _attachTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.25)),
              ),
              child: Icon(icon, color: color, size: 25),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: CeladonColors.textPrimary,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Shows preview + optional caption dialog before sending media/document.
  static Future<PickedMediaAttachment?> _showPreviewConfirmSheet(
    BuildContext context,
    PickedMediaAttachment attachment,
  ) {
    final captionCtrl = TextEditingController();
    return showModalBottomSheet<PickedMediaAttachment>(
      context: context,
      isScrollControlled: true,
      backgroundColor: CeladonColors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            18 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      attachment.kind == MediaAttachKind.photo
                          ? Icons.photo_rounded
                          : (attachment.kind == MediaAttachKind.video
                              ? Icons.videocam_rounded
                              : Icons.description_rounded),
                      color: CeladonColors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            attachment.kind == MediaAttachKind.video
                                ? 'Send Video'
                                : (attachment.kind == MediaAttachKind.photo
                                    ? 'Send Photo'
                                    : 'Send Document'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: CeladonColors.textPrimary,
                            ),
                          ),
                          Text(
                            '${attachment.name} • ${_formatBytes(attachment.sizeBytes)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                if (attachment.kind == MediaAttachKind.photo)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.memory(
                      attachment.bytes,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: CeladonColors.background,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: CeladonColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: CeladonColors.softMint,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            attachment.kind == MediaAttachKind.video
                                ? Icons.play_circle_fill_rounded
                                : Icons.insert_drive_file_rounded,
                            color: CeladonColors.primary,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                attachment.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                  color: CeladonColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${attachment.mimeType} • ${_formatBytes(attachment.sizeBytes)}',
                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 14),
                TextField(
                  controller: captionCtrl,
                  decoration: InputDecoration(
                    hintText: 'Add a caption (optional)...',
                    filled: true,
                    fillColor: CeladonColors.background,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CeladonColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => Navigator.pop(
                        ctx,
                        PickedMediaAttachment(
                          name: attachment.name,
                          mimeType: attachment.mimeType,
                          bytes: attachment.bytes,
                          kind: attachment.kind,
                          caption: captionCtrl.text.trim(),
                        ),
                      ),
                      icon: const Icon(Icons.send_rounded, size: 17),
                      label: const Text('Send', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Video Message Bubble rendered inside chats with tap-to-play VideoPlayerDialog.
class VideoMessageBubble extends StatelessWidget {
  final MessageAttachmentModel attachment;
  final bool isMine;

  const VideoMessageBubble({
    super.key,
    required this.attachment,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context) {
    final sizeLabel = attachment.size != null
        ? '${(attachment.size! / (1024 * 1024)).toStringAsFixed(1)} MB'
        : 'Video';

    return GestureDetector(
      onTap: () {
        if (attachment.resolvedUrl.isEmpty) return;
        showDialog(
          context: context,
          builder: (_) => _VideoPlayerDialog(
            videoUrl: attachment.resolvedUrl,
            title: attachment.name,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        width: 220,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMine ? Colors.black.withValues(alpha: 0.28) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    attachment.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap to play • $sizeLabel',
                    style: const TextStyle(color: Colors.white70, fontSize: 10.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoPlayerDialog extends StatefulWidget {
  final String videoUrl;
  final String title;

  const _VideoPlayerDialog({required this.videoUrl, required this.title});

  @override
  State<_VideoPlayerDialog> createState() => _VideoPlayerDialogState();
}

class _VideoPlayerDialogState extends State<_VideoPlayerDialog> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      _controller = ctrl;
      await ctrl.initialize();
      await ctrl.play();
      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Unable to play video: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxVideoHeight = MediaQuery.of(context).size.height * 0.62;
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              )
            else if (!_initialized || _controller == null)
              const Padding(
                padding: EdgeInsets.all(42),
                child: CircularProgressIndicator(color: Colors.white),
              )
            else ...[
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxVideoHeight),
                child: AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio > 0
                      ? _controller!.value.aspectRatio
                      : 16 / 9,
                  child: VideoPlayer(_controller!),
                ),
              ),
              VideoProgressIndicator(_controller!, allowScrubbing: true),
              IconButton(
                icon: Icon(
                  _controller!.value.isPlaying
                      ? Icons.pause_circle_filled_rounded
                      : Icons.play_circle_filled_rounded,
                  color: Colors.white,
                  size: 40,
                ),
                onPressed: () {
                  setState(() {
                    _controller!.value.isPlaying
                        ? _controller!.pause()
                        : _controller!.play();
                  });
                },
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Document Attachment Card rendered inside chat bubbles.
class DocumentAttachmentCard extends StatelessWidget {
  final MessageAttachmentModel attachment;
  final bool isMine;

  const DocumentAttachmentCard({
    super.key,
    required this.attachment,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context) {
    final lower = attachment.name.toLowerCase();
    final Color badgeColor = lower.endsWith('.pdf')
        ? const Color(0xFFDC2626)
        : (lower.endsWith('.xls') || lower.endsWith('.xlsx') || lower.endsWith('.csv')
            ? const Color(0xFF16A34A)
            : (lower.endsWith('.doc') || lower.endsWith('.docx')
                ? const Color(0xFF2563EB)
                : CeladonColors.primary));
    final sizeText = attachment.size != null
        ? (attachment.size! >= 1024 * 1024
            ? '${(attachment.size! / (1024 * 1024)).toStringAsFixed(1)} MB'
            : '${(attachment.size! / 1024).toStringAsFixed(1)} KB')
        : 'Document';

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isMine
            ? Colors.white.withValues(alpha: 0.14)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isMine ? Colors.white.withValues(alpha: 0.2) : badgeColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              Icons.description_rounded,
              color: isMine ? Colors.white : badgeColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: isMine ? Colors.white : CeladonColors.textPrimary,
                  ),
                ),
                Text(
                  sizeText,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isMine ? Colors.white70 : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen zoomable photo preview dialog when tapping an image in chat.
class FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;

  const FullScreenImageViewer({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              child: Image.network(imageUrl, fit: BoxFit.contain),
            ),
          ),
          Positioned(
            top: 36,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}



/// Live In-App Camera Video Recorder (Web / Chrome, Android & iOS)
///
/// Opens the live camera immediately inside Messenger (never opening Documents/File Explorer),
/// lets the user record themselves with live preview + timer + camera flip, preview the recorded
/// clip, add an optional caption, and send directly to the chat.
class LiveVideoRecorderDialog extends StatefulWidget {
  const LiveVideoRecorderDialog({super.key});

  @override
  State<LiveVideoRecorderDialog> createState() => _LiveVideoRecorderDialogState();
}

class _LiveVideoRecorderDialogState extends State<LiveVideoRecorderDialog> {
  static const int _maxVideoBytes = 20 * 1024 * 1024;

  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final TextEditingController _captionController = TextEditingController();

  MediaStream? _stream;
  MediaRecorder? _mediaRecorder;
  VideoPlayerController? _previewController;

  bool _cameraReady = false;
  bool _isRecording = false;
  bool _isFinalizing = false;
  bool _isFrontCamera = true;
  int _recordSeconds = 0;
  Timer? _timer;
  String? _errorText;
  String? _nativeOutputPath;

  Uint8List? _recordedBytes;
  String? _recordedName;
  String? _recordedMime;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stopCameraStream();
    _previewController?.dispose();
    _localRenderer.dispose();
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _stopCameraStream() async {
    try {
      _localRenderer.srcObject = null;
      _stream?.getTracks().forEach((t) => t.stop());
      await _stream?.dispose();
    } catch (_) {}
    _stream = null;
  }

  Future<void> _initCamera() async {
    setState(() {
      _errorText = null;
      _cameraReady = false;
    });
    try {
      await _localRenderer.initialize();
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {
          'facingMode': _isFrontCamera ? 'user' : 'environment',
          'width': {'ideal': 640},
          'height': {'ideal': 480},
        },
      });
      _stream = stream;
      _localRenderer.srcObject = stream;
      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorText = 'Could not open camera: $e';
          _cameraReady = false;
        });
      }
    }
  }

  Future<void> _flipCamera() async {
    if (_stream == null || _isRecording) return;
    final videoTracks = _stream!.getVideoTracks();
    if (videoTracks.isEmpty) return;
    try {
      await Helper.switchCamera(videoTracks.first);
      if (mounted) setState(() => _isFrontCamera = !_isFrontCamera);
    } catch (_) {}
  }

  Future<void> _startRecording() async {
    if (_stream == null || _isRecording) return;
    setState(() => _errorText = null);

    try {
      final recorder = MediaRecorder();
      _mediaRecorder = recorder;

      if (kIsWeb) {
        recorder.startWeb(_stream!, mimeType: 'video/webm');
      } else {
        final dir = await getTemporaryDirectory();
        final outPath = '${dir.path}/regen_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
        _nativeOutputPath = outPath;
        final videoTracks = _stream!.getVideoTracks();
        if (videoTracks.isEmpty) throw Exception('No camera video track available');
        await recorder.start(
          outPath,
          videoTrack: videoTracks.first,
          audioChannel: RecorderAudioChannel.INPUT,
        );
      }

      _recordSeconds = 0;
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _recordSeconds++);
        if (_recordSeconds >= 120) {
          _stopRecording();
        }
      });

      if (mounted) setState(() => _isRecording = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRecording = false;
          _errorText = 'Recording failed to start: $e';
        });
      }
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording || _mediaRecorder == null) return;
    _timer?.cancel();
    setState(() {
      _isRecording = false;
      _isFinalizing = true;
    });

    try {
      final stopResult = await _mediaRecorder!.stop();
      _mediaRecorder = null;

      Uint8List bytes;
      String mime;
      String fileName;
      VideoPlayerController? previewCtrl;

      if (kIsWeb) {
        final blobUrl = stopResult?.toString() ?? '';
        if (blobUrl.isEmpty) throw Exception('Empty recorded video');
        final resp = await http.get(Uri.parse(blobUrl));
        if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) {
          throw Exception('Could not read recorded video blob');
        }
        bytes = resp.bodyBytes;
        mime = 'video/webm';
        fileName = 'video-${DateTime.now().millisecondsSinceEpoch}.webm';
        previewCtrl = VideoPlayerController.networkUrl(Uri.parse(blobUrl));
      } else {
        final path = _nativeOutputPath ?? stopResult?.toString() ?? '';
        if (path.isEmpty) throw Exception('Recorded video path missing');
        final file = File(path);
        int flushTries = 0;
        while (flushTries < 15 && (!await file.exists() || await file.length() == 0)) {
          await Future.delayed(const Duration(milliseconds: 100));
          flushTries++;
        }
        if (!await file.exists()) throw Exception('Recorded video file not found');
        bytes = await file.readAsBytes();
        mime = 'video/mp4';
        fileName = 'video-${DateTime.now().millisecondsSinceEpoch}.mp4';
        previewCtrl = VideoPlayerController.file(file);
      }

      if (bytes.isEmpty) throw Exception('Recorded video was empty');
      if (bytes.length > _maxVideoBytes) {
        throw Exception('Recorded video exceeds 20 MB limit. Please record a shorter clip.');
      }

      await _stopCameraStream();

      try {
        await previewCtrl.initialize();
        await previewCtrl.setLooping(true);
        await previewCtrl.play();
      } catch (_) {
        previewCtrl = null;
      }

      if (mounted) {
        setState(() {
          _recordedBytes = bytes;
          _recordedMime = mime;
          _recordedName = fileName;
          _previewController = previewCtrl;
          _isFinalizing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isFinalizing = false;
          _errorText = 'Could not finish recording: $e';
        });
      }
    }
  }

  Future<void> _reRecord() async {
    await _previewController?.dispose();
    _previewController = null;
    setState(() {
      _recordedBytes = null;
      _recordedName = null;
      _recordedMime = null;
      _recordSeconds = 0;
      _errorText = null;
    });
    await _initCamera();
  }

  void _sendRecordedVideo() {
    if (_recordedBytes == null || _recordedName == null || _recordedMime == null) return;
    Navigator.pop(
      context,
      PickedMediaAttachment(
        name: _recordedName!,
        mimeType: _recordedMime!,
        bytes: _recordedBytes!,
        kind: MediaAttachKind.video,
        caption: _captionController.text.trim(),
      ),
    );
  }

  String _fmt(int secs) {
    final m = secs ~/ 60;
    final s = secs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final hasRecorded = _recordedBytes != null;

    return Dialog(
      backgroundColor: const Color(0xFF0E1B17),
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top bar
              Row(
                children: [
                  const Icon(Icons.videocam_rounded, color: Color(0xFF6EE7B7), size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasRecorded ? 'Preview & Send Video' : 'Record Video Message',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (!hasRecorded && !kIsWeb && _cameraReady && !_isRecording)
                    IconButton(
                      tooltip: 'Switch Camera',
                      icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white70, size: 21),
                      onPressed: _flipCamera,
                    ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Live Camera / Recorded Video Viewport
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Container(
                    color: Colors.black,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (hasRecorded && _previewController != null)
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _previewController!.value.isPlaying
                                    ? _previewController!.pause()
                                    : _previewController!.play();
                              });
                            },
                            child: VideoPlayer(_previewController!),
                          )
                        else if (hasRecorded)
                          const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 46),
                                SizedBox(height: 8),
                                Text(
                                  'Video Recorded & Ready to Send',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          )
                        else if (_cameraReady)
                          RTCVideoView(
                            _localRenderer,
                            mirror: _isFrontCamera,
                            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                          )
                        else if (_errorText != null)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                _errorText!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                              ),
                            ),
                          )
                        else
                          const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(color: Color(0xFF6EE7B7)),
                                SizedBox(height: 10),
                                Text(
                                  'Opening camera...',
                                  style: TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                              ],
                            ),
                          ),

                        // Recording timer pill
                        if (_isRecording)
                          Positioned(
                            top: 12,
                            left: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: CeladonColors.error,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.fiber_manual_record, color: Colors.white, size: 11),
                                  const SizedBox(width: 5),
                                  Text(
                                    'REC ${_fmt(_recordSeconds)}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        if (_isFinalizing)
                          Container(
                            color: Colors.black54,
                            child: const Center(
                              child: CircularProgressIndicator(color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              if (_errorText != null && _cameraReady)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    _errorText!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),

              // Controls: Record/Stop vs Preview Caption + Send
              if (!hasRecorded)
                Center(
                  child: GestureDetector(
                    onTap: (!_cameraReady || _isFinalizing)
                        ? null
                        : (_isRecording ? _stopRecording : _startRecording),
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3.5),
                      ),
                      padding: const EdgeInsets.all(5),
                      child: Container(
                        decoration: BoxDecoration(
                          color: CeladonColors.error,
                          borderRadius: BorderRadius.circular(_isRecording ? 10 : 99),
                        ),
                        child: Icon(
                          _isRecording ? Icons.stop_rounded : Icons.videocam_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                )
              else ...[
                TextField(
                  controller: _captionController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Add a caption (optional)...',
                    hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                    filled: true,
                    fillColor: Colors.white10,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _reRecord,
                      icon: const Icon(Icons.replay_rounded, size: 17),
                      label: const Text('Re-record'),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CeladonColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _sendRecordedVideo,
                      icon: const Icon(Icons.send_rounded, size: 17),
                      label: const Text('Send Video', style: TextStyle(fontWeight: FontWeight.w800)),
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
