import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_app/features/auth/domain/auth_models.dart';
import 'package:mobile_app/features/auth/domain/auth_session_storage.dart';
import 'package:mobile_app/features/facility/data/http_facility_repository.dart';
import 'package:mobile_app/features/facility/domain/facility.dart';
import 'package:mobile_app/features/facility/domain/facility_team.dart';

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
