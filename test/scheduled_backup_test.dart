import 'package:cms/core/constants.dart';
import 'package:cms/data/database.dart';
import 'package:cms/data/profile_repository.dart';
import 'package:cms/features/backup/background_backup.dart';
import 'package:cms/features/backup/backup_scheduler.dart';
import 'package:cms/features/backup/backup_service.dart';
import 'package:cms/features/backup/drive_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_db.dart';

/// In-memory Drive app folder.
class FakeDrive implements DriveGateway {
  final Map<String, List<int>> files = {};
  BackupException? signInError;
  int silentSignIns = 0;

  @override
  bool get isConfigured => true;

  @override
  Future<void> signInSilently() async {
    silentSignIns++;
    if (signInError case final e?) throw e;
  }

  @override
  Future<void> signInInteractive() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<RemoteBackupInfo?> find(String name) async =>
      files.containsKey(name) ? RemoteBackupInfo(name, null) : null;

  @override
  Future<List<int>> download(String fileId) async => files[fileId]!;

  @override
  Future<Map<String, dynamic>> downloadJson(String fileId) => throw UnimplementedError();

  @override
  Future<void> upload(String name, List<int> bytes, {String? existingId}) async =>
      files[name] = bytes;
}

class FakeScheduler extends BackupScheduler {
  bool? scheduled;

  @override
  Future<void> schedule() async => scheduled = true;

  @override
  Future<void> cancel() async => scheduled = false;
}

void main() {
  late AppDatabase db;
  late ProfileRepository profile;
  late FakeDrive drive;

  setUp(() {
    db = openTestDb();
    profile = ProfileRepository(db);
    drive = FakeDrive();
  });
  tearDown(() => db.close());

  Future<void> addUserData() => profile.saveBodyWeight(DateTime(2026, 10, 1), 70.4);

  group('scheduled backup', () {
    test('skips when Drive is not connected', () async {
      await addUserData();
      await runScheduledBackup(db: db, drive: drive);
      expect(drive.silentSignIns, 0);
      expect(drive.files, isEmpty);
    });

    test('never uploads empty data', () async {
      await profile.setSetting(SETTING_DRIVE_CONNECTED, 'true');
      await profile.setSetting(SETTING_DATA_CHANGED_AT, '1');
      await runScheduledBackup(db: db, drive: drive);
      expect(drive.files, isEmpty);
      expect(await profile.getSetting(SETTING_BACKUP_ERROR), isNull);
    });

    test('uploads changed data with silent sign-in', () async {
      await addUserData();
      await profile.setSetting(SETTING_DRIVE_CONNECTED, 'true');
      await profile.setSetting(SETTING_DATA_CHANGED_AT, '1');
      await runScheduledBackup(db: db, drive: drive);
      expect(drive.silentSignIns, 1);
      expect(drive.files.keys, [BACKUP_FILE_NAME]);
      expect(await profile.getSetting(SETTING_LAST_BACKUP_AT), isNotNull);
    });

    test('skips when nothing changed since the last backup', () async {
      await addUserData();
      await profile.setSetting(SETTING_DRIVE_CONNECTED, 'true');
      await profile.setSetting(SETTING_DATA_CHANGED_AT, '1');
      await profile.setSetting(SETTING_LAST_BACKUP_AT, '2');
      await runScheduledBackup(db: db, drive: drive);
      expect(drive.silentSignIns, 0);
    });

    test('records failures for Profile and retries next time', () async {
      await addUserData();
      await profile.setSetting(SETTING_DRIVE_CONNECTED, 'true');
      await profile.setSetting(SETTING_DATA_CHANGED_AT, '1');
      drive.signInError = const BackupException('Google sign-in expired.');
      await runScheduledBackup(db: db, drive: drive);
      expect(await profile.getSetting(SETTING_BACKUP_ERROR), 'Google sign-in expired.');

      drive.signInError = null;
      await runScheduledBackup(db: db, drive: drive);
      expect(await profile.getSetting(SETTING_BACKUP_ERROR), isNull);
      expect(drive.files.keys, [BACKUP_FILE_NAME]);
    });
  });

  group('daily task registration', () {
    test('registered on connect, cancelled on disconnect', () async {
      final scheduler = FakeScheduler();
      final service = BackupService(db, drive, scheduler);
      await service.connect();
      expect(scheduler.scheduled, isTrue);
      await service.disconnect();
      expect(scheduler.scheduled, isFalse);
    });

    test('not registered while a remote backup awaits a choice', () async {
      drive.files[BACKUP_FILE_NAME] = [];
      final scheduler = FakeScheduler();
      final outcome = await BackupService(db, drive, scheduler).connect();
      expect(outcome, isA<RemoteBackupFound>());
      expect(scheduler.scheduled, isNull);
    });

    test('re-registered at startup when already connected', () async {
      await profile.setSetting(SETTING_DRIVE_CONNECTED, 'true');
      final scheduler = FakeScheduler();
      await BackupService(db, drive, scheduler).start();
      expect(scheduler.scheduled, isTrue);
    });
  });
}
