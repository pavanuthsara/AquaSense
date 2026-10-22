import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_app/features/auth/domain/auth_models.dart';
import 'package:mobile_app/features/auth/domain/auth_session_storage.dart';
import 'package:mobile_app/features/facility/data/http_facility_repository.dart';
import 'package:mobile_app/features/facility/domain/facility.dart';
import 'package:mobile_app/features/facility/domain/appetite_check.dart';
import 'package:mobile_app/features/facility/domain/facility_team.dart';
import 'package:mobile_app/features/facility/domain/feeder_calibration.dart';
import 'package:mobile_app/features/facility/domain/feeding_monitoring.dart';
import 'package:mobile_app/features/facility/domain/tank_group.dart';
import 'package:mobile_app/features/facility/domain/tank.dart';

void main() {
  test(
    'requests a fresh appetite check and reads the model result with authentication',
    () async {
      final requests = <http.Request>[];
      final repository = HttpFacilityRepository(
        apiBaseUrl: 'http://localhost:8080',
        sessionStorage: _MemorySessionStorage(),
        client: MockClient((request) async {
          requests.add(request);
          final completed = request.method == 'GET';
          return http.Response('''{
          "id":"check-1","tankId":"tank-1","status":"${completed ? 'COMPLETED' : 'PENDING'}",
          "requestedAt":"2026-10-22T10:00:00Z","expiresAt":"2026-10-22T10:01:00Z",
          "appetiteResult":${completed ? '"LOW"' : 'null'},
          "confidence":${completed ? '0.82' : 'null'},
          "observedAt":${completed ? '"2026-10-22T10:00:12Z"' : 'null'},
          "modelVersion":"random_forest_live_pre-v1"
        }''', completed ? 200 : 202);
        }),
      );
      final pending = await repository.requestAppetiteCheck(
        facilityId: 'facility-1',
        tankId: 'tank-1',
      );
      final result = await repository.getAppetiteCheck(
        facilityId: 'facility-1',
        tankId: 'tank-1',
        checkId: pending.id,
      );
      expect(pending.status, AppetiteCheckStatus.pending);
      expect(result.appetiteResult, AppetiteResult.low);
      expect(result.confidence, 0.82);
      expect(requests.first.method, 'POST');
      expect(
        requests.first.url.path,
        '/api/v1/facilities/facility-1/tanks/tank-1/appetite-checks',
      );
      expect(
        requests.last.url.path,
        '/api/v1/facilities/facility-1/tanks/tank-1/appetite-checks/check-1',
      );
      expect(
        requests.every(
          (request) =>
              request.headers['authorization'] == 'Bearer access-token',
        ),
        isTrue,
      );
    },
  );

  test('loads dashboard and filtered cursor feeding history', () async {
    final requests = <http.Request>[];
    final repository = HttpFacilityRepository(
      apiBaseUrl: 'https://api.example.com',
      sessionStorage: _MemorySessionStorage(),
      client: MockClient((request) async {
        requests.add(request);
        return request.url.path.endsWith('feeding-dashboard')
            ? http.Response(_feedingDashboardJson, 200)
            : http.Response(_feedingHistoryJson, 200);
      }),
    );

    final dashboard = await repository.getFeedingDashboard('facility-1');
    final history = await repository.listFeedingHistory(
      facilityId: 'facility-1',
      groupId: 'group-1',
      source: FeedingSource.scheduled,
      outcome: FeedingOutcome.delivered,
      cursor: 'next-page',
      size: 10,
    );

    expect(dashboard.totalTanks, 12);
    expect(dashboard.upcoming.single.tankName, 'Nursery 1');
    expect(dashboard.unhealthyDevices.single.state, 'OFFLINE');
    expect(history.items.single.outcome, FeedingOutcome.delivered);
    expect(history.nextCursor, 'cursor-2');
    expect(requests.last.url.queryParameters['groupId'], 'group-1');
    expect(requests.last.url.queryParameters['source'], 'SCHEDULED');
    expect(requests.last.url.queryParameters['outcome'], 'DELIVERED');
    expect(requests.last.url.queryParameters['cursor'], 'next-page');
    expect(requests.last.url.queryParameters['size'], '10');
  });

  test('lists facilities with the saved bearer token', () async {
    late http.Request capturedRequest;
    final repository = HttpFacilityRepository(
      apiBaseUrl: 'https://api.example.com',
      sessionStorage: _MemorySessionStorage(),
      client: MockClient((request) async {
        capturedRequest = request;
        return http.Response('[$_facilityJson]', 200);
      }),
    );

    final facilities = await repository.listFacilities();

    expect(capturedRequest.url.path, '/api/v1/facilities');
    expect(capturedRequest.headers['authorization'], 'Bearer access-token');
    expect(facilities.single.name, 'Blue Reef');
    expect(facilities.single.role, FacilityRole.owner);
  });

  test('creation sends a stable idempotency key and parses response', () async {
    late http.Request capturedRequest;
    final repository = HttpFacilityRepository(
      apiBaseUrl: 'https://api.example.com/base',
      sessionStorage: _MemorySessionStorage(),
      client: MockClient((request) async {
        capturedRequest = request;
        return http.Response(_facilityJson, 201);
      }),
    );

    final facility = await repository.createFacility(
      name: 'Blue Reef',
      timeZone: 'Asia/Colombo',
      idempotencyKey: 'setup-request-123',
    );

    expect(capturedRequest.url.path, '/base/api/v1/facilities');
    expect(capturedRequest.headers['idempotency-key'], 'setup-request-123');
    expect(capturedRequest.body, contains('Asia/Colombo'));
    expect(facility.timeZone, 'Asia/Colombo');
  });

  test('missing session prevents facility requests', () async {
    final repository = HttpFacilityRepository(
      apiBaseUrl: 'https://api.example.com',
      sessionStorage: _MemorySessionStorage(hasSession: false),
      client: MockClient((request) async => http.Response('[]', 200)),
    );

    expect(
      repository.listFacilities(),
      throwsA(
        isA<FacilityException>().having(
          (error) => error.code,
          'code',
          'missing_session',
        ),
      ),
    );
  });

  test('lists and accepts email-bound invitations', () async {
    final requests = <http.Request>[];
    final repository = HttpFacilityRepository(
      apiBaseUrl: 'https://api.example.com',
      sessionStorage: _MemorySessionStorage(),
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/api/v1/invitations/me') {
          return http.Response('[$_invitationJson]', 200);
        }
        return http.Response(_workerFacilityJson, 200);
      }),
    );

    final invitations = await repository.listMyPendingInvitations();
    final facility = await repository.acceptInvitation(invitations.single.id);

    expect(invitations.single.status, FacilityInvitationStatus.pending);
    expect(invitations.single.facilityName, 'Blue Reef');
    expect(requests.last.method, 'POST');
    expect(requests.last.url.path, '/api/v1/invitations/invitation-1/accept');
    expect(facility.role, FacilityRole.worker);
  });

  test('owner team operations use facility-scoped endpoints', () async {
    final requests = <http.Request>[];
    final repository = HttpFacilityRepository(
      apiBaseUrl: 'https://api.example.com',
      sessionStorage: _MemorySessionStorage(),
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'POST') {
          return http.Response(_invitationJson, 201);
        }
        if (request.method == 'DELETE') {
          return http.Response('', 204);
        }
        return http.Response('[$_memberJson]', 200);
      }),
    );

    final members = await repository.listMembers('facility-1');
    await repository.inviteWorker(
      facilityId: 'facility-1',
      email: 'worker@example.com',
    );
    await repository.revokeInvitation(
      facilityId: 'facility-1',
      invitationId: 'invitation-1',
    );
    await repository.removeWorker(
      facilityId: 'facility-1',
      membershipId: 'membership-1',
    );

    expect(members.single.displayName, 'Test Owner');
    expect(requests[0].url.path, '/api/v1/facilities/facility-1/members');
    expect(requests[1].body, contains('worker@example.com'));
    expect(
      requests[2].url.path,
      '/api/v1/facilities/facility-1/invitations/invitation-1',
    );
    expect(
      requests[3].url.path,
      '/api/v1/facilities/facility-1/members/membership-1',
    );
  });

  test('tank group operations use facility-scoped endpoints', () async {
    final requests = <http.Request>[];
    final repository = HttpFacilityRepository(
      apiBaseUrl: 'https://api.example.com',
      sessionStorage: _MemorySessionStorage(),
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return http.Response('[$_tankGroupJson]', 200);
        }
        return http.Response(
          _tankGroupJson,
          request.method == 'POST' ? 201 : 200,
        );
      }),
    );

    final groups = await repository.listTankGroups('facility-1');
    final created = await repository.createTankGroup(
      facilityId: 'facility-1',
      name: 'Nursery',
    );
    await repository.renameTankGroup(
      facilityId: 'facility-1',
      groupId: created.id,
      name: 'Juvenile',
    );
    final scheduled = await repository.updateTankGroupFeedingSchedule(
      facilityId: 'facility-1',
      groupId: created.id,
      times: const ['08:00', '16:00'],
      automationEnabled: true,
    );
    await repository.archiveTankGroup(
      facilityId: 'facility-1',
      groupId: created.id,
    );

    expect(groups.single, isA<TankGroup>());
    expect(groups.single.tankCount, 12);
    expect(scheduled.feedingTimes, ['08:00', '16:00']);
    expect(scheduled.feedingAutomationEnabled, isTrue);
    expect(scheduled.nextSessionAt, DateTime.parse('2026-10-20T02:30:00Z'));
    expect(requests.map((request) => request.method), [
      'GET',
      'POST',
      'PATCH',
      'PUT',
      'POST',
    ]);
    expect(requests[0].url.path, '/api/v1/facilities/facility-1/tank-groups');
    expect(requests[1].body, contains('Nursery'));
    expect(
      requests[2].url.path,
      '/api/v1/facilities/facility-1/tank-groups/group-1',
    );
    expect(
      requests[3].url.path,
      '/api/v1/facilities/facility-1/tank-groups/group-1/feeding-schedule',
    );
    expect(requests[3].body, contains('"automationEnabled":true'));
    expect(
      requests[4].url.path,
      '/api/v1/facilities/facility-1/tank-groups/group-1/archive',
    );
  });

  test(
    'tank inventory and detail operations preserve filters and states',
    () async {
      final requests = <http.Request>[];
      final repository = HttpFacilityRepository(
        apiBaseUrl: 'https://api.example.com',
        sessionStorage: _MemorySessionStorage(),
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/tank-tags')) {
            return http.Response('["breeding","priority"]', 200);
          }
          if (request.method == 'GET' && request.url.path.endsWith('/tanks')) {
            return http.Response(_tankPageJson, 200);
          }
          if (request.method == 'GET') {
            return http.Response(_tankDetailJson, 200);
          }
          if (request.url.path.endsWith('/feeding-schedule')) {
            return http.Response(_tankDetailJson, 200);
          }
          return http.Response(_tankJson, request.method == 'POST' ? 201 : 200);
        }),
      );

      final page = await repository.listTanks(
        facilityId: 'facility-1',
        page: 2,
        search: 'N-001',
        status: TankStatus.active,
        groupId: 'group-1',
        tag: 'breeding',
      );
      final detail = await repository.getTankDetail(
        facilityId: 'facility-1',
        tankId: 'tank-1',
      );
      final tags = await repository.listTankTags('facility-1');
      final scheduled = await repository.updateTankFeedingSchedule(
        facilityId: 'facility-1',
        tankId: 'tank-1',
        mode: TankScheduleMode.override,
        times: const ['08:00', '16:00'],
      );
      final draft = TankDraft(
        name: 'Nursery 1',
        code: 'N-001',
        expectedGuppyCount: 80,
        groupId: 'group-1',
        tags: const ['breeding'],
        automationEnabled: true,
        notes: 'Observe',
      );
      await repository.createTank(facilityId: 'facility-1', draft: draft);
      await repository.updateTank(
        facilityId: 'facility-1',
        tankId: 'tank-1',
        draft: draft,
      );
      await repository.archiveTank(facilityId: 'facility-1', tankId: 'tank-1');

      expect(page.totalItems, 1000);
      expect(page.items.single.name, 'Nursery 1');
      expect(requests.first.url.queryParameters['status'], 'ACTIVE');
      expect(requests.first.url.queryParameters['tag'], 'breeding');
      expect(detail.observationState, TankObservationState.stale);
      expect(detail.deviceStatus, TankDeviceStatus.offline);
      expect(detail.appetiteObservation?.appetiteResult, AppetiteResult.low);
      expect(detail.appetiteObservation?.ownerReviewRequired, isTrue);
      expect(detail.appetiteObservation?.reviewReasons, [
        'LOW_CONFIDENCE',
        'COUNT_INCONSISTENT',
      ]);
      expect(detail.scheduleMode, TankScheduleMode.override);
      expect(scheduled.feedingTimes, ['08:00', '16:00']);
      expect(detail.recentActivity.single.title, 'Tank created');
      expect(tags, ['breeding', 'priority']);
      expect(requests[3].method, 'PUT');
      expect(requests[3].body, contains('"mode":"OVERRIDE"'));
      expect(requests[4].body, contains('expectedGuppyCount'));
      expect(requests[5].method, 'PATCH');
      expect(requests[6].url.path, endsWith('/tank-1/archive'));
    },
  );

  test(
    'feeder calibration and portion preview use facility endpoints',
    () async {
      final requests = <http.Request>[];
      final repository = HttpFacilityRepository(
        apiBaseUrl: 'https://api.example.com',
        sessionStorage: _MemorySessionStorage(),
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/portion-preview')) {
            return http.Response(_portionPreviewJson, 200);
          }
          if (request.method == 'POST') {
            return http.Response(_calibrationJson, 201);
          }
          return http.Response(
            '{"configured":true,"calibration":$_calibrationJson}',
            200,
          );
        }),
      );

      final active = await repository.getFeederCalibration('facility-1');
      final created = await repository.createFeederCalibration(
        facilityId: 'facility-1',
        draft: const FeederCalibrationDraft(
          unitsPerFish: 0.1,
          minimumUnits: 1,
          maximumUnits: 5,
        ),
      );
      final preview = await repository.getPortionPreview(
        facilityId: 'facility-1',
        tankId: 'tank-1',
        fishCount: 80,
      );

      expect(active?.version, 1);
      expect(created.maximumUnits, 5);
      expect(preview.portionUnits, 5);
      expect(preview.limit, PortionLimit.maximum);
      expect(requests[1].body, contains('"unitsPerFish":0.1'));
      expect(requests[2].url.queryParameters['fishCount'], '80');
    },
  );

  test('device health and provisioning use tank hardware endpoints', () async {
    final requests = <http.Request>[];
    final repository = HttpFacilityRepository(
      apiBaseUrl: 'https://api.example.com',
      sessionStorage: _MemorySessionStorage(),
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'POST') {
          return http.Response(
            '{"deviceId":"device-1","type":"FEEDER",'
            '"heartbeatToken":"secret-token",'
            '"createdAt":"2026-10-20T10:00:00Z"}',
            201,
          );
        }
        return http.Response(
          '{"overallState":"UNHEALTHY","feedingAllowed":false,'
          '"components":[{"type":"CAMERA","deviceId":"camera-1",'
          '"state":"ONLINE","lastHeartbeatAt":"2026-10-20T09:59:30Z",'
          '"message":"Ready"},{"type":"EDGE_PROCESSOR",'
          '"deviceId":null,"state":"NOT_CONFIGURED",'
          '"lastHeartbeatAt":null,"message":null},{"type":"FEEDER",'
          '"deviceId":"feeder-1","state":"UNHEALTHY",'
          '"lastHeartbeatAt":"2026-10-20T09:59:45Z",'
          '"message":"Motor jam"}]}',
          200,
        );
      }),
    );

    final health = await repository.getTankDeviceHealth(
      facilityId: 'facility-1',
      tankId: 'tank-1',
    );
    final provisioned = await repository.provisionTankDevice(
      facilityId: 'facility-1',
      tankId: 'tank-1',
      type: TankDeviceType.feeder,
    );

    expect(health.overallState, TankDeviceStatus.unhealthy);
    expect(health.feedingAllowed, isFalse);
    expect(health.components.last.message, 'Motor jam');
    expect(provisioned.heartbeatToken, 'secret-token');
    expect(requests.first.method, 'GET');
    expect(requests.last.method, 'POST');
    expect(
      requests.last.url.path,
      '/api/v1/facilities/facility-1/tanks/tank-1/devices/FEEDER/provision',
    );
  });
}

