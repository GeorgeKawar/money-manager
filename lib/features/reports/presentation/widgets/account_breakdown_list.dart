import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_format.dart';
import '../../data/reports_repository.dart';

/// Proportional bar-row list showing each account's net income-minus-expense
/// for a period, relative to the account with the largest magnitude. Plain
/// Container/LinearProgressIndicator rows (not fl_chart) to match the app's
/// hand-styled card look rather than a generic chart widget.
class AccountBreakdownList extends StatelessWidget {
  const AccountBreakdownList({super.key, required this.items, required this.currency});

  final List<AccountBreakdownItem> items;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.border),
        ),
        alignment: Alignment.center,
        child: Text(
          'No account activity for this period.',
          style: TextStyle(color: colors.textSecondary),
        ),
      );
    }

    final maxAbs = items.map((item) => item.netMinorUnits.abs()).reduce((a, b) => a > b ? a : b);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _AccountBar(
              item: items[i],
              currency: currency,
              fraction: maxAbs == 0 ? 0 : items[i].netMinorUnits.abs() / maxAbs,
            ),
            if (i != items.length - 1) const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _AccountBar extends StatelessWidget {
  const _AccountBar({required this.item, required this.currency, required this.fraction});

  final AccountBreakdownItem item;
  final String currency;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isPositive = item.netMinorUnits >= 0;
    final barColor = isPositive ? colors.income : colors.expense;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(item.account.name, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600)),
            Text(
              '${isPositive ? '+' : '-'}${formatMinorUnits(item.netMinorUnits.abs(), currency)}',
              style: TextStyle(color: barColor, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: fraction.clamp(0, 1),
            minHeight: 8,
            backgroundColor: colors.surfaceVariant,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
      ],
    );
  }
}
