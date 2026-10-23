import 'package:flutter/material.dart';

import '../features/auth/domain/authentication_repository.dart';
import '../features/auth/presentation/authentication_controller.dart';
import '../features/auth/presentation/authentication_scope.dart';
import '../features/export/data/development_export_repository.dart';
import '../features/export/domain/export_repository.dart';
import '../features/export/presentation/export_repository_scope.dart';
import '../features/facility/domain/facility_repository.dart';
import '../features/facility/domain/facility_selection_store.dart';
import '../features/facility/presentation/facility_repository_scope.dart';
import '../features/facility/presentation/facility_selection_store_scope.dart';
import '../features/onboarding/domain/onboarding_repository.dart';
import '../features/onboarding/presentation/startup_gate.dart';
import 'config/app_environment.dart';
import 'routing/app_router.dart';
import 'theme/aquasense_theme.dart';

class AquaSenseApp extends StatefulWidget {
  const AquaSenseApp({
    required this.environment,
    required this.onboardingRepository,
    required this.authenticationRepository,
    required this.facilityRepository,
    required this.facilitySelectionStore,
    this.exportRepository,
    super.key,
  });

  final AppEnvironment environment;
  final OnboardingRepository onboardingRepository;
  final AuthenticationRepository authenticationRepository;
  final FacilityRepository facilityRepository;
  final FacilitySelectionStore facilitySelectionStore;

  /// Export planning backend; defaults to the offline sample repository.
  final ExportRepository? exportRepository;

  @override
  State<AquaSenseApp> createState() => _AquaSenseAppState();
}

class _AquaSenseAppState extends State<AquaSenseApp> {
  late final AuthenticationController _authenticationController;
  late final ExportRepository _exportRepository =
      widget.exportRepository ?? DevelopmentExportRepository();

  @override
  void initState() {
    super.initState();
    _authenticationController = AuthenticationController(
      repository: widget.authenticationRepository,
    );
    _authenticationController.initialize();
  }

  @override
  void dispose() {
    _authenticationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppEnvironmentScope(
      environment: widget.environment,
      child: AuthenticationScope(
        controller: _authenticationController,
        child: FacilitySelectionStoreScope(
          store: widget.facilitySelectionStore,
          child: FacilityRepositoryScope(
            repository: widget.facilityRepository,
            child: ExportRepositoryScope(
              repository: _exportRepository,
              child: MaterialApp(
                title: 'AquaSense',
                debugShowCheckedModeBanner: !widget.environment.isProduction,
                theme: AquaSenseTheme.light,
                home: StartupGate(
                  onboardingRepository: widget.onboardingRepository,
                ),
                onGenerateRoute: AppRouter(
                  onboardingRepository: widget.onboardingRepository,
                ).onGenerateRoute,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
