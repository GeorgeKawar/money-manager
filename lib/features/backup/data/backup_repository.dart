import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';

/// Thrown by [BackupRepository.parseImport] when a picked file isn't a
/// MoneyManager export this app version understands — never lets a bad
/// file crash the import flow, always a message the Settings UI can show
/// directly.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A parsed, not-yet-applied export — lets the Settings UI show a summary
/// (record counts, export date) before [BackupRepository.applyImport]
/// commits the destructive replace.
class ImportPreview {
  const ImportPreview({
    required this.exportedAt,
    required this.appSettings,
    required this.accounts,
    required this.categories,
    required this.notificationRules,
    required this.recurringTransactions,
    required this.transactions,
  });

  final DateTime exportedAt;
  final AppSettingsTableData appSettings;
  final List<Account> accounts;
  final List<Category> categories;
  final List<NotificationRule> notificationRules;
  final List<RecurringTransaction> recurringTransactions;
  final List<Transaction> transactions;
}

/// Local, account-free export/import of the entire database to/from a JSON
/// document — see docs/features/data-import-export.md. Where the file ends
/// up (Downloads, SD card, a cloud-sync folder, email) is entirely the
/// user's choice via Android's own file picker; this repository never makes
/// a network call itself.
class BackupRepository {
  BackupRepository(this._db);

  final AppDatabase _db;

  /// Bumped only if a future export's JSON shape stops being back-compatible
  /// with [parseImport] below — see docs/features/data-import-export.md.
  static const _formatVersion = 1;

  Future<String> exportToJson() async {
    final appSettings = await _db.select(_db.appSettingsTable).getSingle();
    final accounts = await _db.select(_db.accounts).get();
    final categories = await _db.select(_db.categories).get();
    final notificationRules = await _db.select(_db.notificationRules).get();
    final recurringTransactions = await _db.select(_db.recurringTransactions).get();
    final transactions = await _db.select(_db.transactions).get();

    final export = <String, dynamic>{
      'exportFormatVersion': _formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'appSettings': appSettings.toJson(),
      'accounts': accounts.map((row) => row.toJson()).toList(),
      'categories': categories.map((row) => row.toJson()).toList(),
      'notificationRules': notificationRules.map((row) => row.toJson()).toList(),
      'recurringTransactions': recurringTransactions.map((row) => row.toJson()).toList(),
      'transactions': transactions.map((row) => row.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(export);
  }

  ImportPreview parseImport(String jsonString) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonString);
    } on FormatException {
      throw const BackupFormatException('This file is not valid JSON.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const BackupFormatException('This file is not a MoneyManager export.');
    }
    if (decoded['exportFormatVersion'] != _formatVersion) {
      throw const BackupFormatException('This export was made by an incompatible app version.');
    }
    try {
      // Older exports (before allTimeBalanceAdjustmentMinorUnits existed)
      // won't have this key — default it so those files keep importing
      // rather than failing as "missing expected data".
      final appSettingsJson = Map<String, dynamic>.from(decoded['appSettings'] as Map<String, dynamic>);
      appSettingsJson.putIfAbsent('allTimeBalanceAdjustmentMinorUnits', () => 0);
      appSettingsJson.putIfAbsent('includeArchivedInAllTimeBalance', () => false);

      // Older exports (before Account.isDefault existed) won't have this
      // key on each account row; Account.fromJson requires it (non-nullable
      // column), so default it per-row for the same reason as above.
      final accountsJson = (decoded['accounts'] as List).map((row) {
        return Map<String, dynamic>.from(row as Map<String, dynamic>)
          ..putIfAbsent('isDefault', () => false);
      }).toList();

      return ImportPreview(
        exportedAt: DateTime.parse(decoded['exportedAt'] as String),
        appSettings: AppSettingsTableData.fromJson(appSettingsJson),
        accounts: _parseList(accountsJson, Account.fromJson),
        categories: _parseList(decoded['categories'], Category.fromJson),
        notificationRules: _parseList(decoded['notificationRules'], NotificationRule.fromJson),
        recurringTransactions: _parseList(decoded['recurringTransactions'], RecurringTransaction.fromJson),
        transactions: _parseList(decoded['transactions'], Transaction.fromJson),
      );
    } on BackupFormatException {
      rethrow;
    } catch (_) {
      throw const BackupFormatException('This file is missing expected data and cannot be imported.');
    }
  }

  List<T> _parseList<T>(dynamic rawList, T Function(Map<String, dynamic>) fromJson) {
    if (rawList is! List) {
      throw const BackupFormatException('This file is missing expected data and cannot be imported.');
    }
    return rawList.map((row) => fromJson(row as Map<String, dynamic>)).toList();
  }

  /// Replaces every row in the database with [preview]'s contents, inside
  /// one transaction. Deletes children before parents, then inserts parents
  /// before children, to respect the foreign keys declared in tables.dart;
  /// original ids are preserved on insert so cross-references
  /// (`Transaction.categoryId`, etc.) still resolve correctly afterward.
  Future<void> applyImport(ImportPreview preview) {
    return _db.transaction(() async {
      await _db.delete(_db.transactions).go();
      await _db.delete(_db.notificationRules).go();
      await _db.delete(_db.recurringTransactions).go();
      await _db.delete(_db.categories).go();
      await _db.delete(_db.accounts).go();

      await _db.batch((batch) {
        batch.insertAll(_db.accounts, preview.accounts);
        batch.insertAll(_db.categories, preview.categories);
        batch.insertAll(_db.notificationRules, preview.notificationRules);
        batch.insertAll(_db.recurringTransactions, preview.recurringTransactions);
        batch.insertAll(_db.transactions, preview.transactions);
      });

      // AppSettingsTable is a guaranteed-single-row table (see
      // SettingsRepository) — update it in place rather than delete/insert,
      // so its own id is never in question.
      await _db.update(_db.appSettingsTable).write(
            AppSettingsTableCompanion(
              defaultCurrency: Value(preview.appSettings.defaultCurrency),
              themeMode: Value(preview.appSettings.themeMode),
              allTimeBalanceAdjustmentMinorUnits:
                  Value(preview.appSettings.allTimeBalanceAdjustmentMinorUnits),
              includeArchivedInAllTimeBalance:
                  Value(preview.appSettings.includeArchivedInAllTimeBalance),
            ),
          );
    });
  }
}

final backupRepositoryProvider = Provider<BackupRepository>((ref) {
  return BackupRepository(ref.watch(databaseProvider));
});
