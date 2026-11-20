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

  Future<int> addCategory({required String name, required String type}) {
    return _db.into(_db.categories).insert(
          CategoriesCompanion.insert(name: name, type: type),
        );
  }

  Future<void> updateCategory(int id, {required String name}) {
    return (_db.update(_db.categories)..where((c) => c.id.equals(id)))
        .write(CategoriesCompanion(name: Value(name)));
  }

  Future<void> archiveCategory(int id) {
    return (_db.update(_db.categories)..where((c) => c.id.equals(id)))
        .write(const CategoriesCompanion(isArchived: Value(true)));
  }
}

final categoriesRepositoryProvider = Provider<CategoriesRepository>((ref) {
  return CategoriesRepository(ref.watch(databaseProvider));
});

final activeCategoriesProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(categoriesRepositoryProvider).watchActive();
});
