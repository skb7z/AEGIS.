import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypted key/value storage (Android Keystore backed). Never throws.
class SecureStore {
  final FlutterSecureStorage _s = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<String?> read(String key) async {
    try {
      return await _s.read(key: key);
    } catch (e) {
      debugPrint('SecureStore.read($key): $e');
      return null;
    }
  }

  Future<void> write(String key, String value) async {
    try {
      await _s.write(key: key, value: value);
    } catch (e) {
      debugPrint('SecureStore.write($key): $e');
      try {
        // Corrupted keystore blob: reset once and retry so the app never crash-loops.
        await _s.deleteAll();
        await _s.write(key: key, value: value);
      } catch (e2) {
        debugPrint('SecureStore.write retry failed: $e2');
      }
    }
  }

  Future<void> delete(String key) async {
    try {
      await _s.delete(key: key);
    } catch (e) {
      debugPrint('SecureStore.delete($key): $e');
    }
  }
}
