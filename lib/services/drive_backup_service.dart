import 'dart:typed_data';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_lang.dart';
import '../models/pet.dart';
import 'backup_service.dart';
import 'google_account.dart';

/// Keeps one copy of the backup in the user's Google Drive and refreshes it
/// once a day when the app is opened, so a new phone can restore everything.
///
/// It only asks for `drive.file`: the app can see the files it created and
/// nothing else of the user's Drive.
class DriveBackupService extends ChangeNotifier {
  DriveBackupService._();
  static final instance = DriveBackupService._();

  static const fileName = 'PetTime - copia automática.zip';
  static const _scopes = [drive.DriveApi.driveFileScope];
  static const _enabledKey = 'drive_backup_v1';
  static const _lastKey = 'drive_backup_last';
  static const _fileIdKey = 'drive_backup_file_id';

  /// How often the automatic copy is refreshed.
  static const every = Duration(hours: 24);

  bool _enabled = false;
  DateTime? _last;

  bool get enabled => _enabled;
  DateTime? get lastBackup => _last;

  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? false;
    _last = DateTime.tryParse(prefs.getString(_lastKey) ?? '');
    notifyListeners();
  }

  /// Whether the automatic copy is due at [now].
  static bool isDue(DateTime? last, DateTime now) =>
      last == null || now.difference(last) >= every;

  /// Signs in, asks for the Drive permission, turns the automatic copy on
  /// and uploads one right away.
  Future<void> enable(List<Pet> pets) async {
    await GoogleAccount.instance.connect(_scopes);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, true);
    _enabled = true;
    notifyListeners();
    await backupNow(pets);
  }

  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
    _enabled = false;
    notifyListeners();
  }

  Future<drive.DriveApi> _api() async {
    final auth = await GoogleAccount.instance.authorization(_scopes);
    if (auth == null) {
      throw StateError(tr('Hay que volver a conectar Google Drive.'));
    }
    return drive.DriveApi(auth.authClient(scopes: _scopes));
  }

  /// The backup file made by this app, if there is one (it may come from
  /// another phone with the same account).
  Future<drive.File?> _find(drive.DriveApi api) async {
    final prefs = await SharedPreferences.getInstance();
    final known = prefs.getString(_fileIdKey);
    if (known != null) {
      try {
        final f = await api.files.get(known, $fields: 'id,trashed,modifiedTime')
            as drive.File;
        if (f.trashed != true) return f;
      } on drive.DetailedApiRequestError catch (e) {
        if (e.status != 404) rethrow;
      }
    }
    final list = await api.files.list(
      q: "name = '$fileName' and trashed = false",
      orderBy: 'modifiedTime desc',
      pageSize: 1,
      $fields: 'files(id,modifiedTime)',
    );
    final f = list.files?.firstOrNull;
    if (f != null) await prefs.setString(_fileIdKey, f.id!);
    return f;
  }

  /// Uploads the backup now (replacing the previous one).
  Future<void> backupNow(List<Pet> pets) async {
    final api = await _api();
    final bytes = BackupService.buildZip(pets);
    final media = drive.Media(
      Stream.value(bytes),
      bytes.length,
      contentType: 'application/zip',
    );
    final existing = await _find(api);
    final drive.File saved;
    if (existing == null) {
      saved = await api.files.create(
        drive.File()
          ..name = fileName
          ..mimeType = 'application/zip',
        uploadMedia: media,
      );
    } else {
      saved = await api.files.update(drive.File(), existing.id!, uploadMedia: media);
    }
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fileIdKey, saved.id!);
    await prefs.setString(_lastKey, now.toIso8601String());
    _last = now;
    notifyListeners();
  }

  /// Refreshes the copy when it is on and a day has passed. Called when the
  /// app starts; never asks anything and never fails loudly.
  Future<void> backupIfDue(List<Pet> pets) async {
    if (!supported || !_enabled || !isDue(_last, DateTime.now())) return;
    try {
      await backupNow(pets);
    } catch (e) {
      debugPrint('Automatic Drive backup failed: $e');
    }
  }

  /// Downloads the latest copy in Drive: its date and contents, or null when
  /// there is none. Asks to connect the account if needed.
  Future<(DateTime?, Uint8List)?> download() async {
    if (await GoogleAccount.instance.authorization(_scopes) == null) {
      await GoogleAccount.instance.connect(_scopes);
    }
    final api = await _api();
    final f = await _find(api);
    if (f == null) return null;
    final media = await api.files.get(
      f.id!,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in media.stream) {
      builder.add(chunk);
    }
    return (f.modifiedTime?.toLocal(), builder.takeBytes());
  }
}