const _facilityJson = '''
{
  "id": "00000000-0000-0000-0000-000000000010",
  "name": "Blue Reef",
  "timeZone": "Asia/Colombo",
  "role": "OWNER",
  "createdAt": "2026-10-15T08:00:00Z"
}
''';

const _workerFacilityJson = '''
{
  "id": "facility-1",
  "name": "Blue Reef",
  "timeZone": "Asia/Colombo",
  "role": "WORKER",
  "createdAt": "2026-10-15T08:00:00Z"
}
''';

const _invitationJson = '''
{
  "id": "invitation-1",
  "facilityId": "facility-1",
  "facilityName": "Blue Reef",
  "email": "worker@example.com",
  "status": "PENDING",
  "expiresAt": "2026-10-26T08:00:00Z",
  "createdAt": "2026-10-19T08:00:00Z"
}
''';

const _memberJson = '''
{
  "id": "membership-1",
  "userId": "user-1",
  "email": "owner@example.com",
  "displayName": "Test Owner",
  "role": "OWNER",
  "joinedAt": "2026-10-15T08:00:00Z"
}
''';

const _tankGroupJson = '''
{
  "id": "group-1",
  "facilityId": "facility-1",
  "name": "Nursery",
  "tankCount": 12,
  "archived": false,
  "feedingTimes": ["08:00", "16:00"],
  "feedingAutomationEnabled": true,
  "nextSessionAt": "2026-10-20T02:30:00Z",
  "createdAt": "2026-10-19T08:00:00Z",
  "updatedAt": "2026-10-19T08:00:00Z",
  "archivedAt": null
}
''';

