import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/features/notification_capture/domain/date_parser.dart';

void main() {
  group('parseDateWithFormat', () {
    test('parses a matching date string', () {
      expect(parseDateWithFormat('02-11-2026', 'dd-MM-yyyy'), DateTime(2026, 11, 2));
    });

    test('returns null when the text does not match the format', () {
      expect(parseDateWithFormat('not a date', 'dd-MM-yyyy'), isNull);
    });

    test('never throws, even for a malformed format pattern', () {
      // A pattern like this is the kind of user/rule-author input that can
      // surface as something other than FormatException from intl's
      // DateFormat internals — this must never propagate uncaught, since
      // it runs on the headless-engine dispatch path with no surrounding
      // try/catch. The exact return value isn't the point; not throwing is.
      expect(() => parseDateWithFormat('02-11-2026', "dd-MM-yyyy'"), returnsNormally);
      expect(() => parseDateWithFormat('anything', '###bogus###'), returnsNormally);
    });
  });
}
