# Feature: Categories & Accounts

## Categories

- CRUD for categories: name, type (income/expense/both), icon, color.
- Default set seeded on first install (see [../data-model.md](../data-model.md)); user can add, rename, recolor, archive (not hard-delete if in use — archiving keeps historical transactions intact and out of the "pick a category" list for new entries).
- Used for: tagging transactions, breakdown charts/reports, default category on notification rules.
- **Implementation note**: a category's type (income/expense) is chosen at creation and fixed thereafter — editing only allows renaming. Changing type after creation would silently reclassify every historical transaction tagged with that category, so it's blocked at the UI level rather than handled with a migration/confirmation flow. To "convert" a category, archive it and create a new one with the desired type.

## Accounts / wallets

- Reached via the "Accounts" bottom-nav tab (`AccountsScreen`, unchanged otherwise) — previously a Settings-drawer row, moved to a primary tab 2026-11-13 per user request; see [../architecture.md](../architecture.md) "Navigation".
- CRUD for accounts: name, starting balance. Currency is a single app-wide `default_currency` setting (see [../data-model.md](../data-model.md) `AppSettings`), not per-account — v1 is a single-currency app.
- Each transaction belongs to exactly one account (or two, for transfers).
- Account list screen shows current balance per account (derived, see [../data-model.md](../data-model.md)).
- Archiving an account hides it from pickers but keeps its history/balance viewable — the Accounts screen lists archived accounts in their own "Archived accounts" section below the active list (2026-11-09, user request), each still showing its derived balance and still tappable to edit/unarchive. An "Unarchive" action (replacing "Archive" in the edit sheet for an already-archived account) returns it to the active list, no confirmation needed (unlike archiving, which is a one-way-feeling action the user might regret).
- Whether an archived account's starting balance and transactions count toward the dashboard's all-time balance is a user-facing setting, not fixed behavior: `AppSettings.include_archived_in_all_time_balance` (default `false`, matching the 2026-11-08 fix that first excluded them — see [../data-model.md](../data-model.md) "Derived/computed"), toggled via a switch on the Accounts screen's "Archived accounts" section (2026-11-09, user request: "allow the user to see archived accounts, and an option to either include them in the all time balance or exclude them"). `TransactionsRepository.watchAllTimeBalanceMinorUnits()` reads this setting to decide which accounts are "eligible" before summing.
- An account can also be **permanently deleted**, not just archived, but only when nothing references it: `AccountsRepository.isUnused()` checks there are no `Transaction` rows, no `RecurringTransaction` rows, and no `NotificationRule.defaultAccountId` pointing at it (2026-11-09, user request). When true, the edit sheet shows a "Delete permanently" action below Archive/Unarchive (hidden otherwise, since deleting an in-use account would either break those foreign keys or silently orphan them); confirmed via dialog, then `AccountsRepository.deleteAccount()` removes the row outright — no soft-delete/`is_archived` flag involved. An account with any history is only ever archivable, never deletable, so transaction history is never at risk of being lost this way.
- **Default account** (2026-11-18, user request): at most one active account can be marked default (`Account.is_default`, `AccountsRepository.setDefault()`/`clearDefault()`) via a "Set as default account"/"Unset as default account" toggle in the edit sheet (only shown for an active, non-archived account), and shown as a small "Default" badge in the Accounts list. Archiving the default account clears the flag rather than leaving an archived account silently default. It pre-fills two pickers that otherwise default to "the first active account": the add/edit transaction sheet's **Account** field (added alongside this — there was previously no account picker there at all, since early builds only had one account; see [transactions.md](transactions.md) "Add / edit / delete") and a new notification rule's **Default account** field (existing rules are unaffected). See `defaultAccountProvider` in `lib/features/accounts/data/accounts_repository.dart`.

## Transfers

- A transfer moves money between two of the user's own accounts (e.g. Cash → Bank). Modeled as two linked `Transaction` rows (`transfer_pair_id` pointing at each other): one `expense`-like outflow from the source account, one `income`-like inflow to the destination account, both excluded from income/expense totals and reports (see [transactions.md](transactions.md)).
- UI: a single "Transfer" action lets the user pick source account, destination account, amount, date, note — creates both legs atomically.
- Editing/deleting one leg affects the paired leg (kept in sync or deleted together, confirmed via dialog).

## Open questions
- None currently — currency is resolved as a single app-wide default (see [../data-model.md](../data-model.md)).
