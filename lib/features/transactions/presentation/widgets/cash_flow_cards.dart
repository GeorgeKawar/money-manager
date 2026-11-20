import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_format.dart';

class CashFlowCards extends StatelessWidget {
  const CashFlowCards({
    super.key,
    required this.incomeMinorUnits,
    required this.expenseMinorUnits,
    required this.currency,
  });

  final int incomeMinorUnits;
  final int expenseMinorUnits;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Income',
            amountMinorUnits: incomeMinorUnits,
            currency: currency,
            icon: Icons.south_west,
            color: context.colors.income,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'Expenses',
            amountMinorUnits: expenseMinorUnits,
            currency: currency,
            icon: Icons.north_east,
            color: context.colors.expense,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.amountMinorUnits,
    required this.currency,
    required this.icon,
    required this.color,
  });

  final String label;
  final int amountMinorUnits;
  final String currency;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            formatMinorUnits(amountMinorUnits, currency),
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 18),
          ),
        ],
      ),
    );
  }
}
