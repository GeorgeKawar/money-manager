import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/sheet_widgets.dart';
import '../../settings/data/settings_repository.dart';
import '../data/accounts_repository.dart';

/// Opens the add/edit account sheet. Pass [existing] to edit (and allow
/// archiving) an account; omit it to create a new one.
Future<void> showAddEditAccountSheet(BuildContext context, {Account? existing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddEditAccountSheet(existing: existing),
  );
}

class _AddEditAccountSheet extends ConsumerStatefulWidget {
  const _AddEditAccountSheet({this.existing});

  final Account? existing;

  @override
  ConsumerState<_AddEditAccountSheet> createState() => _AddEditAccountSheetState();
}

class _AddEditAccountSheetState extends ConsumerState<_AddEditAccountSheet> {
  final _nameController = TextEditingController();
  final _balanceController = TextEditingController();
  late bool _includeInAllTimeBalance;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _includeInAllTimeBalance = existing?.includeInAllTimeBalance ?? true;
    if (existing != null) {
      _nameController.text = existing.name;
      _balanceController.text = (existing.startingBalanceMinorUnits / 1000).toStringAsFixed(2);
    } else {
      _balanceController.text = '0.00';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
                      _isEditing ? 'Edit account' : 'New account',
                      style: TextStyle(color: colors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                  ),
                  SheetCloseButton(onTap: () => Navigator.of(context).pop()),
                ],
              ),
              const SizedBox(height: 20),
              const SheetFieldLabel('Name'),
              const SizedBox(height: 8),
              SheetFieldBox(
                child: TextField(
                  controller: _nameController,
                  style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'e.g. Bank account',
                    hintStyle: TextStyle(color: colors.textMuted, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const SheetFieldLabel('Starting balance'),
              const SizedBox(height: 8),
              SheetFieldBox(
                child: Row(
                  children: [
                    Text(currency, style: TextStyle(color: colors.textSecondary, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _balanceController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: TextStyle(color: colors.textPrimary, fontSize: 20, fontWeight: FontWeight.w800),
                        decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SheetFieldBox(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Include in all-time balance',
                            style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            'Turn off to exclude just this account from the dashboard\'s all-time balance.',
                            style: TextStyle(color: colors.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _includeInAllTimeBalance,
                      onChanged: (v) => setState(() => _includeInAllTimeBalance = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check),
                  label: Text(_isEditing ? 'Save changes' : 'Save account'),
                ),
              ),
              if (_isEditing) ...[
                if (!widget.existing!.isArchived) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: widget.existing!.isDefault ? _clearDefault : _setDefault,
                      child: Text(widget.existing!.isDefault ? 'Unset as default account' : 'Set as default account'),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: widget.existing!.isArchived ? _unarchive : _archive,
                    child: Text(
                      widget.existing!.isArchived ? 'Unarchive' : 'Archive',
                      style: TextStyle(color: widget.existing!.isArchived ? colors.accent : colors.expense),
                    ),
                  ),
                ),
                // Only offered once nothing references this account — see
                // AccountsRepository.isUnused.
                if (ref.watch(accountIsUnusedProvider(widget.existing!.id)).value ?? false) ...[
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _delete,
                      child: Text('Delete permanently', style: TextStyle(color: colors.expense)),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final balance = double.tryParse(_balanceController.text.trim());
    if (name.isEmpty || balance == null) return;

    final balanceMinorUnits = (balance * 1000).round();
    final repo = ref.read(accountsRepositoryProvider);

    if (_isEditing) {
      await repo.updateAccount(
        widget.existing!.id,
        name: name,
        startingBalanceMinorUnits: balanceMinorUnits,
        includeInAllTimeBalance: _includeInAllTimeBalance,
      );
    } else {
      await repo.addAccount(
        name: name,
        startingBalanceMinorUnits: balanceMinorUnits,
        includeInAllTimeBalance: _includeInAllTimeBalance,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _archive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive account?'),
        content: Text('"${widget.existing!.name}" will be hidden from pickers, but its history stays intact.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Archive')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(accountsRepositoryProvider).archiveAccount(widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _unarchive() async {
    await ref.read(accountsRepositoryProvider).unarchiveAccount(widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _setDefault() async {
    await ref.read(accountsRepositoryProvider).setDefault(widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _clearDefault() async {
    await ref.read(accountsRepositoryProvider).clearDefault(widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete account?'),
        content: Text(
          '"${widget.existing!.name}" has no transactions or recurring/rule references, so it will be removed '
          'completely rather than archived. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(accountsRepositoryProvider).deleteAccount(widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }
}
