import 'facility.dart';

abstract interface class FacilityRepository {
  Future<List<Facility>> listFacilities();

  Future<Facility> getFacility(String facilityId);

  Future<List<String>> listTimeZones();

  Future<Facility> createFacility({
    required String name,
    required String timeZone,
    required String idempotencyKey,
  });
}
