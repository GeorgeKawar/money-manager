import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../backup/presentation/backup_screen.dart';
import '../../categories/presentation/categories_screen.dart';
import '../../notification_capture/data/review_queue_repository.dart';
import '../../notification_capture/presentation/manual_text_entry_screen.dart';
import '../../notification_capture/presentation/review_queue_screen.dart';
import '../../notification_capture/presentation/rules_screen.dart';
import '../../recurring/presentation/recurring_screen.dart';
import '../data/settings_repository.dart';
import 'widgets/settings_row.dart';

/// The app's Settings UI, shown as a left-edge slide-in drawer on the
/// Dashboard (see docs/features/settings-drawer.md) — `Drawer` already
/// gives the edge-swipe-to-open gesture for free, so the dashboard just
/// passes this to `Scaffold.drawer`. The gear icon opens it the same way,
/// via `Scaffold.of(context).openDrawer()`.
class SettingsDrawer extends ConsumerWidget {
  const SettingsDrawer({super.key});

  void _navigate(BuildContext context, Widget screen) {
    Navigator.of(context).pop(); // close the drawer first
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final pendingCount = ref.watch(reviewQueueProvider).value?.length ?? 0;

    return Drawer(
      backgroundColor: colors.background,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Settings', style: TextStyle(color: colors.textPrimary, fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 20),
            SettingsRow(
              icon: Icons.category_outlined,
              label: 'Categories',
              onTap: () => _navigate(context, const CategoriesScreen()),
            ),
            const SizedBox(height: 12),
            SettingsRow(
              icon: Icons.autorenew,
              label: 'Recurring',
              onTap: () => _navigate(context, const RecurringScreen()),
            ),
            const SizedBox(height: 12),
            SettingsRow(
              icon: Icons.rule_outlined,
              label: 'Notification rules',
              onTap: () => _navigate(context, const RulesScreen()),
            ),
            const SizedBox(height: 12),
            SettingsRow(
              icon: Icons.keyboard_outlined,
              label: 'Insert from text',
              onTap: () => _navigate(context, const ManualTextEntryScreen()),
            ),
            const SizedBox(height: 12),
            SettingsRow(
              icon: Icons.inbox_outlined,
              label: 'Review queue',
              badgeCount: pendingCount,
              onTap: () => _navigate(context, const ReviewQueueScreen()),
            ),
            const SizedBox(height: 12),
            SettingsRow(
              icon: Icons.backup_outlined,
              label: 'Backup',
              onTap: () => _navigate(context, const BackupScreen()),
            ),
            const SizedBox(height: 12),
            const _ThemeModeSection(),
          ],
        ),
      ),
    );
  }
}

class _ThemeModeSection extends ConsumerWidget {
  const _ThemeModeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final current = ref.watch(appSettingsStreamProvider).value?.themeMode ?? 'system';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.dark_mode_outlined, color: colors.textSecondary),
              const SizedBox(width: 14),
              Text('Appearance', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: colors.surfaceVariant, borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                _ThemeOption(
                  label: 'System',
                  value: 'system',
                  groupValue: current,
                  onSelect: (v) => ref.read(settingsRepositoryProvider).setThemeMode(v),
                ),
                _ThemeOption(
                  label: 'Light',
                  value: 'light',
                  groupValue: current,
                  onSelect: (v) => ref.read(settingsRepositoryProvider).setThemeMode(v),
                ),
                _ThemeOption(
                  label: 'Dark',
                  value: 'dark',
                  groupValue: current,
                  onSelect: (v) => ref.read(settingsRepositoryProvider).setThemeMode(v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({required this.label, required this.value, required this.groupValue, required this.onSelect});

  final String label;
  final String value;
  final String groupValue;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isSelected = value == groupValue;
    return Expanded(
      child: GestureDetector(
        onTap: () => onSelect(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? colors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? colors.textPrimary : colors.textSecondary,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

