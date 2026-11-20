import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/sheet_widgets.dart';
import '../../../accounts/data/accounts_repository.dart';
import '../../../categories/data/categories_repository.dart';
import '../filter_providers.dart';

/// Icon button shown next to the period filter on the Transactions and
/// Reports tabs (added 2026-11-18 per user request) — opens
/// [showTransactionFilterSheet] and shows a small badge with the combined
/// count of selected categories/accounts when any filter is active.
class TransactionFilterButton extends ConsumerWidget {
  const TransactionFilterButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final categoryCount = ref.watch(selectedCategoryIdsProvider).length;
    final accountCount = ref.watch(selectedAccountIdsProvider).length;
    final activeCount = categoryCount + accountCount;

    return InkWell(
      onTap: () => showTransactionFilterSheet(context),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              activeCount > 0 ? Icons.filter_alt : Icons.filter_alt_outlined,
              color: activeCount > 0 ? colors.accent : colors.textSecondary,
              size: 20,
            ),
            if (activeCount > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: colors.accent, shape: BoxShape.circle),
                  constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                  child: Text(
                    '$activeCount',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.onAccent, fontSize: 9, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> showTransactionFilterSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _TransactionFilterSheet(),
  );
}

class _TransactionFilterSheet extends ConsumerWidget {
  const _TransactionFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final categoriesAsync = ref.watch(activeCategoriesProvider);
    final accountsAsync = ref.watch(activeAccountsProvider);
    final selectedCategoryIds = ref.watch(selectedCategoryIdsProvider);
    final selectedAccountIds = ref.watch(selectedAccountIdsProvider);
    final hasActiveFilter = ref.watch(hasActiveTransactionFilterProvider);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        'Filter',
                        style: TextStyle(color: colors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                    ),
                    SheetCloseButton(onTap: () => Navigator.of(context).pop()),
                  ],
                ),
                const SizedBox(height: 20),
                const SheetFieldLabel('Categories'),
                const SizedBox(height: 8),
                categoriesAsync.when(
                  data: (categories) {
                    if (categories.isEmpty) {
                      return Text('No categories yet.', style: TextStyle(color: colors.textSecondary));
                    }
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: categories
                          .map((c) => SheetChip(
                                label: c.name,
                                selected: selectedCategoryIds.contains(c.id),
                                onTap: () => _toggle(ref, selectedCategoryIdsProvider, c.id),
                              ))
                          .toList(),
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('Could not load categories: $e'),
                ),
                const SizedBox(height: 20),
                const SheetFieldLabel('Accounts'),
                const SizedBox(height: 8),
                accountsAsync.when(
                  data: (accounts) {
                    if (accounts.isEmpty) {
                      return Text('No accounts yet.', style: TextStyle(color: colors.textSecondary));
                    }
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: accounts
                          .map((a) => SheetChip(
                                label: a.name,
                                selected: selectedAccountIds.contains(a.id),
                                onTap: () => _toggle(ref, selectedAccountIdsProvider, a.id),
                              ))
                          .toList(),
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('Could not load accounts: $e'),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ),
                if (hasActiveFilter) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () {
                        ref.read(selectedCategoryIdsProvider.notifier).state = const {};
                        ref.read(selectedAccountIdsProvider.notifier).state = const {};
                      },
                      child: const Text('Clear filters'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _toggle(WidgetRef ref, StateProvider<Set<int>> provider, int id) {
    final current = ref.read(provider);
    final next = Set<int>.from(current);
    if (!next.remove(id)) next.add(id);
    ref.read(provider.notifier).state = next;
  }
}
