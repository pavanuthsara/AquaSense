import 'package:mobile_app/features/facility/domain/facility.dart';
import 'package:mobile_app/features/facility/domain/facility_repository.dart';
import 'package:mobile_app/features/facility/domain/facility_team.dart';
import 'package:mobile_app/features/facility/domain/tank_group.dart';

class FakeFacilityRepository implements FacilityRepository {
  FakeFacilityRepository({
    List<Facility>? facilities,
    List<FacilityInvitation>? invitations,
    Map<String, List<FacilityMember>>? members,
    Map<String, List<TankGroup>>? tankGroups,
    this.listError,
    this.createFailures = 0,
  }) : facilities = facilities ?? [],
       invitations = invitations ?? [],
       members = members ?? {},
       tankGroups = tankGroups ?? {};

  final List<Facility> facilities;
  final List<FacilityInvitation> invitations;
  final Map<String, List<FacilityMember>> members;
  final Map<String, List<TankGroup>> tankGroups;
  Object? listError;
  int createFailures;
  int listCalls = 0;
  int createCalls = 0;
  int getCalls = 0;
  int listTankGroupsCalls = 0;
  final List<String> creationKeys = [];
  final Set<String> inaccessibleFacilityIds = {};

  static Facility facility({
    String id = 'facility-1',
    String name = 'Test Aquarium',
    String timeZone = 'Asia/Colombo',
    FacilityRole role = FacilityRole.owner,
  }) {
    return Facility(
      id: id,
      name: name,
      timeZone: timeZone,
      role: role,
      createdAt: DateTime.utc(2026, 10, 15),
    );
  }

  @override
  Future<Facility> createFacility({
    required String name,
    required String timeZone,
    required String idempotencyKey,
  }) async {
    createCalls += 1;
    creationKeys.add(idempotencyKey);
    if (createFailures > 0) {
      createFailures -= 1;
      throw const FacilityException('Temporary setup failure.');
    }
    final existing = facilities.cast<Facility?>().firstWhere(
      (facility) => facility?.name == name && facility?.timeZone == timeZone,
      orElse: () => null,
    );
    if (existing != null) {
      return existing;
    }
    final created = facility(
      id: 'facility-${facilities.length + 1}',
      name: name,
      timeZone: timeZone,
    );
    facilities.add(created);
    return created;
  }

  @override
  Future<Facility> getFacility(String facilityId) async {
    getCalls += 1;
    if (inaccessibleFacilityIds.remove(facilityId)) {
      facilities.removeWhere((facility) => facility.id == facilityId);
      throw const FacilityException(
        'The aquarium is no longer available.',
        code: 'facility_not_found',
      );
    }
    return facilities.firstWhere(
      (facility) => facility.id == facilityId,
      orElse: () => throw const FacilityException(
        'The aquarium is no longer available.',
        code: 'facility_not_found',
      ),
    );
  }

  @override
  Future<List<Facility>> listFacilities() async {
    listCalls += 1;
    final error = listError;
    if (error != null) {
      throw error;
    }
    return List.unmodifiable(facilities);
  }

  @override
  Future<List<String>> listTimeZones() async => const [
    'Asia/Colombo',
    'Europe/London',
    'UTC',
  ];

  @override
  Future<Facility> acceptInvitation(String invitationId) async {
    final index = invitations.indexWhere((item) => item.id == invitationId);
    if (index == -1) {
      throw const FacilityException('Invitation not found.');
    }
    final invitation = invitations[index];
    invitations.removeAt(index);
    final existing = facilities.cast<Facility?>().firstWhere(
      (item) => item?.id == invitation.facilityId,
      orElse: () => null,
    );
    if (existing != null) {
      return existing;
    }
    final accepted = facility(
      id: invitation.facilityId,
      name: invitation.facilityName,
      role: FacilityRole.worker,
    );
    facilities.add(accepted);
    return accepted;
  }

  @override
  Future<FacilityInvitation> inviteWorker({
    required String facilityId,
    required String email,
  }) async {
    final aquarium = await getFacility(facilityId);
    final now = DateTime.now().toUtc();
    final invitation = FacilityInvitation(
      id: 'invitation-${invitations.length + 1}',
      facilityId: facilityId,
      facilityName: aquarium.name,
      email: email.trim().toLowerCase(),
      status: FacilityInvitationStatus.pending,
      expiresAt: now.add(const Duration(days: 7)),
      createdAt: now,
    );
    invitations.add(invitation);
    return invitation;
  }

  @override
  Future<List<FacilityInvitation>> listFacilityInvitations(
    String facilityId,
  ) async => List.unmodifiable(
    invitations.where((item) => item.facilityId == facilityId),
  );

  @override
  Future<List<FacilityMember>> listMembers(String facilityId) async =>
      List.unmodifiable(members[facilityId] ?? const []);

  @override
  Future<List<FacilityInvitation>> listMyPendingInvitations() async =>
      List.unmodifiable(
        invitations.where(
          (item) => item.status == FacilityInvitationStatus.pending,
        ),
      );

  @override
  Future<void> removeWorker({
    required String facilityId,
    required String membershipId,
  }) async {
    members[facilityId]?.removeWhere((item) => item.id == membershipId);
  }

  @override
  Future<void> revokeInvitation({
    required String facilityId,
    required String invitationId,
  }) async {
    final index = invitations.indexWhere(
      (item) => item.facilityId == facilityId && item.id == invitationId,
    );
    if (index != -1) {
      invitations[index] = invitations[index].copyWith(
        status: FacilityInvitationStatus.revoked,
      );
    }
  }

  @override
  Future<List<TankGroup>> listTankGroups(String facilityId) async {
    listTankGroupsCalls += 1;
    final result = List<TankGroup>.unmodifiable(
      tankGroups[facilityId] ?? const [],
    );
    return result;
  }

  @override
  Future<TankGroup> createTankGroup({
    required String facilityId,
    required String name,
  }) async {
    _requireOwner(facilityId);
    final groups = tankGroups.putIfAbsent(facilityId, () => []);
    final now = DateTime.now().toUtc();
    final group = TankGroup(
      id: 'group-${groups.length + 1}',
      facilityId: facilityId,
      name: name.trim(),
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
    final groups = tankGroups[facilityId] ?? [];
    final index = groups.indexWhere((group) => group.id == groupId);
    if (index == -1) {
      throw const FacilityException(
        'The tank group was not found.',
        code: 'tank_group_not_found',
      );
    }
    final updated = groups[index].copyWith(
      name: name.trim(),
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
    final groups = tankGroups[facilityId] ?? [];
    final index = groups.indexWhere((group) => group.id == groupId);
    if (index == -1) {
      throw const FacilityException(
        'The tank group was not found.',
        code: 'tank_group_not_found',
      );
    }
    if (groups[index].tankCount > 0) {
      throw const FacilityException(
        'Move or archive every tank in this group before archiving it.',
        code: 'group_not_empty',
      );
    }
    final now = DateTime.now().toUtc();
    final archived = groups[index].copyWith(
      archived: true,
      archivedAt: now,
      updatedAt: now,
    );
    groups[index] = archived;
    return archived;
  }

  void _requireOwner(String facilityId) {
    final facility = facilities.firstWhere(
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
  }
}
