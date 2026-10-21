import 'package:flutter/widgets.dart';

import '../domain/export_repository.dart';

class ExportRepositoryScope extends InheritedWidget {
  const ExportRepositoryScope({
    required this.repository,
    required super.child,
    super.key,
  });

  final ExportRepository repository;

  static ExportRepository? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ExportRepositoryScope>()
        ?.repository;
  }

  static ExportRepository of(BuildContext context) {
    final repository = maybeOf(context);
    assert(repository != null, 'ExportRepositoryScope was not found.');
    return repository!;
  }

  @override
  bool updateShouldNotify(ExportRepositoryScope oldWidget) {
    return repository != oldWidget.repository;
  }
}
