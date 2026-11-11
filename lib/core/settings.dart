import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Non-secret user preferences.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._p);
  final SharedPreferences _p;

  static Future<AppSettings> load() async =>
      AppSettings._(await SharedPreferences.getInstance());

  String get themeId => _p.getString('theme') ?? 'cyber'; // cyber = Dark, chalk = White
  String? get wallpaper => _p.getString('wallpaper');
  double get blur => _p.getDouble('blur') ?? 40; // 0..100
  double get blurSigma => blur * 0.3;
  bool get male => _p.getBool('male') ?? true;
  String get language => _p.getString('lang') == 'en' ? 'en' : 'bn'; // bn | en
  bool get wake => _p.getBool('wake') ?? false; // master ON/OFF, survives restarts
  bool get announce => _p.getBool('announce') ?? false;
  bool get autostartDone => _p.getBool('autostart_done') ?? false;
  Set<String> get whitelist => (_p.getStringList('whitelist') ?? const <String>[]).toSet();
  String get nickname => _p.getString('nickname') ?? '';

  Future<void> setTheme(String v) async {
    await _p.setString('theme', v);
    notifyListeners();
  }

  Future<void> setWallpaper(String? v) async {
    if (v == null) {
      await _p.remove('wallpaper');
    } else {
      await _p.setString('wallpaper', v);
    }
    notifyListeners();
  }

  Future<void> setBlur(double v) async {
    await _p.setDouble('blur', v.clamp(0, 100).toDouble());
    notifyListeners();
  }

  Future<void> setMale(bool v) async {
    await _p.setBool('male', v);
    notifyListeners();
  }

  Future<void> setLanguage(String v) async {
    await _p.setString('lang', v);
    notifyListeners();
  }

  Future<void> setWake(bool v) async {
    await _p.setBool('wake', v);
    notifyListeners();
  }

  Future<void> setAnnounce(bool v) async {
    await _p.setBool('announce', v);
    notifyListeners();
  }

  Future<void> setAutostartDone(bool v) async {
    await _p.setBool('autostart_done', v);
    notifyListeners();
  }

  Future<void> setWhitelist(Set<String> v) async {
    await _p.setStringList('whitelist', v.toList());
    notifyListeners();
  }

  Future<void> setNickname(String v) async {
    await _p.setString('nickname', v.trim());
    notifyListeners();
  }

  // ---------------------------------------------------------------- Drive backup

  /// Everything that should survive an uninstall. (Wallpaper path and the ON/OFF wake state are
  /// device-specific, so they are not included.)
  Map<String, dynamic> toBackup() => {
        'theme': themeId,
        'blur': blur,
        'male': male,
        'lang': language,
        'announce': announce,
        'whitelist': whitelist.toList()..sort(),
        'nickname': nickname,
      };

  Future<void> applyBackup(Map<String, dynamic> m) async {
    if (m['theme'] is String) await _p.setString('theme', m['theme'] as String);
    if (m['blur'] is num) await _p.setDouble('blur', (m['blur'] as num).toDouble().clamp(0, 100).toDouble());
    if (m['male'] is bool) await _p.setBool('male', m['male'] as bool);
    if (m['lang'] is String) await _p.setString('lang', m['lang'] as String);
    if (m['announce'] is bool) await _p.setBool('announce', m['announce'] as bool);
    if (m['whitelist'] is List) {
      await _p.setStringList('whitelist', (m['whitelist'] as List).map((e) => '$e').toList());
    }
    if (m['nickname'] is String) await _p.setString('nickname', m['nickname'] as String);
    notifyListeners();
  }
}
