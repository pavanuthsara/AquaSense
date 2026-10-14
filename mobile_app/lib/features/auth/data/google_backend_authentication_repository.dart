import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../domain/auth_models.dart';
import '../domain/auth_session_storage.dart';
import '../domain/authentication_repository.dart';
import 'authentication_api_client.dart';
import 'google_id_token_provider.dart';

class GoogleBackendAuthenticationRepository
    implements AuthenticationRepository {
  GoogleBackendAuthenticationRepository({
    required String apiBaseUrl,
    required String googleServerClientId,
    required AuthSessionStorage sessionStorage,
    AuthenticationApiClient? apiClient,
    GoogleIdTokenProvider? googleIdTokenProvider,
  }) : _apiClient =
           apiClient ?? AuthenticationApiClient(apiBaseUrl: apiBaseUrl),
       _googleIdTokenProvider =
           googleIdTokenProvider ??
           PluginGoogleIdTokenProvider(serverClientId: googleServerClientId),
       _sessionStorage = sessionStorage;

  final AuthenticationApiClient _apiClient;
  final GoogleIdTokenProvider _googleIdTokenProvider;
  final AuthSessionStorage _sessionStorage;

  @override
  Future<AuthSession?> restoreSession() async {
    final savedTokens = await _sessionStorage.readTokens();
    if (savedTokens == null) {
      return null;
    }

    try {
      if (savedTokens.isExpired) {
        return _refresh(savedTokens.refreshToken);
      }
      final user = await _apiClient.me(savedTokens.accessToken);
      return AuthSession(user: user, tokens: savedTokens);
    } on AuthenticationApiException catch (error) {
      if (error.statusCode == 401) {
        try {
          return await _refresh(savedTokens.refreshToken);
        } on AuthenticationException {
          await _sessionStorage.clear();
          return null;
        }
      }
      rethrow;
    } on http.ClientException {
      throw const AuthenticationException(
        'Could not connect to AquaSense. Check your connection and try again.',
        code: 'connection_error',
      );
    }
  }

  @override
  Future<GoogleSignInResult> signInWithGoogle() async {
    try {
      final idToken = await _googleIdTokenProvider.signIn();
      if (idToken == null) {
        return const GoogleSignInCancelled();
      }
      final session = await _apiClient.exchangeGoogleIdToken(idToken);
      await _sessionStorage.writeTokens(session.tokens);
      return GoogleSignInSuccess(session);
    } on GoogleSignInException catch (error) {
      throw AuthenticationException(
        error.code == GoogleSignInExceptionCode.clientConfigurationError
            ? 'Google sign-in is not configured for this Android build.'
            : 'Google could not complete sign-in. Please try again.',
        code: error.code.name,
      );
    } on http.ClientException {
      throw const AuthenticationException(
        'Could not connect to AquaSense. Check your connection and try again.',
        code: 'connection_error',
      );
    }
  }

  @override
  Future<void> signOut() async {
    final tokens = await _sessionStorage.readTokens();
    if (tokens != null) {
      await _apiClient.logout(tokens.refreshToken);
    }
    await _sessionStorage.clear();
    try {
      await _googleIdTokenProvider.signOut();
    } catch (_) {
      // The backend session is already revoked and local tokens are removed.
    }
  }

  Future<AuthSession> _refresh(String refreshToken) async {
    final session = await _apiClient.refresh(refreshToken);
    await _sessionStorage.writeTokens(session.tokens);
    return session;
  }
}
