import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/database/database.dart';
import 'package:money_manager/features/backup/data/backup_repository.dart';

void main() {
  late AppDatabase db;
  late BackupRepository repo;

  // AppDatabase.forTesting seeds one account ('Cash', id 1) and the default
  // category set on open — see AppDatabase._seedDefaultCategories.
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = BackupRepository(db);
  });

  tearDown(() => db.close());

  Future<int> addCategory(String name, String type) {
    return db.into(db.categories).insert(CategoriesCompanion.insert(name: name, type: type));
  }

  Future<int> addTransaction({required int accountId, int? categoryId, required String type, required int amountMinorUnits}) {
    return db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            accountId: accountId,
            categoryId: Value(categoryId),
            type: type,
            amountMinorUnits: amountMinorUnits,
            currency: 'USD',
            date: DateTime(2026, 11, 1),
          ),
        );
  }

  Future<int> addNotificationRule() {
    return db.into(db.notificationRules).insert(
          NotificationRulesCompanion.insert(
            name: 'Test bank',
            appPackage: 'com.bank.app',
            regexPattern: r'debited ([\d.]+)',
            transactionType: 'expense',
            defaultAccountId: 1,
          ),
        );
  }

  Future<int> addRecurringTransaction() {
    return db.into(db.recurringTransactions).insert(
          RecurringTransactionsCompanion.insert(
            accountId: 1,
            type: 'expense',
            amountMinorUnits: 1000,
            frequency: 'monthly',
            startDate: DateTime(2026, 1, 1),
            nextRunDate: DateTime(2026, 12, 1),
          ),
        );
  }

  group('export then import', () {
    test('round-trips every table, preserving ids and relationships', () async {
      final food = await addCategory('Food', 'expense');
      final txnId = await addTransaction(accountId: 1, categoryId: food, type: 'expense', amountMinorUnits: 2500);
      final ruleId = await addNotificationRule();
      final recurringId = await addRecurringTransaction();

      final json = await repo.exportToJson();
      final preview = repo.parseImport(json);

      expect(preview.accounts.map((a) => a.id), contains(1));
      expect(preview.categories.map((c) => c.id), contains(food));
      expect(preview.transactions.single.id, txnId);
      expect(preview.transactions.single.categoryId, food);
      expect(preview.notificationRules.single.id, ruleId);
      expect(preview.recurringTransactions.single.id, recurringId);
      expect(preview.appSettings.defaultCurrency, 'USD');
    });

    test('still imports an older export missing allTimeBalanceAdjustmentMinorUnits', () async {
      final decoded = jsonDecode(await repo.exportToJson()) as Map<String, dynamic>;
      (decoded['appSettings'] as Map<String, dynamic>).remove('allTimeBalanceAdjustmentMinorUnits');

      final preview = repo.parseImport(jsonEncode(decoded));

      expect(preview.appSettings.allTimeBalanceAdjustmentMinorUnits, 0);
    });

    test('still imports an older export missing includeArchivedInAllTimeBalance', () async {
      final decoded = jsonDecode(await repo.exportToJson()) as Map<String, dynamic>;
      (decoded['appSettings'] as Map<String, dynamic>).remove('includeArchivedInAllTimeBalance');

      final preview = repo.parseImport(jsonEncode(decoded));

      expect(preview.appSettings.includeArchivedInAllTimeBalance, false);
    });

    test('still imports an older export missing Account.isDefault', () async {
      final decoded = jsonDecode(await repo.exportToJson()) as Map<String, dynamic>;
      for (final account in decoded['accounts'] as List) {
        (account as Map<String, dynamic>).remove('isDefault');
      }

      final preview = repo.parseImport(jsonEncode(decoded));

      expect(preview.accounts.single.isDefault, false);
    });
  });

  group('applyImport', () {
    test('replaces existing data and restores app settings to the exported values', () async {
      final food = await addCategory('Food', 'expense');
      await addTransaction(accountId: 1, categoryId: food, type: 'expense', amountMinorUnits: 2500);
      final preview = repo.parseImport(await repo.exportToJson());

      // Drift after the export, to prove import is destructive-replace, not
      // merge: an extra transaction and a changed currency setting.
      await addTransaction(accountId: 1, categoryId: null, type: 'income', amountMinorUnits: 9999);
      await db.update(db.appSettingsTable).write(const AppSettingsTableCompanion(defaultCurrency: Value('EUR')));

      await repo.applyImport(preview);

      final transactions = await db.select(db.transactions).get();
      expect(transactions, hasLength(1));
      expect(transactions.single.amountMinorUnits, 2500);
      expect(transactions.single.categoryId, food);

      final settings = await db.select(db.appSettingsTable).getSingle();
      expect(settings.defaultCurrency, 'USD');
    });
  });

  group('parseImport validation', () {
    test('rejects text that is not valid JSON', () {
      expect(() => repo.parseImport('not json'), throwsA(isA<BackupFormatException>()));
    });

    test('rejects a JSON document that is not an object', () {
      expect(() => repo.parseImport('[1, 2, 3]'), throwsA(isA<BackupFormatException>()));
    });

    test('rejects an incompatible export format version', () {
      expect(
        () => repo.parseImport('{"exportFormatVersion": 999}'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('rejects a document missing expected fields', () {
      expect(
        () => repo.parseImport('{"exportFormatVersion": 1}'),
        throwsA(isA<BackupFormatException>()),
      );
    });
  });
}
