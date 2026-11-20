import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_format.dart';
import '../../../core/widgets/sheet_widgets.dart';
import '../../accounts/data/accounts_repository.dart';
import '../../categories/data/categories_repository.dart';
import '../../settings/data/settings_repository.dart';
import '../data/notification_capture_service.dart';
import '../data/notification_rules_repository.dart';
import '../domain/rule_matcher.dart';
import 'rules_screen.dart';

const _dateDisplayFormat = 'dd/MM/yyyy HH:mm';

/// Settings destination for recovering a notification the listener missed
/// (see docs/features/background-reliability.md for why that can happen):
/// paste the notification's text, check it against every enabled rule
/// exactly like a live notification would be, and — if one matches —
/// insert the transaction the same way capture would have (auto-added or
/// sent to the review queue, per that rule's own setting). See
/// docs/features/notification-capture.md "Manual text entry".
class ManualTextEntryScreen extends ConsumerStatefulWidget {
  const ManualTextEntryScreen({super.key});

  @override
  ConsumerState<ManualTextEntryScreen> createState() => _ManualTextEntryScreenState();
}

class _ManualTextEntryScreenState extends ConsumerState<ManualTextEntryScreen> {
  final _textController = TextEditingController();
  RuleMatch? _match;
  bool _checked = false;
  bool _busy = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _resetResult() {
    if (_checked || _match != null) {
      setState(() {
        _checked = false;
        _match = null;
      });
    }
  }

  Future<void> _check() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    final match = await ref.read(notificationCaptureServiceProvider).matchManualText(text);
    if (!mounted) return;
    setState(() {
      _checked = true;
      _match = match;
    });
  }

  Future<void> _insert() async {
    final match = _match;
    if (match == null) return;
    setState(() => _busy = true);
    final isPendingReview = await ref.read(notificationCaptureServiceProvider).insertManualMatch(match);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _checked = false;
      _match = null;
      _textController.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isPendingReview
              ? 'Added to the review queue via "${match.rule.name}" — confirm it there.'
              : 'Inserted via "${match.rule.name}".',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rulesAsync = ref.watch(notificationRulesProvider);
    final hasEnabledRule = rulesAsync.value?.any((r) => r.isEnabled) ?? true;

    return Scaffold(
      appBar: AppBar(title: const Text('Insert from text')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Missed a notification? Paste its text below — it\'s checked against your '
                'notification rules exactly like a live notification would be, and if one '
                'matches, the transaction is added the same way that rule normally would.',
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),
              const SheetFieldLabel('Notification text'),
              const SizedBox(height: 8),
              SheetFieldBox(
                child: TextField(
                  controller: _textController,
                  maxLines: 6,
                  style: TextStyle(color: colors.textPrimary),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Paste the notification\'s title and/or text here',
                    hintStyle: TextStyle(color: colors.textMuted),
                  ),
                  onChanged: (_) => _resetResult(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(onPressed: _check, child: const Text('Check')),
              ),
              if (!hasEnabledRule) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.expense.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'You have no enabled notification rules yet, so nothing can match.',
                        style: TextStyle(color: colors.expense, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const RulesScreen()),
                        ),
                        child: const Text('Go to Notification rules'),
                      ),
                    ],
                  ),
                ),
              ],
              if (_checked) ...[
                const SizedBox(height: 10),
                _MatchResultBanner(match: _match),
              ],
              if (_match != null) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : _insert,
                    icon: const Icon(Icons.check),
                    label: Text(_busy ? 'Inserting…' : 'Insert transaction'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MatchResultBanner extends ConsumerWidget {
  const _MatchResultBanner({required this.match});

  final RuleMatch? match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final match = this.match;

    if (match == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: colors.expense.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
        child: Text(
          'No rule matched this text.',
          style: TextStyle(color: colors.expense, fontWeight: FontWeight.w600, fontSize: 13),
        ),
      );
    }

    final accounts = ref.watch(activeAccountsProvider).value ?? const [];
    final categories = ref.watch(activeCategoriesProvider).value ?? const [];
    final currency = ref.watch(appSettingsStreamProvider).value?.defaultCurrency ?? 'USD';

    String accountName() {
      for (final a in accounts) {
        if (a.id == match.rule.defaultAccountId) return a.name;
      }
      return 'Account #${match.rule.defaultAccountId}';
    }

    String? categoryName() {
      final id = match.rule.defaultCategoryId;
      if (id == null) return null;
      for (final c in categories) {
        if (c.id == id) return c.name;
      }
      return null;
    }

    final isIncome = match.rule.transactionType == 'income';
    final signColor = isIncome ? colors.income : colors.expense;
    final sign = isIncome ? '+' : '-';
    final category = categoryName();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: colors.income.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Matched "${match.rule.name}"',
            style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            '$sign${formatMinorUnits(match.amountMinorUnits, currency)} · ${accountName()}${category != null ? ' · $category' : ''}',
            style: TextStyle(color: signColor, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text('Note: ${match.note}', style: TextStyle(color: colors.textSecondary, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            match.date != null
                ? 'Date: ${DateFormat(_dateDisplayFormat).format(match.date!)}'
                : 'Date: right now — this message had no date for the rule to capture.',
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            match.rule.autoAdd
                ? 'Will be inserted directly, same as this rule\'s other matches.'
                : 'Will go to the review queue, same as this rule\'s other matches.',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
