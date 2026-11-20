import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';
import '../../../platform/notification_listener/notification_listener_channel.dart';
import '../domain/rule_matcher.dart';
import 'notification_rules_repository.dart';

/// Placeholder strings Android (System Intelligence, Android 15+) substitutes
/// for a notification's real text when it delivers that notification to a
/// third-party `NotificationListenerService` it doesn't trust — see
/// docs/features/notification-capture.md "Known limitation: OS-level content
/// redaction". Best-effort detection only: not a stable, documented API, and
/// may vary by OS version/locale/OEM.
const _redactionPlaceholders = ['Sensitive notification content hidden'];

bool looksRedacted(CapturedNotification notification) {
  return _redactionPlaceholders.any((p) => notification.text.contains(p) || notification.title.contains(p));
}

/// Tracks, for this app session only, whether a notification from an
/// allowlisted package arrived with its content redacted by the OS — see
/// [looksRedacted]. Surfaced as a one-time hint on RulesScreen; not
/// persisted, since it's just a "heads up" rather than a durable fact.
final notificationRedactionDetectedProvider = StateProvider<bool>((ref) => false);

/// The single code path that turns one captured notification into a
/// transaction (or a review-queue draft) — shared by both entry points
/// described in docs/architecture.md "Notification capture — how the app
/// gets invoked": the live event-channel stream (app's Flutter engine
/// already running) and the headless-engine dispatcher (app fully closed).
class NotificationCaptureService {
  NotificationCaptureService(this._db, this._rulesRepository);

  final AppDatabase _db;
  final NotificationRulesRepository _rulesRepository;

  /// Returns true if the notification's content looked redacted by the OS
  /// (see [looksRedacted]) — callers with access to a Riverpod `ref` (the
  /// live-path listener in app.dart) use this to flag
  /// [notificationRedactionDetectedProvider] for the UI. The headless path
  /// has no UI to update, so it just drops the notification either way.
  Future<bool> handle(CapturedNotification notification) async {
    final rules = await _rulesRepository.enabledRulesForPackage(notification.package);
    if (rules.isEmpty) return false;

    final redacted = looksRedacted(notification);
    if (redacted) return true;

    final match = matchRules(rules: rules, combinedText: notification.combinedText);
    if (match == null) return false;

    await _insert(match, fallbackDate: notification.postTime, sourceAppPackage: notification.package);
    return false;
  }

  /// Matches pasted [text] against every enabled rule, ignoring app
  /// package (there's no real notification to filter by) — the first step
  /// of the "Insert from text" manual-entry screen (see docs/features/
  /// notification-capture.md "Manual text entry"), for recovering a
  /// notification the listener missed. Pure match, no DB write — call
  /// [insertManualMatch] with the result once the user confirms the
  /// preview.
  Future<RuleMatch?> matchManualText(String text) async {
    final rules = await _rulesRepository.enabledRules();
    return matchRules(rules: rules, combinedText: text);
  }

  /// Inserts the transaction for a [RuleMatch] from [matchManualText],
  /// once the user has reviewed the preview and confirmed. Returns true if
  /// it went to the review queue (the matched rule's `autoAdd` is false)
  /// rather than posting directly, so the caller can word its confirmation
  /// accordingly.
  Future<bool> insertManualMatch(RuleMatch match) {
    return _insert(match, fallbackDate: DateTime.now(), sourceAppPackage: null);
  }

  /// Shared by [handle] and [insertManualMatch]: resolves the date/currency
  /// and writes the transaction for an already-successful [RuleMatch].
  /// [fallbackDate] is used when the rule has no date-group (or it didn't
  /// parse) — the notification's own post time for live/headless capture,
  /// "now" for a manually-entered one with no captured date. Returns
  /// whether it went to the review queue (`!match.rule.autoAdd`, or forced
  /// there by duplicate detection below).
  ///
  /// Duplicate detection (re-added 2026-11-18, replacing the "no duplicate
  /// protection" decision of 2026-11-08 — see docs/features/
  /// notification-capture.md "Matching details"): rather than silently
  /// skipping the insert (the old, since-removed behavior, which risked
  /// losing a genuine second transaction with the same shape) or silently
  /// inserting a real duplicate, a notification/headless match that looks
  /// identical to an already-stored one (same rule, source app, amount,
  /// and resolved date) is still inserted, but flagged via
  /// [duplicateOfTransactionId] and forced into the review queue
  /// regardless of the rule's own autoAdd, so the user decides rather than
  /// either copy being silently dropped or silently double-counted. Only
  /// applies to live/headless capture ([sourceAppPackage] non-null) —
  /// manual text entry has no real notification to have been redelivered,
  /// so it's excluded, matching its existing documented behavior.
  Future<bool> _insert(
    RuleMatch match, {
    required DateTime fallbackDate,
    required String? sourceAppPackage,
  }) async {
    final resolvedDate = match.date ?? fallbackDate;
    final settings = await _db.select(_db.appSettingsTable).getSingleOrNull();
    final currency = settings?.defaultCurrency ?? 'USD';

    int? duplicateOfTransactionId;
    if (sourceAppPackage != null) {
      final existing = await (_db.select(_db.transactions)
            ..where((t) =>
                t.sourceRuleId.equals(match.rule.id) &
                t.sourceAppPackage.equals(sourceAppPackage) &
                t.amountMinorUnits.equals(match.amountMinorUnits) &
                t.date.equals(resolvedDate))
            ..limit(1))
          .getSingleOrNull();
      duplicateOfTransactionId = existing?.id;
    }
    final isPendingReview = !match.rule.autoAdd || duplicateOfTransactionId != null;

    await _db.into(_db.transactions).insert(
          TransactionsCompanion.insert(
            accountId: match.rule.defaultAccountId,
            categoryId: Value(match.rule.defaultCategoryId),
            type: match.rule.transactionType,
            amountMinorUnits: match.amountMinorUnits,
            currency: currency,
            date: resolvedDate,
            note: Value(match.note),
            source: const Value('notification'),
            sourceAppPackage: Value(sourceAppPackage),
            sourceRuleId: Value(match.rule.id),
            isPendingReview: Value(isPendingReview),
            duplicateOfTransactionId: Value(duplicateOfTransactionId),
          ),
        );
    return isPendingReview;
  }
}

final notificationCaptureServiceProvider = Provider<NotificationCaptureService>((ref) {
  return NotificationCaptureService(
    ref.watch(databaseProvider),
    ref.watch(notificationRulesRepositoryProvider),
  );
});
