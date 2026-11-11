import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/errors.dart';
import '../core/settings.dart';
import 'ai_service.dart';
import 'auth_service.dart';
import 'memory_service.dart';
import 'native_bridge.dart';
import 'stt_service.dart';
import 'tools_service.dart';
import 'tts_service.dart';

enum AssistantState { idle, listening, thinking, speaking, offline }

/// wake word / tap -> listen -> AI (with tools) -> speak -> optional follow-ups.
class AssistantController extends ChangeNotifier {
  AssistantController({
    required this.settings,
    required this.native,
    required this.tts,
    required this.stt,
    required this.ai,
    required this.memory,
    required this.tools,
    required this.auth,
  });

  final AppSettings settings;
  final NativeBridge native;
  final TtsService tts;
  final SttService stt;
  final AiService ai;
  final MemoryService memory;
  final ToolsService tools;
  final AuthService auth;

  AssistantState state = AssistantState.idle;
  String lastUser = '';
  String lastReply = '';
  bool online = true;

  bool _busy = false;
  DateTime _lastOfflineAlert = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastNotifPkg;
  String _lastNotifKey = '';
  DateTime _lastNotifAt = DateTime.fromMillisecondsSinceEpoch(0);
  final List<StreamSubscription<dynamic>> _subs = [];

  String tr(String bn, String en) => settings.language == 'bn' ? bn : en;

  AssistantState get orbState =>
      (!online && state == AssistantState.idle) ? AssistantState.offline : state;

  void _set(AssistantState s) {
    state = s;
    notifyListeners();
  }

  Future<void> init() async {
    try {
      await memory.init();
      await tts.init();
      _subs.add(native.onWake.listen((_) => startVoiceTurn()));
      _subs.add(native.onStopWord.listen((_) => stopSpeaking()));
      _subs.add(native.onNotification.listen(_onNotification));
      _subs.add(Connectivity().onConnectivityChanged.listen(_onConnectivity));
      await native.init();
      await native.setWhitelist(settings.whitelist.toList());
      await native.setNickname(settings.nickname);
      if (settings.wake) await native.startService();
      final c = await Connectivity().checkConnectivity();
      online = !_isOffline(c);
      notifyListeners();
    } catch (e) {
      debugPrint('Assistant init: $e');
    }
  }

  // ---------------------------------------------------------------- connectivity

  bool _isOffline(List<ConnectivityResult> r) =>
      r.isEmpty || r.every((e) => e == ConnectivityResult.none);

  void _onConnectivity(List<ConnectivityResult> r) {
    final off = _isOffline(r);
    if (off && online) {
      online = false;
      notifyListeners();
      unawaited(_goOffline());
    } else if (!off && !online) {
      online = true;
      notifyListeners();
    }
  }

  Future<void> _goOffline() async {
    online = false;
    notifyListeners();
    final now = DateTime.now();
    if (now.difference(_lastOfflineAlert) < const Duration(seconds: 20)) return;
    _lastOfflineAlert = now;
    lastReply = tr('ইন্টারনেট সংযোগ নেই। মোবাইল ডাটা বা ওয়াইফাই চালু করুন।',
        'Internet connection is lost. Please enable mobile data.');
    _set(AssistantState.speaking);
    try {
      await tts.stop();
      await tts.speak(lastReply, preferLocal: true);
    } catch (_) {}
    if (!_busy) _set(AssistantState.idle);
  }

  // ---------------------------------------------------------------- public actions

  /// Orb tap: ON <-> OFF. ON keeps Aegis listening for its name in the background (persisted).
  Future<String?> toggleActive() => setWake(!settings.wake);

  Future<void> stopSpeaking() async => tts.stop();

  /// Starts one conversation (wake word or mic button). Follow-ups continue only while ON.
  Future<void> startVoiceTurn() async {
    if (_busy) {
      if (state == AssistantState.speaking) {
        await stopSpeaking();
      } else if (state == AssistantState.listening) {
        await stt.cancel();
      }
      return;
    }
    await _runTurn(() async {
      var rounds = 0;
      while (true) {
        _set(AssistantState.listening);
        await native.duck(); // game / video volume goes down while we talk
        final text = await stt.listenOnce(settings.language);
        if (text.isEmpty) break;
        _set(AssistantState.thinking);
        await _handleText(text);
        rounds++;
        if (!settings.wake || rounds >= 3) break;
      }
    });
  }

