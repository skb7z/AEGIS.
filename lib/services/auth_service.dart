import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../core/secure_store.dart';

enum AuthStatus { unknown, signedOut, signedIn, guest }

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

/// Google Sign-In (phone accounts) + local profile. The session is stored encrypted, so a failed
/// silent refresh never logs the user out. Only [signOut] ends the session.
class AuthService extends ChangeNotifier {
  AuthService(this._store);
  final SecureStore _store;

  final GoogleSignIn _g = GoogleSignIn(scopes: <String>['email', K.driveScope]);

  AuthStatus status = AuthStatus.unknown;
  AegisUser? user;
  AegisProfile profile = const AegisProfile();

  bool get canUseDrive => status == AuthStatus.signedIn;

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
      final raw = await _store.read(K.kProfile);
      if (raw != null && raw.isNotEmpty) {
        try {
          profile = AegisProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        } catch (_) {}
      }
      if (email != null && email.isNotEmpty) {
        user = AegisUser(
          name: await _store.read(K.kName) ?? '',
          email: email,
          photo: await _store.read(K.kPhoto),
        );
        status = AuthStatus.signedIn;
      } else {
        status = guest ? AuthStatus.guest : AuthStatus.signedOut;
      }
    } catch (e) {
      debugPrint('Auth init: $e');
      status = AuthStatus.signedOut;
    }
    notifyListeners();
    if (status == AuthStatus.signedIn) unawaited(_silentRefresh());
  }

  Future<void> _silentRefresh() async {
    try {
      final a = await _g.signInSilently();
      if (a != null) await _persist(a);
    } catch (e) {
      debugPrint('Silent refresh failed (session kept): $e');
    }
  }

  Future<void> _persist(GoogleSignInAccount a) async {
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

  /// Returns an error message or null on success.
  Future<String?> signIn() async {
    try {
      final a = await _g.signIn();
      if (a == null) return 'cancelled';
      await _persist(a);
      await _store.write(K.kGuest, '0');
      status = AuthStatus.signedIn;
      notifyListeners();
      return null;
    } catch (e) {
      debugPrint('signIn: $e');
      return 'failed';
    }
  }

  Future<void> skip() async {
    await _store.write(K.kGuest, '1');
    status = AuthStatus.guest;
    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      await _g.signOut();
    } catch (_) {}
    await _store.delete(K.kName);
    await _store.delete(K.kEmail);
    await _store.delete(K.kPhoto);
    await _store.write(K.kGuest, '0');
    user = null;
    status = AuthStatus.signedOut;
    notifyListeners();
  }

  Future<GoogleAuthClient?> driveClient() async {
    if (status != AuthStatus.signedIn) return null;
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
