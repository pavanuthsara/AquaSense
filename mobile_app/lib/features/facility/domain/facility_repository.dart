import 'facility.dart';
import 'facility_team.dart';

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
}