const _tankJson = '''
{
  "id": "tank-1",
  "facilityId": "facility-1",
  "name": "Nursery 1",
  "code": "N-001",
  "expectedGuppyCount": 80,
  "detectedGuppyCount": 76,
  "detectionConfidence": 0.93,
  "countObservedAt": "2026-10-19T07:00:00Z",
  "groupId": "group-1",
  "groupName": "Nursery",
  "tags": ["breeding"],
  "automationEnabled": true,
  "status": "ACTIVE",
  "notes": "Observe",
  "createdAt": "2026-10-18T08:00:00Z",
  "updatedAt": "2026-10-19T08:00:00Z",
  "archivedAt": null
}
''';

const _tankPageJson =
    '''
{
  "items": [$_tankJson],
  "page": 2,
  "size": 50,
  "totalItems": 1000,
  "totalPages": 20
}
''';

const _tankDetailJson =
    '''
{
  "tank": $_tankJson,
  "observationState": "STALE",
  "deviceStatus": "OFFLINE",
  "appetiteObservation": {
    "id": "observation-1",
    "tankId": "tank-1",
    "detectedGuppyCount": 40,
    "confidence": 0.61,
    "appetiteResult": "LOW",
    "modelVersion": "guppy-appetite-v1",
    "observedAt": "2026-10-19T07:58:00Z",
    "receivedAt": "2026-10-19T07:58:02Z",
    "validForFeedingDecision": false,
    "ownerReviewRequired": true,
    "reviewReasons": ["LOW_CONFIDENCE", "COUNT_INCONSISTENT"]
  },
  "scheduleMode": "OVERRIDE",
  "inheritedFeedingTimes": ["07:00", "17:00"],
  "feedingTimes": ["08:00", "16:00"],
  "lastFeedingAt": "2026-10-19T08:00:00Z",
  "nextFeedingAt": "2026-10-19T16:00:00Z",
  "recentActivity": [
    {"type":"TANK_CREATED","title":"Tank created","occurredAt":"2026-10-18T08:00:00Z"}
  ]
}
''';

