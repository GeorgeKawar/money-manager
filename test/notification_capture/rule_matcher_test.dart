import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/database/database.dart';
import 'package:money_manager/features/notification_capture/domain/rule_matcher.dart';

NotificationRule _rule({
  int id = 1,
  String name = 'Test rule',
  String appPackage = 'com.bank.app',
  bool matchAnyApp = false,
  String regexPattern = r'debited.*?([\d,]+\.\d{2})',
  int amountGroup = 1,
  String transactionType = 'expense',
  int priority = 0,
  int? dateGroup,
  String? dateFormat,
  int? noteGroup,
  int? nameGroup,
}) {
  final now = DateTime(2026, 1, 1);
  return NotificationRule(
    id: id,
    name: name,
    appPackage: appPackage,
    matchAnyApp: matchAnyApp,
    isEnabled: true,
    isPreset: false,
    regexPattern: regexPattern,
    amountGroup: amountGroup,
    transactionType: transactionType,
    defaultAccountId: 1,
    autoAdd: false,
    priority: priority,
    dateGroup: dateGroup,
    dateFormat: dateFormat,
    noteGroup: noteGroup,
    nameGroup: nameGroup,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('matchRules', () {
    test('matches and parses the amount', () {
      final match = matchRules(
        rules: [_rule()],
        combinedText: 'Account debited\nYour account was debited INR 1,250.00 on 02-11-2026.',
      );
      expect(match, isNotNull);
      expect(match!.amountMinorUnits, 1250000);
      expect(match.rule.id, 1);
    });

    test('returns null when nothing matches', () {
      final match = matchRules(rules: [_rule()], combinedText: 'Unrelated notification text.');
      expect(match, isNull);
    });

    test('first matching rule in list order wins (caller sorts by priority)', () {
      final first = _rule(id: 1, priority: 0, regexPattern: r'debited ([\d.]+)');
      final second = _rule(id: 2, priority: 1, regexPattern: r'debited ([\d.]+)');
      final match = matchRules(rules: [first, second], combinedText: 'debited 10.00');
      expect(match!.rule.id, 1);
    });

    test('a later-priority rule is not evaluated once an earlier one matches', () {
      final first = _rule(id: 1, priority: 0, regexPattern: r'debited ([\d.]+)');
      final second = _rule(id: 2, priority: 1, regexPattern: r'[');
      final match = matchRules(rules: [first, second], combinedText: 'debited 10.00');
      expect(match!.rule.id, 1);
    });

    test('skips a rule with an invalid regex rather than throwing', () {
      final broken = _rule(id: 1, regexPattern: r'[');
      final working = _rule(id: 2, regexPattern: r'debited ([\d.]+)');
      final match = matchRules(rules: [broken, working], combinedText: 'debited 10.00');
      expect(match!.rule.id, 2);
    });

    test('rejects a non-positive parsed amount', () {
      final match = matchRules(rules: [_rule(regexPattern: r'debited ([\d.]+)')], combinedText: 'debited 0.00');
      expect(match, isNull);
    });

    test('matches an any-app rule regardless of its own appPackage field', () {
      final rule = _rule(matchAnyApp: true, appPackage: '', regexPattern: r'debited ([\d.]+)');
      final match = matchRules(rules: [rule], combinedText: 'debited 10.00');
      expect(match, isNotNull);
    });

    test('note falls back to the rule name when no name/note group is set', () {
      final match = matchRules(
        rules: [_rule(name: 'My rule', regexPattern: r'debited ([\d.]+)')],
        combinedText: 'debited 10.00',
      );
      expect(match!.note, 'My rule');
    });

    test('note uses the name group capture when it matches', () {
      final match = matchRules(
        rules: [_rule(regexPattern: r'(\w+) debited ([\d.]+)', amountGroup: 2, nameGroup: 1)],
        combinedText: 'Netflix debited 10.00',
      );
      expect(match!.note, 'Netflix');
    });

    test('note appends the note group capture after the name/fallback', () {
      final match = matchRules(
        rules: [
          _rule(
            name: 'My rule',
            regexPattern: r'debited ([\d.]+) for (.+)',
            amountGroup: 1,
            noteGroup: 2,
          ),
        ],
        combinedText: 'debited 10.00 for groceries',
      );
      expect(match!.note, 'My rule · groceries');
    });

    test('date is null when no date group is set', () {
      final match = matchRules(rules: [_rule(regexPattern: r'debited ([\d.]+)')], combinedText: 'debited 10.00');
      expect(match!.date, isNull);
    });

    test('date is parsed from the date group using the configured format', () {
      final match = matchRules(
        rules: [
          _rule(
            regexPattern: r'debited ([\d.]+) on (\d{2}-\d{2}-\d{4})',
            amountGroup: 1,
            dateGroup: 2,
            dateFormat: 'dd-MM-yyyy',
          ),
        ],
        combinedText: 'debited 10.00 on 02-11-2026',
      );
      expect(match!.date, DateTime(2026, 11, 2));
    });

    test('date is null when the date group fails to parse with the format', () {
      final match = matchRules(
        rules: [
          _rule(
            regexPattern: r'debited ([\d.]+) on (\w+)',
            amountGroup: 1,
            dateGroup: 2,
            dateFormat: 'dd-MM-yyyy',
          ),
        ],
        combinedText: 'debited 10.00 on notadate',
      );
      expect(match!.date, isNull);
    });
  });

  group('testRule', () {
    test('reports a successful match with the captured group and parsed amount', () {
      final result = testRule(
        regexPattern: r'debited.*?([\d,]+\.\d{2})',
        amountGroup: 1,
        sampleText: 'Your account was debited INR 1,250.00 on 02-11-2026.',
      );
      expect(result.isSuccess, isTrue);
      expect(result.rawCapturedGroup, '1,250.00');
      expect(result.amountMinorUnits, 1250000);
    });

    test('reports no match without throwing', () {
      final result = testRule(regexPattern: r'debited ([\d.]+)', amountGroup: 1, sampleText: 'unrelated text');
      expect(result.matched, isFalse);
      expect(result.isSuccess, isFalse);
    });

    test('reports an invalid regex pattern', () {
      final result = testRule(regexPattern: '[', amountGroup: 1, sampleText: 'anything');
      expect(result.regexError, isNotNull);
      expect(result.isSuccess, isFalse);
    });

    test('reports a capture group out of range', () {
      final result = testRule(regexPattern: r'debited ([\d.]+)', amountGroup: 5, sampleText: 'debited 10.00');
      expect(result.matched, isTrue);
      expect(result.regexError, isNotNull);
      expect(result.isSuccess, isFalse);
    });

    test('previews the resolved note using the rule name fallback', () {
      final result = testRule(
        regexPattern: r'debited ([\d.]+)',
        amountGroup: 1,
        sampleText: 'debited 10.00',
        ruleName: 'My rule',
      );
      expect(result.resolvedNote, 'My rule');
    });

    test('previews a successfully parsed date group', () {
      final result = testRule(
        regexPattern: r'debited ([\d.]+) on (\d{2}-\d{2}-\d{4})',
        amountGroup: 1,
        sampleText: 'debited 10.00 on 02-11-2026',
        dateGroup: 2,
        dateFormat: 'dd-MM-yyyy',
      );
      expect(result.resolvedDate, DateTime(2026, 11, 2));
      expect(result.dateError, isNull);
    });

    test('previews a date-group parse failure', () {
      final result = testRule(
        regexPattern: r'debited ([\d.]+) on (\w+)',
        amountGroup: 1,
        sampleText: 'debited 10.00 on notadate',
        dateGroup: 2,
        dateFormat: 'dd-MM-yyyy',
      );
      expect(result.resolvedDate, isNull);
      expect(result.dateError, isNotNull);
    });
  });
}
