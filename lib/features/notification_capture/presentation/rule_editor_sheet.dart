import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/sheet_widgets.dart';
import '../../accounts/data/accounts_repository.dart';
import '../../categories/data/categories_repository.dart';
import '../data/notification_rules_repository.dart';
import '../domain/rule_matcher.dart';

/// Opens the add/edit notification-rule sheet. Pass [existing] to edit
/// (and allow deleting) a rule; omit it to create a new one.
Future<void> showRuleEditorSheet(BuildContext context, {NotificationRule? existing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RuleEditorSheet(existing: existing),
  );
}

class _RuleEditorSheet extends ConsumerStatefulWidget {
  const _RuleEditorSheet({this.existing});

  final NotificationRule? existing;

  @override
  ConsumerState<_RuleEditorSheet> createState() => _RuleEditorSheetState();
}

class _RuleEditorSheetState extends ConsumerState<_RuleEditorSheet> {
  late String _type;
  late bool _autoAdd;
  late bool _matchAnyApp;
  final _nameController = TextEditingController();
  final _packageController = TextEditingController();
  final _regexController = TextEditingController();
  final _amountGroupController = TextEditingController(text: '1');
  final _priorityController = TextEditingController();
  final _dateGroupController = TextEditingController();
  final _dateFormatController = TextEditingController();
  final _noteGroupController = TextEditingController();
  final _nameGroupController = TextEditingController();
  final _sampleTextController = TextEditingController();
  int? _accountId;
  int? _categoryId;
  String? _formError;
  RuleTestResult? _testResult;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _type = existing?.transactionType ?? 'expense';
    _autoAdd = existing?.autoAdd ?? false;
    _matchAnyApp = existing?.matchAnyApp ?? false;
    _accountId = existing?.defaultAccountId;
    _categoryId = existing?.defaultCategoryId;
    _nameController.text = existing?.name ?? '';
    _packageController.text = existing?.appPackage ?? '';
    _regexController.text = existing?.regexPattern ?? '';
    _amountGroupController.text = (existing?.amountGroup ?? 1).toString();
    _priorityController.text = existing?.priority.toString() ?? '';
    _dateGroupController.text = existing?.dateGroup?.toString() ?? '';
    _dateFormatController.text = existing?.dateFormat ?? '';
    _noteGroupController.text = existing?.noteGroup?.toString() ?? '';
    _nameGroupController.text = existing?.nameGroup?.toString() ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _packageController.dispose();
    _regexController.dispose();
    _amountGroupController.dispose();
    _priorityController.dispose();
    _dateGroupController.dispose();
    _dateFormatController.dispose();
    _noteGroupController.dispose();
    _nameGroupController.dispose();
    _sampleTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accountsAsync = ref.watch(activeAccountsProvider);
    final categoriesAsync = ref.watch(activeCategoriesProvider);

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
                    child: Text(
                      _isEditing ? 'Edit rule' : 'New rule',
                      style: TextStyle(color: colors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                  ),
                  SheetCloseButton(onTap: () => Navigator.of(context).pop()),
                ],
              ),
              const SizedBox(height: 20),
              const SheetFieldLabel('Rule name'),
              const SizedBox(height: 8),
              SheetFieldBox(
                child: TextField(
                  controller: _nameController,
                  style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'e.g. Bank X — card payment',
                    hintStyle: TextStyle(color: colors.textMuted, fontWeight: FontWeight.w600),
                  ),
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
                          Text('Any app', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700)),
                          Text(
                            'Evaluate this rule against notifications from every app, not just one.',
                            style: TextStyle(color: colors.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Switch(value: _matchAnyApp, onChanged: (v) => setState(() => _matchAnyApp = v)),
                  ],
                ),
              ),
              if (!_matchAnyApp) ...[
                const SizedBox(height: 16),
                const SheetFieldLabel('App package'),
                const SizedBox(height: 8),
                SheetFieldBox(
                  child: TextField(
                    controller: _packageController,
                    style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'e.g. com.bank.app',
                      hintStyle: TextStyle(color: colors.textMuted, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Find this in the app\'s Play Store URL, or Android Settings → Apps.',
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              SheetTypeToggle(type: _type, onChanged: (t) => setState(() => _type = t)),
              const SizedBox(height: 16),
              const SheetFieldLabel('Regex pattern'),
              const SizedBox(height: 8),
              SheetFieldBox(
                child: TextField(
                  controller: _regexController,
                  style: TextStyle(color: colors.textPrimary, fontFamily: 'monospace'),
                  maxLines: 2,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: r'e.g. debited.*?([\d,]+\.\d{2})',
                    hintStyle: TextStyle(color: colors.textMuted),
                  ),
                  onChanged: (_) => setState(() => _testResult = null),
                ),
              ),
              const SizedBox(height: 16),
              const SheetFieldLabel('Amount capture group'),
              const SizedBox(height: 8),
              SheetFieldBox(
                child: TextField(
                  controller: _amountGroupController,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none),
                  onChanged: (_) => setState(() => _testResult = null),
                ),
              ),
              const SizedBox(height: 16),
              const SheetFieldLabel('Priority'),
              const SizedBox(height: 8),
              SheetFieldBox(
                child: TextField(
                  controller: _priorityController,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Leave blank to run last',
                    hintStyle: TextStyle(color: colors.textMuted, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Rules with lower priority are tried first; the first one that matches wins '
                'and the rest are skipped — reorder rules from the Rules screen.',
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SheetFieldLabel('Date group (optional)'),
                        const SizedBox(height: 8),
                        SheetFieldBox(
                          child: TextField(
                            controller: _dateGroupController,
                            keyboardType: TextInputType.number,
                            style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
                            decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none),
                            onChanged: (_) => setState(() => _testResult = null),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SheetFieldLabel('Date format'),
                        const SizedBox(height: 8),
                        SheetFieldBox(
                          child: TextField(
                            controller: _dateFormatController,
                            style: TextStyle(color: colors.textPrimary, fontFamily: 'monospace'),
                            decoration: InputDecoration(
                              isCollapsed: true,
                              border: InputBorder.none,
                              hintText: 'dd-MMM-yyyy',
                              hintStyle: TextStyle(color: colors.textMuted),
                            ),
                            onChanged: (_) => setState(() => _testResult = null),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'If set, overrides the notification\'s own time with a date parsed from this group.',
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SheetFieldLabel('Name group (optional)'),
                        const SizedBox(height: 8),
                        SheetFieldBox(
                          child: TextField(
                            controller: _nameGroupController,
                            keyboardType: TextInputType.number,
                            style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
                            decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none),
                            onChanged: (_) => setState(() => _testResult = null),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SheetFieldLabel('Note group (optional)'),
                        const SizedBox(height: 8),
                        SheetFieldBox(
                          child: TextField(
                            controller: _noteGroupController,
                            keyboardType: TextInputType.number,
                            style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
                            decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none),
                            onChanged: (_) => setState(() => _testResult = null),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Name group fills the transaction\'s note (falling back to the rule name above if it '
                'doesn\'t match); a note group, if set, is appended after it — so the note is never blank.',
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 20),
              Text('Test this rule', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 8),
              SheetFieldBox(
                child: TextField(
                  controller: _sampleTextController,
                  style: TextStyle(color: colors.textPrimary),
                  maxLines: 3,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Paste a sample notification title + text here',
                    hintStyle: TextStyle(color: colors.textMuted),
                  ),
                  onChanged: (_) => setState(() => _testResult = null),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(onPressed: _runTest, child: const Text('Test')),
              ),
              if (_testResult != null) ...[
                const SizedBox(height: 10),
                _TestResultBanner(result: _testResult!),
              ],
              const SizedBox(height: 16),
              const SheetFieldLabel('Default account'),
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
              const SheetFieldLabel('Default category'),
              const SizedBox(height: 8),
              categoriesAsync.when(
                data: (categories) {
                  final filtered = categories.where((c) => c.type == _type || c.type == 'both').toList();
                  if (_categoryId != null && !filtered.any((c) => c.id == _categoryId)) {
                    _categoryId = null;
                  }
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: filtered
                        .map((c) => SheetChip(
                              label: c.name,
                              selected: c.id == _categoryId,
                              onTap: () => setState(() => _categoryId = c.id == _categoryId ? null : c.id),
                            ))
                        .toList(),
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Could not load categories: $e'),
              ),
              const SizedBox(height: 16),
              SheetFieldBox(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Auto-add', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700)),
                          Text(
                            _autoAdd
                                ? 'Matches post directly as confirmed transactions.'
                                : 'Matches wait in the review queue for confirmation.',
                            style: TextStyle(color: colors.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Switch(value: _autoAdd, onChanged: (v) => setState(() => _autoAdd = v)),
                  ],
                ),
              ),
              if (_formError != null) ...[
                const SizedBox(height: 10),
                Text(_formError!, style: TextStyle(color: colors.expense, fontSize: 12)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check),
                  label: Text(_isEditing ? 'Save changes' : 'Save rule'),
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

  /// Parses an optional integer field: empty text means "not set" (null,
  /// valid), non-empty-but-unparseable is distinguished from that by
  /// returning null too — callers that need to tell the two apart check
  /// the source text's `isEmpty` themselves (see `_save`'s validation).
  int? _parseOptionalInt(String text) => text.isEmpty ? null : int.tryParse(text);

  void _runTest() {
    final amountGroup = int.tryParse(_amountGroupController.text.trim()) ?? 1;
    setState(() {
      _testResult = testRule(
        regexPattern: _regexController.text.trim(),
        amountGroup: amountGroup,
        sampleText: _sampleTextController.text,
        ruleName: _nameController.text.trim(),
        dateGroup: _parseOptionalInt(_dateGroupController.text.trim()),
        dateFormat: _dateFormatController.text.trim().isEmpty ? null : _dateFormatController.text.trim(),
        noteGroup: _parseOptionalInt(_noteGroupController.text.trim()),
        nameGroup: _parseOptionalInt(_nameGroupController.text.trim()),
      );
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final package = _matchAnyApp ? '' : _packageController.text.trim();
    final regex = _regexController.text.trim();
    final amountGroup = int.tryParse(_amountGroupController.text.trim());

    if (name.isEmpty || (!_matchAnyApp && package.isEmpty) || regex.isEmpty || amountGroup == null || amountGroup < 1) {
      setState(() => _formError = 'Fill in a name, app package (or enable Any app), regex pattern, and a valid capture group.');
      return;
    }
    try {
      RegExp(regex);
    } on FormatException {
      setState(() => _formError = 'That regex pattern is not valid.');
      return;
    }
    if (_accountId == null) {
      setState(() => _formError = 'Choose a default account.');
      return;
    }

    final priorityText = _priorityController.text.trim();
    final dateGroupText = _dateGroupController.text.trim();
    final noteGroupText = _noteGroupController.text.trim();
    final nameGroupText = _nameGroupController.text.trim();
    final priority = _parseOptionalInt(priorityText);
    final dateGroup = _parseOptionalInt(dateGroupText);
    final dateFormat = _dateFormatController.text.trim().isEmpty ? null : _dateFormatController.text.trim();
    final noteGroup = _parseOptionalInt(noteGroupText);
    final nameGroup = _parseOptionalInt(nameGroupText);
    if ((priorityText.isNotEmpty && priority == null) ||
        (dateGroupText.isNotEmpty && dateGroup == null) ||
        (noteGroupText.isNotEmpty && noteGroup == null) ||
        (nameGroupText.isNotEmpty && nameGroup == null)) {
      setState(() => _formError = 'Priority and capture groups must be whole numbers, or left blank.');
      return;
    }

    final repo = ref.read(notificationRulesRepositoryProvider);
    if (_isEditing) {
      await repo.updateRule(
        widget.existing!.id,
        name: name,
        appPackage: package,
        matchAnyApp: _matchAnyApp,
        regexPattern: regex,
        amountGroup: amountGroup,
        transactionType: _type,
        defaultCategoryId: _categoryId,
        defaultAccountId: _accountId!,
        autoAdd: _autoAdd,
        priority: priority,
        dateGroup: dateGroup,
        dateFormat: dateFormat,
        noteGroup: noteGroup,
        nameGroup: nameGroup,
      );
    } else {
      await repo.addRule(
        name: name,
        appPackage: package,
        matchAnyApp: _matchAnyApp,
        regexPattern: regex,
        amountGroup: amountGroup,
        transactionType: _type,
        defaultCategoryId: _categoryId,
        defaultAccountId: _accountId!,
        autoAdd: _autoAdd,
        priority: priority,
        dateGroup: dateGroup,
        dateFormat: dateFormat,
        noteGroup: noteGroup,
        nameGroup: nameGroup,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    await ref.read(notificationRulesRepositoryProvider).deleteRule(widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }
}

class _TestResultBanner extends StatelessWidget {
  const _TestResultBanner({required this.result});

  final RuleTestResult result;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final String message;
    final Color color;
    if (result.regexError != null) {
      message = result.regexError!;
      color = colors.expense;
    } else if (!result.matched) {
      message = 'No match against the sample text.';
      color = colors.expense;
    } else if (result.amountMinorUnits == null) {
      message = 'Matched, but captured "${result.rawCapturedGroup}" isn\'t a parseable amount.';
      color = colors.expense;
    } else {
      final amount = (result.amountMinorUnits! / 1000).toStringAsFixed(2);
      final buffer = StringBuffer('Matched — captured "${result.rawCapturedGroup}" → $amount.');
      if (result.resolvedNote != null) {
        buffer.write(' Note: "${result.resolvedNote}".');
      }
      if (result.dateError != null) {
        buffer.write(' ${result.dateError}');
      } else if (result.resolvedDate != null) {
        buffer.write(' Date: ${result.resolvedDate}.');
      }
      message = buffer.toString();
      color = result.dateError != null ? colors.expense : colors.income;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Text(message, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }
}
