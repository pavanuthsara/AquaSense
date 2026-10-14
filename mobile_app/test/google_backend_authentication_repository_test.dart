import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_app/features/auth/data/authentication_api_client.dart';
import 'package:mobile_app/features/auth/data/google_backend_authentication_repository.dart';
import 'package:mobile_app/features/auth/data/google_id_token_provider.dart';
import 'package:mobile_app/features/auth/domain/auth_models.dart';
import 'package:mobile_app/features/auth/domain/auth_session_storage.dart';

void main() {
  test(
    'Google ID token is exchanged and AquaSense session is stored',
    () async {
      late http.Request capturedRequest;
      final apiClient = AuthenticationApiClient(
        apiBaseUrl: 'https://api.example.com',
        client: MockClient((request) async {
          capturedRequest = request;
          return http.Response(_sessionJson, 200);
        }),
      );
      final storage = _MemorySessionStorage();
      final repository = GoogleBackendAuthenticationRepository(
        apiBaseUrl: 'https://unused.example.com',
        googleServerClientId: 'test-client-id',
        sessionStorage: storage,
        apiClient: apiClient,
        googleIdTokenProvider: _FakeGoogleIdTokenProvider('google-id-token'),
      );

      final result = await repository.signInWithGoogle();

      expect(result, isA<GoogleSignInSuccess>());
      expect(capturedRequest.url.path, '/api/v1/auth/google/exchange');
      expect(capturedRequest.body, contains('google-id-token'));
      expect(storage.tokens?.accessToken, 'access-token');
    },
  );

  test('cancelled Google sign-in does not call the backend', () async {
    var backendCalls = 0;
    final repository = GoogleBackendAuthenticationRepository(
      apiBaseUrl: 'https://unused.example.com',
      googleServerClientId: 'test-client-id',
      sessionStorage: _MemorySessionStorage(),
      apiClient: AuthenticationApiClient(
        apiBaseUrl: 'https://api.example.com',
        client: MockClient((request) async {
          backendCalls += 1;
          return http.Response(_sessionJson, 200);
        }),
      ),
      googleIdTokenProvider: _FakeGoogleIdTokenProvider(null),
    );

    expect(await repository.signInWithGoogle(), isA<GoogleSignInCancelled>());
    expect(backendCalls, 0);
  });

  test('expired access token is restored through refresh rotation', () async {
    late http.Request capturedRequest;
    final storage = _MemorySessionStorage(
      AuthTokens(
        accessToken: 'expired-access',
        refreshToken: 'saved-refresh',
        expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      ),
    );
    final repository = GoogleBackendAuthenticationRepository(
      apiBaseUrl: 'https://unused.example.com',
      googleServerClientId: 'test-client-id',
      sessionStorage: storage,
      apiClient: AuthenticationApiClient(
        apiBaseUrl: 'https://api.example.com',
        client: MockClient((request) async {
          capturedRequest = request;
          return http.Response(_sessionJson, 200);
        }),
      ),
      googleIdTokenProvider: _FakeGoogleIdTokenProvider(null),
    );

    final restored = await repository.restoreSession();

    expect(capturedRequest.url.path, '/api/v1/auth/refresh');
    expect(capturedRequest.body, contains('saved-refresh'));
    expect(restored?.user.email, 'owner@example.com');
    expect(storage.tokens?.refreshToken, 'refresh-token');
  });

  test('backend authentication message is surfaced', () async {
    final repository = GoogleBackendAuthenticationRepository(
      apiBaseUrl: 'https://unused.example.com',
      googleServerClientId: 'test-client-id',
      sessionStorage: _MemorySessionStorage(),
      apiClient: AuthenticationApiClient(
        apiBaseUrl: 'https://api.example.com',
        client: MockClient(
          (request) async => http.Response(
            '{"message":"The Google identity token is invalid or expired"}',
            401,
          ),
        ),
      ),
      googleIdTokenProvider: _FakeGoogleIdTokenProvider('invalid-token'),
    );

    expect(
      repository.signInWithGoogle(),
      throwsA(
        isA<AuthenticationException>().having(
          (error) => error.message,
          'message',
          contains('invalid or expired'),
        ),
      ),
    );
  });
}

const _sessionJson = '''
{
  "accessToken": "access-token",
  "refreshToken": "refresh-token",
  "tokenType": "Bearer",
  "expiresInSeconds": 900,
  "user": {
    "id": "00000000-0000-0000-0000-000000000001",
    "email": "owner@example.com",
    "displayName": "Aqua Owner",
    "photoUrl": null
  }
}
''';

class _MemorySessionStorage implements AuthSessionStorage {
  _MemorySessionStorage([this.tokens]);

  AuthTokens? tokens;

  @override
  Future<void> clear() async => tokens = null;

  @override
  Future<AuthTokens?> readTokens() async => tokens;

  @override
  Future<void> writeTokens(AuthTokens tokens) async => this.tokens = tokens;
}

class _FakeGoogleIdTokenProvider implements GoogleIdTokenProvider {
  _FakeGoogleIdTokenProvider(this.idToken);

  final String? idToken;

  @override
  Future<String?> signIn() async => idToken;

  @override
  Future<void> signOut() async {}
}
