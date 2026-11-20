# Feature: Background notification-capture reliability

## Status

Done — see [roadmap.md](../roadmap.md) Phase 9.

## Problem reported

User report (2026-11-06): "if the application is closed, it doesn't read notifications" — bank/app notifications received while the app isn't open don't turn into transactions (confirmed or review-queue).

## What's already in place (Phase 3)

Per [architecture.md](../architecture.md) and [notification-capture.md](notification-capture.md), the app already has two capture paths, both shipped in Phase 3:

1. **Live path**: an `EventChannel` to the already-running Flutter engine, used when the app is open/recently backgrounded.
2. **Headless path**: when no engine is listening, the native `NotificationCaptureListenerService` spins up a background `FlutterEngine` on demand and runs a separate Dart entrypoint (`notificationCaptureDispatcher` in [notification_capture_entrypoint.dart](../../lib/platform/notification_listener/notification_capture_entrypoint.dart)) that does the same rule-matching and insert as the live path, then tears the engine down.

The roadmap already recorded this headless path as "verified on-device" from Phase 3. This phase's investigation (below) re-confirms that specific claim and locates where the real gap is.

## Investigation (2026-11-06)

Reproduced end-to-end via `adb` on the dev emulator (stock Android/AOSP, no OEM customization):

1. Force-stopped the app (`adb shell am force-stop com.moneymanager.money_manager`) and confirmed via `adb shell ps -A` that its process was fully dead.
2. Posted a test notification matching an enabled rule's package + regex: `adb shell "cmd notification post -t TestBank tag 'TESTAMT 88.10 debited'"` (package defaults to `com.android.shell`, which was already allowlisted by an existing rule).
3. Added temporary `Log.d`/`developer.log` calls through the native listener and the headless Dart entrypoint (removed again once the investigation was done — see "Diagnostics gap" below) and confirmed, via `adb logcat`, the full chain: `onNotificationPosted` fired → passed the allowlist check → the OS had already restarted the app's process specifically to rebind the listener service → `dispatchHeadless()` created a new `FlutterEngine` → the Dart entrypoint ran → the `ready`/`process` handshake completed → `NotificationCaptureService.handle()` returned successfully.
4. Confirmed directly in the SQLite database (`run-as com.moneymanager.money_manager sqlite3 .../money_manager.sqlite`) that a new `transactions` row was inserted: correct amount, account, `source='notification'`, `source_rule_id` set, and `is_pending_review` matching the rule's `auto_add` setting.

**Conclusion: the headless mechanism itself works correctly on stock Android, including immediately after a force-stop.** This is not a reproducible code bug in this environment — the Android OS's own `NotificationListenerService` rebind behavior brought the process back specifically to redeliver the notification, and the existing Phase 3 pipeline handled it correctly once invoked.

## Likely real-world cause

Given the mechanism works correctly here, the most likely explanation for the user's report is **OEM-specific background/battery restrictions** that go beyond stock Android:

