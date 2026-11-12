import 'package:flutter/material.dart';

import '../core/app_services.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  bool _register = false;
  bool _hide = true;
  String? _error;

  String _t(String bn, String en) => S.settings.language == 'bn' ? bn : en;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _name.dispose();
    super.dispose();
  }

  String _msg(String code) {
    switch (code) {
      case 'invalid_email':
        return _t('সঠিক ইমেইল দিন।', 'Please enter a valid email.');
      case 'wrong':
        return _t('ইমেইল বা পাসওয়ার্ড ভুল।', 'Wrong email or password.');
      case 'exists':
        return _t('এই ইমেইলে আগেই অ্যাকাউন্ট আছে। সাইন ইন করুন।',
            'An account with this email already exists. Please sign in.');
      case 'weak':
        return _t('পাসওয়ার্ড কমপক্ষে ৬ অক্ষরের দিন।', 'Password must be at least 6 characters.');
      case 'network':
        return _t('ইন্টারনেট সংযোগ নেই।', 'No internet connection.');
      case 'many':
        return _t('অনেকবার চেষ্টা হয়েছে, একটু পরে আবার করুন।', 'Too many attempts, try again later.');
      case 'not_enabled':
        return _t('Firebase-এ Email/Password লগইন চালু করা হয়নি।',
            'Email/Password sign-in is not enabled in Firebase.');
      case 'unavailable':
        return _t('ইমেইল লগইন এখন চালু নেই।', 'Email sign-in is not available.');
      default:
        return _t('কিছু একটা সমস্যা হয়েছে, আবার চেষ্টা করুন।', 'Something went wrong, please try again.');
    }
  }

  Future<void> _google() async {
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

  Future<void> _emailSubmit() async {
    final email = _email.text.trim();
    final pass = _pass.text;
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = _t('ইমেইল আর পাসওয়ার্ড দিন।', 'Enter your email and password.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = _register
        ? await S.auth.emailSignUp(email, pass, _name.text)
        : await S.auth.emailSignIn(email, pass);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err == null ? null : _msg(err);
    });
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = _t('আগে উপরে আপনার ইমেইল লিখুন।', 'Type your email above first.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await S.auth.sendReset(email);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err == null ? null : _msg(err);
    });
    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_t('পাসওয়ার্ড রিসেটের লিংক ইমেইলে পাঠানো হয়েছে। স্প্যাম ফোল্ডারও দেখুন।',
            'Password reset link sent. Check your inbox and spam folder.')),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: S.settings,
      builder: (context, _) {
        final pal = AegisPalette.byId(S.settings.themeId);
        final emailOk = AuthService.firebaseReady;
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
                    const SizedBox(height: 24),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'bn', label: Text('বাংলা')),
                        ButtonSegment(value: 'en', label: Text('English')),
                      ],
                      selected: {S.settings.language},
                      showSelectedIcon: false,
                      onSelectionChanged: (v) => S.settings.setLanguage(v.first),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _t('Google দিয়ে সাইন ইন করলে আপনার প্রোফাইল, সেটিংস আর কথোপকথন আপনার Google Drive-এ নিরাপদে সেভ থাকবে, অ্যাপ মুছে ফেললেও হারাবে না।',
                          'Sign in with Google and your profile, settings and conversations are saved privately to your Google Drive, so nothing is lost even if you delete the app.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: pal.subtext, height: 1.45),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _google,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.login_rounded),
                        label: Text(_t('Google দিয়ে সাইন ইন', 'Sign in with Google')),
                      ),
                    ),
                    if (emailOk) ...[
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(child: Divider(color: pal.subtext.op(.4))),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(_t('অথবা ইমেইল দিয়ে', 'or with email'),
                                style: TextStyle(color: pal.subtext, fontSize: 12.5)),
                          ),
                          Expanded(child: Divider(color: pal.subtext.op(.4))),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_register) ...[
                        TextField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: _t('নাম', 'Name'),
                            prefixIcon: const Icon(Icons.person_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: _t('ইমেইল', 'Email'),
                          prefixIcon: const Icon(Icons.email_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _pass,
                        obscureText: _hide,
                        autocorrect: false,
                        onSubmitted: (_) => _emailSubmit(),
                        decoration: InputDecoration(
                          labelText: _t('পাসওয়ার্ড', 'Password'),
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(_hide ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                            onPressed: () => setState(() => _hide = !_hide),
                          ),
                        ),
                      ),
                      if (!_register)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _busy ? null : _forgot,
                            child: Text(_t('পাসওয়ার্ড ভুলে গেছেন?', 'Forgot password?')),
                          ),
                        )
                      else
                        const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton(
                          onPressed: _busy ? null : _emailSubmit,
                          child: Text(_register
                              ? _t('অ্যাকাউন্ট খুলুন', 'Create account')
                              : _t('সাইন ইন', 'Sign in')),
                        ),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  _register = !_register;
                                  _error = null;
                                }),
                        child: Text(_register
                            ? _t('আগে থেকেই অ্যাকাউন্ট আছে? সাইন ইন', 'Already have an account? Sign in')
                            : _t('নতুন? অ্যাকাউন্ট খুলুন', 'New here? Create an account')),
                      ),
                    ],
                    const SizedBox(height: 4),
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
