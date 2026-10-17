import 'package:flutter/material.dart';

import '../../../app/routing/app_routes.dart';
import '../../auth/presentation/authentication_controller.dart';
import '../../auth/presentation/authentication_scope.dart';
import '../domain/facility.dart';

class FacilityHomeScreen extends StatelessWidget {
  const FacilityHomeScreen({required this.facility, super.key});

  final Facility facility;

  @override
  Widget build(BuildContext context) {
    final authentication = AuthenticationScope.of(context);
    final user = authentication.user;
    final isSigningOut =
        authentication.status == AuthenticationStatus.signingOut;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(facility.name),
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
            onPressed: isSigningOut ? null : authentication.signOut,
            icon: isSigningOut
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              user == null
                  ? 'Aquarium overview'
                  : 'Welcome, ${user.displayName}',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              facility.timeZone.replaceAll('_', ' '),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _SummaryCard(
                  icon: Icons.water_rounded,
                  label: 'Tanks',
                  value: '0',
                ),
                _SummaryCard(
                  icon: Icons.groups_rounded,
                  label: 'Workers',
                  value: '1 owner',
                ),
                _SummaryCard(
                  icon: Icons.schedule_rounded,
                  label: 'Schedules',
                  value: '0',
                ),
              ],
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.grid_view_rounded,
                    size: 46,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Your aquarium is ready',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tank groups and tanks will appear here after they are '
                    'added in the next development stages.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 150,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(height: 14),
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(label, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
