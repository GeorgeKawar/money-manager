# Feature: Transactions

Core CRUD + filtering/reporting. See [../data-model.md](../data-model.md) for the `Transaction` schema.

## Add / edit / delete

- **Add**: type (income/expense — transfer handled via [categories-accounts.md](categories-accounts.md)), amount, account, category (optional), date **and time** (defaults to now), note (optional). The date/time field is tap-to-pick (Flutter's `showDatePicker` + `showTimePicker`, chained) rather than free-text — changed 2026-11-13 per user request; seconds aren't user-editable (no native seconds picker) so they're preserved from the existing value (or zeroed for a brand-new transaction) rather than exposed in the UI. Same tap-to-pick treatment applies to the Transfer sheet's date field (date-only, no time).
- **Account field** (2026-11-18): the sheet picks an account via the same chip-row pattern as Category, pre-selected to the default account (see [categories-accounts.md](categories-accounts.md) "Default account") or else the first active account. Before this, the sheet had no account picker at all — every manual transaction silently went to whichever account happened to be first.
- **Description** (optional, 2026-11-20 per user request): a free-text "Description (optional)" field distinct from the required "Name" field above it (`Transaction.note`) — for extra detail beyond the short name (e.g. Name "Gas", Description "Filled up before road trip"). Backed by a new nullable `Transaction.description` column (schema v5→v6); being nullable, no backup-import compatibility fix was needed for older exports (unlike a non-nullable column — see [data-import-export.md](data-import-export.md)).
- **Edit**: all fields editable after creation, including re-categorizing or moving to a different account.
- **Delete**: soft-confirm (dialog) before removing; if the transaction has a `transfer_pair_id`, deleting one leg deletes/prompts about the paired leg too.
- Transactions created from notification capture (`source = notification`) and still `is_pending_review = true` are edited/confirmed/discarded via the **review queue**, not the normal edit flow — see [notification-capture.md](notification-capture.md).

## Filtering by period

User can view transactions and totals scoped to:
- **Day** — a specific date, default today.
- **Week** — Mon–Sun (confirm locale/week-start preference later), default current week.
- **Month** — calendar month, default current month.
- **Year** — calendar year, default current year.
- **Custom** — an arbitrary start/end range picked via Flutter's built-in `showDateRangePicker` (added 2026-11-08 per user request, Cash Flow screen). Selecting it opens the picker pre-filled with the last-picked custom range (or the last 7 days on first use); the chosen range is held in `customDateRangeProvider` (`lib/features/transactions/presentation/period_providers.dart`), separate from the calendar-unit reference date used by the other four periods.

Each period view supports navigating to the previous/next period (e.g. swipe or arrow buttons to move between months). For **Custom**, prev/next shifts the whole picked range backward/forward by its own span (e.g. a 10-day custom range moves by 10 days), rather than by a calendar unit — see `DateRange.next()`/`previous()` and `DateRange.customRange()` in `lib/core/utils/date_period.dart`.

## Filtering by category / account

Added 2026-11-18 per user request, on top of the period filter above. A filter icon (`TransactionFilterButton`, next to the period navigator on both the Transactions tab and the Reports tab) opens a bottom sheet with multi-select category and account chips — pick any combination of each, e.g. "Food + Transport" across "Cash + Bank". An empty selection means "all" (no filter), matching the existing `match_any_app`-style convention elsewhere in this app. Shared via `selectedCategoryIdsProvider`/`selectedAccountIdsProvider` (`lib/features/transactions/presentation/filter_providers.dart`), so — like the period filter — picking a filter on either tab keeps both in sync. The filter icon shows a small badge with the combined selected-item count when any filter is active.

Applies to: the Transactions tab's period transaction list (not the all-time balance card, which stays a fixed, unfiltered total of everything), and the Reports tab's Cash flow summary, By category breakdown, and By account breakdown. Changing either filter resets the Transactions tab's infinite-scroll pagination back to the first page, same as changing the period.

## Summary / totals

For the selected period, show:
- Total income
- Total expenses
- Net (income − expenses)
- Optionally, a breakdown chart by category (bar/pie) — see [../architecture.md](../architecture.md) for charting library choice.

Totals exclude:
- Transactions still in the notification review queue (`is_pending_review = true`).
- Transfers (they net to zero across accounts and shouldn't be double-counted as income/expense) — transfers get their own small "moved between accounts" indicator if shown at all.

## List view

- Lives on the Transactions tab (`TransactionsTab`, `lib/features/transactions/presentation/transactions_tab.dart`) — one of the 3 bottom-nav tabs on `MainScreen` (2026-11-13, see [../architecture.md](../architecture.md) "Navigation"). The period filter (`PeriodSegmentedControl` + `PeriodNavigator`) sits directly below the all-time balance card, immediately above the transaction list, so changing it doesn't require scrolling past the list first. It's shared (same `activeDateRangeProvider`) with the Reports tab, so picking a period on either tab keeps both in sync.
- **Infinite scroll** (2026-11-13 per user request, replacing an earlier 10-at-a-time "Load more"/"Show all" design): the whole tab is one `CustomScrollView`; only a page of items (`_visibleCount`, starting at 20) is actually built into the sliver list, and a `ScrollController` listener grows that count by another page once the user scrolls within ~400px of the bottom. Switching the period (or navigating prev/next) resets back to the first page. Since `TransactionsRepository.watchPeriodTransactions()` already returns the whole period's list reactively (no DB-level pagination exists or is needed at this app's realistic data volumes), "loading more" is just revealing more of that already-fetched list — there's no separate fetch per page.
- Reverse-chronological by default within the selected period.
- Each row: category icon/color, note or category name, amount (colored by income/expense), account, date/time (e.g. "Today, 7:20 PM" or "Nov 5, 12:00 AM" — `relativeDateTimeLabel` in `lib/core/utils/date_period.dart`), plus the optional description (if set) as a muted line below, truncated to 2 lines. Same display in the review queue's rows.
- Tapping a row opens edit view.
- Group-by-day headers within list views spanning more than a day (week/month/year views).

## Open questions
- Whether to support multiple currencies displayed simultaneously in one summary (see [../data-model.md](../data-model.md) open questions) — deferred.
- Exact chart types — will finalize once the user shares designs ([../design.md](../design.md)).
