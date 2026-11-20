import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';

/// A pending-review transaction joined with its account/category names,
/// for display on the Review queue screen — see
/// docs/features/notification-capture.md "Review queue (per-rule, not
/// global)".
class ReviewQueueItem {
  const ReviewQueueItem({required this.transaction, required this.accountName, required this.categoryName});

  final Transaction transaction;
  final String accountName;
  final String? categoryName;

  /// True when this item was forced into the review queue because it
  /// looked like a redelivered duplicate of an existing transaction, not
  /// because its rule is review-only — see
  /// NotificationCaptureService._insert "Duplicate detection".
  bool get isDuplicate => transaction.duplicateOfTransactionId != null;
}

class ReviewQueueRepository {
  ReviewQueueRepository(this._db);

  final AppDatabase _db;

  Stream<List<ReviewQueueItem>> watchPending() {
    final query = _db.select(_db.transactions).join([
      innerJoin(_db.accounts, _db.accounts.id.equalsExp(_db.transactions.accountId)),
      leftOuterJoin(_db.categories, _db.categories.id.equalsExp(_db.transactions.categoryId)),
    ])
      ..where(_db.transactions.isPendingReview.equals(true))
      ..orderBy([OrderingTerm.desc(_db.transactions.date)]);

    return query.watch().map((rows) {
      return rows
          .map((row) => ReviewQueueItem(
                transaction: row.readTable(_db.transactions),
                accountName: row.readTable(_db.accounts).name,
                categoryName: row.readTableOrNull(_db.categories)?.name,
              ))
          .toList();
    });
  }

  /// Confirms as-is — just clears the pending flag. Editing-then-confirming
  /// goes through TransactionsRepository.updateTransaction directly (see
  /// add_edit_transaction_sheet.dart's `confirmOnSave`).
  Future<void> confirm(int id) {
    return (_db.update(_db.transactions)..where((t) => t.id.equals(id)))
        .write(TransactionsCompanion(isPendingReview: const Value(false), updatedAt: Value(DateTime.now())));
  }

  Future<void> discard(int id) {
    return (_db.delete(_db.transactions)..where((t) => t.id.equals(id))).go();
  }
}

final reviewQueueRepositoryProvider = Provider<ReviewQueueRepository>((ref) {
  return ReviewQueueRepository(ref.watch(databaseProvider));
});

final reviewQueueProvider = StreamProvider<List<ReviewQueueItem>>((ref) {
  return ref.watch(reviewQueueRepositoryProvider).watchPending();
});
