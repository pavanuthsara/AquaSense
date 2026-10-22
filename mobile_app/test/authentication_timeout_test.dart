import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_app/features/auth/data/authentication_api_client.dart';
import 'package:mobile_app/features/auth/data/google_backend_authentication_repository.dart';
import 'package:mobile_app/features/auth/domain/auth_models.dart';
import 'package:mobile_app/features/auth/domain/auth_session_storage.dart';
import 'package:mobile_app/features/auth/presentation/authentication_controller.dart';

void main() {
  for (final operation in [
    'register',
    'login',
    'google',
    'refresh',
    'me',
    'logout',
  ]) {
    test('$operation stops waiting when the server does not respond', () async {
      final pending = Completer<http.Response>();
      var calls = 0;
      final api = AuthenticationApiClient(
        apiBaseUrl: 'http://127.0.0.1:8080',
        requestTimeout: const Duration(milliseconds: 10),
        client: MockClient((_) {
          calls++;
          return pending.future;
        }),
      );
      final request = switch (operation) {
        'register' => api.createAccount(
          email: 'owner@example.com',
          displayName: 'Owner',
          password: 'long-password-123',
        ),
        'login' => api.signInWithEmail(
          email: 'owner@example.com',
          password: 'long-password-123',
        ),
        'google' => api.exchangeGoogleIdToken('google-token'),
        'refresh' => api.refresh('refresh-token'),
        'me' => api.me('access-token'),
        _ => api.logout('refresh-token'),
      };
      await expectLater(
        request,
        throwsA(
          isA<AuthenticationException>().having(
            (error) => error.code,
            'code',
            'connection_timeout',
          ),
        ),
      );
      expect(calls, 1); // Registration is never retried automatically.
      pending.complete(http.Response('{}', 200));
    });
  }

  test(
    'timed out registration releases loading and allows a successful retry',
    () async {
      final pending = Completer<http.Response>();
      var calls = 0;
      final storage = _MemoryStorage();
      final controller = AuthenticationController(
        repository: GoogleBackendAuthenticationRepository(
          apiBaseUrl: 'http://127.0.0.1:8080',
          googleServerClientId: '',
          sessionStorage: storage,
          apiClient: AuthenticationApiClient(
            apiBaseUrl: 'http://127.0.0.1:8080',
            requestTimeout: const Duration(milliseconds: 10),
            client: MockClient((_) async {
              calls++;
              if (calls == 1) return pending.future;
              return http.Response(_sessionJson, 201);
            }),
          ),
        ),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final attempt = controller.createAccount(
        email: 'owner@example.com',
        displayName: 'Owner',
        password: 'long-password-123',
      );
      expect(controller.isBusy, isTrue);
      await attempt;
      expect(controller.status, AuthenticationStatus.signedOut);
      expect(controller.isBusy, isFalse);
      expect(controller.notice, contains('took too long'));
      expect(storage.tokens, isNull);

      // A late response from the first attempt cannot silently sign the user in.
      pending.complete(http.Response(_sessionJson, 201));
      await Future<void>.delayed(Duration.zero);
      expect(controller.status, AuthenticationStatus.signedOut);
      expect(storage.tokens, isNull);

      await controller.createAccount(
        email: 'owner@example.com',
        displayName: 'Owner',
        password: 'long-password-123',
      );
      expect(controller.status, AuthenticationStatus.signedIn);
      expect(storage.tokens?.accessToken, 'access-token');
      expect(calls, 2);
    },
  );
}

const _sessionJson = '''{
  "accessToken": "access-token", "refreshToken": "refresh-token",
  "expiresInSeconds": 900,
  "user": {"id": "user-1", "email": "owner@example.com", "displayName": "Owner", "photoUrl": null}
}''';

class _MemoryStorage implements AuthSessionStorage {
  AuthTokens? tokens;
  @override
  Future<void> clear() async => tokens = null;
  @override
  Future<AuthTokens?> readTokens() async => tokens;
  @override
  Future<void> writeTokens(AuthTokens tokens) async => this.tokens = tokens;
}
