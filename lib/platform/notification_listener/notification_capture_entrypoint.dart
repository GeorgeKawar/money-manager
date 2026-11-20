import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/database/database.dart';
import '../../features/notification_capture/data/notification_capture_service.dart';
import '../../features/notification_capture/data/notification_rules_repository.dart';
import 'notification_listener_channel.dart';

const _headlessChannel = MethodChannel('com.moneymanager.money_manager/notification_headless');

/// Headless-engine Dart entrypoint — see docs/architecture.md "Notification
/// capture — how the app gets invoked", path 2 (app fully closed). The
/// native listener spins up a background `FlutterEngine` pointed at this
/// function, same pattern as `workmanager`/`android_alarm_manager_plus`.
///
/// Handshake with the native side: once the method handler below is
/// registered, this signals `ready` so native knows it's now safe to send
/// the actual notification payload via `process` — sending it any earlier
/// would race Dart isolate startup.
@pragma('vm:entry-point')
void notificationCaptureDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();

  _headlessChannel.setMethodCallHandler((call) async {
    if (call.method != 'process') return null;
    final args = (call.arguments as Map).cast<String, dynamic>();
    final notification = CapturedNotification.fromMap(args);

    final db = AppDatabase();
    try {
      final service = NotificationCaptureService(db, NotificationRulesRepository(db));
      await service.handle(notification);
    } finally {
      await db.close();
    }
    return null;
  });

  _headlessChannel.invokeMethod('ready');
}
