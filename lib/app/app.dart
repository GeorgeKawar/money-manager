import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../features/notification_capture/data/notification_capture_service.dart';
import '../features/recurring/data/recurring_repository.dart';
import '../platform/notification_listener/notification_listener_channel.dart';
import 'main_screen.dart';
import 'theme_mode_provider.dart';

class MoneyManagerApp extends ConsumerStatefulWidget {
  const MoneyManagerApp({super.key});

  @override
  ConsumerState<MoneyManagerApp> createState() => _MoneyManagerAppState();
}

class _MoneyManagerAppState extends ConsumerState<MoneyManagerApp> {
  StreamSubscription<CapturedNotification>? _notificationSubscription;

  @override
  void initState() {
    super.initState();
    // Lazy, on-open generation of due recurring transactions — see
    // docs/features/recurring-transactions.md "Generation behavior". Fired
    // once per app start; Drift's live `.watch()` streams pick up any rows
    // it inserts without anything else needing to react to it.
    Future.microtask(() => ref.read(recurringRepositoryProvider).generateDueTransactions());

    // Live notification capture while this engine is running — see
    // docs/architecture.md "Notification capture — how the app gets
    // invoked", path 1. When the app is fully closed, a headless engine
    // calls the same NotificationCaptureService directly instead (see
    // notification_capture_entrypoint.dart).
    _notificationSubscription = notificationListenerChannel.notificationStream().listen(
          (notification) async {
            try {
              final redacted = await ref.read(notificationCaptureServiceProvider).handle(notification);
              if (redacted && mounted) {
                ref.read(notificationRedactionDetectedProvider.notifier).state = true;
              }
            } catch (_) {
              // Guards against one bad notification (e.g. a DB error)
              // silently killing future live capture for the rest of the
              // engine's lifetime — this callback's errors aren't seen by
              // the listen() onError below, which only covers the stream
              // itself.
            }
          },
          // No platform-channel implementation in widget tests (and this
          // must never crash the app if the channel hiccups) — swallow.
          onError: (_) {},
        );
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'Money Manager',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: const MainScreen(),
    );
  }
}
