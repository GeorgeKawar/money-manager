import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/utils/date_period.dart';

/// One category's total for a period, scoped to a single transaction type
/// (income or expense — never mixed, since the two aren't comparable as a
/// single breakdown). A null [category] means "uncategorized" transactions
/// of that type, grouped together as one item.
class CategoryBreakdownItem {
  const CategoryBreakdownItem({required this.category, required this.amountMinorUnits});

  final Category? category;
  final int amountMinorUnits;
}

/// One account's net income-minus-expense for a period. Transfers are
/// excluded — same convention as TransactionsRepository.watchPeriodSummary,
/// since a transfer only moves money between accounts shown elsewhere
/// (see docs/features/categories-accounts.md "Transfers"), it doesn't
/// contribute to how much an account "earned" or "spent" in the period.
class AccountBreakdownItem {
  const AccountBreakdownItem({required this.account, required this.netMinorUnits});

  final Account account;
  final int netMinorUnits;
}

class ReportsRepository {
  ReportsRepository(this._db);

  final AppDatabase _db;

  /// Totals confirmed, non-transfer transactions of [type] ('income' or
  /// 'expense') within [range], grouped by category and sorted descending
  /// by total.
  Stream<List<CategoryBreakdownItem>> watchPeriodCategoryBreakdown(
    DateRange range, {
    required String type,
    Set<int> categoryIds = const {},
    Set<int> accountIds = const {},
  }) {
    final query = _db.select(_db.transactions).join([
      leftOuterJoin(_db.categories, _db.categories.id.equalsExp(_db.transactions.categoryId)),
    ])
      ..where(_db.transactions.date.isBiggerOrEqualValue(range.start) &
          _db.transactions.date.isSmallerThanValue(range.end) &
          _db.transactions.isPendingReview.equals(false) &
          _db.transactions.type.equals(type) &
          (categoryIds.isEmpty ? const Constant(true) : _db.transactions.categoryId.isIn(categoryIds)) &
          (accountIds.isEmpty ? const Constant(true) : _db.transactions.accountId.isIn(accountIds)));

    return query.watch().map((rows) {
      final totals = <int?, int>{};
      final categories = <int?, Category?>{};
      for (final row in rows) {
        final txn = row.readTable(_db.transactions);
        totals.update(txn.categoryId, (sum) => sum + txn.amountMinorUnits,
            ifAbsent: () => txn.amountMinorUnits);
        categories[txn.categoryId] = row.readTableOrNull(_db.categories);
      }
      final items = totals.entries
          .map((entry) => CategoryBreakdownItem(
                category: categories[entry.key],
                amountMinorUnits: entry.value,
              ))
          .toList()
        ..sort((a, b) => b.amountMinorUnits.compareTo(a.amountMinorUnits));
      return items;
    });
  }

  /// Net income-minus-expense per active account within [range], sorted by
  /// largest magnitude first. Accounts with no activity in the period are
  /// omitted.
  Stream<List<AccountBreakdownItem>> watchPeriodAccountBreakdown(
    DateRange range, {
    Set<int> categoryIds = const {},
    Set<int> accountIds = const {},
  }) {
    final accountsQuery = _db.select(_db.accounts)
      ..where((a) => a.isArchived.equals(false) & (accountIds.isEmpty ? const Constant(true) : a.id.isIn(accountIds)));
    final transactionsQuery = _db.select(_db.transactions)
      ..where((t) =>
          t.date.isBiggerOrEqualValue(range.start) &
          t.date.isSmallerThanValue(range.end) &
          t.isPendingReview.equals(false) &
          t.type.isIn(const ['income', 'expense']) &
          (categoryIds.isEmpty ? const Constant(true) : t.categoryId.isIn(categoryIds)));

    return Rx.combineLatest2<List<Account>, List<Transaction>, List<AccountBreakdownItem>>(
      accountsQuery.watch(),
      transactionsQuery.watch(),
      (accounts, txns) {
        final items = <AccountBreakdownItem>[];
        for (final account in accounts) {
          final net = txns.where((t) => t.accountId == account.id).fold<int>(0, (sum, t) {
            return sum + (t.type == 'income' ? t.amountMinorUnits : -t.amountMinorUnits);
          });
          if (net != 0) items.add(AccountBreakdownItem(account: account, netMinorUnits: net));
        }
        items.sort((a, b) => b.netMinorUnits.abs().compareTo(a.netMinorUnits.abs()));
        return items;
      },
    );
  }
}

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  return ReportsRepository(ref.watch(databaseProvider));
});
