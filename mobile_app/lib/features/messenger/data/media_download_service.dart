import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../app/app_config.dart';
import '../../../core/theme/celadon_colors.dart';

/// Service to download chat media (Images, Videos, Documents)
/// directly to the user device's Gallery / Download folders.
class MediaDownloadService {
  MediaDownloadService._();
  static final MediaDownloadService instance = MediaDownloadService._();

  Future<bool> downloadMedia({
    required BuildContext context,
    required String fileName,
    String? dataUri,
    String? url,
    Uint8List? rawBytes,
    bool isVideo = false,
    bool isImage = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // 1. Request permissions on mobile
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        await [Permission.storage].request();
      }

      // 2. Resolve Bytes
      Uint8List? bytes = rawBytes;
      if (bytes == null || bytes.isEmpty) {
        if (dataUri != null && dataUri.isNotEmpty) {
          final comma = dataUri.indexOf(',');
          final base64Str = comma != -1 ? dataUri.substring(comma + 1) : dataUri;
          bytes = base64Decode(base64Str);
        } else if (url != null && url.isNotEmpty) {
          if (url.startsWith('data:')) {
            final comma = url.indexOf(',');
            final base64Str = comma != -1 ? url.substring(comma + 1) : url;
            bytes = base64Decode(base64Str);
          } else {
            final resolved = AppConfig.resolveMediaUrl(url);
            final response = await http.get(Uri.parse(resolved)).timeout(const Duration(seconds: 15));
            if (response.statusCode == 200) {
              bytes = response.bodyBytes;
            }
          }
        }
      }

      if (bytes == null || bytes.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            backgroundColor: CeladonColors.error,
            content: Text('Unable to download: media data is empty'),
          ),
        );
        return false;
      }

      // 3. Resolve target directory for user device gallery / storage
      String targetDirPath;
      String destinationType;

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        if (isImage) {
          final picturesDir = Directory('/storage/emulated/0/Pictures/ReGen');
          if (!await picturesDir.exists()) {
            await picturesDir.create(recursive: true).catchError((_) => picturesDir);
          }
          if (await picturesDir.exists()) {
            targetDirPath = picturesDir.path;
            destinationType = 'Gallery (Pictures/ReGen)';
          } else {
            targetDirPath = '/storage/emulated/0/Download';
            destinationType = 'Downloads';
          }
        } else if (isVideo) {
          final moviesDir = Directory('/storage/emulated/0/Movies/ReGen');
          if (!await moviesDir.exists()) {
            await moviesDir.create(recursive: true).catchError((_) => moviesDir);
          }
          if (await moviesDir.exists()) {
            targetDirPath = moviesDir.path;
            destinationType = 'Gallery (Movies/ReGen)';
          } else {
            targetDirPath = '/storage/emulated/0/Download';
            destinationType = 'Downloads';
          }
        } else {
          final downloadDir = Directory('/storage/emulated/0/Download');
          if (await downloadDir.exists()) {
            targetDirPath = downloadDir.path;
            destinationType = 'Downloads';
          } else {
            final ext = await getExternalStorageDirectory();
            targetDirPath = ext?.path ?? (await getApplicationDocumentsDirectory()).path;
            destinationType = 'Device Storage';
          }
        }
      } else {
        final docDir = await getApplicationDocumentsDirectory();
        targetDirPath = docDir.path;
        destinationType = 'Device Documents';
      }

      // 4. Clean file name and save
      final cleanName = fileName.replaceAll(RegExp(r'[^\w\.\-]'), '_');
      final finalPath = '$targetDirPath/$cleanName';
      final file = File(finalPath);
      await file.writeAsBytes(bytes);

      messenger.showSnackBar(
        SnackBar(
          backgroundColor: CeladonColors.primary,
          duration: const Duration(seconds: 4),
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Saved to $destinationType: $cleanName',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
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
    }
  }
}
