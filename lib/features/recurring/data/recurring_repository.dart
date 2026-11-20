import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';

/// A recurring definition joined with its account/category names, for
/// display on the Recurring list screen.
class RecurringListItem {
  const RecurringListItem({
    required this.definition,
    required this.accountName,
    required this.categoryName,
  });

  final RecurringTransaction definition;
  final String accountName;
  final String? categoryName;
}

class RecurringRepository {
  RecurringRepository(this._db);

  final AppDatabase _db;

  Stream<List<RecurringListItem>> watchAll() {
    final query = _db.select(_db.recurringTransactions).join([
      innerJoin(_db.accounts, _db.accounts.id.equalsExp(_db.recurringTransactions.accountId)),
      leftOuterJoin(_db.categories, _db.categories.id.equalsExp(_db.recurringTransactions.categoryId)),
    ])
      ..orderBy([OrderingTerm.asc(_db.recurringTransactions.nextRunDate)]);

    return query.watch().map((rows) {
      return rows
          .map((row) => RecurringListItem(
                definition: row.readTable(_db.recurringTransactions),
                accountName: row.readTable(_db.accounts).name,
                categoryName: row.readTableOrNull(_db.categories)?.name,
              ))
          .toList();
    });
  }

  Future<int> addRecurring({
    required int accountId,
    int? categoryId,
    required String type,
    required int amountMinorUnits,
    String? note,
    required String frequency,
    required DateTime startDate,
    DateTime? endDate,
  }) {
    return _db.into(_db.recurringTransactions).insert(
          RecurringTransactionsCompanion.insert(
            accountId: accountId,
            categoryId: Value(categoryId),
            type: type,
            amountMinorUnits: amountMinorUnits,
            note: Value(note),
            frequency: frequency,
            startDate: startDate,
            endDate: Value(endDate),
            nextRunDate: startDate,
          ),
        );
  }

  /// `startDate`/`nextRunDate` are intentionally not editable here — see
  /// the sheet's read-only Start date field once a definition exists.
  Future<void> updateRecurring(
    int id, {
    required int accountId,
    int? categoryId,
    required String type,
    required int amountMinorUnits,
    String? note,
    required String frequency,
    DateTime? endDate,
  }) {
    return (_db.update(_db.recurringTransactions)..where((r) => r.id.equals(id))).write(
      RecurringTransactionsCompanion(
        accountId: Value(accountId),
        categoryId: Value(categoryId),
        type: Value(type),
        amountMinorUnits: Value(amountMinorUnits),
        note: Value(note),
        frequency: Value(frequency),
        endDate: Value(endDate),
      ),
    );
  }

  Future<void> setActive(int id, bool isActive) {
    return (_db.update(_db.recurringTransactions)..where((r) => r.id.equals(id)))
        .write(RecurringTransactionsCompanion(isActive: Value(isActive)));
  }

  Future<void> deleteRecurring(int id) {
    return (_db.delete(_db.recurringTransactions)..where((r) => r.id.equals(id))).go();
  }

  /// Generation on app launch (see
  /// docs/features/recurring-transactions.md "Generation behavior"): for
  /// every active definition whose `next_run_date` is due, generate
  /// `Transaction` rows and advance `next_run_date` by the frequency
  /// interval, repeating until it's past today — this catches up on
  /// definitions missed while the app was closed instead of skipping them.
  /// No exact-time background scheduling in v1; this only runs when the
  /// app is opened.
  Future<void> generateDueTransactions() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final due = await (_db.select(_db.recurringTransactions)
          ..where((r) => r.isActive.equals(true) & r.nextRunDate.isSmallerOrEqualValue(today)))
        .get();
    if (due.isEmpty) return;

    final settings = await _db.select(_db.appSettingsTable).getSingleOrNull();
    final currency = settings?.defaultCurrency ?? 'USD';

    await _db.transaction(() async {
      for (final def in due) {
        var nextRun = def.nextRunDate;
        while (!nextRun.isAfter(today) && (def.endDate == null || !nextRun.isAfter(def.endDate!))) {
          await _db.into(_db.transactions).insert(
                TransactionsCompanion.insert(
                  accountId: def.accountId,
                  categoryId: Value(def.categoryId),
                  type: def.type,
                  amountMinorUnits: def.amountMinorUnits,
                  currency: currency,
                  date: nextRun,
                  note: Value(def.note),
                  source: const Value('recurring'),
                  recurringId: Value(def.id),
                ),
              );
          nextRun = _advance(nextRun, def.frequency);
        }
        final stillWithinRange = def.endDate == null || !nextRun.isAfter(def.endDate!);
        await (_db.update(_db.recurringTransactions)..where((r) => r.id.equals(def.id))).write(
          RecurringTransactionsCompanion(
            nextRunDate: Value(nextRun),
            isActive: Value(stillWithinRange),
          ),
        );
      }
    });
  }

  DateTime _advance(DateTime date, String frequency) {
    switch (frequency) {
      case 'daily':
        return date.add(const Duration(days: 1));
      case 'weekly':
        return date.add(const Duration(days: 7));
      case 'monthly':
        return DateTime(date.year, date.month + 1, date.day);
      case 'yearly':
        return DateTime(date.year + 1, date.month, date.day);
      default:
        return date.add(const Duration(days: 1));
    }
  }
}

final recurringRepositoryProvider = Provider<RecurringRepository>((ref) {
  return RecurringRepository(ref.watch(databaseProvider));
});

final recurringListProvider = StreamProvider<List<RecurringListItem>>((ref) {
  return ref.watch(recurringRepositoryProvider).watchAll();
});
