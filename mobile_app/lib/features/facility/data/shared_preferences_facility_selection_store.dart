import 'package:shared_preferences/shared_preferences.dart';

import '../domain/facility_selection_store.dart';

class SharedPreferencesFacilitySelectionStore
    implements FacilitySelectionStore {
  SharedPreferencesFacilitySelectionStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _keyPrefix = 'facility.selected.';

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> readSelectedFacilityId(String userId) {
    return _preferences.getString(_key(userId));
  }

  @override
  Future<void> saveSelectedFacilityId({
    required String userId,
    required String facilityId,
  }) {
    return _preferences.setString(_key(userId), facilityId);
  }

  @override
  Future<void> clearSelectedFacilityId(String userId) {
    return _preferences.remove(_key(userId));
  }

  String _key(String userId) => '$_keyPrefix$userId';
}
