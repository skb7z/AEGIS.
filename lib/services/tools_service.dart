import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../core/settings.dart';
import 'auth_service.dart';
import 'native_bridge.dart';

/// Tools the AI agent can call (modelled on OpenJarvis tools): all free, no API key.
class ToolsService {
  ToolsService(this._native, this._settings, this._auth);
  final NativeBridge _native;
  // ignore: unused_field
  final AppSettings _settings;
  final AuthService _auth;

  final List<String> _notifs = [];
  List<AppInfo>? _apps;
  static const _ua = {'User-Agent': 'Aegis/1.0 (aegis.ai.support.team@gmail.com)'};

  /// Only notifications from whitelisted apps ever reach this list.
  void addNotification(String s) {
    _notifs.add(s);
    if (_notifs.length > 12) _notifs.removeAt(0);
  }

  Future<String> run(String name, String arg, String lang) async {
    try {
      switch (name) {
        case 'time':
          return _time();
        case 'weather':
          return await _weather(arg);
        case 'wiki':
          return await _wiki(arg, lang);
        case 'calc':
          return _calc(arg);
        case 'open_app':
          return await _openApp(arg);
        case 'timer':
          final m = double.tryParse(arg.replaceAll(RegExp(r'[^0-9.]'), ''));
          if (m == null || m <= 0) return 'Invalid minutes.';
          return await _native.setTimer((m * 60).round())
              ? 'Timer set for $m minutes.'
              : 'Could not set the timer.';
        case 'alarm':
          final mt = RegExp(r'(\d{1,2})\s*[:.]\s*(\d{2})').firstMatch(arg);
          if (mt == null) return 'Invalid time. Use HH:MM.';
          final h = int.parse(mt.group(1)!), mi = int.parse(mt.group(2)!);
          if (h > 23 || mi > 59) return 'Invalid time.';
          return await _native.setAlarm(h, mi)
              ? 'Alarm set for $h:${mi.toString().padLeft(2, '0')}.'
              : 'Could not set the alarm.';
        case 'notifications':
          return _notifs.isEmpty
              ? 'No recent notifications from allowed apps.'
              : _notifs.reversed.take(6).join('\n');
        default:
          return 'Unknown tool.';
      }
    } on SocketException {
      return 'Network error.';
    } on TimeoutException {
      return 'The request timed out.';
    } catch (_) {
      return 'The tool failed.';
    }
  }

  // ---------------------------------------------------------------- time

  String _time() {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final n = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${days[n.weekday - 1]}, ${n.year}-${p(n.month)}-${p(n.day)}, ${p(n.hour)}:${p(n.minute)}';
  }

  // ---------------------------------------------------------------- weather (Open-Meteo, key-less)

  static String _wcode(int c) {
    if (c == 0) return 'clear sky';
    if (c <= 3) return 'partly cloudy';
    if (c == 45 || c == 48) return 'foggy';
    if (c >= 51 && c <= 57) return 'drizzle';
    if (c >= 61 && c <= 67) return 'rain';
    if (c >= 71 && c <= 77) return 'snow';
    if (c >= 80 && c <= 82) return 'rain showers';
    if (c >= 95) return 'thunderstorm';
    return 'cloudy';
  }

  Future<String> _weather(String arg) async {
    var place = arg.trim();
    if (place.isEmpty) {
      place = _auth.profile.country.trim().isEmpty ? 'Dhaka' : _auth.profile.country.trim();
    }
    final g = await http
        .get(Uri.https('geocoding-api.open-meteo.com', '/v1/search', {'name': place, 'count': '1'}))
        .timeout(const Duration(seconds: 12));
    final gj = jsonDecode(utf8.decode(g.bodyBytes)) as Map<String, dynamic>;
    final res = gj['results'] as List?;
    if (res == null || res.isEmpty) return 'Place not found: $place.';
    final r = res.first as Map<String, dynamic>;
    final w = await http
        .get(Uri.https('api.open-meteo.com', '/v1/forecast', {
          'latitude': '${r['latitude']}',
          'longitude': '${r['longitude']}',
          'current': 'temperature_2m,apparent_temperature,weather_code,wind_speed_10m',
          'timezone': 'auto',
        }))
        .timeout(const Duration(seconds: 12));
    final cur = (jsonDecode(utf8.decode(w.bodyBytes)) as Map<String, dynamic>)['current']
        as Map<String, dynamic>;
    return '${r['name']}: ${cur['temperature_2m']} C (feels ${cur['apparent_temperature']} C), '
        '${_wcode((cur['weather_code'] as num).toInt())}, wind ${cur['wind_speed_10m']} km/h.';
  }