  Future<void> sendText(String raw) async {
    final t = raw.trim();
    if (t.isEmpty) return;
    if (_busy) {
      if (state != AssistantState.speaking) return;
      await stopSpeaking();
      for (var i = 0; i < 20 && _busy; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (_busy) return;
    }
    await _runTurn(() async {
      _set(AssistantState.thinking);
      await _handleText(t);
    });
  }

  Future<void> previewVoice() async {
    if (_busy) return;
    _busy = true;
    try {
      _set(AssistantState.speaking);
      await tts.speak(settings.male
          ? tr('পুরুষ কণ্ঠ বেছে নেওয়া হয়েছে।', 'Male voice selected.')
          : tr('মহিলা কণ্ঠ বেছে নেওয়া হয়েছে।', 'Female voice selected.'));
    } finally {
      _busy = false;
      _set(AssistantState.idle);
    }
  }

  /// Turns the always-on wake word ON/OFF. Returns an error text or null.
  Future<String?> setWake(bool on) async {
    if (on) {
      final st = await Permission.microphone.request();
      if (!st.isGranted) {
        return tr('ওয়েক ওয়ার্ডের জন্য মাইক্রোফোন পারমিশন লাগবে।',
            'Microphone permission is required for the wake word.');
      }
      await Permission.notification.request();
      await settings.setWake(true);
      await native.startService();
    } else {
      await settings.setWake(false);
      await native.stopService();
    }
    notifyListeners();
    return null;
  }

  Future<void> setNickname(String v) async {
    await settings.setNickname(v);
    await native.setNickname(v);
  }

  // ---------------------------------------------------------------- turn runner

  Future<void> _runTurn(Future<void> Function() body) async {
    _busy = true;
    try {
      await native.pauseWake();
      await body();
      if (!online) {
        online = true;
        notifyListeners();
      }
    } on NetworkFailure {
      await _goOffline();
    } on ApiFailure catch (e) {
      await _say(_failureText(e.message));
    } catch (e, s) {
      debugPrint('Turn error: $e\n$s');
      await _say(tr('দুঃখিত, কিছু একটা সমস্যা হয়েছে।', 'Sorry, something went wrong.'));
    } finally {
      _busy = false;
      _set(AssistantState.idle);
      await native.abandonFocus();
      if (settings.wake) await native.resumeWake();
    }
  }

  String _failureText(String code) {
    switch (code) {
      case 'stt_unavailable':
        return tr(
            'ভয়েস শোনা যাচ্ছে না। ফোনে Google অ্যাপ আর মাইক্রোফোন পারমিশন চালু আছে কিনা দেখুন, অথবা লিখে বলুন।',
            'I cannot hear you. Please check the Google app and microphone permission, or type your message.');
      case 'ai_busy':
        return tr('এই মুহূর্তে এআই সার্ভিস ব্যস্ত, একটু পরে আবার বলুন।',
            'The AI service is busy right now. Please try again shortly.');
      default:
        return code;
    }
  }

  Future<void> _say(String text) async {
    try {
      await _speakReply(text);
    } catch (_) {}
  }

  Future<void> _speakReply(String text) async {
    lastReply = text;
    _set(AssistantState.speaking);
    await native.startStopListener(); // saying "stop" silences Aegis instantly
    try {
      await tts.speak(text);
    } finally {
      await native.pauseWake();
    }
  }

  // ---------------------------------------------------------------- understanding

  static const _stopPhrases = {
    'stop', 'thamo', 'stop it', 'be quiet', 'shut up', 'quiet',
    'থামো', 'থামুন', 'থাম', 'চুপ',
  };

  bool _isStop(String low) {
    final t = low.replaceAll(RegExp(r'[.!?।]'), '').trim();
    if (_stopPhrases.contains(t)) return true;
    final words = t.split(RegExp(r'\s+'));
    return words.length <= 2 && (words.first == 'stop' || words.first == 'thamo');
  }

  bool _isVision(String low) {
    const keys = [
      'screenshot', 'my screen', 'on screen', 'on the screen', 'look at this screen',
      'what do you see', 'what is on my', 'স্ক্রিন', 'স্ক্রীন',
    ];
    return keys.any(low.contains);
  }

  String? _systemAction(String low) {
    final t = low.replaceAll(RegExp(r'[.!?।]'), '').trim();
    const map = {
      'go home': 'home', 'home': 'home', 'go to home screen': 'home', 'হোমে যাও': 'home',
      'go back': 'back', 'back': 'back', 'পিছনে যাও': 'back', 'ব্যাক': 'back',
      'recent apps': 'recents', 'show recent apps': 'recents', 'recents': 'recents',
      'open notifications': 'notifications', 'show notifications': 'notifications',
      'quick settings': 'quick_settings',
      'lock screen': 'lock', 'lock the screen': 'lock', 'lock phone': 'lock', 'ফোন লক করো': 'lock',
    };
    return map[t];
  }

  Future<void> _handleText(String text) async {
    lastUser = text;
    notifyListeners();
    final low = text.toLowerCase().trim();

    if (_isStop(low)) {
      await stopSpeaking();
      return;
    }

    final replyMatch =
        RegExp(r'^(reply|রিপ্লাই)\s+(.+)$', caseSensitive: false).firstMatch(text.trim());
    if (replyMatch != null) {
      final pkg = _lastNotifPkg;
      if (pkg == null) {
        await _speakReply(tr('উত্তর দেওয়ার মতো কোনো সাম্প্রতিক মেসেজ নেই।',
            'There is no recent message from an allowed app to reply to.'));
        return;
      }
      final ok = await native.replyToNotification(pkg, replyMatch.group(2)!.trim());
      await _speakReply(ok
          ? tr('রিপ্লাই পাঠানো হয়েছে।', 'Reply sent.')
          : tr('রিপ্লাই পাঠানো গেল না। ওই অ্যাপ কুইক রিপ্লাই সাপোর্ট করে না।',
              'I could not send the reply. That app does not allow quick replies.'));
      return;
    }

    final action = _systemAction(low);
    if (action != null) {
      final ok = await native.globalAction(action);
      await _speakReply(ok
          ? tr('হয়ে গেছে।', 'Done.')
          : tr('আগে Aegis-এর অ্যাক্সেসিবিলিটি সার্ভিস চালু করুন।',
              'Please enable the Aegis accessibility service first.'));
      return;
    }

    if (_isVision(low)) {
      await _vision(text);
      return;
    }

    _set(AssistantState.thinking);
    final reply = await ai.chat(memory.context, text, settings.language);
    if (reply.isEmpty) throw const ApiFailure('ai_busy');
    await memory.add('user', text);
    await memory.add('model', reply);
    await _speakReply(reply);
  }

  /// One screenshot, sent to the AI, then wiped from disk and image cache.
  Future<void> _vision(String question) async {
    _set(AssistantState.thinking);
    final path = await native.captureScreenshot(); // throws ApiFailure on denial
    String reply;
    try {
      final bytes = await File(path).readAsBytes();
      reply = await ai.vision(bytes, question, settings.language);
    } finally {
      _deleteQuiet(path);
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    }
    if (reply.isEmpty) throw const ApiFailure('ai_busy');
    await memory.add('user', '[screen] $question');
    await memory.add('model', reply);
    await _speakReply(reply);
  }

  void _deleteQuiet(String path) {
    try {
      File(path).deleteSync();
    } catch (_) {}
  }

  // ---------------------------------------------------------------- notifications

  /// Only whitelisted apps ever reach here (filtered natively before any content is read).
  void _onNotification(Map<String, String> n) {
    _lastNotifPkg = n['pkg'];
    tools.addNotification('${n['app']}: ${n['title']} - ${n['text']}');
    if (!settings.announce || _busy) return;
    final key = '${n['pkg']}|${n['title']}|${n['text']}';
    final now = DateTime.now();
    if (key == _lastNotifKey && now.difference(_lastNotifAt) < const Duration(seconds: 6)) return;
    _lastNotifKey = key;
    _lastNotifAt = now;
    var msg = tr('${n['app']}-এ ${n['title']}-এর নতুন মেসেজ। ${n['text']}',
        'New message on ${n['app']} from ${n['title']}. ${n['text']}');
    if (msg.length > 240) msg = msg.substring(0, 240);
    unawaited(_runTurn(() => _speakReply(msg)));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
