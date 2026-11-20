import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Shared building blocks for the app's bottom-sheet forms (add/edit
/// transaction, account, category) — keeps their boxed-field look
/// consistent without re-declaring the same styling in each sheet.

/// Circular close ("×") button used in a sheet's header row.
class SheetCloseButton extends StatelessWidget {
  const SheetCloseButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: colors.accent, shape: BoxShape.circle),
        child: Icon(Icons.close, color: colors.onAccent, size: 20),
      ),
    );
  }
}

/// Bold label above a [SheetFieldBox].
class SheetFieldLabel extends StatelessWidget {
  const SheetFieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
    );
  }
}

/// The rounded, filled container every sheet form field sits in.
class SheetFieldBox extends StatelessWidget {
  const SheetFieldBox({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

/// The Expense/Income segmented toggle used by the transaction and
/// category sheets. The whole control sits on `surfaceVariant`; the
/// selected segment gets a `surface` highlight behind colored text.
class SheetTypeToggle extends StatelessWidget {
  const SheetTypeToggle({super.key, required this.type, required this.onChanged});

  final String type;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: colors.surfaceVariant, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Expanded(child: _segment(context, 'expense', 'Expense', colors.expense)),
          Expanded(child: _segment(context, 'income', 'Income', colors.income)),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, String value, String label, Color activeColor) {
    final colors = context.colors;
    final isSelected = type == value;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? colors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? activeColor : colors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// A selectable pill chip (category chips, etc.) — accent-highlighted when
/// selected, flat `surfaceVariant` otherwise.
class SheetChip extends StatelessWidget {
  const SheetChip({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? colors.accent.withValues(alpha: 0.15) : colors.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? colors.accent : Colors.transparent, width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? colors.accent : colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
