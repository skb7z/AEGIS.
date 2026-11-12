import 'package:flutter/material.dart';

import '../core/app_services.dart';
import '../core/theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;
  String? _error;

  String _t(String bn, String en) => S.settings.language == 'bn' ? bn : en;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await S.auth.signIn();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err == null || err == 'cancelled'
          ? null
          : _t('Google লগইন হয়নি। ইন্টারনেট দেখুন, অথবা গেস্ট হিসেবে চালিয়ে যান।',
              'Google sign-in failed. Check your internet, or continue as guest.');
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: S.settings,
      builder: (context, _) {
        final pal = AegisPalette.byId(S.settings.themeId);
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield_outlined, size: 84, color: pal.accent),
                    const SizedBox(height: 14),
                    Text('AEGIS',
                        style: TextStyle(
                            color: pal.text,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 6)),
                    const SizedBox(height: 28),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'bn', label: Text('বাংলা')),
                        ButtonSegment(value: 'en', label: Text('English')),
                      ],
                      selected: {S.settings.language},
                      showSelectedIcon: false,
                      onSelectionChanged: (v) => S.settings.setLanguage(v.first),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      _t('আপনার ফোনের Google অ্যাকাউন্ট দিয়ে সাইন ইন করুন। আপনার প্রোফাইল, সেটিংস আর কথোপকথন আপনার Google Drive-এ নিরাপদে সেভ থাকবে, অ্যাপ মুছে ফেললেও হারাবে না।',
                          'Sign in with a Google account on this phone. Your profile, settings and conversations are saved privately to your Google Drive, so nothing is lost even if you delete the app.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: pal.subtext, height: 1.45),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _signIn,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.login_rounded),
                        label: Text(_t('Google দিয়ে সাইন ইন', 'Sign in with Google')),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy ? null : S.auth.skip,
                      child: Text(_t('গেস্ট হিসেবে চালিয়ে যান', 'Continue as guest'),
                          style: TextStyle(color: pal.subtext)),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFFF5252), fontSize: 13)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
