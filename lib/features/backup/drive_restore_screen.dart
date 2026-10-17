import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/ui.dart';
import 'backup_service.dart';
import 'drive_gateway.dart';

/// Shown when Drive is connected and a backup already exists.
/// Nothing uploads until the user chooses.
class DriveRestoreScreen extends ConsumerStatefulWidget {
  const DriveRestoreScreen({super.key, required this.remote});
  final RemoteBackupInfo remote;

  @override
  ConsumerState<DriveRestoreScreen> createState() => _DriveRestoreScreenState();
}

class _DriveRestoreScreenState extends ConsumerState<DriveRestoreScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action, String doneMessage) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      showSnack(context, doneMessage);
      Navigator.pop(context, true);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e is BackupException ? e.message : 'Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final ok = await confirm(
      context,
      title: 'Restore this backup?',
      message: 'All workout and food data on this phone is replaced by the backup.',
      confirmLabel: 'Restore',
      destructive: true,
    );
    if (!ok) return;
    await _run(() => ref.read(backupServiceProvider).restore(widget.remote), 'Backup restored');
  }

  Future<void> _startFresh() async {
    final ok = await confirm(
      context,
      title: 'Start fresh?',
      message: 'The backup on your Drive will be replaced by the data on this phone. '
          'The current backup is kept as the previous backup.',
      confirmLabel: 'Start fresh',
      destructive: true,
    );
    if (!ok) return;
    await _run(() => ref.read(backupServiceProvider).startFresh(), 'Google Drive connected');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modified = widget.remote.modifiedTime;
    return Scaffold(
      appBar: AppBar(title: const Text('Google Drive')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Backup found on your Drive',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  if (modified != null) HintText('Last backup: ${formatDateTime(modified)}'),
                  const HintText('Previous backup is kept'),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _restore,
                    child: const Text('Restore (recommended)'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _busy ? null : _startFresh,
                    child: const Text('Start fresh'),
                  ),
                  const SizedBox(height: 16),
                  if (_busy) const Center(child: CircularProgressIndicator()),
                  if (_error != null)
                    Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
                  const SizedBox(height: 8),
                  const HintText('Nothing is uploaded until you choose'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
