import 'auth_models.dart';

abstract interface class AuthenticationRepository {
  Future<AuthSession?> restoreSession();

  Future<GoogleSignInResult> signInWithGoogle();

  Future<AuthSession> signInWithEmail({
    required String email,
    required String password,
  });

  Future<AuthSession> createAccount({
    required String email,
    required String displayName,
    required String password,
  });

  Future<void> signOut();
}
