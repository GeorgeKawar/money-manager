import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/database/database.dart';
import 'package:money_manager/core/utils/date_period.dart';
import 'package:money_manager/features/transactions/data/transactions_repository.dart';

void main() {
  late AppDatabase db;
  late TransactionsRepository repo;

  // AppDatabase.forTesting seeds one account ('Cash', id 1) with a zero
  // starting balance — see AppDatabase._seedDefaultCategories/onCreate.
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TransactionsRepository(db);
  });

  tearDown(() => db.close());

  Future<int> addAccount(
    String name, {
    int startingBalanceMinorUnits = 0,
    bool isArchived = false,
    bool includeInAllTimeBalance = true,
  }) {
    return db.into(db.accounts).insert(
          AccountsCompanion.insert(
            name: name,
            startingBalanceMinorUnits: Value(startingBalanceMinorUnits),
            isArchived: Value(isArchived),
            includeInAllTimeBalance: Value(includeInAllTimeBalance),
          ),
        );
  }

  Future<void> addTransaction({
    required int accountId,
    required String type,
    required int amountMinorUnits,
    bool isPendingReview = false,
    int? categoryId,
  }) {
    return db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            accountId: accountId,
            categoryId: Value(categoryId),
            type: type,
            amountMinorUnits: amountMinorUnits,
            currency: 'USD',
            date: DateTime(2026, 11, 15),
            isPendingReview: Value(isPendingReview),
          ),
        );
  }

  group('watchAllTimeBalanceMinorUnits', () {
    test('sums starting balances and confirmed income/expense transactions across accounts', () async {
      final savings = await addAccount('Savings', startingBalanceMinorUnits: 10000);
      await addTransaction(accountId: 1, type: 'income', amountMinorUnits: 5000);
      await addTransaction(accountId: 1, type: 'expense', amountMinorUnits: 2000);
      await addTransaction(accountId: savings, type: 'income', amountMinorUnits: 1000);

      final balance = await repo.watchAllTimeBalanceMinorUnits().first;

      expect(balance, 10000 + 5000 - 2000 + 1000);
    });

    test('excludes an archived account and its transactions from the total', () async {
      final archived = await addAccount('Old wallet', startingBalanceMinorUnits: 20000, isArchived: true);
      await addTransaction(accountId: archived, type: 'income', amountMinorUnits: 5000);
      await addTransaction(accountId: 1, type: 'income', amountMinorUnits: 3000);

      final balance = await repo.watchAllTimeBalanceMinorUnits().first;

      expect(balance, 3000);
    });

    test('excludes pending-review and transfer transactions', () async {
      await addTransaction(accountId: 1, type: 'income', amountMinorUnits: 5000, isPendingReview: true);
      await addTransaction(accountId: 1, type: 'transfer', amountMinorUnits: 9999);

      final balance = await repo.watchAllTimeBalanceMinorUnits().first;

      expect(balance, 0);
    });

    test('includes an archived account and its transactions when includeArchivedInAllTimeBalance is true', () async {
      final archived = await addAccount('Old wallet', startingBalanceMinorUnits: 20000, isArchived: true);
      await addTransaction(accountId: archived, type: 'income', amountMinorUnits: 5000);
      await addTransaction(accountId: 1, type: 'income', amountMinorUnits: 3000);
      await (db.update(db.appSettingsTable)).write(
        const AppSettingsTableCompanion(includeArchivedInAllTimeBalance: Value(true)),
      );

      final balance = await repo.watchAllTimeBalanceMinorUnits().first;

      expect(balance, 20000 + 5000 + 3000);
    });

    test('excludes an active account with includeInAllTimeBalance = false', () async {
      final excluded = await addAccount('Side fund', startingBalanceMinorUnits: 5000, includeInAllTimeBalance: false);
      await addTransaction(accountId: excluded, type: 'income', amountMinorUnits: 1000);
      await addTransaction(accountId: 1, type: 'income', amountMinorUnits: 3000);

      final balance = await repo.watchAllTimeBalanceMinorUnits().first;

      expect(balance, 3000);
    });

    test('excludes an archived account even when includeArchivedInAllTimeBalance is true, if its own flag is false',
        () async {
      final archived = await addAccount(
        'Old wallet',
        startingBalanceMinorUnits: 20000,
        isArchived: true,
        includeInAllTimeBalance: false,
      );
      await addTransaction(accountId: archived, type: 'income', amountMinorUnits: 5000);
      await addTransaction(accountId: 1, type: 'income', amountMinorUnits: 3000);
      await (db.update(db.appSettingsTable)).write(
        const AppSettingsTableCompanion(includeArchivedInAllTimeBalance: Value(true)),
      );

      final balance = await repo.watchAllTimeBalanceMinorUnits().first;

      expect(balance, 3000);
    });

    test('adds the manual adjustment from AppSettings on top of the computed total', () async {
      await addTransaction(accountId: 1, type: 'income', amountMinorUnits: 5000);
      await (db.update(db.appSettingsTable)).write(
        const AppSettingsTableCompanion(allTimeBalanceAdjustmentMinorUnits: Value(-5000)),
      );

      final balance = await repo.watchAllTimeBalanceMinorUnits().first;

      expect(balance, 0);
    });
  });

  group('watchPeriodTransactions / watchPeriodSummary category+account filters', () {
    final range = DateRange.forPeriod(Period.day, DateTime(2026, 11, 15));

    test('watchPeriodTransactions with no filter returns everything in range', () async {
      await addTransaction(accountId: 1, type: 'expense', amountMinorUnits: 1000, categoryId: 1);
      await addTransaction(accountId: 1, type: 'expense', amountMinorUnits: 2000, categoryId: 2);

      final items = await repo.watchPeriodTransactions(range).first;

      expect(items, hasLength(2));
    });

    test('watchPeriodTransactions filters by categoryIds', () async {
      await addTransaction(accountId: 1, type: 'expense', amountMinorUnits: 1000, categoryId: 1);
      await addTransaction(accountId: 1, type: 'expense', amountMinorUnits: 2000, categoryId: 2);

      final items = await repo.watchPeriodTransactions(range, categoryIds: {1}).first;

      expect(items, hasLength(1));
      expect(items.single.transaction.amountMinorUnits, 1000);
    });

    test('watchPeriodTransactions filters by accountIds', () async {
      final savings = await addAccount('Savings');
      await addTransaction(accountId: 1, type: 'expense', amountMinorUnits: 1000);
      await addTransaction(accountId: savings, type: 'expense', amountMinorUnits: 2000);

      final items = await repo.watchPeriodTransactions(range, accountIds: {savings}).first;

      expect(items, hasLength(1));
      expect(items.single.transaction.amountMinorUnits, 2000);
    });

    test('watchPeriodSummary respects both filters combined', () async {
      final savings = await addAccount('Savings');
      await addTransaction(accountId: 1, type: 'expense', amountMinorUnits: 1000, categoryId: 1);
      await addTransaction(accountId: savings, type: 'expense', amountMinorUnits: 2000, categoryId: 1);
      await addTransaction(accountId: 1, type: 'expense', amountMinorUnits: 4000, categoryId: 2);

      final summary = await repo.watchPeriodSummary(range, categoryIds: {1}, accountIds: {1}).first;

      expect(summary.expenseMinorUnits, 1000);
    });
  });

  group('description field', () {
    test('addTransaction persists a description distinct from note', () async {
      final id = await repo.addTransaction(
        accountId: 1,
        type: 'expense',
        amountMinorUnits: 1000,
        currency: 'USD',
        date: DateTime(2026, 11, 20),
        note: 'Groceries',
        description: 'Weekly shop at the market',
      );

      final row = await (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingle();
      expect(row.note, 'Groceries');
      expect(row.description, 'Weekly shop at the market');
    });

    test('updateTransaction can set and clear the description', () async {
      final id = await repo.addTransaction(
        accountId: 1,
        type: 'expense',
        amountMinorUnits: 1000,
        currency: 'USD',
        date: DateTime(2026, 11, 20),
        description: 'Original detail',
      );

      await repo.updateTransaction(id, description: null);

      final row = await (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingle();
      expect(row.description, isNull);
    });
  });
}
