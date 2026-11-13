import 'disease_check_record.dart';
import 'disease_prediction.dart';

/// Saves and loads disease-check results for an aquarium.
abstract interface class DiseaseCheckRepository {
  /// Saves one result. Retrying with the same [idempotencyKey] never creates
  /// a second copy.
  Future<DiseaseCheckRecord> saveCheck({
    required String facilityId,
    required DiseasePrediction prediction,
    required String idempotencyKey,
    String? tankLabel,
    String? note,
  });

  /// Newest results first.
  Future<List<DiseaseCheckRecord>> listChecks({
    required String facilityId,
    int limit = 20,
  });
}

class DiseaseCheckException implements Exception {
  const DiseaseCheckException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}
