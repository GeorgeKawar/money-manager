# Feature: Local data import/export (replaces cloud backup)

## Status

Done. Supersedes the earlier "Cloud backup via Google Drive/Firebase" plan — see "Why this changed" below. Shipped as the JSON export approach with replace (not merge) semantics — see "Decided" below.

## Why this changed

Per user decision (2026-11-06): instead of requiring a Google sign-in and talking to a cloud API (Drive App Data folder or Firebase) to back up/restore data, the app exports/imports a local file that the user places wherever they want via Android's own file picker (Downloads, SD card, a cloud-sync folder they already have mounted, email attachment, etc.). This keeps the app's "no account required, ever" guarantee fully intact — even backup/restore needs no sign-in, no network permission, no app-side cloud integration. The user decides where the file ends up; the app just reads/writes a file.

## Goal

Let the user save a snapshot of their entire local database to a file they choose, and restore that snapshot later (same device after a data wipe, or a new device after a fresh install) — without any account, network call, or cloud integration.

## Decided

Shipped as **JSON export** (over a raw `.sqlite` file copy): serializes every table (`Accounts`, `Categories`, `Transactions`, `NotificationRules`, `RecurringTransactions`, `AppSettingsTable`) plus a top-level `exportFormatVersion` + `exportedAt` into one JSON document, using Drift's generated `toJson()`/`fromJson()` per row — no hand-written serializer needed. Chosen over a raw file copy because it's resilient to future schema changes (import code can explicitly validate/map fields rather than relying on SQLite's own migration path to run correctly against a restored file) and lets the import flow show a pre-commit summary (record counts, export date) before doing anything destructive.

**Replace (not merge)** was chosen: simpler, matches "restore a backup" semantics, and avoids id-collision handling merge would need. Import always fully replaces local data, behind an explicit confirmation dialog that shows record counts + export date and warns it overwrites current data and cannot be undone.

Implementation: `BackupRepository` ([lib/features/backup/data/backup_repository.dart](../../lib/features/backup/data/backup_repository.dart)) — `exportToJson()`, `parseImport()` (validates shape/version, throws `BackupFormatException` on any problem), `applyImport()` (deletes children-before-parents then bulk-inserts parents-before-children inside one `_db.transaction()`, preserving original row ids via `Batch.insertAll` so foreign keys resolve correctly afterward).

## Scope

- **Export** — an "Export data" action on the **Backup** screen (see [settings-drawer.md](settings-drawer.md), reachable via the drawer's "Backup" row — consolidated there 2026-11-08, previously inline in the drawer itself). Builds the export document, then hands it to Android's Storage Access Framework "Create document" picker (via the `file_picker` package) so the user picks exactly where it's saved. No app-side decision about file location, no permissions beyond what SAF grants per-file.
- **Import** — an "Import data" action on the same Backup screen. Opens the SAF "Open document" picker for a previously exported file, validates it (right format/version), shows a confirmation summary (record counts, export date) before doing anything destructive, then replaces local data.
- Export includes: all accounts, categories, transactions, notification rules, recurring definitions, and the app settings row (currency, theme, all-time balance adjustment). Does **not** include the Android notification-listener permission grant itself — that's an OS-level grant, re-acquired manually regardless of import/export.
- Export format version stays at `1` even for fields added after the format was first shipped (e.g. `AppSettingsTable.allTimeBalanceAdjustmentMinorUnits`, added 2026-11-08) as long as they're additive: `BackupRepository.parseImport()` defaults any missing key on an older export's `appSettings` object before deserializing, so older export files keep importing rather than failing as "missing expected data". Bump `_formatVersion` only for a genuinely breaking shape change.
- **Bug fixed (2026-11-18):** the same missing-key defaulting existed only for `appSettings`, not for other tables' newly-added columns. `Account.isDefault` (added 2026-11-18, non-nullable) had no such fallback, so any export from before that date failed to import with "This file is missing expected data and cannot be imported." — found when the user's real pre-2026-11-18 backup wouldn't import. Fixed by defaulting `isDefault` to `false` per account row in `parseImport()` before calling `Account.fromJson`, same pattern as the `appSettings` fallback; regression test added in `test/backup/backup_repository_test.dart`. When adding a new non-nullable column to any exported table in future, add the same per-row default here, not just to `appSettings`.

## Non-goals

- Any cloud account, API, or network call — this is intentionally 100% local/offline by design, not just deferred for v1.
- Automatic/scheduled exports — manual action only, so the user always knows when a file is written.
- Real-time multi-device sync.

## Android's own Auto Backup — disabled (2026-11-18)

Found while debugging the import bug above: `AndroidManifest.xml` never set `android:allowBackup`, which defaults to `true`. That let Android's OS-level Auto Backup silently copy the app's local database to the user's Google Account cloud backup and restore it automatically on reinstall — completely outside this feature, invisible to the user, and a direct violation of the "no cloud, ever" decision log entry above. It's why data reappeared after a `flutter install`-triggered uninstall/reinstall without any manual import. Fixed by setting `android:allowBackup="false"` (and `android:fullBackupContent="false"`) on the `<application>` element, so a reinstall now behaves as documented: local data is actually gone until the user imports a file themselves.

## Dependencies

- `file_picker` (`^8.1.2`, resolved `8.3.7`) — Android SAF save/open pickers.
