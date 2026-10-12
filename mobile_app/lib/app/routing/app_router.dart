import 'package:flutter/material.dart';

import '../../core/screens/not_found_screen.dart';
import '../../features/auth/presentation/sign_in_placeholder_screen.dart';
import '../../features/home/presentation/home_placeholder_screen.dart';
import '../../features/onboarding/presentation/onboarding_placeholder_screen.dart';
import 'app_routes.dart';

abstract final class AppRouter {
  static Route<void> onGenerateRoute(RouteSettings settings) {
    final builder = switch (settings.name) {
      AppRoutes.onboarding => (_) => const OnboardingPlaceholderScreen(),
      AppRoutes.signIn => (_) => const SignInPlaceholderScreen(),
      AppRoutes.home => (_) => const HomePlaceholderScreen(),
      _ => (_) => NotFoundScreen(routeName: settings.name),
    };

    return MaterialPageRoute<void>(settings: settings, builder: builder);
  }
}
