import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/sheet_widgets.dart';
import '../../settings/data/settings_repository.dart';
import '../../transactions/data/transactions_repository.dart';
import '../../transactions/presentation/filter_providers.dart';
import '../../transactions/presentation/period_providers.dart';
import '../../transactions/presentation/widgets/cash_flow_cards.dart';
import '../../transactions/presentation/widgets/period_selector.dart';
import '../../transactions/presentation/widgets/transaction_filter_sheet.dart';
import '../data/reports_repository.dart';
import 'report_providers.dart';
import 'widgets/account_breakdown_list.dart';
import 'widgets/category_breakdown_chart.dart';

/// Bottom nav's second tab (2026-11-13 per user request) — the period
/// filter plus the Cash flow/By category/By account breakdowns that used
/// to sit below the transaction list on the old single-screen Dashboard.
/// Shares `activeDateRangeProvider` with the Transactions tab, so picking a
/// period here (or there) keeps both in sync.
class ReportsTab extends ConsumerWidget {
  const ReportsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(activeDateRangeProvider);
    final categoryIds = ref.watch(selectedCategoryIdsProvider);
    final accountIds = ref.watch(selectedAccountIdsProvider);
    final settingsAsync = ref.watch(appSettingsStreamProvider);
    final summaryAsync = ref
        .watch(transactionsRepositoryProvider)
        .watchPeriodSummary(range, categoryIds: categoryIds, accountIds: accountIds);
    final breakdownType = ref.watch(categoryBreakdownTypeProvider);
    final categoryBreakdownAsync = ref.watch(reportsRepositoryProvider).watchPeriodCategoryBreakdown(
          range,
          type: breakdownType,
          categoryIds: categoryIds,
          accountIds: accountIds,
        );
    final accountBreakdownAsync = ref
        .watch(reportsRepositoryProvider)
        .watchPeriodAccountBreakdown(range, categoryIds: categoryIds, accountIds: accountIds);
    final currency = settingsAsync.value?.defaultCurrency ?? 'USD';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reports', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 20),
            const PeriodSegmentedControl(),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(range.label, style: Theme.of(context).textTheme.titleMedium),
                ),
                const TransactionFilterButton(),
                const PeriodNavigator(),
              ],
            ),
            const SizedBox(height: 28),
            Text('Cash flow', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            StreamBuilder<PeriodSummary>(
              stream: summaryAsync,
              builder: (context, snapshot) {
                final summary = snapshot.data ?? PeriodSummary.zero;
                return CashFlowCards(
                  incomeMinorUnits: summary.incomeMinorUnits,
                  expenseMinorUnits: summary.expenseMinorUnits,
                  currency: currency,
                );
              },
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('By category', style: Theme.of(context).textTheme.titleLarge),
                SizedBox(
                  width: 160,
                  child: SheetTypeToggle(
                    type: breakdownType,
                    onChanged: (value) => ref.read(categoryBreakdownTypeProvider.notifier).state = value,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            StreamBuilder<List<CategoryBreakdownItem>>(
              stream: categoryBreakdownAsync,
              builder: (context, snapshot) {
                return CategoryBreakdownChart(items: snapshot.data ?? const [], currency: currency);
              },
            ),
            const SizedBox(height: 28),
            Text('By account', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            StreamBuilder<List<AccountBreakdownItem>>(
              stream: accountBreakdownAsync,
              builder: (context, snapshot) {
                return AccountBreakdownList(items: snapshot.data ?? const [], currency: currency);
              },
            ),
          ],
        ),
      ),
    );
  }
}
