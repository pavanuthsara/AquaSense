import 'package:shared_preferences/shared_preferences.dart';

import '../domain/onboarding_repository.dart';

class SharedPreferencesOnboardingRepository implements OnboardingRepository {
  SharedPreferencesOnboardingRepository({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _completedKey = 'onboarding.completed';

  final SharedPreferencesAsync _preferences;

  @override
  Future<bool> hasCompletedOnboarding() async {
    return await _preferences.getBool(_completedKey) ?? false;
  }

  @override
  Future<void> completeOnboarding() {
    return _preferences.setBool(_completedKey, true);
  }
}
