import 'package:mobile_app/features/facility/domain/facility.dart';
import 'package:mobile_app/features/facility/domain/facility_repository.dart';
import 'package:mobile_app/features/facility/domain/facility_team.dart';

class FakeFacilityRepository implements FacilityRepository {
  FakeFacilityRepository({
    List<Facility>? facilities,
    List<FacilityInvitation>? invitations,
    Map<String, List<FacilityMember>>? members,
    this.listError,
    this.createFailures = 0,
  }) : facilities = facilities ?? [],
       invitations = invitations ?? [],
       members = members ?? {};

  final List<Facility> facilities;
  final List<FacilityInvitation> invitations;
  final Map<String, List<FacilityMember>> members;
  Object? listError;
  int createFailures;
  int listCalls = 0;
  int createCalls = 0;
  int getCalls = 0;
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
}
