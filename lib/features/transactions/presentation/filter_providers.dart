import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Multi-select category/account filters, shared between the Transactions
/// tab and the Reports tab (added 2026-11-18 per user request) — an empty
/// set means "no filter" (every category/account), matching the existing
/// convention elsewhere in this app (e.g. `match_any_app`'s absence meaning
/// "all"). Not persisted: resets to "all" on app restart, same lifetime as
/// the period-filter providers in period_providers.dart.
final selectedCategoryIdsProvider = StateProvider<Set<int>>((ref) => const {});
final selectedAccountIdsProvider = StateProvider<Set<int>>((ref) => const {});

final hasActiveTransactionFilterProvider = Provider<bool>((ref) {
  return ref.watch(selectedCategoryIdsProvider).isNotEmpty || ref.watch(selectedAccountIdsProvider).isNotEmpty;
});
