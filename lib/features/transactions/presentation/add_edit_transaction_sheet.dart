import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/sheet_widgets.dart';
import '../../accounts/data/accounts_repository.dart';
import '../../categories/data/categories_repository.dart';
import '../../settings/data/settings_repository.dart';
import '../data/transactions_repository.dart';

const _dateDisplayFormat = 'dd/MM/yyyy HH:mm';

/// Opens the add/edit transaction sheet. Pass [existing] to edit (and
/// allow deleting) a transaction; omit it to create a new one. Pass
/// [confirmOnSave] (from the Review queue's "Edit" action — see
/// docs/features/notification-capture.md "Review queue") to also clear
/// `is_pending_review` when the edit is saved.
Future<void> showAddEditTransactionSheet(
  BuildContext context, {
  Transaction? existing,
  bool confirmOnSave = false,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddEditTransactionSheet(existing: existing, confirmOnSave: confirmOnSave),
  );
}

class _AddEditTransactionSheet extends ConsumerStatefulWidget {
  const _AddEditTransactionSheet({this.existing, this.confirmOnSave = false});

  final Transaction? existing;
  final bool confirmOnSave;

  @override
  ConsumerState<_AddEditTransactionSheet> createState() => _AddEditTransactionSheetState();
}

class _AddEditTransactionSheetState extends ConsumerState<_AddEditTransactionSheet> {
  late String _type;
  final _amountController = TextEditingController();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  late DateTime _selectedDate;
  int? _accountId;
  int? _categoryId;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _type = existing?.type ?? 'expense';
    _accountId = existing?.accountId;
    _categoryId = existing?.categoryId;
    _selectedDate = existing?.date ?? DateTime.now();
    if (existing != null) {
      final decimalDigits = NumberFormat.currency(name: existing.currency).decimalDigits ?? 2;
      _amountController.text =
          (existing.amountMinorUnits / 1000).toStringAsFixed(decimalDigits);
      _nameController.text = existing.note ?? '';
      _descriptionController.text = existing.description ?? '';
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String get _namePlaceholder => _type == 'income' ? 'e.g. Monthly salary' : 'e.g. Groceries';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accountsAsync = ref.watch(activeAccountsProvider);
    final categoriesAsync = ref.watch(activeCategoriesProvider);
    final settingsAsync = ref.watch(appSettingsStreamProvider);
    final currency = settingsAsync.value?.defaultCurrency ?? 'USD';

    final accounts = accountsAsync.value;
    if (_accountId == null && accounts != null && accounts.isNotEmpty) {
      _accountId = ref.read(defaultAccountProvider)?.id ?? accounts.first.id;
    }

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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isEditing ? 'Edit transaction' : 'New transaction',
                          style: TextStyle(color: colors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Keep your cash flow up to date.',
                          style: TextStyle(color: colors.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  SheetCloseButton(onTap: () => Navigator.of(context).pop()),
                ],
              ),
              const SizedBox(height: 20),
              SheetTypeToggle(
                type: _type,
                onChanged: (t) => setState(() => _type = t),
              ),
              const SizedBox(height: 20),
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
              const SheetFieldLabel('Name'),
              const SizedBox(height: 8),
              SheetFieldBox(
                child: TextField(
                  controller: _nameController,
                  style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: _namePlaceholder,
                    hintStyle: TextStyle(color: colors.textMuted, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const SheetFieldLabel('Description (optional)'),
              const SizedBox(height: 8),
              SheetFieldBox(
                child: TextField(
                  controller: _descriptionController,
                  style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w500),
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Extra detail, e.g. what this was for',
                    hintStyle: TextStyle(color: colors.textMuted, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const SheetFieldLabel('Account'),
              const SizedBox(height: 8),
              accountsAsync.when(
                data: (accounts) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: accounts
                      .map((a) => SheetChip(
                            label: a.name,
                            selected: a.id == _accountId,
                            onTap: () => setState(() => _accountId = a.id),
                          ))
                      .toList(),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Could not load accounts: $e'),
              ),
              const SizedBox(height: 16),
              const SheetFieldLabel('Category'),
              const SizedBox(height: 8),
              categoriesAsync.when(
                data: (categories) {
                  final filtered = categories
                      .where((c) => c.type == _type || c.type == 'both')
                      .toList();
                  if (_categoryId == null || !filtered.any((c) => c.id == _categoryId)) {
                    _categoryId = filtered.isNotEmpty ? filtered.first.id : null;
                  }
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: filtered
                        .map((c) => SheetChip(
                              label: c.name,
                              selected: c.id == _categoryId,
                              onTap: () => setState(() => _categoryId = c.id),
                            ))
                        .toList(),
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Could not load categories: $e'),
              ),
              const SizedBox(height: 16),
              const SheetFieldLabel('Date & time'),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickDateTime,
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
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _save(currency),
                  icon: const Icon(Icons.check),
                  label: Text(_isEditing ? 'Save changes' : 'Save transaction'),
                ),
              ),
              if (_isEditing) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _delete,
                    child: Text('Delete', style: TextStyle(color: colors.expense)),
                  ),
                ),
              ],
            ],
          ),
        ),
        ),
      ),
    );
  }

  Future<void> _pickDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 10),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDate),
    );
    if (pickedTime == null) return;

    setState(() {
      _selectedDate = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
        _selectedDate.second,
      );
    });
  }

  Future<void> _save(String currency) async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0 || _accountId == null) return;
    if (_nameController.text.trim().isEmpty) return;

    final amountMinorUnits = (amount * 1000).round();
    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();
    final repo = ref.read(transactionsRepositoryProvider);

    if (_isEditing) {
      await repo.updateTransaction(
        widget.existing!.id,
        accountId: _accountId,
        categoryId: _categoryId,
        type: _type,
        amountMinorUnits: amountMinorUnits,
        date: _selectedDate,
        note: name,
        description: description.isEmpty ? null : description,
        isPendingReview: widget.confirmOnSave ? false : null,
      );
    } else {
      await repo.addTransaction(
        accountId: _accountId!,
        categoryId: _categoryId,
        type: _type,
        amountMinorUnits: amountMinorUnits,
        currency: currency,
        date: _selectedDate,
        note: name,
        description: description.isEmpty ? null : description,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    await ref.read(transactionsRepositoryProvider).deleteTransaction(widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }
}

