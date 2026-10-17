import 'package:flutter/widgets.dart';

import '../domain/facility_selection_store.dart';

class FacilitySelectionStoreScope extends InheritedWidget {
  const FacilitySelectionStoreScope({
    required this.store,
    required super.child,
    super.key,
  });

  final FacilitySelectionStore store;

  static FacilitySelectionStore of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<FacilitySelectionStoreScope>();
    assert(scope != null, 'FacilitySelectionStoreScope was not found.');
    return scope!.store;
  }

  @override
  bool updateShouldNotify(FacilitySelectionStoreScope oldWidget) {
    return store != oldWidget.store;
  }
}
