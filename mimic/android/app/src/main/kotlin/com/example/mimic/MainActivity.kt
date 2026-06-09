package com.example.mimic

import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "mimic/launcher_icon"
    private val LAUNCHER_ALIAS by lazy { "$packageName.LauncherAlias" }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
    }
}
