import 'package:mobile_app/features/facility/domain/facility_selection_store.dart';

class FakeFacilitySelectionStore implements FacilitySelectionStore {
  FakeFacilitySelectionStore([Map<String, String>? selections])
    : selections = {...?selections};

  final Map<String, String> selections;
  final List<String> reads = [];
  final List<({String userId, String facilityId})> writes = [];
  final List<String> clears = [];

  @override
  Future<void> clearSelectedFacilityId(String userId) async {
    clears.add(userId);
    selections.remove(userId);
  }

  @override
  Future<String?> readSelectedFacilityId(String userId) async {
    reads.add(userId);
    return selections[userId];
  }

  @override
  Future<void> saveSelectedFacilityId({
    required String userId,
    required String facilityId,
  }) async {
    writes.add((userId: userId, facilityId: facilityId));
    selections[userId] = facilityId;
  }
}
