import 'package:flutter/material.dart';

import '../../../app/routing/app_routes.dart';
import '../../auth/presentation/authentication_controller.dart';
import '../../auth/presentation/authentication_scope.dart';
import '../domain/facility.dart';
import '../domain/facility_repository.dart';
import '../domain/feeding_monitoring.dart';
import 'feeding_history_screen.dart';
import 'selected_facility_scope.dart';

class FacilityHomeScreen extends StatelessWidget {
  const FacilityHomeScreen({
    required this.facilities,
    required this.isSwitching,
    required this.onFacilitySelected,
    required this.onAddFacility,
    required this.onOpenTeam,
    required this.onOpenTankGroups,
    required this.onOpenTanks,
    required this.onOpenInvitations,
    required this.pendingInvitationCount,
    required this.repository,
    super.key,
  });

  static const _addFacilityChoice = '__add_facility__';

  final List<Facility> facilities;
  final bool isSwitching;
  final Future<bool> Function(Facility) onFacilitySelected;
  final VoidCallback onAddFacility;
  final VoidCallback onOpenTeam;
  final VoidCallback onOpenTankGroups;
  final VoidCallback onOpenTanks;
  final VoidCallback onOpenInvitations;
  final int pendingInvitationCount;
  final FacilityRepository repository;

  Future<void> _openFacilitySwitcher(
    BuildContext context,
    Facility selectedFacility,
  ) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _FacilitySwitcherSheet(
        facilities: facilities,
        selectedFacilityId: selectedFacility.id,
        addFacilityChoice: _addFacilityChoice,
      ),
    );
    if (!context.mounted || choice == null) {
      return;
    }
    if (choice == _addFacilityChoice) {
      onAddFacility();
      return;
    }

    final facility = facilities.firstWhere((item) => item.id == choice);
    await onFacilitySelected(facility);
  }

  @override
  Widget build(BuildContext context) {
    final facility = SelectedFacilityScope.of(context);
    final authentication = AuthenticationScope.of(context);
    final user = authentication.user;
    final isSigningOut =
        authentication.status == AuthenticationStatus.signingOut;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: TextButton.icon(
          key: const Key('facility-switcher-button'),
          onPressed: isSwitching
              ? null
              : () => _openFacilitySwitcher(context, facility),
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurface,
          ),
          iconAlignment: IconAlignment.end,
          icon: isSwitching
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.keyboard_arrow_down_rounded),
          label: Text(facility.name, overflow: TextOverflow.ellipsis),
        ),
        actions: [
          if (pendingInvitationCount > 0)
            IconButton(
              key: const Key('pending-invitations-button'),
              tooltip: 'Aquarium invitations',
              onPressed: onOpenInvitations,
              icon: Badge(
                label: Text('$pendingInvitationCount'),
                child: const Icon(Icons.mail_outline_rounded),
              ),
            ),
          IconButton(
            key: const Key('tank-groups-button'),
            tooltip: facility.role == FacilityRole.owner
                ? 'Manage tank groups'
                : 'View tank groups',
            onPressed: onOpenTankGroups,
            icon: const Icon(Icons.grid_view_rounded),
          ),
          IconButton(
            key: const Key('facility-team-button'),
            tooltip: facility.role == FacilityRole.owner
                ? 'Manage workers'
                : 'View aquarium team',
            onPressed: onOpenTeam,
            icon: const Icon(Icons.group_outlined),
          ),
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
            Align(
              alignment: Alignment.centerLeft,
              child: _SummaryCard(
                icon: Icons.groups_rounded,
                label: 'Team',
                value: facility.role == FacilityRole.owner
                    ? '1 owner'
                    : 'Worker',
              ),
            ),
            const SizedBox(height: 20),
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
                    facility.role == FacilityRole.owner
                        ? 'Create and organize tanks, expected guppy counts, '
                              'tags, and automation settings.'
                        : 'Browse the tanks, groups, guppy counts, and current '
                              'automation settings for this aquarium.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    key: const Key('tanks-button'),
                    onPressed: onOpenTanks,
                    icon: const Icon(Icons.water_rounded),
                    label: const Text('View tanks'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _FeedingDashboardPanel(facility: facility, repository: repository),
          ],
        ),
      ),
    );
  }
}

