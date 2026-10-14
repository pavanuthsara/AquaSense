import 'package:flutter/material.dart';

import '../features/onboarding/domain/onboarding_repository.dart';
import '../features/onboarding/presentation/startup_gate.dart';
import 'config/app_environment.dart';
import 'routing/app_router.dart';
import 'theme/aquasense_theme.dart';

class AquaSenseApp extends StatelessWidget {
  const AquaSenseApp({
    required this.environment,
    required this.onboardingRepository,
    super.key,
  });

  final AppEnvironment environment;
  final OnboardingRepository onboardingRepository;

  @override
  Widget build(BuildContext context) {
    return AppEnvironmentScope(
      environment: environment,
      child: MaterialApp(
        title: 'AquaSense',
        debugShowCheckedModeBanner: !environment.isProduction,
        theme: AquaSenseTheme.light,
        home: StartupGate(onboardingRepository: onboardingRepository),
        onGenerateRoute: AppRouter(
          onboardingRepository: onboardingRepository,
        ).onGenerateRoute,
      ),
    );
  }
}
