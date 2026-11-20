import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which transaction type the dashboard's category breakdown chart shows —
/// 'expense' or 'income', same string convention as Transactions.type.
final categoryBreakdownTypeProvider = StateProvider<String>((ref) => 'expense');
