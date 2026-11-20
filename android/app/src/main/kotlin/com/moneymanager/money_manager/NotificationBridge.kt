package com.moneymanager.money_manager

import android.app.Notification
import android.content.Context
import android.service.notification.StatusBarNotification
import io.flutter.plugin.common.EventChannel

/**
 * Shared state between MainActivity (the Dart-facing channels) and
 * NotificationCaptureListenerService (the OS-bound listener) — see
 * docs/architecture.md "Notification capture — how the app gets invoked".
 *
 * [activeEventSink] is non-null only while a Flutter engine is alive and
 * actively listening on the event channel (path 1: app open/recently
 * backgrounded). The listener service uses that to decide whether it can
 * forward a notification live, or must spin up a headless engine instead
 * (path 2: app fully closed).
 */
object NotificationBridge {
    private const val PREFS_NAME = "notification_capture"
    private const val ALLOWLIST_KEY = "allowlist_packages"
    private const val MATCH_ANY_APP_KEY = "match_any_app"
    private const val LAST_CONNECTED_AT_KEY = "last_connected_at"
    private const val LAST_DISCONNECTED_AT_KEY = "last_disconnected_at"
    private const val LAST_HEADLESS_OUTCOME_KEY = "last_headless_outcome"
    private const val LAST_HEADLESS_OUTCOME_AT_KEY = "last_headless_outcome_at"

    @Volatile
    var activeEventSink: EventChannel.EventSink? = null

    /** Packages with at least one enabled rule — see
     * docs/features/notification-capture.md "Permission & platform
     * mechanics": avoids processing/forwarding irrelevant notifications. */
    fun loadAllowlist(context: Context): Set<String> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getStringSet(ALLOWLIST_KEY, emptySet()) ?: emptySet()
    }

    /** True when at least one enabled rule has matchAnyApp set — the
     * listener then skips the package-allowlist check entirely. See
     * docs/features/notification-capture.md "Any-app rules". */
    fun loadMatchAnyApp(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getBoolean(MATCH_ANY_APP_KEY, false)
    }

    fun saveAllowlist(context: Context, packages: List<String>, matchAnyApp: Boolean) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putStringSet(ALLOWLIST_KEY, packages.toSet())
            .putBoolean(MATCH_ANY_APP_KEY, matchAnyApp)
            .apply()
    }

    /** See docs/features/background-reliability.md "In-app diagnostics" —
     * timestamps only, read on-demand by the Dart side; never polled. */
    fun saveListenerConnected(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putLong(LAST_CONNECTED_AT_KEY, System.currentTimeMillis()).apply()
    }

    fun saveListenerDisconnected(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putLong(LAST_DISCONNECTED_AT_KEY, System.currentTimeMillis()).apply()
    }

    /** "succeeded" | "failed" | "timedOut" — written exactly when
     * dispatchHeadless() resolves, nothing new runs in the background to
     * produce this. See docs/features/background-reliability.md "Headless
     * dispatch outcome". */
    fun saveHeadlessDispatchOutcome(context: Context, outcome: String) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(LAST_HEADLESS_OUTCOME_KEY, outcome)
            .putLong(LAST_HEADLESS_OUTCOME_AT_KEY, System.currentTimeMillis())
            .apply()
    }

    fun loadListenerDiagnostics(context: Context): Map<String, Any?> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        fun readOrNull(key: String): Long? {
            val value = prefs.getLong(key, -1L)
            return if (value == -1L) null else value
        }
        return mapOf(
            "lastConnectedAt" to readOrNull(LAST_CONNECTED_AT_KEY),
            "lastDisconnectedAt" to readOrNull(LAST_DISCONNECTED_AT_KEY),
            "lastHeadlessOutcome" to prefs.getString(LAST_HEADLESS_OUTCOME_KEY, null),
            "lastHeadlessOutcomeAt" to readOrNull(LAST_HEADLESS_OUTCOME_AT_KEY),
        )
    }

    /** {package, title, text, postTime} — matches CapturedNotification.fromMap
     * on the Dart side (notification_listener_channel.dart). */
    fun toPayload(sbn: StatusBarNotification): Map<String, Any> {
        val extras = sbn.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        return mapOf(
            "package" to sbn.packageName,
            "title" to title,
            "text" to text,
            "postTime" to sbn.postTime,
        )
    }
}