const _calibrationJson = '''
{
  "id": "calibration-1",
  "version": 1,
  "unitsPerFish": 0.1,
  "minimumUnits": 1.0,
  "maximumUnits": 5.0,
  "createdAt": "2026-10-20T08:00:00Z"
}
''';

const _portionPreviewJson =
    '''
{
  "configured": true,
  "fishCount": 80,
  "calibration": $_calibrationJson,
  "rawUnits": 8.0,
  "portionUnits": 5.0,
  "limitedBy": "MAXIMUM"
}
''';

const _feedingItemJson = '''
{
  "id":"session-1",
  "tankId":"tank-1",
  "tankName":"Nursery 1",
  "groupId":"group-1",
  "groupName":"Nursery",
  "scheduledFor":"2026-10-21T08:00:00Z",
  "source":"SCHEDULED",
  "outcome":"DELIVERED",
  "portionUnits":4.5,
  "commandSentAt":"2026-10-21T08:00:01Z",
  "feedbackAt":"2026-10-21T08:00:04Z",
  "reason":null
}
''';

const _feedingDashboardJson =
    '''
{
  "generatedAt":"2026-10-21T09:00:00Z",
  "totalTanks":12,
  "automatedTanks":10,
  "upcomingCount":4,
  "pendingCommands":1,
  "delivered":8,
  "skipped":2,
  "blocked":1,
  "failed":1,
  "unhealthyDeviceCount":1,
  "upcoming":[{
    "tankId":"tank-1","tankName":"Nursery 1","groupId":"group-1",
    "groupName":"Nursery","scheduledFor":"2026-10-21T10:00:00Z"
  }],
  "unhealthyDevices":[{
    "tankId":"tank-2","tankName":"Nursery 2","type":"FEEDER",
    "state":"OFFLINE","lastHeartbeatAt":null
  }],
  "recentSessions":[$_feedingItemJson]
}
''';

const _feedingHistoryJson =
    '''
{"items":[$_feedingItemJson],"nextCursor":"cursor-2"}
''';

class _MemorySessionStorage implements AuthSessionStorage {
  _MemorySessionStorage({this.hasSession = true});

  final bool hasSession;

  @override
  Future<void> clear() async {}

  @override
  Future<AuthTokens?> readTokens() async {
    if (!hasSession) {
      return null;
    }
    return AuthTokens(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
  }

  @override
  Future<void> writeTokens(AuthTokens tokens) async {}
}
