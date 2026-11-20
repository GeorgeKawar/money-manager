import 'package:intl/intl.dart';

/// Parses a raw captured date string using a rule-specified `DateFormat`
/// (package:intl) pattern, e.g. "dd-MMM-yyyy". Returns null if the pattern
/// is invalid or [raw] doesn't match it — same "return null on failure"
/// convention as [parseAmountToMinorUnits] in amount_parser.dart.
///
/// Catches broadly (not just `FormatException`): both the pattern and the
/// raw text come from user/notification input we don't control, and this
/// runs on the headless-engine dispatch path with no surrounding
/// try/catch — a bad pattern must degrade to "fall back to post time",
/// never crash the capture pipeline.
DateTime? parseDateWithFormat(String raw, String format) {
  try {
    return DateFormat(format).parseStrict(raw.trim());
  } catch (_) {
    return null;
  }
}
