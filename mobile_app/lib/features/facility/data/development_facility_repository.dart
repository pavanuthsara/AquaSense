import '../domain/facility.dart';
import '../domain/facility_repository.dart';

class DevelopmentFacilityRepository implements FacilityRepository {
  final List<Facility> _facilities = [];
  final Map<String, Facility> _creationRequests = {};

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
}
