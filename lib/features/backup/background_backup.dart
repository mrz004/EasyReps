import 'package:workmanager/workmanager.dart';

import '../../core/constants.dart';
import '../../data/database.dart';
import 'backup_service.dart';
import 'drive_gateway.dart';

/// Entry point of the `workmanager` isolate. It shares nothing with the UI
/// isolate, so it opens its own database connection.
@pragma('vm:entry-point')
void backgroundBackupDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == BACKUP_TASK_NAME) await runScheduledBackup();
    return true;
  });
}

/// Runs the same checks as the background-of-app backup: skips when Drive
/// isn't connected, nothing changed, or local data is empty. Failures land in
/// `settings.backup_error` (shown in Profile), so the task itself always
/// succeeds and simply tries again the next day.
Future<void> runScheduledBackup({AppDatabase? db, DriveGateway? drive}) async {
  final database = db ?? AppDatabase();
  try {
    await BackupService(database, drive ?? DriveGateway()).backupIfNeeded();
  } finally {
    if (db == null) await database.close();
  }
}
