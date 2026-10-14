class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.displayName,
    this.photoUrl,
  });

  final String id;
  final String email;
  final String displayName;
  final String? photoUrl;
}

class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  bool get isExpired => !expiresAt.isAfter(DateTime.now().toUtc());
}

class AuthSession {
  const AuthSession({required this.user, required this.tokens});

  final AuthUser user;
  final AuthTokens tokens;
}

sealed class GoogleSignInResult {
  const GoogleSignInResult();
}

class GoogleSignInSuccess extends GoogleSignInResult {
  const GoogleSignInSuccess(this.session);

  final AuthSession session;
}

class GoogleSignInCancelled extends GoogleSignInResult {
  const GoogleSignInCancelled();
}

class AuthenticationException implements Exception {
  const AuthenticationException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}
