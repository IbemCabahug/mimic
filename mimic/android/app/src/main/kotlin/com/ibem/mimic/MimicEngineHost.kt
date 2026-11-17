package com.ibem.mimic

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.Settings
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.lang.ref.WeakReference
import java.util.concurrent.Executors

/**
 * Process-scoped owner of the single cached [FlutterEngine] and platform
 * method channels so active background imports survive [MainActivity]
 * recreation or teardown without retaining stale Activity references.
 */
object MimicEngineHost {
    const val ENGINE_ID = "mimic_main_engine"
    const val REQUEST_POST_NOTIFICATIONS = 9104
    const val CHANNEL_LAUNCHER_ICON = "mimic/launcher_icon"

    internal interface ImportServiceBridge {
        fun startForegroundImport(
            context: Context,
            completed: Int,
            total: Int,
            activePercent: Int = -1,
        )
        fun updateForegroundImport(
            context: Context,
            completed: Int,
            total: Int,
            activePercent: Int = -1,
        )
        fun stopForegroundImport(context: Context)
        fun stopForDeadEngine(context: Context)
        fun isServiceActive(): Boolean
    }

    private object DefaultImportServiceBridge : ImportServiceBridge {
        override fun startForegroundImport(
            context: Context,
            completed: Int,
            total: Int,
            activePercent: Int,
        ) {
            val intent = Intent(context, ImportForegroundService::class.java).apply {
                action = ImportForegroundService.ACTION_START_OR_UPDATE
                putExtra(ImportForegroundService.EXTRA_COMPLETED, completed)
                putExtra(ImportForegroundService.EXTRA_TOTAL, total)
                putExtra(ImportForegroundService.EXTRA_ACTIVE_PERCENT, activePercent)
            }
            ContextCompat.startForegroundService(context, intent)
        }

        override fun updateForegroundImport(
            context: Context,
            completed: Int,
            total: Int,
            activePercent: Int,
        ) {
            val intent = Intent(context, ImportForegroundService::class.java).apply {
                action = ImportForegroundService.ACTION_START_OR_UPDATE
                putExtra(ImportForegroundService.EXTRA_COMPLETED, completed)
                putExtra(ImportForegroundService.EXTRA_TOTAL, total)
                putExtra(ImportForegroundService.EXTRA_ACTIVE_PERCENT, activePercent)
            }
            context.startService(intent)
        }

        override fun stopForegroundImport(context: Context) {
            ImportForegroundService.markHostStopping()
            val stopIntent = Intent(context, ImportForegroundService::class.java).apply {
                action = ImportForegroundService.ACTION_STOP
            }
            context.stopService(stopIntent)
        }

        override fun stopForDeadEngine(context: Context) {
            ImportForegroundService.stopForDeadEngine(context)
        }

        override fun isServiceActive(): Boolean = ImportForegroundService.isServiceActive
    }

    private val lock = Any()
    private val thumbnailExecutor = Executors.newFixedThreadPool(2)

    @Volatile
    private var cachedEngine: FlutterEngine? = null

    @Volatile
    private var pluginsConfiguredEngineRef: WeakReference<FlutterEngine>? = null

    @Volatile
    private var boundEngineRef: WeakReference<FlutterEngine>? = null

    @Volatile
    private var boundMessenger: BinaryMessenger? = null

    @Volatile
    private var importServiceChannel: MethodChannel? = null

    @Volatile
    private var currentActivityRef: WeakReference<FragmentActivity>? = null

    @Volatile
    private var secureScreenEnabled: Boolean = false

    @Volatile
    private var pendingNotifPermissionResult: MethodChannel.Result? = null

    @Volatile
    private var pendingPermissionActivityRef: WeakReference<FragmentActivity>? = null

    @Volatile
    internal var serviceBridgeForTest: ImportServiceBridge? = null

    @Volatile
    internal var postToMainOverrideForTest: ((Runnable) -> Unit)? = null

    @Volatile
    internal var notificationPermissionOverrideForTest: Boolean? = null

    @Volatile
    internal var sdkIntOverrideForTest: Int? = null

    @Volatile
    internal var requestPermissionLauncherForTest: ((FragmentActivity, Array<String>, Int) -> Unit)? = null

