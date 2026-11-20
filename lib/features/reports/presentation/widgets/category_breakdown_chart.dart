import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/category_style.dart';
import '../../../../core/utils/currency_format.dart';
import '../../data/reports_repository.dart';

/// Donut chart + legend showing how a period's income or expense splits
/// across categories, matching CashFlowCards' card styling.
class CategoryBreakdownChart extends StatelessWidget {
  const CategoryBreakdownChart({super.key, required this.items, required this.currency});

  final List<CategoryBreakdownItem> items;
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
          'Nothing to break down for this period.',
          style: TextStyle(color: colors.textSecondary),
        ),
      );
    }

    final total = items.fold<int>(0, (sum, item) => sum + item.amountMinorUnits);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 150,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 36,
                sections: [
                  for (final item in items)
                    PieChartSectionData(
                      value: item.amountMinorUnits.toDouble(),
                      color: categoryStyle(item.category).color,
                      radius: 44,
                      showTitle: false,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _LegendRow(item: item, currency: currency, total: total),
            ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.item, required this.currency, required this.total});

  final CategoryBreakdownItem item;
  final String currency;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = categoryStyle(item.category);
    final percent = total == 0 ? 0 : (item.amountMinorUnits / total * 100).round();

    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: style.color, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            item.category?.name ?? 'Uncategorized',
            style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
          ),
        ),
        Text('$percent%', style: TextStyle(color: colors.textMuted, fontSize: 12)),
        const SizedBox(width: 8),
        Text(
          formatMinorUnits(item.amountMinorUnits, currency),
          style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
