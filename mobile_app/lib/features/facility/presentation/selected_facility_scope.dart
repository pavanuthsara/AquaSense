import 'package:flutter/widgets.dart';

import '../domain/facility.dart';

class SelectedFacilityScope extends InheritedWidget {
  const SelectedFacilityScope({
    required this.facility,
    required super.child,
    super.key,
  });

  final Facility facility;

  static Facility of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<SelectedFacilityScope>();
    assert(scope != null, 'SelectedFacilityScope was not found.');
    return scope!.facility;
  }

  @override
  bool updateShouldNotify(SelectedFacilityScope oldWidget) {
    return facility.id != oldWidget.facility.id ||
        facility.name != oldWidget.facility.name ||
        facility.timeZone != oldWidget.facility.timeZone ||
        facility.role != oldWidget.facility.role;
  }
}
