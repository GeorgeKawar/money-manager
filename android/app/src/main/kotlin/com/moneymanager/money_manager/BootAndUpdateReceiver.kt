package com.moneymanager.money_manager

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.service.notification.NotificationListenerService
import android.util.Log

/**
 * Event-driven only — fires once per boot and once per app update, never on
 * a timer or schedule. Complements (does not replace) MainActivity's
 * launch-time requestRebind(): covers the two cases where nothing opens the
 * app for a long time after the listener binding could have been dropped.
 *
 * Does NOT fix the Samsung "sleeping apps" kill described in
 * docs/features/background-reliability.md — that happens without a reboot
 * or update, so it still needs the user to reopen the app, tap "Recheck",
 * or change the device setting (see the in-app guidance for that).
 */
class BootAndUpdateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }
        try {
            NotificationListenerService.requestRebind(
                ComponentName(context, NotificationCaptureListenerService::class.java),
            )
            Log.i("NotifCapture", "Rebind requested on ${intent.action}")
        } catch (e: Exception) {
            // Best-effort only — nothing to recover from here.
        }
    }
}
