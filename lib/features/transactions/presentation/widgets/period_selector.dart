import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_period.dart';
import '../period_providers.dart';

class PeriodNavigator extends ConsumerWidget {
  const PeriodNavigator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(activeDateRangeProvider);
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _NavButton(
          icon: Icons.chevron_left,
          onTap: () => _shift(ref, range.previous()),
        ),
        SizedBox(
          width: 130,
          child: Text(
            range.label,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
          ),
        ),
        _NavButton(
          icon: Icons.chevron_right,
          onTap: () => _shift(ref, range.next()),
        ),
      ],
    );
  }

  /// A custom range has no single reference date (see [DateRange.customRange]),
  /// so shifting it updates [customDateRangeProvider] directly instead of
  /// [periodReferenceDateProvider].
  void _shift(WidgetRef ref, DateRange shifted) {
    if (shifted.period == Period.custom) {
      ref.read(customDateRangeProvider.notifier).state = shifted;
    } else {
      ref.read(periodReferenceDateProvider.notifier).state = shifted.start;
    }
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, color: colors.textSecondary, size: 20),
      ),
    );
  }
}

class PeriodSegmentedControl extends ConsumerWidget {
  const PeriodSegmentedControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final selected = ref.watch(selectedPeriodProvider);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: Period.values.map((period) {
          final isSelected = period == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => _select(context, ref, period),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? colors.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(
                  _label(period),
                  style: TextStyle(
                    color: isSelected ? colors.textPrimary : colors.textSecondary,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _label(Period period) => switch (period) {
        Period.day => 'Day',
        Period.week => 'Week',
        Period.month => 'Month',
        Period.year => 'Year',
        Period.custom => 'Custom',
      };

  /// Switching to a preset period is instant, same as before. [Period.custom]
  /// instead opens a date-range picker; picking Custom again later re-opens
  /// it pre-filled with the current range, letting the user adjust it. If
  /// the user cancels the picker, the current selection is left unchanged.
  Future<void> _select(BuildContext context, WidgetRef ref, Period period) async {
    if (period != Period.custom) {
      ref.read(selectedPeriodProvider.notifier).state = period;
      ref.read(periodReferenceDateProvider.notifier).state = DateTime.now();
      return;
    }

    final existing = ref.read(customDateRangeProvider);
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 10),
      initialDateRange: existing != null
          ? DateTimeRange(start: existing.start, end: existing.end.subtract(const Duration(days: 1)))
          : DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now),
    );
    if (picked == null) return;

    final start = DateTime(picked.start.year, picked.start.month, picked.start.day);
    final end = DateTime(picked.end.year, picked.end.month, picked.end.day).add(const Duration(days: 1));
    ref.read(customDateRangeProvider.notifier).state = DateRange.customRange(start: start, end: end);
    ref.read(selectedPeriodProvider.notifier).state = Period.custom;
  }
}
