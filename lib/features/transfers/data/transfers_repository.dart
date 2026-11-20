import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';

/// A completed transfer, both legs resolved to their account names for
/// display (see docs/features/categories-accounts.md "Transfers").
class TransferListItem {
  const TransferListItem({
    required this.id,
    required this.fromAccountName,
    required this.toAccountName,
    required this.amountMinorUnits,
    required this.currency,
    required this.date,
  });

  /// Id of the outflow leg — used to delete the pair.
  final int id;
  final String fromAccountName;
  final String toAccountName;
  /// Always positive (magnitude) — the amount moved.
  final int amountMinorUnits;
  final String currency;
  final DateTime date;
}

class TransfersRepository {
  TransfersRepository(this._db);

  final AppDatabase _db;

  /// Moves money between two of the user's own accounts: two linked
  /// `Transaction` rows (`type = 'transfer'`), inserted atomically. The
  /// outflow leg's amount is stored negative, the inflow leg's positive —
  /// both signs flow straight into the existing balance sums (see
  /// AccountsRepository.watchActiveWithBalances) without special-casing.
  Future<void> addTransfer({
    required int fromAccountId,
    required int toAccountId,
    required int amountMinorUnits,
    required String currency,
    required DateTime date,
    String? note,
  }) async {
    await _db.transaction(() async {
      final fromAccount =
          await (_db.select(_db.accounts)..where((a) => a.id.equals(fromAccountId))).getSingle();
      final toAccount =
          await (_db.select(_db.accounts)..where((a) => a.id.equals(toAccountId))).getSingle();

      final outId = await _db.into(_db.transactions).insert(
            TransactionsCompanion.insert(
              accountId: fromAccountId,
              type: 'transfer',
              amountMinorUnits: -amountMinorUnits,
              currency: currency,
              date: date,
              note: Value(note ?? 'Transfer to ${toAccount.name}'),
            ),
          );
      final inId = await _db.into(_db.transactions).insert(
            TransactionsCompanion.insert(
              accountId: toAccountId,
              type: 'transfer',
              amountMinorUnits: amountMinorUnits,
              currency: currency,
              date: date,
              note: Value(note ?? 'Transfer from ${fromAccount.name}'),
              transferPairId: Value(outId),
            ),
          );
      await (_db.update(_db.transactions)..where((t) => t.id.equals(outId)))
          .write(TransactionsCompanion(transferPairId: Value(inId)));
    });
  }

  /// Recent transfers, most recent first. Reads all transfer-type rows plus
  /// accounts and pairs legs up in Dart — simpler and more robust than a
  /// self-join in Drift, and fine at personal-finance data volumes.
  Stream<List<TransferListItem>> watchRecent({int limit = 20}) {
    final transferQuery = _db.select(_db.transactions)..where((t) => t.type.equals('transfer'));
    final accountsQuery = _db.select(_db.accounts);

    return Rx.combineLatest2<List<Transaction>, List<Account>, List<TransferListItem>>(
      transferQuery.watch(),
      accountsQuery.watch(),
      (txns, accounts) {
        final nameById = {for (final a in accounts) a.id: a.name};
        final byId = {for (final t in txns) t.id: t};
        final seenIds = <int>{};
        final items = <TransferListItem>[];
        for (final t in txns) {
          if (t.transferPairId == null || seenIds.contains(t.id)) continue;
          final paired = byId[t.transferPairId];
          if (paired == null) continue;
          seenIds.add(t.id);
          seenIds.add(paired.id);
          final outLeg = t.amountMinorUnits < 0 ? t : paired;
          final inLeg = t.amountMinorUnits < 0 ? paired : t;
          items.add(TransferListItem(
            id: outLeg.id,
            fromAccountName: nameById[outLeg.accountId] ?? '—',
            toAccountName: nameById[inLeg.accountId] ?? '—',
            amountMinorUnits: inLeg.amountMinorUnits,
            currency: outLeg.currency,
            date: outLeg.date,
          ));
        }
        items.sort((a, b) => b.date.compareTo(a.date));
        return items.take(limit).toList();
      },
    );
  }

  /// Deletes both legs of a transfer, given either leg's id.
  Future<void> deleteTransfer(int id) async {
    await _db.transaction(() async {
      final row = await (_db.select(_db.transactions)..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return;
      await (_db.delete(_db.transactions)..where((t) => t.id.equals(id))).go();
      final pairId = row.transferPairId;
      if (pairId != null) {
        await (_db.delete(_db.transactions)..where((t) => t.id.equals(pairId))).go();
      }
    });
  }
}

final transfersRepositoryProvider = Provider<TransfersRepository>((ref) {
  return TransfersRepository(ref.watch(databaseProvider));
});

final recentTransfersProvider = StreamProvider<List<TransferListItem>>((ref) {
  return ref.watch(transfersRepositoryProvider).watchRecent();
});
