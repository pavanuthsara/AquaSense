import 'package:flutter/material.dart';

import '../domain/facility.dart';
import '../domain/facility_repository.dart';
import '../domain/tank_group.dart';

class GroupFeedingScheduleScreen extends StatefulWidget {
  const GroupFeedingScheduleScreen({
    required this.facility,
    required this.group,
    required this.repository,
    super.key,
  });

  final Facility facility;
  final TankGroup group;
  final FacilityRepository repository;

  @override
  State<GroupFeedingScheduleScreen> createState() =>
      _GroupFeedingScheduleScreenState();
}

class _GroupFeedingScheduleScreenState
    extends State<GroupFeedingScheduleScreen> {
  late List<String> _times;
  late bool _automationEnabled;
  bool _saving = false;
  String? _error;

  bool get _canEdit =>
      widget.facility.role == FacilityRole.owner && !widget.group.archived;

  @override
  void initState() {
    super.initState();
    _times = [...widget.group.feedingTimes]..sort();
    _automationEnabled = widget.group.feedingAutomationEnabled;
  }

  Future<void> _addTime() async {
    final initial = _times.isEmpty
        ? const TimeOfDay(hour: 8, minute: 0)
        : _parse(_times.last);
    final selected = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: 'Select daily feeding time',
    );
    if (selected == null || !mounted) return;
    final value = _format(selected);
    if (_times.contains(value)) {
      _message('$value is already in this schedule.');
      return;
    }
    setState(() {
      _times = [..._times, value]..sort();
      _error = null;
    });
  }

  void _removeTime(String value) {
    setState(() {
      _times = _times.where((time) => time != value).toList();
      if (_times.isEmpty) _automationEnabled = false;
    });
  }

  Future<void> _save() async {
    if (_times.isEmpty || _saving) {
      setState(() => _error = 'Add at least one daily feeding time.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.updateTankGroupFeedingSchedule(
        facilityId: widget.facility.id,
        groupId: widget.group.id,
        times: _times,
        automationEnabled: _automationEnabled,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on FacilityException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'The feeding schedule could not be saved. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.group.name} schedule')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Daily feeding schedule',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Times use the aquarium timezone: '
                      '${widget.facility.timeZone.replaceAll('_', ' ')}.',
                    ),
                    if (!_canEdit) ...[
                      const SizedBox(height: 8),
                      Text(
                        widget.group.archived
                            ? 'Archived groups are read-only.'
                            : 'Workers can view this schedule but cannot change it.',
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Session start times',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (_canEdit)
                          TextButton.icon(
                            key: const Key('add-group-feeding-time'),
                            onPressed: _saving ? null : _addTime,
                            icon: const Icon(Icons.add_alarm_rounded),
                            label: const Text('Add time'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_times.isEmpty)
                      const Text('No feeding times configured.')
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _times
                            .map(
                              (time) => InputChip(
                                key: Key('group-feeding-time-$time'),
                                label: Text(time),
                                deleteIcon: Icon(
                                  Icons.close_rounded,
                                  key: Key('remove-group-feeding-time-$time'),
                                ),
                                deleteButtonTooltipMessage: 'Remove $time',
                                onDeleted: _canEdit && !_saving
                                    ? () => _removeTime(time)
                                    : null,
                              ),
                            )
                            .toList(),
                      ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      key: const Key('group-feeding-automation-switch'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Automatic group feeding'),
                      subtitle: Text(
                        _automationEnabled
                            ? 'Enabled for the configured daily times.'
                            : 'Paused. No automatic sessions will be started.',
                      ),
                      value: _automationEnabled,
                      onChanged: _canEdit && !_saving && _times.isNotEmpty
                          ? (value) =>
                                setState(() => _automationEnabled = value)
                          : null,
                    ),
                    if (widget.group.nextSessionAt != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Stored next execution: '
                        '${_utc(widget.group.nextSessionAt!)} UTC',
                        key: const Key('group-next-session'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('group-feeding-schedule-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_canEdit) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const Key('save-group-feeding-schedule'),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: const Text('Save schedule'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  TimeOfDay _parse(String value) {
    final parts = value.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _format(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  String _utc(DateTime value) {
    final utc = value.toUtc();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${utc.year}-${two(utc.month)}-${two(utc.day)} '
        '${two(utc.hour)}:${two(utc.minute)}';
  }
}
