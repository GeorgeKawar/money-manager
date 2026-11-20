import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/database/database.dart';
import 'package:money_manager/features/accounts/data/accounts_repository.dart';

void main() {
  late AppDatabase db;
  late AccountsRepository repo;

  // AppDatabase.forTesting seeds one account ('Cash', id 1) — see
  // AppDatabase.onCreate.
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AccountsRepository(db);
  });

  tearDown(() => db.close());

  Future<int> addAccount(String name) {
    return db.into(db.accounts).insert(AccountsCompanion.insert(name: name));
  }

  group('isUnused', () {
    test('is true for an account with no references', () async {
      final id = await addAccount('Spare wallet');

      expect(await repo.isUnused(id), isTrue);
    });

    test('is false when a transaction references the account', () async {
      final id = await addAccount('Spare wallet');
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              accountId: id,
              type: 'income',
              amountMinorUnits: 1000,
              currency: 'USD',
              date: DateTime(2026, 11, 15),
            ),
          );

      expect(await repo.isUnused(id), isFalse);
    });

    test('is false when a recurring transaction references the account', () async {
      final id = await addAccount('Spare wallet');
      await db.into(db.recurringTransactions).insert(
            RecurringTransactionsCompanion.insert(
              accountId: id,
              type: 'expense',
              amountMinorUnits: 1000,
              frequency: 'monthly',
              startDate: DateTime(2026, 11, 15),
              nextRunDate: DateTime(2026, 12, 15),
            ),
          );

      expect(await repo.isUnused(id), isFalse);
    });

    test('is false when a notification rule defaults to the account', () async {
      final id = await addAccount('Spare wallet');
      await db.into(db.notificationRules).insert(
            NotificationRulesCompanion.insert(
              name: 'Rule',
              appPackage: 'com.bank.app',
              regexPattern: r'debited ([\d.]+)',
              transactionType: 'expense',
              defaultAccountId: id,
            ),
          );

      expect(await repo.isUnused(id), isFalse);
    });
  });

  group('updateAccount', () {
    test('persists includeInAllTimeBalance', () async {
      final id = await addAccount('Spare wallet');

      await repo.updateAccount(id, name: 'Spare wallet', startingBalanceMinorUnits: 0, includeInAllTimeBalance: false);

      final account = await (db.select(db.accounts)..where((a) => a.id.equals(id))).getSingle();
      expect(account.includeInAllTimeBalance, isFalse);
    });

    test('defaults a newly-inserted account to includeInAllTimeBalance = true', () async {
      final id = await addAccount('Spare wallet');

      final account = await (db.select(db.accounts)..where((a) => a.id.equals(id))).getSingle();
      expect(account.includeInAllTimeBalance, isTrue);
    });
  });

  group('deleteAccount', () {
    test('removes the account row', () async {
      final id = await addAccount('Spare wallet');

      await repo.deleteAccount(id);

      final remaining = await (db.select(db.accounts)..where((a) => a.id.equals(id))).getSingleOrNull();
      expect(remaining, isNull);
    });
  });
}
