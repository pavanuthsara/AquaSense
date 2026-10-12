import 'package:flutter/material.dart';

import '../../../app/routing/app_routes.dart';
import '../../../core/widgets/development_placeholder.dart';

class SignInPlaceholderScreen extends StatelessWidget {
  const SignInPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: DevelopmentPlaceholder(
        icon: Icons.account_circle_outlined,
        eyebrow: 'Account',
        title: 'Sign in to your aquarium',
        description:
            'Google sign-in and secure session handling will be implemented '
            'in MOB-003.',
        action: OutlinedButton(
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.home),
          child: const Text('Preview home placeholder'),
        ),
      ),
    );
  }
}
