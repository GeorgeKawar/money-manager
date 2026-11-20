# Architecture

## Tech stack

| Layer | Choice | Why |
|---|---|---|
| UI framework | Flutter (Dart, stable channel) | One codebase for Android now, iOS later. Rich widget set for custom charts/filter UI. |
| State management | Riverpod | Testable, compile-safe DI, good fit for a local database + background notification stream feeding the UI reactively. |
| Local database | Drift (`drift` package, SQLite under the hood) | Type-safe SQL, real migrations, good for relational data (transactions ↔ categories ↔ accounts ↔ rules). Preferred over Isar/Hive because the data is inherently relational and we'll want ad-hoc aggregate queries (sums per category/month/year). |
| Notification access | Native Android `NotificationListenerService` (Kotlin) + a Flutter platform channel (or a thin custom plugin) | Flutter has no cross-platform notification-reading API; this is inherently platform-specific. Isolating it behind a plugin interface means iOS can later get its own (much more limited) implementation or a documented "not supported on iOS" fallback without touching shared code. |
| Background capture pipeline | Android `NotificationListenerService` (OS-managed bound service, event-driven — no polling/WorkManager) → Dart-side rule engine (same code path regardless of entry) → local DB write (direct or into review queue) | Keeps parsing/regex logic in Dart (shared, testable) rather than duplicated in Kotlin; Kotlin side only forwards raw notification text + source package. See "Notification capture — how the app gets invoked" below for the two entry paths. |
| Charts/summaries | `fl_chart` (or similar Flutter charting package) | Rendering income/expense breakdowns and trend charts for the filter views. Pinned to `^0.69.2`, not latest (`1.x`): `1.x`'s `CustomInteractiveViewer` calls `Matrix4.translateByDouble`/`scaleByDouble`, added in `vector_math` 2.3.0, but this project's Flutter SDK (3.32.7) pins `vector_math` 2.1.4 via the `flutter` package itself — `1.x` fails to compile against it. Revisit once the Flutter SDK is upgraded past whatever version first bundles `vector_math` 2.3.0+. |
| Theming | Single Flutter `ThemeData` pair (light + dark) generated from one semantic color-token file | Required: light/dark mode support, and the palette must be swappable later by editing one file. See [design.md](design.md) theming section for the token list. No hardcoded colors in widgets — always read from `Theme.of(context)`/the token file. |
| Local data import/export | File export/import via Android's Storage Access Framework (`file_picker` package), no account or network call | Shipped in Phase 5; see [features/data-import-export.md](features/data-import-export.md). Replaced an earlier Google Drive/Firebase cloud-backup plan per user decision (2026-11-06) — keeps the "no account required, ever" guarantee. JSON export, replace (not merge) semantics. |
| App icon / splash screen | `flutter_launcher_icons` + `flutter_native_splash`, generated from source images in `assets/icon/` | Per user request (2026-11-06): a mint-green coin-with-"$" mark, built from the app's own palette (`AppPalette.accent` #8FE3B3 / `accentDark` #5FBE8C / dark bg #0C120E) rather than a generic placeholder. `assets/icon/icon.png` (legacy launcher icon) + `icon_foreground.png` (adaptive icon foreground, transparent bg) + `splash_logo.png` (native splash) are source-of-truth; regenerate Android resources after changing any of them with `dart run flutter_launcher_icons` and `dart run flutter_native_splash:create` (config lives in `pubspec.yaml`). |

## App layers

```
lib/
  main.dart
  app/                     # App-wide setup: routing, theming, DI providers root
                            #   main_screen.dart — root nav shell (bottom NavigationBar + IndexedStack of the 3 tabs)
  core/
    database/              # Drift database, DAOs, migrations
    utils/                 # Date range helpers (day/week/month/year), currency formatting
  features/
    transactions/
      data/                # Repository implementations over Drift DAOs
      domain/              # Entities, use-cases (add/edit/delete, filter/query)
      presentation/        # Screens, widgets, Riverpod providers/controllers
    categories/
    accounts/
    notification_capture/
      data/                # Rule repository, review-queue repository
      domain/               # Rule entity, matching/regex engine, use-cases
      presentation/         # Rule editor UI, review queue UI
    recurring/
    reports/
      data/                # ReportsRepository — category/account breakdown queries, scoped to the dashboard's active period
      presentation/        # Breakdown chart/list widgets + the category breakdown's income/expense toggle provider
    settings/
  platform/
    notification_listener/ # Dart-side wrapper around the native plugin's event channel
android/
  app/.../NotificationListenerService.kt   # Native listener, package allowlist, forwards raw text
```

This is a standard "feature-first" Flutter structure: each feature owns its data/domain/presentation, and cross-feature code lives in `core/`. Keeps notification-capture (the most platform-specific, riskiest feature) isolated so it can be developed/tested independently of the core transaction CRUD.

