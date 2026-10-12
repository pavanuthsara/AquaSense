import 'package:flutter/material.dart';

import 'config/app_environment.dart';
import 'routing/app_router.dart';
import 'routing/app_routes.dart';
import 'theme/aquasense_theme.dart';

class AquaSenseApp extends StatelessWidget {
  const AquaSenseApp({required this.environment, super.key});

  final AppEnvironment environment;

  @override
  Widget build(BuildContext context) {
    return AppEnvironmentScope(
      environment: environment,
      child: MaterialApp(
        title: 'AquaSense',
        debugShowCheckedModeBanner: !environment.isProduction,
        theme: AquaSenseTheme.light,
        initialRoute: AppRoutes.onboarding,
        onGenerateRoute: AppRouter.onGenerateRoute,
      ),
    );
  }
}
