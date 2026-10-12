import 'package:flutter/material.dart';

import '../../../core/widgets/development_placeholder.dart';

class HomePlaceholderScreen extends StatelessWidget {
  const HomePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AquaSense')),
      body: const DevelopmentPlaceholder(
        icon: Icons.dashboard_outlined,
        eyebrow: 'Dashboard',
        title: 'Your aquarium overview',
        description:
            'Facility health, tanks, schedules, feeding activity, and alerts '
            'will be added incrementally in later development tasks.',
      ),
    );
  }
}
