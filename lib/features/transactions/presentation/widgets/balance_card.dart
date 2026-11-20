import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_format.dart';

class BalanceCard extends StatelessWidget {
  const BalanceCard({
    super.key,
    required this.balanceMinorUnits,
    required this.currency,
    this.onTapAdjust,
    this.isMasked = false,
    this.onToggleMask,
  });

  final int balanceMinorUnits;
  final String currency;

  /// Opens the "adjust all-time balance" sheet — see docs/data-model.md
  /// "Derived/computed". Null hides the edit affordance.
  final VoidCallback? onTapAdjust;

  /// Privacy toggle (2026-11-20, user request) — see AppSettings
  /// `isBalanceMasked`. True shows a fixed-width mask instead of the real
  /// amount.
  final bool isMasked;

  /// Flips [isMasked]. Null hides the eye-icon affordance.
  final VoidCallback? onToggleMask;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.accent,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ALL-TIME BALANCE',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.onAccent.withValues(alpha: 0.7)),
              ),
              Row(
                children: [
                  if (onToggleMask != null) ...[
                    Tooltip(
                      message: isMasked ? 'Show balance' : 'Hide balance',
                      child: InkWell(
                        onTap: onToggleMask,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: colors.onAccent.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isMasked ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            color: colors.onAccent,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (onTapAdjust != null)
                    Tooltip(
                      message: 'Adjust all-time balance',
                      child: InkWell(
                        onTap: onTapAdjust,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: colors.onAccent.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.edit_outlined, color: colors.onAccent, size: 18),
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colors.onAccent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.show_chart, color: colors.onAccent, size: 18),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            isMasked ? '•••••' : formatMinorUnits(balanceMinorUnits, currency),
            style: TextStyle(
              color: colors.onAccent,
              fontSize: 36,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your income minus expenses',
            style: TextStyle(color: colors.onAccent.withValues(alpha: 0.7), fontSize: 13),
          ),
        ],
      ),
    );
  }
}
