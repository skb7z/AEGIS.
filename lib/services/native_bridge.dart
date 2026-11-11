import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/constants.dart';
import '../core/errors.dart';

class AppInfo {
  const AppInfo(this.name, this.pkg, [this.icon]);
  final String name;
  final String pkg;
  final Uint8List? icon;
}

/// Thin typed wrapper around the Kotlin MethodChannel. Every call is crash-safe.
class NativeBridge {
  static const MethodChannel _ch = MethodChannel(K.channel);

  final _wake = StreamController<void>.broadcast();
  final _stopWord = StreamController<void>.broadcast();
  final _notif = StreamController<Map<String, String>>.broadcast();
  final ValueNotifier<String> wakeStatus = ValueNotifier<String>('idle');

  Stream<void> get onWake => _wake.stream;
  Stream<void> get onStopWord => _stopWord.stream;
  Stream<Map<String, String>> get onNotification => _notif.stream;

  Future<void> init() async {
    _ch.setMethodCallHandler(_handle);
    final pending = await _invoke<bool>('ready');
    if (pending == true) _wake.add(null);
  }

  Future<dynamic> _handle(MethodCall c) async {
    switch (c.method) {
      case 'wake':
        _wake.add(null);
        break;
      case 'stopWord':
        _stopWord.add(null);
        break;
      case 'notification':
        final m = Map<dynamic, dynamic>.from(c.arguments as Map);
        _notif.add({for (final e in m.entries) e.key.toString(): e.value?.toString() ?? ''});
        break;
      case 'voskStatus':
        wakeStatus.value = c.arguments?.toString() ?? '';
        break;
    }
    return null;
  }

  Future<T?> _invoke<T>(String method, [dynamic args]) async {
    try {
      return await _ch.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      debugPrint('native $method: ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    } catch (e) {
      debugPrint('native $method: $e');
      return null;
    }
  }

  Future<List<AppInfo>> getApps() async {
    try {
      final r = await _ch.invokeListMethod<Map<Object?, Object?>>('getApps') ?? const [];
      return r.map((m) {
        final ic = m['icon'];
        return AppInfo('${m['name']}', '${m['pkg']}', ic is Uint8List ? ic : null);
      }).toList();
    } catch (e) {
      debugPrint('getApps: $e');
      return const [];
    }
  }

  Future<void> setWhitelist(List<String> pkgs) => _invoke('setWhitelist', {'pkgs': pkgs});

  Future<Map<String, dynamic>> status() async {
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>('status');
      return r ?? <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> openSetting(String which) => _invoke('openSetting', {'which': which});
  Future<void> startService() => _invoke('startService');
  Future<void> stopService() => _invoke('stopService');
  Future<void> pauseWake() => _invoke('pauseWake');
  Future<void> resumeWake() => _invoke('resumeWake');
  Future<void> startStopListener() => _invoke('startStopListener');
  Future<void> duck() => _invoke('duck');
  Future<void> abandonFocus() => _invoke('abandonFocus');

  Future<void> setNickname(String n) => _invoke('setNickname', {'name': n});

  Future<bool> openApp(String pkg) async =>
      (await _invoke<bool>('openApp', {'pkg': pkg})) ?? false;

  Future<bool> setTimer(int seconds) async =>
      (await _invoke<bool>('setTimer', {'seconds': seconds})) ?? false;

  Future<bool> setAlarm(int hour, int minute) async =>
      (await _invoke<bool>('setAlarm', {'hour': hour, 'minute': minute})) ?? false;

  Future<bool> globalAction(String name) async =>
      (await _invoke<bool>('globalAction', {'name': name})) ?? false;

  Future<bool> replyToNotification(String pkg, String text) async =>
      (await _invoke<bool>('replyToNotification', {'pkg': pkg, 'text': text})) ?? false;

  /// Captures exactly one screenshot and returns the JPEG path.
  Future<String> captureScreenshot() async {
    try {
      final p = await _ch.invokeMethod<String>('captureScreenshot');
      if (p == null || p.isEmpty) throw const ApiFailure('Screenshot failed.');
      return p;
    } on PlatformException catch (e) {
      throw ApiFailure(e.code == 'denied'
          ? 'Screenshot permission was denied.'
          : 'I could not take the screenshot.');
    }
  }
}
