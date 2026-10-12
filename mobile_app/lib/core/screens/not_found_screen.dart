import 'package:flutter/material.dart';

import '../../app/routing/app_routes.dart';

class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({required this.routeName, super.key});

  final String? routeName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Page not found')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 56,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'We could not open ${routeName ?? 'this page'}.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(
                  AppRoutes.onboarding,
                  (route) => false,
                ),
                child: const Text('Return to start'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
