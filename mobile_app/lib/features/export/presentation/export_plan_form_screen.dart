import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../facility/domain/facility.dart';
import '../domain/export_advisory.dart';
import '../domain/export_repository.dart';
import 'export_advisory_screen.dart';

/// Shipment details -> transit advisory.
class ExportPlanFormScreen extends StatefulWidget {
  const ExportPlanFormScreen({
    required this.facility,
    required this.repository,
    super.key,
  });

  final Facility facility;
  final ExportRepository repository;

  @override
  State<ExportPlanFormScreen> createState() => _ExportPlanFormScreenState();
}

class _ExportPlanFormScreenState extends State<ExportPlanFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _label = TextEditingController();
  final _mass = TextEditingController(text: '0.3');
  final _total = TextEditingController(text: '1000');
  final _water = TextEditingController(text: '0.4');
  final _gas = TextEditingController(text: '1.2');
  var _species = ExportSpecies.guppy;
  var _hours = 36.0;
  var _temperature = const RangeValues(24, 28);
  var _target = 95.0;
  var _allowAnaesthetic = true;
  var _allowZeolite = true;
  var _maxFasting = 48.0;
  var _submitting = false;
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    _mass.dispose();
    _total.dispose();
    _water.dispose();
    _gas.dispose();
    super.dispose();
  }

  String? Function(String?) _number(double min, double max) {
    return (value) {
      final number = double.tryParse((value ?? '').trim());
      if (number == null || number < min || number > max) {
        return 'Enter a value from $min to $max.';
      }
      return null;
    };
  }

  String? _optionalCount(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    final count = int.tryParse(text);
    if (count == null || count < 1 || count > 10000000) {
      return 'Enter a whole number, or leave empty.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final request = ExportShipmentRequest(
      label: _label.text,
      species: _species,
      fishMassG: double.parse(_mass.text.trim()),
      totalFish: int.tryParse(_total.text.trim()),
      waterL: double.parse(_water.text.trim()),
      gasL: double.parse(_gas.text.trim()),
      durationH: _hours,
      tempLowC: _temperature.start,
      tempHighC: _temperature.end,
      targetSurvivalPct: _target,
      allowAnaesthetic: _allowAnaesthetic,
      allowZeolite: _allowZeolite,
      maxFastingH: _maxFasting,
    );
    try {
      final detail = await widget.repository.createAdvisory(
        facilityId: widget.facility.id,
        request: request,
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<bool>(
          builder: (_) => ExportAdvisoryScreen(detail: detail),
        ),
        result: true,
      );
    } on ExportException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'The plan could not be calculated. Try again.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decimal = [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      LengthLimitingTextInputFormatter(8),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Plan a shipment')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            key: const Key('export-form-scroll'),
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Tell AquaSense about the shipment. It simulates what happens '
                'inside the sealed bag and works out how many fish to pack, '
                'what to add, and what to expect.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                key: const Key('export-label-field'),
                controller: _label,
                inputFormatters: [LengthLimitingTextInputFormatter(120)],
                decoration: const InputDecoration(
                  labelText: 'Plan name (optional)',
                  hintText: 'Dubai order, 12 March',
                ),
              ),
              const SizedBox(height: 20),
              Text('Species', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<ExportSpecies>(
                key: const Key('export-species-selector'),
                segments: [
                  for (final species in ExportSpecies.values)
                    ButtonSegment(value: species, label: Text(species.label)),
                ],
                selected: {_species},
                onSelectionChanged: _submitting
                    ? null
                    : (selection) => setState(() {
                        _species = selection.first;
                        _mass.text = _species.typicalMassG.toString();
                      }),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const Key('export-mass-field'),
                      controller: _mass,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: decimal,
                      decoration: const InputDecoration(
                        labelText: 'Average fish weight',
                        suffixText: 'g',
                      ),
                      validator: _number(0.01, 500),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      key: const Key('export-total-field'),
                      controller: _total,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(8),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Fish to ship',
                        helperText: 'Optional',
                      ),
                      validator: _optionalCount,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text('Bag', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const Key('export-water-field'),
                      controller: _water,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: decimal,
                      decoration: const InputDecoration(
                        labelText: 'Water per bag',
                        suffixText: 'L',
                      ),
                      validator: _number(0.05, 50),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      key: const Key('export-gas-field'),
                      controller: _gas,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: decimal,
                      decoration: const InputDecoration(
                        labelText: 'Oxygen per bag',
                        suffixText: 'L',
                      ),
                      validator: _number(0.05, 100),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _SliderHeader(
                title: 'Door-to-door time',
                value: '${_hours.round()} h',
              ),
              Slider(
                key: const Key('export-hours-slider'),
                value: _hours,
                min: 6,
                max: 96,
                divisions: 45,
                label: '${_hours.round()} h',
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _hours = value),
              ),
              _SliderHeader(
                title: 'Expected temperature during the trip',
                value:
                    '${_temperature.start.toStringAsFixed(1)}–'
                    '${_temperature.end.toStringAsFixed(1)} °C',
              ),
              RangeSlider(
                key: const Key('export-temperature-slider'),
                values: _temperature,
                min: 15,
                max: 35,
                divisions: 40,
                labels: RangeLabels(
                  '${_temperature.start.toStringAsFixed(1)} °C',
                  '${_temperature.end.toStringAsFixed(1)} °C',
                ),
                onChanged: _submitting
                    ? null
                    : (values) => setState(() => _temperature = values),
              ),
              Text(
                'Give a range, not one value: the plan must stay safe at the '
                'hot end.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _SliderHeader(
                title: 'Minimum fish alive after unpacking',
                value: '${_target.toStringAsFixed(1)} %',
              ),
              Slider(
                key: const Key('export-target-slider'),
                value: _target,
                min: 80,
                max: 99.5,
                divisions: 39,
                label: '${_target.toStringAsFixed(1)} %',
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _target = value),
              ),
              Text(
                '95 % matches the usual 5 % dead-on-arrival warranty.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Text('Allowed add-ons', style: theme.textTheme.titleSmall),
              SwitchListTile(
                key: const Key('export-anaesthetic-switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Anaesthetics (MS-222, benzocaine)'),
                subtitle: const Text('Check the importing country allows them'),
                value: _allowAnaesthetic,
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _allowAnaesthetic = value),
              ),
              SwitchListTile(
                key: const Key('export-zeolite-switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Zeolite (ammonia absorber)'),
                value: _allowZeolite,
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _allowZeolite = value),
              ),
              const SizedBox(height: 8),
              Text(
                'Longest fasting before packing',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SegmentedButton<double>(
                key: const Key('export-fasting-selector'),
                segments: const [
                  ButtonSegment(value: 24, label: Text('24 h')),
                  ButtonSegment(value: 48, label: Text('48 h')),
                ],
                selected: {_maxFasting},
                onSelectionChanged: _submitting
                    ? null
                    : (selection) =>
                          setState(() => _maxFasting = selection.first),
              ),
              if (_error != null) ...[
                const SizedBox(height: 20),
                Text(
                  _error!,
                  key: const Key('export-form-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 28),
              FilledButton.icon(
                key: const Key('export-submit-button'),
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.inventory_2_outlined),
                label: Text(
                  _submitting
                      ? 'Simulating the journey…'
                      : 'Calculate packing plan',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SliderHeader extends StatelessWidget {
  const _SliderHeader({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
