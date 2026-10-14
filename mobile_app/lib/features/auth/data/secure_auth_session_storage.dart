import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/auth_models.dart';
import '../domain/auth_session_storage.dart';

class SecureAuthSessionStorage implements AuthSessionStorage {
  SecureAuthSessionStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _accessTokenKey = 'auth.access_token';
  static const _refreshTokenKey = 'auth.refresh_token';
  static const _expiresAtKey = 'auth.expires_at';

  final FlutterSecureStorage _storage;

  @override
  Future<AuthTokens?> readTokens() async {
    final values = await Future.wait([
      _storage.read(key: _accessTokenKey),
      _storage.read(key: _refreshTokenKey),
      _storage.read(key: _expiresAtKey),
    ]);

    final accessToken = values[0];
    final refreshToken = values[1];
    final expiresAt = DateTime.tryParse(values[2] ?? '');

    if (accessToken == null || refreshToken == null || expiresAt == null) {
      if (values.any((value) => value != null)) {
        await clear();
      }
      return null;
    }

    return AuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresAt.toUtc(),
    );
  }

  @override
  Future<void> writeTokens(AuthTokens tokens) async {
    await Future.wait([
      _storage.write(key: _accessTokenKey, value: tokens.accessToken),
      _storage.write(key: _refreshTokenKey, value: tokens.refreshToken),
      _storage.write(
        key: _expiresAtKey,
        value: tokens.expiresAt.toUtc().toIso8601String(),
      ),
    ]);
  }

  @override
  Future<void> clear() {
    return Future.wait([
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
      _storage.delete(key: _expiresAtKey),
    ]);
  }
}
