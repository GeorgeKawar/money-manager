# Roadmap

Phased so each phase is independently testable on a real device before moving on.

## Phase 0 — Project setup
- Flutter project scaffold, folder structure per [architecture.md](architecture.md).
- Drift database setup with empty schema.
- Basic app shell: navigation, theming placeholder (real theme once [design.md](design.md) is provided).

## Phase 1 — Core transaction CRUD (MVP floor) — done
- Accounts + Categories CRUD ([features/categories-accounts.md](features/categories-accounts.md)) — management UI (list, add/edit, archive-with-confirm) verified on-device for both.
- Add/edit/delete transactions ([features/transactions.md](features/transactions.md)).
- Day/week/month/year filtering + income/expense/net summary.
- **This phase alone is a usable manual money-tracking app.**

## Phase 2 — Transfers & recurring — done
- Account-to-account transfers — verified on-device: create, balances update on both legs, appears in Accounts' "Recent transfers", delete reverts both legs.
- Recurring transaction definitions + lazy generation-on-launch ([features/recurring-transactions.md](features/recurring-transactions.md)) — verified on-device: create with a past start date, app-relaunch catch-up backfills every missed occurrence and advances `next_run_date` past all of them, pause/resume toggle, edit (start date read-only), delete (independent of already-generated transactions).

## Phase 3 — Notification capture — done
- Native `NotificationListenerService` + platform channel plumbing (live EventChannel path + headless `FlutterEngine` dispatch path for when the app is fully closed) — both verified on-device.
- Rule engine (regex matching, Dart-side) + rule editor UI with live test tool — verified on-device.
- Review queue screen (confirm/discard/edit) + per-rule auto-add vs. review-queue + duplicate protection — verified (review-queue UI on-device; insert/dedupe/auto-add logic via [notification_capture_service_test.dart](../test/notification_capture/notification_capture_service_test.dart), see note below on why).
- Rule enable/disable toggle, edit, delete — verified on-device.
- **Known limitation found during on-device testing, not fixable in-app**: see [features/notification-capture.md](features/notification-capture.md) "Known limitation: OS-level content redaction" — Android 15+ can withhold a notification's real text from this listener for notifications it classifies as sensitive, which is exactly the kind of content bank transaction alerts are. There's no app-level workaround (the bypass permission is restricted to system-signed apps/OS roles). The app detects when this happens and shows an in-app hint; this is also why most of this phase's pipeline verification (insert/dedupe/auto-add) had to be done via a deterministic service-level test rather than live on-device notifications, which this emulator's OS build redacts unconditionally.
- Deliberately scoped out: notification-rule **presets** (no real sample notification text from the user yet) and a native "installed apps" picker for the rule editor (manual package-name entry used instead, per the doc's own allowance — avoids Android 11+ package-visibility complexity).
- **Follow-up (2026-11-02)**: extended the rule model with any-app matching, explicit/reorderable rule priority (first match wins, by priority order rather than creation order), and optional date/note/name capture groups (date overrides the notification's post time when set; name falls back to the rule's own name so the transaction note is never blank) — see [features/notification-capture.md](features/notification-capture.md) "Any-app rules" and "Matching details". First real Drift schema migration (`schemaVersion` 1 → 2).

## Phase 4 — Polish & reports — done
- Category breakdown (donut chart + legend, Income/Expense toggle) and account breakdown (proportional bar rows, net income-minus-expense) added to the dashboard, scoped to the existing period selector — see [features/reports.md](features/reports.md). Verified on-device: added a transaction, both breakdowns update live, switching the Income/Expense toggle and the period selector all reflect correctly.
- **Dependency fix found during this phase**: `fl_chart ^1.1.0` (declared in `pubspec.yaml` since project setup but never actually used until now) fails to compile against this project's Flutter SDK — see `architecture.md`'s tech-stack table. Downgraded to `^0.69.2`.
- Any further day-to-day refinements: none identified yet.

## Phase 5 — Local data import/export — done
- Replaces the earlier "cloud backup via Google Drive/Firebase" plan — per user decision (2026-11-06), no account/sign-in/network call at all; the user exports a file via Android's own file picker and imports it back later. Shipped with the JSON approach and replace (not merge) semantics — see [features/data-import-export.md](features/data-import-export.md). `BackupRepository` exports all tables + settings to a versioned JSON document and restores them atomically inside one transaction, preserving row ids so foreign keys resolve correctly; malformed/incompatible files are rejected with a typed `BackupFormatException` before anything is touched. Verified on-device: exported via the Settings screen to Downloads through the system Save dialog, confirmed the file's content, then re-imported it through the system Open dialog — the confirmation dialog showed the correct record counts and export time, and the dashboard's data was unchanged after the replace.

## Phase 6 — Settings side-drawer navigation — done
- Swipe-from-left-edge (or the gear icon) opens Settings as a slide-in `Drawer` panel instead of a full-screen push. See [features/settings-drawer.md](features/settings-drawer.md). `settings_screen.dart` was renamed to `settings_drawer.dart`; the old push-only `SettingsScreen` is gone, replaced by `SettingsDrawer`. Verified on-device: gear icon opens the drawer with the expected scrim/partial-width look, and tapping a row (tested with Review queue) closes the drawer then pushes the screen correctly.

## Phase 7 — Dark/light mode toggle — done
- Exposes the theme-mode infrastructure that already existed (`AppTheme`, `AppColors`, `themeModeProvider`, `settingsRepository.setThemeMode()`) as an actual Settings control — see [features/theming.md](features/theming.md). A System/Light/Dark segmented control was added to the Settings drawer (no new data-model/provider work needed, as expected). Verified on-device: switching to Dark instantly re-themed the drawer, the dimmed dashboard behind it, the dashboard itself, and the add-transaction sheet, with no contrast or hardcoded-color issues found.

## Phase 8 — Notification-rules-only export/import — done
- A second, narrower export/import path: back up and restore just the `NotificationRule` table, separate from the existing full-database export/import (Phase 5, unchanged — still exports/imports everything and still replaces all data on import). See [features/rules-import-export.md](features/rules-import-export.md) for the full plan and the decisions finalized during implementation. `RulesBackupRepository` exports every rule plus its resolved account/category **names**; import resolves each by case-insensitive name match against the destination device, skipping (not auto-creating) anything unresolvable, and skipping exact duplicates (same name + app scope + regex) — everything else is appended after the device's existing rules, never replacing them. A distinct `"fileType": "money_manager_rules_export"` marker (and recognizing Phase 5's own shape) lets each importer reject the other's file with a specific message. Verified on-device: exported via the new "Export rules" row to Downloads, confirmed the file's content (resolved account name included), re-imported the same file to see it correctly flagged as "1 already exist here and will be skipped", then imported a crafted file with one resolvable and one unresolvable-account rule and confirmed only the resolvable one was inserted (appended at the next priority) while the other was skipped with its missing account name named in the summary.

