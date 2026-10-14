abstract interface class OnboardingRepository {
  Future<bool> hasCompletedOnboarding();

  Future<void> completeOnboarding();
}
