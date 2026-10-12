import 'package:flutter/material.dart';

import '../../../app/routing/app_routes.dart';
import '../../../core/widgets/development_placeholder.dart';

class OnboardingPlaceholderScreen extends StatelessWidget {
  const OnboardingPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DevelopmentPlaceholder(
        icon: Icons.water_rounded,
        eyebrow: 'AquaSense',
        title: 'Smarter feeding starts here',
        description:
            'The onboarding experience will introduce tank management, '
            'appetite-aware feeding, and safe human control.',
        action: FilledButton(
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.signIn),
          child: const Text('Continue to sign in'),
        ),
      ),
    );
  }
}
