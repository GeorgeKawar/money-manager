import 'package:flutter/services.dart';

/// A single posted notification forwarded from the native
/// `NotificationListenerService` — see docs/architecture.md "Notification
/// capture — how the app gets invoked".
class CapturedNotification {
  const CapturedNotification({
    required this.package,
    required this.title,
    required this.text,
    required this.postTime,
  });

  factory CapturedNotification.fromMap(Map<dynamic, dynamic> map) {
    return CapturedNotification(
      package: map['package'] as String,
      title: (map['title'] as String?) ?? '',
      text: (map['text'] as String?) ?? '',
      postTime: DateTime.fromMillisecondsSinceEpoch(map['postTime'] as int),
    );
  }

  final String package;
  final String title;
  final String text;
  final DateTime postTime;

  /// See docs/features/notification-capture.md "Matching details": regex
  /// is applied against title + "\n" + text.
  String get combinedText => '$title\n$text';
}

/// Native listener connection history — see docs/features/
/// background-reliability.md "In-app diagnostics". Read on-demand (screen
/// view / manual recheck) from native SharedPreferences, never polled.
class ListenerDiagnostics {
  const ListenerDiagnostics({
    this.lastConnectedAt,
    this.lastDisconnectedAt,
    this.lastHeadlessOutcome,
    this.lastHeadlessOutcomeAt,
  });

  factory ListenerDiagnostics.fromMap(Map<dynamic, dynamic> map) {
    DateTime? toDateTime(Object? value) {
      if (value == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(value as int);
    }

    return ListenerDiagnostics(
      lastConnectedAt: toDateTime(map['lastConnectedAt']),
      lastDisconnectedAt: toDateTime(map['lastDisconnectedAt']),
      lastHeadlessOutcome: map['lastHeadlessOutcome'] as String?,
      lastHeadlessOutcomeAt: toDateTime(map['lastHeadlessOutcomeAt']),
    );
  }

  final DateTime? lastConnectedAt;
  final DateTime? lastDisconnectedAt;

  /// "succeeded" | "failed" | "timedOut" — the outcome of the most recent
  /// headless dispatch, persisted natively exactly when it resolves. See
  /// docs/features/background-reliability.md "Headless dispatch outcome".
  final String? lastHeadlessOutcome;
  final DateTime? lastHeadlessOutcomeAt;
}

/// One installed, launchable app — package name + display label — for the
/// rule editor's app picker. See docs/features/notification-capture.md
/// "Presets + custom rules".
class InstalledApp {
  const InstalledApp({required this.package, required this.label});

  factory InstalledApp.fromMap(Map<dynamic, dynamic> map) {
    return InstalledApp(
      package: map['package'] as String,
      label: (map['label'] as String?) ?? '',
    );
  }

  final String package;
  final String label;
}

/// Dart-side wrapper around the native notification-listener plugin (no
/// package — plain platform channels declared directly in MainActivity.kt,
/// matching the thin-native/logic-in-Dart split in docs/architecture.md).
class NotificationListenerChannel {
  static const _methodChannel = MethodChannel('com.moneymanager.money_manager/notification_listener');
  static const _eventChannel = EventChannel('com.moneymanager.money_manager/notification_listener/events');

  /// Whether the user has granted notification access to this app in
  /// system settings. Cannot be requested via a normal permission dialog.
  Future<bool> isPermissionGranted() async {
    final granted = await _methodChannel.invokeMethod<bool>('isPermissionGranted');
    return granted ?? false;
  }

  /// Deep-links to Android's notification access settings screen so the
  /// user can grant (or review) the permission.
  Future<void> openNotificationAccessSettings() {
    return _methodChannel.invokeMethod('openNotificationAccessSettings');
  }

  /// Pushes the set of app packages that currently have at least one
  /// enabled rule, so the native listener can cheaply ignore everything
  /// else (privacy + performance) before ever forwarding to Dart. Called
  /// by NotificationRulesRepository whenever rules change.
  ///
  /// [matchAnyApp] is true when at least one enabled rule has its
  /// `matchAnyApp` flag set — the native listener then bypasses the
  /// package-allowlist check entirely. See docs/features/
  /// notification-capture.md "Any-app rules".
  Future<void> updateAllowlist(List<String> packages, {required bool matchAnyApp}) {
    return _methodChannel.invokeMethod('updateAllowlist', {
      'packages': packages,
      'matchAnyApp': matchAnyApp,
    });
  }

  /// Whether this app is currently exempt from Android's battery-
  /// optimization restrictions. Checked on-demand only (screen view /
  /// manual recheck) — see docs/features/background-reliability.md;
  /// never polled in the background, since polling itself costs battery.
  Future<bool> isIgnoringBatteryOptimizations() async {
    final ignoring = await _methodChannel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
    return ignoring ?? false;
  }

  /// Deep-links to the OS's own battery-optimization settings list (not
  /// the direct exemption-request dialog) — see background-reliability.md
  /// "Open decisions" for why the safer generic settings page was chosen.
  Future<void> openBatteryOptimizationSettings() {
    return _methodChannel.invokeMethod('openBatteryOptimizationSettings');
  }

  /// Last known listener connect/disconnect times, for the in-app
  /// diagnostics row — see background-reliability.md "In-app diagnostics".
  Future<ListenerDiagnostics> getListenerDiagnostics() async {
    final raw = await _methodChannel.invokeMethod<Map>('getListenerDiagnostics');
    return ListenerDiagnostics.fromMap(raw ?? const {});
  }

  /// Defensively asks the OS to rebind the notification listener — the
  /// same call MainActivity already makes once per launch, exposed here
  /// so the user can trigger it on demand via a "Recheck" button.
  Future<void> requestRebind() {
    return _methodChannel.invokeMethod('requestRebind');
  }

  /// Lowercase `Build.MANUFACTURER` (e.g. `"samsung"`) — used only to decide
  /// whether to show OEM-specific background-usage-limits guidance, never
  /// for anything behavioral beyond that.
  Future<String> getDeviceManufacturer() async {
    final value = await _methodChannel.invokeMethod<String>('getDeviceManufacturer');
    return value ?? '';
  }

  /// Best-effort deep link into the OEM's own background-restriction screen
  /// (currently: Samsung Device Care's battery screen), falling back to the
  /// standard per-app "App info" settings screen if unavailable. See
  /// docs/features/background-reliability.md "Samsung background usage
  /// limits".
  Future<void> openOemBackgroundSettings() {
    return _methodChannel.invokeMethod('openOemBackgroundSettings');
  }

  /// Installed launchable apps, for the rule editor's app picker — see
  /// docs/features/notification-capture.md "Presets + custom rules".
  /// Returns an empty list on any platform-call failure (e.g. a test
  /// environment with no platform channel registered), since manual
  /// package entry remains available as a fallback in the rule editor.
  Future<List<InstalledApp>> getInstalledApps() async {
    try {
      final raw = await _methodChannel.invokeMethod<List<dynamic>>('getInstalledApps');
      return (raw ?? const []).map((e) => InstalledApp.fromMap(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Notifications forwarded live while a Flutter engine is already
  /// running (app open or recently backgrounded). When the app is fully
  /// closed, the native side instead spins up a headless engine that
  /// calls straight into [notificationCaptureDispatcher] — see
  /// notification_capture_entrypoint.dart.
  Stream<CapturedNotification> notificationStream() {
    return _eventChannel.receiveBroadcastStream().map(
          (event) => CapturedNotification.fromMap(event as Map),
        );
  }
}

final notificationListenerChannel = NotificationListenerChannel();
