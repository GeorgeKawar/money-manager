# Feature: Category/account breakdown charts

Phase 4 (see [../roadmap.md](../roadmap.md)) — visual breakdowns layered on top of the existing period summaries, not a new screen/nav entry.

## Placement

Both breakdowns live on their own bottom-nav tab, `ReportsTab` (`lib/features/reports/presentation/reports_tab.dart`) — moved there 2026-11-13 per user request, when the old single-screen Dashboard was split into the Transactions/Reports/Accounts tabs (see [../architecture.md](../architecture.md) "Navigation"). `ReportsTab` has its own copy of the period filter (`PeriodSegmentedControl`/`PeriodNavigator`), scoped to the same `activeDateRangeProvider` the Transactions tab uses, so picking a period on either tab keeps both in sync — switching periods updates the charts (and the other tab's list) together.

## Category breakdown

- `ReportsRepository.watchPeriodCategoryBreakdown(range, type: 'income' | 'expense')` — totals confirmed, non-pending-review transactions of the given type within `range`, grouped by category. Transactions with no category are grouped together as one "Uncategorized" item (`CategoryBreakdownItem.category == null`).
- Only one type is shown at a time (an Income/Expense toggle, reusing `SheetTypeToggle`) — income and expense totals aren't comparable as a single pie, so mixing them would misrepresent proportions.
- UI: `CategoryBreakdownChart` — an `fl_chart` `PieChart` (donut) plus a legend list (swatch, name, % of total, amount), colored via the existing `categoryStyle()` helper (same colors as the transaction list's category icons).

## Account breakdown

- `ReportsRepository.watchPeriodAccountBreakdown(range)` — net income-minus-expense per active account within `range`. Transfers are excluded, same convention as `TransactionsRepository.watchPeriodSummary` (see [categories-accounts.md](categories-accounts.md) "Transfers") — a transfer only moves money between accounts shown elsewhere, it doesn't represent the account "earning" or "spending" in the period. Accounts with zero net activity in the period are omitted; the rest are sorted by largest magnitude first.
- UI: `AccountBreakdownList` — a custom proportional horizontal-bar-row widget (not `fl_chart`), each row sized relative to the largest `|net|` in the list and colored income/expense per sign. Hand-rolled rather than a chart-library bar chart to match the app's existing minimalist, hand-styled card look (same family as `CashFlowCards`' `_StatCard`).

## Known constraint: fl_chart version

`fl_chart` is pinned to `^0.69.2`, not the `^1.1.0` originally declared in `pubspec.yaml` — see `architecture.md`'s tech-stack table for why (a `vector_math` version mismatch with this project's Flutter SDK). No feature impact: `0.69.2`'s `PieChart` API covers everything this chart needs.
