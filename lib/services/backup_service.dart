import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import '../core/settings.dart';
import 'auth_service.dart';

/// Backs up profile + settings to the hidden Google Drive app folder of the signed-in Google account
/// and restores them after a reinstall. Email/password accounts have no Drive access, so they are
/// skipped. Never throws; if Drive fails, the app keeps working locally.
///
/// Order matters: after sign-in we RESTORE first and only then start backing up, so an empty fresh
/// install can never overwrite the cloud copy.
class BackupService {
  BackupService(this._auth, this._settings) {
    _auth.addListener(_onChange);
    _settings.addListener(_onChange);
  }

  static const _file = 'aegis_profile.json';
  final AuthService _auth;
  final AppSettings _settings;

  bool _ready = false; // true once restore has finished for this sign-in
  bool _restoring = false;
  Timer? _debounce;
  Timer? _retry;
  String _lastSent = '';

  void _onChange() {
    if (!_auth.canUseDrive) {
      _ready = false;
      return;
    }
    if (!_ready) {
      if (!_restoring) unawaited(_restore());
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 6), () => unawaited(backup()));
  }

  Future<drive.DriveApi?> _api() async {
    final c = await _auth.driveClient();
    return c == null ? null : drive.DriveApi(c);
  }

  Future<String?> _findId(drive.DriveApi api) async {
    final r = await api.files
        .list(spaces: 'appDataFolder', q: "name = '$_file'", $fields: 'files(id)')
        .timeout(const Duration(seconds: 25));
    final f = r.files;
    return (f != null && f.isNotEmpty) ? f.first.id : null;
  }

  Future<void> _restore() async {
    _restoring = true;
    try {
      final api = await _api();
      if (api == null) throw StateError('no drive client');
      final id = await _findId(api);
      if (id != null) {
        final media = await api.files.get(id, downloadOptions: drive.DownloadOptions.fullMedia)
            as drive.Media;
        final data = <int>[];
        await for (final chunk in media.stream) {
          data.addAll(chunk);
        }
        final j = jsonDecode(utf8.decode(data, allowMalformed: true)) as Map<String, dynamic>;
        // Cloud wins only on a fresh install (no complete local profile yet).
        if (!_auth.profile.complete) {
          if (j['profile'] is Map) {
            await _auth.saveProfile(
                AegisProfile.fromJson(Map<String, dynamic>.from(j['profile'] as Map)));
          }
          if (j['settings'] is Map) {
            await _settings.applyBackup(Map<String, dynamic>.from(j['settings'] as Map));
          }
        }
      }
      _ready = true;
      _restoring = false;
      unawaited(backup());
    } catch (e) {
      debugPrint('Drive restore failed, will retry: $e');
      _restoring = false;
      _retry?.cancel();
      _retry = Timer(const Duration(seconds: 45), () {
        if (_auth.canUseDrive && !_ready && !_restoring) unawaited(_restore());
      });
    }
  }

  /// Uploads the current profile + settings (skipped when nothing changed).
  Future<void> backup() async {
    if (!_ready || !_auth.canUseDrive) return;
    try {
      final body = jsonEncode({
        'v': 1,
        'profile': _auth.profile.toJson(),
        'settings': _settings.toBackup(),
      });
      if (body == _lastSent) return;
      final api = await _api();
      if (api == null) return;
      final bytes = Uint8List.fromList(utf8.encode(body));
      final media = drive.Media(Stream<List<int>>.value(bytes), bytes.length);
      final id = await _findId(api);
      if (id != null) {
        await api.files
            .update(drive.File(), id, uploadMedia: media)
            .timeout(const Duration(seconds: 40));
      } else {
        await api.files
            .create(
              drive.File()
                ..name = _file
                ..parents = ['appDataFolder'],
              uploadMedia: media,
            )
            .timeout(const Duration(seconds: 40));
      }
      _lastSent = body;
    } catch (e) {
      debugPrint('Drive backup failed (local data kept): $e');
    }
  }
}
