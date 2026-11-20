import 'package:flutter/material.dart';

/// The single source of truth for MoneyManager's color palette.
///
/// To re-theme the app, edit the values here only — nothing else in the
/// codebase should contain a literal color. [AppPalette.light] and
/// [AppPalette.dark] are consumed by `app_theme.dart` to build the two
/// [ThemeData]s, and every widget reads colors via the `AppColors` theme
/// extension (see `app_colors.dart`), never from this file directly.
class AppPalette {
  const AppPalette._();

  // Brand accent — the mint green used for the balance card, primary
  // button, income figures, and selected segment control option.
  static const Color accent = Color(0xFF8FE3B3);
  static const Color accentDark = Color(0xFF5FBE8C);

  // Semantic status colors.
  static const Color income = Color(0xFF6FD79B);
  static const Color expense = Color(0xFFFF7A59);

  // Dark mode surfaces — near-black with a faint green tint, per the
  // first design mockup.
  static const Color darkBackground = Color(0xFF0C120E);
  static const Color darkSurface = Color(0xFF151F19);
  static const Color darkSurfaceVariant = Color(0xFF1C2821);
  static const Color darkBorder = Color(0xFF263229);
  static const Color darkTextPrimary = Color(0xFFF4F7F5);
  static const Color darkTextSecondary = Color(0xFFA9B6AE);
  static const Color darkTextMuted = Color(0xFF6E7A73);
  static const Color darkOnAccent = Color(0xFF0C120E);

  // Light mode surfaces — derived from the same semantic roles so the
  // two modes stay visually consistent.
  static const Color lightBackground = Color(0xFFF6FAF7);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceVariant = Color(0xFFEAF2EC);
  static const Color lightBorder = Color(0xFFDCE6DF);
  static const Color lightTextPrimary = Color(0xFF13201A);
  static const Color lightTextSecondary = Color(0xFF4C5A52);
  static const Color lightTextMuted = Color(0xFF879087);
  static const Color lightOnAccent = Color(0xFF0C120E);

  // Light-mode-tuned status colors (darker for contrast on white).
  static const Color incomeOnLight = Color(0xFF2E9A5E);
  static const Color expenseOnLight = Color(0xFFD9502F);
  static const Color accentOnLight = Color(0xFF4FAE7B);
}
