import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../auth/domain/auth_session_storage.dart';
import '../domain/facility.dart';
import '../domain/appetite_check.dart';
import '../domain/facility_repository.dart';
import '../domain/facility_team.dart';
import '../domain/feeder_calibration.dart';
import '../domain/feeding_monitoring.dart';
import '../domain/tank_group.dart';
import '../domain/tank.dart';

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
  Future<AppetiteCheck> requestAppetiteCheck({
    required String facilityId,
    required String tankId,
  }) async {
    final response = await _authorizedPost(
      '/api/v1/facilities/$facilityId/tanks/$tankId/appetite-checks',
    );
    final body = _decode(response);
    _requireSuccess(response, body);
    return AppetiteCheck.fromJson(body as Map<String, dynamic>);
  }

  @override
  Future<AppetiteCheck> getAppetiteCheck({
    required String facilityId,
    required String tankId,
    required String checkId,
  }) async {
    final response = await _authorizedGet(
      '/api/v1/facilities/$facilityId/tanks/$tankId/appetite-checks/$checkId',
    );
    final body = _decode(response);
    _requireSuccess(response, body);
    return AppetiteCheck.fromJson(body as Map<String, dynamic>);
  }

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

  @override
  Future<Facility> acceptInvitation(String invitationId) async {
    final response = await _authorizedPost(
      '/api/v1/invitations/$invitationId/accept',
    );
    final body = _decode(response);
    _requireSuccess(response, body);
    return _facilityFromJson(body as Map<String, dynamic>);
  }

  @override
  Future<FacilityInvitation> inviteWorker({
    required String facilityId,
    required String email,
  }) async {
    final response = await _authorizedPost(
      '/api/v1/facilities/$facilityId/invitations',
      body: {'email': email},
    );
    final body = _decode(response);
    _requireSuccess(response, body);
    return _invitationFromJson(body as Map<String, dynamic>);
  }

  @override
  Future<List<FacilityInvitation>> listFacilityInvitations(
    String facilityId,
  ) async {
    final response = await _authorizedGet(
      '/api/v1/facilities/$facilityId/invitations',
    );
    final body = _decode(response);
    _requireSuccess(response, body);
    return (body as List<dynamic>)
        .map((item) => _invitationFromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<List<FacilityMember>> listMembers(String facilityId) async {
    final response = await _authorizedGet(
      '/api/v1/facilities/$facilityId/members',
    );
    final body = _decode(response);
    _requireSuccess(response, body);
    return (body as List<dynamic>)
        .map((item) => _memberFromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<List<FacilityInvitation>> listMyPendingInvitations() async {
    final response = await _authorizedGet('/api/v1/invitations/me');
    final body = _decode(response);
    _requireSuccess(response, body);
    return (body as List<dynamic>)
        .map((item) => _invitationFromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<void> removeWorker({
    required String facilityId,
    required String membershipId,
  }) async {
    final response = await _authorizedDelete(
      '/api/v1/facilities/$facilityId/members/$membershipId',
    );
    _requireSuccess(response, _decode(response));
  }

  @override
  Future<void> revokeInvitation({
    required String facilityId,
    required String invitationId,
  }) async {
    final response = await _authorizedDelete(
      '/api/v1/facilities/$facilityId/invitations/$invitationId',
    );
    _requireSuccess(response, _decode(response));
  }

  @override
  Future<List<TankGroup>> listTankGroups(String facilityId) async {
    final response = await _authorizedGet(
      '/api/v1/facilities/$facilityId/tank-groups',
    );
    final body = _decode(response);
    _requireSuccess(response, body);
    return (body as List<dynamic>)
        .map((item) => _tankGroupFromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<TankGroup> createTankGroup({
    required String facilityId,
    required String name,
  }) async {
    final response = await _authorizedPost(
      '/api/v1/facilities/$facilityId/tank-groups',
      body: {'name': name},
    );
    final body = _decode(response);
    _requireSuccess(response, body);
    return _tankGroupFromJson(body as Map<String, dynamic>);
  }

  @override
  Future<TankGroup> renameTankGroup({
    required String facilityId,
    required String groupId,
    required String name,
  }) async {
    final response = await _authorizedPatch(
      '/api/v1/facilities/$facilityId/tank-groups/$groupId',
      body: {'name': name},
    );
    final body = _decode(response);
    _requireSuccess(response, body);
    return _tankGroupFromJson(body as Map<String, dynamic>);
  }

  @override
  Future<TankGroup> archiveTankGroup({
    required String facilityId,
    required String groupId,
  }) async {
    final response = await _authorizedPost(
      '/api/v1/facilities/$facilityId/tank-groups/$groupId/archive',
    );
    final body = _decode(response);
    _requireSuccess(response, body);
    return _tankGroupFromJson(body as Map<String, dynamic>);
  }

  @override
  Future<TankGroup> updateTankGroupFeedingSchedule({
    required String facilityId,
    required String groupId,
    required List<String> times,
    required bool automationEnabled,
  }) async {
    final response = await _authorizedPut(
      '/api/v1/facilities/$facilityId/tank-groups/$groupId/feeding-schedule',
      body: {'times': times, 'automationEnabled': automationEnabled},
    );
    final body = _decode(response);
    _requireSuccess(response, body);
    return _tankGroupFromJson(body as Map<String, dynamic>);
  }

  @override
  Future<TankPage> listTanks({
    required String facilityId,
    required int page,
    int size = 50,
    String? search,
    TankStatus? status,
    String? groupId,
    bool unassigned = false,
    String? tag,
  }) async {
    final response = await _authorizedGet(
      '/api/v1/facilities/$facilityId/tanks',
      queryParameters: {
        'page': '$page',
        'size': '$size',
        if (search != null && search.trim().isNotEmpty) 'query': search.trim(),
        if (status != null) 'status': status.name.toUpperCase(),
        if (groupId != null) 'groupId': groupId,
        if (unassigned) 'unassigned': 'true',
        if (tag != null && tag.isNotEmpty) 'tag': tag,
      },
    );
    final body = _decode(response);
    _requireSuccess(response, body);
    final json = body as Map<String, dynamic>;
    return TankPage(
      items: (json['items'] as List<dynamic>)
          .map((item) => _tankFromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      page: json['page'] as int,
      size: json['size'] as int,
      totalItems: json['totalItems'] as int,
      totalPages: json['totalPages'] as int,
    );
  }

  @override
  Future<TankDetail> getTankDetail({
    required String facilityId,
    required String tankId,
  }) async {
    final response = await _authorizedGet(
      '/api/v1/facilities/$facilityId/tanks/$tankId',
    );
    final body = _decode(response);
    _requireSuccess(response, body);
    return _tankDetailFromJson(body as Map<String, dynamic>);
  }

  @override
  Future<TankHardwareHealth> getTankDeviceHealth({
    required String facilityId,
    required String tankId,
  }) async {
    final response = await _authorizedGet(
      '/api/v1/facilities/$facilityId/tanks/$tankId/device-health',
    );
    final body = _decode(response);
    _requireSuccess(response, body);
    return _deviceHealthFromJson(body as Map<String, dynamic>);
  }

  @override
  Future<ProvisionedTankDevice> provisionTankDevice({
    required String facilityId,
    required String tankId,
    required TankDeviceType type,
  }) async {
    final response = await _authorizedPost(
      '/api/v1/facilities/$facilityId/tanks/$tankId/devices/${_deviceTypeToApi(type)}/provision',
    );
    final body = _decode(response);
    _requireSuccess(response, body);
    final json = body as Map<String, dynamic>;
    return ProvisionedTankDevice(
      deviceId: json['deviceId'] as String,
      type: _deviceTypeFromApi(json['type'] as String),
      heartbeatToken: json['heartbeatToken'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
    );
  }

  @override
  Future<TankDetail> updateTankFeedingSchedule({
    required String facilityId,
    required String tankId,
    required TankScheduleMode mode,
    required List<String> times,
  }) async {
    final response = await _authorizedPut(
      '/api/v1/facilities/$facilityId/tanks/$tankId/feeding-schedule',
      body: {
        'mode': mode == TankScheduleMode.inherited ? 'INHERITED' : 'OVERRIDE',
        'times': times,
      },
    );
    final body = _decode(response);
    _requireSuccess(response, body);
    return _tankDetailFromJson(body as Map<String, dynamic>);
  }

  @override
  Future<List<String>> listTankTags(String facilityId) async {
    final response = await _authorizedGet(
      '/api/v1/facilities/$facilityId/tank-tags',
    );
    final body = _decode(response);
    _requireSuccess(response, body);
    return (body as List<dynamic>).cast<String>();
  }

  @override
  Future<Tank> createTank({
    required String facilityId,
    required TankDraft draft,
  }) async {
    final response = await _authorizedPost(
      '/api/v1/facilities/$facilityId/tanks',
      body: _tankDraftToJson(draft),
    );
    final body = _decode(response);
    _requireSuccess(response, body);
    return _tankFromJson(body as Map<String, dynamic>);
  }

  @override
  Future<Tank> updateTank({
    required String facilityId,
    required String tankId,
    required TankDraft draft,
  }) async {
    final response = await _authorizedPatch(
      '/api/v1/facilities/$facilityId/tanks/$tankId',
      body: _tankDraftToJson(draft),
    );
    final body = _decode(response);
    _requireSuccess(response, body);
    return _tankFromJson(body as Map<String, dynamic>);
  }

  @override
  Future<Tank> archiveTank({
    required String facilityId,
    required String tankId,
  }) async {
    final response = await _authorizedPost(
      '/api/v1/facilities/$facilityId/tanks/$tankId/archive',
    );
    final body = _decode(response);
    _requireSuccess(response, body);
    return _tankFromJson(body as Map<String, dynamic>);
  }

  @override
  Future<FeederCalibration?> getFeederCalibration(String facilityId) async {
    final response = await _authorizedGet(
      '/api/v1/facilities/$facilityId/feeder-calibration',
    );
    final body = _decode(response);
    _requireSuccess(response, body);
    final json = body as Map<String, dynamic>;
    final calibration = json['calibration'];
    return calibration is Map<String, dynamic>
        ? _calibrationFromJson(calibration)
        : null;
  }

  @override
  Future<FeederCalibration> createFeederCalibration({
    required String facilityId,
    required FeederCalibrationDraft draft,
  }) async {
    final response = await _authorizedPost(
      '/api/v1/facilities/$facilityId/feeder-calibration',
      body: {
        'unitsPerFish': draft.unitsPerFish,
        'minimumUnits': draft.minimumUnits,
        'maximumUnits': draft.maximumUnits,
      },
    );
    final body = _decode(response);
    _requireSuccess(response, body);
    return _calibrationFromJson(body as Map<String, dynamic>);
  }

  @override
  Future<PortionPreview> getPortionPreview({
    required String facilityId,
    required String tankId,
    int? fishCount,
  }) async {
    final response = await _authorizedGet(
      '/api/v1/facilities/$facilityId/tanks/$tankId/portion-preview',
      queryParameters: {if (fishCount != null) 'fishCount': '$fishCount'},
    );
    final body = _decode(response);
    _requireSuccess(response, body);
    final json = body as Map<String, dynamic>;
    final calibration = json['calibration'];
    return PortionPreview(
      configured: json['configured'] as bool,
      fishCount: json['fishCount'] as int,
      calibration: calibration is Map<String, dynamic>
          ? _calibrationFromJson(calibration)
          : null,
      rawUnits: (json['rawUnits'] as num?)?.toDouble(),
      portionUnits: (json['portionUnits'] as num?)?.toDouble(),
      limit: switch (json['limitedBy']) {
        'NONE' => PortionLimit.none,
        'MINIMUM' => PortionLimit.minimum,
        'MAXIMUM' => PortionLimit.maximum,
        'ZERO_FISH' => PortionLimit.zeroFish,
        _ => PortionLimit.notConfigured,
      },
    );
  }

  @override
  Future<FeedingDashboard> getFeedingDashboard(String facilityId) async {
    final response = await _authorizedGet(
      '/api/v1/facilities/$facilityId/feeding-dashboard',
    );
    final body = _decode(response);
    _requireSuccess(response, body);
    return _feedingDashboardFromJson(body as Map<String, dynamic>);
  }

  @override
  Future<FeedingHistoryPage> listFeedingHistory({
    required String facilityId,
    String? tankId,
    String? groupId,
    FeedingSource? source,
    FeedingOutcome? outcome,
    DateTime? from,
    DateTime? to,
    String? cursor,
    int size = 25,
  }) async {
    final path = tankId == null
        ? '/api/v1/facilities/$facilityId/feeding-history'
        : '/api/v1/facilities/$facilityId/tanks/$tankId/feeding-history';
    final response = await _authorizedGet(
      path,
      queryParameters: {
        if (groupId != null) 'groupId': groupId,
        if (source != null) 'source': _feedingSourceToApi(source),
        if (outcome != null) 'outcome': _feedingOutcomeToApi(outcome),
        if (from != null) 'from': from.toUtc().toIso8601String(),
        if (to != null) 'to': to.toUtc().toIso8601String(),
        if (cursor != null) 'cursor': cursor,
        'size': '$size',
      },
    );
    final body = _decode(response);
    _requireSuccess(response, body);
    final json = body as Map<String, dynamic>;
    return FeedingHistoryPage(
      items: (json['items'] as List<dynamic>)
          .map(
            (item) => _feedingHistoryItemFromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      nextCursor: json['nextCursor'] as String?,
    );
  }

  Future<http.Response> _authorizedGet(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    try {
      final uri = _resolve(path);
      return await _client.get(
        queryParameters == null
            ? uri
            : uri.replace(queryParameters: queryParameters),
        headers: await _headers(),
      );
    } on http.ClientException {
      throw const FacilityException(
        'Could not connect to AquaSense. Check your connection and try again.',
        code: 'connection_error',
      );
    }
  }

  Future<http.Response> _authorizedPost(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      return await _client.post(
        _resolve(path),
        headers: await _headers(),
        body: body == null ? null : jsonEncode(body),
      );
    } on http.ClientException {
      throw const FacilityException(
        'Could not connect to AquaSense. Check your connection and try again.',
        code: 'connection_error',
      );
    }
  }

  Future<http.Response> _authorizedPatch(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    try {
      return await _client.patch(
        _resolve(path),
        headers: await _headers(),
        body: jsonEncode(body),
      );
    } on http.ClientException {
      throw const FacilityException(
        'Could not connect to AquaSense. Check your connection and try again.',
        code: 'connection_error',
      );
    }
  }

  Future<http.Response> _authorizedPut(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    try {
      return await _client.put(
        _resolve(path),
        headers: await _headers(),
        body: jsonEncode(body),
      );
    } on http.ClientException {
      throw const FacilityException(
        'Could not connect to AquaSense. Check your connection and try again.',
        code: 'connection_error',
      );
    }
  }

  Future<http.Response> _authorizedDelete(String path) async {
    try {
      return await _client.delete(_resolve(path), headers: await _headers());
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
      role: _roleFromJson(json['role']),
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
    );
  }

  FeedingDashboard _feedingDashboardFromJson(Map<String, dynamic> json) {
    return FeedingDashboard(
      generatedAt: DateTime.parse(json['generatedAt'] as String).toUtc(),
      totalTanks: json['totalTanks'] as int,
      automatedTanks: json['automatedTanks'] as int,
      upcomingCount: json['upcomingCount'] as int,
      pendingCommands: json['pendingCommands'] as int,
      delivered: json['delivered'] as int,
      skipped: json['skipped'] as int,
      blocked: json['blocked'] as int,
      failed: json['failed'] as int,
      unhealthyDeviceCount: json['unhealthyDeviceCount'] as int,
      upcoming: (json['upcoming'] as List<dynamic>)
          .map((item) {
            final value = item as Map<String, dynamic>;
            return UpcomingFeedingSession(
              tankId: value['tankId'] as String,
              tankName: value['tankName'] as String,
              groupId: value['groupId'] as String?,
              groupName: value['groupName'] as String?,
              scheduledFor: DateTime.parse(
                value['scheduledFor'] as String,
              ).toUtc(),
            );
          })
          .toList(growable: false),
      unhealthyDevices: (json['unhealthyDevices'] as List<dynamic>)
          .map((item) {
            final value = item as Map<String, dynamic>;
            return UnhealthyTankDevice(
              tankId: value['tankId'] as String,
              tankName: value['tankName'] as String,
              type: value['type'] as String,
              state: value['state'] as String,
              lastHeartbeatAt: value['lastHeartbeatAt'] == null
                  ? null
                  : DateTime.parse(value['lastHeartbeatAt'] as String).toUtc(),
            );
          })
          .toList(growable: false),
      recentSessions: (json['recentSessions'] as List<dynamic>)
          .map(
            (item) => _feedingHistoryItemFromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }

  FeedingHistoryItem _feedingHistoryItemFromJson(Map<String, dynamic> json) {
    DateTime? date(String key) =>
        json[key] == null ? null : DateTime.parse(json[key] as String).toUtc();
    return FeedingHistoryItem(
      id: json['id'] as String,
      tankId: json['tankId'] as String,
      tankName: json['tankName'] as String,
      groupId: json['groupId'] as String?,
      groupName: json['groupName'] as String?,
      scheduledFor: date('scheduledFor')!,
      source: json['source'] == 'MANUAL'
          ? FeedingSource.manual
          : FeedingSource.scheduled,
      outcome: _feedingOutcomeFromApi(json['outcome'] as String),
      portionUnits: (json['portionUnits'] as num?)?.toDouble(),
      commandSentAt: date('commandSentAt'),
      feedbackAt: date('feedbackAt'),
      reason: json['reason'] as String?,
    );
  }

  FeedingOutcome _feedingOutcomeFromApi(String value) => switch (value) {
    'PROCESSING' => FeedingOutcome.processing,
    'COMMAND_SENT' => FeedingOutcome.commandSent,
    'DELIVERED' => FeedingOutcome.delivered,
    'SKIPPED_LOW_APPETITE' => FeedingOutcome.skippedLowAppetite,
    'SKIPPED_LOW_CONFIDENCE' => FeedingOutcome.skippedLowConfidence,
    'SKIPPED_STALE_OBSERVATION' => FeedingOutcome.skippedStaleObservation,
    'SKIPPED_COUNT_INCONSISTENT' => FeedingOutcome.skippedCountInconsistent,
    'BLOCKED_AUTOMATION' => FeedingOutcome.blockedAutomation,
    'BLOCKED_COOLDOWN' => FeedingOutcome.blockedCooldown,
    'BLOCKED_UNHEALTHY_DEVICE' => FeedingOutcome.blockedUnhealthyDevice,
    'BLOCKED_CALIBRATION' => FeedingOutcome.blockedCalibration,
    'FAILED' => FeedingOutcome.failed,
    _ => throw const FacilityException(
      'The server returned an unknown feeding outcome.',
      code: 'invalid_server_response',
    ),
  };

  String _feedingSourceToApi(FeedingSource value) => switch (value) {
    FeedingSource.scheduled => 'SCHEDULED',
    FeedingSource.manual => 'MANUAL',
  };

  String _feedingOutcomeToApi(FeedingOutcome value) => switch (value) {
    FeedingOutcome.processing => 'PROCESSING',
    FeedingOutcome.commandSent => 'COMMAND_SENT',
    FeedingOutcome.delivered => 'DELIVERED',
    FeedingOutcome.skippedLowAppetite => 'SKIPPED_LOW_APPETITE',
    FeedingOutcome.skippedLowConfidence => 'SKIPPED_LOW_CONFIDENCE',
    FeedingOutcome.skippedStaleObservation => 'SKIPPED_STALE_OBSERVATION',
    FeedingOutcome.skippedCountInconsistent => 'SKIPPED_COUNT_INCONSISTENT',
    FeedingOutcome.blockedAutomation => 'BLOCKED_AUTOMATION',
    FeedingOutcome.blockedCooldown => 'BLOCKED_COOLDOWN',
    FeedingOutcome.blockedUnhealthyDevice => 'BLOCKED_UNHEALTHY_DEVICE',
    FeedingOutcome.blockedCalibration => 'BLOCKED_CALIBRATION',
    FeedingOutcome.failed => 'FAILED',
  };

  FeederCalibration _calibrationFromJson(Map<String, dynamic> json) {
    return FeederCalibration(
      id: json['id'] as String,
      version: json['version'] as int,
      unitsPerFish: (json['unitsPerFish'] as num).toDouble(),
      minimumUnits: (json['minimumUnits'] as num).toDouble(),
      maximumUnits: (json['maximumUnits'] as num).toDouble(),
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
    );
  }

  FacilityMember _memberFromJson(Map<String, dynamic> json) {
    return FacilityMember(
      id: json['id'] as String,
      userId: json['userId'] as String,
      email: json['email'] as String,
      displayName: json['displayName'] as String,
      role: _roleFromJson(json['role']),
      joinedAt: DateTime.parse(json['joinedAt'] as String).toUtc(),
    );
  }

  FacilityInvitation _invitationFromJson(Map<String, dynamic> json) {
    return FacilityInvitation(
      id: json['id'] as String,
      facilityId: json['facilityId'] as String,
      facilityName: json['facilityName'] as String,
      email: json['email'] as String,
      status: switch (json['status']) {
        'PENDING' => FacilityInvitationStatus.pending,
        'ACCEPTED' => FacilityInvitationStatus.accepted,
        'REVOKED' => FacilityInvitationStatus.revoked,
        'EXPIRED' => FacilityInvitationStatus.expired,
        _ => throw const FacilityException(
          'The AquaSense server returned an unknown invitation status.',
          code: 'invalid_server_response',
        ),
      },
      expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
    );
  }

  TankGroup _tankGroupFromJson(Map<String, dynamic> json) {
    final archivedAt = json['archivedAt'];
    final nextSessionAt = json['nextSessionAt'];
    return TankGroup(
      id: json['id'] as String,
      facilityId: json['facilityId'] as String,
      name: json['name'] as String,
      tankCount: json['tankCount'] as int,
      feedingTimes: (json['feedingTimes'] as List<dynamic>? ?? const [])
          .cast<String>(),
      feedingAutomationEnabled:
          json['feedingAutomationEnabled'] as bool? ?? false,
      nextSessionAt: nextSessionAt is String
          ? DateTime.parse(nextSessionAt).toUtc()
          : null,
      archived: json['archived'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
      archivedAt: archivedAt is String
          ? DateTime.parse(archivedAt).toUtc()
          : null,
    );
  }

  Map<String, dynamic> _tankDraftToJson(TankDraft draft) => {
    'name': draft.name,
    'code': draft.code,
    'expectedGuppyCount': draft.expectedGuppyCount,
    'groupId': draft.groupId,
    'tags': draft.tags,
    'automationEnabled': draft.automationEnabled,
    'notes': draft.notes,
  };

  Tank _tankFromJson(Map<String, dynamic> json) {
    DateTime? date(String key) {
      final value = json[key];
      return value is String ? DateTime.parse(value).toUtc() : null;
    }

    return Tank(
      id: json['id'] as String,
      facilityId: json['facilityId'] as String,
      name: json['name'] as String,
      code: json['code'] as String,
      expectedGuppyCount: json['expectedGuppyCount'] as int,
      detectedGuppyCount: json['detectedGuppyCount'] as int?,
      detectionConfidence: (json['detectionConfidence'] as num?)?.toDouble(),
      countObservedAt: date('countObservedAt'),
      groupId: json['groupId'] as String?,
      groupName: json['groupName'] as String?,
      tags: (json['tags'] as List<dynamic>).cast<String>(),
      automationEnabled: json['automationEnabled'] as bool,
      scheduleMode: json['scheduleMode'] == 'OVERRIDE'
          ? TankScheduleMode.override
          : TankScheduleMode.inherited,
      status: _tankStatusFromJson(json['status']),
      notes: json['notes'] as String?,
      createdAt: date('createdAt')!,
      updatedAt: date('updatedAt')!,
      archivedAt: date('archivedAt'),
    );
  }

  TankDetail _tankDetailFromJson(Map<String, dynamic> json) {
    DateTime? date(String key) {
      final value = json[key];
      return value is String ? DateTime.parse(value).toUtc() : null;
    }

    return TankDetail(
      tank: _tankFromJson(json['tank'] as Map<String, dynamic>),
      observationState: switch (json['observationState']) {
        'NO_DATA' => TankObservationState.noData,
        'CURRENT' => TankObservationState.current,
        'STALE' => TankObservationState.stale,
        _ => throw const FacilityException(
          'The server returned an unknown observation state.',
          code: 'invalid_server_response',
        ),
      },
      deviceStatus: switch (json['deviceStatus']) {
        'NOT_CONFIGURED' => TankDeviceStatus.notConfigured,
        'ONLINE' => TankDeviceStatus.online,
        'OFFLINE' => TankDeviceStatus.offline,
        'STALE' => TankDeviceStatus.stale,
        'UNHEALTHY' => TankDeviceStatus.unhealthy,
        _ => throw const FacilityException(
          'The server returned an unknown device status.',
          code: 'invalid_server_response',
        ),
      },
      deviceHealth: json['deviceHealth'] is Map<String, dynamic>
          ? _deviceHealthFromJson(json['deviceHealth'] as Map<String, dynamic>)
          : null,
      appetiteObservation: json['appetiteObservation'] is Map<String, dynamic>
          ? _appetiteObservationFromJson(
              json['appetiteObservation'] as Map<String, dynamic>,
            )
          : null,
      scheduleMode: switch (json['scheduleMode']) {
        'OVERRIDE' => TankScheduleMode.override,
        'INHERITED' || null => TankScheduleMode.inherited,
        _ => throw const FacilityException(
          'The server returned an unknown tank schedule mode.',
          code: 'invalid_server_response',
        ),
      },
      inheritedFeedingTimes:
          (json['inheritedFeedingTimes'] as List<dynamic>? ?? const [])
              .cast<String>(),
      feedingTimes: (json['feedingTimes'] as List<dynamic>).cast<String>(),
      lastFeedingAt: date('lastFeedingAt'),
      nextFeedingAt: date('nextFeedingAt'),
      recentActivity: (json['recentActivity'] as List<dynamic>)
          .map((item) {
            final activity = item as Map<String, dynamic>;
            return TankActivity(
              type: activity['type'] as String,
              title: activity['title'] as String,
              occurredAt: DateTime.parse(
                activity['occurredAt'] as String,
              ).toUtc(),
            );
          })
          .toList(growable: false),
    );
  }

  TankAppetiteObservation _appetiteObservationFromJson(
    Map<String, dynamic> json,
  ) {
    return TankAppetiteObservation(
      id: json['id'] as String,
      detectedGuppyCount: json['detectedGuppyCount'] as int,
      confidence: (json['confidence'] as num).toDouble(),
      appetiteResult: json['appetiteResult'] == 'LOW'
          ? AppetiteResult.low
          : AppetiteResult.high,
      modelVersion: json['modelVersion'] as String,
      observedAt: DateTime.parse(json['observedAt'] as String).toUtc(),
      receivedAt: DateTime.parse(json['receivedAt'] as String).toUtc(),
      validForFeedingDecision:
          json['validForFeedingDecision'] as bool? ?? false,
      ownerReviewRequired: json['ownerReviewRequired'] as bool? ?? false,
      reviewReasons: (json['reviewReasons'] as List<dynamic>? ?? const [])
          .cast<String>(),
    );
  }

  TankHardwareHealth _deviceHealthFromJson(Map<String, dynamic> json) {
    return TankHardwareHealth(
      overallState: _deviceStatusFromApi(json['overallState']),
      feedingAllowed: json['feedingAllowed'] as bool? ?? false,
      components: (json['components'] as List<dynamic>? ?? const [])
          .map((item) {
            final component = item as Map<String, dynamic>;
            return TankDeviceComponent(
              type: _deviceTypeFromApi(component['type'] as String),
              deviceId: component['deviceId'] as String?,
              state: _deviceStatusFromApi(component['state']),
              lastHeartbeatAt: component['lastHeartbeatAt'] == null
                  ? null
                  : DateTime.parse(
                      component['lastHeartbeatAt'] as String,
                    ).toUtc(),
              message: component['message'] as String?,
            );
          })
          .toList(growable: false),
    );
  }

  TankDeviceStatus _deviceStatusFromApi(dynamic value) => switch (value) {
    'ONLINE' => TankDeviceStatus.online,
    'OFFLINE' => TankDeviceStatus.offline,
    'STALE' => TankDeviceStatus.stale,
    'UNHEALTHY' => TankDeviceStatus.unhealthy,
    _ => TankDeviceStatus.notConfigured,
  };

  TankDeviceType _deviceTypeFromApi(String value) => switch (value) {
    'CAMERA' => TankDeviceType.camera,
    'EDGE_PROCESSOR' => TankDeviceType.edgeProcessor,
    'FEEDER' => TankDeviceType.feeder,
    _ => throw FormatException('Unknown device type: $value'),
  };

  String _deviceTypeToApi(TankDeviceType value) => switch (value) {
    TankDeviceType.camera => 'CAMERA',
    TankDeviceType.edgeProcessor => 'EDGE_PROCESSOR',
    TankDeviceType.feeder => 'FEEDER',
  };

  TankStatus _tankStatusFromJson(dynamic value) => switch (value) {
    'ACTIVE' => TankStatus.active,
    'PAUSED' => TankStatus.paused,
    'ARCHIVED' => TankStatus.archived,
    _ => throw const FacilityException(
      'The server returned an unknown tank status.',
      code: 'invalid_server_response',
    ),
  };

  FacilityRole _roleFromJson(dynamic value) {
    return switch (value) {
      'OWNER' => FacilityRole.owner,
      'WORKER' => FacilityRole.worker,
      _ => throw const FacilityException(
        'The AquaSense server returned an unknown facility role.',
        code: 'invalid_server_response',
      ),
    };
  }
}
