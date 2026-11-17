package com.ibem.mimic

import android.content.Context
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine {
        return MimicEngineHost.obtainOrCreateEngine(context.applicationContext ?: context)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        if (MimicEngineHost.shouldConfigurePlugins(flutterEngine)) {
            super.configureFlutterEngine(flutterEngine)
        }
        MimicEngineHost.ensureChannelsBound(applicationContext ?: this, flutterEngine)
        MimicEngineHost.attachActivity(this)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (MimicEngineHost.handleRequestPermissionsResult(this, requestCode, grantResults)) {
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        val changingConfigs = isChangingConfigurations
        val finishing = isFinishing
        MimicEngineHost.detachActivity(this)
        super.onDestroy()
        MimicEngineHost.onActivityDestroyed(
            context = applicationContext ?: this,
            isChangingConfigurations = changingConfigs,
            isFinishing = finishing,
        )
    }
}
