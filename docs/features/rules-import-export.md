# Feature: Notification-rules-only export/import

## Status

Done — see [roadmap.md](../roadmap.md) Phase 8.

## Goal

Let the user back up and restore just their notification rules (see [notification-capture.md](notification-capture.md) and [data-model.md](../data-model.md) `NotificationRule`) as a separate, narrower action from the existing full-database export/import.

**The existing full backup (Phase 5, [data-import-export.md](data-import-export.md)) is unchanged by this phase** — it still exports/imports every table and still fully replaces local data on import. This phase adds a second, independent path; it does not touch `BackupRepository`, its UI rows, or its file format.

## Why a separate feature, not an option on the existing one

A rule set is something a user plausibly wants to share or re-apply on its own — e.g. hand-tuned rules for their bank's notification format, worth keeping separate from (and re-usable across) whatever transaction/account data happens to be on a given device at the time. Folding this into the full backup would mean either always carrying the whole database just to move rules around, or adding a "what to include" picker to the existing destructive-replace flow — more complexity in the one feature that's deliberately simple and total. A second, narrow feature keeps both simple: the full backup stays "replace everything," this one stays "just the rules."

## The core problem: rules reference accounts and categories by id

`NotificationRule.default_account_id` (required) and `default_category_id` (nullable) are foreign keys into `Account`/`Category`. Phase 5's full backup can preserve raw ids across export/import because it replaces *all* tables together — accounts, categories, and rules land back in one atomic transaction, so a rule's `default_account_id` still points at the right row.

A rules-only import can't do that: it must leave existing accounts/categories/transactions untouched (that's the whole point of "rules only"), but the destination device's accounts/categories were very likely created independently and have different ids — a different device, or the same device after accounts were added/edited/deleted since the export. Blindly reusing the exported numeric ids would silently point an imported rule at an arbitrary, likely-wrong account/category on the destination device. That's worse than failing loudly.

**Proposed resolution**: export each rule's account/category reference by **name**, not just id, and resolve by name on import:

- Export includes `defaultAccountName` (and `defaultCategoryName`, when set) alongside the raw `default_account_id`/`default_category_id` (kept for same-device debugging only, never relied on by import).
- On import, for each rule: look up an existing account on the destination device by exact (case-insensitive) name match.
  - **Match found** → use its id.
  - **No match** → the rule can't be safely imported as-is. Surface it in the pre-import confirmation summary (e.g. *"2 rules reference an account that doesn't exist here: 'Chase Checking', 'Cash — old'. These will be skipped."*) and skip just those rules — the rest of the import proceeds. The user can create a matching account first and re-import if they want those rules back.
  - Same treatment for `default_category_id`, except it's nullable — a rule with no category reference always imports cleanly.
- Import **never auto-creates** accounts or categories to satisfy a rule reference. Keeping this strictly name-match-or-skip is what keeps a "just import rules" action from having a surprise side effect of also creating new accounts/categories.

## Decided

- **Merge/append, not replace**: unlike the full backup (always replace), importing adds each resolvable, non-duplicate rule as a new row — existing rules are never touched. A per-rule duplicate check (same `name` + `app_package`/`match_any_app` + `regex_pattern` as an existing rule, all case-insensitive on name/package) skips re-adding an exact duplicate, so re-importing the same file twice doesn't pile up copies — surfaced in the confirmation summary as "N already exist here and will be skipped." Imported rules are appended after the device's existing rules in priority order (lowest priority = evaluated first), preserving their relative order from the file.
- **Placement**: originally a separate "Export rules" / "Import rules" row pair directly in the Settings drawer. Consolidated (2026-11-08, per user request) onto the **Backup** screen's second list, "Notification rules only" — alongside, but visually separated from, the full backup's "All data" list — reachable via a single "Backup" row in the drawer. See [settings-drawer.md](settings-drawer.md).
- **`is_preset` on imported rules**: preserved as exported.
- **File format marker**: `"fileType": "money_manager_rules_export"` plus `"exportFormatVersion": 1`. The full backup (Phase 5) has no such marker of its own, so the rules importer instead recognizes its shape directly (`appSettings` + `accounts` keys present) to give a specific "this is a full data export, use Import data instead" message rather than a generic one. Filename convention: `money_manager_rules_<timestamp>.json`.
- **Account/category matching scope**: name lookup matches against *all* accounts/categories on the destination device, including archived ones — an archived account still exists, so a rule referencing it by name still resolves; only a genuinely absent name is unresolvable.

## Scope (implemented)

- **Export rules** — "Export rules" row on the Backup screen. `RulesBackupRepository.exportToJson()` serializes every `NotificationRule` row (all fields per [data-model.md](../data-model.md)) plus each rule's resolved account/category **names**, to a versioned JSON document. Same SAF "Create document" flow as the full backup (`file_picker`).
- **Import rules** — "Import rules" row on the Backup screen. `RulesBackupRepository.parseImport()` validates the file (right format/version, rejects a full-backup file or malformed JSON with a clear message via `RulesBackupFormatException`), resolves each rule's account/category by name against the destination device, and returns a `RulesImportPreview` the UI uses to show a confirmation summary (importable / duplicate / unresolvable counts, naming missing account/category names). `applyImport()` then inserts only the importable rules and pushes the updated native allowlist.
- Implementation: `lib/features/notification_capture/data/rules_backup_repository.dart` (parallel to `BackupRepository`, not a modification of it), wired into `_RulesOnlyBackupSection` in `lib/features/backup/presentation/backup_screen.dart`. Tests: `test/notification_capture/rules_backup_repository_test.dart`.

## Non-goals

- Any change to the existing full-database export/import (Phase 5) — file format, UI, or replace semantics all stay exactly as shipped.
- Auto-creating accounts/categories during rules import.
- Merging/reconciling two *different* edits of the "same" rule (e.g. the same rule tweaked differently on two devices then imported both ways) — a name/pattern collision is handled as "skip as duplicate," not a 3-way merge.
- Exporting/importing anything beyond the `NotificationRule` table itself (no linked review-queue items, no captured transactions).
