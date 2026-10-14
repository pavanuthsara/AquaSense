import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/widgets/app_error_view.dart';
import '../features/auth/data/development_authentication_repository.dart';
import '../features/auth/data/google_backend_authentication_repository.dart';
import '../features/auth/data/secure_auth_session_storage.dart';
import '../features/auth/domain/authentication_repository.dart';
import '../features/onboarding/data/shared_preferences_onboarding_repository.dart';
import '../features/onboarding/domain/onboarding_repository.dart';
import 'app.dart';
import 'config/app_environment.dart';

Future<void> bootstrap({
  AppEnvironment? environment,
  OnboardingRepository? onboardingRepository,
  AuthenticationRepository? authenticationRepository,
}) async {
  WidgetsFlutterBinding.ensureInitialized();

  final resolvedEnvironment = environment ?? AppEnvironment.fromDartDefines();
  final resolvedOnboardingRepository =
      onboardingRepository ?? SharedPreferencesOnboardingRepository();
  final sessionStorage = SecureAuthSessionStorage();
  final resolvedAuthenticationRepository =
      authenticationRepository ??
      (resolvedEnvironment.usesRealAuthentication
          ? GoogleBackendAuthenticationRepository(
              apiBaseUrl: resolvedEnvironment.apiBaseUrl,
              googleServerClientId: resolvedEnvironment.googleServerClientId,
              sessionStorage: sessionStorage,
            )
          : DevelopmentAuthenticationRepository(
              sessionStorage: sessionStorage,
            ));

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'AquaSense application',
      ),
    );
    return true;
  };

  ErrorWidget.builder = (details) =>
      const AppErrorView(message: 'This screen could not be displayed.');

  runZonedGuarded(
    () => runApp(
      AquaSenseApp(
        environment: resolvedEnvironment,
        onboardingRepository: resolvedOnboardingRepository,
        authenticationRepository: resolvedAuthenticationRepository,
      ),
    ),
    (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'AquaSense application zone',
        ),
      );
    },
  );
}
