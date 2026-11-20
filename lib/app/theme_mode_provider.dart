import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/data/settings_repository.dart';

/// Derives Flutter's [ThemeMode] from the persisted `themeMode` setting
/// ('system' | 'light' | 'dark'). Defaults to [ThemeMode.system] while the
/// settings row hasn't loaded yet.
final themeModeProvider = Provider<ThemeMode>((ref) {
  final settings = ref.watch(appSettingsStreamProvider);
  return settings.when(
    data: (value) => switch (value.themeMode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    },
    loading: () => ThemeMode.system,
    error: (_, __) => ThemeMode.system,
  );
});
