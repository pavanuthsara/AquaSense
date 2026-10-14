import 'package:mobile_app/features/auth/domain/auth_models.dart';
import 'package:mobile_app/features/auth/domain/authentication_repository.dart';

enum FakeGoogleSignInBehavior { success, cancelled, failure }

class FakeAuthenticationRepository implements AuthenticationRepository {
  FakeAuthenticationRepository({
    this.restoredSession,
    this.behavior = FakeGoogleSignInBehavior.success,
    this.delay = Duration.zero,
  });

  AuthSession? restoredSession;
  FakeGoogleSignInBehavior behavior;
  Duration delay;
  int signInCalls = 0;
  int signOutCalls = 0;

  static AuthSession session({
    String displayName = 'Test Owner',
    String email = 'owner@example.com',
  }) {
    return AuthSession(
      user: AuthUser(id: 'test-owner', email: email, displayName: displayName),
      tokens: AuthTokens(
        accessToken: 'test-access-token',
        refreshToken: 'test-refresh-token',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
    );
  }

  @override
  Future<AuthSession?> restoreSession() async => restoredSession;

  @override
  Future<GoogleSignInResult> signInWithGoogle() async {
    signInCalls += 1;
    await Future<void>.delayed(delay);

    return switch (behavior) {
      FakeGoogleSignInBehavior.success => GoogleSignInSuccess(
        restoredSession = session(),
      ),
      FakeGoogleSignInBehavior.cancelled => const GoogleSignInCancelled(),
      FakeGoogleSignInBehavior.failure => throw const AuthenticationException(
        'Test connection failure.',
        code: 'test_failure',
      ),
    };
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    restoredSession = null;
  }
}
