import 'package:flutter/foundation.dart';
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
       _googleIdTokenProvider = googleIdTokenProvider,
       _googleServerClientId = googleServerClientId,
       _sessionStorage = sessionStorage;

  final AuthenticationApiClient _apiClient;
  GoogleIdTokenProvider? _googleIdTokenProvider;
  final String _googleServerClientId;
  final AuthSessionStorage _sessionStorage;

  @override
  Future<AuthSession> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _storeEmailSession(
      () => _apiClient.signInWithEmail(email: email, password: password),
    );
  }

  @override
  Future<AuthSession> createAccount({
    required String email,
    required String displayName,
    required String password,
  }) {
    return _storeEmailSession(
      () => _apiClient.createAccount(
        email: email,
        displayName: displayName,
        password: password,
      ),
    );
  }

  Future<AuthSession> _storeEmailSession(
    Future<AuthSession> Function() authenticate,
  ) async {
    try {
      final session = await authenticate();
      await _sessionStorage.writeTokens(session.tokens);
      return session;
    } on http.ClientException {
      throw const AuthenticationException(
        'Could not connect to AquaSense. Check your connection and try again.',
        code: 'connection_error',
      );
    }
  }

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
      if (_googleIdTokenProvider == null && _googleServerClientId.isEmpty) {
        throw const AuthenticationException(
          'Google sign-in is not configured. Please sign in with email.',
          code: 'google_not_configured',
        );
      }
      final provider = _googleIdTokenProvider ??= PluginGoogleIdTokenProvider(
        serverClientId: _googleServerClientId,
      );
      final idToken = await provider.signIn();
      if (idToken == null || idToken.trim().isEmpty) {
        throw const AuthenticationException(
          'Google did not return an identity token. Please contact support.',
          code: 'missing_google_id_token',
        );
      }
      final session = await _apiClient.exchangeGoogleIdToken(idToken);
      await _sessionStorage.writeTokens(session.tokens);
      return GoogleSignInSuccess(session);
    } on GoogleSignInException catch (error) {
      if (kDebugMode) {
        // Do not log credentials or account details from the SDK exception.
        debugPrint('Google sign-in failed (${error.code.name}).');
      }
      if (error.code == GoogleSignInExceptionCode.canceled) {
        // Android can also report OAuth configuration errors as cancellation.
        if (kDebugMode) {
          debugPrint(
            'If the account chooser closed without being dismissed, check the '
            'Android OAuth package/signing SHA-1 and the Web serverClientId. '
            'See mobile_app/README.md: Google chooser closes after account selection.',
          );
        }
        return const GoogleSignInCancelled();
      }
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
      await _googleIdTokenProvider?.signOut();
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
