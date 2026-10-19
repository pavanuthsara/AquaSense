import '../domain/facility.dart';
import '../domain/facility_repository.dart';
import '../domain/facility_team.dart';

class DevelopmentFacilityRepository implements FacilityRepository {
  final List<Facility> _facilities = [];
  final Map<String, Facility> _creationRequests = {};
  final Map<String, List<FacilityMember>> _members = {};
  final List<FacilityInvitation> _invitations = [];

  @override
  Future<Facility> createFacility({
    required String name,
    required String timeZone,
    required String idempotencyKey,
  }) async {
    final existing = _creationRequests[idempotencyKey];
    if (existing != null) {
      if (existing.name != name.trim() || existing.timeZone != timeZone) {
        throw const FacilityException(
          'That setup request was already used with different details.',
          code: 'idempotency_conflict',
        );
      }
      return existing;
    }

    final facility = Facility(
      id: 'development-facility-${_facilities.length + 1}',
      name: name.trim(),
      timeZone: timeZone,
      role: FacilityRole.owner,
      createdAt: DateTime.now().toUtc(),
    );
    _facilities.add(facility);
    _members[facility.id] = [
      FacilityMember(
        id: 'development-owner-membership-${_facilities.length}',
        userId: 'development-owner',
        email: 'owner@aquasense.local',
        displayName: 'Development Owner',
        role: FacilityRole.owner,
        joinedAt: facility.createdAt,
      ),
    ];
    _creationRequests[idempotencyKey] = facility;
    return facility;
  }

  @override
  Future<Facility> getFacility(String facilityId) async {
    return _facilities.firstWhere(
      (facility) => facility.id == facilityId,
      orElse: () => throw const FacilityException(
        'The aquarium is no longer available.',
        code: 'facility_not_found',
      ),
    );
  }

  @override
  Future<List<Facility>> listFacilities() async =>
      List.unmodifiable(_facilities);

  @override
  Future<List<String>> listTimeZones() async => const [
    'Asia/Colombo',
    'Asia/Kolkata',
    'Asia/Singapore',
    'Australia/Sydney',
    'Europe/London',
    'UTC',
  ];

  @override
  Future<Facility> acceptInvitation(String invitationId) async {
    final index = _invitations.indexWhere((item) => item.id == invitationId);
    if (index == -1 ||
        _invitations[index].status != FacilityInvitationStatus.pending) {
      throw const FacilityException(
        'That invitation is no longer available.',
        code: 'invitation_unavailable',
      );
    }
    _invitations[index] = _invitations[index].copyWith(
      status: FacilityInvitationStatus.accepted,
    );
    return getFacility(_invitations[index].facilityId);
  }

  @override
  Future<FacilityInvitation> inviteWorker({
    required String facilityId,
    required String email,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (_invitations.any(
      (item) =>
          item.facilityId == facilityId &&
          item.email == normalizedEmail &&
          item.status == FacilityInvitationStatus.pending,
    )) {
      throw const FacilityException(
        'An active invitation already exists for that email.',
        code: 'invitation_already_pending',
      );
    }
    final facility = await getFacility(facilityId);
    final now = DateTime.now().toUtc();
    final invitation = FacilityInvitation(
      id: 'development-invitation-${_invitations.length + 1}',
      facilityId: facilityId,
      facilityName: facility.name,
      email: normalizedEmail,
      status: FacilityInvitationStatus.pending,
      expiresAt: now.add(const Duration(days: 7)),
      createdAt: now,
    );
    _invitations.add(invitation);
    return invitation;
  }

  @override
  Future<List<FacilityInvitation>> listFacilityInvitations(
    String facilityId,
  ) async => List.unmodifiable(
    _invitations.where((item) => item.facilityId == facilityId),
  );

  @override
  Future<List<FacilityMember>> listMembers(String facilityId) async {
    final existing = _members[facilityId];
    if (existing != null) {
      return List.unmodifiable(existing);
    }
    final facility = await getFacility(facilityId);
    return [
      FacilityMember(
        id: 'development-owner-membership-${facility.id}',
        userId: 'development-owner',
        email: 'owner@aquasense.local',
        displayName: 'Development Owner',
        role: facility.role,
        joinedAt: facility.createdAt,
      ),
    ];
  }

  @override
  Future<List<FacilityInvitation>> listMyPendingInvitations() async =>
      List.unmodifiable(
        _invitations.where(
          (item) => item.status == FacilityInvitationStatus.pending,
        ),
      );

  @override
  Future<void> removeWorker({
    required String facilityId,
    required String membershipId,
  }) async {
    _members[facilityId]?.removeWhere((item) => item.id == membershipId);
  }

  @override
  Future<void> revokeInvitation({
    required String facilityId,
    required String invitationId,
  }) async {
    final index = _invitations.indexWhere(
      (item) => item.id == invitationId && item.facilityId == facilityId,
    );
    if (index != -1) {
      _invitations[index] = _invitations[index].copyWith(
        status: FacilityInvitationStatus.revoked,
      );
    }
  }
}
