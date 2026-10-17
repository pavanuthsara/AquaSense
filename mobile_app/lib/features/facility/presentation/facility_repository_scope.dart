import 'package:flutter/widgets.dart';

import '../domain/facility_repository.dart';

class FacilityRepositoryScope extends InheritedWidget {
  const FacilityRepositoryScope({
    required this.repository,
    required super.child,
    super.key,
  });

  final FacilityRepository repository;

  static FacilityRepository of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<FacilityRepositoryScope>();
    assert(scope != null, 'FacilityRepositoryScope was not found.');
    return scope!.repository;
  }

  @override
  bool updateShouldNotify(FacilityRepositoryScope oldWidget) {
    return repository != oldWidget.repository;
  }
}
