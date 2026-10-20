/// A disease check saved in an aquarium's history on the backend.
class DiseaseCheckRecord {
  const DiseaseCheckRecord({
    required this.id,
    required this.facilityId,
    required this.predictedLabel,
    required this.confidence,
    required this.uncertain,
    required this.modelVersion,
    required this.checkedByName,
    required this.checkedAt,
    this.tankLabel,
    this.note,
  });

  final String id;
  final String facilityId;
  final String predictedLabel;
  final double confidence;
  final bool uncertain;
  final String modelVersion;
  final String? tankLabel;
  final String? note;
  final String checkedByName;
  final DateTime checkedAt;
}