  // ---------------------------------------------------------------- Wikipedia (key-less)

  Future<String> _wiki(String q, String lang) async {
    if (q.trim().isEmpty) return 'No topic given.';
    for (final l in lang == 'bn' ? ['bn', 'en'] : ['en']) {
      final s = await http
          .get(
            Uri.https('$l.wikipedia.org', '/w/api.php', {
              'action': 'query',
              'list': 'search',
              'srsearch': q,
              'srlimit': '1',
              'format': 'json',
            }),
            headers: _ua,
          )
          .timeout(const Duration(seconds: 12));
      final list = ((jsonDecode(utf8.decode(s.bodyBytes)) as Map)['query']?['search']) as List?;
      if (list == null || list.isEmpty) continue;
      final title = '${(list.first as Map)['title']}';
      final r = await http
          .get(Uri.https('$l.wikipedia.org', '/api/rest_v1/page/summary/$title'), headers: _ua)
          .timeout(const Duration(seconds: 12));
      var ex = '${(jsonDecode(utf8.decode(r.bodyBytes)) as Map)['extract'] ?? ''}'.trim();
      if (ex.isEmpty) continue;
      if (ex.length > 600) ex = ex.substring(0, 600);
      return '$title: $ex';
    }
    return 'Nothing found for "$q".';
  }

  // ---------------------------------------------------------------- calculator

  String _calc(String e) {
    try {
      final v = _Calc(e.replaceAll('×', '*').replaceAll('÷', '/').replaceAll(',', '')).parse();
      if (v.isNaN || v.isInfinite) return 'Math error.';
      return v == v.roundToDouble() && v.abs() < 1e15 ? v.toInt().toString() : v.toStringAsFixed(4);
    } catch (_) {
      return 'Could not calculate that.';
    }
  }

  // ---------------------------------------------------------------- open app

  Future<String> _openApp(String name) async {
    final q = name.toLowerCase().trim();
    if (q.isEmpty) return 'No app name given.';
    _apps ??= await _native.getApps();
    AppInfo? hit;
    for (final a in _apps!) {
      if (a.name.toLowerCase() == q) {
        hit = a;
        break;
      }
    }
    if (hit == null) {
      for (final a in _apps!) {
        final n = a.name.toLowerCase();
        if (n.contains(q) || q.contains(n)) {
          hit = a;
          break;
        }
      }
    }
    if (hit == null) return 'No app named "$name" is installed.';
    return await _native.openApp(hit.pkg) ? 'Opened ${hit.name}.' : 'Could not open ${hit.name}.';
  }
}

class _Calc {
  _Calc(this.s);
  final String s;
  int i = 0;

  double parse() {
    final v = _expr();
    _ws();
    if (i != s.length) throw const FormatException();
    return v;
  }

  void _ws() {
    while (i < s.length && s[i] == ' ') {
      i++;
    }
  }

  double _expr() {
    var v = _term();
    while (true) {
      _ws();
      if (i < s.length && (s[i] == '+' || s[i] == '-')) {
        final o = s[i++];
        final r = _term();
        v = o == '+' ? v + r : v - r;
      } else {
        return v;
      }
    }
  }

  double _term() {
    var v = _pow();
    while (true) {
      _ws();
      if (i < s.length && (s[i] == '*' || s[i] == '/' || s[i] == '%')) {
        final o = s[i++];
        final r = _pow();
        v = o == '*' ? v * r : (o == '/' ? v / r : v % r);
      } else {
        return v;
      }
    }
  }

  double _pow() {
    final b = _unary();
    _ws();
    if (i < s.length && s[i] == '^') {
      i++;
      return math.pow(b, _pow()).toDouble();
    }
    return b;
  }

  double _unary() {
    _ws();
    if (i < s.length && s[i] == '-') {
      i++;
      return -_unary();
    }
    if (i < s.length && s[i] == '+') {
      i++;
      return _unary();
    }
    return _atom();
  }

  double _atom() {
    _ws();
    if (i < s.length && s[i] == '(') {
      i++;
      final v = _expr();
      _ws();
      if (i >= s.length || s[i] != ')') throw const FormatException();
      i++;
      return v;
    }
    final st = i;
    while (i < s.length && RegExp(r'[0-9.]').hasMatch(s[i])) {
      i++;
    }
    if (st == i) throw const FormatException();
    return double.parse(s.substring(st, i));
  }
}
