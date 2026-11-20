package com.moneymanager.money_manager

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

private const val HEADLESS_CHANNEL = "com.moneymanager.money_manager/notification_headless"
private const val HEADLESS_ENGINE_TIMEOUT_MS = 15_000L

// See docs/features/background-reliability.md "Foreground service
// promotion" — a low-importance, silent, ongoing notification whose only
// purpose is to keep this service's process at foreground priority.
private const val FOREGROUND_CHANNEL_ID = "capture_status"
private const val FOREGROUND_NOTIFICATION_ID = 1

// See docs/features/background-reliability.md "Non-sensitive lifecycle
// logging" — connect/disconnect/dispatch outcome only, timings, package
// names (already visible in the user's own allowlist). Never notification
// title/text, which is the user's private bank/transaction content.
private const val TAG = "NotifCapture"

/**
 * OS-managed bound service — Android instantiates and binds this once the
 * user grants notification access, and calls onNotificationPosted() for
 * every posted notification system-wide, independent of whether the app's
 * UI is open. See docs/architecture.md "Notification capture — how the app
 * gets invoked".
 *
 * Thin forwarder only: all rule matching lives in Dart (docs/architecture.md
 * table, "Background capture pipeline" row). This just filters by the
 * package allowlist and hands the raw {package, title, text, postTime} off
 * to whichever Dart entry path is available.
 */
class NotificationCaptureListenerService : NotificationListenerService() {
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onListenerConnected() {
        super.onListenerConnected()
        NotificationBridge.saveListenerConnected(applicationContext)
        Log.i(TAG, "Listener connected")
        startForeground(FOREGROUND_NOTIFICATION_ID, buildForegroundNotification())
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        NotificationBridge.saveListenerDisconnected(applicationContext)
        Log.i(TAG, "Listener disconnected")
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    /**
     * Promotes this service's process to foreground priority — see
     * docs/features/background-reliability.md "Foreground service
     * promotion": OEM battery managers (confirmed on Samsung One UI) can
     * still suspend a merely-bound listener service after the device is
     * idle for a while, but leave foreground services alone, same as a
     * music player. The notification itself is low-importance/silent and
     * only exists because Android requires one while a service is
     * foreground — tapping it just reopens the app.
     */
    private fun buildForegroundNotification(): Notification {
        val notificationManager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                FOREGROUND_CHANNEL_ID,
                "Notification capture status",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shows while MoneyManager is listening for bank/app notifications to capture."
                setShowBadge(false)
            }
            notificationManager.createNotificationChannel(channel)
        }

        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(this, FOREGROUND_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("MoneyManager")
            .setContentText("Listening for transaction notifications")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setSilent(true)
            .setContentIntent(contentIntent)
            .build()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName == applicationContext.packageName) return
        val matchAnyApp = NotificationBridge.loadMatchAnyApp(applicationContext)
        if (!matchAnyApp) {
            val allowlist = NotificationBridge.loadAllowlist(applicationContext)
            if (sbn.packageName !in allowlist) return
        }

        val payload = NotificationBridge.toPayload(sbn)
        mainHandler.post {
            val sink = NotificationBridge.activeEventSink
            if (sink != null) {
                // Path 1: a Flutter engine is already running and listening.
                // sink.success() can still silently fail if this is a stale
                // sink left behind by a torn-down engine (see MainActivity's
                // cleanUpFlutterEngine) — fall back to headless rather than
                // lose the notification.
                Log.d(TAG, "Dispatching notification from ${sbn.packageName} (live)")
                try {
                    sink.success(payload)
                } catch (e: Exception) {
                    Log.w(TAG, "Live dispatch failed (${e.message}), falling back to headless")
                    NotificationBridge.activeEventSink = null
                    dispatchHeadless(payload)
                }
            } else {
                // Path 2: app fully closed — spin up a headless engine.
                Log.d(TAG, "Dispatching notification from ${sbn.packageName} (headless)")
                dispatchHeadless(payload)
            }
        }
    }

    private fun dispatchHeadless(payload: Map<String, Any>) {
        val engine = FlutterEngine(applicationContext)
        val loader = FlutterInjector.instance().flutterLoader()
        if (!loader.initialized()) {
            loader.startInitialization(applicationContext)
        }
        loader.ensureInitializationComplete(applicationContext, null)

        // The 2-arg DartEntrypoint constructor resolves the function name
        // against the "main" library (main.dart) only — since
        // notificationCaptureDispatcher lives in its own library file, it
        // has to be named explicitly here, or the engine fails with
        // "Could not resolve main entrypoint function".
        val entrypoint = DartExecutor.DartEntrypoint(
            loader.findAppBundlePath(),
            "package:money_manager/platform/notification_listener/notification_capture_entrypoint.dart",
            "notificationCaptureDispatcher",
        )
        engine.dartExecutor.executeDartEntrypoint(entrypoint)

        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, HEADLESS_CHANNEL)
        var finished = false
        val timeoutRunnable = Runnable {
            if (!finished) {
                finished = true
                NotificationBridge.saveHeadlessDispatchOutcome(applicationContext, "timedOut")
                Log.w(TAG, "Headless dispatch timed out after ${HEADLESS_ENGINE_TIMEOUT_MS}ms")
                engine.destroy()
            }
        }
        mainHandler.postDelayed(timeoutRunnable, HEADLESS_ENGINE_TIMEOUT_MS)

        channel.setMethodCallHandler { call, result ->
            if (call.method == "ready") {
                channel.invokeMethod("process", payload, object : MethodChannel.Result {
                    override fun success(resultValue: Any?) {
                        NotificationBridge.saveHeadlessDispatchOutcome(applicationContext, "succeeded")
                        Log.i(TAG, "Headless dispatch succeeded")
                        teardown()
                    }

                    override fun error(code: String, message: String?, details: Any?) {
                        NotificationBridge.saveHeadlessDispatchOutcome(applicationContext, "failed")
                        Log.w(TAG, "Headless dispatch failed: $code")
                        teardown()
                    }

                    override fun notImplemented() {
                        NotificationBridge.saveHeadlessDispatchOutcome(applicationContext, "failed")
                        Log.w(TAG, "Headless dispatch: method not implemented")
                        teardown()
                    }

                    private fun teardown() {
                        if (!finished) {
                            finished = true
                            mainHandler.removeCallbacks(timeoutRunnable)
                            engine.destroy()
                        }
                    }
                })
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }
}
