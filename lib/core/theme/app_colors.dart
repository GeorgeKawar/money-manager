import 'package:flutter/material.dart';

import 'app_palette.dart';

/// Semantic color tokens for the app, exposed as a [ThemeExtension] so
/// every widget reads `Theme.of(context).extension<AppColors>()!` instead
/// of a literal color. Values come from [AppPalette] — this class only
/// defines the *roles* (background, surface, income, expense, ...), never
/// the literal hex values, so the palette can change without touching
/// widget code.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.border,
    required this.accent,
    required this.onAccent,
    required this.income,
    required this.expense,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
  });

  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color border;
  final Color accent;
  final Color onAccent;
  final Color income;
  final Color expense;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  static const AppColors dark = AppColors(
    background: AppPalette.darkBackground,
    surface: AppPalette.darkSurface,
    surfaceVariant: AppPalette.darkSurfaceVariant,
    border: AppPalette.darkBorder,
    accent: AppPalette.accent,
    onAccent: AppPalette.darkOnAccent,
    income: AppPalette.income,
    expense: AppPalette.expense,
    textPrimary: AppPalette.darkTextPrimary,
    textSecondary: AppPalette.darkTextSecondary,
    textMuted: AppPalette.darkTextMuted,
  );

  static const AppColors light = AppColors(
    background: AppPalette.lightBackground,
    surface: AppPalette.lightSurface,
    surfaceVariant: AppPalette.lightSurfaceVariant,
    border: AppPalette.lightBorder,
    accent: AppPalette.accentOnLight,
    onAccent: AppPalette.lightOnAccent,
    income: AppPalette.incomeOnLight,
    expense: AppPalette.expenseOnLight,
    textPrimary: AppPalette.lightTextPrimary,
    textSecondary: AppPalette.lightTextSecondary,
    textMuted: AppPalette.lightTextMuted,
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? border,
    Color? accent,
    Color? onAccent,
    Color? income,
    Color? expense,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      border: border ?? this.border,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      income: income ?? this.income,
      expense: expense ?? this.expense,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      border: Color.lerp(border, other.border, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
    );
  }
}

/// Convenience accessor: `context.colors.income`.
extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
