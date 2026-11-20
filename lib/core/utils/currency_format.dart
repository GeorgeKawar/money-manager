import 'package:intl/intl.dart';

/// Formats an integer amount stored at the app's fixed 1000x ("minor
/// units") scale into a currency string using that currency's own ISO 4217
/// decimal precision, e.g. `formatMinorUnits(0, 'SAR')` -> "SAR 0.00",
/// `formatMinorUnits(0, 'JPY')` -> "JPY 0", `formatMinorUnits(0, 'KWD')` ->
/// "KWD 0.000".
///
/// Storage always uses 1000x regardless of the currency (see
/// Transactions.amountMinorUnits) — `NumberFormat.currency` with no
/// explicit `decimalDigits` infers the correct number of decimals (0, 2, or
/// 3) per ISO 4217 currency code, so dividing by 1000 and letting it round
/// handles every currency losslessly from one storage scale.
String formatMinorUnits(int minorUnits, String currencyCode) {
  final format = NumberFormat.currency(
    name: currencyCode,
    symbol: '$currencyCode ',
  );
  return format.format(minorUnits / 1000);
}
