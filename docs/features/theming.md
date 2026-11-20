# Feature: Dark/light mode toggle

## Status

Done. Implemented as Phase 7, after Phase 6 (settings drawer), exactly as scoped below — the underlying infrastructure already existed, so this was a small phase.

## Decided

- **Control widget**: a three-way segmented control (System / Light / Dark) inside a new "Appearance" card in the Settings drawer, styled identically to `PeriodSegmentedControl` (pill container on `surfaceVariant`, selected segment highlighted with a `surface` pill) rather than a bottom sheet — keeps it a single always-visible tap, consistent with the drawer's other at-a-glance rows. See `_ThemeModeSection`/`_ThemeOption` in [`settings_drawer.dart`](../../lib/features/settings/presentation/settings_drawer.dart). Selecting an option calls `settingsRepository.setThemeMode()` directly — no new provider or data-model work needed, as expected.
- **On-device dark-mode pass**: done — dashboard (balance card, cash-flow cards, category donut chart), the add-transaction sheet (fields, category chips, Save button), and the Settings drawer itself (including the dimmed-dashboard scrim behind it) were all checked in dark mode. No contrast or hardcoded-color bugs found; every screen already read colors through `context.colors` as the convention required.

## What already exists

Light/dark theming was built in from early on (per [design.md](../design.md)'s theming section: "Light and dark mode are both required"), just never exposed as a user-facing setting:

- [app_palette.dart](../../lib/core/theme/app_palette.dart) — full light + dark literal color values, the single palette source.
- [app_colors.dart](../../lib/core/theme/app_colors.dart) — `AppColors.light` / `AppColors.dark` semantic token sets, exposed as a `ThemeExtension` (`context.colors`).
- [app_theme.dart](../../lib/core/theme/app_theme.dart) — `AppTheme.light()` / `AppTheme.dark()` build the two `ThemeData`s from those tokens.
- [theme_mode_provider.dart](../../lib/app/theme_mode_provider.dart) — derives Flutter's `ThemeMode` from the persisted `AppSettings.themeMode` (`'system' | 'light' | 'dark'`), defaulting to `ThemeMode.system`.
- [app.dart](../../lib/app/app.dart) — `MaterialApp` already wires `theme` / `darkTheme` / `themeMode` from that provider.
- [settings_repository.dart](../../lib/features/settings/data/settings_repository.dart) — `setThemeMode(String)` already persists a choice to the DB (see `AppSettingsTable.themeMode` in [data-model.md](../data-model.md)).

Every screen already reads colors through `context.colors` (never a hardcoded literal), so both themes should already render correctly wherever that convention was followed — this phase doesn't need to touch screen code for colors, only add the control that changes which theme is active.

## What's missing (the actual Phase 7 work)

Nothing currently lets the user change `AppSettings.themeMode` — it only ever sits at its default (`'system'`). This phase adds exactly that: a row/control in [settings_screen.dart](../../lib/features/settings/presentation/settings_screen.dart) to pick Light / Dark / System, calling `settingsRepository.setThemeMode()` on change.

## Scope

- One new settings control — exact widget (three-way segmented control, radio list, or a bottom sheet like the currency picker) to decide at implementation time, following the visual language already used elsewhere in Settings/sheets (`SheetTypeToggle`/`SheetChip` style).
- No data-model, provider, or theme-token changes needed — wire existing pieces only.
- **The real risk in this phase**: no one has actually looked at the app running in dark mode on-device yet (every on-device verification so far has been in the emulator's default/light mode) — screens built since Phase 1 may have a contrast or hardcoded-color bug that's never been visually caught. Once the toggle exists, do a manual pass over every screen (dashboard incl. the new Phase 4 charts, add/edit sheet, settings rows, review queue, rule editor) in dark mode specifically, not just unit/widget tests.

## Non-goals

- Per-screen theme overrides, scheduled (time-of-day) theme switching, or any mode beyond the three already defined (`system`/`light`/`dark`).
- Re-deriving the palette itself — [app_palette.dart](../../lib/core/theme/app_palette.dart) is considered final until the user asks to re-theme it.
