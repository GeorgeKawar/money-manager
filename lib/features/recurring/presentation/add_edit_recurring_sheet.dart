import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/sheet_widgets.dart';
import '../../accounts/data/accounts_repository.dart';
import '../../categories/data/categories_repository.dart';
import '../data/recurring_repository.dart';

const _dateFormat = 'yyyy-MM-dd';

const _frequencies = [
  ('daily', 'Daily'),
  ('weekly', 'Weekly'),
  ('monthly', 'Monthly'),
  ('yearly', 'Yearly'),
];

/// Opens the add/edit recurring-transaction sheet. Pass [existing] to edit
/// (and allow deleting) a definition; omit it to create a new one.
Future<void> showAddEditRecurringSheet(BuildContext context, {RecurringTransaction? existing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddEditRecurringSheet(existing: existing),
  );
}

class _AddEditRecurringSheet extends ConsumerStatefulWidget {
  const _AddEditRecurringSheet({this.existing});

  final RecurringTransaction? existing;

  @override
  ConsumerState<_AddEditRecurringSheet> createState() => _AddEditRecurringSheetState();
}

class _AddEditRecurringSheetState extends ConsumerState<_AddEditRecurringSheet> {
  late String _type;
  late String _frequency;
  final _amountController = TextEditingController();
  final _nameController = TextEditingController();
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();
  int? _accountId;
  int? _categoryId;
  String? _endDateError;
  String? _formError;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _type = existing?.type ?? 'expense';
    _frequency = existing?.frequency ?? 'monthly';
    _accountId = existing?.accountId;
    _categoryId = existing?.categoryId;
    _startDateController.text = DateFormat(_dateFormat).format(existing?.startDate ?? DateTime.now());
    _endDateController.text = existing?.endDate != null ? DateFormat(_dateFormat).format(existing!.endDate!) : '';
    if (existing != null) {
      _amountController.text = (existing.amountMinorUnits / 1000).toStringAsFixed(2);
      _nameController.text = existing.note ?? '';
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _nameController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accountsAsync = ref.watch(activeAccountsProvider);
    final categoriesAsync = ref.watch(activeCategoriesProvider);

    final accounts = accountsAsync.value;
    if (_accountId == null && accounts != null && accounts.isNotEmpty) {
      _accountId = accounts.first.id;
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
                    child: Text(
                      _isEditing ? 'Edit recurring' : 'New recurring',
                      style: TextStyle(color: colors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                  ),
                  SheetCloseButton(onTap: () => Navigator.of(context).pop()),
                ],
              ),
              const SizedBox(height: 20),
              SheetTypeToggle(type: _type, onChanged: (t) => setState(() => _type = t)),
              const SizedBox(height: 20),
              const SheetFieldLabel('Amount'),
              const SizedBox(height: 8),
              SheetFieldBox(
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
                    hintText: _type == 'income' ? 'e.g. Monthly salary' : 'e.g. Rent',
                    hintStyle: TextStyle(color: colors.textMuted, fontWeight: FontWeight.w600),
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
                  final filtered = categories.where((c) => c.type == _type || c.type == 'both').toList();
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
              const SheetFieldLabel('Frequency'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _frequencies
                    .map((f) => SheetChip(
                          label: f.$2,
                          selected: f.$1 == _frequency,
                          onTap: () => setState(() => _frequency = f.$1),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
              const SheetFieldLabel('Start date'),
              const SizedBox(height: 8),
              SheetFieldBox(
                child: TextField(
                  controller: _startDateController,
                  enabled: !_isEditing,
                  keyboardType: TextInputType.datetime,
                  style: TextStyle(
                    color: _isEditing ? colors.textMuted : colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none),
                ),
              ),
              if (!_isEditing) ...[
                const SizedBox(height: 6),
                Text(
                  'Use year-month-day, for example 2026-11-01. Fixed after creation.',
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              const SheetFieldLabel('End date (optional)'),
              const SizedBox(height: 8),
              SheetFieldBox(
                child: TextField(
                  controller: _endDateController,
                  keyboardType: TextInputType.datetime,
                  style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Leave blank for indefinite',
                    hintStyle: TextStyle(color: colors.textMuted, fontWeight: FontWeight.w600),
                  ),
                  onChanged: (_) {
                    if (_endDateError != null) setState(() => _endDateError = null);
                  },
                ),
              ),
              if (_endDateError != null) ...[
                const SizedBox(height: 6),
                Text(_endDateError!, style: TextStyle(color: colors.expense, fontSize: 12)),
              ],
              if (_formError != null) ...[
                const SizedBox(height: 6),
                Text(_formError!, style: TextStyle(color: colors.expense, fontSize: 12)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check),
                  label: Text(_isEditing ? 'Save changes' : 'Save recurring'),
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

  Future<void> _save() async {
    DateTime? startDate;
    try {
      startDate = DateFormat(_dateFormat).parseStrict(_startDateController.text.trim());
    } on FormatException {
      startDate = null;
    }
    if (startDate == null) {
      // Only reachable in create mode — the field is read-only once editing.
      setState(() => _formError = 'Enter a valid start date as $_dateFormat.');
      return;
    }

    DateTime? endDate;
    final endText = _endDateController.text.trim();
    if (endText.isNotEmpty) {
      try {
        endDate = DateFormat(_dateFormat).parseStrict(endText);
      } on FormatException {
        setState(() => _endDateError = 'Enter a valid date as $_dateFormat, or leave blank.');
        return;
      }
      if (endDate.isBefore(startDate)) {
        setState(() => _endDateError = 'End date must be on or after the start date.');
        return;
      }
    }

    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0 || _accountId == null) {
      setState(() => _formError = 'Enter an amount greater than 0 and choose an account.');
      return;
    }

    final amountMinorUnits = (amount * 1000).round();
    final name = _nameController.text.trim();
    final repo = ref.read(recurringRepositoryProvider);

    if (_isEditing) {
      await repo.updateRecurring(
        widget.existing!.id,
        accountId: _accountId!,
        categoryId: _categoryId,
        type: _type,
        amountMinorUnits: amountMinorUnits,
        note: name.isEmpty ? null : name,
        frequency: _frequency,
        endDate: endDate,
      );
    } else {
      await repo.addRecurring(
        accountId: _accountId!,
        categoryId: _categoryId,
        type: _type,
        amountMinorUnits: amountMinorUnits,
        note: name.isEmpty ? null : name,
        frequency: _frequency,
        startDate: startDate,
        endDate: endDate,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    await ref.read(recurringRepositoryProvider).deleteRecurring(widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }
}
