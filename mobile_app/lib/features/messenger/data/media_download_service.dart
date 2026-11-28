import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../app/app_config.dart';
import '../../../core/storage/session_storage.dart';
import '../../../core/theme/celadon_colors.dart';

/// Result metadata returned after saving media to the user's device.
class SavedMediaResult {
  final String displayName;
  final String location;
  final String mimeType;
  final String? contentUri;
  final String? filePath;

  const SavedMediaResult({
    required this.displayName,
    required this.location,
    required this.mimeType,
    this.contentUri,
    this.filePath,
  });
}

/// Service to download chat media (Images, Videos, Documents) securely
/// using ReGen JWT auth and save them into user-accessible Gallery / Downloads folders.
class MediaDownloadService {
  MediaDownloadService._();
  static final MediaDownloadService instance = MediaDownloadService._();

  static const MethodChannel _channel =
      MethodChannel('com.mukeshkumar_coder33.regen_mobile/media_download');

  /// Tracks active download progress [0.0..1.0] keyed by media URL or filename.
  final ValueNotifier<Map<String, double>> progressMap =
      ValueNotifier<Map<String, double>>(<String, double>{});

  void _setProgress(String key, double? value) {
    final next = Map<String, double>.from(progressMap.value);
    if (value == null) {
      next.remove(key);
    } else {
      next[key] = value.clamp(0.0, 1.0);
    }
    progressMap.value = next;
  }

  /// Resolves an attachment path/URL into the authenticated ReGen download endpoint when hosted by ReGen.
  static String buildSecureDownloadUrl(String rawUrl) {
    final s = rawUrl.trim();
    if (s.isEmpty || s.startsWith('data:') || s.startsWith('blob:')) return s;

    final resolved = AppConfig.resolveMediaUrl(s);
    final uri = Uri.tryParse(resolved);
    if (uri != null && resolved.startsWith(AppConfig.activeBaseUrl)) {
      final segments = uri.pathSegments;
      if (segments.length >= 2 && segments[segments.length - 2] == 'assets') {
        final fname = segments.last;
        if (fname.startsWith('dm-') || fname.startsWith('msg-')) {
          return '${AppConfig.activeBaseUrl}/api/dm/media/${Uri.encodeComponent(fname)}?download=1';
        }
      }
    }
    return resolved;
  }

  static String inferMimeType(String fileName, {bool isImage = false, bool isVideo = false, String? explicitMime}) {
    if (explicitMime != null &&
        explicitMime.isNotEmpty &&
        explicitMime != 'application/octet-stream') {
      return explicitMime;
    }
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    if (lower.endsWith('.m4a')) return 'audio/mp4';
    if (lower.endsWith('.aac')) return 'audio/aac';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.pdf')) return 'application/pdf';
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
    if (lower.endsWith('.txt')) return 'text/plain';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.zip')) return 'application/zip';
    if (isImage) return 'image/jpeg';
    if (isVideo) return 'video/mp4';
    return 'application/octet-stream';
  }

