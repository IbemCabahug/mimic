package com.example.mimic

import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import android.view.WindowManager
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "mimic/launcher_icon"
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mimic/keystore").setMethodCallHandler(KeystoreChannel(this))
    }
}
