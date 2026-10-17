import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/backup_codec.dart';
import '../../data/database.dart';
import '../../data/profile_repository.dart';
import '../../data/providers.dart';
import 'backup_scheduler.dart';
import 'drive_gateway.dart';

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(databaseProvider), DriveGateway(), BackupScheduler()),
);

sealed class ConnectOutcome {
  const ConnectOutcome();
}

/// Connected; there was no remote backup.
class ConnectedFresh extends ConnectOutcome {
  const ConnectedFresh();
}

/// A remote backup exists. Nothing uploads until the user picks Restore or
/// Start fresh on the Drive connect / restore screen.
class RemoteBackupFound extends ConnectOutcome {
  const RemoteBackupFound(this.info);
  final RemoteBackupInfo info;
}

/// Google Drive backup with the safety rules of spec section 8.
class BackupService {
  /// [scheduler] is only needed where Drive can be connected or disconnected
  /// (the UI isolate), not inside the scheduled task itself.
  BackupService(this.db, this.drive, [this.scheduler])
    : _profile = ProfileRepository(db),
      _codec = BackupCodec(db);

  final AppDatabase db;
  final DriveGateway drive;
  final BackupScheduler? scheduler;
  final ProfileRepository _profile;
  final BackupCodec _codec;

  StreamSubscription<Set<TableUpdate>>? _changes;
  bool _trackChanges = true;
  Future<void>? _running;

  bool get isConfigured => drive.isConfigured;

  /// Starts tracking local data changes (for "changed since last backup"),
  /// and re-registers the daily task if Drive is connected (WorkManager can
  /// lose it, e.g. after the app's data is restored by Android).
  Future<void> start() async {
    _changes ??= db
        .tableUpdates(TableUpdateQuery.onAllTables(db.userDataTables))
        .listen((_) {
          if (_trackChanges) _setMs(SETTING_DATA_CHANGED_AT, DateTime.now());
        });
    if (isConfigured && await _connected) await scheduler?.schedule();
  }

  Future<void> _setMs(String key, DateTime t) =>
      _profile.setSetting(key, '${t.millisecondsSinceEpoch}');

  Future<int?> _getMs(String key) async => int.tryParse(await _profile.getSetting(key) ?? '');

  Future<bool> get _connected async =>
      await _profile.getSetting(SETTING_DRIVE_CONNECTED) == 'true';

  /// The daily task exists exactly while Drive is connected.
  Future<void> _setConnected(bool connected) async {
    await _profile.setSetting(SETTING_DRIVE_CONNECTED, '$connected');
    connected ? await scheduler?.schedule() : await scheduler?.cancel();
  }

  /// User tapped Connect. Signs in, then checks for an existing backup.
  Future<ConnectOutcome> connect() async {
    await drive.signInInteractive();
    final remote = await drive.find(BACKUP_FILE_NAME);
    if (remote != null) return RemoteBackupFound(remote);
    await _setConnected(true);
    await _recordResult(null);
    await backupNow(interactive: false);
    return const ConnectedFresh();
  }

  /// Looks for a remote backup (Profile > Restore from Drive).
  Future<RemoteBackupInfo?> findRemote() async {
    await drive.signInInteractive();
    return drive.find(BACKUP_FILE_NAME);
  }

  /// Replaces local data with the remote backup in one transaction.
  Future<void> restore(RemoteBackupInfo info) async {
    final payload = await drive.downloadJson(info.fileId);
    _trackChanges = false;
    try {
      await _codec.restore(payload);
      await Future<void>.delayed(Duration.zero); // Let update events drain.
    } finally {
      _trackChanges = true;
    }
    final now = DateTime.now();
    await _setMs(SETTING_LAST_BACKUP_AT, now);
    await _setMs(SETTING_DATA_CHANGED_AT, now.subtract(const Duration(seconds: 1)));
    await _setConnected(true);
    await _recordResult(null);
  }

  /// Keeps the remote file; the next backup moves it to backup.prev.json
  /// before writing this phone's data.
  Future<void> startFresh() async {
    await _setConnected(true);
    await _recordResult(null);
    await backupNow(interactive: false);
  }

  Future<void> disconnect() async {
    await drive.disconnect();
    await _setConnected(false);
    await _recordResult(null);
  }

  /// App went to the background, or the daily task ran: back up if data
  /// changed or the last try failed.
  Future<void> backupIfNeeded() async {
    if (!isConfigured || !await _connected) return;
    final changed = await _getMs(SETTING_DATA_CHANGED_AT) ?? 0;
    final last = await _getMs(SETTING_LAST_BACKUP_AT) ?? 0;
    final failed = await _profile.getSetting(SETTING_BACKUP_ERROR) != null;
    if (changed > last || failed) await backupNow(interactive: false);
  }

  /// Uploads a backup. Failures are recorded for Profile, never thrown.
  Future<void> backupNow({required bool interactive}) {
    return _running ??= _backup(interactive).whenComplete(() => _running = null);
  }

  Future<void> _backup(bool interactive) async {
    try {
      if (!await _connected) return;
      final payload = await _codec.export();
      if (BackupCodec.isEmpty(payload)) return; // Never upload empty data.

      interactive ? await drive.signInInteractive() : await drive.signInSilently();
      final current = await drive.find(BACKUP_FILE_NAME);
      if (current != null) {
        final previous = await drive.find(BACKUP_PREV_FILE_NAME);
        await drive.upload(
          BACKUP_PREV_FILE_NAME,
          await drive.download(current.fileId),
          existingId: previous?.fileId,
        );
      }
      await drive.upload(
        BACKUP_FILE_NAME,
        utf8.encode(jsonEncode(payload)),
        existingId: current?.fileId,
      );
      await _setMs(SETTING_LAST_BACKUP_AT, DateTime.now());
      await _recordResult(null);
    } on BackupException catch (e) {
      await _recordResult(e.message);
    } on SocketException {
      await _recordResult('No connection to Google Drive. Will retry later.');
    } on Object catch (e) {
      await _recordResult('Backup failed: $e');
    }
  }

  Future<void> _recordResult(String? error) =>
      _profile.setSetting(SETTING_BACKUP_ERROR, error);
}
