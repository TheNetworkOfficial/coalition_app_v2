import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionManager {
  SessionManager({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _sessionKey = 'auth.session.marker';

  final FlutterSecureStorage _storage;

  Future<void> persistSessionMarker(String value) async {
    try {
      await _storage.write(key: _sessionKey, value: value);
    } catch (error, stackTrace) {
      debugPrint('[SessionManager] Failed to persist session marker: $error\n$stackTrace');
    }
  }

  Future<String?> readSessionMarker() async {
    try {
      return await _storage.read(key: _sessionKey);
    } catch (error, stackTrace) {
      debugPrint('[SessionManager] Failed to read session marker: $error\n$stackTrace');
      return null;
    }
  }

  Future<void> clearSessionMarker() async {
    try {
      await _storage.delete(key: _sessionKey);
    } catch (error, stackTrace) {
      debugPrint('[SessionManager] Failed to clear session marker: $error\n$stackTrace');
    }
  }
}
