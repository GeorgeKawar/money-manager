import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../platform/notification_listener/notification_listener_channel.dart';
import '../data/notification_capture_service.dart';
import '../data/notification_rules_repository.dart';
import 'rule_editor_sheet.dart';

final _permissionGrantedProvider = FutureProvider.autoDispose<bool>((ref) {
  return notificationListenerChannel.isPermissionGranted();
});

final _batteryOptimizationIgnoredProvider = FutureProvider.autoDispose<bool>((ref) {
  return notificationListenerChannel.isIgnoringBatteryOptimizations();
});

final _listenerDiagnosticsProvider = FutureProvider.autoDispose<ListenerDiagnostics>((ref) {
  return notificationListenerChannel.getListenerDiagnostics();
});

final _manufacturerProvider = FutureProvider.autoDispose<String>((ref) {
  return notificationListenerChannel.getDeviceManufacturer();
});

class RulesScreen extends ConsumerStatefulWidget {
  const RulesScreen({super.key});

  @override
  ConsumerState<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends ConsumerState<RulesScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check after the user returns from Android's notification access
    // settings screen (there's no callback for that — just recheck on
    // resume, same as any permission-settings round trip).
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(_permissionGrantedProvider);
      ref.invalidate(_batteryOptimizationIgnoredProvider);
      ref.invalidate(_listenerDiagnosticsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rulesAsync = ref.watch(notificationRulesProvider);
    final permissionAsync = ref.watch(_permissionGrantedProvider);
    final batteryAsync = ref.watch(_batteryOptimizationIgnoredProvider);
    final diagnosticsAsync = ref.watch(_listenerDiagnosticsProvider);
    final sawRedacted = ref.watch(notificationRedactionDetectedProvider);
    final manufacturer = ref.watch(_manufacturerProvider).value ?? '';
    final isSamsung = manufacturer == 'samsung';

    return Scaffold(
      appBar: AppBar(title: const Text('Notification rules')),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Column(
                children: [
                  if (permissionAsync.value == false || batteryAsync.value == false || sawRedacted || isSamsung)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Column(
                        children: [
                          if (permissionAsync.value == false) ...[
                            _PermissionBanner(
                              onGrant: () => notificationListenerChannel.openNotificationAccessSettings(),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (batteryAsync.value == false) ...[
                            _BatteryBanner(
                              onOpenSettings: () => notificationListenerChannel.openBatteryOptimizationSettings(),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (isSamsung) ...[
                            _SamsungBackgroundBanner(
                              onOpenSettings: () => notificationListenerChannel.openOemBackgroundSettings(),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (sawRedacted) ...[
                            _RedactionBanner(
                              onDismiss: () => ref.read(notificationRedactionDetectedProvider.notifier).state = false,
                            ),
                            const SizedBox(height: 16),
                          ],
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: _ListenerDiagnosticsCard(diagnostics: diagnosticsAsync),
                  ),
                  Expanded(
                    child: rulesAsync.when(
                      data: (rules) {
                        if (rules.isEmpty) {
                          return Center(
                            child: Text(
                              'No notification rules yet.',
                              style: TextStyle(color: colors.textSecondary),
                            ),
                          );
                        }
                        return ReorderableListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                          itemCount: rules.length,
                          onReorder: (oldIndex, newIndex) {
                            if (newIndex > oldIndex) newIndex -= 1;
                            final reordered = List<NotificationRule>.of(rules);
                            final moved = reordered.removeAt(oldIndex);
                            reordered.insert(newIndex, moved);
                            ref.read(notificationRulesRepositoryProvider).reorderRules(
                                  reordered.map((r) => r.id).toList(),
                                );
                          },
                          itemBuilder: (context, index) => Padding(
                            key: ValueKey(rules[index].id),
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _RuleRow(rule: rules[index]),
                          ),
                        );
                      },
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(child: Text('Could not load rules: $e')),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 16,
              child: ElevatedButton.icon(
                onPressed: () => showRuleEditorSheet(context),
                icon: const Icon(Icons.add),
                label: const Text('Add rule'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({required this.onGrant});

  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.expense.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.expense.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications_off_outlined, color: colors.expense),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notification access needed',
                  style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Rules can\'t capture transactions until you grant access in system settings.',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 10),
                ElevatedButton(onPressed: onGrant, child: const Text('Grant access')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// See docs/features/background-reliability.md "Battery-optimization
/// exemption prompt" — shown when the OS isn't exempting this app from
/// Doze/App Standby restrictions, which can stop background capture.
class _BatteryBanner extends StatelessWidget {
  const _BatteryBanner({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.expense.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.expense.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.battery_alert_outlined, color: colors.expense),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Battery optimization may block capture',
                  style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Some phones stop apps running in the background to save battery, which can '
                  'also stop notifications from being captured while this app is closed. '
                  'Exempting it in settings can help.',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
                TextButton(onPressed: onOpenSettings, child: const Text('Open battery settings')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// See docs/features/background-reliability.md "Samsung background usage
/// limits" — a separate One UI-only setting from the standard Android
/// battery-optimization toggle above: Samsung can still classify this app
/// as a "sleeping app" even when it's exempt from standard Doze/App
/// Standby. Shown on every Samsung device (not gated on the standard
/// battery check, since the two settings are independent) because there is
/// no public API to detect the user's current choice there.
class _SamsungBackgroundBanner extends StatelessWidget {
  const _SamsungBackgroundBanner({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.expense.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.expense.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.bedtime_outlined, color: colors.expense),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Samsung may still put this app to sleep',
                  style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Samsung phones have their own background-usage limits, separate from the '
                  'battery setting above. Open Battery > Background usage limits and add '
                  'MoneyManager to "Never sleeping apps" so it keeps receiving notifications '
                  'while closed.',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
                TextButton(onPressed: onOpenSettings, child: const Text('Open battery settings')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// See docs/features/background-reliability.md "In-app diagnostics" — a
/// small always-visible status row, checked on screen view / manual tap
/// only (never polled), so the user can tell whether the listener is
/// actually bound without needing `adb logcat`.
class _ListenerDiagnosticsCard extends ConsumerWidget {
  const _ListenerDiagnosticsCard({required this.diagnostics});

  final AsyncValue<ListenerDiagnostics> diagnostics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final lastConnected = diagnostics.value?.lastConnectedAt;
    final statusText = lastConnected == null
        ? 'Listener: not yet connected this install'
        : 'Listener last connected ${_formatRelative(lastConnected)}';
    final lastOutcome = diagnostics.value?.lastHeadlessOutcome;
    final lastOutcomeAt = diagnostics.value?.lastHeadlessOutcomeAt;
    final outcomeText = (lastOutcome == null || lastOutcomeAt == null)
        ? null
        : 'Last background capture: $lastOutcome ${_formatRelative(lastOutcomeAt)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.sync_outlined, color: colors.textMuted, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(statusText, style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                if (outcomeText != null)
                  Text(outcomeText, style: TextStyle(color: colors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              await notificationListenerChannel.requestRebind();
              ref.invalidate(_listenerDiagnosticsProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Rebind requested')),
                );
              }
            },
            child: const Text('Recheck'),
          ),
        ],
      ),
    );
  }
}

String _formatRelative(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// See docs/features/notification-capture.md "Known limitation: OS-level
/// content redaction" — Android (System Intelligence, Android 15+) can
/// withhold a notification's real text from this listener, so a correctly
/// written rule may still never fire for some notifications. Nothing in the
/// app can fix that; this just tells the user it happened.
class _RedactionBanner extends StatelessWidget {
  const _RedactionBanner({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.visibility_off_outlined, color: colors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Android hid a notification\'s content',
                  style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Android can withhold a notification\'s real text from this app for some '
                  'notifications it treats as sensitive — a correctly written rule can\'t '
                  'match text it never receives. This is a device setting, not a rule problem.',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: colors.textMuted, size: 18),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

class _RuleRow extends ConsumerWidget {
  const _RuleRow({required this.rule});

  final NotificationRule rule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final isIncome = rule.transactionType == 'income';
    final target = rule.matchAnyApp ? 'Any app' : rule.appPackage;

    return InkWell(
      onTap: () => showRuleEditorSheet(context, existing: rule),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.drag_handle, color: colors.textMuted, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          rule.name,
                          style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (rule.isPreset) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colors.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Preset',
                            style: TextStyle(color: colors.accent, fontSize: 10, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$target · ${isIncome ? 'Income' : 'Expense'}'
                    '${rule.autoAdd ? '' : ' · review queue'}',
                    style: TextStyle(color: colors.textMuted, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              value: rule.isEnabled,
              onChanged: (v) => ref.read(notificationRulesRepositoryProvider).setEnabled(rule.id, v),
            ),
          ],
        ),
      ),
    );
  }
}
