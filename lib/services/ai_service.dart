import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../core/errors.dart';
import 'auth_service.dart';
import 'tools_service.dart';

/// The brain: a free key-less chat model + an OpenJarvis-style tool loop.
/// Speed: plain questions go out as ONE short request; the tool instructions are only sent
/// when the message looks like it needs a tool (weather, time, calc, open app, ...).
class AiService {
  AiService(this._tools, this._auth);
  final ToolsService _tools;
  final AuthService _auth;

  int _good = 0; // index of the last endpoint/model combo that worked
  static const _maxSteps = 3;

  static final RegExp _toolHint = RegExp(
    r'weather|temperature|forecast|\btime\b|\bdate\b|what day|calculat|\d\s*[+\-*/x×÷^%]\s*\d|'
    r'\bplus\b|\bminus\b|multipl|divid|\bopen\b|launch|timer|alarm|notification|wikipedia|'
    r'who is|who was|tell me about|search|'
    r'আবহাওয়া|তাপমাত্রা|সময়|তারিখ|হিসাব|যোগ|বিয়োগ|গুণ|ভাগ|খুল|টাইমার|অ্যালার্ম|এলার্ম|নোটিফিকেশন|সম্পর্কে|কে ছিল',
    caseSensitive: false,
  );

  String _system(String lang, bool tools) {
    final b = StringBuffer("You are AEGIS, a fast, loyal personal voice assistant on the user's phone. ");
    final p = _auth.profileText;
    if (p.isNotEmpty) b.write('$p ');
    b.write('Your replies are SPOKEN: 1-3 short sentences, no markdown, no lists, no emojis. ');
    b.write(lang == 'bn'
        ? 'Always answer in Bangla script. '
        : 'Always answer in English. ');
    if (tools) {
      b.write(
        'To use a tool reply with EXACTLY one line: TOOL: <name> | <argument>. '
        'Tools: time | (empty); weather | city (empty = user home country); wiki | topic; '
        'calc | math expression; open_app | app name; timer | minutes; alarm | HH:MM (24h); '
        'notifications | (empty). Use a tool only when really needed. ',
      );
    }
    b.write('Never claim to have done something you cannot do.');
    return b.toString();
  }

  List<Map<String, String>> _normalize(List<Map<String, String>> h) {
    final out = <Map<String, String>>[];
    for (final m in h) {
      final role = m['role'] == 'user' ? 'user' : 'assistant';
      final text = m['text'] ?? '';
      if (text.trim().isEmpty) continue;
      if (out.isEmpty && role != 'user') continue;
      if (out.isNotEmpty && out.last['role'] == role) {
        out.last = {'role': role, 'text': '${out.last['text']}\n$text'};
      } else {
        out.add({'role': role, 'text': text});
      }
    }
    if (out.isNotEmpty && out.last['role'] == 'user') out.removeLast();
    // Only the last few turns: smaller request = faster answer.
    var recent = out.length > 8 ? out.sublist(out.length - 8) : out;
    if (recent.isNotEmpty && recent.first['role'] != 'user') recent = recent.sublist(1);
    return recent;
  }

  Future<String> chat(List<Map<String, String>> history, String text, String lang) async {
    final useTools = _toolHint.hasMatch(text);
    final msgs = <Map<String, dynamic>>[
      {'role': 'system', 'content': _system(lang, useTools)},
      for (final h in _normalize(history)) {'role': h['role'], 'content': h['text']},
      {'role': 'user', 'content': text},
    ];
    if (!useTools) return _clean(await _complete(msgs));

    for (var step = 0; step <= _maxSteps; step++) {
      final out = await _complete(msgs);
      final call = _parseTool(out);
      if (call == null || step == _maxSteps) return _clean(out);
      final result = await _tools.run(call.$1, call.$2, lang);
      msgs.add({'role': 'assistant', 'content': out});
      msgs.add({
        'role': 'user',
        'content': 'TOOL RESULT (${call.$1}): $result\n'
            'Now answer the user briefly, as speech, in their language. Do not call another tool.',
      });
    }
    return '';
  }

  /// One-shot question about a small screenshot.
  Future<String> vision(Uint8List jpeg, String question, String lang) async {
    final msgs = <Map<String, dynamic>>[
      {'role': 'system', 'content': _system(lang, false)},
      {
        'role': 'user',
        'content': [
          {
            'type': 'text',
            'text':
                'The image is a screenshot of my phone screen right now. Answer briefly, as speech. My request: $question'
          },
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/jpeg;base64,${base64Encode(jpeg)}'}
          },
        ],
      },
    ];
    return _clean(await _complete(msgs, vision: true));
  }

  (String, String)? _parseTool(String out) {
    final m = RegExp(r'^\s*TOOL:\s*([a-z_]+)\s*\|?\s*(.*)$', multiLine: true).firstMatch(out);
    if (m == null) return null;
    return (m.group(1)!, (m.group(2) ?? '').trim());
  }

  String _clean(String t) => t
      .replaceAll(RegExp(r'^\s*TOOL:.*$', multiLine: true), '')
      .replaceAll(RegExp(r'[*_#`]'), '')
      .trim();

  Future<String> _complete(List<Map<String, dynamic>> msgs, {bool vision = false}) async {
    final models = vision ? K.aiVisionModels : K.aiModels;
    final combos = <(String, String)>[
      for (final m in models)
        for (final e in K.aiEndpoints) (e, m),
    ];
    final first = vision ? 0 : _good % combos.length;
    var reached = false;
    for (var k = 0; k < combos.length && k < 4; k++) {
      final i = (first + k) % combos.length;
      final (ep, model) = combos[i];
      try {
        final r = await http
            .post(
              Uri.parse(ep),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'model': model,
                'messages': msgs,
                'temperature': 0.6,
                'max_tokens': vision ? 300 : 180,
                'private': true,
              }),
            )
            .timeout(Duration(seconds: vision ? 20 : 12));
        reached = true;
        if (r.statusCode == 200) {
          final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
          final msg = ((j['choices'] as List).first as Map)['message'] as Map;
          final out = '${msg['content'] ?? ''}'.trim();
          if (out.isNotEmpty) {
            if (!vision) _good = i;
            return out;
          }
        } else {
          debugPrint('AI $ep $model -> ${r.statusCode}');
        }
      } on SocketException {
        // try next
      } on TimeoutException {
        // try next
      } on http.ClientException {
        // try next
      } catch (e) {
        reached = true;
        debugPrint('AI parse error: $e');
      }
    }
    if (!reached) throw const NetworkFailure('ai');
    throw const ApiFailure('ai_busy');
  }
}
