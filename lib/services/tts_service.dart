import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../core/constants.dart';
import '../core/settings.dart';
import 'native_bridge.dart';

/// Native Android Google TTS only: free, unlimited, Bangla + English.
class TtsService {
  TtsService(this._native, this._settings);
  final NativeBridge _native;
  final AppSettings _settings;
  final FlutterTts _tts = FlutterTts();

  final ValueNotifier<bool> speaking = ValueNotifier<bool>(false);
  List<Map<String, String>> _voices = [];
  Completer<void>? _cancelSignal;
  bool _cancelled = false;
  String? _appliedKey;

  // Known Google voice codes (best effort). Pitch shifting guarantees an audible male/female switch
  // even when a language ships only one voice.
  static const _maleCodes = ['iom', 'iol', 'tpd', 'rjs', 'gbd', 'bnm'];
  static const _femaleCodes = ['tpf', 'iob', 'tpc', 'sfg', 'gba', 'gbc', 'ban'];

  Future<void> init() async {
    try {
      await _tts.setEngine('com.google.android.tts');
      await _tts.awaitSpeakCompletion(true);
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      try {
        await _tts.setAudioAttributesForNavigation();
      } catch (_) {}
      final v = await _tts.getVoices;
      if (v is List) {
        _voices = v
            .whereType<Map>()
            .map((m) => {'name': '${m['name']}', 'locale': '${m['locale']}'})
            .toList();
      }
    } catch (e) {
      debugPrint('TTS init: $e');
    }
  }

  static bool _isBangla(String s) {
    final total = s.runes.where((r) => r > 32).length;
    if (total == 0) return false;
    final bn = s.runes.where((r) => r >= 0x0980 && r <= 0x09FF).length;
    return bn / total > 0.3;
  }

  static String _clean(String t) => t
      .replaceAll(RegExp(r'[*_#`>~|]'), '')
      .replaceAll(RegExp('[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static List<String> _chunks(String text) {
    final sentences = text.split(RegExp(r'(?<=[.!?\u0964\n])\s+'));
    final out = <String>[];
    var cur = '';
    for (final s in sentences) {
      if (s.trim().isEmpty) continue;
      if (cur.isNotEmpty && cur.length + s.length > 220) {
        out.add(cur);
        cur = s;
      } else {
        cur = cur.isEmpty ? s : '$cur $s';
      }
    }
    if (cur.isNotEmpty) out.add(cur);
    return out;
  }

  Future<void> _prepare(String locale, {bool preferLocal = false}) async {
    final key = '$locale|${_settings.male}|$preferLocal';
    if (key == _appliedKey) return;
    try {
      await _tts.setLanguage(locale);
      await _tts.setPitch(_settings.male ? 0.78 : 1.12);
      final cands = _voices
          .where((v) => v['locale']!.replaceAll('_', '-').toLowerCase() == locale.toLowerCase())
          .toList();
      final codes = _settings.male ? _maleCodes : _femaleCodes;
      Map<String, String>? pick;
      for (final v in cands) {
        final n = v['name']!.toLowerCase();
        if (codes.any((c) => n.contains('-x-$c')) && (!preferLocal || n.contains('local'))) {
          pick = v;
          break;
        }
      }
      if (pick == null && preferLocal) {
        for (final v in cands) {
          if (v['name']!.toLowerCase().contains('local')) {
            pick = v;
            break;
          }
        }
      }
      if (pick != null) {
        await _tts.setVoice({'name': pick['name']!, 'locale': pick['locale']!});
      }
    } catch (e) {
      debugPrint('TTS prepare: $e');
    }
    _appliedKey = key;
  }

  /// Speaks [text]; completes when finished or when [stop] is called.
  Future<void> speak(String text, {bool preferLocal = false}) async {
    final chunks = _chunks(_clean(text));
    if (chunks.isEmpty) return;
    _cancelled = false;
    _cancelSignal = Completer<void>();
    speaking.value = true;
    await _native.duck();
    try {
      for (final c in chunks) {
        if (_cancelled) break;
        await _prepare(_isBangla(c) ? 'bn-BD' : 'en-US', preferLocal: preferLocal);
        if (_cancelled) break;
        await Future.any<Object?>([_tts.speak(c), _cancelSignal!.future]);
      }
    } catch (e) {
      debugPrint('TTS speak: $e');
    } finally {
      speaking.value = false;
      await _native.abandonFocus();
    }
  }

  /// Immediately kills the TTS stream.
  Future<void> stop() async {
    _cancelled = true;
    final c = _cancelSignal;
    if (c != null && !c.isCompleted) c.complete();
    try {
      await _tts.stop();
    } catch (_) {}
  }

  /// Offline emergency line, spoken with a local (offline) voice.
  Future<void> speakOfflineAlert() async {
    await stop();
    _appliedKey = null;
    await speak(K.offlineLine, preferLocal: true);
  }
}
