import 'dart:convert';

import '../domain/export_advisory.dart';
import '../domain/export_repository.dart';
import 'sample_advisory.dart';

/// Offline repository used when the app runs without the AquaSense backend.
/// Every plan returns the same bundled sample advisory.
class DevelopmentExportRepository implements ExportRepository {
  DevelopmentExportRepository({this.delay = const Duration(milliseconds: 600)});

  final Duration delay;
  final _saved = <String, List<_SavedPlan>>{};
  var _nextId = 1;

  static TransitAdvisory sampleAdvisory() => TransitAdvisory.fromJson(
    jsonDecode(sampleAdvisoryJson) as Map<String, dynamic>,
  );

  @override
  Future<ExportAdvisoryDetail> createAdvisory({
    required String facilityId,
    required ExportShipmentRequest request,
  }) async {
    await Future<void>.delayed(delay);
    final advisory = sampleAdvisory();
    final plan = _SavedPlan(
      ExportAdvisoryDetail(
        id: 'dev-plan-${_nextId++}',
        label: request.label,
        createdAt: DateTime.now().toUtc(),
        advisory: advisory,
      ),
      request,
    );
    _saved.putIfAbsent(facilityId, () => []).insert(0, plan);
    return plan.detail;
  }

  @override
  Future<List<ExportAdvisorySummary>> listAdvisories(String facilityId) async {
    await Future<void>.delayed(delay ~/ 3);
    return (_saved[facilityId] ?? const <_SavedPlan>[])
        .map((plan) {
          final advisory = plan.detail.advisory;
          return ExportAdvisorySummary(
            id: plan.detail.id,
            label: plan.detail.label,
            species: plan.request.species,
            durationHours: plan.request.durationH,
            feasible: advisory.feasible,
            mode: plan.request.mode,
            meetsTarget: advisory.verdict?.meetsTarget ?? true,
            fishPerBag: advisory.recommendation.fishPerBag,
            bagsNeeded: advisory.recommendation.bagsNeeded,
            survivalPct: advisory.mortality?.survivalAfterUnpackingPct,
            worstSurvivalPct:
                advisory.mortality?.worstSurvivalAfterUnpackingPct,
            createdAt: plan.detail.createdAt,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<ExportAdvisoryDetail> getAdvisory({
    required String facilityId,
    required String advisoryId,
  }) async {
    final plans = _saved[facilityId] ?? const <_SavedPlan>[];
    for (final plan in plans) {
      if (plan.detail.id == advisoryId) return plan.detail;
    }
    throw const ExportException(
      'The shipment plan was not found',
      code: 'export_advisory_not_found',
    );
  }
}

class _SavedPlan {
  const _SavedPlan(this.detail, this.request);

  final ExportAdvisoryDetail detail;
  final ExportShipmentRequest request;
}
