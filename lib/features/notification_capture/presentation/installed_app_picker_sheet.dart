import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/sheet_widgets.dart';
import '../../../platform/notification_listener/notification_listener_channel.dart';

/// Opens a searchable sheet of installed launchable apps; returns the
/// chosen package name, or null if dismissed without a selection. Manual
/// package entry remains available in the rule editor as a fallback — see
/// docs/features/notification-capture.md "Presets + custom rules".
Future<String?> showInstalledAppPickerSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _InstalledAppPickerSheet(),
  );
}

class _InstalledAppPickerSheet extends StatefulWidget {
  const _InstalledAppPickerSheet();

  @override
  State<_InstalledAppPickerSheet> createState() => _InstalledAppPickerSheetState();
}

class _InstalledAppPickerSheetState extends State<_InstalledAppPickerSheet> {
  final _searchController = TextEditingController();
  List<InstalledApp>? _apps;
  String _query = '';

  @override
  void initState() {
    super.initState();
    notificationListenerChannel.getInstalledApps().then((apps) {
      if (mounted) setState(() => _apps = apps);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final apps = _apps;
    final filtered = apps == null
        ? const <InstalledApp>[]
        : apps.where((a) {
            final q = _query.trim().toLowerCase();
            if (q.isEmpty) return true;
            return a.label.toLowerCase().contains(q) || a.package.toLowerCase().contains(q);
          }).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Choose an app',
                      style: TextStyle(color: colors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                  ),
                  SheetCloseButton(onTap: () => Navigator.of(context).pop()),
                ],
              ),
              const SizedBox(height: 16),
              SheetFieldBox(
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Search installed apps',
                    hintStyle: TextStyle(color: colors.textMuted, fontWeight: FontWeight.w600),
                    icon: Icon(Icons.search, color: colors.textMuted, size: 20),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(height: 12),
              if (apps == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (apps.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Could not load installed apps on this device. Type the package name manually instead.',
                    style: TextStyle(color: colors.textMuted),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final app = filtered[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(app.label, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600)),
                        subtitle: Text(app.package, style: TextStyle(color: colors.textMuted, fontSize: 12)),
                        onTap: () => Navigator.of(context).pop(app.package),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
