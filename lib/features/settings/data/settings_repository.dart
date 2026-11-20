import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';

/// Reads and writes the single-row [AppSettingsTable]. The app guarantees
/// exactly one row exists (seeded in onCreate, see [AppDatabase]), so all
/// reads/writes here act on "the" row without filtering by id.
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  /// Emits the current settings row, creating a default one first if the
  /// migration hasn't run yet (defensive — normally seeded in onCreate).
  Stream<AppSettingsTableData> watch() {
    final query = _db.select(_db.appSettingsTable);
    return query.watchSingleOrNull().asyncMap((row) async {
      if (row != null) return row;
      return _db.into(_db.appSettingsTable).insertReturning(
            const AppSettingsTableCompanion(),
          );
    });
  }

  Future<void> setDefaultCurrency(String currencyCode) {
    return _db
        .update(_db.appSettingsTable)
        .write(AppSettingsTableCompanion(defaultCurrency: Value(currencyCode)));
  }

  Future<void> setThemeMode(String themeMode) {
    return _db
        .update(_db.appSettingsTable)
        .write(AppSettingsTableCompanion(themeMode: Value(themeMode)));
  }

  Future<void> setAllTimeBalanceAdjustment(int minorUnits) {
    return _db.update(_db.appSettingsTable).write(
          AppSettingsTableCompanion(allTimeBalanceAdjustmentMinorUnits: Value(minorUnits)),
        );
  }

  Future<void> setIncludeArchivedInAllTimeBalance(bool include) {
    return _db.update(_db.appSettingsTable).write(
          AppSettingsTableCompanion(includeArchivedInAllTimeBalance: Value(include)),
        );
  }
}

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(databaseProvider));
});

final appSettingsStreamProvider = StreamProvider<AppSettingsTableData>((ref) {
  return ref.watch(settingsRepositoryProvider).watch();
});
