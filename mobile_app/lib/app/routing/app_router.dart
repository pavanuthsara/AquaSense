import 'package:flutter/material.dart';

import '../../core/screens/not_found_screen.dart';
import '../../features/auth/presentation/authentication_gate.dart';
import '../../features/onboarding/domain/onboarding_repository.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import 'app_routes.dart';

class AppRouter {
  const AppRouter({required this.onboardingRepository});

  final OnboardingRepository onboardingRepository;

  Route<void> onGenerateRoute(RouteSettings settings) {
    final onboardingArguments = settings.arguments is OnboardingRouteArguments
        ? settings.arguments! as OnboardingRouteArguments
        : const OnboardingRouteArguments();

    final builder = switch (settings.name) {
      AppRoutes.onboarding => (_) => OnboardingScreen(
        onboardingRepository: onboardingRepository,
        isReplay: onboardingArguments.isReplay,
      ),
      AppRoutes.signIn => (_) => const AuthenticationGate(),
      AppRoutes.home => (_) => const AuthenticationGate(),
      _ => (_) => NotFoundScreen(routeName: settings.name),
    };

    return MaterialPageRoute<void>(settings: settings, builder: builder);
  }
}
