import 'package:flutter/widgets.dart';

enum AppEnvironmentName { development, test, production }

class AppEnvironment {
  const AppEnvironment({
    required this.name,
    required this.apiBaseUrl,
    this.googleServerClientId = '',
  });

  const AppEnvironment.test()
    : name = AppEnvironmentName.test,
      apiBaseUrl = 'http://localhost',
      googleServerClientId = '';

  final AppEnvironmentName name;
  final String apiBaseUrl;
  final String googleServerClientId;

  bool get isProduction => name == AppEnvironmentName.production;
  bool get usesRealAuthentication => googleServerClientId.isNotEmpty;

  factory AppEnvironment.fromDartDefines() {
    const environmentValue = String.fromEnvironment(
      'AQUASENSE_ENV',
      defaultValue: 'development',
    );
    const configuredApiBaseUrl = String.fromEnvironment(
      'AQUASENSE_API_BASE_URL',
    );
    const googleServerClientId = String.fromEnvironment(
      'AQUASENSE_GOOGLE_SERVER_CLIENT_ID',
    );

    final name = switch (environmentValue.toLowerCase()) {
      'production' => AppEnvironmentName.production,
      'test' => AppEnvironmentName.test,
      _ => AppEnvironmentName.development,
    };

    final apiBaseUrl = configuredApiBaseUrl.isNotEmpty
        ? configuredApiBaseUrl
        : switch (name) {
            AppEnvironmentName.development => 'http://10.0.2.2:8080',
            AppEnvironmentName.test => 'http://localhost',
            AppEnvironmentName.production => throw StateError(
              'AQUASENSE_API_BASE_URL is required in production.',
            ),
          };

    if (name == AppEnvironmentName.production && googleServerClientId.isEmpty) {
      throw StateError(
        'AQUASENSE_GOOGLE_SERVER_CLIENT_ID is required in production.',
      );
    }

    return AppEnvironment(
      name: name,
      apiBaseUrl: apiBaseUrl,
      googleServerClientId: googleServerClientId,
    );
  }
}

class AppEnvironmentScope extends InheritedWidget {
  const AppEnvironmentScope({
    required this.environment,
    required super.child,
    super.key,
  });

  final AppEnvironment environment;

  static AppEnvironment of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppEnvironmentScope>();
    assert(scope != null, 'AppEnvironmentScope was not found.');
    return scope!.environment;
  }

  @override
  bool updateShouldNotify(AppEnvironmentScope oldWidget) {
    return environment != oldWidget.environment;
  }
}
