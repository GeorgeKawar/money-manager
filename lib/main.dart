import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
// Not called from here — the native side invokes it by name to start a
// headless engine (see docs/architecture.md "Notification capture — how
// the app gets invoked", path 2). Only needs to be reachable from this
// compilation unit so `@pragma('vm:entry-point')` keeps it in the build.
// ignore: unused_import
import 'platform/notification_listener/notification_capture_entrypoint.dart';

void main() {
  runApp(const ProviderScope(child: MoneyManagerApp()));
}
