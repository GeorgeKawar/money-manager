import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/category_style.dart';
import '../../../core/utils/currency_format.dart';
import '../../../core/utils/date_period.dart';
import '../../transactions/presentation/add_edit_transaction_sheet.dart';
import '../data/review_queue_repository.dart';

class ReviewQueueScreen extends ConsumerWidget {
  const ReviewQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final itemsAsync = ref.watch(reviewQueueProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Review queue')),
      body: SafeArea(
        child: itemsAsync.when(
          data: (items) {
            if (items.isEmpty) {
              return Center(
                child: Text(
                  'Nothing waiting for review.',
                  style: TextStyle(color: colors.textSecondary),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _ReviewRow(item: items[index]),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load the review queue: $e')),
        ),
      ),
    );
  }
}

class _ReviewRow extends ConsumerWidget {
  const _ReviewRow({required this.item});

  final ReviewQueueItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final txn = item.transaction;
    final isIncome = txn.type == 'income';
    final signColor = isIncome ? colors.income : colors.expense;
    final sign = isIncome ? '+' : '-';
    final style = categoryStyle(item.categoryName);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.isDuplicate) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colors.expense.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.content_copy, size: 13, color: colors.expense),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Looks like a duplicate of an existing transaction',
                      style: TextStyle(color: colors.expense, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: style.color.withValues(alpha: 0.18), shape: BoxShape.circle),
                child: Icon(style.icon, color: style.color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      txn.note?.isNotEmpty == true ? txn.note! : (item.categoryName ?? 'Uncategorized'),
                      style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${item.accountName} · ${relativeDateTimeLabel(txn.date)}',
                      style: TextStyle(color: colors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Text(
                '$sign${formatMinorUnits(txn.amountMinorUnits, txn.currency)}',
                style: TextStyle(color: signColor, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                  onPressed: () => showAddEditTransactionSheet(context, existing: txn, confirmOnSave: true),
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: const Text('Edit', overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                  onPressed: () => ref.read(reviewQueueRepositoryProvider).discard(txn.id),
                  icon: Icon(Icons.close, size: 14, color: colors.expense),
                  label: Text('Discard', style: TextStyle(color: colors.expense), overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                  onPressed: () => ref.read(reviewQueueRepositoryProvider).confirm(txn.id),
                  icon: const Icon(Icons.check, size: 14),
                  label: const Text('Confirm', overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
