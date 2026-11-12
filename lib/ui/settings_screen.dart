import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_services.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import 'app_filter_screen.dart';
import 'permissions_screen.dart';
import 'profile_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _nick = TextEditingController(text: S.settings.nickname);

  /// Every text in the app follows the APP language (not the Aegis language).
  String _t(String bn, String en) => S.settings.appLang == 'bn' ? bn : en;

  @override
  void dispose() {
    _nick.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ---------------------------------------------------------------- actions

  Future<void> _pickWallpaper() async {
    try {
      final x = await ImagePicker()
          .pickImage(source: ImageSource.gallery, maxWidth: 1080, imageQuality: 80);
      if (x == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final dest = '${dir.path}/wallpaper_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(x.path).copy(dest);
      final old = S.settings.wallpaper;
      await S.settings.setWallpaper(dest);
      if (old != null) {
        try {
          await File(old).delete();
        } catch (_) {}
      }
    } catch (_) {
      _snack(_t('ছবি নেওয়া যায়নি।', 'Could not load the image.'));
    }
  }

  Future<void> _removeWallpaper() async {
    final old = S.settings.wallpaper;
    await S.settings.setWallpaper(null);
    if (old != null) {
      try {
        await File(old).delete();
      } catch (_) {}
    }
  }

  Future<void> _saveNick() async {
    final v = _nick.text.trim();
    if (v.isNotEmpty && !RegExp(r'^[A-Za-z]{2,20}$').hasMatch(v)) {
      _snack(_t('এই নাম শুধু ইংরেজি অক্ষরে (২-২০টা) হতে হবে।',
          'This name must be English letters only (2-20).'));
      return;
    }
    await S.assistant.setNickname(v);
    FocusManager.instance.primaryFocus?.unfocus();
    _snack(v.isEmpty
        ? _t('নাম মুছে ফেলা হয়েছে।', 'Name removed.')
        : _t('এখন "Aegis" বা "$v" বলে ডাকলে সাড়া দেবে।', 'Aegis will now answer to "Aegis" or "$v".'));
  }

  Future<void> _signIn() async {
    final err = await S.auth.signIn();
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    } else if (err != 'cancelled') {
      _snack(_t('Google লগইন হয়নি।', 'Google sign-in failed.'));
    }
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(_t('সাইন আউট করবেন?', 'Sign out?')),
        content: Text(_t('Google Drive-এ সেভ করা ডেটা থেকে যাবে। আবার সাইন ইন করলে ফিরে পাবেন।',
            'Data saved in Google Drive stays safe. Sign in again to get it back.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(_t('না', 'Cancel'))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(_t('সাইন আউট', 'Sign out'))),
        ],
      ),
    );
    if (ok == true) {
      await S.auth.signOut();
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  Future<void> _clearHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(_t('ইতিহাস মুছবেন?', 'Clear history?')),
        content: Text(_t('সব কথোপকথন এই ফোন আর Drive থেকে মুছে যাবে।',
            'All conversations will be removed from this phone and from Drive.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(_t('না', 'Cancel'))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(_t('মুছুন', 'Clear'))),
        ],
      ),
    );
    if (ok == true) await S.memory.clear();
  }

  Future<void> _report() async {
    final uri = Uri(
      scheme: 'mailto',
      path: K.supportEmail,
      query: 'subject=${Uri.encodeComponent('Aegis - problem report')}'
          '&body=${Uri.encodeComponent('Describe the problem:\n\n\n---\nAegis 1.0.0')}',
    );
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok) {
      _snack(_t('Gmail খোলা যায়নি। ইমেইল করুন: ${K.supportEmail}',
          'Could not open Gmail. Email us: ${K.supportEmail}'));
    }
  }

  void _push(Widget w) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));

  // ---------------------------------------------------------------- pieces

  Widget _title(String text, AegisPalette pal) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
        child: Text(text,
            style: TextStyle(
                color: pal.accent, fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 1.6)),
      );

  ImageProvider? _avatarImage() {
    final p = S.auth.profile.photo;
    if (p.isNotEmpty) {
      try {
        return MemoryImage(base64Decode(p));
      } catch (_) {}
    }
    final u = S.auth.user;
    if (S.auth.status == AuthStatus.signedIn && S.auth.method == LoginMethod.google && u?.photo != null) {
      return NetworkImage(u!.photo!);
    }
    return null;
  }

  Widget _profileHeader(AegisPalette pal) {
    final signedIn = S.auth.status == AuthStatus.signedIn;
    final u = S.auth.user;
    final name = signedIn ? (S.auth.callName.isEmpty ? (u?.name ?? '') : S.auth.callName) : '';
    final img = _avatarImage();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: _t('প্রোফাইল', 'Profile'),
              icon: Icon(Icons.account_circle_rounded, color: pal.accent, size: 30),
              onPressed: () {
                if (signedIn) {
                  _push(const ProfileScreen());
                } else {
                  _snack(_t('প্রোফাইল বানাতে আগে সাইন ইন করুন।', 'Sign in first to create a profile.'));
                }
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: pal.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: pal.accent.op(.25)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: pal.accent.op(.2),
                  backgroundImage: signedIn ? img : null,
                  child: signedIn && img != null
                      ? null
                      : Icon(Icons.person_rounded, color: pal.accent, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(signedIn ? (name.isEmpty ? 'Aegis' : name) : _t('গেস্ট মোড', 'Guest mode'),
                          style: TextStyle(color: pal.text, fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(
                        signedIn
                            ? (u?.email ?? '')
                            : _t('Google Drive-এ মেমোরি সেভ করতে সাইন ইন করুন',
                                'Sign in to sync memory with Google Drive'),
                        style: TextStyle(color: pal.subtext, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([S.settings, S.auth, S.assistant]),
      builder: (context, _) {
        final pal = AegisPalette.byId(S.settings.themeId);
        final s = S.settings;
        final signedIn = S.auth.status == AuthStatus.signedIn;
        final drive = S.auth.canUseDrive;
        return Scaffold(
          appBar: AppBar(title: Text(_t('সেটিংস', 'Settings'))),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              _profileHeader(pal),

              // ------------------------------------------------ appearance
              _title(_t('অ্যাপিয়ারেন্স', 'APPEARANCE'), pal),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<String>(
                  showSelectedIcon: true,
                  segments: [
                    ButtonSegment(value: 'cyber', label: Text(AegisPalette.cyber.name)),
                    ButtonSegment(value: 'chalk', label: Text(AegisPalette.chalk.name)),
                  ],
                  selected: {s.themeId},
                  onSelectionChanged: (v) => s.setTheme(v.first),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.wallpaper_rounded),
                title: Text(_t('কাস্টম ওয়ালপেপার', 'Custom wallpaper')),
                subtitle: Text(s.wallpaper == null
                    ? _t('গ্যালারি থেকে ছবি বেছে নিন', 'Pick an image from the gallery')
                    : _t('চালু আছে', 'Active')),
                onTap: _pickWallpaper,
                trailing: s.wallpaper == null
                    ? null
                    : IconButton(icon: const Icon(Icons.close_rounded), onPressed: _removeWallpaper),
              ),
              ListTile(
                leading: const Icon(Icons.blur_on_rounded),
                title: Text(_t('ব্যাকগ্রাউন্ড ঝাপসা: ${s.blur.round()} / 100',
                    'Backdrop blur: ${s.blur.round()} / 100')),
                subtitle: Slider(
                  value: s.blur,
                  min: 0,
                  max: 100,
                  divisions: 100,
                  label: s.blur.round().toString(),
                  onChanged: s.setBlur,
                ),
              ),

              // ------------------------------------------------ languages
              _title(_t('ভাষা', 'LANGUAGE'), pal),
              ListTile(
                leading: const Icon(Icons.translate_rounded),
                title: Text(_t('অ্যাপের ভাষা', 'App language')),
                subtitle: Text(_t('মেনু, বাটন আর সেটিংসের সব লেখা', 'Menus, buttons and all settings text')),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SegmentedButton<String>(
                  showSelectedIcon: true,
                  segments: const [
                    ButtonSegment(value: 'en', label: Text('English')),
                    ButtonSegment(value: 'bn', label: Text('বাংলা')),
                  ],
                  selected: {s.appLang},
                  onSelectionChanged: (v) => s.setAppLang(v.first),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.record_voice_over_rounded),
                title: Text(_t('Aegis-এর ভাষা', 'Aegis language')),
                subtitle: Text(_t('Aegis যে ভাষায় শোনে ও উত্তর দেয়', 'The language Aegis listens and answers in')),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SegmentedButton<String>(
                  showSelectedIcon: true,
                  segments: const [
                    ButtonSegment(value: 'bn', label: Text('বাংলা')),
                    ButtonSegment(value: 'en', label: Text('English')),
                  ],
                  selected: {s.language},
                  onSelectionChanged: (v) => s.setLanguage(v.first),
                ),
              ),

              // ------------------------------------------------ voice
              _title(_t('ভয়েস', 'VOICE'), pal),
              SwitchListTile(
                secondary: const Icon(Icons.volume_up_rounded),
                title: Text(s.male ? _t('পুরুষ কণ্ঠ', 'Male voice') : _t('মহিলা কণ্ঠ', 'Female voice')),
                subtitle: Text(_t('এক ট্যাপে ছেলে/মেয়ে কণ্ঠ বদলান', 'One-tap voice switch')),
                value: s.male,
                onChanged: (v) async {
                  await s.setMale(v);
                  S.assistant.previewVoice();
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: TextField(
                  controller: _nick,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _saveNick(),
                  decoration: InputDecoration(
                    labelText: _t('Aegis-কে ডাকার নাম', 'Name to call Aegis'),
                    helperText: _t(
                        'এটা আপনার নিজের নাম না। "Aegis" বা এই নাম বললে Aegis সাড়া দেবে। যেমন: buddy, friday (ইংরেজি অক্ষরে)।',
                        'This is NOT your own name. Aegis wakes up when you say "Aegis" or this name, e.g. buddy, friday (English letters).'),
                    helperMaxLines: 3,
                    prefixIcon: const Icon(Icons.campaign_outlined),
                    suffixIcon: IconButton(icon: const Icon(Icons.check_rounded), onPressed: _saveNick),
                  ),
                ),
              ),

              // ------------------------------------------------ wake & automation
              _title(_t('ওয়েক ও অটোমেশন', 'WAKE & AUTOMATION'), pal),
              SwitchListTile(
                secondary: const Icon(Icons.hearing_rounded),
                title: Text(_t('ওয়েক ওয়ার্ড "Aegis"', 'Wake word "Aegis"')),
                subtitle: Text(_t('লক স্ক্রিন, গেম বা ভিডিও চলাকালেও শোনে',
                    'Works on the lock screen, in games and videos')),
                value: s.wake,
                onChanged: (v) async {
                  final err = await S.assistant.setWake(v);
                  if (err != null) _snack(err);
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.notifications_active_rounded),
                title: Text(_t('অনুমোদিত অ্যাপের নোটিফিকেশন বলবে', 'Announce allowed notifications')),
                subtitle: Text(_t('শুধু নিচে বেছে নেওয়া অ্যাপ', 'Only the apps you selected below')),
                value: s.announce,
                onChanged: s.setAnnounce,
              ),
              ListTile(
                leading: const Icon(Icons.apps_rounded),
                title: Text(_t('অ্যাপ সিলেকশন ফিল্টার', 'App selection filter')),
                subtitle: Text(_t('${s.whitelist.length}টা অ্যাপ অনুমোদিত', '${s.whitelist.length} app(s) allowed')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _push(const AppFilterScreen()),
              ),
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_rounded),
                title: Text(_t('পারমিশন ও ব্যাকগ্রাউন্ড সেটআপ', 'Permissions & background setup')),
                subtitle: Text(_t('অটো-স্টার্ট, ব্যাটারি, ওভারলে, অ্যাক্সেসিবিলিটি',
                    'Auto-start, battery, overlay, accessibility')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _push(const PermissionsScreen()),
              ),

              // ------------------------------------------------ memory
              _title(_t('মেমোরি', 'MEMORY'), pal),
              ValueListenableBuilder<String>(
                valueListenable: S.memory.syncStatus,
                builder: (context, v, _) => ListTile(
                  leading: const Icon(Icons.cloud_sync_rounded),
                  title: Text(_t('Google Drive সিঙ্ক', 'Google Drive sync')),
                  subtitle: Text(drive
                      ? v
                      : (signedIn
                          ? _t('এই অ্যাকাউন্টে ডেটা শুধু ফোনে থাকে। Drive ব্যাকআপের জন্য Google দিয়ে সাইন ইন করুন।',
                              'Data stays on this phone for this account. Sign in with Google for Drive backup.')
                          : _t('শুধু এই ফোনে (Google দিয়ে সাইন ইন করলে Drive-এ সেভ হবে)',
                              'This phone only (sign in with Google to save to Drive)'))),
                  isThreeLine: signedIn && !drive,
                  trailing: drive
                      ? TextButton(onPressed: S.memory.sync, child: Text(_t('এখনই সিঙ্ক', 'Sync now')))
                      : null,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.delete_sweep_rounded),
                title: Text(_t('কথোপকথনের ইতিহাস মুছুন', 'Clear conversation history')),
                onTap: _clearHistory,
              ),

              // ------------------------------------------------ account
              _title(_t('অ্যাকাউন্ট', 'ACCOUNT'), pal),
              if (signedIn)
                ListTile(
                  leading: const Icon(Icons.logout_rounded),
                  title: Text(_t('সাইন আউট', 'Sign out')),
                  onTap: _signOut,
                )
              else
                ListTile(
                  leading: const Icon(Icons.login_rounded),
                  title: Text(_t('Google দিয়ে সাইন ইন', 'Sign in with Google')),
                  onTap: _signIn,
                ),

              // ------------------------------------------------ report (last)
              _title(_t('সাপোর্ট', 'SUPPORT'), pal),
              ListTile(
                leading: const Icon(Icons.bug_report_rounded),
                title: Text(_t('সমস্যা রিপোর্ট করুন', 'Report a problem')),
                subtitle: Text(K.supportEmail),
                onTap: _report,
              ),
            ],
          ),
        );
      },
    );
  }
}
