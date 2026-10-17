import 'dart:async';
import 'dart:convert';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../../core/constants.dart';

/// A problem the user has to act on (shown in Profile).
class BackupException implements Exception {
  const BackupException(this.message);
  final String message;

  @override
  String toString() => message;
}

class RemoteBackupInfo {
  const RemoteBackupInfo(this.fileId, this.modifiedTime);
  final String fileId;
  final DateTime? modifiedTime;
}

/// Google sign-in plus the hidden Drive app data folder (drive.appdata scope).
class DriveGateway {
  static const List<String> _SCOPES = [DRIVE_APPDATA_SCOPE];
  static const String _APP_FOLDER = 'appDataFolder';

  Future<void>? _init;
  drive.DriveApi? _api;
  http.Client? _client;

  bool get isConfigured => GOOGLE_SERVER_CLIENT_ID.isNotEmpty;

  Future<void> _ensureInitialised() {
    if (!isConfigured) {
      throw const BackupException(
        'Google Drive is not set up in this build (missing GOOGLE_SERVER_CLIENT_ID).',
      );
    }
    return _init ??= GoogleSignIn.instance.initialize(serverClientId: GOOGLE_SERVER_CLIENT_ID);
  }

  /// Interactive sign-in and consent; call from a button press.
  Future<void> signInInteractive() async {
    await _ensureInitialised();
    try {
      final account = await GoogleSignIn.instance.authenticate(scopeHint: _SCOPES);
      final authz = await account.authorizationClient.authorizationForScopes(_SCOPES) ??
          await account.authorizationClient.authorizeScopes(_SCOPES);
      _setClient(authz);
    } on GoogleSignInException catch (e) {
      throw BackupException(
        e.code == GoogleSignInExceptionCode.canceled
            ? 'Sign-in was cancelled.'
            : 'Google sign-in failed (${e.code.name}).',
      );
    }
  }

  /// Silent sign-in for background backups.
  Future<void> signInSilently() async {
    await _ensureInitialised();
    const expired = BackupException('Google sign-in expired. Tap Back up now to sign in again.');
    GoogleSignInAccount? account;
    try {
      account = await GoogleSignIn.instance.attemptLightweightAuthentication();
    } on GoogleSignInException {
      account = null;
    }
    // Credential Manager needs an Activity, which the workmanager isolate
    // doesn't have (uiUnavailable). The account-less client still returns a
    // token for scopes granted earlier, without any UI.
    final client = account?.authorizationClient ?? GoogleSignIn.instance.authorizationClient;
    final authz = await client.authorizationForScopes(_SCOPES);
    if (authz == null) throw expired;
    _setClient(authz);
  }

  void _setClient(GoogleSignInClientAuthorization authz) {
    _client?.close();
    final client = authz.authClient(scopes: _SCOPES);
    _client = client;
    _api = drive.DriveApi(client);
  }

  Future<void> disconnect() async {
    _client?.close();
    _client = null;
    _api = null;
    if (!isConfigured) return;
    await _ensureInitialised();
    try {
      await GoogleSignIn.instance.disconnect();
    } on Object {
      await GoogleSignIn.instance.signOut();
    }
  }

  drive.DriveApi get _drive {
    final api = _api;
    if (api == null) throw const BackupException('Not signed in to Google Drive.');
    return api;
  }

  Future<RemoteBackupInfo?> find(String name) => _guard(() async {
    final list = await _drive.files.list(
      spaces: _APP_FOLDER,
      q: "name = '$name' and trashed = false",
      orderBy: 'modifiedTime desc',
      $fields: 'files(id,name,modifiedTime)',
    );
    final file = list.files?.firstOrNull;
    return file?.id == null ? null : RemoteBackupInfo(file!.id!, file.modifiedTime?.toLocal());
  });

  Future<List<int>> download(String fileId) => _guard(() async {
    final media = await _drive.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final bytes = <int>[];
    await for (final chunk in media.stream) {
      bytes.addAll(chunk);
    }
    return bytes;
  });

  Future<Map<String, dynamic>> downloadJson(String fileId) async =>
      (jsonDecode(utf8.decode(await download(fileId))) as Map).cast<String, dynamic>();

  /// Creates [name] in the app folder, or overwrites [existingId].
  Future<void> upload(String name, List<int> bytes, {String? existingId}) => _guard(() async {
    final media = drive.Media(Stream.value(bytes), bytes.length, contentType: 'application/json');
    if (existingId != null) {
      await _drive.files.update(drive.File(), existingId, uploadMedia: media);
    } else {
      await _drive.files.create(
        drive.File()
          ..name = name
          ..parents = [_APP_FOLDER],
        uploadMedia: media,
      );
    }
  });

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call().timeout(const Duration(seconds: 60));
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 401 || e.status == 403) {
        throw const BackupException('Google sign-in expired. Tap Back up now to sign in again.');
      }
      throw BackupException('Google Drive error ${e.status}: ${e.message}');
    } on TimeoutException {
      throw const BackupException('Google Drive did not answer. Will retry later.');
    } on http.ClientException {
      throw const BackupException('No connection to Google Drive. Will retry later.');
    }
  }
}
