# Data model

Local SQLite tables via Drift. Names below are logical table/entity names, not final Dart class names.

## AppSettings
Single-row table (or key/value store) for app-wide preferences.

| Field | Type | Notes |
|---|---|---|
| default_currency | text | ISO code, e.g. "SAR". User-selectable (dashboard pill shortcut + Settings screen, per [design.md](design.md)). v1 is single-currency app-wide — all accounts/transactions are in this one currency, no per-account currency and no FX conversion. |
| theme_mode | enum(light, dark, system) | See [design.md](design.md) theming section. |
| all_time_balance_adjustment_minor_units | int, default 0 | User-set correction added on top of the computed all-time balance (see "Derived/computed" below). Added 2026-11-08 so the user can make the dashboard balance show a value they expect — e.g. after archiving an account — via the balance card's "Adjust" affordance (`_showAdjustBalanceSheet` in `lib/features/transactions/presentation/dashboard_screen.dart`), without discarding the running computed total (new transactions still move the displayed balance afterward). |
| include_archived_in_all_time_balance | bool, default false | Whether archived accounts' starting balances and transactions count toward the all-time balance (see "Derived/computed" below). Added 2026-11-09 per user request, making the 2026-11-08 exclusion-of-archived-accounts fix configurable rather than fixed; toggled via a switch on the Accounts screen's "Archived accounts" section — see [features/categories-accounts.md](features/categories-accounts.md). |

## Account
Represents a wallet/bank account/cash source.

| Field | Type | Notes |
|---|---|---|
| id | int, PK | |
| name | text | e.g. "Cash", "Main Bank", "Credit Card" |
| starting_balance_minor_units | int | Balance at account creation, stored as integer minor units (see "Money storage" below); current balance is derived (starting + sum of transactions + transfers). Always in the app's `default_currency` (see `AppSettings`) — no per-account currency in v1. |
| is_archived | bool | Soft-hide without deleting history. |
| is_default | bool, default false | At most one account has this set (`AccountsRepository.setDefault`, 2026-11-18). Pre-fills the account field on new manual transactions and new notification rules — see [features/categories-accounts.md](features/categories-accounts.md). Cleared automatically on archive. |

## Category
| Field | Type | Notes |
|---|---|---|
| id | int, PK | |
| name | text | e.g. "Food", "Transport", "Salary" |
| type | enum(income, expense, both) | A category is generally scoped to one transaction type, but "both" allowed for flexible ones. |
| icon / color | text | For UI display. |
| is_archived | bool | |

Default seed list (per [design.md](design.md) add/edit transaction mockups, 2026-11-01): **expense** = Food, Home, Transport, Shopping, Health, Bills, Other; **income** = Salary, Freelance, Gift, Other. Shown as selectable chips (not a dropdown) in the add/edit sheet, and drive the transaction list's leading icon/color via a fixed name-based lookup (`lib/core/utils/category_style.dart`) rather than the unused `icon`/`color` columns above.

## Transaction
The core record.

| Field | Type | Notes |
|---|---|---|
| id | int, PK | |
| account_id | FK → Account | |
| category_id | FK → Category, nullable | Nullable to allow "uncategorized". |
| type | enum(income, expense, transfer) | |
| amount_minor_units | int | Integer, scaled 1000x (see "Money storage" below). Avoids float rounding issues. |
| date | datetime | User-editable (full date **and time**, not just date — see [features/transactions.md](features/transactions.md)); defaults to now (or notification timestamp for captured ones). |
| note | text, nullable | The transaction's required display name (e.g. "Groceries", "Monthly salary") — UI-labeled "Name", not optional, despite the nullable column. This is the title shown on transaction list rows; see [design.md](design.md) "Add/Edit transaction". Column kept as `note` rather than renamed, to avoid unnecessary schema churn pre-release. |
| currency | text | ISO code, snapshotted from `AppSettings.default_currency` at creation time. Historical transactions keep the currency/amount they were logged with even if the app's default currency is changed later — no retroactive conversion (per user decision). Display formatting for a transaction always uses its own `currency`, not the current app default. |
| source | enum(manual, notification, recurring) | How the transaction was created. |
| source_app_package | text, nullable | Set when `source = notification`; e.g. `com.bank.app`. |
| source_rule_id | FK → NotificationRule, nullable | Which rule produced it, if any. |
| transfer_pair_id | FK → Transaction, nullable | Links the two legs of an account-to-account transfer. |
| recurring_id | FK → RecurringTransaction, nullable | Set when generated from a recurring definition. |
| is_pending_review | bool | True = sits in the review queue, excluded from totals/reports until confirmed. |
| duplicate_of_transaction_id | FK → Transaction, nullable | Set (2026-11-18) when this transaction looks like a redelivered duplicate of an existing one (same `source_rule_id`/`source_app_package`/`amount_minor_units`/resolved `date`) — see [features/notification-capture.md](features/notification-capture.md) "Matching details". Non-null forces `is_pending_review = true` regardless of the matched rule's `auto_add`, so it waits in the review queue instead of being silently dropped or silently double-counted. Only set by live/headless notification capture, never manual text entry. |
| created_at / updated_at | datetime | Audit fields. |

## NotificationRule
A user-configured (or preset) regex rule for parsing a specific app's notifications.

