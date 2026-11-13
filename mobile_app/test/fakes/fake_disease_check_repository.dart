import 'package:mobile_app/features/disease_check/data/development_disease_check_repository.dart';
import 'package:mobile_app/features/disease_check/domain/disease_check_record.dart';
import 'package:mobile_app/features/disease_check/domain/disease_check_repository.dart';
import 'package:mobile_app/features/disease_check/domain/disease_prediction.dart';

/// In-memory repository that records request keys and can fail on demand.
class FakeDiseaseCheckRepository implements DiseaseCheckRepository {
  FakeDiseaseCheckRepository({this.saveFailures = 0, this.listError});

  final _inner = DevelopmentDiseaseCheckRepository(checkedByName: 'Test Owner');
  int saveFailures;
  Object? listError;
  final List<String> requestKeys = [];
  final List<String?> tankLabels = [];

  @override
  Future<DiseaseCheckRecord> saveCheck({
    required String facilityId,
    required DiseasePrediction prediction,
    required String idempotencyKey,
    String? tankLabel,
    String? note,
  }) async {
    requestKeys.add(idempotencyKey);
    tankLabels.add(tankLabel);
    if (saveFailures > 0) {
      saveFailures -= 1;
      throw const DiseaseCheckException('Temporary save failure.');
    }
    return _inner.saveCheck(
      facilityId: facilityId,
      prediction: prediction,
      idempotencyKey: idempotencyKey,
      tankLabel: tankLabel,
      note: note,
    );
  }

  @override
  Future<List<DiseaseCheckRecord>> listChecks({
    required String facilityId,
    int limit = 20,
  }) async {
    if (listError != null) {
      throw listError!;
    }
    return _inner.listChecks(facilityId: facilityId, limit: limit);
  }
}