- Many manufacturer Android skins (Xiaomi MIUI, Huawei EMUI/HarmonyOS, Oppo ColorOS, Vivo FuntouchOS, Samsung's "Put unused apps to sleep" / adaptive battery, OnePlus OxygenOS, and others) layer their own aggressive process-killing and "autostart" restrictions on top of AOSP's, specifically to save battery — and these frequently override or ignore the OS-level listener-rebind behavior this app relies on. This is a well-known class of issues affecting any Android app with background work, not specific to notification listeners (see https://dontkillmyapp.com for a catalog of per-manufacturer behaviors — external reference for context, not a dependency).
- A plain device **reboot** is a separate known edge case: on some Android versions/OEMs, a `NotificationListenerService` binding isn't automatically re-established after boot until something nudges the system to recheck it (the permission grant itself persists, but the active binding may not) — the standard mitigation is calling `NotificationListenerService.requestRebind()`.
- Doze mode / App Standby buckets are less likely to fully block delivery (listener-binding delivery isn't deferred the way `WorkManager`/`AlarmManager` scheduled work is), but a deprioritized standby bucket can still delay process creation under memory pressure.

None of this is fixable purely from Dart or from inside this app's own process — it needs native-side defensive measures, and in several cases, the user's own device settings.

This is a different limitation from the one already documented in [notification-capture.md](notification-capture.md) "Known limitation: OS-level content redaction" — that one is about content being withheld *after* successful delivery; this one is about delivery/process-wake not happening at all on some devices.

## Diagnostics gap found during investigation

Neither the native listener nor the headless Dart entrypoint logs anything today. When headless dispatch succeeds, fails, or times out, there's currently zero visibility into which happened — on a dev machine via `adb logcat`, or for the user on their own device. This made the investigation above slower than it needed to be, and leaves the user with no way to self-diagnose ("is my phone blocking this?") from inside the app. Addressing this is part of this phase's proposed scope, without logging raw notification text (that's the user's bank/transaction content, not safe to log even locally).

## Resolution (implemented 2026-11-06)

All five proposed mitigations shipped, with an explicit constraint carried through every decision below: **nothing here may drain battery** — no periodic/polling background work, no foreground service, every check is event-driven or on-demand only.

1. **Self-healing rebind**: `MainActivity.requestListenerRebind()` calls `NotificationListenerService.requestRebind(ComponentName)` once in `configureFlutterEngine` on every launch, wrapped in try/catch (harmless no-op if the service isn't registered yet). Also exposed on demand via the new `requestRebind` method-channel call, for the in-app "Recheck" button (item 3). **Not periodic** — confirmed via on-device testing that the OS declines a rebind request outright when the listener is already healthily bound (logged: `NotificationManagerService$NotificationListeners: Not registering ... is already bound`), so calling it costs nothing when there's nothing to fix.
2. **Battery-optimization exemption prompt**: `isIgnoringBatteryOptimizations` (native, via `PowerManager`) checked on-demand only (screen view / app resume / manual recheck — see `_batteryOptimizationIgnoredProvider` in `rules_screen.dart`, a `FutureProvider.autoDispose`, never polled). When not exempt, a banner on the Rules screen explains why and links to `openBatteryOptimizationSettings`, which deep-links to `Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS` — the generic settings-list page, **not** `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (decided against: that intent's exemption is restricted under Play Store policy to apps with a justified always-on need, which this app isn't). Verified on-device: the button opens the OS's actual "App battery usage" list.
3. **In-app diagnostics**: a small always-visible card on the Rules screen reads `getListenerDiagnostics()` (native `SharedPreferences`, via the existing `notification_listener` method channel — no new DB schema) and shows "Listener last connected `<relative time>`" or "not yet connected this install", plus a manual "Recheck" button that calls `requestRebind()` and shows a confirmation snackbar. Re-checked on app resume alongside the permission/battery checks, never polled.
4. **Non-sensitive lifecycle logging**: `NotificationCaptureListenerService` logs (tag `NotifCapture`) `onListenerConnected`/`onListenerDisconnected`, which dispatch path was taken (live vs. headless) with the source package name only, and the headless dispatch outcome (succeeded/failed/timed out) — never notification title/text. Verified via `adb logcat -s NotifCapture:*` during the re-run of the original force-stop repro (see below) — this is exactly the diagnosability gap the original investigation hit.
5. **Document the limitation for the user**: done — see [notification-capture.md](notification-capture.md) "Known limitation: background delivery on some devices" (already cross-referenced this doc; no change needed there beyond what already existed).

**Re-verification (2026-11-06, same session)**: re-ran the original investigation's exact repro (force-stop, then `adb shell cmd notification post` a matching test notification) with the new logging in place. Confirmed via `adb logcat`: `Dispatching notification from com.android.shell (headless)` → `Headless dispatch succeeded`, and the resulting row landed correctly in `transactions` (confirmed via direct SQLite read, then deleted along with the temporary test rule used to produce it). Also forced an actual disconnect/reconnect via `adb shell cmd notification disallow_listener`/`allow_listener` and confirmed both the `Listener disconnected`/`Listener connected` log lines and the persisted timestamps in `shared_prefs/notification_capture.xml` updated correctly, and that the Rules screen diagnostics card reflected it ("last connected just now" → "1m ago" after resume-triggered recheck).

### Samsung One UI follow-up (2026-11-12)

User report: Galaxy S23 Ultra (SM-S938B), capture stops ~30 minutes after the app is closed, resumes on reopen. 30 minutes is too short for stock Doze/App Standby, and points instead at One UI's own "Background usage limits" ("sleeping apps") classifier, which is independent of the standard Android battery-optimization exemption already prompted for. Two sub-cases are possible — binding torn down (nothing fires) vs. binding alive but headless dispatch blocked/slow (times out) — previously indistinguishable without `adb logcat`.

Added, without reopening the no-periodic-work decision: (1) a Samsung-specific banner guiding the user to Device Care's background-usage-limits screen, best-effort deep-linked with a safe fallback to the standard App Info screen; (2) a `BOOT_COMPLETED`/`MY_PACKAGE_REPLACED` receiver calling `requestRebind()` — event-driven, fires once per occurrence, not a timer, closes the reboot/update gap the original launch-only rebind couldn't; (3) persisted + surfaced last headless-dispatch outcome (succeeded/failed/timedOut) next to the existing "last connected" diagnostic, so the two sub-cases are now distinguishable from the phone itself.

Considered and **not adopted**: a foreground service to signal "in use" to One UI's classifier. Plausible given this is OEM-specific evidence rather than the stock-Android finding Phase 9 was based on, but still crosses the explicit no-foreground-service decision and the non-goal below for a benefit that isn't confirmed on this device yet. Revisit only if A/B/C above are confirmed insufficient in practice and the user explicitly opts in to the trade-off.

Still not fixable from inside the app: Samsung's "sleeping apps" bucket membership can't be read or set programmatically; RAM-pressure process kills on heavily-used devices can't be prevented by a non-system app.

### Foreground service promotion (2026-11-14)

User report: notifications received overnight (phone asleep for hours, app closed) were still missed, confirming the 30-minutes-closed symptom from the Samsung follow-up above actually recurs over longer idle periods, and that items 1–4 above aren't sufficient on their own.

This reopens the no-foreground-service non-goal below — per explicit user request, given the Samsung follow-up's own "revisit only if... the user explicitly opts in" condition is now met. `NotificationCaptureListenerService.onListenerConnected()` now calls `startForeground()` with a low-importance (`IMPORTANCE_LOW`), silent, ongoing notification ("MoneyManager — Listening for transaction notifications"), and `onListenerDisconnected()` calls `stopForeground()`. This promotes the listener's process to foreground priority — the same mechanism a music player uses to survive backgrounding — which OEM battery managers (including Samsung's "sleeping apps" classifier) are designed to leave alone, unlike a merely-bound service.

- **Manifest**: `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_SPECIAL_USE` + `POST_NOTIFICATIONS` permissions added; the listener service declares `android:foregroundServiceType="specialUse"` with a `PROPERTY_SPECIAL_USE_FGS_SUBTYPE` justification string — `specialUse` because none of Android 14's other foreground-service types ("keep a notification listener alive") fit, and this app isn't moving data to/from a server (`dataSync`), recording media, etc. If this app is ever submitted to the Play Store, `specialUse` foreground services require a declared-use justification in Play Console — not needed for local builds/sideloading.
- **Notification permission**: `MainActivity.requestNotificationPermissionIfNeeded()` requests `POST_NOTIFICATIONS` once per launch (Android 13+) — without it, the foreground promotion still takes effect, it just has no visible notification, so this is a best-effort visibility improvement, not load-bearing for the mechanism itself.
- **Trade-off accepted**: a permanent, low-priority notification icon while the notification-access permission is granted — this is the cost of the reliability gain, and is visible to the user by design (so they know the app is actively listening), not a bug.
- **Not revisited**: items 1–4 above and the non-goal of a separate always-on foreground service unrelated to the listener itself — this reuses the listener service's own process rather than adding a second one.

This was selected from an abbreviated [arena-skill](https://github.com/Jakeschincariol/arena-skill) tournament (100 solutions spawned, Round 1 partially judged — 10 of 50 matches fully cross-attacked — then stopped short to save budget rather than running all 7 rounds). It was the only solution in the fully-judged subset to survive its match with zero fatal attacks; one unresolved MAJOR critique from that match worth tracking if this doesn't fully resolve the symptom: the new headless-outcome diagnostic can't distinguish "listener healthy, no notification happened to arrive" from "listener healthy but something's actually wrong," since both read as "no recent outcome."

**On-device verification (2026-11-13), on the real Galaxy S23 Ultra from the bug report, found and fixed one real bug**: the deep link's hardcoded Samsung activity class name (`com.samsung.android.sm.ui.battery.BatteryActivity`) does not exist on this device's One UI version — confirmed via `adb shell dumpsys package com.samsung.android.lool`, which lists the real activity as `com.samsung.android.sm.battery.ui.BatteryActivity` (segments swapped). `tryOpenSamsungBackgroundUsageSettings()` in `MainActivity.kt` now uses the action-based intent `com.samsung.android.sm.ACTION_BATTERY` (also present in that dumpsys output) instead, since the action is the stable public contract and the internal activity class has evidently already been renamed at least once across One UI versions. Re-verified on-device after the fix: the button now opens Samsung's real Battery screen instead of silently falling back to the generic App Info screen. The banner's correct rendering, the headless-outcome diagnostics (forced via `adb shell cmd notification post` after a force-stop), and the boot/update receiver (fired by a genuine OS `MY_PACKAGE_REPLACED` from `adb install -r`, not a spoofed broadcast — those are blocked by Android as protected) were all confirmed working as designed. Not yet verified: the actual 30-minutes-closed repro, which needs real wait time on the device.

### Stale live-dispatch sink fix (2026-11-14)

User report, same day as the foreground-service change above: notifications still missed, now reproducing even right after a fresh app launch/foreground — not an idle-period symptom at all, so a separate bug from everything above.

Diagnosed via temporary `Log.d`/`print` instrumentation through the whole native→Dart chain plus `adb logcat`: the native listener's `Log.d(TAG, "Dispatching ... (live)")` fired correctly for the missed notification (and for an unrelated one dispatched moments later), but the Dart-side event-stream listener in `app.dart` never logged receiving either of them — ruling out anything PushMe-specific and pointing at the native→Dart handoff itself.

Root cause: `NotificationBridge.activeEventSink` (set by `MainActivity`'s `EventChannel.onListen`, meant to be cleared by `onCancel`) can go stale. Flutter's engine teardown (Activity/engine destroyed — e.g. task removed from Recents) doesn't reliably invoke `onCancel`, so the sink can keep pointing at a dead engine. This was always theoretically possible, but rarely observed before because the whole *process* usually died along with the engine; the foreground service added hours earlier in the same session keeps the process alive well past engine teardown, which made the stale-sink window far easier to hit. The listener's `sink != null` check passed on a dead sink, so it took the "live" branch and called `.success()` on it, which silently swallowed the notification (no crash, no error) instead of falling through to headless dispatch.

Fix: `MainActivity.cleanUpFlutterEngine()` (the mirror of `configureFlutterEngine()`) now explicitly clears `NotificationBridge.activeEventSink = null` whenever this Activity's engine is torn down, so a dead engine can't leave a stale sink behind. As a safety net, `onNotificationPosted()`'s live-dispatch call is now wrapped in try/catch — if `sink.success()` ever still fails, it clears the sink and falls back to headless dispatch rather than losing the notification. Verified on-device: user confirmed capture now works after closing the app and sending a new notification.

## Scope (implemented)

- Native: `MainActivity.kt` (`requestListenerRebind()` on launch + on-demand; `isIgnoringBatteryOptimizations`/`openBatteryOptimizationSettings`/`getListenerDiagnostics`/`requestRebind` method-channel handlers; `cleanUpFlutterEngine()` clearing the stale-sink window), `NotificationBridge.kt` (`saveListenerConnected`/`saveListenerDisconnected`/`loadListenerDiagnostics` SharedPreferences helpers), `NotificationCaptureListenerService.kt` (`onListenerConnected`/`onListenerDisconnected` overrides + lifecycle/dispatch-outcome logging; try/catch fallback to headless on a failed live dispatch).
- Dart: `notification_listener_channel.dart` (`ListenerDiagnostics`, `isIgnoringBatteryOptimizations`, `openBatteryOptimizationSettings`, `getListenerDiagnostics`, `requestRebind`), `rules_screen.dart` (`_BatteryBanner`, `_ListenerDiagnosticsCard`, two new `FutureProvider.autoDispose` providers re-checked on app resume).
- No `AndroidManifest.xml` changes needed — the chosen battery-settings intent requires no special permission declaration.

## Non-goals

- Replacing `NotificationListenerService` with a different capture mechanism — there isn't a more reliable one available to a non-system app on Android.
- A **separate** always-on foreground service/process just to keep the app alive — superseded 2026-11-14 (see "Foreground service promotion" above) by promoting the existing listener service itself to foreground, rather than adding a second service. The original reasoning (battery drain, persistent notification, marginal gain given OS-managed rebinding) held until real-world evidence (a Samsung device, and later an overnight-idle report) showed the OS-managed rebinding path alone isn't sufficient on this hardware.
- Working around every individual OEM's battery manager programmatically — not reliably possible from a normal (non-system-signed) app. This phase mitigates (rebind, exemption prompt) and makes the remaining risk visible (diagnostics, documentation) rather than attempting to eliminate it entirely.
