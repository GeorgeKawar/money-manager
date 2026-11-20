# Next steps: build & verify the Samsung notification-capture fix

Picking this up after a usage-limit break. Context below so a fresh session
doesn't need to re-derive it.

## What was just done

Ran a 100-agent arena-skill tournament on: *"when i close the application for
more than 30 minutes, it stops reading notifications, what can we make as a
solution?"* Stopped the tournament short after a partial Round 1 (token
budget) and picked the strongest fully-judged survivor (`a069`) rather than
running all 7 rounds. Applied that solution to the real project. Run record:
`.arena/run-20261111-223220-s782241/` (if still present).

## Files changed (already applied, not yet build-verified)

- `android/app/src/main/kotlin/com/moneymanager/money_manager/MainActivity.kt`
  — `getDeviceManufacturer`, `openOemBackgroundSettings`,
  `tryOpenSamsungBackgroundUsageSettings()`.
- `android/app/src/main/kotlin/com/moneymanager/money_manager/BootAndUpdateReceiver.kt`
  — new file. Event-driven `requestRebind()` on `BOOT_COMPLETED` /
  `MY_PACKAGE_REPLACED`.
- `android/app/src/main/kotlin/com/moneymanager/money_manager/NotificationBridge.kt`
  — `saveHeadlessDispatchOutcome`, `loadListenerDiagnostics` return type
  widened to `Map<String, Any?>`.
- `android/app/src/main/kotlin/com/moneymanager/money_manager/NotificationCaptureListenerService.kt`
  — calls `saveHeadlessDispatchOutcome` at all 4 dispatch resolution points
  (success / error / notImplemented / timeout).
- `android/app/src/main/AndroidManifest.xml` — `RECEIVE_BOOT_COMPLETED`
  permission, `BootAndUpdateReceiver` registration, and a `<queries>` entry
  for `com.samsung.android.lool` (added beyond the arena solution itself —
  needed for `resolveActivity()` to see Samsung's activity under
  package-visibility filtering; a sibling arena attack caught this exact gap
  in a different competitor's near-identical mechanism).
- `lib/platform/notification_listener/notification_listener_channel.dart` —
  `getDeviceManufacturer()`, `openOemBackgroundSettings()`,
  `ListenerDiagnostics.lastHeadlessOutcome` / `lastHeadlessOutcomeAt`.
- `lib/features/notification_capture/presentation/rules_screen.dart` — new
  `_SamsungBackgroundBanner` widget, wired into the existing banner gate via
  `isSamsung`; diagnostics card shows the last headless-dispatch outcome.
- `docs/features/background-reliability.md` — new dated section "Samsung
  One UI follow-up (2026-11-12)".
- `CLAUDE.md` — new decision-log entry for the same date.

**Verified so far (2026-11-13):**
- `flutter analyze` on the whole project — clean, no issues.
- `flutter build apk --debug` — succeeded, so all the new/changed Kotlin
  (`MainActivity.kt`, `BootAndUpdateReceiver.kt`, `NotificationBridge.kt`,
  `NotificationCaptureListenerService.kt`) and the manifest changes compile
  correctly. `build\app\outputs\flutter-apk\app-debug.apk` exists.

**Verified on-device (2026-11-13), on the actual Galaxy S23 Ultra
(SM-S938B) from the bug report:**
- Installed and launched the debug build successfully, no crash.
- Samsung banner renders correctly on the Rules screen, and — critically —
  still shows even though permission + battery-optimization are already
  granted (the FATAL bug class other arena competitors' solutions had was
  avoided here).
- **Found and fixed a real bug during verification**: the hardcoded Samsung
  activity class name in `tryOpenSamsungBackgroundUsageSettings()`
  (`com.samsung.android.sm.ui.battery.BatteryActivity`) does not exist on
  this device's One UI version — confirmed via
  `adb shell dumpsys package com.samsung.android.lool`, which showed the
  real activity is `com.samsung.android.sm.battery.ui.BatteryActivity`
  (segments swapped). Changed the implementation to use the action-based
  intent `com.samsung.android.sm.ACTION_BATTERY` (also confirmed present in
  that dumpsys output) instead of a hardcoded class name, since the action
  is the stable contract and the internal class has evidently already been
  renamed at least once across One UI versions. Rebuilt, reinstalled, and
  confirmed on-device: the button now opens Samsung's real Battery screen
  (`topResumedActivity` confirmed via `adb shell dumpsys activity
  activities`) instead of silently falling back to generic App Info.
- Headless-dispatch diagnostics confirmed working end-to-end: force-stopped
  the app, posted a test notification via
  `adb shell cmd notification post`, and confirmed via
  `adb shell run-as com.moneymanager.money_manager cat
  .../shared_prefs/notification_capture.xml` that `last_headless_outcome`
  updated to `succeeded` with a fresh timestamp — and the Rules screen
  diagnostics card showed the new "Last background capture: succeeded just
  now" line live. No stray test transaction was created (the test
  notification's text didn't match any real rule's regex, so nothing to
  clean up).
