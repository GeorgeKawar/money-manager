import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';

class CategoriesRepository {
  CategoriesRepository(this._db);

  final AppDatabase _db;

  /// Ordered by id (seed/creation order), not name — so the category
  /// chips in the add/edit sheet match the fixed order from the design
  /// mockups (Food, Home, Transport, ... ) instead of shuffling
  /// alphabetically.
  Stream<List<Category>> watchActive() {
    final query = _db.select(_db.categories)
      ..where((c) => c.isArchived.equals(false))
      ..orderBy([(c) => OrderingTerm.asc(c.id)]);
    return query.watch();
  }

  Future<int> addCategory({required String name, required String type, String? icon, int? color}) {
    return _db.into(_db.categories).insert(
          CategoriesCompanion.insert(name: name, type: type, icon: Value(icon), color: Value(color)),
        );
  }

  Future<void> updateCategory(int id, {required String name, String? icon, int? color}) {
    return (_db.update(_db.categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(name: Value(name), icon: Value(icon), color: Value(color)),
    );
  }

  Future<void> archiveCategory(int id) {
    return (_db.update(_db.categories)..where((c) => c.id.equals(id)))
        .write(const CategoriesCompanion(isArchived: Value(true)));
  }

  /// Whether [id] is safe to permanently delete: nothing references it, so
  /// there's no history to lose and no foreign key to break. Checked before
  /// offering delete in the UI (see add_edit_category_sheet.dart) — mirrors
  /// AccountsRepository.isUnused.
  Future<bool> isUnused(int id) async {
    final transaction = await (_db.select(_db.transactions)
          ..where((t) => t.categoryId.equals(id))
          ..limit(1))
        .getSingleOrNull();
    if (transaction != null) return false;

    final recurring = await (_db.select(_db.recurringTransactions)
          ..where((r) => r.categoryId.equals(id))
          ..limit(1))
        .getSingleOrNull();
    if (recurring != null) return false;

    final rule = await (_db.select(_db.notificationRules)
          ..where((r) => r.defaultCategoryId.equals(id))
          ..limit(1))
        .getSingleOrNull();
    return rule == null;
  }

  /// Permanently removes a category. Only call this after confirming
  /// [isUnused] — deleting one still referenced by a transaction,
  /// recurring definition, or rule would violate their foreign keys (or, if
  /// unenforced, silently orphan them).
  Future<void> deleteCategory(int id) {
    return (_db.delete(_db.categories)..where((c) => c.id.equals(id))).go();
  }
}

final categoriesRepositoryProvider = Provider<CategoriesRepository>((ref) {
  return CategoriesRepository(ref.watch(databaseProvider));
});

final activeCategoriesProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(categoriesRepositoryProvider).watchActive();
});

/// Re-checked each time it's watched (autoDispose, no caching across sheet
/// opens) since usage can change between one open of the edit sheet and the
/// next.
final categoryIsUnusedProvider = FutureProvider.autoDispose.family<bool, int>((ref, id) {
  return ref.watch(categoriesRepositoryProvider).isUnused(id);
});
