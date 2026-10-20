import 'package:flutter/material.dart';

import '../features/auth/domain/authentication_repository.dart';
import '../features/auth/presentation/authentication_controller.dart';
import '../features/auth/presentation/authentication_scope.dart';
import '../features/disease_check/data/development_disease_check_repository.dart';
import '../features/disease_check/data/image_picker_photo_source.dart';
import '../features/disease_check/data/tflite_disease_classifier.dart';
import '../features/disease_check/domain/disease_check_repository.dart';
import '../features/disease_check/domain/disease_classifier.dart';
import '../features/disease_check/domain/fish_photo_source.dart';
import '../features/disease_check/presentation/disease_check_scope.dart';
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
    this.diseaseClassifier,
    this.diseaseCheckRepository,
    this.fishPhotoSource,
    super.key,
  });

  final AppEnvironment environment;
  final OnboardingRepository onboardingRepository;
  final AuthenticationRepository authenticationRepository;
  final FacilityRepository facilityRepository;
  final FacilitySelectionStore facilitySelectionStore;

  /// Optional so existing tests keep working; defaults are created below.
  final DiseaseClassifier? diseaseClassifier;
  final DiseaseCheckRepository? diseaseCheckRepository;
  final FishPhotoSource? fishPhotoSource;

  @override
  State<AquaSenseApp> createState() => _AquaSenseAppState();
}

class _AquaSenseAppState extends State<AquaSenseApp> {
  late final AuthenticationController _authenticationController;
  late final DiseaseClassifier _diseaseClassifier;
  late final DiseaseCheckRepository _diseaseCheckRepository;
  late final FishPhotoSource _fishPhotoSource;

  @override
  void initState() {
    super.initState();
    // The model itself is only loaded the first time a fish is checked.
    _diseaseClassifier = widget.diseaseClassifier ?? TfliteDiseaseClassifier();
    _diseaseCheckRepository =
        widget.diseaseCheckRepository ?? DevelopmentDiseaseCheckRepository();
    _fishPhotoSource = widget.fishPhotoSource ?? ImagePickerPhotoSource();
    _authenticationController = AuthenticationController(
      repository: widget.authenticationRepository,
    );
    _authenticationController.initialize();
  }

  @override
  void dispose() {
    _authenticationController.dispose();
    if (widget.diseaseClassifier == null) {
      _diseaseClassifier.dispose();
    }
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
            child: DiseaseCheckScope(
              classifier: _diseaseClassifier,
              repository: _diseaseCheckRepository,
              photoSource: _fishPhotoSource,
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
