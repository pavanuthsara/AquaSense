class TankGroup {
  const TankGroup({
    required this.id,
    required this.facilityId,
    required this.name,
    required this.tankCount,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
    this.archivedAt,
  });

  final String id;
  final String facilityId;
  final String name;
  final int tankCount;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;

  TankGroup copyWith({
    String? name,
    int? tankCount,
    bool? archived,
    DateTime? updatedAt,
    DateTime? archivedAt,
  }) {
    return TankGroup(
      id: id,
      facilityId: facilityId,
      name: name ?? this.name,
      tankCount: tankCount ?? this.tankCount,
      archived: archived ?? this.archived,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      archivedAt: archivedAt ?? this.archivedAt,
    );
  }
}
