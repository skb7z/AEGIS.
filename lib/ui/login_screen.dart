import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../core/app_services.dart';
import '../services/auth_service.dart';
import 'star_field.dart';

enum _Step { welcome, password, register }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _bg = Color(0xFF0D0D0D);
  static const _sub = Color(0xFF9AA7B4);

  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _name = TextEditingController();
  _Step _step = _Step.welcome;
  bool _busy = false;
  bool _hide = true;
  String? _error;
  String? _detail;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _name.dispose();
    super.dispose();
  }

  void _go(_Step s) {
    setState(() {
      _step = s;
      _error = null;
      _detail = null;
      _pass.clear();
    });
  }

  String _msg(String code) {
    switch (code) {
      case 'invalid_email':
        return 'Please enter a valid email.';
      case 'wrong':
        return 'Wrong email or password.';
      case 'exists':
        return 'An account with this email already exists. Please sign in.';
      case 'weak':
        return 'Password must be at least 6 characters.';
      case 'network':
        return 'No internet connection.';
      case 'many':
        return 'Too many attempts, try again later.';
      case 'not_enabled':
        return 'Email/Password sign-in is not enabled in Firebase.';
      case 'unavailable':
        return 'Email sign-in is not available.';
      default:
        return 'Something went wrong, please try again.';
    }
  }

  // ---------------------------------------------------------------- actions

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
      _detail = null;
    });
    final err = await S.auth.signIn();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (err == 'failed') {
        _error = 'Google sign-in failed. Check your internet, or continue as guest.';
        _detail = S.auth.lastError.isEmpty ? null : S.auth.lastError;
      }
    });
  }

  void _continueEmail() {
    final e = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) {
      setState(() => _error = 'Please enter a valid email.');
      return;
    }
    _go(_Step.password);
  }

  Future<void> _signInEmail() async {
    if (_pass.text.isEmpty) {
      setState(() => _error = 'Enter your password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await S.auth.emailSignIn(_email.text, _pass.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err == null ? null : _msg(err);
    });
  }

  Future<void> _register() async {
    final e = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) {
      setState(() => _error = 'Please enter a valid email.');
      return;
    }
    if (_pass.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await S.auth.emailSignUp(e, _pass.text, _name.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err == null ? null : _msg(err);
    });
  }

  Future<void> _forgot() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await S.auth.sendReset(_email.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err == null ? null : _msg(err);
    });
    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Password reset link sent. Check your inbox and spam folder.'),
      ));
    }
  }

  // ---------------------------------------------------------------- pieces

  Widget _logo() {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: Image.asset(
            K.logoAsset,
            width: 112,
            height: 112,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.shield_outlined, size: 96, color: Color(0xFF00E5FF)),
          ),
        ),
        const SizedBox(height: 16),
        const Text('AEGIS',
            style: TextStyle(
                color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 7)),
        const SizedBox(height: 6),
        const Text('Your personal voice assistant', style: TextStyle(color: _sub, fontSize: 14)),
      ],
    );
  }

  Widget _errorBox() {
    if (_error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        children: [
          Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 13.5, height: 1.35)),
          if (_detail != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('($_detail)',
                  textAlign: TextAlign.center, style: const TextStyle(color: _sub, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _backBar() {
    return Align(
      alignment: Alignment.centerLeft,
      child: IconButton(
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        onPressed: _busy ? null : () => _go(_Step.welcome),
      ),
    );
  }

  Widget _divider() => Row(
        children: const [
          Expanded(child: Divider(color: Color(0x33FFFFFF))),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Text('or with email', style: TextStyle(color: _sub, fontSize: 12.5)),
          ),
          Expanded(child: Divider(color: Color(0x33FFFFFF))),
        ],
      );

  Widget _welcome() {
    final emailOk = AuthService.firebaseReady;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _logo(),
        const SizedBox(height: 34),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
            ),
            onPressed: _busy ? null : _google,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54))
                : const Icon(Icons.g_mobiledata_rounded, size: 34),
            label: const Text('Sign in with Google',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
        if (emailOk) ...[
          const SizedBox(height: 22),
          _divider(),
          const SizedBox(height: 18),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.go,
            autocorrect: false,
            onSubmitted: (_) => _continueEmail(),
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _busy ? null : _continueEmail,
              child: const Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
        _errorBox(),
        const SizedBox(height: 26),
        if (emailOk)
          TextButton(
            onPressed: _busy ? null : () => _go(_Step.register),
            child: const Text('New here? Create an account', style: TextStyle(fontSize: 15)),
          ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Color(0x44FFFFFF)),
            ),
            onPressed: _busy ? null : S.auth.skip,
            child: const Text('Continue as guest'),
          ),
        ),
      ],
    );
  }

  Widget _passwordStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _backBar(),
        const SizedBox(height: 4),
        _logo(),
        const SizedBox(height: 26),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0x1AFFFFFF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.account_circle_outlined, color: _sub, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_email.text.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 15)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _pass,
          obscureText: _hide,
          autocorrect: false,
          autofocus: true,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _signInEmail(),
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              icon: Icon(_hide ? Icons.visibility_off_rounded : Icons.visibility_rounded),
              onPressed: () => setState(() => _hide = !_hide),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _busy ? null : _forgot,
            child: const Text('Forgot password?'),
          ),
        ),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: _busy ? null : _signInEmail,
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Sign in', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
        _errorBox(),
      ],
    );
  }

  Widget _registerStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _backBar(),
        const SizedBox(height: 4),
        _logo(),
        const SizedBox(height: 26),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Create your account',
              style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pass,
          obscureText: _hide,
          autocorrect: false,
          onSubmitted: (_) => _register(),
          decoration: InputDecoration(
            labelText: 'Password (min 6 characters)',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              icon: Icon(_hide ? Icons.visibility_off_rounded : Icons.visibility_rounded),
              onPressed: () => setState(() => _hide = !_hide),
            ),
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: _busy ? null : _register,
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Create account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
        _errorBox(),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _busy ? null : () => _go(_Step.welcome),
          child: const Text('Already have an account? Sign in'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    switch (_step) {
      case _Step.welcome:
        body = _welcome();
        break;
      case _Step.password:
        body = _passwordStep();
        break;
      case _Step.register:
        body = _registerStep();
        break;
    }
    return Theme(
      data: AegisPalette.cyber.theme,
      child: PopScope(
        canPop: _step == _Step.welcome,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _go(_Step.welcome);
        },
        child: Scaffold(
          backgroundColor: _bg,
          body: Stack(
            children: [
              const Positioned.fill(child: StarField()),
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      child: KeyedSubtree(
                        key: ValueKey(_step),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                          child: body,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
