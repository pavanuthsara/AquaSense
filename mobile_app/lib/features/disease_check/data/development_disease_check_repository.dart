import '../domain/disease_check_record.dart';
import '../domain/disease_check_repository.dart';
import '../domain/disease_prediction.dart';

/// Keeps disease checks in memory for development builds without a backend.
///
/// Like the backend, a repeated request key returns the first saved check.
class DevelopmentDiseaseCheckRepository implements DiseaseCheckRepository {
  DevelopmentDiseaseCheckRepository({this.checkedByName = 'Local test owner'});

  final String checkedByName;
  final List<DiseaseCheckRecord> _records = [];
  final Map<String, DiseaseCheckRecord> _byRequestKey = {};
  var _nextId = 1;

  @override
  Future<DiseaseCheckRecord> saveCheck({
    required String facilityId,
    required DiseasePrediction prediction,
    required String idempotencyKey,
    String? tankLabel,
    String? note,
  }) async {
    final existing = _byRequestKey[idempotencyKey];
    if (existing != null) {
      return existing;
    }
    final record = DiseaseCheckRecord(
      id: 'local-disease-check-${_nextId++}',
      facilityId: facilityId,
      predictedLabel: prediction.topLabel,
      confidence: prediction.confidence,
      uncertain: prediction.isUncertain,
      modelVersion: prediction.modelVersion,
      tankLabel: _clean(tankLabel),
      note: _clean(note),
      checkedByName: checkedByName,
      checkedAt: prediction.checkedAt.toUtc(),
    );
    _records.add(record);
    _byRequestKey[idempotencyKey] = record;
    return record;
  }

  @override
  Future<List<DiseaseCheckRecord>> listChecks({
    required String facilityId,
    int limit = 20,
  }) async {
    final matching =
        _records.where((record) => record.facilityId == facilityId).toList()
          ..sort((a, b) => b.checkedAt.compareTo(a.checkedAt));
    return matching.take(limit).toList(growable: false);
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
