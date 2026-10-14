import '../domain/auth_models.dart';
import '../domain/authentication_repository.dart';

class PendingGoogleAuthenticationRepository
    implements AuthenticationRepository {
  const PendingGoogleAuthenticationRepository();

  @override
  Future<AuthSession?> restoreSession() async => null;

  @override
  Future<GoogleSignInResult> signInWithGoogle() {
    throw const AuthenticationException(
      'Google sign-in is not connected to the AquaSense backend yet.',
      code: 'google_backend_pending',
    );
  }

  @override
  Future<void> signOut() async {}
}
