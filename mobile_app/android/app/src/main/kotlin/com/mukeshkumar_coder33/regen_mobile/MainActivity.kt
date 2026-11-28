package com.mukeshkumar_coder33.regen_mobile

import android.content.ContentValues
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.OutputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val MEDIA_CHANNEL = "com.mukeshkumar_coder33.regen_mobile/media_download"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSdkInt" -> result.success(Build.VERSION.SDK_INT)
                    "saveMediaFile" -> {
                        val tempPath = call.argument<String>("tempPath")
                        val fileName = call.argument<String>("fileName") ?: "file"
                        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                        val kind = call.argument<String>("kind") ?: "document"
                        if (tempPath.isNullOrEmpty()) {
                            result.error("INVALID_ARGS", "Missing temporary file path", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val saved = saveToPublicMediaStore(File(tempPath), fileName, mimeType, kind)
                                runOnUiThread { result.success(saved) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("SAVE_FAILED", e.message ?: "Failed to save file", null)
                                }
                            }
                        }.start()
                    }
                    "openSavedFile" -> {
                        val uriStr = call.argument<String>("uri")
                        val filePath = call.argument<String>("filePath")
                        val mimeType = call.argument<String>("mimeType") ?: "*/*"
                        try {
                            val opened = openTargetFile(uriStr, filePath, mimeType)
                            result.success(opened)
                        } catch (e: Exception) {
                            result.error("OPEN_FAILED", e.message ?: "Cannot open file", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun saveToPublicMediaStore(
        sourceFile: File,
        fileName: String,
        mimeType: String,
        kind: String
    ): Map<String, String> {
        if (!sourceFile.exists() || sourceFile.length() <= 0L) {
            throw IllegalStateException("Downloaded file is empty or missing")
        }

        val subFolder = when (kind) {
            "image" -> Environment.DIRECTORY_PICTURES
            "video" -> Environment.DIRECTORY_MOVIES
            else -> Environment.DIRECTORY_DOWNLOADS
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val collectionUri: Uri = when (kind) {
                "image" -> MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                "video" -> MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                else -> MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            }

            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                put(MediaStore.MediaColumns.RELATIVE_PATH, "$subFolder/ReGen")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }

            val resolver = applicationContext.contentResolver
            val insertedUri = resolver.insert(collectionUri, values)
                ?: throw IllegalStateException("MediaStore failed to create destination entry")

            try {
                resolver.openOutputStream(insertedUri)?.use { out ->
                    copyStream(sourceFile, out)
                } ?: throw IllegalStateException("Failed to open MediaStore output stream")

                val doneValues = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                resolver.update(insertedUri, doneValues, null, null)
            } catch (e: Exception) {
                resolver.delete(insertedUri, null, null)
                throw e
            }

            return mapOf(
                "uri" to insertedUri.toString(),
                "displayName" to fileName,
                "location" to "$subFolder/ReGen",
                "mimeType" to mimeType
            )
        }

        // Android 9 (API 28) and earlier: write to public directory & trigger MediaScanner
        val publicBase = Environment.getExternalStoragePublicDirectory(subFolder)
        val targetDir = File(publicBase, "ReGen")
        if (!targetDir.exists()) targetDir.mkdirs()

        val destFile = resolveUniqueFile(targetDir, fileName)
        FileInputStream(sourceFile).use { input ->
            destFile.outputStream().use { out ->
                val buf = ByteArray(16 * 1024)
                var read: Int
                while (input.read(buf).also { read = it } != -1) {
                    out.write(buf, 0, read)
                }
                out.flush()
            }
        }

        MediaScannerConnection.scanFile(
            applicationContext,
            arrayOf(destFile.absolutePath),
            arrayOf(mimeType),
            null
        )

        return mapOf(
            "uri" to "",
            "filePath" to destFile.absolutePath,
            "displayName" to destFile.name,
            "location" to "$subFolder/ReGen",
            "mimeType" to mimeType
        )
    }

    private fun resolveUniqueFile(dir: File, rawName: String): File {
        var candidate = File(dir, rawName)
        if (!candidate.exists()) return candidate
        val dotIdx = rawName.lastIndexOf('.')
        val stem = if (dotIdx > 0) rawName.substring(0, dotIdx) else rawName
        val ext = if (dotIdx > 0) rawName.substring(dotIdx) else ""
        var counter = 1
        while (candidate.exists()) {
            candidate = File(dir, "${stem}_($counter)$ext")
            counter++
        }
        return candidate
    }

    private fun copyStream(sourceFile: File, out: OutputStream) {
        FileInputStream(sourceFile).use { input ->
            val buf = ByteArray(16 * 1024)
            var bytesRead: Int
            while (input.read(buf).also { bytesRead = it } != -1) {
                out.write(buf, 0, bytesRead)
            }
            out.flush()
        }
    }

    private fun openTargetFile(uriStr: String?, filePath: String?, mimeType: String): Boolean {
        val targetUri: Uri? = when {
            !uriStr.isNullOrEmpty() -> Uri.parse(uriStr)
            !filePath.isNullOrEmpty() -> {
                val file = File(filePath)
                if (!file.exists()) null
                else FileProvider.getUriForFile(
                    applicationContext,
                    "${applicationContext.packageName}.fileprovider",
                    file
                )
            }
            else -> null
        }
        if (targetUri == null) return false

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(targetUri, mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        if (intent.resolveActivity(packageManager) != null) {
            startActivity(intent)
            return true
        }
        val chooser = Intent.createChooser(intent, "Open with").apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(chooser)
        return true
    }
}
