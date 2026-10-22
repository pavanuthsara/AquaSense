import '../domain/auth_models.dart';
import '../domain/auth_session_storage.dart';
import '../domain/authentication_repository.dart';

class DevelopmentAuthenticationRepository implements AuthenticationRepository {
  DevelopmentAuthenticationRepository({
    required AuthSessionStorage sessionStorage,
    this.signInDelay = const Duration(milliseconds: 700),
  }) : _sessionStorage = sessionStorage;

  static const _developmentUser = AuthUser(
    id: 'development-owner',
    email: 'owner@aquasense.local',
    displayName: 'Development Owner',
  );

  final AuthSessionStorage _sessionStorage;
  final Duration signInDelay;

  @override
  Future<AuthSession> signInWithEmail({
    required String email,
    required String password,
  }) async {
    throw const AuthenticationException(
      'Email sign-in requires the AquaSense backend. Turn off local demo mode.',
      code: 'demo_mode',
    );
  }

  @override
  Future<AuthSession> createAccount({
    required String email,
    required String displayName,
    required String password,
  }) async {
    throw const AuthenticationException(
      'Account creation requires the AquaSense backend. Turn off local demo mode.',
      code: 'demo_mode',
    );
  }

  @override
  Future<AuthSession?> restoreSession() async {
    final tokens = await _sessionStorage.readTokens();
    if (tokens == null) {
      return null;
    }

    if (tokens.isExpired) {
      await _sessionStorage.clear();
      return null;
    }

    return AuthSession(user: _developmentUser, tokens: tokens);
  }

  @override
  Future<GoogleSignInResult> signInWithGoogle() async {
    await Future<void>.delayed(signInDelay);

    final now = DateTime.now().toUtc();
    final tokens = AuthTokens(
      accessToken: 'development-access-${now.microsecondsSinceEpoch}',
      refreshToken: 'development-refresh-${now.microsecondsSinceEpoch}',
      expiresAt: now.add(const Duration(hours: 8)),
    );
    await _sessionStorage.writeTokens(tokens);

    return GoogleSignInSuccess(
      AuthSession(user: _developmentUser, tokens: tokens),
    );
  }

  @override
  Future<void> signOut() => _sessionStorage.clear();
}
