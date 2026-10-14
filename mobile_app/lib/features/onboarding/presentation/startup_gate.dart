import 'package:flutter/material.dart';

import '../../auth/presentation/authentication_gate.dart';
import '../domain/onboarding_repository.dart';
import 'onboarding_screen.dart';

class StartupGate extends StatefulWidget {
  const StartupGate({required this.onboardingRepository, super.key});

  final OnboardingRepository onboardingRepository;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  late final Future<bool> _hasCompletedOnboarding;

  @override
  void initState() {
    super.initState();
    _hasCompletedOnboarding = widget.onboardingRepository
        .hasCompletedOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasCompletedOnboarding,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _StartupLoadingScreen();
        }

        if (snapshot.data == true) {
          return const AuthenticationGate();
        }

        return OnboardingScreen(
          onboardingRepository: widget.onboardingRepository,
        );
      },
    );
  }
}

class _StartupLoadingScreen extends StatelessWidget {
  const _StartupLoadingScreen();

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
                'AquaSense',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
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