## Phase 9 — Background notification-capture reliability — done
- Addresses the user report "if the application is closed, it doesn't read notifications," with an explicit constraint: none of it may drain battery (no polling, no foreground service). See [features/background-reliability.md](features/background-reliability.md) for the full investigation and implementation. A 2026-11-06 investigation first reproduced the scenario via `adb` (force-stop, then a test notification) and confirmed the existing headless capture path (Phase 3) works correctly on stock Android — the real-world gap is most likely OEM-specific battery/autostart restrictions on real devices, not a bug in the capture pipeline itself. Shipped: a defensive `requestRebind()` on `MainActivity` launch (and on-demand via a "Recheck" button) that's a no-op when the listener is already healthily bound; a battery-optimization banner on the Rules screen linking to the OS's generic battery-settings list (not the direct-exemption intent, to avoid Play Store policy risk); an in-app diagnostics card showing last listener connect time (native `SharedPreferences`, checked on-demand only, never polled); and non-sensitive lifecycle logging (`NotifCapture` tag — connect/disconnect/dispatch-outcome only, never notification content). Verified on-device: re-ran the original force-stop repro with the new logging and confirmed the full chain in `adb logcat`, confirmed the inserted transaction, and confirmed the battery banner/diagnostics card/recheck button all behave correctly (including the OS declining a redundant rebind when already bound).

## Later / not yet scheduled
- iOS build (app already designed to not block this, but no iOS-specific work — e.g. iOS has no equivalent to `NotificationListenerService`, so notification capture would need an iOS-specific fallback design or an iOS limitation disclosed to the user).
- Multi-currency conversion.
- Subcategories.
- Custom recurring intervals.
- Background-exact-time recurring generation (WorkManager) instead of lazy-on-launch.

## Open decisions to resolve before/at the relevant phase
- Minimum Android SDK version (default assumption: 24+, see [architecture.md](architecture.md)).
- Preset notification rules — need real sample notification text (Phase 3).
- Visual design / IA — pending [design.md](design.md) delivery; should ideally land before or during Phase 1 so screens are built against real layouts instead of placeholders.
