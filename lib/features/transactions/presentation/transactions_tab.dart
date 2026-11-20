import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../settings/data/settings_repository.dart';
import '../data/transactions_repository.dart';
import 'add_edit_transaction_sheet.dart';
import 'filter_providers.dart';
import 'period_providers.dart';
import 'widgets/balance_card.dart';
import 'widgets/period_selector.dart';
import 'widgets/transaction_filter_sheet.dart';
import 'widgets/transaction_list_section.dart';

const _pageSize = 20;
const _loadMoreThresholdPx = 400.0;

/// Bottom nav's first tab (2026-11-13 per user request, replacing the old
/// single-screen Dashboard): all-time balance, the period filter, and the
/// transaction list for that period. The list loads more as the user
/// scrolls near the bottom, rather than a tap-to-load button or a separate
/// "show all" screen — everything is reachable by scrolling this one tab.
class TransactionsTab extends ConsumerStatefulWidget {
  const TransactionsTab({super.key});

  @override
  ConsumerState<TransactionsTab> createState() => _TransactionsTabState();
}

class _TransactionsTabState extends ConsumerState<TransactionsTab> {
  int _visibleCount = _pageSize;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - _loadMoreThresholdPx) {
      setState(() => _visibleCount += _pageSize);
    }
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'GOOD MORNING';
    if (hour < 18) return 'GOOD AFTERNOON';
    return 'GOOD EVENING';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final settingsAsync = ref.watch(appSettingsStreamProvider);
    final range = ref.watch(activeDateRangeProvider);
    final categoryIds = ref.watch(selectedCategoryIdsProvider);
    final accountIds = ref.watch(selectedAccountIdsProvider);
    final balanceAsync = ref.watch(transactionsRepositoryProvider).watchAllTimeBalanceMinorUnits();
    final transactionsAsync = ref
        .watch(transactionsRepositoryProvider)
        .watchPeriodTransactions(range, categoryIds: categoryIds, accountIds: accountIds);
    final currency = settingsAsync.value?.defaultCurrency ?? 'USD';

    // Switching the period (or navigating prev/next) starts the list over
    // from the first page, matching the dashboard's old reset-on-filter-
    // change behavior. Changing the category/account filter does too.
    ref.listen<DateRangeIsh>(_rangeKeyProvider, (previous, next) {
      if (previous != null && previous != next) {
        setState(() => _visibleCount = _pageSize);
      }
    });
    ref.listen<bool>(hasActiveTransactionFilterProvider, (previous, next) {
      if (previous != null && previous != next) {
        setState(() => _visibleCount = _pageSize);
      }
    });

    return SafeArea(
      child: StreamBuilder<List<TransactionListItem>>(
        stream: transactionsAsync,
        builder: (context, txnSnapshot) {
          final items = txnSnapshot.data ?? const [];
          final visible = items.take(_visibleCount).toList();
          final hasMore = items.length > _visibleCount;

          return CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Builder(
                            builder: (context) => _SettingsButton(
                              onTap: () => Scaffold.of(context).openDrawer(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_greeting(), style: Theme.of(context).textTheme.labelSmall),
                                const SizedBox(height: 4),
                                Text('Your money', style: Theme.of(context).textTheme.headlineMedium),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          _CurrencyPill(
                            currency: currency,
                            onTap: () => _pickCurrency(context, ref, currency),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      StreamBuilder<int>(
                        stream: balanceAsync,
                        builder: (context, snapshot) {
                          final balance = snapshot.data ?? 0;
                          return BalanceCard(
                            balanceMinorUnits: balance,
                            currency: currency,
                            isMasked: settingsAsync.value?.isBalanceMasked ?? false,
                            onToggleMask: () => ref
                                .read(settingsRepositoryProvider)
                                .setBalanceMasked(!(settingsAsync.value?.isBalanceMasked ?? false)),
                            onTapAdjust: () => _showAdjustBalanceSheet(
                              context,
                              ref,
                              currentBalanceMinorUnits: balance,
                              currentAdjustmentMinorUnits: settingsAsync.value?.allTimeBalanceAdjustmentMinorUnits ?? 0,
                              currency: currency,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 28),
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
                      const SizedBox(height: 16),
                      Text('Transactions', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(
                        '${range.label} · ${items.length} ${items.length == 1 ? 'entry' : 'entries'}',
                        style: TextStyle(color: colors.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      if (items.isEmpty) const TransactionsEmptyState(),
                    ],
                  ),
                ),
              ),
              if (items.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList.separated(
                    itemCount: visible.length,
                    itemBuilder: (context, index) => TransactionRow(
                      item: visible[index],
                      onTap: () => showAddEditTransactionSheet(context, existing: visible[index].transaction),
                    ),
                    separatorBuilder: (context, index) => Divider(height: 1, color: colors.border),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 100),
                  child: hasMore
                      ? const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
                      : null,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// `ref.listen` needs a provider to watch; this projects [activeDateRangeProvider]
/// down to just the fields that identify "which period", so prev/next and
/// granularity switches reset pagination without over-triggering on
/// unrelated rebuilds.
typedef DateRangeIsh = (DateTime, DateTime);
final _rangeKeyProvider = Provider<DateRangeIsh>((ref) {
  final range = ref.watch(activeDateRangeProvider);
  return (range.start, range.end);
});

Future<void> _pickCurrency(BuildContext context, WidgetRef ref, String current) async {
  const presets = ['USD', 'EUR', 'GBP', 'SAR', 'AED', 'EGP', 'JOD', 'KWD'];
  final controller = TextEditingController();
  final colors = context.colors;

  final selected = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: colors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (sheetContext) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Default currency', style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: presets.map((code) {
                final isSelected = code == current;
                return ChoiceChip(
                  label: Text(code),
                  selected: isSelected,
                  onSelected: (_) => Navigator.of(sheetContext).pop(code),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              maxLength: 3,
              decoration: const InputDecoration(labelText: 'Other (ISO code, e.g. CAD)'),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final code = controller.text.trim().toUpperCase();
                  if (code.length == 3) Navigator.of(sheetContext).pop(code);
                },
                child: const Text('Use this currency'),
              ),
            ),
          ],
        ),
      );
    },
  );

  if (selected != null && selected != current) {
    await ref.read(settingsRepositoryProvider).setDefaultCurrency(selected);
  }
}

/// Lets the user set what the all-time balance should show right now (e.g.
/// 0, after archiving an account whose history they no longer want counted)
/// — see docs/data-model.md "Derived/computed". Internally this is stored
/// as a delta (`AppSettings.allTimeBalanceAdjustmentMinorUnits`) added on
/// top of the computed total, so it keeps tracking new transactions
/// afterward rather than freezing the display at a fixed number.
Future<void> _showAdjustBalanceSheet(
  BuildContext context,
  WidgetRef ref, {
  required int currentBalanceMinorUnits,
  required int currentAdjustmentMinorUnits,
  required String currency,
}) async {
  final colors = context.colors;
  final controller = TextEditingController(
    text: (currentBalanceMinorUnits / 1000).toStringAsFixed(2),
  );

  final result = await showModalBottomSheet<_BalanceAdjustResult>(
    context: context,
    backgroundColor: colors.background,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (sheetContext) {
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 28 + MediaQuery.of(sheetContext).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Adjust all-time balance',
                style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'Set what your all-time balance should show. New transactions still add/subtract from it afterward.',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
              decoration: InputDecoration(labelText: 'Balance ($currency)'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final value = double.tryParse(controller.text.trim());
                  if (value == null) return;
                  final desiredMinorUnits = (value * 1000).round();
                  final newAdjustment =
                      desiredMinorUnits - currentBalanceMinorUnits + currentAdjustmentMinorUnits;
                  Navigator.of(sheetContext).pop(_BalanceAdjustResult(newAdjustment));
                },
                child: const Text('Save'),
              ),
            ),
            if (currentAdjustmentMinorUnits != 0) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(const _BalanceAdjustResult(0)),
                  child: const Text('Reset to calculated value'),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );

  if (result != null) {
    await ref.read(settingsRepositoryProvider).setAllTimeBalanceAdjustment(result.adjustmentMinorUnits);
  }
}

class _BalanceAdjustResult {
  const _BalanceAdjustResult(this.adjustmentMinorUnits);
  final int adjustmentMinorUnits;
}

class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: colors.surfaceVariant, borderRadius: BorderRadius.circular(20)),
        child: Icon(Icons.settings_outlined, color: colors.textPrimary, size: 20),
      ),
    );
  }
}

class _CurrencyPill extends StatelessWidget {
  const _CurrencyPill({required this.currency, required this.onTap});

  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(currency, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700)),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down, color: colors.textSecondary, size: 18),
          ],
        ),
      ),
    );
  }
}
