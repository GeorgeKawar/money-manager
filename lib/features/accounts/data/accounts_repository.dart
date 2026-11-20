import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';

/// An account paired with its derived current balance (starting balance +
/// signed sum of its own non-transfer transactions).
class AccountBalance {
  const AccountBalance({required this.account, required this.balanceMinorUnits});

  final Account account;
  final int balanceMinorUnits;
}

class AccountsRepository {
  AccountsRepository(this._db);

  final AppDatabase _db;

  Stream<List<Account>> watchActive() {
    final query = _db.select(_db.accounts)
      ..where((a) => a.isArchived.equals(false))
      ..orderBy([(a) => OrderingTerm.asc(a.id)]);
    return query.watch();
  }

  Stream<List<AccountBalance>> watchActiveWithBalances() {
    final accountsQuery = _db.select(_db.accounts)
      ..where((a) => a.isArchived.equals(false))
      ..orderBy([(a) => OrderingTerm.asc(a.id)]);
    return _withBalances(accountsQuery.watch());
  }

  /// Mirrors [watchActiveWithBalances] but for archived accounts — lets the
  /// Accounts screen show them (per user request, 2026-11-09) rather than
  /// hiding them with no way back short of editing the database directly.
  Stream<List<AccountBalance>> watchArchivedWithBalances() {
    final accountsQuery = _db.select(_db.accounts)
      ..where((a) => a.isArchived.equals(true))
      ..orderBy([(a) => OrderingTerm.asc(a.id)]);
    return _withBalances(accountsQuery.watch());
  }

  Stream<List<AccountBalance>> _withBalances(Stream<List<Account>> accounts) {
    // Transfer legs are included here (unlike the income/expense-only
    // queries elsewhere): each account's balance must reflect money moved
    // in/out by a transfer. Their amountMinorUnits is pre-signed at
    // creation (negative = outflow, positive = inflow — see
    // TransfersRepository.addTransfer), so they fold in directly below.
    final transactionsQuery = _db.select(_db.transactions)
      ..where((t) =>
          t.isPendingReview.equals(false) & t.type.isIn(const ['income', 'expense', 'transfer']));

    return Rx.combineLatest2<List<Account>, List<Transaction>, List<AccountBalance>>(
      accounts,
      transactionsQuery.watch(),
      (accountList, txns) {
        return accountList.map((account) {
          final txnTotal = txns.where((t) => t.accountId == account.id).fold<int>(0, (sum, t) {
            return switch (t.type) {
              'income' => sum + t.amountMinorUnits,
              'expense' => sum - t.amountMinorUnits,
              _ => sum + t.amountMinorUnits, // transfer — already signed
            };
          });
          return AccountBalance(
            account: account,
            balanceMinorUnits: account.startingBalanceMinorUnits + txnTotal,
          );
        }).toList();
      },
    );
  }

  Future<int> addAccount({
    required String name,
    required int startingBalanceMinorUnits,
    bool includeInAllTimeBalance = true,
  }) {
    return _db.into(_db.accounts).insert(
          AccountsCompanion.insert(
            name: name,
            startingBalanceMinorUnits: Value(startingBalanceMinorUnits),
            includeInAllTimeBalance: Value(includeInAllTimeBalance),
          ),
        );
  }

  Future<void> updateAccount(
    int id, {
    required String name,
    required int startingBalanceMinorUnits,
    required bool includeInAllTimeBalance,
  }) {
    return (_db.update(_db.accounts)..where((a) => a.id.equals(id))).write(
      AccountsCompanion(
        name: Value(name),
        startingBalanceMinorUnits: Value(startingBalanceMinorUnits),
        includeInAllTimeBalance: Value(includeInAllTimeBalance),
      ),
    );
  }

  Future<void> archiveAccount(int id) {
    // Also clears isDefault — an archived account shouldn't silently keep
    // receiving new transactions via the default-account pre-fill.
    return (_db.update(_db.accounts)..where((a) => a.id.equals(id)))
        .write(const AccountsCompanion(isArchived: Value(true), isDefault: Value(false)));
  }

  /// Marks [id] as the sole default account (clearing the flag on every
  /// other account first, so at most one is ever default) — pre-fills the
  /// account field on new manual transactions and new notification rules.
  /// See docs/features/categories-accounts.md.
  Future<void> setDefault(int id) async {
    await _db.transaction(() async {
      await (_db.update(_db.accounts)..where((a) => a.isDefault.equals(true)))
          .write(const AccountsCompanion(isDefault: Value(false)));
      await (_db.update(_db.accounts)..where((a) => a.id.equals(id)))
          .write(const AccountsCompanion(isDefault: Value(true)));
    });
  }

  /// Clears the default-account flag without setting a new one.
  Future<void> clearDefault(int id) {
    return (_db.update(_db.accounts)..where((a) => a.id.equals(id)))
        .write(const AccountsCompanion(isDefault: Value(false)));
  }

  Future<void> unarchiveAccount(int id) {
    return (_db.update(_db.accounts)..where((a) => a.id.equals(id)))
        .write(const AccountsCompanion(isArchived: Value(false)));
  }

  /// Whether [id] is safe to permanently delete: nothing references it, so
  /// there's no history to lose and no foreign key to break. Checked before
  /// offering delete in the UI (see add_edit_account_sheet.dart) — otherwise
  /// archiving is the only way to remove an account from use.
  Future<bool> isUnused(int id) async {
    final transaction = await (_db.select(_db.transactions)
          ..where((t) => t.accountId.equals(id))
          ..limit(1))
        .getSingleOrNull();
    if (transaction != null) return false;

    final recurring = await (_db.select(_db.recurringTransactions)
          ..where((r) => r.accountId.equals(id))
          ..limit(1))
        .getSingleOrNull();
    if (recurring != null) return false;

    final rule = await (_db.select(_db.notificationRules)
          ..where((r) => r.defaultAccountId.equals(id))
          ..limit(1))
        .getSingleOrNull();
    return rule == null;
  }

  /// Permanently removes an account. Only call this after confirming
  /// [isUnused] — deleting an account that still has transactions or
  /// recurring/rule references pointing at it would violate their foreign
  /// keys (or, if unenforced, silently orphan them).
  Future<void> deleteAccount(int id) {
    return (_db.delete(_db.accounts)..where((a) => a.id.equals(id))).go();
  }
}

final accountsRepositoryProvider = Provider<AccountsRepository>((ref) {
  return AccountsRepository(ref.watch(databaseProvider));
});

final activeAccountsProvider = StreamProvider<List<Account>>((ref) {
  return ref.watch(accountsRepositoryProvider).watchActive();
});

/// The current default account (at most one), or null if none is set — see
/// AccountsRepository.setDefault.
final defaultAccountProvider = Provider<Account?>((ref) {
  final accounts = ref.watch(activeAccountsProvider).value;
  if (accounts == null) return null;
  for (final account in accounts) {
    if (account.isDefault) return account;
  }
  return null;
});

final activeAccountsWithBalancesProvider = StreamProvider<List<AccountBalance>>((ref) {
  return ref.watch(accountsRepositoryProvider).watchActiveWithBalances();
});

final archivedAccountsWithBalancesProvider = StreamProvider<List<AccountBalance>>((ref) {
  return ref.watch(accountsRepositoryProvider).watchArchivedWithBalances();
});

/// Re-checked each time it's watched (autoDispose, no caching across sheet
/// opens) since usage can change between one open of the edit sheet and the
/// next.
final accountIsUnusedProvider = FutureProvider.autoDispose.family<bool, int>((ref, id) {
  return ref.watch(accountsRepositoryProvider).isUnused(id);
});
