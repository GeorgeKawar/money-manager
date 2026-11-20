import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/database/database.dart';
import 'package:money_manager/core/utils/date_period.dart';
import 'package:money_manager/features/reports/data/reports_repository.dart';

void main() {
  late AppDatabase db;
  late ReportsRepository repo;

  // AppDatabase.forTesting seeds one account ('Cash', id 1) and the default
  // category set on open — see AppDatabase._seedDefaultCategories.
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ReportsRepository(db);
  });

  tearDown(() => db.close());

  final range = DateRange.forPeriod(Period.month, DateTime(2026, 11, 15));

  Future<int> addCategory(String name, String type) {
    return db.into(db.categories).insert(CategoriesCompanion.insert(name: name, type: type));
  }

  Future<int> addAccount(String name) {
    return db.into(db.accounts).insert(AccountsCompanion.insert(name: name));
  }

  Future<void> addTransaction({
    required int accountId,
    int? categoryId,
    required String type,
    required int amountMinorUnits,
    DateTime? date,
    bool isPendingReview = false,
  }) {
    return db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            accountId: accountId,
            categoryId: Value(categoryId),
            type: type,
            amountMinorUnits: amountMinorUnits,
            currency: 'USD',
            date: date ?? DateTime(2026, 11, 15),
            isPendingReview: Value(isPendingReview),
          ),
        );
  }

  group('watchPeriodCategoryBreakdown', () {
    test('sums by category, scoped to the given type, sorted descending', () async {
      final food = await addCategory('Food', 'expense');
      final transport = await addCategory('Transport', 'expense');
      await addTransaction(accountId: 1, categoryId: food, type: 'expense', amountMinorUnits: 5000);
      await addTransaction(accountId: 1, categoryId: food, type: 'expense', amountMinorUnits: 3000);
      await addTransaction(accountId: 1, categoryId: transport, type: 'expense', amountMinorUnits: 9000);

      final items = await repo.watchPeriodCategoryBreakdown(range, type: 'expense').first;

      expect(items, hasLength(2));
      expect(items[0].category?.name, 'Transport');
      expect(items[0].amountMinorUnits, 9000);
      expect(items[1].category?.name, 'Food');
      expect(items[1].amountMinorUnits, 8000);
    });

    test('groups transactions with no category as a single "null category" item', () async {
      await addTransaction(accountId: 1, categoryId: null, type: 'expense', amountMinorUnits: 1000);
      await addTransaction(accountId: 1, categoryId: null, type: 'expense', amountMinorUnits: 500);

      final items = await repo.watchPeriodCategoryBreakdown(range, type: 'expense').first;

      expect(items, hasLength(1));
      expect(items.single.category, isNull);
      expect(items.single.amountMinorUnits, 1500);
    });

    test('excludes pending-review transactions and the other transaction type', () async {
      final food = await addCategory('Food', 'expense');
      final salary = await addCategory('Salary', 'income');
      await addTransaction(accountId: 1, categoryId: food, type: 'expense', amountMinorUnits: 1000, isPendingReview: true);
      await addTransaction(accountId: 1, categoryId: salary, type: 'income', amountMinorUnits: 50000);

      final items = await repo.watchPeriodCategoryBreakdown(range, type: 'expense').first;

      expect(items, isEmpty);
    });

    test('excludes transactions outside the requested range', () async {
      final food = await addCategory('Food', 'expense');
      await addTransaction(accountId: 1, categoryId: food, type: 'expense', amountMinorUnits: 1000, date: DateTime(2026, 10, 31));

      final items = await repo.watchPeriodCategoryBreakdown(range, type: 'expense').first;

      expect(items, isEmpty);
    });
  });

  group('watchPeriodAccountBreakdown', () {
    test('nets income minus expense per account, excluding transfers', () async {
      final savings = await addAccount('Savings');
      await addTransaction(accountId: 1, type: 'income', amountMinorUnits: 10000);
      await addTransaction(accountId: 1, type: 'expense', amountMinorUnits: 4000);
      await addTransaction(accountId: savings, type: 'income', amountMinorUnits: 2000);
      await addTransaction(accountId: 1, type: 'transfer', amountMinorUnits: 99999999);

      final items = await repo.watchPeriodAccountBreakdown(range).first;

      final cash = items.firstWhere((item) => item.account.name == 'Cash');
      final savingsItem = items.firstWhere((item) => item.account.name == 'Savings');
      expect(cash.netMinorUnits, 6000);
      expect(savingsItem.netMinorUnits, 2000);
    });

    test('omits accounts with no net activity and sorts by largest magnitude first', () async {
      await addAccount('Savings');
      await addTransaction(accountId: 1, type: 'expense', amountMinorUnits: 500);
      // Savings has no transactions at all in range -> net 0 -> omitted.

      final items = await repo.watchPeriodAccountBreakdown(range).first;

      expect(items.map((item) => item.account.name), ['Cash']);
      expect(items.any((item) => item.account.name == 'Savings'), isFalse);
    });
  });
}
