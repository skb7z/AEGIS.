import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as st;

import '../core/errors.dart';

/// Speech-to-text through Android's built-in recognizer: free, no API key, Bangla + English.
class SttService {
  final st.SpeechToText _s = st.SpeechToText();
  bool _ready = false;
  List<st.LocaleName> _locales = const [];
  Completer<String>? _c;
  String _last = '';
  DateTime _startedAt = DateTime.fromMillisecondsSinceEpoch(0);

  void _finish() {
    final c = _c;
    if (c != null && !c.isCompleted) c.complete(_last);
  }

  Future<bool> _init() async {
    if (_ready) return true;
    try {
      _ready = await _s.initialize(
        onError: (e) {
          debugPrint('STT error: ${e.errorMsg}');
          _finish();
        },
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            // Ignore stale status events that arrive right after a new session starts.
            if (DateTime.now().difference(_startedAt).inMilliseconds < 800) return;
            Future<void>.delayed(const Duration(milliseconds: 250), _finish);
          }
        },
      );
      if (_ready) _locales = await _s.locales();
    } catch (e) {
      debugPrint('STT init: $e');
      _ready = false;
    }
    return _ready;
  }

  String _localeFor(String lang) {
    final ids = _locales.map((l) => l.localeId).toList();
    String? pick(bool Function(String) f) {
      for (final i in ids) {
        if (f(i)) return i;
      }
      return null;
    }

    if (lang == 'bn') {
      return pick((i) => i.toLowerCase().startsWith('bn_bd')) ??
          pick((i) => i.toLowerCase().startsWith('bn')) ??
          'bn_BD';
    }
    return pick((i) => i.toLowerCase() == 'en_us') ??
        pick((i) => i.toLowerCase().startsWith('en')) ??
        'en_US';
  }

  /// Listens for one utterance. Returns '' when nothing was heard.
  Future<String> listenOnce(String lang) async {
    if (!await _init()) throw const ApiFailure('stt_unavailable');
    _last = '';
    final c = Completer<String>();
    _c = c;
    _startedAt = DateTime.now();
    try {
      await _s.listen(
        onResult: (r) {
          _last = r.recognizedWords;
          if (r.finalResult) _finish();
        },
        localeId: _localeFor(lang),
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 2),
        listenOptions: st.SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: st.ListenMode.dictation,
        ),
      );
    } catch (e) {
      debugPrint('STT listen: $e');
      _c = null;
      throw const ApiFailure('stt_unavailable');
    }
    final guard = Timer(const Duration(seconds: 25), _finish);
    try {
      return (await c.future).trim();
    } finally {
      guard.cancel();
      _c = null;
      try {
        await _s.stop();
      } catch (_) {}
    }
  }

  Future<void> cancel() async {
    try {
      await _s.cancel();
    } catch (_) {}
    _finish();
  }
}
