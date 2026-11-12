import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/app_services.dart';
import '../core/theme.dart';

class _Step {
  const _Step(this.id, this.icon, this.bnTitle, this.enTitle, this.bnSub, this.enSub);
  final String id;
  final IconData icon;
  final String bnTitle;
  final String enTitle;
  final String bnSub;
  final String enSub;
}

/// Guided setup for every phone brand (Redmi, Samsung, Realme, Infinix, ...).
/// Each step opens the brand-specific screen when it exists, otherwise the plain App info page.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> with WidgetsBindingObserver {
  static const _all = [
    _Step('mic', Icons.mic_rounded, 'মাইক্রোফোন', 'Microphone',
        'ভয়েস কমান্ড আর ওয়েক ওয়ার্ডের জন্য', 'For voice commands and the wake word'),
    _Step('restricted', Icons.lock_open_rounded, 'সীমাবদ্ধ সেটিংস অনুমতি (Android 13+)',
        'Allow restricted settings (Android 13+)',
        'App info খুলবে → উপরে ডানে ⋮ চাপুন → "Allow restricted settings" দিন। এটা না দিলে নিচের অ্যাক্সেসিবিলিটি আর নোটিফিকেশন বাটন ধূসর থাকে।',
        'Opens App info → tap ⋮ (top right) → "Allow restricted settings". Without this, the Accessibility and Notification switches stay greyed out.'),
    _Step('autostart', Icons.rocket_launch_rounded, 'অটো-স্টার্ট', 'Auto-start',
        'ফোন রিস্টার্টের পর Aegis নিজে চালু হবে', 'Aegis starts itself after a reboot'),
    _Step('battery', Icons.battery_charging_full_rounded, 'ব্যাটারি অপ্টিমাইজেশন বন্ধ',
        'Ignore battery optimization', 'ব্যাকগ্রাউন্ডে Aegis বন্ধ হয়ে যাওয়া আটকায়',
        'Stops the system from killing Aegis in the background'),
    _Step('overlay', Icons.layers_rounded, 'অন্য অ্যাপের উপরে দেখানো', 'Display over other apps',
        'লক স্ক্রিন বা গেমের সময় ডাকলে Aegis সামনে আসতে পারবে',
        'Lets Aegis come to the front from the lock screen or a game'),
    _Step('accessibility', Icons.accessibility_new_rounded, 'অ্যাক্সেসিবিলিটি সার্ভিস',
        'Accessibility service', 'ব্যাক / হোম / রিসেন্ট ভয়েস কমান্ডের জন্য',
        'For Back / Home / Recents voice actions'),
    _Step('notification', Icons.notifications_rounded, 'নোটিফিকেশন অ্যাক্সেস', 'Notification access',
        'শুধু আপনার বেছে নেওয়া অ্যাপের নোটিফিকেশন পড়বে', 'Reads notifications from allowed apps only'),
  ];

  Map<String, bool> _ok = {};
  int _sdk = 0;
  bool _restrictedTapped = false;
  bool _running = false;
  Completer<void>? _resume;

  String _t(String bn, String en) => S.settings.appLang == 'bn' ? bn : en;

  List<_Step> get _steps => _all.where((s) => s.id != 'restricted' || _sdk >= 33).toList();

  bool get _allOk => _ok.isNotEmpty && _steps.every((s) => _ok[s.id] == true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final c = _resume;
      if (c != null && !c.isCompleted) c.complete();
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final st = await S.native.status();
    final mic = await Permission.microphone.isGranted;
    if (!mounted) return;
    final acc = st['accessibility'] == true;
    final nl = st['notification'] == true;
    setState(() {
      _sdk = (st['sdk'] is int) ? st['sdk'] as int : 0;
      _ok = {
        'mic': mic,
        'restricted': _restrictedTapped || acc || nl,
        'autostart': S.settings.autostartDone,
        'battery': st['battery'] == true,
        'overlay': st['overlay'] == true,
        'accessibility': acc,
        'notification': nl,
      };
    });
  }

  Future<void> _request(String id) async {
    switch (id) {
      case 'mic':
        await Permission.microphone.request();
        await Permission.notification.request();
        break;
      case 'restricted':
        _restrictedTapped = true;
        await S.native.openSetting('appinfo');
        break;
      case 'autostart':
        await S.native.openSetting('autostart');
        await S.settings.setAutostartDone(true);
        break;
      default:
        await S.native.openSetting(id);
    }
    await _refresh();
  }

  Future<void> _guided() async {
    if (_running) return;
    setState(() => _running = true);
    for (final s in _steps) {
      await _refresh();
      if (_ok[s.id] == true) continue;
      if (!mounted) break;
      await _request(s.id);
      if (s.id != 'mic') {
        _resume = Completer<void>();
        await _resume!.future.timeout(const Duration(minutes: 3), onTimeout: () {});
      }
    }
    await _refresh();
    if (mounted) setState(() => _running = false);
  }

  String _engineText(String v) {
    if (v == 'ready') return _t('ওয়েক ইঞ্জিন প্রস্তুত', 'Wake engine ready');
    if (v == 'loading') return _t('ওয়েক ইঞ্জিন লোড হচ্ছে...', 'Loading wake engine...');
    if (v == 'missing') {
      return _t('Vosk মডেল নেই - GitHub workflow দিয়ে APK বানান', 'Vosk model missing - build the APK with the GitHub workflow');
    }
    if (v.startsWith('error')) return v;
    return _t('ওয়েক ইঞ্জিন নিষ্ক্রিয়', 'Wake engine idle');
  }

  @override
  Widget build(BuildContext context) {
    final pal = AegisPalette.byId(S.settings.themeId);
    return Scaffold(
      appBar: AppBar(title: Text(_t('পারমিশন ও ব্যাকগ্রাউন্ড', 'Permissions & background'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (_allOk)
            Card(
              color: pal.listen.op(.14),
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: Icon(Icons.verified_rounded, color: pal.listen, size: 30),
                title: Text(_t('সব সেটআপ সম্পূর্ণ', 'All set'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(_t('সব পারমিশন দেওয়া আছে। আর কিছু করতে হবে না।',
                    'Every permission is granted. Nothing more to do.')),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FilledButton.icon(
                onPressed: _running ? null : _guided,
                icon: _running
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.playlist_add_check_rounded),
                label: Text(_t('ধাপে ধাপে সেটআপ শুরু করুন', 'Run guided setup')),
              ),
            ),
          for (final s in _steps)
            Card(
              color: pal.surface,
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: Icon(s.icon),
                title: Text(_t(s.bnTitle, s.enTitle)),
                subtitle: Text(_t(s.bnSub, s.enSub)),
                isThreeLine: s.id == 'restricted',
                trailing: _ok[s.id] == true
                    ? Icon(Icons.check_circle_rounded, color: pal.listen)
                    : TextButton(onPressed: () => _request(s.id), child: Text(_t('অনুমতি', 'Grant'))),
              ),
            ),
          Card(
            color: pal.surface,
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 10),
            child: ListenableBuilder(
              listenable: S.settings,
              builder: (context, _) => ValueListenableBuilder<String>(
                valueListenable: S.native.wakeStatus,
                builder: (context, v, _) => SwitchListTile(
                  secondary: const Icon(Icons.hearing_rounded),
                  title: Text(_t('ওয়েক ওয়ার্ড ইঞ্জিন', 'Wake word engine')),
                  subtitle: Text(_engineText(v)),
                  value: S.settings.wake,
                  onChanged: (on) async {
                    final err = await S.assistant.setWake(on);
                    if (err != null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                    }
                  },
                ),
              ),
            ),
          ),
          Card(
            color: pal.surface,
            elevation: 0,
            child: ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: Text(_t('App info-তে সব পারমিশন কেন নেই?', 'Why are some permissions missing in App info?')),
              subtitle: Text(_t(
                  'শুধু মাইক্রোফোন আর নোটিফিকেশনের মতো সাধারণ পারমিশন App info → Permissions-এ দেখায়। ওভারলে, অ্যাক্সেসিবিলিটি, নোটিফিকেশন অ্যাক্সেস, ব্যাটারি আর অটো-স্টার্ট Android-এর আলাদা "বিশেষ অ্যাক্সেস" পেজে থাকে, তাই ওগুলো এই পেজ থেকেই দিতে হবে।',
                  'Only normal permissions like Microphone and Notifications appear under App info → Permissions. Overlay, Accessibility, Notification access, Battery and Auto-start are Android "special access" pages, so grant those from this screen.')),
              isThreeLine: true,
              trailing: TextButton(
                onPressed: () => S.native.openSetting('appinfo'),
                child: const Text('App info'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
