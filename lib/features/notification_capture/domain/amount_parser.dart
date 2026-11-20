/// Parses a raw captured amount string (e.g. "1,234.56", "$42.00") into
/// integer minor units (scaled 1000x — see Transactions.amountMinorUnits).
///
/// Convention (see docs/features/notification-capture.md "Matching
/// details"): `,` is the thousands separator, `.` is the decimal separator.
/// Everything else (currency symbols, spaces, a leading +/- sign — the
/// transaction's income/expense direction comes from the matching rule, not
/// the notification text) is stripped before parsing. Returns null if the
/// remaining text isn't a valid number.
int? parseAmountToMinorUnits(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[^\d.,]'), '');
  if (cleaned.isEmpty) return null;
  final withoutThousands = cleaned.replaceAll(',', '');
  final value = double.tryParse(withoutThousands);
  if (value == null) return null;
  return (value * 1000).round();
}
