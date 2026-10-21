import 'package:flutter/material.dart';

import '../domain/facility.dart';
import '../domain/facility_repository.dart';
import '../domain/tank.dart';

class TankFeedingScheduleScreen extends StatefulWidget {
  const TankFeedingScheduleScreen({
    required this.facility,
    required this.detail,
    required this.repository,
    super.key,
  });

  final Facility facility;
  final TankDetail detail;
  final FacilityRepository repository;

  @override
  State<TankFeedingScheduleScreen> createState() =>
      _TankFeedingScheduleScreenState();
}

class _TankFeedingScheduleScreenState extends State<TankFeedingScheduleScreen> {
  late TankScheduleMode _mode;
  late List<String> _overrideTimes;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _mode = widget.detail.scheduleMode;
    _overrideTimes = [...widget.detail.feedingTimes]..sort();
  }

  Future<void> _addTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _overrideTimes.isEmpty
          ? const TimeOfDay(hour: 8, minute: 0)
          : _parse(_overrideTimes.last),
      helpText: 'Select tank feeding time',
    );
    if (selected == null || !mounted) return;
    final value = _format(selected);
    if (_overrideTimes.contains(value)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$value is already in this override.')),
      );
      return;
    }
    setState(() {
      _overrideTimes = [..._overrideTimes, value]..sort();
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_mode == TankScheduleMode.override && _overrideTimes.isEmpty) {
      setState(() => _error = 'Add at least one time to the tank override.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.updateTankFeedingSchedule(
        facilityId: widget.facility.id,
        tankId: widget.detail.tank.id,
        mode: _mode,
        times: _mode == TankScheduleMode.override ? _overrideTimes : const [],
      );
      if (mounted) Navigator.of(context).pop(true);
    } on FacilityException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tank = widget.detail.tank;
    final inherited = _mode == TankScheduleMode.inherited;
    return Scaffold(
      appBar: AppBar(title: Text('${tank.name} schedule')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Schedule source',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('Times use ${widget.facility.timeZone.replaceAll('_', ' ')}.'),
            const SizedBox(height: 16),
            SegmentedButton<TankScheduleMode>(
              key: const Key('tank-schedule-mode'),
              segments: const [
                ButtonSegment(
                  value: TankScheduleMode.inherited,
                  icon: Icon(Icons.account_tree_outlined),
                  label: Text('Inherit group'),
                ),
                ButtonSegment(
                  value: TankScheduleMode.override,
                  icon: Icon(Icons.tune_rounded),
                  label: Text('Tank override'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: _saving
                  ? null
                  : (selection) => setState(() {
                      _mode = selection.single;
                      _error = null;
                    }),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      inherited
                          ? tank.groupName == null
                                ? 'No group schedule available'
                                : 'Inherited from ${tank.groupName}'
                          : 'Complete tank replacement',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      inherited
                          ? tank.groupName == null
                                ? 'Automatic feeding stays disabled until this tank joins a group or receives an override.'
                                : 'Changes to the group schedule automatically apply to this tank.'
                          : 'These times fully replace the group schedule for this tank.',
                    ),
                    const SizedBox(height: 12),
                    if (!inherited)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const Key('add-tank-feeding-time'),
                          onPressed: _saving ? null : _addTime,
                          icon: const Icon(Icons.add_alarm_rounded),
                          label: const Text('Add time'),
                        ),
                      ),
                    if ((inherited
                            ? widget.detail.inheritedFeedingTimes
                            : _overrideTimes)
                        .isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('No feeding times configured.'),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            (inherited
                                    ? widget.detail.inheritedFeedingTimes
                                    : _overrideTimes)
                                .map(
                                  (time) => InputChip(
                                    key: Key('tank-feeding-time-$time'),
                                    label: Text(time),
                                    deleteIcon: Icon(
                                      Icons.close_rounded,
                                      key: Key(
                                        'remove-tank-feeding-time-$time',
                                      ),
                                    ),
                                    onDeleted: inherited || _saving
                                        ? null
                                        : () => setState(
                                            () => _overrideTimes.remove(time),
                                          ),
                                  ),
                                )
                                .toList(),
                      ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('tank-schedule-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('save-tank-feeding-schedule'),
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_rounded),
              label: const Text('Save schedule'),
            ),
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
}
