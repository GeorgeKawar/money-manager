import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Builds the app's light and dark [ThemeData] from the semantic
/// [AppColors] tokens. This is the only place that turns tokens into a
/// Flutter theme — screens should never set colors directly, only read
/// `Theme.of(context)` / `context.colors`.
class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(AppColors.light, Brightness.light);

  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors colors, Brightness brightness) {
    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: colors.background,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: colors.accent,
        onPrimary: colors.onAccent,
        secondary: colors.accent,
        onSecondary: colors.onAccent,
        error: colors.expense,
        onError: colors.onAccent,
        surface: colors.surface,
        onSurface: colors.textPrimary,
      ),
      cardColor: colors.surface,
      dividerColor: colors.border,
      textTheme: _textTheme(colors),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: colors.border),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        indicatorColor: colors.accent.withValues(alpha: 0.18),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? colors.textPrimary : colors.textSecondary,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? colors.accent : colors.textSecondary,
          ),
        ),
      ),
    );

    return base.copyWith(
      extensions: [colors],
    );
  }

  static TextTheme _textTheme(AppColors colors) {
    return TextTheme(
      headlineMedium: TextStyle(
        color: colors.textPrimary,
        fontWeight: FontWeight.w800,
        fontSize: 28,
      ),
      titleLarge: TextStyle(
        color: colors.textPrimary,
        fontWeight: FontWeight.w700,
        fontSize: 20,
      ),
      titleMedium: TextStyle(
        color: colors.textPrimary,
        fontWeight: FontWeight.w700,
        fontSize: 16,
      ),
      bodyLarge: TextStyle(color: colors.textPrimary, fontSize: 16),
      bodyMedium: TextStyle(color: colors.textSecondary, fontSize: 14),
      labelSmall: TextStyle(
        color: colors.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }
}