| Field | Type | Notes |
|---|---|---|
| id | int, PK | |
| name | text | Display name, e.g. "Bank X — card payment"; also the note fallback when no name_group captures and fallback_name is unset — see "Matching details" below. |
| fallback_name | text, nullable | Overrides `name` as the note fallback only, without changing the rule's own display name — e.g. a descriptively-named rule "Bank X — card payment v2" can still produce a short note like "Card payment". Added 2026-11-20, user request. Null/blank means "use `name`". |
| app_package | text | Android package the rule applies to, e.g. `com.chase.mobile`. Ignored (may be blank) when match_any_app is true. |
| match_any_app | bool, default false | True = evaluate against notifications from every app, not just app_package. |
| is_enabled | bool | |
| is_preset | bool | True for built-in rules shipped with the app (still user-editable/toggleable, per decision below). |
| regex_pattern | text | Applied against notification title+text. |
| amount_group | int | Capture group index containing the numeric amount. |
| transaction_type | enum(income, expense) | What a match should be recorded as. |
| default_category_id | FK → Category, nullable | Pre-fills category on the captured/draft transaction. |
| default_account_id | FK → Account | Which account captured transactions post to. |
| auto_add | bool | **Per-rule setting** (per user decision): true = skip review queue and insert directly as a confirmed transaction; false = insert as `is_pending_review = true`. |
| priority | int, default 0 | Evaluation order across all of a notification's candidate rules, lowest first — "first match wins" (the rest aren't evaluated). Explicit and reorderable in the Rules screen, not implied by id/creation order. |
| date_group | int, nullable | Capture group holding a date string that overrides the notification's own post time, if set and parseable. |
| date_format | text, nullable | `DateFormat` (package:intl) pattern used to parse date_group's capture, e.g. `dd-MMM-yyyy`. Only meaningful when date_group is set. |
| note_group | int, nullable | Capture group appended to the resolved name (see name_group/name below) to build `Transaction.note`. |
| name_group | int, nullable | Capture group used as the base of `Transaction.note` instead of the rule's own name, when it matches. |
| created_at / updated_at | datetime | |

Both name_group and note_group populate the single existing `Transaction.note` column — there's no separate name/title column on Transaction. See [features/notification-capture.md](features/notification-capture.md) "Matching details" for the exact resolution rule.

## RecurringTransaction
Definition that periodically generates `Transaction` rows (e.g. subscriptions, salary).

| Field | Type | Notes |
|---|---|---|
| id | int, PK | |
| account_id | FK → Account | |
| category_id | FK → Category, nullable | |
| type | enum(income, expense) | |
| amount_minor_units | int | Same 1000x-scaled integer convention as `Transaction.amount_minor_units`. |
| note | text, nullable | |
| frequency | enum(daily, weekly, monthly, yearly) | v1 scope; custom intervals (e.g. "every 2 weeks") can be added later if needed. |
| start_date | date | |
| end_date | date, nullable | Null = indefinite. |
| next_run_date | date | Advances each time a transaction is generated. |
| is_active | bool | |

Generation strategy: on app open (and optionally via a periodic background task later), check all active recurring definitions whose `next_run_date <= today`, generate the corresponding `Transaction` rows, advance `next_run_date`. No reliance on exact-time background execution for v1 — Android background scheduling for exact-time recurring entries is a later refinement if needed.

## Money storage
All monetary fields (`starting_balance_minor_units`, `amount_minor_units`) are stored as a plain integer scaled **1000x** the major currency unit — i.e. thousandths — regardless of which currency a given row is in.

Why 1000x and not the more common 100x ("cents"): per [ISO 4217](https://en.wikipedia.org/wiki/ISO_4217), currencies don't all use 2 decimal digits — most do (USD, EUR, SAR, ...), some use 0 (JPY, KRW, CLP, ...), and a handful use 3 (KWD, BHD, JOD, OMR, LYD, TND, IQD). A fixed 100x scale can't represent that third decimal digit without losing precision. Scaling everything by 1000x covers every ISO 4217 currency's minor-unit precision losslessly in one consistent integer column — no per-currency schema branching.

Formatting divides back down (`amount / 1000`) and lets `intl`'s `NumberFormat.currency(name: currencyCode)` infer and round to that currency's actual decimal digits for display (0, 2, or 3) — see `lib/core/utils/currency_format.dart`.

## Derived/computed (not stored)
- **Account balance** = `starting_balance_minor_units` + signed sum of its non-transfer transactions + net of transfers in/out.
- **All-time balance** (dashboard) = sum of eligible accounts' balances, plus `AppSettings.all_time_balance_adjustment_minor_units` (all accounts share `default_currency`, so this is a plain sum, no conversion — see [design.md](design.md)). Which accounts are "eligible" depends on `AppSettings.include_archived_in_all_time_balance`: `false` (default, fixed 2026-11-08 — previously summed *every* account regardless of `is_archived`, inconsistent with `AccountsRepository.watchActive()`/`watchActiveWithBalances()` already excluding them) excludes archived accounts; `true` includes them too (2026-11-09, user-toggleable). The adjustment field lets the user additionally nudge the displayed total to a value they expect, without freezing it — see `AppSettings.all_time_balance_adjustment_minor_units` above.
- **Period summaries** (day/week/month/year) = sum of `amount_minor_units` grouped by `type`, filtered by `date` within the period and `is_pending_review = false`.

## Open questions
- Whether categories need subcategories (e.g. Food → Groceries/Restaurants) — not in v1 unless requested.
- **Resolved**: changing `default_currency` does not retroactively convert or relabel historical transactions — each `Transaction` snapshots its own `currency` at creation (see above). The all-time balance / period summaries will, as a consequence, need to either (a) only sum transactions matching the *current* default currency, or (b) sum raw amounts regardless of per-transaction currency and label the total ambiguously. Since v1 has no FX conversion, approach (a) is correct: if a user changes their default currency, summaries going forward are computed from same-currency transactions; mixed-currency history is an edge case to handle in the UI (e.g. a small note) when it's actually built, not a blocker for starting implementation.