## Navigation

Resolved 2026-11-13 (previously tentative), per user request — `MainScreen` (`lib/app/main_screen.dart`) is the app's root: a single `Scaffold` with a 3-item `NavigationBar` and an `IndexedStack` body (so each tab keeps its scroll position/state when switching away and back):
- **Transactions** (`TransactionsTab`) — the old single-screen Dashboard's greeting/currency header, all-time balance card, and period filter (day/week/month/year/custom), plus the transaction list for that period. Replaces the old 10-at-a-time "Load more"/"Show all" design (2026-11-13) with true infinite scroll: the list reveals more items client-side as the user scrolls near the bottom (`ScrollController` + a visible-count threshold), rather than a button or a separate screen.
- **Reports** (`ReportsTab`) — the period filter again (same shared `activeDateRangeProvider`, so it stays in sync with the Transactions tab) plus the Cash flow/By category/By account breakdowns that used to sit below the transaction list on the old Dashboard.
- **Accounts** (`AccountsScreen`, unchanged) — now a primary tab instead of a Settings-drawer row.
- **Settings** — accounts, categories, notification rules, backup, appearance. Opened via a left-edge swipe or the gear icon (now on the Transactions tab's header), both opening `SettingsDrawer` as a slide-in drawer (`Scaffold.drawer`) attached to `MainScreen`'s root `Scaffold` — see [features/settings-drawer.md](features/settings-drawer.md) (Phase 6). Tapping a row closes the drawer then pushes that row's screen as before. The drawer's own "Accounts" row was removed (2026-11-13) since Accounts is now a tab.
- **Review queue** — still only reachable from the Settings drawer (badge-counted row), not a tab — unchanged from before this round of navigation changes.
- The "Add transaction" `FloatingActionButton` lives on `MainScreen` itself (not per-tab) and is hidden on the Accounts tab, which has its own "Add account" action.

## Notification capture — how the app gets invoked

Resolved 2026-11-01 (previously open): `NotificationListenerService` is an OS-managed bound service, not something the app starts/keeps alive itself. Once the user grants notification access, Android instantiates and binds our listener as part of the app's process and calls `onNotificationPosted()` on it automatically for every posted notification, system-wide, **regardless of whether the app's UI is open or the app is in the recents list**. There is no polling and no periodic background job for this.

Since the actual rule-matching + DB-write logic lives in Dart (not duplicated in Kotlin — see the table above), there are two entry paths into that same Dart code, depending on whether a Flutter engine already exists when the listener fires:

1. **App's Flutter engine already running** (app open or recently backgrounded, engine not yet destroyed): the Kotlin listener forwards `{package, title, text, timestamp}` to Dart over an event channel; the existing Riverpod/Drift repository code runs as normal.
2. **App fully closed** (no Flutter engine alive): the native listener is still alive and still gets the callback (it's bound by the OS independently of any Activity/engine), but there's no Dart VM to hand work to. In this case, spin up a **headless `FlutterEngine`** from Kotlin pointed at a dedicated Dart entrypoint (`@pragma('vm:entry-point')`, same pattern used by `workmanager`/`android_alarm_manager_plus`), run the match + Drift write there, then let the engine tear down. This reuses the exact same Dart matching/write code as path 1 — the headless entrypoint just calls into the same rule-engine function the event-channel handler does.
   - **Gotcha hit during implementation**: `DartExecutor.DartEntrypoint`'s 2-arg constructor `(bundlePath, functionName)` resolves the function against the `main` library (`main.dart`) only, regardless of the `@pragma('vm:entry-point')` annotation — it fails at runtime with "Could not resolve main entrypoint function" if the entrypoint function lives in any other file, even one `main.dart` imports. Since the entrypoint lives in its own file (`lib/platform/notification_listener/notification_capture_entrypoint.dart`), the native side has to use the 3-arg constructor with the entrypoint's library URI spelled out explicitly (`"package:money_manager/platform/notification_listener/notification_capture_entrypoint.dart"`) — see `NotificationCaptureListenerService.kt`'s `dispatchHeadless()`.

Both paths write to the same on-disk Drift database the UI reads, so a capture that happens while the app is closed shows up next time the UI (or its live `.watch()` streams) is opened — no separate sync step needed.

## Permissions (Android)

- `BIND_NOTIFICATION_LISTENER_SERVICE` — required for notification capture; user must grant via system settings (cannot be requested via a normal runtime permission dialog). App must detect whether access is granted and guide the user to the settings page if not.
- No other sensitive permissions expected for v1 (no SMS, no contacts, no location).

## Open architecture questions

- Exact Riverpod provider structure (will firm up once first feature is scaffolded).
- Minimum Android SDK version — default assumption: minSdk 24+ (covers `NotificationListenerService` cleanly and nearly all active devices); confirm before project setup if the user needs older-device support.
