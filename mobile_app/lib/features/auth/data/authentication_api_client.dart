import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/auth_models.dart';

class AuthenticationApiClient {
  AuthenticationApiClient({required String apiBaseUrl, http.Client? client})
    : _baseUri = Uri.parse(apiBaseUrl),
      _client = client ?? http.Client();

  final Uri _baseUri;
  final http.Client _client;

  Future<AuthSession> exchangeGoogleIdToken(String idToken) async {
    final response = await _post('/api/v1/auth/google/exchange', {
      'idToken': idToken,
    });
    return _sessionFromResponse(response);
  }

  Future<AuthSession> refresh(String refreshToken) async {
    final response = await _post('/api/v1/auth/refresh', {
      'refreshToken': refreshToken,
    });
    return _sessionFromResponse(response);
  }

  Future<AuthUser> me(String accessToken) async {
    final response = await _client.get(
      _resolve('/api/v1/auth/me'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    final body = _decode(response);
    _requireSuccess(response, body);
    return _userFromJson(body);
  }

  Future<void> logout(String refreshToken) async {
    final response = await _client.post(
      _resolve('/api/v1/auth/logout'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refreshToken': refreshToken}),
    );
    if (response.statusCode != 204) {
      final body = _decode(response);
      _requireSuccess(response, body);
    }
  }

  Future<http.Response> _post(String path, Map<String, String> body) {
    return _client.post(
      _resolve(path),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
  }

  Uri _resolve(String path) {
    final basePath = _baseUri.path.endsWith('/')
        ? _baseUri.path.substring(0, _baseUri.path.length - 1)
        : _baseUri.path;
    return _baseUri.replace(path: '$basePath$path');
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.body.isEmpty) {
      return const {};
    }
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw const AuthenticationException(
        'The AquaSense server returned an unreadable response.',
        code: 'invalid_server_response',
      );
    }
  }

  void _requireSuccess(
    http.Response response,
    Map<String, dynamic> responseBody,
  ) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    final message = responseBody['message'];
    throw AuthenticationApiException(
      message is String && message.isNotEmpty
          ? message
          : 'AquaSense could not complete authentication.',
      statusCode: response.statusCode,
    );
  }

  AuthSession _sessionFromResponse(http.Response response) {
    final body = _decode(response);
    _requireSuccess(response, body);
    final expiresInSeconds = body['expiresInSeconds'];
    if (expiresInSeconds is! num) {
      throw const AuthenticationException(
        'The AquaSense server returned an incomplete session.',
        code: 'invalid_server_response',
      );
    }
    return AuthSession(
      user: _userFromJson(body['user'] as Map<String, dynamic>),
      tokens: AuthTokens(
        accessToken: body['accessToken'] as String,
        refreshToken: body['refreshToken'] as String,
        expiresAt: DateTime.now().toUtc().add(
          Duration(seconds: expiresInSeconds.toInt()),
        ),
      ),
    );
  }

  AuthUser _userFromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: json['displayName'] as String,
      photoUrl: json['photoUrl'] as String?,
    );
  }
}

class AuthenticationApiException extends AuthenticationException {
  const AuthenticationApiException(super.message, {required this.statusCode})
    : super(code: 'backend_authentication_error');

  final int statusCode;
}
