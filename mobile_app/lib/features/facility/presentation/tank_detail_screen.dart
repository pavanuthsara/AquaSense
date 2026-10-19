import 'package:flutter/material.dart';

import '../domain/facility.dart';
import '../domain/facility_repository.dart';
import '../domain/tank.dart';
import 'tank_form_screen.dart';

class TankDetailScreen extends StatefulWidget {
  const TankDetailScreen({
    required this.facility,
    required this.tankId,
    required this.repository,
    super.key,
  });

  final Facility facility;
  final String tankId;
  final FacilityRepository repository;

  @override
  State<TankDetailScreen> createState() => _TankDetailScreenState();
}

class _TankDetailScreenState extends State<TankDetailScreen> {
  TankDetail? _detail;
  Object? _error;
  bool _loading = true;

  bool get _isOwner => widget.facility.role == FacilityRole.owner;

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
      final detail = await widget.repository.getTankDetail(
        facilityId: widget.facility.id,
        tankId: widget.tankId,
      );
      if (mounted) {
        setState(() {
          _detail = detail;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error;
        });
      }
    }
  }

  Future<void> _edit() async {
    final detail = _detail;
    if (detail == null) return;
    try {
      final groups = await widget.repository.listTankGroups(widget.facility.id);
      if (!mounted) return;
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => TankFormScreen(
            facility: widget.facility,
            repository: widget.repository,
            groups: groups,
            tank: detail.tank,
          ),
        ),
      );
      if (changed == true) await _load();
    } on FacilityException catch (error) {
      _message(error.message);
    }
  }

  Future<void> _archive() async {
    final tank = _detail?.tank;
    if (tank == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive tank?'),
        content: Text(
          '${tank.name} will be removed from active operations and automatic feeding.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-archive-tank'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.archiveTank(
        facilityId: widget.facility.id,
        tankId: tank.id,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on FacilityException catch (error) {
      _message(error.message);
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      appBar: AppBar(
        title: Text(detail?.tank.name ?? 'Tank details'),
        actions: [
          if (_isOwner && detail?.tank.status != TankStatus.archived) ...[
            IconButton(
              key: const Key('edit-tank-button'),
              tooltip: 'Edit tank',
              onPressed: _edit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              key: const Key('archive-tank-button'),
              tooltip: 'Archive tank',
              onPressed: _archive,
              icon: const Icon(Icons.archive_outlined),
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      final error = _error;
      return _DetailError(
        message: error is FacilityException
            ? error.message
            : 'Tank details could not be loaded.',
        onRetry: _load,
      );
    }
    final detail = _detail!;
    final tank = detail.tank;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusChip(label: _tankStatus(tank.status)),
              _StatusChip(label: _deviceStatus(detail.deviceStatus)),
              _StatusChip(label: _observationStatus(detail.observationState)),
            ],
          ),
          const SizedBox(height: 18),
          _Section(
            title: 'Tank information',
            children: [
              _InfoRow(label: 'Code', value: tank.code),
              _InfoRow(label: 'Group', value: tank.groupName ?? 'Unassigned'),
              _InfoRow(
                label: 'Automation',
                value: tank.automationEnabled ? 'Enabled' : 'Paused',
              ),
              _InfoRow(
                label: 'Tags',
                value: tank.tags.isEmpty ? 'None' : tank.tags.join(', '),
              ),
              if (tank.notes != null && tank.notes!.isNotEmpty)
                _InfoRow(label: 'Notes', value: tank.notes!),
            ],
          ),
          const SizedBox(height: 14),
          _Section(
            title: 'Guppy count',
            children: [
              _InfoRow(label: 'Expected', value: '${tank.expectedGuppyCount}'),
              _InfoRow(
                label: 'Detected',
                value:
                    tank.detectedGuppyCount?.toString() ?? 'No observation yet',
              ),
              _InfoRow(
                label: 'Confidence',
                value: tank.detectionConfidence == null
                    ? 'Not available'
                    : '${(tank.detectionConfidence! * 100).toStringAsFixed(0)}%',
              ),
              _InfoRow(
                label: 'Observed',
                value: tank.countObservedAt == null
                    ? 'Not yet observed'
                    : _date(tank.countObservedAt!),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Section(
            title: 'Feeding and hardware',
            children: [
              _InfoRow(
                label: 'Device',
                value: _deviceDescription(detail.deviceStatus),
              ),
              _InfoRow(
                label: 'Schedule',
                value: detail.feedingTimes.isEmpty
                    ? 'No feeding schedule'
                    : detail.feedingTimes.join(', '),
              ),
              _InfoRow(
                label: 'Last feeding',
                value: detail.lastFeedingAt == null
                    ? 'No feeding history'
                    : _date(detail.lastFeedingAt!),
              ),
              _InfoRow(
                label: 'Next session',
                value: detail.nextFeedingAt == null
                    ? 'Not scheduled'
                    : _date(detail.nextFeedingAt!),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Section(
            title: 'Recent activity',
            children: detail.recentActivity.isEmpty
                ? const [_InfoRow(label: 'Activity', value: 'No activity yet')]
                : detail.recentActivity
                      .map(
                        (activity) => _InfoRow(
                          label: _date(activity.occurredAt),
                          value: activity.title,
                        ),
                      )
                      .toList(),
          ),
        ],
      ),
    );
  }

  String _tankStatus(TankStatus status) => switch (status) {
    TankStatus.active => 'Active',
    TankStatus.paused => 'Automation paused',
    TankStatus.archived => 'Archived',
  };

  String _observationStatus(TankObservationState state) => switch (state) {
    TankObservationState.noData => 'No count data',
    TankObservationState.current => 'Count current',
    TankObservationState.stale => 'Count stale',
  };

  String _deviceStatus(TankDeviceStatus status) => switch (status) {
    TankDeviceStatus.notConfigured => 'Hardware not connected',
    TankDeviceStatus.online => 'Hardware online',
    TankDeviceStatus.offline => 'Hardware offline',
    TankDeviceStatus.stale => 'Hardware stale',
    TankDeviceStatus.unhealthy => 'Hardware unhealthy',
  };

  String _deviceDescription(TankDeviceStatus status) => switch (status) {
    TankDeviceStatus.notConfigured => 'Not connected yet',
    TankDeviceStatus.online => 'Online',
    TankDeviceStatus.offline => 'Offline — feeding unavailable',
    TankDeviceStatus.stale => 'Heartbeat stale — check hardware',
    TankDeviceStatus.unhealthy => 'Unhealthy — feeding blocked',
  };

  String _date(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Chip(label: Text(label));
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}
