import 'facility.dart';
import 'appetite_check.dart';
import 'facility_team.dart';
import 'feeder_calibration.dart';
import 'feeding_monitoring.dart';
import 'tank_group.dart';
import 'tank.dart';

abstract interface class FacilityRepository {
  Future<AppetiteCheck> requestAppetiteCheck({
    required String facilityId,
    required String tankId,
  });

  Future<AppetiteCheck> getAppetiteCheck({
    required String facilityId,
    required String tankId,
    required String checkId,
  });

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

  Future<TankGroup> updateTankGroupFeedingSchedule({
    required String facilityId,
    required String groupId,
    required List<String> times,
    required bool automationEnabled,
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

  Future<TankHardwareHealth> getTankDeviceHealth({
    required String facilityId,
    required String tankId,
  });

  Future<ProvisionedTankDevice> provisionTankDevice({
    required String facilityId,
    required String tankId,
    required TankDeviceType type,
  });

  Future<TankDetail> updateTankFeedingSchedule({
    required String facilityId,
    required String tankId,
    required TankScheduleMode mode,
    required List<String> times,
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

  Future<FeederCalibration?> getFeederCalibration(String facilityId);

  Future<FeederCalibration> createFeederCalibration({
    required String facilityId,
    required FeederCalibrationDraft draft,
  });

  Future<PortionPreview> getPortionPreview({
    required String facilityId,
    required String tankId,
    int? fishCount,
  });

  Future<FeedingDashboard> getFeedingDashboard(String facilityId);

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
  });
}
