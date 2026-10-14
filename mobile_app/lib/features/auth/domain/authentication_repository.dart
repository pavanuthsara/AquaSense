import 'auth_models.dart';

abstract interface class AuthenticationRepository {
  Future<AuthSession?> restoreSession();

  Future<GoogleSignInResult> signInWithGoogle();

  Future<void> signOut();
}
