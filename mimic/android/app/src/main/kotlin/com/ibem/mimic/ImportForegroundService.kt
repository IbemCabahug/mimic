package com.ibem.mimic

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import kotlin.math.max

/**
 * Unexported dataSync foreground service supporting user-initiated local
 * encrypted gallery imports while the user switches apps or turns the screen off.
 *
 * Security & lifecycle invariants:
 * - Single FlutterEngine / single process: runs NO separate Dart engine or
 *   competing queue coordinator. All work continues in the app's single
 *   ImportCoordinator; this service strictly holds foreground execution,
 *   privacy-safe progress notification, and bounded WakeLock.
 * - START_NOT_STICKY so OS process termination never phantom-restarts imports.
 * - Generic non-PII notification strings only (no filenames, paths, MIME,
 *   thumbnails, or vault labels).
 * - Explicit Android 15+ [onTimeout] handling releases WakeLock & stops FGS.
 */
class ImportForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "mimic_local_import"
        const val CHANNEL_NAME = "Local Media Processing"
        const val NOTIFICATION_ID = 4107

        const val ACTION_START_OR_UPDATE = "com.ibem.mimic.import.START_OR_UPDATE"
        const val ACTION_STOP = "com.ibem.mimic.import.STOP"
        const val ACTION_PAUSE = "com.ibem.mimic.import.PAUSE"
        const val ACTION_CANCEL = "com.ibem.mimic.import.CANCEL"

        const val EXTRA_COMPLETED = "completed"
        const val EXTRA_TOTAL = "total"
        const val EXTRA_ACTIVE_PERCENT = "active_percent"
        const val EXTRA_TOKEN = "token"

        private const val MAX_WAKELOCK_MS = 31L * 60L * 1000L

        private val mainHandler = Handler(Looper.getMainLooper())
        private val processToken: String = UUID.randomUUID().toString()

        @Volatile
        private var channel: MethodChannel? = null

        @Volatile
        var isServiceActive: Boolean = false
            private set

        @Volatile
        private var stopRequestedByHost: Boolean = false

        internal fun isValidActionToken(token: String?): Boolean = token == processToken

        internal data class NotificationProgressSpec(
            val contentText: String,
            val progressMax: Int,
            val progressValue: Int,
            val indeterminate: Boolean,
        )

        internal fun buildProgressSpec(
            completed: Int,
            total: Int,
            activePercent: Int? = null,
        ): NotificationProgressSpec {
            val safeTotal = max(total, 0)
            val safeCompleted = if (safeTotal > 0) completed.coerceIn(0, safeTotal) else 0
            if (safeTotal <= 0) {
                return NotificationProgressSpec(
                    contentText = "Processing items locally",
                    progressMax = 1,
                    progressValue = 0,
                    indeterminate = true,
                )
            }
            val validPercent = activePercent?.takeIf { it in 0..100 }
            if (validPercent != null && safeCompleted < safeTotal) {
                val activeItemNumber = minOf(safeCompleted + 1, safeTotal)
                val overallPercent =
                    (((safeCompleted.toLong() * 100L) + validPercent.toLong()) / safeTotal.toLong())
                        .toInt()
                        .coerceIn(0, 100)
                return NotificationProgressSpec(
                    contentText = "Processing $activeItemNumber of $safeTotal items ($validPercent%)",
                    progressMax = 100,
                    progressValue = overallPercent,
                    indeterminate = false,
                )
            }
            return NotificationProgressSpec(
                contentText = "Processing $safeCompleted of $safeTotal items",
                progressMax = safeTotal,
                progressValue = safeCompleted,
                indeterminate = false,
            )
        }

        internal fun currentProcessTokenForTest(): String = processToken

        @Volatile
        internal var eventDispatcherForTest: ((MethodChannel?, String) -> Unit)? = null

        fun attachChannel(methodChannel: MethodChannel) {
            channel = methodChannel
        }

        fun detachChannel(methodChannel: MethodChannel) {
            if (channel === methodChannel) {
                channel = null
            }
        }

        internal fun currentChannelForTest(): MethodChannel? = channel

        fun markHostStopping() {
            stopRequestedByHost = true
        }

        internal fun setServiceActiveForTest(active: Boolean) {
            isServiceActive = active
        }

        fun stopForDeadEngine(context: Context) {
            stopRequestedByHost = true
            isServiceActive = false
            channel = null
            val appContext = context.applicationContext ?: context
            try {
                val nm =
                    appContext.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                nm?.cancel(NOTIFICATION_ID)
            } catch (_: Exception) {
            }
            try {
                appContext.stopService(Intent(appContext, ImportForegroundService::class.java))
            } catch (_: Exception) {
            }
        }

        fun emitEvent(event: String) {
            val dispatcher = eventDispatcherForTest
            if (dispatcher != null) {
                dispatcher(channel, event)
                return
            }
            mainHandler.post {
                try {
                    channel?.invokeMethod(
                        "onServiceEvent",
                        hashMapOf("event" to event),
                    )
                } catch (_: Exception) {
                }
            }
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureChannel()
        val action = intent?.action ?: ACTION_START_OR_UPDATE

        if (action == ACTION_PAUSE) {
            if (isValidActionToken(intent?.getStringExtra(EXTRA_TOKEN))) {
                isServiceActive = false
                stopRequestedByHost = true
                releaseWakeLock()
                emitEvent("pause")
                stopForegroundCompat()
                stopSelf(startId)
            }
            return START_NOT_STICKY
        }

        if (action == ACTION_CANCEL) {
            if (isValidActionToken(intent?.getStringExtra(EXTRA_TOKEN))) {
                isServiceActive = false
                stopRequestedByHost = true
                releaseWakeLock()
                emitEvent("cancel")
                stopForegroundCompat()
                stopSelf(startId)
            }
            return START_NOT_STICKY
        }

        if (action == ACTION_STOP) {
            stopRequestedByHost = true
            isServiceActive = false
            releaseWakeLock()
            stopForegroundCompat()
            stopSelf(startId)
            return START_NOT_STICKY
        }

        stopRequestedByHost = false
        val completed = (intent?.getIntExtra(EXTRA_COMPLETED, 0) ?: 0).coerceAtLeast(0)
        val total = (intent?.getIntExtra(EXTRA_TOTAL, 0) ?: 0).coerceAtLeast(0)
        val rawActivePercent = intent?.getIntExtra(EXTRA_ACTIVE_PERCENT, -1) ?: -1
        val activePercent = if (rawActivePercent in 0..100) rawActivePercent else null
        val notification = buildNotification(
            completed = completed,
            total = total,
            activePercent = activePercent,
        )

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            isServiceActive = true
            refreshWakeLock(activeWork = total == 0 || completed < total)
        } catch (e: Exception) {
            isServiceActive = false
            releaseWakeLock()
            emitEvent("stopped")
            stopSelf(startId)
        }

        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        isServiceActive = false
        stopRequestedByHost = true
        releaseWakeLock()
        emitEvent("timeout")
        stopForegroundCompat()
        stopSelf(startId)
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        isServiceActive = false
        stopRequestedByHost = true
        releaseWakeLock()
        emitEvent("stopped")
        stopForegroundCompat()
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        val wasExpected = stopRequestedByHost
        isServiceActive = false
        stopRequestedByHost = false
        releaseWakeLock()
        if (!wasExpected) {
            emitEvent("stopped")
        }
        super.onDestroy()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Ongoing local media encryption status"
                    setShowBadge(false)
                    enableVibration(false)
                    setSound(null, null)
                }
                nm.createNotificationChannel(channel)
            }
        }
    }

    private fun buildNotification(
        completed: Int,
        total: Int,
        activePercent: Int?,
    ): Notification {
        val spec = buildProgressSpec(
            completed = completed,
            total = total,
            activePercent = activePercent,
        )

        val launchIntent = Intent(this, MainActivity::class.java).apply {
            this.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentPendingIntent = PendingIntent.getActivity(
            this,
            100,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val pauseIntent = Intent(this, ImportForegroundService::class.java).apply {
            action = ACTION_PAUSE
            putExtra(EXTRA_TOKEN, processToken)
        }
        val pausePendingIntent = PendingIntent.getService(
            this,
            101,
            pauseIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val cancelIntent = Intent(this, ImportForegroundService::class.java).apply {
            action = ACTION_CANCEL
            putExtra(EXTRA_TOKEN, processToken)
        }
        val cancelPendingIntent = PendingIntent.getService(
            this,
            102,
            cancelIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder
            .setSmallIcon(R.drawable.ic_import_sync)
            .setContentTitle("Mimic")
            .setContentText(spec.contentText)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(contentPendingIntent)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setProgress(spec.progressMax, spec.progressValue, spec.indeterminate)
            .addAction(
                Notification.Action.Builder(null, "Pause", pausePendingIntent).build(),
            )
            .addAction(
                Notification.Action.Builder(null, "Cancel", cancelPendingIntent).build(),
            )

        return builder.build()
    }

    private fun refreshWakeLock(activeWork: Boolean) {
        if (!activeWork) {
            releaseWakeLock()
            return
        }
        try {
            var lock = wakeLock
            if (lock == null) {
                val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
                lock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "mimic:import_wakelock")
                lock.setReferenceCounted(false)
                wakeLock = lock
            }
            lock.acquire(MAX_WAKELOCK_MS)
        } catch (_: Exception) {
        }
    }

    private fun releaseWakeLock() {
        try {
            val lock = wakeLock
            if (lock != null && lock.isHeld) {
                lock.release()
            }
        } catch (_: Exception) {
        }
    }

    private fun stopForegroundCompat() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Exception) {
        }
    }
}
