import 'package:flutter/material.dart';

import '../../facility/presentation/facility_gate.dart';
import 'authentication_controller.dart';
import 'authentication_scope.dart';
import 'sign_in_screen.dart';

class AuthenticationGate extends StatelessWidget {
  const AuthenticationGate({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AuthenticationScope.of(context);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return switch (controller.status) {
          AuthenticationStatus.checkingSession =>
            const AuthenticationLoadingScreen(),
          AuthenticationStatus.signedOut ||
          AuthenticationStatus.signingIn => const SignInScreen(),
          AuthenticationStatus.signedIn ||
          AuthenticationStatus.signingOut => const FacilityGate(),
        };
      },
    );
  }
}

class AuthenticationLoadingScreen extends StatelessWidget {
  const AuthenticationLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.water_rounded,
                size: 52,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Restoring your session',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 22),
              const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
