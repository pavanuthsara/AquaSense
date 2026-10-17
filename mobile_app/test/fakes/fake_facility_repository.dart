import 'package:mobile_app/features/facility/domain/facility.dart';
import 'package:mobile_app/features/facility/domain/facility_repository.dart';

class FakeFacilityRepository implements FacilityRepository {
  FakeFacilityRepository({
    List<Facility>? facilities,
    this.listError,
    this.createFailures = 0,
  }) : facilities = facilities ?? [];

  final List<Facility> facilities;
  Object? listError;
  int createFailures;
  int listCalls = 0;
  int createCalls = 0;
  final List<String> creationKeys = [];

  static Facility facility({
    String id = 'facility-1',
    String name = 'Test Aquarium',
    String timeZone = 'Asia/Colombo',
  }) {
    return Facility(
      id: id,
      name: name,
      timeZone: timeZone,
      role: FacilityRole.owner,
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
    return facilities.firstWhere((facility) => facility.id == facilityId);
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
}
