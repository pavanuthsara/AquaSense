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
  int emailSignInCalls = 0;
  int createAccountCalls = 0;
  String? lastEmail;
  String? lastPassword;
  String? lastDisplayName;

  @override
  Future<AuthSession> signInWithEmail({
    required String email,
    required String password,
  }) async {
    emailSignInCalls++;
    lastEmail = email;
    lastPassword = password;
    await Future<void>.delayed(delay);
    if (behavior == FakeGoogleSignInBehavior.failure) {
      throw const AuthenticationException(
        'Email or password is incorrect.',
        code: 'invalid_credentials',
      );
    }
    return restoredSession = session(email: email);
  }

  @override
  Future<AuthSession> createAccount({
    required String email,
    required String displayName,
    required String password,
  }) async {
    createAccountCalls++;
    lastDisplayName = displayName;
    return signInWithEmail(email: email, password: password);
  }

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
