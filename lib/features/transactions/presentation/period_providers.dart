import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/date_period.dart';

/// Currently selected period granularity on the dashboard (Day/Week/Month/Year).
final selectedPeriodProvider = StateProvider<Period>((ref) => Period.month);

/// The reference date used to compute the active [DateRange] — advanced by
/// the ‹ › navigator independently per granularity switch, but reset to
/// "now" whenever the user changes granularity (matches the mockup, which
/// defaults each filter to the current period).
final periodReferenceDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

/// Set only while [selectedPeriodProvider] is [Period.custom] — the
/// user-picked range from `PeriodSegmentedControl`'s date-range picker.
final customDateRangeProvider = StateProvider<DateRange?>((ref) => null);

final activeDateRangeProvider = Provider<DateRange>((ref) {
  final period = ref.watch(selectedPeriodProvider);
  if (period == Period.custom) {
    return ref.watch(customDateRangeProvider) ?? DateRange.forPeriod(Period.month, DateTime.now());
  }
  final reference = ref.watch(periodReferenceDateProvider);
  return DateRange.forPeriod(period, reference);
});
