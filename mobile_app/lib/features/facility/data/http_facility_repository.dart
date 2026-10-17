import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../auth/domain/auth_session_storage.dart';
import '../domain/facility.dart';
import '../domain/facility_repository.dart';

class HttpFacilityRepository implements FacilityRepository {
  HttpFacilityRepository({
    required String apiBaseUrl,
    required AuthSessionStorage sessionStorage,
    http.Client? client,
  }) : _baseUri = Uri.parse(apiBaseUrl),
       _sessionStorage = sessionStorage,
       _client = client ?? http.Client();

  final Uri _baseUri;
  final AuthSessionStorage _sessionStorage;
  final http.Client _client;

  @override
  Future<List<Facility>> listFacilities() async {
    final response = await _authorizedGet('/api/v1/facilities');
    final body = _decode(response);
    _requireSuccess(response, body);
    return (body as List<dynamic>)
        .map((item) => _facilityFromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<Facility> getFacility(String facilityId) async {
    final response = await _authorizedGet('/api/v1/facilities/$facilityId');
    final body = _decode(response);
    _requireSuccess(response, body);
    return _facilityFromJson(body as Map<String, dynamic>);
  }

  @override
  Future<List<String>> listTimeZones() async {
    final response = await _authorizedGet('/api/v1/facilities/timezones');
    final body = _decode(response);
    _requireSuccess(response, body);
    return (body as List<dynamic>).cast<String>();
  }

  @override
  Future<Facility> createFacility({
    required String name,
    required String timeZone,
    required String idempotencyKey,
  }) async {
    try {
      final response = await _client.post(
        _resolve('/api/v1/facilities'),
        headers: await _headers(idempotencyKey: idempotencyKey),
        body: jsonEncode({'name': name, 'timeZone': timeZone}),
      );
      final body = _decode(response);
      _requireSuccess(response, body);
      return _facilityFromJson(body as Map<String, dynamic>);
    } on http.ClientException {
      throw const FacilityException(
        'Could not connect to AquaSense. Check your connection and try again.',
        code: 'connection_error',
      );
    }
  }

  Future<http.Response> _authorizedGet(String path) async {
    try {
      return await _client.get(_resolve(path), headers: await _headers());
    } on http.ClientException {
      throw const FacilityException(
        'Could not connect to AquaSense. Check your connection and try again.',
        code: 'connection_error',
      );
    }
  }

  Future<Map<String, String>> _headers({String? idempotencyKey}) async {
    final tokens = await _sessionStorage.readTokens();
    if (tokens == null) {
      throw const FacilityException(
        'Your session has ended. Sign in again to continue.',
        code: 'missing_session',
      );
    }
    return {
      'Authorization': 'Bearer ${tokens.accessToken}',
      'Content-Type': 'application/json',
      if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
    };
  }

  Uri _resolve(String path) {
    final basePath = _baseUri.path.endsWith('/')
        ? _baseUri.path.substring(0, _baseUri.path.length - 1)
        : _baseUri.path;
    return _baseUri.replace(path: '$basePath$path');
  }

  dynamic _decode(http.Response response) {
    if (response.body.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(response.body);
    } on FormatException {
      throw const FacilityException(
        'The AquaSense server returned an unreadable response.',
        code: 'invalid_server_response',
      );
    }
  }

  void _requireSuccess(http.Response response, dynamic body) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    final errorBody = body is Map<String, dynamic> ? body : null;
    final message = errorBody?['message'];
    final code = errorBody?['code'];
    throw FacilityException(
      message is String && message.isNotEmpty
          ? message
          : 'AquaSense could not complete the aquarium request.',
      code: code is String ? code : 'facility_request_failed',
    );
  }

  Facility _facilityFromJson(Map<String, dynamic> json) {
    return Facility(
      id: json['id'] as String,
      name: json['name'] as String,
      timeZone: json['timeZone'] as String,
      role: switch (json['role']) {
        'OWNER' => FacilityRole.owner,
        'WORKER' => FacilityRole.worker,
        _ => throw const FacilityException(
          'The AquaSense server returned an unknown facility role.',
          code: 'invalid_server_response',
        ),
      },
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
    );
  }
}
