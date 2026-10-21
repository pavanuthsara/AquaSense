import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../auth/domain/auth_session_storage.dart';
import '../domain/export_advisory.dart';
import '../domain/export_repository.dart';

class HttpExportRepository implements ExportRepository {
  HttpExportRepository({
    required String apiBaseUrl,
    required AuthSessionStorage sessionStorage,
    http.Client? client,
  }) : _baseUri = Uri.parse(apiBaseUrl),
       _sessionStorage = sessionStorage,
       _client = client ?? http.Client();

  final Uri _baseUri;
  final AuthSessionStorage _sessionStorage;
  final http.Client _client;

  static const _connectionError = ExportException(
    'Could not connect to AquaSense. Check your connection and try again.',
    code: 'connection_error',
  );

  @override
  Future<ExportAdvisoryDetail> createAdvisory({
    required String facilityId,
    required ExportShipmentRequest request,
  }) async {
    final response = await _post(
      '/api/v1/facilities/$facilityId/export-advisories',
      request.toJson(),
    );
    final body = _decode(response);
    _requireSuccess(response, body);
    return ExportAdvisoryDetail.fromJson(body as Map<String, dynamic>);
  }

  @override
  Future<List<ExportAdvisorySummary>> listAdvisories(String facilityId) async {
    final response = await _get(
      '/api/v1/facilities/$facilityId/export-advisories',
    );
    final body = _decode(response);
    _requireSuccess(response, body);
    return (body as List<dynamic>)
        .map(
          (item) => ExportAdvisorySummary.fromJson(item as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  @override
  Future<ExportAdvisoryDetail> getAdvisory({
    required String facilityId,
    required String advisoryId,
  }) async {
    final response = await _get(
      '/api/v1/facilities/$facilityId/export-advisories/$advisoryId',
    );
    final body = _decode(response);
    _requireSuccess(response, body);
    return ExportAdvisoryDetail.fromJson(body as Map<String, dynamic>);
  }

  Future<http.Response> _post(String path, Map<String, dynamic> body) async {
    try {
      return await _client.post(
        _resolve(path),
        headers: await _headers(),
        body: jsonEncode(body),
      );
    } on http.ClientException {
      throw _connectionError;
    }
  }

  Future<http.Response> _get(String path) async {
    try {
      return await _client.get(_resolve(path), headers: await _headers());
    } on http.ClientException {
      throw _connectionError;
    }
  }

  Future<Map<String, String>> _headers() async {
    final tokens = await _sessionStorage.readTokens();
    if (tokens == null) {
      throw const ExportException(
        'Your session has ended. Sign in again to continue.',
        code: 'missing_session',
      );
    }
    return {
      'Authorization': 'Bearer ${tokens.accessToken}',
      'Content-Type': 'application/json',
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
      throw const ExportException(
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
    throw ExportException(
      message is String && message.isNotEmpty
          ? message
          : 'AquaSense could not complete the shipment plan.',
      code: code is String ? code : 'export_request_failed',
    );
  }
}
