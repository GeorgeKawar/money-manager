# money_manager

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Running on a physical Android phone

Plug the phone in via USB (with USB debugging enabled in Developer Options), then check it's detected:

```bash
flutter devices
```

**Debug mode** (live-reloading from your terminal, for active development):

```bash
flutter run -d <device-id>
```

**Install permanently** (a real app icon on the phone, survives reboot/unplug, no dev machine needed afterward):

```bash
flutter build apk --release
flutter install -d <device-id>
```

Or do both in one step:

```bash
flutter run --release -d <device-id>
```

After installing, grant "Notification access" to the app under Android Settings — required for the notification-capture feature, and not something `flutter install` does automatically.

## Building an APK to share with others

```bash
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`. Share that file however you like (email, cloud drive, USB, messaging apps) — no Play Store/account needed.

Whoever installs it will need to allow installs from that source once, since it isn't from the Play Store:

1. Open the APK file on their phone.
2. Tap Install — Android will block it with "not allowed to install unknown apps from this source".
3. Tap **Settings**, enable **"Allow from this source"** for the app used to open the file (Files, Chrome, Drive, etc.).
4. Go back and tap Install again.
