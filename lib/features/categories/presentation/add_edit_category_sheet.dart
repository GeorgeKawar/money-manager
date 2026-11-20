import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/category_style.dart';
import '../../../core/widgets/sheet_widgets.dart';
import '../data/categories_repository.dart';

/// Opens the add/edit category sheet. Pass [existing] to rename (and allow
/// archiving) a category; pass [initialType] to pre-select Expense/Income
/// when creating a new one (e.g. whichever tab is active on the list).
Future<void> showAddEditCategorySheet(
  BuildContext context, {
  Category? existing,
  String initialType = 'expense',
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddEditCategorySheet(existing: existing, initialType: initialType),
  );
}

class _AddEditCategorySheet extends ConsumerStatefulWidget {
  const _AddEditCategorySheet({this.existing, required this.initialType});

  final Category? existing;
  final String initialType;

  @override
  ConsumerState<_AddEditCategorySheet> createState() => _AddEditCategorySheetState();
}

class _AddEditCategorySheetState extends ConsumerState<_AddEditCategorySheet> {
  final _nameController = TextEditingController();
  late String _type;
  String? _iconKey;
  int? _colorValue;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _type = widget.existing?.type ?? widget.initialType;
    if (widget.existing != null) {
      _nameController.text = widget.existing!.name;
      _iconKey = widget.existing!.icon;
      _colorValue = widget.existing!.color;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final previewColor = _colorValue != null ? Color(_colorValue!) : categoryStyle(widget.existing).color;
    final previewIcon = categoryIconChoices[_iconKey] ?? categoryStyle(widget.existing).icon;

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
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: previewColor.withValues(alpha: 0.18), shape: BoxShape.circle),
                    child: Icon(previewIcon, color: previewColor, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isEditing ? 'Edit category' : 'New category',
                      style: TextStyle(color: colors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                  ),
                  SheetCloseButton(onTap: () => Navigator.of(context).pop()),
                ],
              ),
              const SizedBox(height: 20),
              if (_isEditing) ...[
                // Type is fixed once a category exists — changing it would
                // reclassify every historical transaction tagged with it.
                SheetFieldLabel(_type == 'income' ? 'Income category' : 'Expense category'),
              ] else ...[
                const SheetFieldLabel('Type'),
                const SizedBox(height: 8),
                SheetTypeToggle(type: _type, onChanged: (t) => setState(() => _type = t)),
              ],
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
                    hintText: 'e.g. Groceries',
                    hintStyle: TextStyle(color: colors.textMuted, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const SheetFieldLabel('Color'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: categoryColorChoices.map((color) {
                  final selected = _colorValue == color.toARGB32();
                  return InkWell(
                    onTap: () => setState(() => _colorValue = color.toARGB32()),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: selected ? colors.textPrimary : Colors.transparent, width: 2),
                      ),
                      child: selected ? Icon(Icons.check, color: colors.onAccent, size: 18) : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const SheetFieldLabel('Icon'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: categoryIconChoices.entries.map((entry) {
                  final selected = _iconKey == entry.key;
                  return InkWell(
                    onTap: () => setState(() => _iconKey = entry.key),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: selected ? colors.accent.withValues(alpha: 0.15) : colors.surfaceVariant,
                        shape: BoxShape.circle,
                        border: Border.all(color: selected ? colors.accent : Colors.transparent, width: 1.5),
                      ),
                      child: Icon(entry.value, color: selected ? colors.accent : colors.textSecondary, size: 18),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check),
                  label: Text(_isEditing ? 'Save changes' : 'Save category'),
                ),
              ),
              if (_isEditing) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _archive,
                    child: Text('Archive', style: TextStyle(color: colors.expense)),
                  ),
                ),
                // Only offered once nothing references this category — see
                // CategoriesRepository.isUnused.
                if (ref.watch(categoryIsUnusedProvider(widget.existing!.id)).value ?? false) ...[
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
    if (name.isEmpty) return;

    final repo = ref.read(categoriesRepositoryProvider);
    if (_isEditing) {
      await repo.updateCategory(widget.existing!.id, name: name, icon: _iconKey, color: _colorValue);
    } else {
      await repo.addCategory(name: name, type: _type, icon: _iconKey, color: _colorValue);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _archive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive category?'),
        content: Text('"${widget.existing!.name}" will be hidden from pickers, but its history stays intact.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Archive')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(categoriesRepositoryProvider).archiveCategory(widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete category?'),
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
    await ref.read(categoriesRepositoryProvider).deleteCategory(widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }
}
