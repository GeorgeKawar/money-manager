import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/utils/date_period.dart';

void main() {
  group('DateRange.customRange', () {
    test('contains dates within [start, end) and excludes the end date', () {
      final range = DateRange.customRange(start: DateTime(2026, 11, 1), end: DateTime(2026, 11, 11));

      expect(range.contains(DateTime(2026, 11, 1)), isTrue);
      expect(range.contains(DateTime(2026, 11, 10, 23, 59)), isTrue);
      expect(range.contains(DateTime(2026, 11, 11)), isFalse);
      expect(range.period, Period.custom);
    });

    test('next()/previous() repeat the same span forward/backward', () {
      final range = DateRange.customRange(start: DateTime(2026, 11, 1), end: DateTime(2026, 11, 11));

      final next = range.next();
      expect(next.start, DateTime(2026, 11, 11));
      expect(next.end, DateTime(2026, 11, 21));
      expect(next.period, Period.custom);

      final previous = range.previous();
      expect(previous.start, DateTime(2026, 10, 22));
      expect(previous.end, DateTime(2026, 11, 1));
    });

    test('label shows both dates, with year once when same year', () {
      final range = DateRange.customRange(start: DateTime(2026, 11, 1), end: DateTime(2026, 11, 11));
      expect(range.label, 'Nov 1 – Nov 10, 2026');
    });

    test('label shows the year on both dates when they differ', () {
      final range = DateRange.customRange(start: DateTime(2025, 12, 28), end: DateTime(2026, 1, 3));
      expect(range.label, 'Dec 28, 2025 – Jan 2, 2026');
    });
  });

  group('DateRange.forPeriod', () {
    test('throws for Period.custom — use DateRange.customRange instead', () {
      expect(() => DateRange.forPeriod(Period.custom, DateTime.now()), throwsArgumentError);
    });
  });
}
