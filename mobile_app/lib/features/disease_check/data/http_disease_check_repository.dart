import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../auth/domain/auth_session_storage.dart';
import '../domain/disease_check_record.dart';
import '../domain/disease_check_repository.dart';
import '../domain/disease_prediction.dart';

/// Saves and lists disease checks through the AquaSense backend.
///
/// Endpoints: `POST` and `GET /api/v1/facilities/{facilityId}/disease-checks`.
/// Only the result is sent, never the photo.
class HttpDiseaseCheckRepository implements DiseaseCheckRepository {
  HttpDiseaseCheckRepository({
    required String apiBaseUrl,
    required AuthSessionStorage sessionStorage,
    http.Client? client,
  }) : _baseUri = Uri.parse(apiBaseUrl),
       _sessionStorage = sessionStorage,
       _client = client ?? http.Client();

  final Uri _baseUri;
  final AuthSessionStorage _sessionStorage;
  final http.Client _client;

  static const _connectionMessage =
      'Could not connect to AquaSense. Check your connection and try again.';

  @override
  Future<DiseaseCheckRecord> saveCheck({
    required String facilityId,
    required DiseasePrediction prediction,
    required String idempotencyKey,
    String? tankLabel,
    String? note,
  }) async {
    final http.Response response;
    try {
      response = await _client.post(
        _checksUri(facilityId),
        headers: await _headers(idempotencyKey: idempotencyKey),
        body: jsonEncode({
          'predictedLabel': prediction.topLabel,
          'confidence': prediction.confidence,
          'uncertain': prediction.isUncertain,
          'modelVersion': prediction.modelVersion,
          'checkedAt': prediction.checkedAt.toUtc().toIso8601String(),
          if (_hasText(tankLabel)) 'tankLabel': tankLabel!.trim(),
          if (_hasText(note)) 'note': note!.trim(),
        }),
      );
    } on http.ClientException {
      throw const DiseaseCheckException(
        _connectionMessage,
        code: 'connection_error',
      );
    }
    final body = _decode(response);
    _requireSuccess(response, body);
    return _recordFromJson(body as Map<String, dynamic>);
  }

  @override
  Future<List<DiseaseCheckRecord>> listChecks({
    required String facilityId,
    int limit = 20,
  }) async {
    final http.Response response;
    try {
      response = await _client.get(
        _checksUri(facilityId, query: {'limit': '$limit'}),
        headers: await _headers(),
      );
    } on http.ClientException {
      throw const DiseaseCheckException(
        _connectionMessage,
        code: 'connection_error',
      );
    }
    final body = _decode(response);
    _requireSuccess(response, body);
    return (body as List<dynamic>)
        .map((item) => _recordFromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Uri _checksUri(String facilityId, {Map<String, String>? query}) {
    final basePath = _baseUri.path.endsWith('/')
        ? _baseUri.path.substring(0, _baseUri.path.length - 1)
        : _baseUri.path;
    return _baseUri.replace(
      path:
          '$basePath/api/v1/facilities/${Uri.encodeComponent(facilityId)}'
          '/disease-checks',
      queryParameters: query,
    );
  }

  Future<Map<String, String>> _headers({String? idempotencyKey}) async {
    final tokens = await _sessionStorage.readTokens();
    if (tokens == null) {
      throw const DiseaseCheckException(
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

  dynamic _decode(http.Response response) {
    if (response.body.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(response.body);
    } on FormatException {
      throw const DiseaseCheckException(
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
    throw DiseaseCheckException(
      message is String && message.isNotEmpty
          ? message
          : 'AquaSense could not complete the disease-check request.',
      code: code is String ? code : 'disease_check_request_failed',
    );
  }

  DiseaseCheckRecord _recordFromJson(Map<String, dynamic> json) {
    try {
      return DiseaseCheckRecord(
        id: json['id'] as String,
        facilityId: json['facilityId'] as String,
        predictedLabel: json['predictedLabel'] as String,
        confidence: (json['confidence'] as num).toDouble(),
        uncertain: json['uncertain'] as bool,
        modelVersion: json['modelVersion'] as String,
        tankLabel: json['tankLabel'] as String?,
        note: json['note'] as String?,
        checkedByName: json['checkedByName'] as String,
        checkedAt: DateTime.parse(json['checkedAt'] as String).toUtc(),
      );
    } on Object {
      throw const DiseaseCheckException(
        'The AquaSense server returned an unreadable disease check.',
        code: 'invalid_server_response',
      );
    }
  }

  static bool _hasText(String? value) =>
      value != null && value.trim().isNotEmpty;
}
