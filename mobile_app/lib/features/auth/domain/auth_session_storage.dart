import 'auth_models.dart';

abstract interface class AuthSessionStorage {
  Future<AuthTokens?> readTokens();

  Future<void> writeTokens(AuthTokens tokens);

  Future<void> clear();
}
