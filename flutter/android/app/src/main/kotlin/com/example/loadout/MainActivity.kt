package com.example.loadout

import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "loadout/media_scan")
            .setMethodCallHandler { call, result ->
                if (call.method != "scanSavedImage") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val name = call.argument<String>("name")
                if (name == null) {
                    result.error("BAD_ARGS", "name is required", null)
                    return@setMethodCallHandler
                }
                scanSavedImage(name) { result.success(it) }
            }
    }

    // gal (wrapped_export.dart) saves Endgame cards. Up to Android 10 it writes the
    // file straight into Pictures/ and inserts a MediaStore row before the bytes
    // exist, so the row keeps a NULL size and dimensions and galleries (Google
    // Photos, Files) skip it. Scanning the file afterwards fills the row in.
    // Android 11+ saves through MediaStore properly, so nothing is needed there.
    private fun scanSavedImage(name: String, reply: (Map<String, Any?>) -> Unit) {
        if (Build.VERSION.SDK_INT > Build.VERSION_CODES.Q) {
            reply(mapOf("status" to "not_needed", "sdk" to Build.VERSION.SDK_INT))
            return
        }
        @Suppress("DEPRECATION")
        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
        // gal adds a number before the extension if the name is already taken.
        val file = dir.listFiles { f -> f.name.startsWith(name) && f.name.endsWith(".png") }
            ?.maxByOrNull { it.lastModified() }
        if (file == null || file.length() == 0L) {
            reply(mapOf("status" to "missing", "dir" to dir.path, "sdk" to Build.VERSION.SDK_INT))
            return
        }
        val size = file.length()
        MediaScannerConnection.scanFile(applicationContext, arrayOf(file.path), arrayOf("image/png")) { path, uri ->
            Handler(Looper.getMainLooper()).post {
                reply(
                    mapOf(
                        "status" to if (uri != null) "scanned" else "scan_failed",
                        "path" to path,
                        "size" to size,
                        "uri" to uri?.toString(),
                        "sdk" to Build.VERSION.SDK_INT,
                    ),
                )
            }
        }
    }
}
