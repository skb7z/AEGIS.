import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../core/secure_store.dart';

enum AuthStatus { unknown, signedOut, signedIn, guest }

enum LoginMethod { none, google, email }

class AegisUser {
  const AegisUser({required this.name, required this.email, this.photo});
  final String name;
  final String email;
  final String? photo;
}

/// Name, age, gender, country - editable from Settings.
class AegisProfile {
  const AegisProfile({this.name = '', this.age, this.gender = '', this.country = ''});
  final String name;
  final int? age;
  final String gender; // male | female
  final String country;

  bool get complete =>
      name.trim().isNotEmpty && age != null && gender.isNotEmpty && country.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {'n': name, 'a': age, 'g': gender, 'c': country};

  static AegisProfile fromJson(Map<String, dynamic> j) => AegisProfile(
        name: '${j['n'] ?? ''}',
        age: j['a'] is int ? j['a'] as int : int.tryParse('${j['a']}'),
        gender: '${j['g'] ?? ''}',
        country: '${j['c'] ?? ''}',
      );
}

class GoogleAuthClient extends http.BaseClient {
  GoogleAuthClient(this._headers);
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

/// Google Sign-In (phone accounts) OR email + password (Firebase). The session is stored encrypted,
/// so a failed refresh never logs the user out. Only [signOut] ends the session.
/// Google Drive backup is available for Google sign-in only.
class AuthService extends ChangeNotifier {
  AuthService(this._store);
  final SecureStore _store;

  static const _kMethod = 'login_method';

  /// True when google-services.json was bundled and Firebase started. Email login is hidden otherwise.
  static bool firebaseReady = false;

  static Future<void> initFirebase() async {
    try {
      await Firebase.initializeApp();
      firebaseReady = true;
    } catch (e) {
      debugPrint('Firebase unavailable (email login hidden): $e');
      firebaseReady = false;
    }
  }

  final GoogleSignIn _g = GoogleSignIn(scopes: <String>['email', K.driveScope]);

  AuthStatus status = AuthStatus.unknown;
  LoginMethod method = LoginMethod.none;
  AegisUser? user;
  AegisProfile profile = const AegisProfile();

  /// Drive backup works only with a Google sign-in.
  bool get canUseDrive => status == AuthStatus.signedIn && method == LoginMethod.google;

  /// How Aegis addresses the user.
  String get callName =>
      profile.name.trim().isNotEmpty ? profile.name.trim() : (user?.name ?? '');

  /// One sentence for the AI prompt.
  String get profileText {
    if (callName.isEmpty && profile.age == null) return '';
    final b = StringBuffer("The user's name is ${callName.isEmpty ? 'unknown' : callName}");
    if (profile.age != null) b.write(', age ${profile.age}');
    if (profile.gender.isNotEmpty) b.write(', ${profile.gender}');
    if (profile.country.isNotEmpty) b.write(', from ${profile.country}');
    b.write('.');
    return b.toString();
  }

  Future<void> init() async {
    try {
      final email = await _store.read(K.kEmail);
      final guest = (await _store.read(K.kGuest)) == '1';
      final m = await _store.read(_kMethod);
      final raw = await _store.read(K.kProfile);
      if (raw != null && raw.isNotEmpty) {
        try {
          profile = AegisProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        } catch (_) {}
      }
      if (m == 'email') {
        fb.User? u;
        if (firebaseReady) {
          try {
            u = await fb.FirebaseAuth.instance
                .authStateChanges()
                .first
                .timeout(const Duration(seconds: 4));
          } catch (_) {
            u = fb.FirebaseAuth.instance.currentUser;
          }
        }
        if (u != null) {
          user = AegisUser(name: u.displayName ?? '', email: u.email ?? (email ?? ''));
          method = LoginMethod.email;
          status = AuthStatus.signedIn;
        } else {
          status = AuthStatus.signedOut;
        }
      } else if (email != null && email.isNotEmpty) {
        user = AegisUser(
          name: await _store.read(K.kName) ?? '',
          email: email,
          photo: await _store.read(K.kPhoto),
        );
        method = LoginMethod.google;
        status = AuthStatus.signedIn;
      } else {
        status = guest ? AuthStatus.guest : AuthStatus.signedOut;
      }
    } catch (e) {
      debugPrint('Auth init: $e');
      status = AuthStatus.signedOut;
    }
    notifyListeners();
    if (method == LoginMethod.google && status == AuthStatus.signedIn) unawaited(_silentRefresh());
  }

