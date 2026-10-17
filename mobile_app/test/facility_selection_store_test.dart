import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/facility/data/shared_preferences_facility_selection_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = null;
  });

  test('stores facility selections independently for each user', () async {
    final store = SharedPreferencesFacilitySelectionStore();

    await store.saveSelectedFacilityId(
      userId: 'owner-one',
      facilityId: 'facility-one',
    );
    await store.saveSelectedFacilityId(
      userId: 'owner-two',
      facilityId: 'facility-two',
    );

    expect(await store.readSelectedFacilityId('owner-one'), 'facility-one');
    expect(await store.readSelectedFacilityId('owner-two'), 'facility-two');

    await store.clearSelectedFacilityId('owner-one');
    expect(await store.readSelectedFacilityId('owner-one'), isNull);
    expect(await store.readSelectedFacilityId('owner-two'), 'facility-two');
  });
}
