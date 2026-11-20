import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';
import '../../../platform/notification_listener/notification_listener_channel.dart';

class NotificationRulesRepository {
  NotificationRulesRepository(this._db);

  final AppDatabase _db;

  Stream<List<NotificationRule>> watchAll() {
    final query = _db.select(_db.notificationRules)
      ..orderBy([(r) => OrderingTerm.asc(r.priority), (r) => OrderingTerm.asc(r.id)]);
    return query.watch();
  }

  /// Rules to evaluate for one notification: enabled, and either targeting
  /// its app package or flagged to match any app, ordered by priority
  /// ascending (ties broken by id) — lower priority runs first, and "first
  /// match wins" (the matched rule's result is used, the rest are never
  /// evaluated) — see docs/features/notification-capture.md "Matching
  /// details".
  Future<List<NotificationRule>> enabledRulesForPackage(String package) {
    return (_db.select(_db.notificationRules)
          ..where((r) => r.isEnabled.equals(true) & (r.appPackage.equals(package) | r.matchAnyApp.equals(true)))
          ..orderBy([(r) => OrderingTerm.asc(r.priority), (r) => OrderingTerm.asc(r.id)]))
        .get();
  }

  /// Every enabled rule, with no app-package filter — used for the
  /// "Insert from text" manual-entry screen (see docs/features/
  /// notification-capture.md "Manual text entry"), where there's no real
  /// notification to know a package from. Same priority-ascending order as
  /// [enabledRulesForPackage], so "first match wins" behaves identically.
  Future<List<NotificationRule>> enabledRules() {
    return (_db.select(_db.notificationRules)
          ..where((r) => r.isEnabled.equals(true))
          ..orderBy([(r) => OrderingTerm.asc(r.priority), (r) => OrderingTerm.asc(r.id)]))
        .get();
  }

  Future<int> addRule({
    required String name,
    String? fallbackName,
    required String appPackage,
    bool matchAnyApp = false,
    required String regexPattern,
    required int amountGroup,
    required String transactionType,
    int? defaultCategoryId,
    required int defaultAccountId,
    required bool autoAdd,
    int? priority,
    int? dateGroup,
    String? dateFormat,
    int? noteGroup,
    int? nameGroup,
  }) async {
    // Computing the next priority and inserting are wrapped in one
    // transaction so two near-simultaneous addRule() calls (e.g. a rapid
    // double-tap of Save) can't both read the same "current max" and
    // assign the same priority to two different new rules.
    final id = await _db.transaction(() async {
      final resolvedPriority = priority ?? await _nextPriority();
      return _db.into(_db.notificationRules).insert(
            NotificationRulesCompanion.insert(
              name: name,
              fallbackName: Value(fallbackName),
              appPackage: appPackage,
              matchAnyApp: Value(matchAnyApp),
              regexPattern: regexPattern,
              amountGroup: Value(amountGroup),
              transactionType: transactionType,
              defaultCategoryId: Value(defaultCategoryId),
              defaultAccountId: defaultAccountId,
              autoAdd: Value(autoAdd),
              priority: Value(resolvedPriority),
              dateGroup: Value(dateGroup),
              dateFormat: Value(dateFormat),
              noteGroup: Value(noteGroup),
              nameGroup: Value(nameGroup),
            ),
          );
    });
    await _pushAllowlist();
    return id;
  }

  Future<void> updateRule(
    int id, {
    required String name,
    String? fallbackName,
    required String appPackage,
    bool matchAnyApp = false,
    required String regexPattern,
    required int amountGroup,
    required String transactionType,
    int? defaultCategoryId,
    required int defaultAccountId,
    required bool autoAdd,
    // Null means "run last" — same meaning as in addRule, so a blank
    // Priority field behaves identically whether adding or editing a rule
    // (see rule_editor_sheet.dart's priority-field hint text).
    int? priority,
    int? dateGroup,
    String? dateFormat,
    int? noteGroup,
    int? nameGroup,
  }) async {
    await _db.transaction(() async {
      final resolvedPriority = priority ?? await _nextPriority();
      await (_db.update(_db.notificationRules)..where((r) => r.id.equals(id))).write(
        NotificationRulesCompanion(
          name: Value(name),
          fallbackName: Value(fallbackName),
          appPackage: Value(appPackage),
          matchAnyApp: Value(matchAnyApp),
          regexPattern: Value(regexPattern),
          amountGroup: Value(amountGroup),
          transactionType: Value(transactionType),
          defaultCategoryId: Value(defaultCategoryId),
          defaultAccountId: Value(defaultAccountId),
          autoAdd: Value(autoAdd),
          priority: Value(resolvedPriority),
          dateGroup: Value(dateGroup),
          dateFormat: Value(dateFormat),
          noteGroup: Value(noteGroup),
          nameGroup: Value(nameGroup),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
    await _pushAllowlist();
  }

  Future<void> setEnabled(int id, bool isEnabled) async {
    await (_db.update(_db.notificationRules)..where((r) => r.id.equals(id)))
        .write(NotificationRulesCompanion(isEnabled: Value(isEnabled)));
    await _pushAllowlist();
  }

  Future<void> deleteRule(int id) async {
    await (_db.delete(_db.notificationRules)..where((r) => r.id.equals(id))).go();
    await _pushAllowlist();
  }

  /// Persists a new evaluation order after a drag-to-reorder in the Rules
  /// screen: [orderedIds] is the full rule list's ids in their new
  /// (top-to-bottom = evaluation-order) sequence, each rule's priority is
  /// set to its index.
  Future<void> reorderRules(List<int> orderedIds) async {
    await _db.batch((batch) {
      for (var index = 0; index < orderedIds.length; index++) {
        batch.update(
          _db.notificationRules,
          NotificationRulesCompanion(priority: Value(index)),
          where: (r) => r.id.equals(orderedIds[index]),
        );
      }
    });
  }

  Future<int> _nextPriority() async {
    final rules = await _db.select(_db.notificationRules).get();
    if (rules.isEmpty) return 0;
    return rules.map((r) => r.priority).reduce((a, b) => a > b ? a : b) + 1;
  }

  /// Pushes the current set of packages with ≥1 enabled rule, and whether
  /// any enabled rule matches any app, to the native listener — see
  /// docs/features/notification-capture.md "Permission & platform
  /// mechanics" / "Any-app rules". Best-effort: failures here (e.g. in a
  /// test environment with no platform channel) shouldn't block the DB
  /// write that triggered it.
  Future<void> _pushAllowlist() async {
    try {
      final enabled = await (_db.select(_db.notificationRules)..where((r) => r.isEnabled.equals(true))).get();
      final packages = enabled.map((r) => r.appPackage).toSet().toList();
      final matchAnyApp = enabled.any((r) => r.matchAnyApp);
      await notificationListenerChannel.updateAllowlist(packages, matchAnyApp: matchAnyApp);
    } catch (_) {
      // Platform channel unavailable (e.g. unit tests) — safe to ignore.
    }
  }
}

final notificationRulesRepositoryProvider = Provider<NotificationRulesRepository>((ref) {
  return NotificationRulesRepository(ref.watch(databaseProvider));
});

final notificationRulesProvider = StreamProvider<List<NotificationRule>>((ref) {
  return ref.watch(notificationRulesRepositoryProvider).watchAll();
});
