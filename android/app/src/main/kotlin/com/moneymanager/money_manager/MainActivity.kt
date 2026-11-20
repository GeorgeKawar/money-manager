package com.moneymanager.money_manager

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.service.notification.NotificationListenerService
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

private const val METHOD_CHANNEL = "com.moneymanager.money_manager/notification_listener"
private const val EVENT_CHANNEL = "com.moneymanager.money_manager/notification_listener/events"

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // See docs/features/background-reliability.md "Self-healing rebind"
        // — a defensive nudge, once per app launch only (never periodic,
        // so this costs nothing in the background). Harmless no-op if the
        // service isn't registered yet (e.g. permission never granted).
        requestListenerRebind()

        // See docs/features/background-reliability.md "Foreground service
        // promotion" — the listener service's persistent notification
        // (Android 13+) needs this runtime permission to actually be
        // visible; without it the foreground promotion itself still takes
        // effect, it just has no visible notification. Once per launch,
        // same as requestListenerRebind() above.
        requestNotificationPermissionIfNeeded()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isPermissionGranted" -> {
                    val enabled = NotificationManagerCompat.getEnabledListenerPackages(this)
                    result.success(enabled.contains(packageName))
                }
                "openNotificationAccessSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(null)
                }
                "updateAllowlist" -> {
                    @Suppress("UNCHECKED_CAST")
                    val packages = call.argument<List<String>>("packages") ?: emptyList()
                    val matchAnyApp = call.argument<Boolean>("matchAnyApp") ?: false
                    NotificationBridge.saveAllowlist(applicationContext, packages, matchAnyApp)
                    result.success(null)
                }
                "isIgnoringBatteryOptimizations" -> {
                    val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(powerManager.isIgnoringBatteryOptimizations(packageName))
                }
                "openBatteryOptimizationSettings" -> {
                    // Deep-links to the OS's own generic settings list rather
                    // than requesting direct exemption — see
                    // background-reliability.md "Open decisions": avoids
                    // Play Store policy risk tied to the direct-request intent.
                    startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                    result.success(null)
                }
                "getListenerDiagnostics" -> {
                    result.success(NotificationBridge.loadListenerDiagnostics(applicationContext))
                }
                "requestRebind" -> {
                    requestListenerRebind()
                    result.success(null)
                }
                "getDeviceManufacturer" -> {
                    // Lets Dart decide whether to show the Samsung-specific
                    // guidance banner below — no public cross-platform API
                    // tells us whether this app is in One UI's "sleeping
                    // apps" bucket, so the app guides rather than detects.
                    result.success(Build.MANUFACTURER?.lowercase() ?: "")
                }
                "openOemBackgroundSettings" -> {
                    if (!tryOpenSamsungBackgroundUsageSettings()) {
                        // Fallback: standard, documented, always-available
                        // per-app settings screen. From there "Battery" ->
                        // "Background usage limits" is a couple of taps —
                        // communicated in the banner copy, since the public
                        // API doesn't let us deep-link past this screen.
                        startActivity(
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.fromParts("package", packageName, null)
                            },
                        )
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    NotificationBridge.activeEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    NotificationBridge.activeEventSink = null
                }
            },
        )
    }

    /**
     * Mirror of configureFlutterEngine, called when this Activity's engine
     * is about to be destroyed. Flutter's EventChannel plumbing doesn't
     * reliably invoke onCancel on engine teardown (it's driven by the Dart
     * stream's own cancellation, not by engine lifecycle), so without this
     * [NotificationBridge.activeEventSink] can be left pointing at a dead
     * sink from this now-gone engine. That used to mostly self-correct
     * because the whole process died with the engine — now that the
     * notification listener's foreground service (see
     * docs/features/background-reliability.md "Foreground service
     * promotion") keeps the process alive past engine teardown, a stale
     * sink can live on and silently swallow live dispatches. Clearing it
     * here makes the listener correctly fall back to headless dispatch
     * instead.
     */
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        NotificationBridge.activeEventSink = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun requestListenerRebind() {
        try {
            NotificationListenerService.requestRebind(
                ComponentName(this, NotificationCaptureListenerService::class.java),
            )
        } catch (e: Exception) {
            // Best-effort only — nothing to recover from here.
        }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
    }

    /**
     * Samsung's Device Care "Battery" screen — not a public/documented
     * Android API (there is no AOSP equivalent of One UI's "sleeping apps"
     * list). Uses the action Samsung's own Device Care package registers
     * for this screen (`com.samsung.android.sm.ACTION_BATTERY`, confirmed
     * via `adb shell dumpsys package com.samsung.android.lool` against a
     * real Galaxy S23 Ultra) rather than an internal activity class name —
     * on-device testing found the hardcoded class name this originally
     * used (`com.samsung.android.sm.ui.battery.BatteryActivity`) does not
     * exist on this device's One UI version, which actually exposes
     * `com.samsung.android.sm.battery.ui.BatteryActivity` instead; the
     * action is the stable contract, not the implementation class, which
     * One UI has evidently renamed at least once already. Wrapped so that
     * if a future One UI version drops this action too, this just returns
     * false and the caller falls back to the standard App Info screen —
     * never crashes, never silently does nothing.
     */
    private fun tryOpenSamsungBackgroundUsageSettings(): Boolean {
        return try {
            val intent = Intent("com.samsung.android.sm.ACTION_BATTERY").apply {
                setPackage("com.samsung.android.lool")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (packageManager.resolveActivity(intent, 0) != null) {
                startActivity(intent)
                true
            } else {
                false
            }
        } catch (e: Exception) {
            false
        }
    }
}
