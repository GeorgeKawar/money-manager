import '../../../core/database/database.dart';
import 'amount_parser.dart';
import 'date_parser.dart';

/// Result of successfully matching a notification against a rule.
class RuleMatch {
  const RuleMatch({
    required this.rule,
    required this.amountMinorUnits,
    required this.date,
    required this.note,
  });

  final NotificationRule rule;
  final int amountMinorUnits;

  /// Parsed from the rule's dateGroup/dateFormat, if set and successfully
  /// parsed. Null means "use the notification's own post time" — resolved
  /// by the caller, not here (see notification_capture_service.dart).
  final DateTime? date;

  /// Always non-blank: nameGroup's capture if set and matched, else the
  /// rule's own name; noteGroup's capture, if set and matched, is appended
  /// with " · " — see docs/features/notification-capture.md "Matching
  /// details".
  final String note;
}

/// Tries [rules] (already filtered to the notification's app package or
/// any-app rules, and to enabled ones, and ordered by priority ascending —
/// see NotificationRulesRepository) against [combinedText] in order and
/// returns the first one that both matches its regex and yields a
/// parseable amount — "first match wins" per docs/features/
/// notification-capture.md "Matching details". Returns null if no rule
/// matches.
RuleMatch? matchRules({required List<NotificationRule> rules, required String combinedText}) {
  for (final rule in rules) {
    final match = _tryMatch(rule, combinedText);
    if (match != null) return match;
  }
  return null;
}

/// Returns the regex match's group [index], or null if [index] is null or
/// out of bounds for [match] (bounds-checked the same way the amount group
/// has always been).
String? _safeGroup(RegExpMatch match, int? index) {
  if (index == null || index < 1 || index > match.groupCount) return null;
  return match.group(index);
}

/// The one place that defines how a name-group capture, a note-group
/// capture, and a fallback name combine into `Transaction.note` — both the
/// production match path ([_resolveNote]) and the rule editor's live
/// preview ([testRule]) call this, so the two can't silently drift apart.
String _composeNote({required String? rawName, required String? rawNote, required String fallbackName}) {
  final base = (rawName != null && rawName.trim().isNotEmpty) ? rawName.trim() : fallbackName;
  if (rawNote == null || rawNote.trim().isEmpty) return base;
  return '$base · ${rawNote.trim()}';
}

/// The one place that defines how a date-group capture + format parse into
/// a resolved date — see [_composeNote] for why this is shared between
/// [_resolveDate] and [testRule].
DateTime? _composeDate({required String? rawDate, required String? format}) {
  if (rawDate == null || format == null || format.isEmpty) return null;
  return parseDateWithFormat(rawDate, format);
}

String _resolveNote({
  required RegExpMatch match,
  required NotificationRule rule,
}) {
  return _composeNote(
    rawName: _safeGroup(match, rule.nameGroup),
    rawNote: _safeGroup(match, rule.noteGroup),
    fallbackName: rule.name,
  );
}

DateTime? _resolveDate({
  required RegExpMatch match,
  required NotificationRule rule,
}) {
  return _composeDate(rawDate: _safeGroup(match, rule.dateGroup), format: rule.dateFormat);
}

RuleMatch? _tryMatch(NotificationRule rule, String combinedText) {
  final RegExp regex;
  try {
    regex = RegExp(rule.regexPattern);
  } on FormatException {
    return null;
  }
  final match = regex.firstMatch(combinedText);
  if (match == null) return null;
  final rawAmount = _safeGroup(match, rule.amountGroup);
  if (rawAmount == null) return null;
  final amountMinorUnits = parseAmountToMinorUnits(rawAmount);
  if (amountMinorUnits == null || amountMinorUnits <= 0) return null;
  return RuleMatch(
    rule: rule,
    amountMinorUnits: amountMinorUnits,
    date: _resolveDate(match: match, rule: rule),
    note: _resolveNote(match: match, rule: rule),
  );
}

/// Diagnostic result for the rule editor's "test this rule" tool — unlike
/// [matchRules], this reports *why* a single rule didn't match so the user
/// can fix their pattern, rather than just yielding null, and previews the
/// optional date/name/note groups alongside the amount.
class RuleTestResult {
  const RuleTestResult({
    required this.regexError,
    required this.matched,
    required this.rawCapturedGroup,
    required this.amountMinorUnits,
    this.resolvedNote,
    this.resolvedDate,
    this.dateError,
  });

  final String? regexError;
  final bool matched;
  final String? rawCapturedGroup;
  final int? amountMinorUnits;

  /// Preview of the name/note resolution (see [RuleMatch.note]); null only
  /// when [matched] is false.
  final String? resolvedNote;

  /// Preview of the date-group parse; null if no dateGroup/dateFormat is
  /// set, or if [matched] is false.
  final DateTime? resolvedDate;

  /// Set when a dateGroup/dateFormat is configured but the sample text's
  /// captured group couldn't be parsed with it.
  final String? dateError;

  bool get isSuccess => regexError == null && matched && amountMinorUnits != null;
}

RuleTestResult testRule({
  required String regexPattern,
  required int amountGroup,
  required String sampleText,
  String ruleName = '',
  int? dateGroup,
  String? dateFormat,
  int? noteGroup,
  int? nameGroup,
}) {
  final RegExp regex;
  try {
    regex = RegExp(regexPattern);
  } on FormatException catch (e) {
    return RuleTestResult(
      regexError: e.message,
      matched: false,
      rawCapturedGroup: null,
      amountMinorUnits: null,
    );
  }
  final match = regex.firstMatch(sampleText);
  if (match == null) {
    return const RuleTestResult(
      regexError: null,
      matched: false,
      rawCapturedGroup: null,
      amountMinorUnits: null,
    );
  }
  if (amountGroup < 1 || amountGroup > match.groupCount) {
    return RuleTestResult(
      regexError: 'Pattern only has ${match.groupCount} capture group(s).',
      matched: true,
      rawCapturedGroup: null,
      amountMinorUnits: null,
    );
  }
  final rawAmount = match.group(amountGroup);
  final amountMinorUnits = rawAmount == null ? null : parseAmountToMinorUnits(rawAmount);

  final resolvedNote = _composeNote(
    rawName: _safeGroup(match, nameGroup),
    rawNote: _safeGroup(match, noteGroup),
    fallbackName: ruleName.isNotEmpty ? ruleName : '(rule name)',
  );

  DateTime? resolvedDate;
  String? dateError;
  final rawDate = _safeGroup(match, dateGroup);
  if (dateGroup != null && rawDate != null && dateFormat != null && dateFormat.isNotEmpty) {
    resolvedDate = _composeDate(rawDate: rawDate, format: dateFormat);
    if (resolvedDate == null) dateError = 'Could not parse "$rawDate" with format "$dateFormat".';
  }

  return RuleTestResult(
    regexError: null,
    matched: true,
    rawCapturedGroup: rawAmount,
    amountMinorUnits: amountMinorUnits,
    resolvedNote: resolvedNote,
    resolvedDate: resolvedDate,
    dateError: dateError,
  );
}
