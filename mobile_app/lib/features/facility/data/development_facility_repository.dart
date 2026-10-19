import '../domain/facility.dart';
import '../domain/facility_repository.dart';
import '../domain/facility_team.dart';
import '../domain/tank_group.dart';

class DevelopmentFacilityRepository implements FacilityRepository {
  final List<Facility> _facilities = [];
  final Map<String, Facility> _creationRequests = {};
  final Map<String, List<FacilityMember>> _members = {};
  final List<FacilityInvitation> _invitations = [];
  final Map<String, List<TankGroup>> _tankGroups = {};

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

  @override
  Future<List<TankGroup>> listTankGroups(String facilityId) async {
    await getFacility(facilityId);
    final groups = [...?_tankGroups[facilityId]]
      ..sort((first, second) {
        if (first.archived != second.archived) {
          return first.archived ? 1 : -1;
        }
        return first.name.toLowerCase().compareTo(second.name.toLowerCase());
      });
    return List.unmodifiable(groups);
  }

  @override
  Future<TankGroup> createTankGroup({
    required String facilityId,
    required String name,
  }) async {
    _requireOwner(facilityId);
    final groups = _tankGroups.putIfAbsent(facilityId, () => []);
    final cleanName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    _rejectDuplicate(groups, cleanName);
    final now = DateTime.now().toUtc();
    final group = TankGroup(
      id: 'development-group-${groups.length + 1}',
      facilityId: facilityId,
      name: cleanName,
      tankCount: 0,
      archived: false,
      createdAt: now,
      updatedAt: now,
    );
    groups.add(group);
    return group;
  }

  @override
  Future<TankGroup> renameTankGroup({
    required String facilityId,
    required String groupId,
    required String name,
  }) async {
    _requireOwner(facilityId);
    final groups = _tankGroups[facilityId] ?? [];
    final index = groups.indexWhere((group) => group.id == groupId);
    if (index == -1) {
      throw const FacilityException(
        'The tank group was not found.',
        code: 'tank_group_not_found',
      );
    }
    final existing = groups[index];
    if (existing.archived) {
      throw const FacilityException(
        'An archived tank group cannot be renamed.',
        code: 'group_archived',
      );
    }
    final cleanName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    _rejectDuplicate(groups, cleanName, excludingId: groupId);
    final updated = existing.copyWith(
      name: cleanName,
      updatedAt: DateTime.now().toUtc(),
    );
    groups[index] = updated;
    return updated;
  }

  @override
  Future<TankGroup> archiveTankGroup({
    required String facilityId,
    required String groupId,
  }) async {
    _requireOwner(facilityId);
    final groups = _tankGroups[facilityId] ?? [];
    final index = groups.indexWhere((group) => group.id == groupId);
    if (index == -1) {
      throw const FacilityException(
        'The tank group was not found.',
        code: 'tank_group_not_found',
      );
    }
    final existing = groups[index];
    if (existing.tankCount > 0) {
      throw const FacilityException(
        'Move or archive every tank in this group before archiving it.',
        code: 'group_not_empty',
      );
    }
    if (existing.archived) {
      return existing;
    }
    final now = DateTime.now().toUtc();
    final archived = existing.copyWith(
      archived: true,
      archivedAt: now,
      updatedAt: now,
    );
    groups[index] = archived;
    return archived;
  }

  Facility _requireOwner(String facilityId) {
    final facility = _facilities.firstWhere(
      (item) => item.id == facilityId,
      orElse: () => throw const FacilityException(
        'The aquarium is no longer available.',
        code: 'facility_not_found',
      ),
    );
    if (facility.role != FacilityRole.owner) {
      throw const FacilityException(
        'Only an aquarium owner can manage tank groups.',
        code: 'owner_required',
      );
    }
    return facility;
  }

  void _rejectDuplicate(
    List<TankGroup> groups,
    String name, {
    String? excludingId,
  }) {
    if (groups.any(
      (group) =>
          !group.archived &&
          group.id != excludingId &&
          group.name.toLowerCase() == name.toLowerCase(),
    )) {
      throw const FacilityException(
        'An active tank group already uses that name.',
        code: 'tank_group_name_exists',
      );
    }
  }
}
