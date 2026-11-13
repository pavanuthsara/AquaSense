import 'export_advisory.dart';

abstract interface class ExportRepository {
  /// Runs the transit simulator for a planned shipment and saves the result.
  Future<ExportAdvisoryDetail> createAdvisory({
    required String facilityId,
    required ExportShipmentRequest request,
  });

  Future<List<ExportAdvisorySummary>> listAdvisories(String facilityId);

  Future<ExportAdvisoryDetail> getAdvisory({
    required String facilityId,
    required String advisoryId,
  });
}
