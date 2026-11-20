import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Shared row style for the Settings drawer and the screens it navigates to
/// (e.g. the Backup screen) — icon, label, optional badge count, and an
/// optional trailing widget (e.g. a busy spinner) in place of the default
/// chevron. See docs/features/settings-drawer.md.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.badgeCount = 0,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final int badgeCount;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
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
            Icon(icon, color: colors.textSecondary),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 16)),
            ),
            if (badgeCount > 0) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: colors.accent, borderRadius: BorderRadius.circular(10)),
                child: Text(
                  '$badgeCount',
                  style: TextStyle(color: colors.onAccent, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
            ],
            trailing ?? Icon(Icons.chevron_right, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}

class BusyIndicator extends StatelessWidget {
  const BusyIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.textMuted),
    );
  }
}
