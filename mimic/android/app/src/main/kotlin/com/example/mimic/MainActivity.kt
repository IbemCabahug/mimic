package com.example.mimic

import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import android.view.WindowManager
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "mimic/launcher_icon"

    // F23: one bounded worker pool for frame extraction. Two workers so a slow
    // metadata read cannot starve the queue entirely; the Dart side bounds each
    // call with its own timeout. Frames live only in memory on this side — they
    // are compressed to JPEG bytes and handed back through the channel; nothing
    // is written to disk or any system cache (register constraint).
    private val thumbnailExecutor = Executors.newFixedThreadPool(2)

    private val LAUNCHER_ALIAS by lazy { "$packageName.LauncherAlias" }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mimic/storage").setMethodCallHandler { call, result ->
            when (call.method) {
                "getAvailableBytes" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        try {
                            val stat = android.os.StatFs(path)
                            result.success(stat.availableBytes)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARG", "Path required", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mimic/secure_screen").setMethodCallHandler { call, result ->
            when (call.method) {
                "enable" -> {
                    runOnUiThread { window.addFlags(WindowManager.LayoutParams.FLAG_SECURE) }
                    result.success(null)
                }
                "disable" -> {
                    runOnUiThread { window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE) }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setIconVisible" -> {
                    val visible = call.argument<Boolean>("visible") ?: true
                    val component = ComponentName(this, LAUNCHER_ALIAS)
                    val newState = if (visible) {
                        PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                    } else {
                        PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                    }
                    packageManager.setComponentEnabledSetting(
                        component,
                        newState,
                        PackageManager.DONT_KILL_APP,
                    )
                    result.success(true)
                }
                "isIconVisible" -> {
                    val component = ComponentName(this, LAUNCHER_ALIAS)
                    val state = packageManager.getComponentEnabledSetting(component)
                    val isVisible = state != PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                    result.success(isVisible)
                }
                else -> result.notImplemented()
            }
        }

        // F23 — video thumbnails: capture one early keyframe from the vault's own
        // loopback streaming server (the same URL the player consumes), scale it
        // to tile width and return JPEG bytes. In memory only, best-effort.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mimic/video_thumbnail").setMethodCallHandler { call, result ->
            when (call.method) {
                "extractFrame" -> {
                    val url = call.argument<String>("url")
                    val maxWidthPx = call.argument<Int>("maxWidthPx") ?: 640
                    if (url == null) {
                        result.error("INVALID_ARG", "url required", null)
                        return@setMethodCallHandler
                    }
                    thumbnailExecutor.execute {
                        val retriever = android.media.MediaMetadataRetriever()
                        try {
                            retriever.setDataSource(url, HashMap<String, String>())
                            val frame = retriever.getFrameAtTime(
                                0,
                                android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                            )
                            val bitmap = if (frame != null && frame.width > maxWidthPx) {
                                val height = (frame.height.toLong() * maxWidthPx / frame.width).toInt()
                                android.graphics.Bitmap.createScaledBitmap(frame, maxWidthPx, height, true)
                            } else {
                                frame
                            }
                            val bytes = if (bitmap != null) {
                                val out = java.io.ByteArrayOutputStream()
                                bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 72, out)
                                out.toByteArray()
                            } else {
                                null
                            }
                            runOnUiThread { result.success(bytes) }
                        } catch (e: Exception) {
                            // Best-effort by design: any failure means "no thumbnail",
                            // never an error the vault UI has to surface.
                            runOnUiThread { result.success(null) }
                        } finally {
                            try {
                                retriever.release()
                            } catch (_: Exception) {}
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mimic/keystore").setMethodCallHandler(KeystoreChannel(this))
    }
}
