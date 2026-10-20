import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/facility.dart';
import '../domain/facility_repository.dart';
import '../domain/tank.dart';
import '../domain/tank_group.dart';

class TankFormScreen extends StatefulWidget {
  const TankFormScreen({
    required this.facility,
    required this.repository,
    required this.groups,
    this.tank,
    super.key,
  });

  final Facility facility;
  final FacilityRepository repository;
  final List<TankGroup> groups;
  final Tank? tank;

  @override
  State<TankFormScreen> createState() => _TankFormScreenState();
}

class _TankFormScreenState extends State<TankFormScreen> {
  static const _unassigned = '__unassigned__';
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _expectedCount;
  late final TextEditingController _tags;
  late final TextEditingController _notes;
  late String _groupId;
  late bool _automationEnabled;
  bool _saving = false;
  String? _error;

  bool get _canEnableAutomation =>
      _groupId != _unassigned ||
      widget.tank?.scheduleMode == TankScheduleMode.override;

  @override
  void initState() {
    super.initState();
    final tank = widget.tank;
    _name = TextEditingController(text: tank?.name);
    _code = TextEditingController(text: tank?.code);
    _expectedCount = TextEditingController(
      text: tank?.expectedGuppyCount.toString() ?? '',
    );
    _tags = TextEditingController(text: tank?.tags.join(', '));
    _notes = TextEditingController(text: tank?.notes);
    _groupId = tank?.groupId ?? _unassigned;
    _automationEnabled = tank?.automationEnabled ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _expectedCount.dispose();
    _tags.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final draft = TankDraft(
      name: _name.text.trim(),
      code: _code.text.trim(),
      expectedGuppyCount: int.parse(_expectedCount.text),
      groupId: _groupId == _unassigned ? null : _groupId,
      tags: _tags.text.split(','),
      automationEnabled: _automationEnabled,
      notes: _notes.text.trim(),
    );
    try {
      final tank = widget.tank;
      if (tank == null) {
        await widget.repository.createTank(
          facilityId: widget.facility.id,
          draft: draft,
        );
      } else {
        await widget.repository.updateTank(
          facilityId: widget.facility.id,
          tankId: tank.id,
          draft: draft,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on FacilityException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'The tank could not be saved. Try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeGroups = widget.groups.where((group) => !group.archived);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tank == null ? 'Add tank' : 'Edit tank'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            key: const Key('tank-form-scroll'),
            padding: const EdgeInsets.all(24),
            children: [
              TextFormField(
                key: const Key('tank-name-field'),
                controller: _name,
                textCapitalization: TextCapitalization.words,
                inputFormatters: [LengthLimitingTextInputFormatter(120)],
                decoration: const InputDecoration(labelText: 'Tank name'),
                validator: _required,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('tank-code-field'),
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [LengthLimitingTextInputFormatter(64)],
                decoration: const InputDecoration(
                  labelText: 'Tank code',
                  hintText: 'N-001',
                ),
                validator: _required,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('tank-expected-count-field'),
                controller: _expectedCount,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Expected guppy count',
                ),
                validator: (value) {
                  final count = int.tryParse(value ?? '');
                  if (count == null || count < 0 || count > 1000000) {
                    return 'Enter a count from 0 to 1,000,000.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: const Key('tank-group-field'),
                value: _groupId,
                decoration: const InputDecoration(labelText: 'Tank group'),
                items: [
                  const DropdownMenuItem(
                    value: _unassigned,
                    child: Text('Unassigned'),
                  ),
                  ...activeGroups.map(
                    (group) => DropdownMenuItem(
                      value: group.id,
                      child: Text(group.name),
                    ),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        _groupId = value!;
                        if (!_canEnableAutomation) {
                          _automationEnabled = false;
                        }
                      }),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('tank-tags-field'),
                controller: _tags,
                inputFormatters: [LengthLimitingTextInputFormatter(400)],
                decoration: const InputDecoration(
                  labelText: 'Tags',
                  helperText: 'Separate tags with commas',
                  hintText: 'breeding, priority',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                key: const Key('tank-automation-switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Automatic feeding enabled'),
                subtitle: Text(
                  _canEnableAutomation
                      ? 'Runs only when its effective schedule and safety checks allow it.'
                      : 'Assign a group or save a tank schedule override first.',
                ),
                value: _automationEnabled,
                onChanged: _saving || !_canEnableAutomation
                    ? null
                    : (value) => setState(() => _automationEnabled = value),
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('tank-notes-field'),
                controller: _notes,
                maxLines: 4,
                inputFormatters: [LengthLimitingTextInputFormatter(2000)],
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const Key('save-tank-button'),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(
                  widget.tank == null ? 'Create tank' : 'Save changes',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;
}
