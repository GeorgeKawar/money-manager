import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/sheet_widgets.dart';
import '../../accounts/data/accounts_repository.dart';
import '../../settings/data/settings_repository.dart';
import '../data/transfers_repository.dart';

const _dateDisplayFormat = 'dd/MM/yyyy';

/// Opens the transfer sheet: moves money between two of the user's own
/// accounts (see docs/features/categories-accounts.md "Transfers").
Future<void> showTransferSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _TransferSheet(),
  );
}

class _TransferSheet extends ConsumerStatefulWidget {
  const _TransferSheet();

  @override
  ConsumerState<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends ConsumerState<_TransferSheet> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  int? _fromAccountId;
  int? _toAccountId;
  String? _formError;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 10),
    );
    if (picked == null) return;
    setState(() => _selectedDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accountsAsync = ref.watch(activeAccountsProvider);
    final settingsAsync = ref.watch(appSettingsStreamProvider);
    final currency = settingsAsync.value?.defaultCurrency ?? 'USD';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Transfer',
                      style: TextStyle(color: colors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                  ),
                  SheetCloseButton(onTap: () => Navigator.of(context).pop()),
                ],
              ),
              const SizedBox(height: 20),
              accountsAsync.when(
                data: (accounts) => _buildForm(context, accounts, currency),
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('Could not load accounts: $e'),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context, List<Account> accounts, String currency) {
    final colors = context.colors;
    if (accounts.length < 2) {
      return Text(
        'Add a second account first — transfers move money between two of your own accounts.',
        style: TextStyle(color: colors.textSecondary),
      );
    }

    _fromAccountId ??= accounts.first.id;
    if (_toAccountId == null || _toAccountId == _fromAccountId) {
      _toAccountId = accounts.firstWhere((a) => a.id != _fromAccountId).id;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SheetFieldLabel('From'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: accounts
              .map((a) => SheetChip(
                    label: a.name,
                    selected: a.id == _fromAccountId,
                    onTap: () => setState(() => _fromAccountId = a.id),
                  ))
              .toList(),
        ),
        const SizedBox(height: 16),
        const SheetFieldLabel('To'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: accounts
              .where((a) => a.id != _fromAccountId)
              .map((a) => SheetChip(
                    label: a.name,
                    selected: a.id == _toAccountId,
                    onTap: () => setState(() => _toAccountId = a.id),
                  ))
              .toList(),
        ),
        const SizedBox(height: 16),
        const SheetFieldLabel('Amount'),
        const SizedBox(height: 8),
        SheetFieldBox(
          child: Row(
            children: [
              Text(currency, style: TextStyle(color: colors.textSecondary, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: colors.textPrimary, fontSize: 24, fontWeight: FontWeight.w800),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: '0.00',
                    hintStyle: TextStyle(color: colors.textMuted, fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SheetFieldLabel('Note (optional)'),
        const SizedBox(height: 8),
        SheetFieldBox(
          child: TextField(
            controller: _noteController,
            style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: 'e.g. Monthly savings',
              hintStyle: TextStyle(color: colors.textMuted, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const SheetFieldLabel('Date'),
        const SizedBox(height: 8),
        InkWell(
          onTap: _pickDate,
          borderRadius: BorderRadius.circular(16),
          child: SheetFieldBox(
            child: Row(
              children: [
                Icon(Icons.calendar_today_outlined, color: colors.textSecondary, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    DateFormat(_dateDisplayFormat).format(_selectedDate),
                    style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(Icons.keyboard_arrow_down, color: colors.textSecondary, size: 20),
              ],
            ),
          ),
        ),
        if (_formError != null) ...[
          const SizedBox(height: 6),
          Text(_formError!, style: TextStyle(color: colors.expense, fontSize: 12)),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _save(currency),
            icon: const Icon(Icons.check),
            label: const Text('Save transfer'),
          ),
        ),
      ],
    );
  }

  Future<void> _save(String currency) async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _formError = 'Enter an amount greater than 0.');
      return;
    }
    if (_fromAccountId == null || _toAccountId == null || _fromAccountId == _toAccountId) {
      setState(() => _formError = 'Choose two different accounts.');
      return;
    }

    final amountMinorUnits = (amount * 1000).round();
    final note = _noteController.text.trim();
    await ref.read(transfersRepositoryProvider).addTransfer(
          fromAccountId: _fromAccountId!,
          toAccountId: _toAccountId!,
          amountMinorUnits: amountMinorUnits,
          currency: currency,
          date: _selectedDate,
          note: note.isEmpty ? null : note,
        );
    if (mounted) Navigator.of(context).pop();
  }
}
