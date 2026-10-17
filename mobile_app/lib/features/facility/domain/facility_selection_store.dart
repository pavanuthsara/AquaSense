abstract interface class FacilitySelectionStore {
  Future<String?> readSelectedFacilityId(String userId);

  Future<void> saveSelectedFacilityId({
    required String userId,
    required String facilityId,
  });

  Future<void> clearSelectedFacilityId(String userId);
}
