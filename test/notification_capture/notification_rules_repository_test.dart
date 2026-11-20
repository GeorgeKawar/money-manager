import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/database/database.dart';
import 'package:money_manager/features/notification_capture/data/notification_rules_repository.dart';

void main() {
  late AppDatabase db;
  late NotificationRulesRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = NotificationRulesRepository(db);
  });

  tearDown(() => db.close());

  Future<int> addRule({
    String name = 'Rule',
    String appPackage = 'com.bank.app',
    bool matchAnyApp = false,
  }) {
    return repo.addRule(
      name: name,
      appPackage: appPackage,
      matchAnyApp: matchAnyApp,
      regexPattern: r'debited ([\d.]+)',
      amountGroup: 1,
      transactionType: 'expense',
      defaultAccountId: 1,
      autoAdd: false,
    );
  }

  test('new rules are auto-appended with an increasing priority', () async {
    final first = await addRule(name: 'First');
    final second = await addRule(name: 'Second');

    final rules = await (db.select(db.notificationRules)..orderBy([(r) => OrderingTerm.asc(r.priority)])).get();
    expect(rules.map((r) => r.id), [first, second]);
    expect(rules[0].priority < rules[1].priority, isTrue);
  });

  test('enabledRulesForPackage returns rules ordered by priority ascending', () async {
    final second = await addRule(name: 'Second', appPackage: 'com.bank.app');
    await repo.updateRule(
      second,
      name: 'Second',
      appPackage: 'com.bank.app',
      regexPattern: r'debited ([\d.]+)',
      amountGroup: 1,
      transactionType: 'expense',
      defaultAccountId: 1,
      autoAdd: false,
      priority: 0,
    );
    final first = await addRule(name: 'First', appPackage: 'com.bank.app');
    await repo.updateRule(
      first,
      name: 'First',
      appPackage: 'com.bank.app',
      regexPattern: r'debited ([\d.]+)',
      amountGroup: 1,
      transactionType: 'expense',
      defaultAccountId: 1,
      autoAdd: false,
      priority: -1,
    );

    final rules = await repo.enabledRulesForPackage('com.bank.app');
    expect(rules.map((r) => r.id), [first, second]);
  });

  test('enabledRulesForPackage includes any-app rules alongside package matches', () async {
    final anyApp = await addRule(name: 'Any', appPackage: '', matchAnyApp: true);
    final specific = await addRule(name: 'Specific', appPackage: 'com.other.app');

    final rules = await repo.enabledRulesForPackage('com.other.app');
    expect(rules.map((r) => r.id), containsAll([anyApp, specific]));
  });

  test('rules with equal priority (e.g. after a pre-priority migration) break ties by id', () async {
    final first = await addRule(name: 'First', appPackage: 'com.bank.app');
    final second = await addRule(name: 'Second', appPackage: 'com.bank.app');
    // Simulate two rules sharing a priority, as every rule does immediately
    // after the v1->v2 migration (all default to 0).
    await repo.updateRule(
      second,
      name: 'Second',
      appPackage: 'com.bank.app',
      regexPattern: r'debited ([\d.]+)',
      amountGroup: 1,
      transactionType: 'expense',
      defaultAccountId: 1,
      autoAdd: false,
      priority: 0,
    );
    await repo.updateRule(
      first,
      name: 'First',
      appPackage: 'com.bank.app',
      regexPattern: r'debited ([\d.]+)',
      amountGroup: 1,
      transactionType: 'expense',
      defaultAccountId: 1,
      autoAdd: false,
      priority: 0,
    );

    final rules = await repo.enabledRulesForPackage('com.bank.app');
    expect(rules.map((r) => r.id), [first, second]);
  });

  test('updateRule with a blank priority auto-appends to the end, same as addRule', () async {
    final first = await addRule(name: 'First');
    final second = await addRule(name: 'Second');

    await repo.updateRule(
      first,
      name: 'First',
      appPackage: 'com.bank.app',
      regexPattern: r'debited ([\d.]+)',
      amountGroup: 1,
      transactionType: 'expense',
      defaultAccountId: 1,
      autoAdd: false,
      priority: null,
    );

    final rules = await (db.select(db.notificationRules)..orderBy([(r) => OrderingTerm.asc(r.priority)])).get();
    expect(rules.map((r) => r.id), [second, first]);
  });

  test('reorderRules persists the new priority order', () async {
    final a = await addRule(name: 'A');
    final b = await addRule(name: 'B');
    final c = await addRule(name: 'C');

    await repo.reorderRules([c, a, b]);

    final rules = await (db.select(db.notificationRules)..orderBy([(r) => OrderingTerm.asc(r.priority)])).get();
    expect(rules.map((r) => r.id), [c, a, b]);
  });
}
