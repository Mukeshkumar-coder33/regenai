import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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

  /// Record a video using the device camera and show caption preview before sending.
  static Future<PickedMediaAttachment?> recordVideo(BuildContext context) async {
    if (!await _ensureCameraAndMicPermissions(context)) return null;
    try {
      final XFile? recorded = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 2),
      );
      if (recorded == null || !context.mounted) return null;

      final bytes = await recorded.readAsBytes();
      if (bytes.isEmpty) {
        if (context.mounted) _showError(context, 'Recorded video was empty.');
        return null;
      }
      if (bytes.length > _maxVideoBytes) {
        if (context.mounted) _showError(context, 'Video exceeds 20 MB limit. Record a shorter clip.');
        return null;
      }
      final rawName = recorded.name.isNotEmpty
          ? recorded.name
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
      if (context.mounted) _showError(context, 'Could not record video: $e');
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
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _attachTile(
                    icon: Icons.videocam_rounded,
                    label: 'Record\nVideo',
                    color: const Color(0xFFDC2626),
                    onTap: () => Navigator.pop(ctx, 'record_video'),
                  ),
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
      case 'record_video':
        return recordVideo(context);
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
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
            AspectRatio(
              aspectRatio: _controller!.value.aspectRatio > 0
                  ? _controller!.value.aspectRatio
                  : 16 / 9,
              child: VideoPlayer(_controller!),
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

