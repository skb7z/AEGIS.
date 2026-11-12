import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';
import 'auth_service.dart';

/// Conversation memory: lightweight JSON-lines file on disk, mirrored to the hidden Google Drive
/// appDataFolder. Any Drive problem falls back silently to local storage - it never throws.
class MemoryService {
  MemoryService(this._auth) {
    _auth.addListener(_onAuth);
  }

  final AuthService _auth;
  final ValueNotifier<String> syncStatus = ValueNotifier<String>('Local only');
  final List<Map<String, String>> _recent = [];
  File? _file;
  int _unsynced = 0;
  bool _syncing = false;
  bool _restored = false;

  Future<void> init() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/aegis_conversations.jsonl');
      if (await _file!.exists()) {
        final lines = await _file!.readAsLines();
        for (final l in lines.skip(lines.length > 40 ? lines.length - 40 : 0)) {
          _tryParse(l);
        }
      }
    } catch (e) {
      debugPrint('Memory init: $e');
    }
    // The login may already be known by now (fresh install + same Google account).
    _onAuth();
  }

  void _tryParse(String l) {
    try {
      final m = jsonDecode(l) as Map<String, dynamic>;
      _recent.add({'role': '${m['r']}', 'text': '${m['x']}'});
    } catch (_) {}
  }

  /// Last turns, used as AI context.
  List<Map<String, String>> get context =>
      _recent.length > 16 ? _recent.sublist(_recent.length - 16) : List.of(_recent);

  Future<void> add(String role, String text) async {
    _recent.add({'role': role, 'text': text});
    if (_recent.length > 60) _recent.removeRange(0, _recent.length - 60);
    try {
      final f = _file;
      if (f != null) {
        final line = jsonEncode({'t': DateTime.now().toIso8601String(), 'r': role, 'x': text});
        await f.writeAsString('$line\n', mode: FileMode.append, flush: true);
        if (await f.length() > 300 * 1024) await _trim(f);
      }
    } catch (e) {
      debugPrint('Memory add: $e');
    }
    _unsynced++;
    if (_unsynced >= 3) unawaited(sync());
  }

  Future<void> _trim(File f) async {
    final lines = await f.readAsLines();
    final keep = lines.length > 400 ? lines.sublist(lines.length - 400) : lines;
    await f.writeAsString('${keep.join('\n')}\n', flush: true);
  }

  Future<void> clear() async {
    _recent.clear();
    try {
      await _file?.writeAsString('', flush: true);
    } catch (_) {}
    _unsynced = 1;
    unawaited(sync());
  }

  void _onAuth() {
    if (_file == null) return; // init() not finished yet; it will call us again
    if (_auth.status == AuthStatus.signedIn && !_restored) {
      _restored = true;
      unawaited(restoreIfEmpty());
    }
  }

  /// Pushes the local log to Drive appDataFolder. Safe to call anytime.
  Future<void> sync() async {
    final f = _file;
    if (_syncing || f == null) return;
    if (!_auth.canUseDrive) {
      syncStatus.value = 'Local only';
      return;
    }
    _syncing = true;
    GoogleAuthClient? client;
    try {
      client = await _auth.driveClient();
      if (client == null) {
        syncStatus.value = 'Local only (Drive permission pending)';
        return;
      }
      final api = drive.DriveApi(client);
      final existing = await api.files
          .list(spaces: 'appDataFolder', q: "name = '${K.driveFile}'", $fields: 'files(id)')
          .timeout(const Duration(seconds: 25));
      final bytes = await f.exists() ? await f.readAsBytes() : Uint8List(0);
      final media = drive.Media(Stream<List<int>>.value(bytes), bytes.length);
      final files = existing.files;
      if (files != null && files.isNotEmpty && files.first.id != null) {
        await api.files
            .update(drive.File(), files.first.id!, uploadMedia: media)
            .timeout(const Duration(seconds: 40));
      } else {
        await api.files
            .create(drive.File()
              ..name = K.driveFile
              ..parents = ['appDataFolder'], uploadMedia: media)
            .timeout(const Duration(seconds: 40));
      }
      _unsynced = 0;
      final n = DateTime.now();
      syncStatus.value =
          'Synced ${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      debugPrint('Drive sync failed (local kept): $e');
      syncStatus.value = 'Local only (sync will retry)';
    } finally {
      client?.close();
      _syncing = false;
    }
  }

  /// If this device has no history yet, pull it from Drive.
  Future<void> restoreIfEmpty() async {
    final f = _file;
    if (f == null || !_auth.canUseDrive) return;
    GoogleAuthClient? client;
    try {
      if (await f.exists() && await f.length() > 0) return;
      client = await _auth.driveClient();
      if (client == null) return;
      final api = drive.DriveApi(client);
      final existing = await api.files
          .list(spaces: 'appDataFolder', q: "name = '${K.driveFile}'", $fields: 'files(id)')
          .timeout(const Duration(seconds: 25));
      final id = existing.files?.isNotEmpty == true ? existing.files!.first.id : null;
      if (id == null) return;
      final media = await api.files.get(id, downloadOptions: drive.DownloadOptions.fullMedia)
          as drive.Media;
      final data = <int>[];
      await for (final chunk in media.stream) {
        data.addAll(chunk);
      }
      await f.writeAsBytes(data, flush: true);
      _recent.clear();
      final lines = utf8.decode(data, allowMalformed: true).split('\n');
      for (final l in lines.skip(lines.length > 40 ? lines.length - 40 : 0)) {
        if (l.trim().isNotEmpty) _tryParse(l);
      }
      syncStatus.value = 'Restored from Drive';
    } catch (e) {
      debugPrint('Drive restore failed (ignored): $e');
    } finally {
      client?.close();
    }
  }
}
