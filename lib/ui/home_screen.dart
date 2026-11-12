import 'package:flutter/material.dart';

import '../core/app_services.dart';
import '../core/theme.dart';
import '../services/assistant_controller.dart';
import 'backdrop.dart';
import 'orb_view.dart';
import 'settings_screen.dart';

/// Main screen: settings icon, orb (tap once = Aegis ON, tap again = OFF), ON/OFF status, text box.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _text = TextEditingController();

  String _t(String bn, String en) => S.settings.appLang == 'bn' ? bn : en;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final t = _text.text;
    _text.clear();
    S.assistant.sendText(t);
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }

  Future<void> _toggle() async {
    final err = await S.assistant.toggleActive();
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  String _stateLabel(AssistantState s) {
    switch (s) {
      case AssistantState.idle:
        return '';
      case AssistantState.listening:
        return _t('শুনছি...', 'Listening...');
      case AssistantState.thinking:
        return _t('ভাবছি...', 'Thinking...');
      case AssistantState.speaking:
        return _t('বলছি • থামাতে চাপ দিন', 'Speaking • tap to stop');
      case AssistantState.offline:
        return _t('অফলাইন', 'Offline');
    }
  }

  Widget _statusPill(AegisPalette pal, bool on) {
    final nick = S.settings.nickname;
    final onText = nick.isEmpty
        ? _t('চালু • "Aegis" বলে ডাকুন', 'ON • say "Aegis"')
        : _t('চালু • "Aegis" বা "$nick" বলুন', 'ON • say "Aegis" or "$nick"');
    final offText = _t('বন্ধ • চালু করতে অরবে চাপ দিন', 'OFF • tap the orb to turn on');
    final color = on ? pal.listen : pal.subtext;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: color.op(.14),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.op(.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: on ? [BoxShadow(color: color.op(.7), blurRadius: 8)] : null,
            ),
          ),
          const SizedBox(width: 10),
          Text(on ? onText : offText,
              style: TextStyle(color: pal.text, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([S.settings, S.assistant]),
      builder: (context, _) {
        final pal = AegisPalette.byId(S.settings.themeId);
        final a = S.assistant;
        final on = S.settings.wake;
        final label = _stateLabel(a.orbState);
        final caption = a.state == AssistantState.idle && a.lastReply.isNotEmpty ? a.lastReply : label;
        return Scaffold(
          resizeToAvoidBottomInset: true,
          body: Stack(
            children: [
              const Positioned.fill(child: Backdrop()),
              SafeArea(
                child: Column(
                  children: [
                    SizedBox(
                      height: 56,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: IconButton(
                            tooltip: _t('সেটিংস', 'Settings'),
                            icon: Icon(Icons.settings_rounded, color: pal.text.op(.8), size: 26),
                            onPressed: _openSettings,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: a.state == AssistantState.speaking ? a.stopSpeaking : _toggle,
                        child: Column(
                          children: [
                            Expanded(child: OrbView(state: a.orbState, palette: pal)),
                            _statusPill(pal, on),
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 28),
                              child: Text(
                                caption,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: pal.subtext, fontSize: 14, height: 1.35),
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: TextField(
                        controller: _text,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        style: TextStyle(color: pal.text),
                        decoration: InputDecoration(
                          hintText: _t('Aegis-কে লিখুন...', 'Message Aegis...'),
                          hintStyle: TextStyle(color: pal.subtext),
                          filled: true,
                          fillColor: pal.surface.op(pal.dark ? .72 : .9),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: BorderSide(color: pal.accent.op(.35)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: BorderSide(color: pal.accent.op(.25)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: BorderSide(color: pal.accent, width: 1.4),
                          ),
                          prefixIcon: IconButton(
                            tooltip: _t('একবার বলুন', 'Talk once'),
                            icon: Icon(Icons.mic_rounded, color: pal.accent),
                            onPressed: S.assistant.startVoiceTurn,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(Icons.arrow_upward_rounded, color: pal.accent),
                            onPressed: _send,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