  static String sanitizeSafeFilename(String rawName, {bool isImage = false, bool isVideo = false}) {
    final cleaned = rawName
        .trim()
        .replaceAll(RegExp(r'[^\w\.\-\(\) ]'), '_')
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'\.{2,}'), '.');
    if (cleaned.isEmpty) {
      if (isImage) return 'IMG_${DateTime.now().millisecondsSinceEpoch}.jpg';
      if (isVideo) return 'VID_${DateTime.now().millisecondsSinceEpoch}.mp4';
      return 'FILE_${DateTime.now().millisecondsSinceEpoch}';
    }
    if (!cleaned.contains('.')) {
      if (isImage) return '$cleaned.jpg';
      if (isVideo) return '$cleaned.mp4';
    }
    return cleaned;
  }

  Future<bool> openSavedFile(SavedMediaResult saved) async {
    if (kIsWeb) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final ok = await _channel.invokeMethod<bool>('openSavedFile', {
          'uri': saved.contentUri ?? '',
          'filePath': saved.filePath ?? '',
          'mimeType': saved.mimeType,
        });
        return ok == true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> downloadMedia({
    required BuildContext context,
    required String fileName,
    String? dataUri,
    String? url,
    Uint8List? rawBytes,
    String? mimeType,
    bool isVideo = false,
    bool isImage = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final progressKey = (url != null && url.isNotEmpty) ? url : fileName;
    final cleanName = sanitizeSafeFilename(fileName, isImage: isImage, isVideo: isVideo);
    final resolvedMime = inferMimeType(cleanName, isImage: isImage, isVideo: isVideo, explicitMime: mimeType);
    final kind = isImage ? 'image' : (isVideo ? 'video' : 'document');

    File? tempFile;
    http.Client? client;

    try {
      // Only request legacy WRITE_EXTERNAL_STORAGE on Android 9 (SDK <= 28).
      // Android 10+ uses Scoped Storage / MediaStore without requiring broad storage permissions.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        int sdkInt = 33;
        try {
          sdkInt = await _channel.invokeMethod<int>('getSdkInt') ?? 33;
        } catch (_) {}
        if (sdkInt <= 28) {
          final status = await Permission.storage.request();
          if (!status.isGranted) {
            messenger.showSnackBar(
              const SnackBar(
                backgroundColor: CeladonColors.error,
                content: Text('Storage permission is required to save files on this Android version.'),
              ),
            );
            return false;
          }
        }
      }

      _setProgress(progressKey, 0.05);
      final tempDir = await getTemporaryDirectory();
      tempFile = File('${tempDir.path}/dl_${DateTime.now().millisecondsSinceEpoch}_$cleanName');

      if (rawBytes != null && rawBytes.isNotEmpty) {
        await tempFile.writeAsBytes(rawBytes);
        _setProgress(progressKey, 0.9);
      } else if (dataUri != null && dataUri.isNotEmpty) {
        final comma = dataUri.indexOf(',');
        final base64Str = comma != -1 ? dataUri.substring(comma + 1) : dataUri;
        await tempFile.writeAsBytes(base64Decode(base64Str));
        _setProgress(progressKey, 0.9);
      } else if (url != null && url.isNotEmpty) {
        if (url.startsWith('data:')) {
          final comma = url.indexOf(',');
          final base64Str = comma != -1 ? url.substring(comma + 1) : url;
          await tempFile.writeAsBytes(base64Decode(base64Str));
          _setProgress(progressKey, 0.9);
        } else {
          final targetUrl = buildSecureDownloadUrl(url);
          final req = http.Request('GET', Uri.parse(targetUrl));
          if (targetUrl.startsWith(AppConfig.activeBaseUrl)) {
            final token = await SessionStorage.getToken();
            if (token != null && token.isNotEmpty) {
              req.headers['Authorization'] = 'Bearer $token';
            }
          }

          client = http.Client();
          final streamed = await client.send(req).timeout(const Duration(minutes: 5));

          if (streamed.statusCode == 401 || streamed.statusCode == 403) {
            messenger.showSnackBar(
              const SnackBar(
                backgroundColor: CeladonColors.error,
                content: Text('Unauthorized: you do not have permission to download this media.'),
              ),
            );
            return false;
          }
          if (streamed.statusCode != 200) {
            messenger.showSnackBar(
              SnackBar(
                backgroundColor: CeladonColors.error,
                content: Text('Download failed (HTTP ${streamed.statusCode}).'),
              ),
            );
            return false;
          }

          final totalBytes = streamed.contentLength ?? 0;
          int received = 0;
          final sink = tempFile.openWrite();
          try {
            await for (final chunk in streamed.stream.timeout(const Duration(minutes: 2))) {
              sink.add(chunk);
              received += chunk.length;
              if (totalBytes > 0) {
                _setProgress(progressKey, 0.1 + 0.8 * (received / totalBytes));
              }
            }
            await sink.flush();
          } finally {
            await sink.close();
          }
        }
      }

      if (!await tempFile.exists() || await tempFile.length() == 0) {
        messenger.showSnackBar(
          const SnackBar(
            backgroundColor: CeladonColors.error,
            content: Text('Unable to download: media file is empty.'),
          ),
        );
        return false;
      }

      SavedMediaResult savedResult;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final res = await _channel.invokeMapMethod<String, dynamic>('saveMediaFile', {
          'tempPath': tempFile.path,
          'fileName': cleanName,
          'mimeType': resolvedMime,
          'kind': kind,
        });
        savedResult = SavedMediaResult(
          displayName: (res?['displayName'] ?? cleanName).toString(),
          location: (res?['location'] ?? (isImage ? 'Gallery (Pictures/ReGen)' : isVideo ? 'Gallery (Movies/ReGen)' : 'Downloads/ReGen')).toString(),
          mimeType: (res?['mimeType'] ?? resolvedMime).toString(),
          contentUri: res?['uri']?.toString(),
          filePath: res?['filePath']?.toString(),
        );
      } else {
        final docDir = await getApplicationDocumentsDirectory();
        final saveDir = Directory('${docDir.path}/ReGen Downloads');
        if (!await saveDir.exists()) {
          await saveDir.create(recursive: true);
        }
        var dest = File('${saveDir.path}/$cleanName');
        if (await dest.exists()) {
          final dotIdx = cleanName.lastIndexOf('.');
          final stem = dotIdx > 0 ? cleanName.substring(0, dotIdx) : cleanName;
          final ext = dotIdx > 0 ? cleanName.substring(dotIdx) : '';
          int c = 1;
          while (await dest.exists()) {
            dest = File('${saveDir.path}/${stem}_($c)$ext');
            c++;
          }
        }
        await tempFile.copy(dest.path);
        savedResult = SavedMediaResult(
          displayName: dest.path.split(Platform.pathSeparator).last,
          location: 'Files (ReGen Downloads)',
          mimeType: resolvedMime,
          filePath: dest.path,
        );
      }

      _setProgress(progressKey, 1.0);
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: CeladonColors.primary,
          duration: const Duration(seconds: 5),
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Saved to ${savedResult.location}: ${savedResult.displayName}',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          action: (!kIsWeb &&
                  defaultTargetPlatform == TargetPlatform.android &&
                  ((savedResult.contentUri?.isNotEmpty ?? false) ||
                      (savedResult.filePath?.isNotEmpty ?? false)))
              ? SnackBarAction(
                  label: 'OPEN',
                  textColor: Colors.white,
                  onPressed: () {
                    openSavedFile(savedResult);
                  },
                )
              : null,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[MediaDownloadService] Download error: $e');
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: CeladonColors.error,
          content: Text('Failed to download media: $e'),
        ),
      );
      return false;
    } finally {
      _setProgress(progressKey, null);
      client?.close();
      try {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
  }
}
