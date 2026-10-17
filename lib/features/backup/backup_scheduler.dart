import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/constants.dart';
import 'background_backup.dart';

/// Registers the daily, network-constrained backup task (spec section 8,
/// phase 2). Android only; a no-op elsewhere (and in tests).
class BackupScheduler {
  Future<void>? _init;

  bool get _supported => !kIsWeb && Platform.isAndroid;

  Future<void> _ensureInitialised() =>
      _init ??= Workmanager().initialize(backgroundBackupDispatcher);

  /// Safe to call repeatedly: `update` keeps the existing schedule.
  Future<void> schedule() => _guard(() async {
    await _ensureInitialised();
    await Workmanager().registerPeriodicTask(
      BACKUP_TASK_UNIQUE_NAME,
      BACKUP_TASK_NAME,
      frequency: const Duration(days: 1),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  });

  Future<void> cancel() => _guard(() async {
    await _ensureInitialised();
    await Workmanager().cancelByUniqueName(BACKUP_TASK_UNIQUE_NAME);
  });

  /// Scheduling problems never break connect / disconnect: the backup on
  /// going to the background (phase 1) still runs.
  Future<void> _guard(Future<void> Function() call) async {
    if (!_supported) return;
    try {
      await call();
    } on Object catch (e) {
      debugPrint('Backup scheduling failed: $e');
    }
  }
}
