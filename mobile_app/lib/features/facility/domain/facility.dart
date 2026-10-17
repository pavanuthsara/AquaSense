enum FacilityRole { owner, worker }

class Facility {
  const Facility({
    required this.id,
    required this.name,
    required this.timeZone,
    required this.role,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String timeZone;
  final FacilityRole role;
  final DateTime createdAt;
}

class FacilityException implements Exception {
  const FacilityException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}
