import 'package:flutter/material.dart';

import '../../../app/routing/app_routes.dart';
import '../../../core/widgets/development_placeholder.dart';
import '../../auth/presentation/authentication_controller.dart';
import '../../auth/presentation/authentication_scope.dart';

class HomePlaceholderScreen extends StatelessWidget {
  const HomePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AuthenticationScope.of(context);
    final user = controller.user;
    final isSigningOut = controller.status == AuthenticationStatus.signingOut;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AquaSense'),
        actions: [
          IconButton(
            tooltip: 'View onboarding again',
            onPressed: () => Navigator.of(context).pushNamed(
              AppRoutes.onboarding,
              arguments: const OnboardingRouteArguments(isReplay: true),
            ),
            icon: const Icon(Icons.help_outline_rounded),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: isSigningOut
                ? null
                : () async {
                    await controller.signOut();
                    if (!context.mounted ||
                        controller.status != AuthenticationStatus.signedOut) {
                      return;
                    }
                    await Navigator.of(context).pushNamedAndRemoveUntil(
                      AppRoutes.signIn,
                      (route) => false,
                    );
                  },
            icon: isSigningOut
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: DevelopmentPlaceholder(
        icon: Icons.dashboard_outlined,
        eyebrow: user?.email ?? 'Dashboard',
        uppercaseEyebrow: user == null,
        title: user == null
            ? 'Your aquarium overview'
            : 'Welcome, ${user.displayName}',
        description:
            'Facility health, tanks, schedules, feeding activity, and alerts '
            'will be added incrementally in later development tasks.',
        action: OutlinedButton.icon(
          onPressed: isSigningOut ? null : controller.signOut,
          icon: const Icon(Icons.logout_rounded),
          label: Text(isSigningOut ? 'Signing out…' : 'Sign out'),
        ),
      ),
    );
  }
}
