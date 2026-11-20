import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_format.dart';
import '../../settings/data/settings_repository.dart';
import '../data/recurring_repository.dart';
import 'add_edit_recurring_sheet.dart';

const _frequencyLabels = {
  'daily': 'Daily',
  'weekly': 'Weekly',
  'monthly': 'Monthly',
  'yearly': 'Yearly',
};

class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final recurringAsync = ref.watch(recurringListProvider);
    final settingsAsync = ref.watch(appSettingsStreamProvider);
    final currency = settingsAsync.value?.defaultCurrency ?? 'USD';

    return Scaffold(
      appBar: AppBar(title: const Text('Recurring')),
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
              child: recurringAsync.when(
                data: (items) {
                  if (items.isEmpty) {
                    return Center(
                      child: Text(
                        'No recurring transactions yet.',
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _RecurringRow(item: items[index], currency: currency),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Could not load recurring transactions: $e')),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 16,
              child: ElevatedButton.icon(
                onPressed: () => showAddEditRecurringSheet(context),
                icon: const Icon(Icons.add),
                label: const Text('Add recurring'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecurringRow extends ConsumerWidget {
  const _RecurringRow({required this.item, required this.currency});

  final RecurringListItem item;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final def = item.definition;
    final isIncome = def.type == 'income';
    final signColor = isIncome ? colors.income : colors.expense;
    final sign = isIncome ? '+' : '-';
    final name = def.note?.isNotEmpty == true ? def.note! : (item.categoryName ?? (isIncome ? 'Income' : 'Expense'));

    return InkWell(
      onTap: () => showAddEditRecurringSheet(context, existing: def),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_frequencyLabels[def.frequency] ?? def.frequency} · ${item.accountName} · '
                    'next ${DateFormat.yMMMd().format(def.nextRunDate)}',
                    style: TextStyle(color: colors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$sign${formatMinorUnits(def.amountMinorUnits, currency)}',
                  style: TextStyle(color: signColor, fontWeight: FontWeight.w700),
                ),
                Switch(
                  value: def.isActive,
                  onChanged: (v) => ref.read(recurringRepositoryProvider).setActive(def.id, v),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
