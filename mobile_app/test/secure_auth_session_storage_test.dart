import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/auth/data/secure_auth_session_storage.dart';
import 'package:mobile_app/features/auth/domain/auth_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('secure storage writes, reads, and clears AquaSense tokens', () async {
    final storage = SecureAuthSessionStorage(
      storage: const FlutterSecureStorage(),
    );
    final tokens = AuthTokens(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      expiresAt: DateTime.utc(2026, 10, 14, 12),
    );

    await storage.writeTokens(tokens);
    final restored = await storage.readTokens();

    expect(restored?.accessToken, tokens.accessToken);
    expect(restored?.refreshToken, tokens.refreshToken);
    expect(restored?.expiresAt, tokens.expiresAt);

    await storage.clear();
    expect(await storage.readTokens(), isNull);
  });

  test('partial token data is rejected and removed', () async {
    FlutterSecureStorage.setMockInitialValues({
      'auth.access_token': 'partial-access-token',
    });
    final storage = SecureAuthSessionStorage(
      storage: const FlutterSecureStorage(),
    );

    expect(await storage.readTokens(), isNull);
    expect(
      await const FlutterSecureStorage().read(key: 'auth.access_token'),
      isNull,
    );
  });
}
