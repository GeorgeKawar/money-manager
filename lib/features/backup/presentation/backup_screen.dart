import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../notification_capture/data/rules_backup_repository.dart';
import '../../settings/presentation/widgets/settings_row.dart';
import '../data/backup_repository.dart';

/// Single screen consolidating every backup/restore action, reachable from
/// the Settings drawer's "Backup" row — see
/// docs/features/data-import-export.md and
/// docs/features/rules-import-export.md. Two lists: the full database
/// (which already includes notification rules, since it's a full dump) and
/// notification rules on their own, for users who only want to back those
/// up.
class BackupScreen extends StatelessWidget {
  const BackupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Backup'),
        backgroundColor: colors.background,
        foregroundColor: colors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('All data', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 4),
            Text(
              'Your full database — accounts, categories, transactions, recurring transactions, and notification rules, all in one file.',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            const _AllDataBackupSection(),
            const SizedBox(height: 28),
            Text('Notification rules only', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 4),
            Text(
              'Just your notification-capture rules — for backing those up, or moving them to another device, without touching anything else.',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            const _RulesOnlyBackupSection(),
          ],
        ),
      ),
    );
  }
}

class _AllDataBackupSection extends ConsumerStatefulWidget {
  const _AllDataBackupSection();

  @override
  ConsumerState<_AllDataBackupSection> createState() => _AllDataBackupSectionState();
}

class _AllDataBackupSectionState extends ConsumerState<_AllDataBackupSection> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SettingsRow(
          icon: Icons.upload_outlined,
          label: 'Export data',
          trailing: _busy ? const BusyIndicator() : null,
          onTap: _busy ? null : _export,
        ),
        const SizedBox(height: 12),
        SettingsRow(
          icon: Icons.download_outlined,
          label: 'Import data',
          trailing: _busy ? const BusyIndicator() : null,
          onTap: _busy ? null : _import,
        ),
      ],
    );
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final json = await ref.read(backupRepositoryProvider).exportToJson();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save MoneyManager export',
        fileName: 'money_manager_export_$timestamp.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(utf8.encode(json)),
      );
      if (savedPath != null) {
        messenger.showSnackBar(const SnackBar(content: Text('Export saved.')));
      }
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Export failed. Please try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    final bytes = picked?.files.single.bytes;
    if (bytes == null) return; // User cancelled the picker.
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(backupRepositoryProvider);
    final ImportPreview preview;
    try {
      preview = repo.parseImport(utf8.decode(bytes));
    } on BackupFormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }

    if (!mounted) return;
    final confirmed = await _confirmImport(preview);
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await repo.applyImport(preview);
      messenger.showSnackBar(const SnackBar(content: Text('Import complete.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Import failed. Please try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmImport(ImportPreview preview) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Replace all data?'),
        content: Text(
          'This file was exported ${DateFormat.yMMMd().add_jm().format(preview.exportedAt)} and contains '
          '${preview.accounts.length} accounts, ${preview.categories.length} categories, and '
          '${preview.transactions.length} transactions.\n\n'
          'Importing replaces everything currently on this device. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Replace')),
        ],
      ),
    );
  }
}

class _RulesOnlyBackupSection extends ConsumerStatefulWidget {
  const _RulesOnlyBackupSection();

  @override
  ConsumerState<_RulesOnlyBackupSection> createState() => _RulesOnlyBackupSectionState();
}

class _RulesOnlyBackupSectionState extends ConsumerState<_RulesOnlyBackupSection> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SettingsRow(
          icon: Icons.upload_file_outlined,
          label: 'Export rules',
          trailing: _busy ? const BusyIndicator() : null,
          onTap: _busy ? null : _export,
        ),
        const SizedBox(height: 12),
        SettingsRow(
          icon: Icons.file_download_outlined,
          label: 'Import rules',
          trailing: _busy ? const BusyIndicator() : null,
          onTap: _busy ? null : _import,
        ),
      ],
    );
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final json = await ref.read(rulesBackupRepositoryProvider).exportToJson();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save MoneyManager rules export',
        fileName: 'money_manager_rules_$timestamp.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(utf8.encode(json)),
      );
      if (savedPath != null) {
        messenger.showSnackBar(const SnackBar(content: Text('Rules export saved.')));
      }
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Export failed. Please try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    final bytes = picked?.files.single.bytes;
    if (bytes == null) return; // User cancelled the picker.
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(rulesBackupRepositoryProvider);
    final RulesImportPreview preview;
    try {
      preview = await repo.parseImport(utf8.decode(bytes));
    } on RulesBackupFormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }

    if (!mounted) return;
    final confirmed = await _confirmImport(preview);
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await repo.applyImport(preview);
      messenger.showSnackBar(SnackBar(content: Text('Imported ${preview.importable.length} rule(s).')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Import failed. Please try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmImport(RulesImportPreview preview) {
    final lines = <String>[
      'This file was exported ${DateFormat.yMMMd().add_jm().format(preview.exportedAt)}.',
      '',
      '${preview.importable.length} rule(s) will be added.',
    ];
    if (preview.duplicates.isNotEmpty) {
      lines.add('${preview.duplicates.length} already exist here and will be skipped.');
    }
    if (preview.unresolvable.isNotEmpty) {
      lines.add(
        '${preview.unresolvable.length} rule(s) reference an account or category that doesn\'t exist here '
        '(${preview.missingNames.join(', ')}) and will be skipped.',
      );
    }
    if (preview.importable.isEmpty) {
      lines.add('');
      lines.add('Nothing to import.');
    }

    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import rules?'),
        content: Text(lines.join('\n')),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: preview.importable.isEmpty ? null : () => Navigator.of(dialogContext).pop(true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }
}
