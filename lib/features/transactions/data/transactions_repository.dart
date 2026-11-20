import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/utils/date_period.dart';

/// Totals for a period, in integer minor units (scaled 1000x — see
/// Transactions.amountMinorUnits).
class PeriodSummary {
  const PeriodSummary({required this.incomeMinorUnits, required this.expenseMinorUnits});

  final int incomeMinorUnits;
  final int expenseMinorUnits;

  int get netMinorUnits => incomeMinorUnits - expenseMinorUnits;

  static const zero = PeriodSummary(incomeMinorUnits: 0, expenseMinorUnits: 0);
}

/// A transaction row joined with its category, for list display.
class TransactionListItem {
  const TransactionListItem({required this.transaction, required this.category});

  final Transaction transaction;
  final Category? category;
}

class TransactionsRepository {
  TransactionsRepository(this._db);

  final AppDatabase _db;

  Future<int> addTransaction({
    required int accountId,
    int? categoryId,
    required String type,
    required int amountMinorUnits,
    required String currency,
    required DateTime date,
    String? note,
  }) {
    return _db.into(_db.transactions).insert(
          TransactionsCompanion.insert(
            accountId: accountId,
            categoryId: Value(categoryId),
            type: type,
            amountMinorUnits: amountMinorUnits,
            currency: currency,
            date: date,
            note: Value(note),
          ),
        );
  }

  Future<void> updateTransaction(
    int id, {
    int? accountId,
    int? categoryId,
    String? type,
    int? amountMinorUnits,
    DateTime? date,
    String? note,
    bool? isPendingReview,
  }) {
    return (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        accountId: accountId != null ? Value(accountId) : const Value.absent(),
        categoryId: Value(categoryId),
        type: type != null ? Value(type) : const Value.absent(),
        amountMinorUnits:
            amountMinorUnits != null ? Value(amountMinorUnits) : const Value.absent(),
        date: date != null ? Value(date) : const Value.absent(),
        note: Value(note),
        isPendingReview: isPendingReview != null ? Value(isPendingReview) : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteTransaction(int id) {
    return (_db.delete(_db.transactions)..where((t) => t.id.equals(id))).go();
  }

  Stream<PeriodSummary> watchPeriodSummary(
    DateRange range, {
    Set<int> categoryIds = const {},
    Set<int> accountIds = const {},
  }) {
    final query = _db.select(_db.transactions)
      ..where((t) =>
          t.date.isBiggerOrEqualValue(range.start) &
          t.date.isSmallerThanValue(range.end) &
          t.isPendingReview.equals(false) &
          t.type.isIn(const ['income', 'expense']) &
          (categoryIds.isEmpty ? const Constant(true) : t.categoryId.isIn(categoryIds)) &
          (accountIds.isEmpty ? const Constant(true) : t.accountId.isIn(accountIds)));

    return query.watch().map((rows) {
      var income = 0;
      var expense = 0;
      for (final row in rows) {
        if (row.type == 'income') {
          income += row.amountMinorUnits;
        } else if (row.type == 'expense') {
          expense += row.amountMinorUnits;
        }
      }
      return PeriodSummary(incomeMinorUnits: income, expenseMinorUnits: expense);
    });
  }

  Stream<List<TransactionListItem>> watchPeriodTransactions(
    DateRange range, {
    Set<int> categoryIds = const {},
    Set<int> accountIds = const {},
  }) {
    final query = _db.select(_db.transactions).join([
      leftOuterJoin(
        _db.categories,
        _db.categories.id.equalsExp(_db.transactions.categoryId),
      ),
    ])
      ..where(_db.transactions.date.isBiggerOrEqualValue(range.start) &
          _db.transactions.date.isSmallerThanValue(range.end) &
          _db.transactions.isPendingReview.equals(false) &
          // Transfers are excluded from the main list — they're excluded
          // from income/expense totals/reports (per
          // docs/features/categories-accounts.md "Transfers") and shown
          // instead in the Accounts screen's "Recent transfers" section.
          _db.transactions.type.isIn(const ['income', 'expense']) &
          (categoryIds.isEmpty ? const Constant(true) : _db.transactions.categoryId.isIn(categoryIds)) &
          (accountIds.isEmpty ? const Constant(true) : _db.transactions.accountId.isIn(accountIds)))
      ..orderBy([OrderingTerm.desc(_db.transactions.date)]);

    return query.watch().map((rows) {
      return rows
          .map((row) => TransactionListItem(
                transaction: row.readTable(_db.transactions),
                category: row.readTableOrNull(_db.categories),
              ))
          .toList();
    });
  }

  /// Sum of eligible accounts' starting balances plus their confirmed,
  /// non-transfer transactions (income adds, expense subtracts), plus the
  /// user's manual adjustment (AppSettings
  /// `allTimeBalanceAdjustmentMinorUnits`, set via
  /// SettingsRepository.setAllTimeBalanceAdjustment). Which accounts are
  /// "eligible" depends on AppSettings `includeArchivedInAllTimeBalance`
  /// (set via SettingsRepository.setIncludeArchivedInAllTimeBalance): false
  /// (default, fixed 2026-11-08) excludes archived accounts, matching
  /// AccountsRepository.watchActive()/watchActiveWithBalances(); true
  /// includes them too, for users who want the old behavior back — see
  /// docs/features/categories-accounts.md. Transfers are intentionally
  /// excluded here (rather than included like in
  /// AccountsRepository.watchActiveWithBalances): a transfer's outflow and
  /// inflow legs are equal-and-opposite signed amounts, so they cancel to
  /// zero across all accounts combined — excluding them is equivalent to
  /// including them, and cheaper.
  Stream<int> watchAllTimeBalanceMinorUnits() {
    final accountsQuery = _db.select(_db.accounts);
    final transactionsQuery = _db.select(_db.transactions)
      ..where((t) =>
          t.isPendingReview.equals(false) & t.type.isIn(const ['income', 'expense']));
    final settingsQuery = _db.select(_db.appSettingsTable);

    return Rx.combineLatest3<List<Account>, List<Transaction>, AppSettingsTableData, int>(
      accountsQuery.watch(),
      transactionsQuery.watch(),
      settingsQuery.watchSingle(),
      (accounts, txns, settings) {
        final eligibleAccounts = settings.includeArchivedInAllTimeBalance
            ? accounts
            : accounts.where((a) => !a.isArchived).toList();
        final eligibleAccountIds = eligibleAccounts.map((a) => a.id).toSet();
        final startingTotal =
            eligibleAccounts.fold<int>(0, (sum, a) => sum + a.startingBalanceMinorUnits);
        final txnTotal = txns.where((t) => eligibleAccountIds.contains(t.accountId)).fold<int>(
          0,
          (sum, t) => sum + (t.type == 'income' ? t.amountMinorUnits : -t.amountMinorUnits),
        );
        return startingTotal + txnTotal + settings.allTimeBalanceAdjustmentMinorUnits;
      },
    );
  }
}

final transactionsRepositoryProvider = Provider<TransactionsRepository>((ref) {
  return TransactionsRepository(ref.watch(databaseProvider));
});
