import 'package:flutter/material.dart';

import '../../auth/presentation/authentication_controller.dart';
import '../../auth/presentation/authentication_scope.dart';
import '../domain/facility_team.dart';

class PendingInvitationsScreen extends StatelessWidget {
  const PendingInvitationsScreen({
    required this.invitations,
    required this.isAccepting,
    required this.onAccept,
    this.onCreateFacility,
    super.key,
  });

  final List<FacilityInvitation> invitations;
  final bool isAccepting;
  final Future<bool> Function(FacilityInvitation) onAccept;
  final VoidCallback? onCreateFacility;

  @override
  Widget build(BuildContext context) {
    final authentication = AuthenticationScope.of(context);
    final isSigningOut =
        authentication.status == AuthenticationStatus.signingOut;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aquarium invitations'),
        actions: [
          if (onCreateFacility != null)
            IconButton(
              tooltip: 'Sign out',
              onPressed: isSigningOut ? null : authentication.signOut,
              icon: const Icon(Icons.logout_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'You have been invited',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Invitations only appear for your verified Google email.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            ...invitations.map(
              (invitation) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        invitation.facilityName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(invitation.email),
                      const SizedBox(height: 4),
                      Text(
                        'Expires ${_date(invitation.expiresAt.toLocal())}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        key: Key('accept-invitation-${invitation.id}'),
                        onPressed: isAccepting
                            ? null
                            : () => onAccept(invitation),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Accept invitation'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (onCreateFacility != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: isAccepting ? null : onCreateFacility,
                icon: const Icon(Icons.add_business_rounded),
                label: const Text('Create my own aquarium'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _date(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }
}