- Boot/update receiver confirmed firing on a genuine OS-issued
  `MY_PACKAGE_REPLACED` (triggered naturally by `adb install -r` over the
  existing install, not a spoofed shell broadcast — those are blocked by
  `SecurityException: Permission Denial`, as expected for protected
  broadcasts): logcat showed `Rebind requested on
  android.intent.action.MY_PACKAGE_REPLACED` followed by `Listener
  connected`.

**Still not verified:** the real-world "closed 30+ minutes, does a genuine
bank notification still get captured" repro — that needs actual wait time
on the device, not something this session can simulate.

## To do, in order

1. **Full static analysis**
   ```bash
   flutter analyze
   ```
   Should be clean; if not, the issue is almost certainly in
   `rules_screen.dart` or `notification_listener_channel.dart` from this
   change (new provider, new widget, extended model).

2. **Build the debug APK** (this is the first real test of the Kotlin —
   nothing here has gone through a compiler yet)
   ```bash
   flutter build apk --debug
   ```
   Likely failure modes to check if it fails:
   - `Build.MANUFACTURER` / `android.os.Build` import in `MainActivity.kt`.
   - `Uri.fromParts` import (`android.net.Uri`) in `MainActivity.kt`.
   - `NotificationBridge.loadListenerDiagnostics` return type change
     (`Map<String, Long?>` → `Map<String, Any?>`) — check nothing else in
     the Kotlin codebase still expects the old signature.
   - `BootAndUpdateReceiver` manifest registration (`.BootAndUpdateReceiver`
     resolving to the right package).

3. **Install on the test device and smoke-test the UI**
   ```bash
   flutter install
   ```
   or `flutter run --debug` with the device connected. On the Rules screen:
   - If the device is Samsung: the new "Samsung may still put this app to
     sleep" banner should appear (it's unconditional for
     `Build.MANUFACTURER == "samsung"`, not gated on anything else).
   - Tap its "Open battery settings" button — should open Samsung's Device
     Care battery screen directly (thanks to the `<queries>` fix). If it
     instead opens the generic per-app "App info" screen, the Samsung
     component name (`com.samsung.android.sm.ui.battery.BatteryActivity`)
     may not exist on this One UI version — that's the documented fallback
     working as designed, not a bug, but worth noting which path fired.
   - The diagnostics card should still show "Listener last connected …" as
     before; after a real notification gets headlessly dispatched (app
     fully closed), it should also show a new second line, "Last background
     capture: succeeded <time> ago" (or `failed`/`timedOut`).

4. **Verify the boot/update receiver fires** (can't easily trigger a real
   reboot from `adb` reliably across all devices, so this is best-effort):
   ```bash
   adb shell am broadcast -a android.intent.action.MY_PACKAGE_REPLACED -p com.moneymanager.money_manager
   adb logcat -s NotifCapture:*
   ```
   Look for `Rebind requested on android.intent.action.MY_PACKAGE_REPLACED`.
   Note: some Android versions restrict sending this broadcast to apps other
   than the system, so this may need a real app update or reboot to confirm
   end-to-end on the actual device.

5. **Re-run the original bug repro** (the whole point of this fix): close
   the app fully on the Galaxy S23 Ultra, wait ~30+ minutes without opening
   it, then trigger a notification from an allow-listed app. Confirm the
   transaction lands. If it still doesn't:
   - Check the diagnostics card's new headless-outcome line first — it
     should now say whether headless dispatch ran at all (and how) vs.
     never ran (listener torn down, no outcome recorded).
   - This will only get materially better if the user has actually gone
     into Samsung's Device Care → Battery → Background usage limits and
     added the app to "Never sleeping apps" via the new banner — the app
     cannot force this setting itself (no public API).

6. **Known limitations to keep in mind while verifying** (carried over
   honestly from the arena attack on this solution, not fixed by this
   change):
   - The headless-outcome diagnostic can't distinguish "listener healthy,
     no notification happened to arrive" from "something's actually wrong
     and nothing ran" — both just show no recent outcome line.
   - A foreground service (which might be a stronger mitigation on One UI)
     was deliberately **not** added — it would reopen the no-periodic-work /
     no-foreground-service decision from Phase 9, and is only noted as a
     user-opt-in escalation in `background-reliability.md` if this proves
     insufficient.

## If this doesn't fully fix it

The fallback already documented in `docs/features/background-reliability.md`
"Samsung One UI follow-up" is the foreground-service option — flagged, not
shipped, needs explicit user go-ahead since it reopens a settled decision and
costs a permanent visible notification + battery.
