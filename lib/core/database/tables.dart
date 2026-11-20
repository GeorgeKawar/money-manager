import 'package:drift/drift.dart';

/// Single-row table for app-wide preferences. The app guarantees exactly
/// one row exists (seeded in onCreate); callers read/update "the" row
/// without filtering by id — see SettingsRepository.
/// See docs/data-model.md `AppSettings`.
class AppSettingsTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get defaultCurrency => text().withDefault(const Constant('USD'))();
  // 'system' | 'light' | 'dark'
  TextColumn get themeMode => text().withDefault(const Constant('system'))();
  // User-set correction added on top of the computed all-time balance (see
  // docs/data-model.md "Derived/computed" and
  // TransactionsRepository.watchAllTimeBalanceMinorUnits) — lets the
  // dashboard balance be nudged to a value the user expects (e.g. after
  // archiving an account) without discarding the running computed total.
  IntColumn get allTimeBalanceAdjustmentMinorUnits => integer().withDefault(const Constant(0))();
  // False (default) = all-time balance excludes archived accounts, per the
  // 2026-11-08 fix. True = archived accounts' starting balances and
  // transactions count toward it too, for users who want the old
  // behavior back — see docs/features/categories-accounts.md.
  BoolColumn get includeArchivedInAllTimeBalance => boolean().withDefault(const Constant(false))();
  // Privacy toggle: masks the all-time balance card's amount (e.g. behind a
  // shoulder-surfer) until tapped to reveal. Added 2026-11-20, user
  // request. Default false — the balance is shown as it always was.
  BoolColumn get isBalanceMasked => boolean().withDefault(const Constant(false))();
}

/// See docs/data-model.md `Account`.
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  // Scaled by 1000 (thousandths), not 100 — see Transactions.amountMinorUnits.
  IntColumn get startingBalanceMinorUnits => integer().withDefault(const Constant(0))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  // At most one account has this set — see AccountsRepository.setDefault.
  // Pre-fills the account field on new manual transactions and on new
  // notification rules, per docs/features/categories-accounts.md.
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  // Per-account override for whether this account counts toward the
  // dashboard's all-time balance — independent of isArchived (the existing
  // AppSettings.includeArchivedInAllTimeBalance toggle controls archived
  // accounts as a group; this lets one specific account, active or
  // archived, be excluded/included individually). Default true preserves
  // every pre-existing account's current behavior. Added 2026-11-20, user
  // request. See TransactionsRepository.watchAllTimeBalanceMinorUnits.
  BoolColumn get includeInAllTimeBalance => boolean().withDefault(const Constant(true))();
}

/// See docs/data-model.md `Category`.
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  // 'income' | 'expense' | 'both'
  TextColumn get type => text()();
  TextColumn get icon => text().nullable()();
  // ARGB stored as a signed 32-bit int.
  IntColumn get color => integer().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
}

/// See docs/data-model.md `NotificationRule`.
class NotificationRules extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  // Overrides `name` as the Transaction.note fallback (used when nameGroup
  // is unset or doesn't match — see docs/features/notification-capture.md
  // "Matching details") without changing the rule's own display name in
  // the Rules screen. Added 2026-11-20, user request. Null/blank means
  // "use `name`", preserving the original behavior for existing rules.
  TextColumn get fallbackName => text().nullable()();
  // Ignored (may be blank) when matchAnyApp is true.
  TextColumn get appPackage => text()();
  // True = evaluate this rule against notifications from any app, not just
  // appPackage — see docs/features/notification-capture.md "Any-app rules".
  BoolColumn get matchAnyApp => boolean().withDefault(const Constant(false))();
  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();
  BoolColumn get isPreset => boolean().withDefault(const Constant(false))();
  TextColumn get regexPattern => text()();
  IntColumn get amountGroup => integer().withDefault(const Constant(1))();
  // 'income' | 'expense'
  TextColumn get transactionType => text()();
  IntColumn get defaultCategoryId =>
      integer().nullable().references(Categories, #id)();
  IntColumn get defaultAccountId => integer().references(Accounts, #id)();
  BoolColumn get autoAdd => boolean().withDefault(const Constant(false))();
  // Evaluation order across all of a notification's candidate rules, lowest
  // first ("first match wins" — see docs/features/notification-capture.md
  // "Matching details"). Explicit and user-editable/reorderable, not implied
  // by id/creation order.
  IntColumn get priority => integer().withDefault(const Constant(0))();
  // Optional capture groups layered on top of the required amountGroup —
  // each nullable/independent of the others, see docs/features/
  // notification-capture.md "Matching details".
  IntColumn get dateGroup => integer().nullable()();
  // DateFormat pattern (package:intl) used to parse dateGroup's capture,
  // e.g. "dd-MMM-yyyy". Required (and only meaningful) when dateGroup is set.
  TextColumn get dateFormat => text().nullable()();
  IntColumn get noteGroup => integer().nullable()();
  IntColumn get nameGroup => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// See docs/data-model.md `RecurringTransaction`.
class RecurringTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get accountId => integer().references(Accounts, #id)();
  IntColumn get categoryId => integer().nullable().references(Categories, #id)();
  // 'income' | 'expense'
  TextColumn get type => text()();
  // Scaled by 1000 (thousandths) — see Transactions.amountMinorUnits.
  IntColumn get amountMinorUnits => integer()();
  TextColumn get note => text().nullable()();
  // 'daily' | 'weekly' | 'monthly' | 'yearly'
  TextColumn get frequency => text()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();
  DateTimeColumn get nextRunDate => dateTime()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

/// See docs/data-model.md `Transaction`.
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get accountId => integer().references(Accounts, #id)();
  IntColumn get categoryId => integer().nullable().references(Categories, #id)();
  // 'income' | 'expense' | 'transfer'
  TextColumn get type => text()();
  // Fixed-point, scaled by 1000 (thousandths of the major unit) regardless
  // of the currency's own minor-unit precision. ISO 4217 currencies use at
  // most 3 decimal digits (e.g. KWD/BHD/JOD), most use 2, some use 0 — this
  // single scale represents all of them losslessly; formatting divides back
  // down and rounds to the currency's actual decimal digits for display.
  IntColumn get amountMinorUnits => integer()();
  // ISO code snapshotted from AppSettings.defaultCurrency at creation time.
  TextColumn get currency => text()();
  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().nullable()();
  // Free-text detail distinct from `note` (shown as the transaction's
  // required "Name" in the add/edit sheet) — added 2026-11-20, user
  // request, for extra detail beyond the short name.
  TextColumn get description => text().nullable()();
  // 'manual' | 'notification' | 'recurring'
  TextColumn get source => text().withDefault(const Constant('manual'))();
  TextColumn get sourceAppPackage => text().nullable()();
  IntColumn get sourceRuleId =>
      integer().nullable().references(NotificationRules, #id)();
  IntColumn get transferPairId => integer().nullable()();
  IntColumn get recurringId =>
      integer().nullable().references(RecurringTransactions, #id)();
  BoolColumn get isPendingReview => boolean().withDefault(const Constant(false))();
  // Set when this transaction looks like a redelivered duplicate of an
  // existing one (same rule/app/amount/resolved date — see
  // NotificationCaptureService._insert) — points at that existing
  // transaction's id. Non-null forces isPendingReview = true regardless of
  // the matched rule's autoAdd, so it lands in the review queue for the
  // user to confirm or discard rather than being silently dropped or
  // silently double-counted. Only set for live/headless notification
  // capture, never manual text entry — see docs/features/
  // notification-capture.md "Matching details".
  IntColumn get duplicateOfTransactionId => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
