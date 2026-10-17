import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/ui.dart';
import '../../data/providers.dart';
import '../backup/backup_service.dart';
import '../backup/drive_gateway.dart';
import '../backup/drive_restore_screen.dart';

/// Drive status in Profile: connect / disconnect, last backup, visible error.
class DriveSection extends ConsumerStatefulWidget {
  const DriveSection({super.key});

  @override
  ConsumerState<DriveSection> createState() => _DriveSectionState();
}

class _DriveSectionState extends ConsumerState<DriveSection> {
  bool _busy = false;

  Future<void> _guarded(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on BackupException catch (e) {
      if (mounted) showSnack(context, e.message);
    } on Object catch (e) {
      if (mounted) showSnack(context, 'Google Drive: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openRestore(RemoteBackupInfo info) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => DriveRestoreScreen(remote: info)),
  );

  Future<void> _connect() => _guarded(() async {
    final outcome = await ref.read(backupServiceProvider).connect();
    if (!mounted) return;
    switch (outcome) {
      case RemoteBackupFound(:final info):
        await _openRestore(info);
      case ConnectedFresh():
        showSnack(context, 'Google Drive connected');
    }
  });

  Future<void> _restoreFromDrive() => _guarded(() async {
    final info = await ref.read(backupServiceProvider).findRemote();
    if (!mounted) return;
    if (info == null) {
      showSnack(context, 'No backup found on your Drive');
    } else {
      await _openRestore(info);
    }
  });

  Future<void> _disconnect() async {
    final ok = await confirm(
      context,
      title: 'Disconnect Google Drive?',
      message: 'Automatic backups stop. Your existing Drive backup is not deleted.',
      confirmLabel: 'Disconnect',
    );
    if (ok) await _guarded(() => ref.read(backupServiceProvider).disconnect());
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(backupServiceProvider);
    final connected = ref.watch(driveConnectedProvider);
    final lastMs = int.tryParse(ref.watch(settingProvider(SETTING_LAST_BACKUP_AT)).value ?? '');
    final error = ref.watch(settingProvider(SETTING_BACKUP_ERROR)).value;
    final theme = Theme.of(context);

    if (!service.isConfigured) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: HintText(
            'Drive backup is not set up in this build. See README (Google Drive setup).',
            textAlign: TextAlign.start,
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(connected ? 'Connected' : 'Not connected', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            if (connected)
              HintText(
                lastMs == null
                    ? 'No backup yet'
                    : 'Last backup: ${formatRelativeDateTime(fromMillis(lastMs))}',
                textAlign: TextAlign.start,
              )
            else
              const HintText(
                'Back up to a hidden folder in your own Google Drive.',
                textAlign: TextAlign.start,
              ),
            if (connected && error != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 20, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(child: Text(error, style: TextStyle(color: theme.colorScheme.error))),
                ],
              ),
            ],
            const SizedBox(height: 12),
            if (_busy) const LinearProgressIndicator(),
            if (!connected)
              FilledButton(onPressed: _busy ? null : _connect, child: const Text('Connect'))
            else ...[
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _guarded(() => service.backupNow(interactive: true)),
                child: const Text('Back up now'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _busy ? null : _restoreFromDrive,
                      child: const Text('Restore from Drive'),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: _busy ? null : _disconnect,
                      child: const Text('Disconnect'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
