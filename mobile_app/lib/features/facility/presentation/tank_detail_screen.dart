import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/facility.dart';
import '../domain/facility_repository.dart';
import '../domain/tank.dart';
import 'tank_form_screen.dart';
import 'tank_feeding_schedule_screen.dart';
import 'portion_preview_screen.dart';
import 'feeding_history_screen.dart';

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

  Future<void> _editSchedule() async {
    final detail = _detail;
    if (detail == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TankFeedingScheduleScreen(
          facility: widget.facility,
          detail: detail,
          repository: widget.repository,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _openPortionPreview() async {
    final tank = _detail?.tank;
    if (tank == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PortionPreviewScreen(
          facility: widget.facility,
          tank: tank,
          repository: widget.repository,
        ),
      ),
    );
  }

  Future<void> _openFeedingHistory() async {
    final tank = _detail?.tank;
    if (tank == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FeedingHistoryScreen(
          facility: widget.facility,
          repository: widget.repository,
          tankId: tank.id,
          tankName: tank.name,
        ),
      ),
    );
  }

  Future<void> _provisionDevice(TankDeviceType type) async {
    try {
      final provisioned = await widget.repository.provisionTankDevice(
        facilityId: widget.facility.id,
        tankId: widget.tankId,
        type: type,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text('${_deviceType(type)} credential'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Copy this token now. For security, AquaSense will not show it again.',
              ),
              const SizedBox(height: 12),
              SelectableText(
                provisioned.heartbeatToken,
                key: const Key('device-heartbeat-token'),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: provisioned.heartbeatToken),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Token copied')));
                }
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      await _load();
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
          if (detail != null)
            IconButton(
              key: const Key('tank-feeding-history-button'),
              tooltip: 'Feeding history',
              onPressed: _openFeedingHistory,
              icon: const Icon(Icons.history_rounded),
            ),
          if (detail != null)
            IconButton(
              key: const Key('portion-preview-button'),
              tooltip: 'Preview feeding portion',
              onPressed: _openPortionPreview,
              icon: const Icon(Icons.scale_outlined),
            ),
          if (_isOwner && detail?.tank.status != TankStatus.archived) ...[
            IconButton(
              key: const Key('edit-tank-schedule-button'),
              tooltip: 'Edit feeding schedule',
              onPressed: _editSchedule,
              icon: const Icon(Icons.schedule_rounded),
            ),
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
          _AppetiteObservationSection(
            observation: detail.appetiteObservation,
            dateLabel: _date,
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
                label: 'Schedule source',
                value: detail.scheduleMode == TankScheduleMode.override
                    ? 'Tank override'
                    : tank.groupName == null
                    ? 'Inherited — no group assigned'
                    : 'Inherited from ${tank.groupName}',
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
              if (detail.deviceHealth != null) ...[
                const Divider(height: 24),
                _InfoRow(
                  label: 'Feeding safety',
                  value: detail.deviceHealth!.feedingAllowed
                      ? 'Ready — all required hardware is healthy'
                      : 'Blocked — hardware attention required',
                ),
                ...detail.deviceHealth!.components.map(
                  (component) => _DeviceHealthRow(
                    component: component,
                    canProvision:
                        _isOwner && tank.status != TankStatus.archived,
                    onProvision: () => _provisionDevice(component.type),
                    typeLabel: _deviceType(component.type),
                    statusLabel: _deviceDescription(component.state),
                    heartbeatLabel: component.lastHeartbeatAt == null
                        ? 'No heartbeat received'
                        : 'Last heartbeat ${_date(component.lastHeartbeatAt!)}',
                  ),
                ),
              ],
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

  String _deviceType(TankDeviceType type) => switch (type) {
    TankDeviceType.camera => 'Camera',
    TankDeviceType.edgeProcessor => 'Edge processor',
    TankDeviceType.feeder => 'Feeder',
  };

  String _date(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _AppetiteObservationSection extends StatelessWidget {
  const _AppetiteObservationSection({
    required this.observation,
    required this.dateLabel,
  });

  final TankAppetiteObservation? observation;
  final String Function(DateTime) dateLabel;

  @override
  Widget build(BuildContext context) {
    final item = observation;
    if (item == null) {
      return const _Section(
        title: 'Appetite observation',
        children: [
          _InfoRow(
            label: 'Status',
            value: 'No appetite observation received yet',
          ),
        ],
      );
    }
    final reasons = item.reviewReasons.map(_reviewReason).join(', ');
    return _Section(
      title: 'Appetite observation',
      children: [
        _InfoRow(
          label: 'Appetite',
          value: item.appetiteResult == AppetiteResult.high ? 'High' : 'Low',
        ),
        _InfoRow(
          label: 'Detected',
          value: '${item.detectedGuppyCount} guppies',
        ),
        _InfoRow(
          label: 'Confidence',
          value: '${(item.confidence * 100).toStringAsFixed(0)}%',
        ),
        _InfoRow(label: 'Observed', value: dateLabel(item.observedAt)),
        _InfoRow(label: 'Model', value: item.modelVersion),
        _InfoRow(
          label: 'Safety',
          value: item.validForFeedingDecision
              ? 'Valid for feeding decision'
              : 'Not valid for feeding decision',
        ),
        if (item.ownerReviewRequired)
          _InfoRow(
            label: 'Review',
            value: reasons.isEmpty ? 'Owner review required' : reasons,
          ),
      ],
    );
  }

  String _reviewReason(String reason) => switch (reason) {
    'STALE' => 'Observation is stale',
    'LOW_CONFIDENCE' => 'Low confidence',
    'COUNT_INCONSISTENT' => 'Count differs from expected',
    _ => reason,
  };
}

class _DeviceHealthRow extends StatelessWidget {
  const _DeviceHealthRow({
    required this.component,
    required this.canProvision,
    required this.onProvision,
    required this.typeLabel,
    required this.statusLabel,
    required this.heartbeatLabel,
  });

  final TankDeviceComponent component;
  final bool canProvision;
  final VoidCallback onProvision;
  final String typeLabel;
  final String statusLabel;
  final String heartbeatLabel;

  @override
  Widget build(BuildContext context) {
    final message = component.message;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  typeLabel,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(statusLabel),
                Text(
                  heartbeatLabel,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (message != null && message.isNotEmpty)
                  Text(message, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (canProvision)
            TextButton(
              key: Key('provision-${component.type.name}-device'),
              onPressed: onProvision,
              child: Text(component.deviceId == null ? 'Connect' : 'Rotate'),
            ),
        ],
      ),
    );
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
