import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_format.dart';
import '../../../core/utils/date_period.dart';
import '../../settings/data/settings_repository.dart';
import '../../transfers/data/transfers_repository.dart';
import '../../transfers/presentation/transfer_sheet.dart';
import '../data/accounts_repository.dart';
import 'add_edit_account_sheet.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final accountsAsync = ref.watch(activeAccountsWithBalancesProvider);
    final archivedAsync = ref.watch(archivedAccountsWithBalancesProvider);
    final transfersAsync = ref.watch(recentTransfersProvider);
    final settingsAsync = ref.watch(appSettingsStreamProvider);
    final currency = settingsAsync.value?.defaultCurrency ?? 'USD';
    final includeArchivedInBalance = settingsAsync.value?.includeArchivedInAllTimeBalance ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          IconButton(
            onPressed: () => showTransferSheet(context),
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Transfer',
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  accountsAsync.when(
                    data: (accounts) {
                      if (accounts.isEmpty) {
                        return Center(
                          child: Text('No accounts yet.', style: TextStyle(color: colors.textSecondary)),
                        );
                      }
                      return Column(
                        children: [
                          for (var i = 0; i < accounts.length; i++) ...[
                            if (i != 0) const SizedBox(height: 12),
                            _AccountRow(item: accounts[i], currency: currency),
                          ],
                        ],
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Could not load accounts: $e')),
                  ),
                  const SizedBox(height: 28),
                  Text('Archived accounts', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    "Hidden from pickers, but their history stays. Choose whether they still count toward the "
                    "dashboard's all-time balance as a group below, or tap an account's own \"Include in "
                    "all-time balance\" toggle to decide for just that one.",
                    style: TextStyle(color: colors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  _IncludeArchivedInBalanceToggle(value: includeArchivedInBalance),
                  const SizedBox(height: 12),
                  archivedAsync.when(
                    data: (accounts) {
                      if (accounts.isEmpty) {
                        return Text('No archived accounts.', style: TextStyle(color: colors.textSecondary));
                      }
                      return Column(
                        children: [
                          for (var i = 0; i < accounts.length; i++) ...[
                            if (i != 0) const SizedBox(height: 12),
                            _AccountRow(item: accounts[i], currency: currency),
                          ],
                        ],
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Could not load archived accounts: $e')),
                  ),
                  const SizedBox(height: 28),
                  Text('Recent transfers', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  transfersAsync.when(
                    data: (transfers) {
                      if (transfers.isEmpty) {
                        return Text('No transfers yet.', style: TextStyle(color: colors.textSecondary));
                      }
                      return Container(
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: colors.border),
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < transfers.length; i++) ...[
                              _TransferRow(item: transfers[i]),
                              if (i != transfers.length - 1) Divider(height: 1, color: colors.border),
                            ],
                          ],
                        ),
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Text('Could not load transfers: $e'),
                  ),
                ],
              ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 16,
              child: ElevatedButton.icon(
                onPressed: () => showAddEditAccountSheet(context),
                icon: const Icon(Icons.add),
                label: const Text('Add account'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.item, required this.currency});

  final AccountBalance item;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: () => showAddEditAccountSheet(context, existing: item.account),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: colors.accent.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Icon(Icons.account_balance_wallet_outlined, color: colors.accent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      item.account.name,
                      style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (item.account.isDefault) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Default',
                        style: TextStyle(color: colors.accent, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                  if (!item.account.includeInAllTimeBalance) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colors.textMuted.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Excluded from total',
                        style: TextStyle(color: colors.textMuted, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Text(
              formatMinorUnits(item.balanceMinorUnits, currency),
              style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncludeArchivedInBalanceToggle extends ConsumerWidget {
  const _IncludeArchivedInBalanceToggle({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Include archived accounts in all-time balance',
              style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: (v) => ref.read(settingsRepositoryProvider).setIncludeArchivedInAllTimeBalance(v),
          ),
        ],
      ),
    );
  }
}

class _TransferRow extends ConsumerWidget {
  const _TransferRow({required this.item});

  final TransferListItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return InkWell(
      onTap: () => _confirmDelete(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: colors.accent.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Icon(Icons.swap_horiz, color: colors.accent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item.fromAccountName} → ${item.toAccountName}',
                    style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(relativeDateLabel(item.date), style: TextStyle(color: colors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            Text(
              formatMinorUnits(item.amountMinorUnits, item.currency),
              style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete transfer?'),
        content: Text('This removes both legs of the ${item.fromAccountName} → ${item.toAccountName} transfer.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(transfersRepositoryProvider).deleteTransfer(item.id);
  }
}