  Future<void> _silentRefresh() async {
    try {
      final a = await _g.signInSilently();
      if (a != null) await _persistGoogle(a);
    } catch (e) {
      debugPrint('Silent refresh failed (session kept): $e');
    }
  }

  Future<void> _persistGoogle(GoogleSignInAccount a) async {
    user = AegisUser(name: a.displayName ?? '', email: a.email, photo: a.photoUrl);
    await _store.write(K.kName, user!.name);
    await _store.write(K.kEmail, user!.email);
    if (a.photoUrl != null) await _store.write(K.kPhoto, a.photoUrl!);
    notifyListeners();
  }

  Future<void> saveProfile(AegisProfile p) async {
    profile = p;
    await _store.write(K.kProfile, jsonEncode(p.toJson()));
    notifyListeners();
  }

  // ---------------------------------------------------------------- Google

  /// Returns an error code or null on success.
  Future<String?> signIn() async {
    try {
      final a = await _g.signIn();
      if (a == null) return 'cancelled';
      await _persistGoogle(a);
      await _store.write(K.kGuest, '0');
      await _store.write(_kMethod, 'google');
      method = LoginMethod.google;
      status = AuthStatus.signedIn;
      notifyListeners();
      return null;
    } catch (e) {
      debugPrint('signIn: $e');
      return 'failed';
    }
  }

  // ---------------------------------------------------------------- email + password

  static String _code(String c) {
    switch (c) {
      case 'invalid-email':
        return 'invalid_email';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'wrong';
      case 'email-already-in-use':
        return 'exists';
      case 'weak-password':
        return 'weak';
      case 'network-request-failed':
        return 'network';
      case 'too-many-requests':
        return 'many';
      case 'operation-not-allowed':
        return 'not_enabled';
      default:
        return 'failed';
    }
  }

  Future<void> _finishEmail(fb.User? u) async {
    user = AegisUser(name: u?.displayName ?? '', email: u?.email ?? '');
    await _store.write(K.kEmail, user!.email);
    await _store.write(K.kName, user!.name);
    await _store.write(K.kGuest, '0');
    await _store.write(_kMethod, 'email');
    method = LoginMethod.email;
    status = AuthStatus.signedIn;
    notifyListeners();
  }

  Future<String?> emailSignIn(String email, String password) async {
    if (!firebaseReady) return 'unavailable';
    try {
      final c = await fb.FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email.trim(), password: password);
      await _finishEmail(c.user);
      return null;
    } on fb.FirebaseAuthException catch (e) {
      return _code(e.code);
    } catch (e) {
      debugPrint('emailSignIn: $e');
      return 'failed';
    }
  }

  Future<String?> emailSignUp(String email, String password, String name) async {
    if (!firebaseReady) return 'unavailable';
    try {
      final c = await fb.FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email.trim(), password: password);
      final u = c.user;
      if (u != null) {
        if (name.trim().isNotEmpty) await u.updateDisplayName(name.trim());
        try {
          await u.sendEmailVerification();
        } catch (_) {}
        await u.reload();
      }
      await _finishEmail(fb.FirebaseAuth.instance.currentUser ?? u);
      return null;
    } on fb.FirebaseAuthException catch (e) {
      return _code(e.code);
    } catch (e) {
      debugPrint('emailSignUp: $e');
      return 'failed';
    }
  }

  /// Sends the password-reset link to the email address.
  Future<String?> sendReset(String email) async {
    if (!firebaseReady) return 'unavailable';
    try {
      await fb.FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
      return null;
    } on fb.FirebaseAuthException catch (e) {
      return _code(e.code);
    } catch (e) {
      debugPrint('sendReset: $e');
      return 'failed';
    }
  }

  // ---------------------------------------------------------------- guest / sign-out

  Future<void> skip() async {
    await _store.write(K.kGuest, '1');
    status = AuthStatus.guest;
    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      await _g.signOut();
    } catch (_) {}
    if (firebaseReady) {
      try {
        await fb.FirebaseAuth.instance.signOut();
      } catch (_) {}
    }
    await _store.delete(K.kName);
    await _store.delete(K.kEmail);
    await _store.delete(K.kPhoto);
    await _store.delete(_kMethod);
    await _store.write(K.kGuest, '0');
    user = null;
    method = LoginMethod.none;
    status = AuthStatus.signedOut;
    notifyListeners();
  }

  Future<GoogleAuthClient?> driveClient() async {
    if (!canUseDrive) return null;
    try {
      final a = _g.currentUser ?? await _g.signInSilently();
      if (a == null) return null;
      return GoogleAuthClient(await a.authHeaders);
    } catch (e) {
      debugPrint('driveClient: $e');
      return null;
    }
  }
}
