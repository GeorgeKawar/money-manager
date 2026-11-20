import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/database/database.dart';
import 'package:money_manager/features/categories/data/categories_repository.dart';

void main() {
  late AppDatabase db;
  late CategoriesRepository repo;

  // AppDatabase.forTesting seeds one account ('Cash', id 1) and the default
  // category set on open — see AppDatabase._seedDefaultCategories.
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = CategoriesRepository(db);
  });

  tearDown(() => db.close());

  group('updateCategory', () {
    test('persists the chosen icon and color', () async {
      final id = await repo.addCategory(name: 'Hobbies', type: 'expense');

      await repo.updateCategory(id, name: 'Hobbies', icon: 'movie', color: 0xFF112233);

      final row = await (db.select(db.categories)..where((c) => c.id.equals(id))).getSingle();
      expect(row.icon, 'movie');
      expect(row.color, 0xFF112233);
    });
  });

  group('isUnused', () {
    test('is true for a category with no references', () async {
      final id = await repo.addCategory(name: 'Hobbies', type: 'expense');

      expect(await repo.isUnused(id), isTrue);
    });

    test('is false when a transaction references the category', () async {
      final id = await repo.addCategory(name: 'Hobbies', type: 'expense');
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              accountId: 1,
              categoryId: Value(id),
              type: 'expense',
              amountMinorUnits: 1000,
              currency: 'USD',
              date: DateTime(2026, 11, 15),
            ),
          );

      expect(await repo.isUnused(id), isFalse);
    });

    test('is false when a recurring transaction references the category', () async {
      final id = await repo.addCategory(name: 'Hobbies', type: 'expense');
      await db.into(db.recurringTransactions).insert(
            RecurringTransactionsCompanion.insert(
              accountId: 1,
              categoryId: Value(id),
              type: 'expense',
              amountMinorUnits: 1000,
              frequency: 'monthly',
              startDate: DateTime(2026, 11, 15),
              nextRunDate: DateTime(2026, 12, 15),
            ),
          );

      expect(await repo.isUnused(id), isFalse);
    });

    test('is false when a notification rule defaults to the category', () async {
      final id = await repo.addCategory(name: 'Hobbies', type: 'expense');
      await db.into(db.notificationRules).insert(
            NotificationRulesCompanion.insert(
              name: 'Rule',
              appPackage: 'com.bank.app',
              regexPattern: r'debited ([\d.]+)',
              transactionType: 'expense',
              defaultAccountId: 1,
              defaultCategoryId: Value(id),
            ),
          );

      expect(await repo.isUnused(id), isFalse);
    });
  });

  group('deleteCategory', () {
    test('removes the category row', () async {
      final id = await repo.addCategory(name: 'Hobbies', type: 'expense');

      await repo.deleteCategory(id);

      final remaining = await (db.select(db.categories)..where((c) => c.id.equals(id))).getSingleOrNull();
      expect(remaining, isNull);
    });
  });
}
