import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/features/notification_capture/domain/amount_parser.dart';

void main() {
  group('parseAmountToMinorUnits', () {
    test('parses a plain decimal amount', () {
      expect(parseAmountToMinorUnits('25.00'), 25000);
    });

    test('strips thousands separators', () {
      expect(parseAmountToMinorUnits('1,234.56'), 1234560);
    });

    test('strips currency symbols and spaces', () {
      expect(parseAmountToMinorUnits('\$ 42.00'), 42000);
      expect(parseAmountToMinorUnits('USD 42.00'), 42000);
    });

    test('handles an amount with no decimal point', () {
      expect(parseAmountToMinorUnits('500'), 500000);
    });

    test('ignores a leading sign', () {
      expect(parseAmountToMinorUnits('-25.00'), 25000);
    });

    test('returns null for unparseable text', () {
      expect(parseAmountToMinorUnits('not a number'), isNull);
      expect(parseAmountToMinorUnits(''), isNull);
    });
  });
}
