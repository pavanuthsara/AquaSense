import 'facility.dart';
import 'facility_team.dart';
import 'tank_group.dart';
import 'tank.dart';

abstract interface class FacilityRepository {
  Future<List<Facility>> listFacilities();

  Future<Facility> getFacility(String facilityId);

  Future<List<String>> listTimeZones();

  Future<Facility> createFacility({
    required String name,
    required String timeZone,
    required String idempotencyKey,
  });

  Future<List<FacilityMember>> listMembers(String facilityId);

  Future<List<FacilityInvitation>> listFacilityInvitations(String facilityId);

  Future<List<FacilityInvitation>> listMyPendingInvitations();

  Future<FacilityInvitation> inviteWorker({
    required String facilityId,
    required String email,
  });

  Future<Facility> acceptInvitation(String invitationId);

  Future<void> revokeInvitation({
    required String facilityId,
    required String invitationId,
  });

  Future<void> removeWorker({
    required String facilityId,
    required String membershipId,
  });

  Future<List<TankGroup>> listTankGroups(String facilityId);

  Future<TankGroup> createTankGroup({
    required String facilityId,
    required String name,
  });

  Future<TankGroup> renameTankGroup({
    required String facilityId,
    required String groupId,
    required String name,
  });

  Future<TankGroup> archiveTankGroup({
    required String facilityId,
    required String groupId,
  });

  Future<TankPage> listTanks({
    required String facilityId,
    required int page,
    int size = 50,
    String? search,
    TankStatus? status,
    String? groupId,
    bool unassigned = false,
    String? tag,
  });

  Future<TankDetail> getTankDetail({
    required String facilityId,
    required String tankId,
  });

  Future<List<String>> listTankTags(String facilityId);

  Future<Tank> createTank({
    required String facilityId,
    required TankDraft draft,
  });

  Future<Tank> updateTank({
    required String facilityId,
    required String tankId,
    required TankDraft draft,
  });

  Future<Tank> archiveTank({
    required String facilityId,
    required String tankId,
  });
}
