import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_app/features/auth/domain/auth_models.dart';
import 'package:mobile_app/features/auth/domain/auth_session_storage.dart';
import 'package:mobile_app/features/facility/data/http_facility_repository.dart';
import 'package:mobile_app/features/facility/domain/facility.dart';
import 'package:mobile_app/features/facility/domain/facility_team.dart';
import 'package:mobile_app/features/facility/domain/feeder_calibration.dart';
import 'package:mobile_app/features/facility/domain/tank_group.dart';
import 'package:mobile_app/features/facility/domain/tank.dart';

void main() {
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
