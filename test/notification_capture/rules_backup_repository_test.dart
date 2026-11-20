import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/database/database.dart';
import 'package:money_manager/features/notification_capture/data/rules_backup_repository.dart';

void main() {
  late AppDatabase db;
  late RulesBackupRepository repo;

  // AppDatabase.forTesting seeds one account ('Cash', id 1) and the default
  // category set (including 'Food') on open.
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = RulesBackupRepository(db);
  });

  tearDown(() => db.close());

  Future<int> addAccount(String name) {
    return db.into(db.accounts).insert(AccountsCompanion.insert(name: name));
  }

  Future<int> addRule({
    required String name,
    required int defaultAccountId,
    int? defaultCategoryId,
    String appPackage = 'com.bank.app',
    bool matchAnyApp = false,
    String regexPattern = r'debited ([\d.]+)',
  }) {
    return db.into(db.notificationRules).insert(
          NotificationRulesCompanion.insert(
            name: name,
            appPackage: appPackage,
            matchAnyApp: Value(matchAnyApp),
            regexPattern: regexPattern,
            transactionType: 'expense',
            defaultAccountId: defaultAccountId,
            defaultCategoryId: Value(defaultCategoryId),
          ),
        );
  }

  group('export then import', () {
    test('round-trips a rule by resolving its account/category by name', () async {
      final foodId = (await db.select(db.categories).get()).firstWhere((c) => c.name == 'Food').id;
      await addRule(name: 'Bank rule', defaultAccountId: 1, defaultCategoryId: foodId);

      final json = await repo.exportToJson();

      // Simulate a fresh device: wipe the rule so the re-import can't be
      // seen as a duplicate of itself.
      await db.delete(db.notificationRules).go();

      final preview = await repo.parseImport(json);
      expect(preview.importable, hasLength(1));
      expect(preview.importable.single.resolvedAccountId, 1);
      expect(preview.importable.single.resolvedCategoryId, foodId);

      await repo.applyImport(preview);
      final rules = await db.select(db.notificationRules).get();
      expect(rules.single.name, 'Bank rule');
      expect(rules.single.defaultAccountId, 1);
      expect(rules.single.defaultCategoryId, foodId);
    });
  });

  group('parseImport resolution', () {
    test('marks a rule unresolvable when its account name has no match on this device', () async {
      final otherAccountId = await addAccount('Chase Checking');
      await addRule(name: 'Chase rule', defaultAccountId: otherAccountId);
      final json = await repo.exportToJson();

      // The destination device never had "Chase Checking" — delete it to
      // simulate importing on a different device.
      await db.delete(db.notificationRules).go();
      await (db.delete(db.accounts)..where((a) => a.id.equals(otherAccountId))).go();

      final preview = await repo.parseImport(json);
      expect(preview.unresolvable, hasLength(1));
      expect(preview.missingNames, contains('Chase Checking'));
      expect(preview.importable, isEmpty);
    });

    test('marks a rule as duplicate when the same name/scope/regex already exists', () async {
      await addRule(name: 'Bank rule', defaultAccountId: 1);
      final json = await repo.exportToJson();

      // Re-parsing without deleting the original rule first — it's still
      // there, so this is the "re-import the same file twice" case.
      final preview = await repo.parseImport(json);
      expect(preview.duplicates, hasLength(1));
      expect(preview.importable, isEmpty);
    });

    test('a rule with no category reference always resolves cleanly', () async {
      await addRule(name: 'No category rule', defaultAccountId: 1);
      final json = await repo.exportToJson();
      await db.delete(db.notificationRules).go();

      final preview = await repo.parseImport(json);
      expect(preview.importable.single.resolvedCategoryId, null);
    });
  });

  group('applyImport', () {
    test('appends imported rules after existing ones, never replacing anything', () async {
      await addRule(name: 'Existing rule', defaultAccountId: 1);
      final existingId = (await db.select(db.notificationRules).get()).single.id;

      final otherDb = AppDatabase.forTesting(NativeDatabase.memory());
      final otherRepo = RulesBackupRepository(otherDb);
      await otherDb.into(otherDb.notificationRules).insert(
            NotificationRulesCompanion.insert(
              name: 'Imported rule',
              appPackage: 'com.other.app',
              regexPattern: r'charged ([\d.]+)',
              transactionType: 'expense',
              defaultAccountId: 1,
            ),
          );
      final json = await otherRepo.exportToJson();
      await otherDb.close();

      final preview = await repo.parseImport(json);
      await repo.applyImport(preview);

      final rules = await db.select(db.notificationRules).get();
      expect(rules, hasLength(2));
      expect(rules.firstWhere((r) => r.id == existingId).name, 'Existing rule');
      final imported = rules.firstWhere((r) => r.name == 'Imported rule');
      expect(imported.priority, greaterThan(rules.firstWhere((r) => r.id == existingId).priority));
    });
  });

  group('parseImport validation', () {
    test('rejects text that is not valid JSON', () async {
      await expectLater(repo.parseImport('not json'), throwsA(isA<RulesBackupFormatException>()));
    });

    test('rejects a JSON document that is not an object', () async {
      await expectLater(repo.parseImport('[1, 2, 3]'), throwsA(isA<RulesBackupFormatException>()));
    });

    test('rejects an incompatible export format version', () async {
      await expectLater(
        repo.parseImport('{"fileType": "money_manager_rules_export", "exportFormatVersion": 999}'),
        throwsA(isA<RulesBackupFormatException>()),
      );
    });

    test('rejects a full data export with a specific message', () async {
      const fullExportJson = '{"appSettings": {}, "accounts": []}';
      await expectLater(
        repo.parseImport(fullExportJson),
        throwsA(isA<RulesBackupFormatException>().having(
          (e) => e.message,
          'message',
          contains('full data export'),
        )),
      );
    });

    test('rejects a document missing expected fields', () async {
      await expectLater(
        repo.parseImport('{"fileType": "money_manager_rules_export", "exportFormatVersion": 1}'),
        throwsA(isA<RulesBackupFormatException>()),
      );
    });
  });
}