    @Volatile
    internal var engineCacheOverrideForTest: FlutterEngineCache? = null

    val currentActivity: FragmentActivity?
        get() = currentActivityRef?.get()

    internal val isSecureScreenEnabledForTest: Boolean
        get() = secureScreenEnabled

    internal val hasCachedEngineForTest: Boolean
        get() = cachedEngine != null

    private fun activeBridge(): ImportServiceBridge =
        serviceBridgeForTest ?: DefaultImportServiceBridge

    private fun activeEngineCache(): FlutterEngineCache =
        engineCacheOverrideForTest ?: FlutterEngineCache.getInstance()

    private fun effectiveSdkInt(): Int =
        sdkIntOverrideForTest ?: Build.VERSION.SDK_INT

    private fun postToMain(task: () -> Unit) {
        val override = postToMainOverrideForTest
        if (override != null) {
            override(Runnable { task() })
            return
        }
        val looper = Looper.getMainLooper()
        if (looper == null) {
            task()
        } else if (Looper.myLooper() == looper) {
            task()
        } else {
            Handler(looper).post(task)
        }
    }

    /**
     * Pure lifecycle retention decision for Activity destruction:
     * keep the single [FlutterEngine] alive during configuration changes,
     * non-finishing destruction, or while [ImportForegroundService] is active.
     */
    fun shouldRetainEngine(
        isChangingConfigurations: Boolean,
        isFinishing: Boolean,
        isServiceActive: Boolean,
    ): Boolean = isChangingConfigurations || isServiceActive || !isFinishing

    fun obtainOrCreateEngine(context: Context): FlutterEngine {
        val appContext = context.applicationContext ?: context
        synchronized(lock) {
            val cache = activeEngineCache()
            val existing = cachedEngine ?: cache.get(ENGINE_ID)
            if (existing != null) {
                cachedEngine = existing
                return existing
            }
            val engine = FlutterEngine(appContext)
            registerEngineInstanceLocked(appContext, engine, cache)
            return engine
        }
    }

    internal fun registerEngineForTest(
        context: Context,
        engine: FlutterEngine,
        cache: FlutterEngineCache? = null,
    ) {
        val appContext = context.applicationContext ?: context
        synchronized(lock) {
            if (cache != null) {
                engineCacheOverrideForTest = cache
            }
            registerEngineInstanceLocked(appContext, engine, activeEngineCache())
        }
    }

    private fun registerEngineInstanceLocked(
        appContext: Context,
        engine: FlutterEngine,
        cache: FlutterEngineCache,
    ) {
        cachedEngine = engine
        cache.put(ENGINE_ID, engine)
        engine.addEngineLifecycleListener(
            object : FlutterEngine.EngineLifecycleListener {
                override fun onPreEngineRestart() {}

                override fun onEngineWillDestroy() {
                    handleEngineWillDestroy(appContext, engine)
                }
            },
        )
    }

    fun shouldConfigurePlugins(engine: FlutterEngine): Boolean {
        synchronized(lock) {
            if (pluginsConfiguredEngineRef?.get() === engine) {
                return false
            }
            pluginsConfiguredEngineRef = WeakReference(engine)
            return true
        }
    }

    fun ensureChannelsBound(context: Context, engine: FlutterEngine) {
        val appContext = context.applicationContext ?: context
        synchronized(lock) {
            if (boundEngineRef?.get() === engine && boundMessenger != null) {
                return
            }
            bindChannelsLocked(appContext, engine.dartExecutor.binaryMessenger)
            boundEngineRef = WeakReference(engine)
        }
    }

    internal fun bindChannelsForTest(context: Context, messenger: BinaryMessenger) {
        val appContext = context.applicationContext ?: context
        synchronized(lock) {
            if (boundMessenger === messenger) {
                return
            }
            bindChannelsLocked(appContext, messenger)
        }
    }

