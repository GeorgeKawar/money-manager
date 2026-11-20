# Feature: Settings side-drawer navigation

## Status

Done. Implemented as Phase 6, after Phase 5 (local import/export). See "Decided" below for how the open decisions resolved.

## Decided

- **Drawer width**: default `Drawer()` (no explicit width override) — partial-width with a scrim over the dimmed dashboard, exactly the "leaning partial" default Material behavior described below.
- **Where the swipe/gear gesture is active**: Dashboard only, as leaned — it's the only screen with the gear icon/`Scaffold.drawer`.
- Implementation: [`settings_drawer.dart`](../../lib/features/settings/presentation/settings_drawer.dart)'s `SettingsDrawer` (a `ConsumerWidget` returning a `Drawer`) replaced the old `SettingsScreen` full-screen push entirely — the file was renamed since there's no longer a separate pushed screen, only the drawer. [`dashboard_screen.dart`](../../lib/features/transactions/presentation/dashboard_screen.dart) passes `const SettingsDrawer()` to `Scaffold.drawer`; the gear icon is wrapped in a `Builder` so its `onTap` can call `Scaffold.of(context).openDrawer()` (needs a context below the `Scaffold`). Each row's `onTap` calls a shared `_navigate()` helper that pops the drawer first (`Navigator.of(context).pop()` — Flutter's `Scaffold` registers the open drawer as a local history entry, so this closes it exactly like the back button would) then pushes the target screen, so behavior is unchanged from the old push-only flow except for how Settings itself opens.
- Verified on-device: gear icon opens the drawer with the expected partial-width/scrim look; tapping "Review queue" closed the drawer and pushed the screen correctly, proving the close-then-navigate behavior.

## Goal

Replace today's "tap the gear icon → push Settings as a full screen" interaction with a slide-in panel opened by swiping from the left edge of the screen, matching how most Android apps surface a side-drawer.

## Current behavior (for contrast)

[dashboard_screen.dart](../../lib/features/transactions/presentation/dashboard_screen.dart)'s `_SettingsButton` opens `SettingsScreen` via `Navigator.push(MaterialPageRoute(...))` — a full-screen forward navigation, only reachable by tapping the gear icon top-right. [settings_screen.dart](../../lib/features/settings/presentation/settings_screen.dart) itself (Accounts/Categories/Recurring/Notification rules/Review queue rows) doesn't change in this phase — only how it's opened changes.

## Scope

- Swipe from the left edge of the Dashboard opens Settings as a slide-in panel instead of (or alongside) the push navigation. Flutter's `Scaffold.drawer` already recognizes an edge-swipe-to-open gesture for free — likely the simplest implementation is moving `SettingsScreen`'s content into a `Drawer` passed to the Dashboard's `Scaffold.drawer`, rather than hand-rolling a custom `Dismissible`/`PageView` gesture.
- **Keep the gear icon working** (calling `Scaffold.of(context).openDrawer()` instead of pushing a route) rather than removing it — relying on an edge-swipe alone isn't discoverable for first-time users and is harder to hit reliably for accessibility (TalkBack/switch-access) users.
- Tapping a row inside the drawer (Accounts, Categories, etc.) closes the drawer first, then pushes that row's screen exactly as today — no change to any sub-screen.

## Open decisions to finalize when this phase starts

- **Drawer width**: partial-width (e.g. ~85%, dashboard content dimmed/visible behind a scrim) vs. full-bleed. Partial width is the more typical "slide-in panel" feel and is what Material's `Drawer` does by default — leaning partial unless the user wants full-bleed.
- **Where the swipe gesture is active**: Dashboard only (where the gear icon already lives today) vs. every screen in the app. Leaning Dashboard-only initially, since that's the one screen with the gear icon today, then revisit once this ships.
- Checked for gesture conflicts before starting: the period navigator uses tap arrows (not swipe), and transaction-list rows use a trash icon button rather than swipe-to-delete (per [design.md](../design.md) populated-list section) — no existing horizontal-swipe gesture on the Dashboard to collide with an edge-swipe-to-open drawer.

## Non-goals

- Reordering, renaming, or adding to the existing Settings rows — this phase only changes the entry point, not the contents.
- The still-open bottom-navigation-bar question in [architecture.md](../architecture.md)'s Navigation section — separate, unresolved, not addressed by this phase.

## Later change: Backup consolidation (2026-11-08)

Per user request, the drawer's four separate backup-related rows ("Export data", "Import data", "Export rules", "Import rules") were replaced with a single "Backup" row that navigates to a new `BackupScreen` ([lib/features/backup/presentation/backup_screen.dart](../../lib/features/backup/presentation/backup_screen.dart)), which holds those four actions as two labeled lists — "All data" (the full export, which already includes notification rules) and "Notification rules only" (see [rules-import-export.md](rules-import-export.md)). The shared row/spinner widgets (`SettingsRow`, `BusyIndicator`) were extracted from `settings_drawer.dart` into [lib/features/settings/presentation/widgets/settings_row.dart](../../lib/features/settings/presentation/widgets/settings_row.dart) so both the drawer and the new screen use the same visual style. This keeps the drawer itself short (one row per destination) while the backup actions get more room to explain what each list does.

## Later change: gear moved top-left + wider swipe zone (2026-11-08)

Per user request ("either make the button at top left, or allow the users to swipe from left to right to open the settings"), both were done rather than picking one: the gear icon in the dashboard header moved from top-right to top-left (more conventional position for a drawer-opening affordance, and closer to the screen edge it opens from), and `Scaffold.drawerEdgeDragWidth` was set to `48` (up from Flutter's default ~20px) so the edge-swipe gesture is easier to land without precise targeting. The currency pill stays top-right; the greeting/title column is `Expanded` between the two.

## Later change: "Insert from text" row added (2026-11-13)

A new row, "Insert from text", was added between "Notification rules" and "Review queue" — opens `ManualTextEntryScreen` for recovering a notification the listener missed, see [notification-capture.md](notification-capture.md) "Manual text entry".

## Later change: moved to the root nav shell + Accounts row removed (2026-11-13)

When the single-screen Dashboard was split into a bottom-nav shell (`MainScreen`, see [../architecture.md](../architecture.md) "Navigation"), `SettingsDrawer` moved with it: it's now `Scaffold.drawer` on `MainScreen`'s root `Scaffold` rather than the old `DashboardScreen`'s, so the edge-swipe gesture and `drawerEdgeDragWidth: 48` are effectively app-wide (every tab sits inside that same root `Scaffold`) even though the gear icon that also opens it still only appears on the Transactions tab's header, same as before. The drawer's "Accounts" row was removed — Accounts is now a primary bottom-nav tab, not a Settings destination.
