import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';
import '../../../platform/notification_listener/notification_listener_channel.dart';

/// Thrown by [RulesBackupRepository.parseImport] when a picked file isn't a
/// rules-only export this app version understands, or is actually a full
/// database export (Phase 5) — mirrors [BackupFormatException] from
/// data-import-export.md, same intent: never let a bad file crash the
/// import flow.
class RulesBackupFormatException implements Exception {
  const RulesBackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Why one exported rule can or can't land on this device — see
/// docs/features/rules-import-export.md "The core problem".
enum RuleImportStatus {
  /// Its account (and category, if any) resolved by name on this device,
  /// and it's not a duplicate of an existing rule — will be inserted.
  importable,

  /// Same name + app scope + regex as a rule already on this device —
  /// skipped so re-importing the same file twice doesn't pile up copies.
  duplicate,

  /// Its account (or category) name doesn't match anything on this
  /// device — skipped; auto-creating accounts/categories is a non-goal.
  unresolvable,
}

/// One rule from an import file, with its name-based lookup against this
/// device's current accounts/categories already resolved.
class RuleImportItem {
  const RuleImportItem({
    required this.name,
    required this.appPackage,
    required this.matchAnyApp,
    required this.isEnabled,
    required this.isPreset,
    required this.regexPattern,
    required this.amountGroup,
    required this.transactionType,
    required this.defaultAccountName,
    required this.defaultCategoryName,
    required this.autoAdd,
    required this.priority,
    required this.dateGroup,
    required this.dateFormat,
    required this.noteGroup,
    required this.nameGroup,
    required this.status,
    required this.resolvedAccountId,
    required this.resolvedCategoryId,
  });

  final String name;
  final String appPackage;
  final bool matchAnyApp;
  final bool isEnabled;
  final bool isPreset;
  final String regexPattern;
  final int amountGroup;
  final String transactionType;
  final String defaultAccountName;
  final String? defaultCategoryName;
  final bool autoAdd;
  final int priority;
  final int? dateGroup;
  final String? dateFormat;
  final int? noteGroup;
  final int? nameGroup;

  final RuleImportStatus status;
  final int? resolvedAccountId;
  final int? resolvedCategoryId;
}

/// A parsed, not-yet-applied rules export — lets the Settings UI show a
/// summary (how many will import, how many are duplicates/unresolvable)
/// before [RulesBackupRepository.applyImport] inserts anything.
class RulesImportPreview {
  const RulesImportPreview({required this.exportedAt, required this.items});

  final DateTime exportedAt;
  final List<RuleImportItem> items;

  List<RuleImportItem> get importable =>
      items.where((i) => i.status == RuleImportStatus.importable).toList();

  List<RuleImportItem> get duplicates =>
      items.where((i) => i.status == RuleImportStatus.duplicate).toList();

  List<RuleImportItem> get unresolvable =>
      items.where((i) => i.status == RuleImportStatus.unresolvable).toList();

  /// Distinct missing account/category names across all unresolvable
  /// items, for the confirmation summary (e.g. "references an account
  /// that doesn't exist here: 'Chase Checking'").
  List<String> get missingNames {
    final names = <String>{};
    for (final item in unresolvable) {
      if (item.resolvedAccountId == null) names.add(item.defaultAccountName);
      if (item.defaultCategoryName != null && item.resolvedCategoryId == null) {
        names.add(item.defaultCategoryName!);
      }
    }
    return names.toList();
  }
}

/// Local export/import of just the `NotificationRule` table — see
/// docs/features/rules-import-export.md. Deliberately separate from
/// [BackupRepository] (Phase 5): that one always replaces everything, this
/// one always merges/appends, and neither modifies the other's file format
/// or UI.
class RulesBackupRepository {
  RulesBackupRepository(this._db);

  final AppDatabase _db;

  static const _fileType = 'money_manager_rules_export';
  static const _formatVersion = 1;