class _FeedingDashboardPanel extends StatefulWidget {
  const _FeedingDashboardPanel({
    required this.facility,
    required this.repository,
  });

  final Facility facility;
  final FacilityRepository repository;

  @override
  State<_FeedingDashboardPanel> createState() => _FeedingDashboardPanelState();
}

class _FeedingDashboardPanelState extends State<_FeedingDashboardPanel> {
  FeedingDashboard? _dashboard;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dashboard = await widget.repository.getFeedingDashboard(
        widget.facility.id,
      );
      if (mounted) {
        setState(() {
          _dashboard = dashboard;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _openHistory() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FeedingHistoryScreen(
          facility: widget.facility,
          repository: widget.repository,
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_error != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              const Icon(Icons.cloud_off_rounded),
              const SizedBox(width: 12),
              const Expanded(child: Text('Dashboard could not be loaded.')),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final dashboard = _dashboard!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Feeding operations',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'Refresh dashboard',
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _SummaryCard(
              icon: Icons.water_rounded,
              label: 'Active tanks',
              value: '${dashboard.totalTanks}',
            ),
            _SummaryCard(
              icon: Icons.schedule_rounded,
              label: 'Next 24 hours',
              value: '${dashboard.upcomingCount}',
            ),
            _SummaryCard(
              icon: Icons.check_circle_outline_rounded,
              label: 'Delivered · 24h',
              value: '${dashboard.delivered}',
            ),
            _SummaryCard(
              icon: Icons.pause_circle_outline_rounded,
              label: 'Skipped · 24h',
              value: '${dashboard.skipped}',
            ),
            _SummaryCard(
              icon: Icons.error_outline_rounded,
              label: 'Failed · 24h',
              value: '${dashboard.failed}',
            ),
            _SummaryCard(
              icon: Icons.memory_rounded,
              label: 'Hardware attention',
              value: '${dashboard.unhealthyDeviceCount}',
            ),
          ],
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Upcoming sessions',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (dashboard.upcoming.isEmpty)
                  const Text('No automatic sessions in the next 24 hours.')
                else
                  ...dashboard.upcoming
                      .take(3)
                      .map(
                        (item) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: const Icon(Icons.schedule_rounded),
                          title: Text(item.tankName),
                          subtitle: Text(
                            '${item.groupName ?? 'Unassigned'} · ${_dashboardDate(item.scheduledFor)}',
                          ),
                        ),
                      ),
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        dashboard.unhealthyDeviceCount == 0
                            ? 'Required hardware is reporting normally.'
                            : '${dashboard.unhealthyDeviceCount} device(s) need attention.',
                      ),
                    ),
                    FilledButton.icon(
                      key: const Key('feeding-history-button'),
                      onPressed: _openHistory,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 52),
                      ),
                      icon: const Icon(Icons.history_rounded),
                      label: const Text('History'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _dashboardDate(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

class _FacilitySwitcherSheet extends StatelessWidget {
  const _FacilitySwitcherSheet({
    required this.facilities,
    required this.selectedFacilityId,
    required this.addFacilityChoice,
  });

  final List<Facility> facilities;
  final String selectedFacilityId;
  final String addFacilityChoice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
              child: Text(
                'Switch aquarium',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: facilities.length,
                itemBuilder: (context, index) {
                  final facility = facilities[index];
                  final isSelected = facility.id == selectedFacilityId;
                  return ListTile(
                    key: Key('facility-choice-${facility.id}'),
                    leading: CircleAvatar(
                      child: Text(facility.name.characters.first.toUpperCase()),
                    ),
                    title: Text(facility.name),
                    subtitle: Text(
                      '${facility.timeZone.replaceAll('_', ' ')} · '
                      '${facility.role == FacilityRole.owner ? 'Owner' : 'Worker'}',
                    ),
                    trailing: isSelected
                        ? Icon(
                            Icons.check_circle_rounded,
                            color: theme.colorScheme.primary,
                          )
                        : null,
                    onTap: () => Navigator.of(context).pop(facility.id),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                key: const Key('add-aquarium-button'),
                onPressed: () => Navigator.of(context).pop(addFacilityChoice),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add aquarium'),
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