    private fun bindChannelsLocked(appContext: Context, messenger: BinaryMessenger) {
        boundMessenger = messenger

        MethodChannel(messenger, "mimic/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceId" -> {
                    try {
                        val androidId = Settings.Secure.getString(
                            appContext.contentResolver,
                            Settings.Secure.ANDROID_ID,
                        ) ?: ""
                        result.success(androidId)
                    } catch (_: Exception) {
                        result.success("")
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "mimic/storage").setMethodCallHandler { call, result ->
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

        MethodChannel(messenger, "mimic/secure_screen").setMethodCallHandler { call, result ->
            handleSecureScreenMethod(call, result)
        }

        MethodChannel(messenger, "mimic/documents").setMethodCallHandler { call, result ->
            when (call.method) {
                "deleteDocument" -> {
                    val uriStr = call.argument<String>("uri")
                    if (uriStr == null) {
                        result.error("INVALID_ARG", "uri required", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        var ok = false
                        try {
                            val uri = Uri.parse(uriStr)
                            if (DocumentsContract.isDocumentUri(appContext, uri)) {
                                ok = DocumentsContract.deleteDocument(appContext.contentResolver, uri)
                            }
                        } catch (_: Exception) {
                            ok = false
                        }
                        postToMain { result.success(ok) }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, CHANNEL_LAUNCHER_ICON).setMethodCallHandler { call, result ->
            val launcherAlias = "${appContext.packageName}.LauncherAlias"
            when (call.method) {
                "setIconVisible" -> {
                    val visible = call.argument<Boolean>("visible") ?: true
                    val component = ComponentName(appContext, launcherAlias)
                    val newState = if (visible) {
                        PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                    } else {
                        PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                    }
                    appContext.packageManager.setComponentEnabledSetting(
                        component,
                        newState,
                        PackageManager.DONT_KILL_APP,
                    )
                    result.success(true)
                }
                "isIconVisible" -> {
                    val component = ComponentName(appContext, launcherAlias)
                    val state = appContext.packageManager.getComponentEnabledSetting(component)
                    val isVisible = state != PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                    result.success(isVisible)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "mimic/video_thumbnail").setMethodCallHandler { call, result ->
            when (call.method) {
                "extractFrame" -> {
                    val url = call.argument<String>("url")
                    val maxWidthPx = call.argument<Int>("maxWidthPx") ?: 640
                    if (url == null) {
                        result.error("INVALID_ARG", "url required", null)
                        return@setMethodCallHandler
                    }
                    thumbnailExecutor.execute {
                        val retriever = MediaMetadataRetriever()
                        try {
                            retriever.setDataSource(url, HashMap<String, String>())
                            val frame = retriever.getFrameAtTime(
                                0,
                                MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                            )
                            val bitmap = if (frame != null && frame.width > maxWidthPx) {
                                val height = (frame.height.toLong() * maxWidthPx / frame.width).toInt()
                                Bitmap.createScaledBitmap(frame, maxWidthPx, height, true)
                            } else {
                                frame
                            }
                            val bytes = if (bitmap != null) {
                                val out = ByteArrayOutputStream()
                                bitmap.compress(Bitmap.CompressFormat.JPEG, 72, out)
                                out.toByteArray()
                            } else {
                                null
                            }
                            postToMain { result.success(bytes) }
                        } catch (_: Exception) {
                            postToMain { result.success(null) }
                        } finally {
                            try {
                                retriever.release()
                            } catch (_: Exception) {
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "mimic/keystore").setMethodCallHandler(
            KeystoreChannel { currentActivity },
        )

        val serviceChannel = MethodChannel(messenger, "mimic/import_service")
        importServiceChannel = serviceChannel
        ImportForegroundService.attachChannel(serviceChannel)
        serviceChannel.setMethodCallHandler { call, result ->
            handleImportServiceMethod(appContext, call, result)
        }
    }

    internal fun handleSecureScreenMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "enable" -> {
                secureScreenEnabled = true
                val act = currentActivity
                if (act != null) {
                    postToMain { act.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE) }
                }
                result.success(null)
            }
            "disable" -> {
                secureScreenEnabled = false
                val act = currentActivity
                if (act != null) {
                    postToMain { act.window?.clearFlags(WindowManager.LayoutParams.FLAG_SECURE) }
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    internal fun handleImportServiceMethod(
        context: Context,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val appContext = context.applicationContext ?: context
        val bridge = activeBridge()
        when (call.method) {
            "hasNotificationPermission" -> {
                result.success(hasNotificationPermissionCompat(appContext))
            }
            "requestNotificationPermission" -> {
                val act = currentActivity
                if (hasNotificationPermissionCompat(appContext) ||
                    effectiveSdkInt() < Build.VERSION_CODES.TIRAMISU
                ) {
                    result.success(true)
                } else if (act == null) {
                    result.success(false)
                } else {
                    var staleResult: MethodChannel.Result? = null
                    synchronized(lock) {
                        val existing = pendingNotifPermissionResult
                        if (existing != null) {
                            val existingAct = pendingPermissionActivityRef?.get()
                            if (existingAct != null && existingAct === act) {
                                result.success(false)
                                return
                            }
                            // Fail orphaned callback from an earlier detached Activity so
                            // future permission prompts cannot stay latched out.
                            staleResult = existing
                            pendingNotifPermissionResult = null
                            pendingPermissionActivityRef = null
                        }
                        pendingNotifPermissionResult = result
                        pendingPermissionActivityRef = WeakReference(act)
                    }
                    try {
                        staleResult?.success(false)
                    } catch (_: Exception) {
                    }
                    val launcher = requestPermissionLauncherForTest
                    if (launcher != null) {
                        launcher(
                            act,
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            REQUEST_POST_NOTIFICATIONS,
                        )
                    } else {
                        ActivityCompat.requestPermissions(
                            act,
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            REQUEST_POST_NOTIFICATIONS,
                        )
                    }
                }
            }
            "startService" -> {
                val completed = (call.argument<Int>("completed") ?: 0).coerceAtLeast(0)
                val total = (call.argument<Int>("total") ?: 0).coerceAtLeast(0)
                val rawPercent = call.argument<Int>("activePercent") ?: -1
                val activePercent = if (rawPercent in 0..100) rawPercent else -1
                val notifGranted = hasNotificationPermissionCompat(appContext)
                try {
                    bridge.startForegroundImport(appContext, completed, total, activePercent)
                    result.success(
                        hashMapOf(
                            "started" to true,
                            "notificationsGranted" to notifGranted,
                        ),
                    )
                } catch (e: Exception) {
                    val code = if (effectiveSdkInt() >= Build.VERSION_CODES.S &&
                        e is android.app.ForegroundServiceStartNotAllowedException
                    ) {
                        "start_not_allowed"
                    } else if (e is SecurityException) {
                        "security_exception"
                    } else {
                        "start_failed"
                    }
                    result.success(
                        hashMapOf(
                            "started" to false,
                            "notificationsGranted" to notifGranted,
                            "errorCode" to code,
                            "safeMessage" to "Background processing permission unavailable.",
                        ),
                    )
                }
            }
            "updateProgress" -> {
                if (!bridge.isServiceActive()) {
                    result.success(null)
                    return
                }
                val completed = (call.argument<Int>("completed") ?: 0).coerceAtLeast(0)
                val total = (call.argument<Int>("total") ?: 0).coerceAtLeast(0)
                val rawPercent = call.argument<Int>("activePercent") ?: -1
                val activePercent = if (rawPercent in 0..100) rawPercent else -1
                try {
                    bridge.updateForegroundImport(appContext, completed, total, activePercent)
                } catch (_: Exception) {
                }
                result.success(null)
            }
            "stopService" -> {
                try {
                    bridge.stopForegroundImport(appContext)
                } catch (_: Exception) {
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun attachActivity(activity: FragmentActivity) {
        synchronized(lock) {
            currentActivityRef = WeakReference(activity)
            if (secureScreenEnabled) {
                postToMain {
                    activity.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
            }
        }
    }

    fun detachActivity(activity: FragmentActivity) {
        var pendingToFail: MethodChannel.Result? = null
        synchronized(lock) {
            if (currentActivityRef?.get() === activity) {
                currentActivityRef = null
            }
            if (pendingNotifPermissionResult != null &&
                pendingPermissionActivityRef?.get() === activity
            ) {
                pendingToFail = pendingNotifPermissionResult
                pendingNotifPermissionResult = null
                pendingPermissionActivityRef = null
            }
        }
        pendingToFail?.success(false)
    }

    fun handleRequestPermissionsResult(
        activity: FragmentActivity,
        requestCode: Int,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_POST_NOTIFICATIONS) {
            return false
        }
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        var pending: MethodChannel.Result? = null
        synchronized(lock) {
            val owner = pendingPermissionActivityRef?.get()
            if (owner == null || owner === activity) {
                pending = pendingNotifPermissionResult
                pendingNotifPermissionResult = null
                pendingPermissionActivityRef = null
            }
        }
        pending?.success(granted)
        return true
    }

    fun onActivityDestroyed(
        context: Context,
        isChangingConfigurations: Boolean,
        isFinishing: Boolean,
    ) {
        val appContext = context.applicationContext ?: context
        val bridge = activeBridge()
        var engineToDestroy: FlutterEngine? = null
        synchronized(lock) {
            if (currentActivityRef?.get() != null) {
                return
            }
            val retain = shouldRetainEngine(
                isChangingConfigurations = isChangingConfigurations,
                isFinishing = isFinishing,
                isServiceActive = bridge.isServiceActive(),
            )
            if (!retain) {
                engineToDestroy = prepareTeardownLocked(appContext, targetEngine = cachedEngine)
            }
        }
        if (engineToDestroy != null) {
            bridge.stopForDeadEngine(appContext)
            try {
                engineToDestroy?.destroy()
            } catch (_: Exception) {
            }
        }
    }

    internal fun handleEngineWillDestroy(
        context: Context,
        engine: FlutterEngine,
    ) {
        val appContext = context.applicationContext ?: context
        val bridge = activeBridge()
        var shouldStopService = false
        synchronized(lock) {
            if (cachedEngine === engine || boundEngineRef?.get() === engine) {
                prepareTeardownLocked(appContext, targetEngine = engine)
                shouldStopService = true
            }
        }
        if (shouldStopService) {
            bridge.stopForDeadEngine(appContext)
        }
    }

    private fun prepareTeardownLocked(
        @Suppress("UNUSED_PARAMETER") appContext: Context,
        targetEngine: FlutterEngine?,
    ): FlutterEngine? {
        val engine = targetEngine ?: cachedEngine
        if (cachedEngine === engine) {
            cachedEngine = null
        }
        if (boundEngineRef?.get() === engine) {
            boundEngineRef = null
        }
        if (pluginsConfiguredEngineRef?.get() === engine) {
            pluginsConfiguredEngineRef = null
        }
        boundMessenger = null

        val serviceCh = importServiceChannel
        importServiceChannel = null
        if (serviceCh != null) {
            ImportForegroundService.detachChannel(serviceCh)
        }

        val pending = pendingNotifPermissionResult
        pendingNotifPermissionResult = null
        pendingPermissionActivityRef = null
        if (pending != null) {
            try {
                pending.success(false)
            } catch (_: Exception) {
            }
        }

        val cache = activeEngineCache()
        if (engine == null || cache.get(ENGINE_ID) === engine) {
            cache.remove(ENGINE_ID)
        }
        secureScreenEnabled = false
        return engine
    }

    private fun hasNotificationPermissionCompat(context: Context): Boolean {
        notificationPermissionOverrideForTest?.let { return it }
        if (effectiveSdkInt() < Build.VERSION_CODES.TIRAMISU) {
            return true
        }
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    internal fun resetForTest() {
        synchronized(lock) {
            val ch = importServiceChannel
            importServiceChannel = null
            if (ch != null) {
                ImportForegroundService.detachChannel(ch)
            }
            cachedEngine = null
            pluginsConfiguredEngineRef = null
            boundEngineRef = null
            boundMessenger = null
            currentActivityRef = null
            secureScreenEnabled = false
            pendingNotifPermissionResult = null
            pendingPermissionActivityRef = null
            serviceBridgeForTest = null
            postToMainOverrideForTest = null
            notificationPermissionOverrideForTest = null
            sdkIntOverrideForTest = null
            requestPermissionLauncherForTest = null
            engineCacheOverrideForTest = null
        }
        ImportForegroundService.eventDispatcherForTest = null
        ImportForegroundService.setServiceActiveForTest(false)
    }
}
