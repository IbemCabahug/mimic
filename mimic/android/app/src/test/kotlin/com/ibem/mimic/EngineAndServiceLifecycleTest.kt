package com.ibem.mimic

import android.content.Context
import android.content.pm.PackageManager
import android.view.Window
import android.view.WindowManager
import androidx.fragment.app.FragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class EngineAndServiceLifecycleTest {
    private lateinit var appContext: Context
    private lateinit var messenger: BinaryMessenger
    private lateinit var engine: FlutterEngine
    private lateinit var engineCache: FlutterEngineCache

    @Before
    fun setUp() {
        MimicEngineHost.resetForTest()
        appContext = mockk(relaxed = true)
        every { appContext.applicationContext } returns appContext
        messenger = mockk(relaxed = true)
        val dartExecutor = mockk<io.flutter.embedding.engine.dart.DartExecutor>(relaxed = true)
        every { dartExecutor.binaryMessenger } returns messenger
        engine = mockk(relaxed = true)
        every { engine.dartExecutor } returns dartExecutor
        engineCache = mockk(relaxed = true)
        every { engineCache.get(MimicEngineHost.ENGINE_ID) } returns engine
        MimicEngineHost.postToMainOverrideForTest = { it.run() }
    }

    @After
    fun tearDown() {
        MimicEngineHost.resetForTest()
    }

    @Test
    fun retainPolicyRespectsConfigChangeAndActiveForegroundService() {
        assertTrue(
            MimicEngineHost.shouldRetainEngine(
                isChangingConfigurations = true,
                isFinishing = true,
                isServiceActive = false,
            ),
        )
        assertTrue(
            MimicEngineHost.shouldRetainEngine(
                isChangingConfigurations = false,
                isFinishing = true,
                isServiceActive = true,
            ),
        )
        assertTrue(
            MimicEngineHost.shouldRetainEngine(
                isChangingConfigurations = false,
                isFinishing = false,
                isServiceActive = false,
            ),
        )
        assertFalse(
            MimicEngineHost.shouldRetainEngine(
                isChangingConfigurations = false,
                isFinishing = true,
                isServiceActive = false,
            ),
        )
    }

    @Test
    fun activityDestructionWithActiveImportRetainsEngineChannelAndRebindsSafely() {
        val bridge = FakeImportServiceBridge(active = true)
        MimicEngineHost.serviceBridgeForTest = bridge
        MimicEngineHost.registerEngineForTest(appContext, engine, engineCache)

        assertTrue(MimicEngineHost.shouldConfigurePlugins(engine))
        assertFalse(MimicEngineHost.shouldConfigurePlugins(engine))

        MimicEngineHost.ensureChannelsBound(appContext, engine)
        // Second call (simulating Activity recreation) must not rebind channels.
        MimicEngineHost.ensureChannelsBound(appContext, engine)
        verify(exactly = 1) { messenger.setMessageHandler("mimic/import_service", any()) }
        verify(exactly = 1) { messenger.setMessageHandler("mimic/keystore", any()) }

        val activity1 = mockk<FragmentActivity>(relaxed = true)
        val window1 = mockk<Window>(relaxed = true)
        every { activity1.window } returns window1
        MimicEngineHost.attachActivity(activity1)
        assertSame(activity1, MimicEngineHost.currentActivity)

        val secureResult = mockk<MethodChannel.Result>(relaxed = true)
        MimicEngineHost.handleSecureScreenMethod(MethodCall("enable", null), secureResult)
        verify(exactly = 1) { window1.addFlags(WindowManager.LayoutParams.FLAG_SECURE) }
        verify(exactly = 1) { secureResult.success(null) }

        // Simulate Activity #1 finishing while foreground import service is active.
        MimicEngineHost.detachActivity(activity1)
        assertNull(MimicEngineHost.currentActivity)

        MimicEngineHost.onActivityDestroyed(
            context = appContext,
            isChangingConfigurations = false,
            isFinishing = true,
        )

        assertTrue(MimicEngineHost.hasCachedEngineForTest)
        assertEquals(0, bridge.stopDeadEngineCalls)
        assertTrue(ImportForegroundService.currentChannelForTest() != null)
        verify(exactly = 0) { engine.destroy() }

        // Background progress updates and service events continue with null Activity.
        val updateResult = mockk<MethodChannel.Result>(relaxed = true)
        MimicEngineHost.handleImportServiceMethod(
            appContext,
            MethodCall("updateProgress", hashMapOf("completed" to 4, "total" to 10)),
            updateResult,
        )
        assertEquals(1, bridge.updateCalls)
        verify(exactly = 1) { updateResult.success(null) }

        val emittedEvents = mutableListOf<String>()
        ImportForegroundService.eventDispatcherForTest = { ch, event ->
            if (ch != null) emittedEvents.add(event)
        }
        ImportForegroundService.emitEvent("pause")
        assertEquals(listOf("pause"), emittedEvents)

        // Recreated Activity #2 re-attaches cleanly and inherits FLAG_SECURE + fresh reference.
        val activity2 = mockk<FragmentActivity>(relaxed = true)
        val window2 = mockk<Window>(relaxed = true)
        every { activity2.window } returns window2
        MimicEngineHost.attachActivity(activity2)
        assertSame(activity2, MimicEngineHost.currentActivity)
        verify(exactly = 1) { window2.addFlags(WindowManager.LayoutParams.FLAG_SECURE) }
    }

    @Test
    fun finishingWithIdleServiceDestroysEngineDetachesChannelAndStopsService() {
        val bridge = FakeImportServiceBridge(active = false)
        MimicEngineHost.serviceBridgeForTest = bridge
        MimicEngineHost.registerEngineForTest(appContext, engine, engineCache)
        MimicEngineHost.ensureChannelsBound(appContext, engine)

        val activity = mockk<FragmentActivity>(relaxed = true)
        MimicEngineHost.attachActivity(activity)
        MimicEngineHost.handleSecureScreenMethod(
            MethodCall("enable", null),
            mockk(relaxed = true),
        )
        assertTrue(MimicEngineHost.isSecureScreenEnabledForTest)

        MimicEngineHost.detachActivity(activity)
        MimicEngineHost.onActivityDestroyed(
            context = appContext,
            isChangingConfigurations = false,
            isFinishing = true,
        )

        assertFalse(MimicEngineHost.hasCachedEngineForTest)
        assertFalse(MimicEngineHost.isSecureScreenEnabledForTest)
        assertNull(ImportForegroundService.currentChannelForTest())
        assertEquals(1, bridge.stopDeadEngineCalls)
        verify(exactly = 1) { engineCache.remove(MimicEngineHost.ENGINE_ID) }
        verify(exactly = 1) { engine.destroy() }
    }

    @Test
    fun engineWillDestroyStopsForegroundServiceSoNotificationAndWakeLockCannotOutliveEngine() {
        val bridge = FakeImportServiceBridge(active = true)
        MimicEngineHost.serviceBridgeForTest = bridge
        MimicEngineHost.registerEngineForTest(appContext, engine, engineCache)
        MimicEngineHost.ensureChannelsBound(appContext, engine)

        MimicEngineHost.handleEngineWillDestroy(appContext, engine)

        assertFalse(MimicEngineHost.hasCachedEngineForTest)
        assertNull(ImportForegroundService.currentChannelForTest())
        assertEquals(1, bridge.stopDeadEngineCalls)
        verify(exactly = 1) { engineCache.remove(MimicEngineHost.ENGINE_ID) }
    }

    @Test
    fun pendingNotificationPermissionResolvesFalseOnDetachAndGrantsAfterReattach() {
        MimicEngineHost.sdkIntOverrideForTest = 33
        MimicEngineHost.notificationPermissionOverrideForTest = false
        var launchedCount = 0
        MimicEngineHost.requestPermissionLauncherForTest = { _, _, _ -> launchedCount++ }

        val activity1 = mockk<FragmentActivity>(relaxed = true)
        MimicEngineHost.attachActivity(activity1)

        val pendingResult1 = mockk<MethodChannel.Result>(relaxed = true)
        MimicEngineHost.handleImportServiceMethod(
            appContext,
            MethodCall("requestNotificationPermission", null),
            pendingResult1,
        )
        assertEquals(1, launchedCount)

        // Detaching Activity #1 before grant arrives must cleanly fail pending future.
        MimicEngineHost.detachActivity(activity1)
        verify(exactly = 1) { pendingResult1.success(false) }

        val activity2 = mockk<FragmentActivity>(relaxed = true)
        MimicEngineHost.attachActivity(activity2)
        val pendingResult2 = mockk<MethodChannel.Result>(relaxed = true)
        MimicEngineHost.handleImportServiceMethod(
            appContext,
            MethodCall("requestNotificationPermission", null),
            pendingResult2,
        )
        assertEquals(2, launchedCount)

        assertTrue(
            MimicEngineHost.handleRequestPermissionsResult(
                activity2,
                MimicEngineHost.REQUEST_POST_NOTIFICATIONS,
                intArrayOf(PackageManager.PERMISSION_GRANTED),
            ),
        )
        verify(exactly = 1) { pendingResult2.success(true) }
    }

    @Test
    fun orphanedNotificationPermissionCallbackIsFailedWhenDifferentActivityRequestsPermission() {
        MimicEngineHost.sdkIntOverrideForTest = 33
        MimicEngineHost.notificationPermissionOverrideForTest = false
        MimicEngineHost.requestPermissionLauncherForTest = { _, _, _ -> }

        val activity1 = mockk<FragmentActivity>(relaxed = true)
        MimicEngineHost.attachActivity(activity1)
        val orphanedResult = mockk<MethodChannel.Result>(relaxed = true)
        MimicEngineHost.handleImportServiceMethod(
            appContext,
            MethodCall("requestNotificationPermission", null),
            orphanedResult,
        )

        // Attach activity2 without detaching activity1 first: stale request must resolve false
        // instead of blocking activity2's notification permission request.
        val activity2 = mockk<FragmentActivity>(relaxed = true)
        MimicEngineHost.attachActivity(activity2)
        val freshResult = mockk<MethodChannel.Result>(relaxed = true)
        MimicEngineHost.handleImportServiceMethod(
            appContext,
            MethodCall("requestNotificationPermission", null),
            freshResult,
        )

        verify(exactly = 1) { orphanedResult.success(false) }
        assertTrue(
            MimicEngineHost.handleRequestPermissionsResult(
                activity2,
                MimicEngineHost.REQUEST_POST_NOTIFICATIONS,
                intArrayOf(PackageManager.PERMISSION_GRANTED),
            ),
        )
        verify(exactly = 1) { freshResult.success(true) }
    }

    @Test
    fun foregroundServiceActionTokenRejectsForgedIntents() {
        val valid = ImportForegroundService.currentProcessTokenForTest()
        assertTrue(ImportForegroundService.isValidActionToken(valid))
        assertFalse(ImportForegroundService.isValidActionToken(null))
        assertFalse(ImportForegroundService.isValidActionToken(""))
        assertFalse(ImportForegroundService.isValidActionToken("forged-token"))
    }

    @Test
    fun notificationProgressSpecReportsPrivacySafeActivePercent() {
        val activeFirst = ImportForegroundService.buildProgressSpec(
            completed = 0,
            total = 2,
            activePercent = 42,
        )
        assertEquals("Processing 1 of 2 items (42%)", activeFirst.contentText)
        assertEquals(100, activeFirst.progressMax)
        assertEquals(21, activeFirst.progressValue)
        assertFalse(activeFirst.indeterminate)

        val activeSecond = ImportForegroundService.buildProgressSpec(
            completed = 1,
            total = 2,
            activePercent = 50,
        )
        assertEquals("Processing 2 of 2 items (50%)", activeSecond.contentText)
        assertEquals(100, activeSecond.progressMax)
        assertEquals(75, activeSecond.progressValue)
        assertFalse(activeSecond.indeterminate)

        val withoutPercent = ImportForegroundService.buildProgressSpec(
            completed = 1,
            total = 2,
            activePercent = null,
        )
        assertEquals("Processing 1 of 2 items", withoutPercent.contentText)
        assertEquals(2, withoutPercent.progressMax)
        assertEquals(1, withoutPercent.progressValue)

        val allDone = ImportForegroundService.buildProgressSpec(
            completed = 2,
            total = 2,
            activePercent = 99,
        )
        assertEquals("Processing 2 of 2 items", allDone.contentText)
        assertEquals(2, allDone.progressMax)
        assertEquals(2, allDone.progressValue)

        val unknownTotal = ImportForegroundService.buildProgressSpec(
            completed = 0,
            total = 0,
            activePercent = 50,
        )
        assertEquals("Processing items locally", unknownTotal.contentText)
        assertTrue(unknownTotal.indeterminate)
    }

    @Test
    fun handleImportServiceMethodForwardsActivePercentAndClampsOutOfRangeValues() {
        val bridge = FakeImportServiceBridge(active = false)
        MimicEngineHost.serviceBridgeForTest = bridge

        val startResult = mockk<MethodChannel.Result>(relaxed = true)
        MimicEngineHost.handleImportServiceMethod(
            appContext,
            MethodCall("startService", hashMapOf("completed" to 0, "total" to 3, "activePercent" to 37)),
            startResult,
        )
        assertEquals(1, bridge.startCalls)
        assertEquals(37, bridge.lastStartActivePercent)

        val updateValidResult = mockk<MethodChannel.Result>(relaxed = true)
        MimicEngineHost.handleImportServiceMethod(
            appContext,
            MethodCall("updateProgress", hashMapOf("completed" to 1, "total" to 3, "activePercent" to 64)),
            updateValidResult,
        )
        assertEquals(1, bridge.updateCalls)
        assertEquals(64, bridge.lastUpdateActivePercent)

        val updateInvalidResult = mockk<MethodChannel.Result>(relaxed = true)
        MimicEngineHost.handleImportServiceMethod(
            appContext,
            MethodCall("updateProgress", hashMapOf("completed" to 1, "total" to 3, "activePercent" to 180)),
            updateInvalidResult,
        )
        assertEquals(2, bridge.updateCalls)
        assertEquals(-1, bridge.lastUpdateActivePercent)
    }

    private class FakeImportServiceBridge(
        var active: Boolean,
    ) : MimicEngineHost.ImportServiceBridge {
        var startCalls = 0
        var updateCalls = 0
        var stopCalls = 0
        var stopDeadEngineCalls = 0
        var lastStartActivePercent = -1
        var lastUpdateActivePercent = -1

        override fun startForegroundImport(
            context: Context,
            completed: Int,
            total: Int,
            activePercent: Int,
        ) {
            startCalls++
            lastStartActivePercent = activePercent
            active = true
        }

        override fun updateForegroundImport(
            context: Context,
            completed: Int,
            total: Int,
            activePercent: Int,
        ) {
            updateCalls++
            lastUpdateActivePercent = activePercent
        }

        override fun stopForegroundImport(context: Context) {
            stopCalls++
            active = false
        }

        override fun stopForDeadEngine(context: Context) {
            stopDeadEngineCalls++
            active = false
        }

        override fun isServiceActive(): Boolean = active
    }
}