  Future<String> exportToJson() async {
    final rules = await _db.select(_db.notificationRules).get();
    final accounts = await _db.select(_db.accounts).get();
    final categories = await _db.select(_db.categories).get();
    final accountNames = {for (final a in accounts) a.id: a.name};
    final categoryNames = {for (final c in categories) c.id: c.name};

    final export = <String, dynamic>{
      'fileType': _fileType,
      'exportFormatVersion': _formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'rules': rules
          .map((r) => {
                'rule': r.toJson(),
                'defaultAccountName': accountNames[r.defaultAccountId] ?? '',
                'defaultCategoryName': r.defaultCategoryId == null ? null : categoryNames[r.defaultCategoryId],
              })
          .toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(export);
  }

  Future<RulesImportPreview> parseImport(String jsonString) async {
    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonString);
    } on FormatException {
      throw const RulesBackupFormatException('This file is not valid JSON.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const RulesBackupFormatException('This file is not a MoneyManager rules export.');
    }
    if (decoded['fileType'] != _fileType) {
      // The full backup (Phase 5) doesn't carry a fileType marker of its
      // own — recognize its shape directly so picking the wrong file gets
      // a specific, helpful message instead of a generic one.
      if (decoded.containsKey('appSettings') && decoded.containsKey('accounts')) {
        throw const RulesBackupFormatException(
          'This is a full data export, not a rules export. Use "Import data" instead.',
        );
      }
      throw const RulesBackupFormatException('This file is not a MoneyManager rules export.');
    }
    if (decoded['exportFormatVersion'] != _formatVersion) {
      throw const RulesBackupFormatException('This export was made by an incompatible app version.');
    }

    final rawRules = decoded['rules'];
    if (rawRules is! List) {
      throw const RulesBackupFormatException('This file is missing expected data and cannot be imported.');
    }

    final DateTime exportedAt;
    try {
      exportedAt = DateTime.parse(decoded['exportedAt'] as String);
    } catch (_) {
      throw const RulesBackupFormatException('This file is missing expected data and cannot be imported.');
    }

    final accounts = await _db.select(_db.accounts).get();
    final categories = await _db.select(_db.categories).get();
    final existingRules = await _db.select(_db.notificationRules).get();
    final accountIdByName = {for (final a in accounts) a.name.toLowerCase(): a.id};
    final categoryIdByName = {for (final c in categories) c.name.toLowerCase(): c.id};

    final items = <RuleImportItem>[];
    for (final raw in rawRules) {
      if (raw is! Map<String, dynamic>) {
        throw const RulesBackupFormatException('This file is missing expected data and cannot be imported.');
      }
      final NotificationRule rule;
      try {
        rule = NotificationRule.fromJson(raw['rule'] as Map<String, dynamic>);
      } catch (_) {
        throw const RulesBackupFormatException('This file is missing expected data and cannot be imported.');
      }
      final accountName = raw['defaultAccountName'] as String? ?? '';
      final categoryName = raw['defaultCategoryName'] as String?;

      final resolvedAccountId = accountIdByName[accountName.toLowerCase()];
      final resolvedCategoryId = categoryName == null ? null : categoryIdByName[categoryName.toLowerCase()];

      final isDuplicate = existingRules.any((r) =>
          r.name.toLowerCase() == rule.name.toLowerCase() &&
          r.appPackage.toLowerCase() == rule.appPackage.toLowerCase() &&
          r.matchAnyApp == rule.matchAnyApp &&
          r.regexPattern == rule.regexPattern);

      final accountResolved = resolvedAccountId != null;
      final categoryResolved = categoryName == null || resolvedCategoryId != null;

      final status = !accountResolved || !categoryResolved
          ? RuleImportStatus.unresolvable
          : isDuplicate
              ? RuleImportStatus.duplicate
              : RuleImportStatus.importable;

      items.add(RuleImportItem(
        name: rule.name,
        appPackage: rule.appPackage,
        matchAnyApp: rule.matchAnyApp,
        isEnabled: rule.isEnabled,
        isPreset: rule.isPreset,
        regexPattern: rule.regexPattern,
        amountGroup: rule.amountGroup,
        transactionType: rule.transactionType,
        defaultAccountName: accountName,
        defaultCategoryName: categoryName,
        autoAdd: rule.autoAdd,
        priority: rule.priority,
        dateGroup: rule.dateGroup,
        dateFormat: rule.dateFormat,
        noteGroup: rule.noteGroup,
        nameGroup: rule.nameGroup,
        status: status,
        resolvedAccountId: resolvedAccountId,
        resolvedCategoryId: resolvedCategoryId,
      ));
    }

    return RulesImportPreview(exportedAt: exportedAt, items: items);
  }

  /// Inserts every [RulesImportPreview.importable] item as a new rule,
  /// appended after this device's existing rules in evaluation order
  /// (lowest priority first — see NotificationRulesRepository). Duplicate
  /// and unresolvable items are never inserted; this never touches any
  /// other table.
  Future<void> applyImport(RulesImportPreview preview) async {
    final importable = preview.importable;
    if (importable.isEmpty) return;

    await _db.transaction(() async {
      final existing = await _db.select(_db.notificationRules).get();
      var nextPriority = existing.isEmpty
          ? 0
          : existing.map((r) => r.priority).reduce((a, b) => a > b ? a : b) + 1;

      await _db.batch((batch) {
        for (final item in importable) {
          batch.insert(
            _db.notificationRules,
            NotificationRulesCompanion.insert(
              name: item.name,
              appPackage: item.appPackage,
              matchAnyApp: Value(item.matchAnyApp),
              isEnabled: Value(item.isEnabled),
              isPreset: Value(item.isPreset),
              regexPattern: item.regexPattern,
              amountGroup: Value(item.amountGroup),
              transactionType: item.transactionType,
              defaultCategoryId: Value(item.resolvedCategoryId),
              defaultAccountId: item.resolvedAccountId!,
              autoAdd: Value(item.autoAdd),
              priority: Value(nextPriority++),
              dateGroup: Value(item.dateGroup),
              dateFormat: Value(item.dateFormat),
              noteGroup: Value(item.noteGroup),
              nameGroup: Value(item.nameGroup),
            ),
          );
        }
      });
    });

    try {
      final enabled = await (_db.select(_db.notificationRules)..where((r) => r.isEnabled.equals(true))).get();
      final packages = enabled.map((r) => r.appPackage).toSet().toList();
      final matchAnyApp = enabled.any((r) => r.matchAnyApp);
      await notificationListenerChannel.updateAllowlist(packages, matchAnyApp: matchAnyApp);
    } catch (_) {
      // Platform channel unavailable (e.g. unit tests) — safe to ignore,
      // same as NotificationRulesRepository's own best-effort push.
    }
  }
}

final rulesBackupRepositoryProvider = Provider<RulesBackupRepository>((ref) {
  return RulesBackupRepository(ref.watch(databaseProvider));
});
