import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/category_style.dart';
import '../../../../core/utils/currency_format.dart';
import '../../../../core/utils/date_period.dart';
import '../../data/transactions_repository.dart';

/// Shared transaction-list building blocks — used by the Transactions tab
/// (`TransactionsTab`, infinite-scroll) and anywhere else a transaction row
/// or boxed list of rows is needed.

/// Shown when a period/filter has no matching transactions.
class TransactionsEmptyState extends StatelessWidget {
  const TransactionsEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: colors.surfaceVariant, shape: BoxShape.circle),
            child: Icon(Icons.inbox_outlined, color: colors.textSecondary),
          ),
          const SizedBox(height: 16),
          Text('Nothing here yet', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 6),
          Text(
            'Add an income or expense to start tracking this period.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// The bordered, rounded box of transaction rows, with dividers between
/// them — used where a short, fully-rendered list fits in one card.
class TransactionListBox extends StatelessWidget {
  const TransactionListBox({super.key, required this.items, required this.onTapItem});

  final List<TransactionListItem> items;
  final ValueChanged<TransactionListItem> onTapItem;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            TransactionRow(item: items[i], onTap: () => onTapItem(items[i])),
            if (i != items.length - 1) Divider(height: 1, color: colors.border),
          ],
        ],
      ),
    );
  }
}

/// A single transaction row's content (icon, note/category, amount, delete
/// button) with no outer decoration of its own — callers wrap it (a boxed
/// list with dividers, or an individually-carded row) as needed.
class TransactionRow extends ConsumerWidget {
  const TransactionRow({super.key, required this.item, required this.onTap});

  final TransactionListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final txn = item.transaction;
    final isIncome = txn.type == 'income';
    final signColor = isIncome ? colors.income : colors.expense;
    final sign = isIncome ? '+' : '-';
    final style = categoryStyle(item.category);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
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
                    txn.note?.isNotEmpty == true ? txn.note! : (item.category?.name ?? 'Uncategorized'),
                    style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${item.category?.name ?? 'Uncategorized'} · ${relativeDateTimeLabel(txn.date)}',
                    style: TextStyle(color: colors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              '$sign${formatMinorUnits(txn.amountMinorUnits, txn.currency)}',
              style: TextStyle(color: signColor, fontWeight: FontWeight.w700),
            ),
            IconButton(
              onPressed: () => _delete(context, ref),
              icon: Icon(Icons.delete_outline, color: colors.textMuted, size: 20),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.only(left: 4),
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final txn = item.transaction;
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(transactionsRepositoryProvider);
    await repo.deleteTransaction(txn.id);
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Transaction deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => repo.addTransaction(
            accountId: txn.accountId,
            categoryId: txn.categoryId,
            type: txn.type,
            amountMinorUnits: txn.amountMinorUnits,
            currency: txn.currency,
            date: txn.date,
            note: txn.note,
          ),
        ),
      ),
    );
  }
}
