import 'package:intl/intl.dart';

/// The filter granularities from docs/features/transactions.md. [custom] is
/// a user-picked arbitrary range (added 2026-11-09), not derived from a
/// single reference date like the other four — see [DateRange.customRange].
enum Period { day, week, month, year, custom }

/// An inclusive-start, exclusive-end date range for a given [Period],
/// anchored at some reference date within it.
class DateRange {
  const DateRange({required this.period, required this.start, required this.end});

  final Period period;
  final DateTime start; // inclusive
  final DateTime end; // exclusive

  bool contains(DateTime date) => !date.isBefore(start) && date.isBefore(end);

  /// A custom range's own length, re-applied by [next]/[previous] instead
  /// of a calendar-unit shift — there's no natural "next month"-style step
  /// for an arbitrary range, so it repeats the same span forward/backward.
  Duration get _customSpan => end.difference(start);

  DateRange next() => period == Period.custom
      ? DateRange.customRange(start: start.add(_customSpan), end: end.add(_customSpan))
      : DateRange.forPeriod(period, _shift(1));

  DateRange previous() => period == Period.custom
      ? DateRange.customRange(start: start.subtract(_customSpan), end: end.subtract(_customSpan))
      : DateRange.forPeriod(period, _shift(-1));

  DateTime _shift(int direction) {
    switch (period) {
      case Period.day:
        return start.add(Duration(days: direction));
      case Period.week:
        return start.add(Duration(days: 7 * direction));
      case Period.month:
        return DateTime(start.year, start.month + direction, 1);
      case Period.year:
        return DateTime(start.year + direction, 1, 1);
      case Period.custom:
        throw StateError('Period.custom shifts via next()/previous() directly, not _shift().');
    }
  }

  /// Builds the range containing [reference] for the given [period].
  /// Weeks start on Monday. Not valid for [Period.custom] — use
  /// [DateRange.customRange] instead, since a custom range needs two
  /// independent dates, not one reference date.
  factory DateRange.forPeriod(Period period, DateTime reference) {
    switch (period) {
      case Period.day:
        final start = DateTime(reference.year, reference.month, reference.day);
        return DateRange(period: period, start: start, end: start.add(const Duration(days: 1)));
      case Period.week:
        final startOfDay = DateTime(reference.year, reference.month, reference.day);
        final start = startOfDay.subtract(Duration(days: startOfDay.weekday - DateTime.monday));
        return DateRange(period: period, start: start, end: start.add(const Duration(days: 7)));
      case Period.month:
        final start = DateTime(reference.year, reference.month, 1);
        final end = DateTime(reference.year, reference.month + 1, 1);
        return DateRange(period: period, start: start, end: end);
      case Period.year:
        final start = DateTime(reference.year, 1, 1);
        final end = DateTime(reference.year + 1, 1, 1);
        return DateRange(period: period, start: start, end: end);
      case Period.custom:
        throw ArgumentError('Period.custom has no single-reference range — use DateRange.customRange(start, end).');
    }
  }

  /// A user-picked arbitrary [start, end) range (e.g. from a date-range
  /// picker) — see docs/features/transactions.md "Filtering by period".
  /// [end] is exclusive like every other period's range, so pass the day
  /// *after* the last day to include (callers normalize a picker's
  /// inclusive end date before calling this — see `PeriodSegmentedControl`).
  factory DateRange.customRange({required DateTime start, required DateTime end}) {
    return DateRange(period: Period.custom, start: start, end: end);
  }

  /// Human label matching the design mockup, e.g. "November 2026" for a
  /// month, "2026" for a year, "Jan 5 – Jan 11" for a week.
  String get label {
    switch (period) {
      case Period.day:
        return DateFormat.yMMMd().format(start);
      case Period.week:
        final lastDay = end.subtract(const Duration(days: 1));
        final sameMonth = start.month == lastDay.month;
        final startLabel = DateFormat.MMMd().format(start);
        final endLabel = sameMonth ? DateFormat.d().format(lastDay) : DateFormat.MMMd().format(lastDay);
        return '$startLabel – $endLabel';
      case Period.month:
        return DateFormat.yMMMM().format(start);
      case Period.year:
        return DateFormat.y().format(start);
      case Period.custom:
        final lastDay = end.subtract(const Duration(days: 1));
        final sameYear = start.year == lastDay.year;
        final startLabel = sameYear ? DateFormat.MMMd().format(start) : DateFormat.yMMMd().format(start);
        final endLabel = DateFormat.yMMMd().format(lastDay);
        return '$startLabel – $endLabel';
    }
  }
}

/// "Today" / "Yesterday" for the last two days, otherwise a short date
/// (e.g. "Nov 2"), used on transaction list rows.
String relativeDateLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final difference = today.difference(day).inDays;
  if (difference == 0) return 'Today';
  if (difference == 1) return 'Yesterday';
  return DateFormat.MMMd().format(date);
}

/// [relativeDateLabel] plus the time of day — transactions carry a full
/// timestamp (see docs/data-model.md `Transaction.date`), and the add/edit
/// sheet lets the user enter it, so list rows show it too.
String relativeDateTimeLabel(DateTime date) {
  return '${relativeDateLabel(date)}, ${DateFormat.jm().format(date)}';
}
