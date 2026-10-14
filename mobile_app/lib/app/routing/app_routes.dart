abstract final class AppRoutes {
  static const onboarding = '/onboarding';
  static const signIn = '/sign-in';
  static const home = '/home';
}

class OnboardingRouteArguments {
  const OnboardingRouteArguments({this.isReplay = false});

  final bool isReplay;
}
