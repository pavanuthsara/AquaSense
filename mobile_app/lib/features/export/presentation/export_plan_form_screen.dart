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
  final _bags = TextEditingController(text: '20');
  final _fishPerBag = TextEditingController(text: '60');
  var _mode = PlanningMode.suggest;
  var _checkFasting = 24.0;
  var _checkZeolite = false;
  var _checkAnaesthetic = BagAnaesthetic.none;
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
    _bags.dispose();
    _fishPerBag.dispose();
    super.dispose();
  }

  String? Function(String?) _number(double min, double max, String unit) {
    return (value) {
      final number = double.tryParse((value ?? '').trim());
      if (number == null || number < min || number > max) {
        return 'Use $min–$max $unit';
      }
      return null;
    };
  }

  String? _requiredCount(String? value) {
    final count = int.tryParse((value ?? '').trim());
    if (count == null || count < 1 || count > 1000000) {
      return 'Whole number from 1';
    }
    return null;
  }

  String? _bagsValidator(String? value) {
    final error = _requiredCount(value);
    if (error != null) return error;
    final total = int.tryParse(_total.text.trim());
    if (total != null && int.parse(value!.trim()) > total) {
      return 'More bags than fish';
    }
    return null;
  }

  String? _optionalCount(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return _mode == PlanningMode.fixedBags ? 'Needed to fill the bags' : null;
    }
    final count = int.tryParse(text);
    if (count == null || count < 1 || count > 10000000) {
      return 'Whole number, or leave empty';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) {
      setState(() => _error = 'Check the highlighted fields.');
      return;
    }
    FocusScope.of(context).unfocus();
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
      mode: _mode,
      bags: _mode == PlanningMode.fixedBags
          ? int.tryParse(_bags.text.trim())
          : null,
      fishPerBag: _mode == PlanningMode.check
          ? int.tryParse(_fishPerBag.text.trim())
          : null,
      checkFastingH: _checkFasting,
      checkZeolite: _checkZeolite,
      checkAnaesthetic: _checkAnaesthetic,
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

  String get _advancedSummary => [
    'Keep ${_target.toStringAsFixed(1)} % alive',
    'fast up to ${_maxFasting.round()} h',
    if (_allowAnaesthetic && _allowZeolite)
      'all add-ons'
    else if (_allowAnaesthetic)
      'anaesthetics only'
    else if (_allowZeolite)
      'zeolite only'
    else
      'no add-ons',
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.35,
    );
    final decimal = [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      LengthLimitingTextInputFormatter(8),
    ];
    final enabled = !_submitting;
    return Scaffold(
      appBar: AppBar(title: const Text('Plan a shipment')),
      bottomNavigationBar: _SubmitBar(
        submitting: _submitting,
        error: _error,
        onSubmit: _submit,
        label: switch (_mode) {
          PlanningMode.suggest => 'Calculate packing plan',
          PlanningMode.fixedBags => 'Check these bags',
          PlanningMode.check => 'Check my packing',
        },
      ),
      body: SafeArea(
        bottom: false,
        // Fields sit on white cards, so tint them to stay visible.
        child: Theme(
          data: theme.copyWith(
            inputDecorationTheme: theme.inputDecorationTheme.copyWith(
              fillColor: theme.colorScheme.surfaceContainerHigh,
            ),
          ),
          child: Form(
            key: _formKey,
            child: ListView(
              key: const Key('export-form-scroll'),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
                  child: Text(
                    'Enter the shipment details. AquaSense simulates the sealed '
                    'bag over the whole trip and tells you how many fish to '
                    'pack, what to add and what to expect.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),
                _Section(
                  icon: Icons.alt_route_rounded,
                  title: 'How do you want to plan?',
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<PlanningMode>(
                        key: const Key('export-mode-selector'),
                        showSelectedIcon: false,
                        segments: [
                          for (final mode in PlanningMode.values)
                            ButtonSegment(value: mode, label: Text(mode.label)),
                        ],
                        selected: {_mode},
                        onSelectionChanged: enabled
                            ? (selection) =>
                                  setState(() => _mode = selection.first)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(switch (_mode) {
                      PlanningMode.suggest =>
                        'AquaSense works out how many fish to pack per bag, '
                            'how many bags you need and what to add.',
                      PlanningMode.fixedBags =>
                        'You choose how many bags. AquaSense checks if that is '
                            'safe and what to add, or how many bags you need.',
                      PlanningMode.check =>
                        'Enter how you normally pack. AquaSense shows what '
                            'happens to your fish and compares it with the '
                            'safe plan.',
                    }, style: muted),
                  ],
                ),
                _Section(
                  icon: Icons.set_meal_outlined,
                  title: 'Fish',
                  children: [
                    TextFormField(
                      key: const Key('export-label-field'),
                      controller: _label,
                      enabled: enabled,
                      textCapitalization: TextCapitalization.sentences,
                      inputFormatters: [LengthLimitingTextInputFormatter(120)],
                      decoration: const InputDecoration(
                        labelText: 'Plan name (optional)',
                        hintText: 'e.g. Dubai order, 12 March',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Species', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ExportSpecies>(
                        key: const Key('export-species-selector'),
                        segments: [
                          for (final species in ExportSpecies.values)
                            ButtonSegment(
                              value: species,
                              label: Text(species.label),
                            ),
                        ],
                        selected: {_species},
                        onSelectionChanged: enabled
                            ? (selection) => setState(() {
                                _species = selection.first;
                                _mass.text = _species.typicalMassG.toString();
                              })
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: const Key('export-mass-field'),
                            controller: _mass,
                            enabled: enabled,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: decimal,
                            decoration: InputDecoration(
                              labelText: 'Weight per fish',
                              suffixText: 'g',
                              helperText: 'Typical ${_species.typicalMassG} g',
                            ),
                            validator: _number(0.01, 500, 'g'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            key: const Key('export-total-field'),
                            controller: _total,
                            enabled: enabled,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(8),
                            ],
                            decoration: InputDecoration(
                              labelText: 'Fish to ship',
                              suffixText: 'fish',
                              helperText: _mode == PlanningMode.fixedBags
                                  ? 'Required'
                                  : 'Optional, for bag count',
                            ),
                            validator: _optionalCount,
                          ),
                        ),
                      ],
                    ),
                    if (_mode == PlanningMode.fixedBags) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('export-bags-field'),
                        controller: _bags,
                        enabled: enabled,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(7),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Number of bags you have',
                          suffixText: 'bags',
                        ),
                        validator: _bagsValidator,
                      ),
                    ],
                    if (_mode == PlanningMode.check) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('export-fish-per-bag-field'),
                        controller: _fishPerBag,
                        enabled: enabled,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(7),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Fish per bag (your packing)',
                          suffixText: 'fish',
                        ),
                        validator: _requiredCount,
                      ),
                    ],
                  ],
                ),
                _Section(
                  icon: Icons.shopping_bag_outlined,
                  title: 'Each bag',
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: const Key('export-water-field'),
                            controller: _water,
                            enabled: enabled,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: decimal,
                            decoration: const InputDecoration(
                              labelText: 'Water',
                              suffixText: 'L',
                            ),
                            validator: _number(0.05, 50, 'L'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            key: const Key('export-gas-field'),
                            controller: _gas,
                            enabled: enabled,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: decimal,
                            decoration: const InputDecoration(
                              labelText: 'Oxygen gas',
                              suffixText: 'L',
                            ),
                            validator: _number(0.05, 100, 'L'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'A common ratio is 1 part water to 3 parts oxygen.',
                      style: muted,
                    ),
                  ],
                ),
                _Section(
                  icon: Icons.flight_takeoff_rounded,
                  title: 'Journey',
                  children: [
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
                      onChanged: enabled
                          ? (value) => setState(() => _hours = value)
                          : null,
                    ),
                    _SliderEnds(start: '6 h', end: '96 h'),
                    const SizedBox(height: 4),
                    Text(
                      'From packing until the fish are out of the bag.',
                      style: muted,
                    ),
                    const SizedBox(height: 20),
                    _SliderHeader(
                      title: 'Temperature during the trip',
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
                      onChanged: enabled
                          ? (values) => setState(() => _temperature = values)
                          : null,
                    ),
                    _SliderEnds(start: '15 °C', end: '35 °C'),
                    const SizedBox(height: 4),
                    Text(
                      'Give the coolest and warmest you expect. The plan must '
                      'stay safe at the warm end.',
                      style: muted,
                    ),
                  ],
                ),
                if (_mode == PlanningMode.check)
                  _Section(
                    icon: Icons.science_outlined,
                    title: 'What you put in the bag',
                    children: [
                      Text(
                        'Fasting before packing',
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<double>(
                          key: const Key('export-check-fasting-selector'),
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: 0, label: Text('0 h')),
                            ButtonSegment(value: 12, label: Text('12 h')),
                            ButtonSegment(value: 24, label: Text('24 h')),
                            ButtonSegment(value: 48, label: Text('48 h')),
                          ],
                          selected: {_checkFasting},
                          onSelectionChanged: enabled
                              ? (selection) => setState(
                                  () => _checkFasting = selection.first,
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Anaesthetic', style: theme.textTheme.labelLarge),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<BagAnaesthetic>(
                          key: const Key('export-check-anaesthetic-selector'),
                          showSelectedIcon: false,
                          segments: [
                            for (final option in BagAnaesthetic.values)
                              ButtonSegment(
                                value: option,
                                label: Text(option.label),
                              ),
                          ],
                          selected: {_checkAnaesthetic},
                          onSelectionChanged: enabled
                              ? (selection) => setState(
                                  () => _checkAnaesthetic = selection.first,
                                )
                              : null,
                        ),
                      ),
                      SwitchListTile(
                        key: const Key('export-check-zeolite-switch'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Zeolite 20 g/L'),
                        value: _checkZeolite,
                        onChanged: enabled
                            ? (value) => setState(() => _checkZeolite = value)
                            : null,
                      ),
                    ],
                  ),
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  clipBehavior: Clip.antiAlias,
                  child: Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      key: const Key('export-advanced-settings'),
                      tilePadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      leading: Icon(
                        Icons.tune_rounded,
                        color: theme.colorScheme.primary,
                      ),
                      title: Text(
                        _mode == PlanningMode.check
                            ? 'Safety target and recommended add-ons'
                            : 'Safety and add-ons',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(_advancedSummary, style: muted),
                      children: [
                        _SliderHeader(
                          title: 'Fish alive after unpacking, at least',
                          value: '${_target.toStringAsFixed(1)} %',
                        ),
                        Slider(
                          key: const Key('export-target-slider'),
                          value: _target,
                          min: 80,
                          max: 99.5,
                          divisions: 39,
                          label: '${_target.toStringAsFixed(1)} %',
                          onChanged: enabled
                              ? (value) => setState(() => _target = value)
                              : null,
                        ),
                        Text(
                          '95 % matches the usual 5 % dead-on-arrival warranty.',
                          style: muted,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Longest fasting before packing',
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<double>(
                            key: const Key('export-fasting-selector'),
                            segments: const [
                              ButtonSegment(value: 24, label: Text('24 h')),
                              ButtonSegment(value: 48, label: Text('48 h')),
                            ],
                            selected: {_maxFasting},
                            onSelectionChanged: enabled
                                ? (selection) => setState(
                                    () => _maxFasting = selection.first,
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Allowed in the bag',
                          style: theme.textTheme.labelLarge,
                        ),
                        SwitchListTile(
                          key: const Key('export-anaesthetic-switch'),
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Anaesthetics'),
                          subtitle: const Text(
                            'MS-222, benzocaine. Check the importing country '
                            'allows them.',
                          ),
                          value: _allowAnaesthetic,
                          onChanged: enabled
                              ? (value) =>
                                    setState(() => _allowAnaesthetic = value)
                              : null,
                        ),
                        SwitchListTile(
                          key: const Key('export-zeolite-switch'),
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Zeolite'),
                          subtitle: const Text('Absorbs ammonia in the water.'),
                          value: _allowZeolite,
                          onChanged: enabled
                              ? (value) => setState(() => _allowZeolite = value)
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps the calculate button reachable at the bottom of the screen.
class _SubmitBar extends StatelessWidget {
  const _SubmitBar({
    required this.submitting,
    required this.error,
    required this.onSubmit,
    required this.label,
  });

  final bool submitting;
  final String? error;
  final VoidCallback onSubmit;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            12 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error != null) ...[
                Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 18,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        error!,
                        key: const Key('export-form-error'),
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              FilledButton.icon(
                key: const Key('export-submit-button'),
                onPressed: submitting ? null : onSubmit,
                icon: submitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_graph_rounded),
                label: Text(submitting ? 'Simulating the journey…' : label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
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
        Expanded(child: Text(title, style: theme.textTheme.labelLarge)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _SliderEnds extends StatelessWidget {
  const _SliderEnds({required this.start, required this.end});

  final String start;
  final String end;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(start, style: style),
          Text(end, style: style),
        ],
      ),
    );
  }
}
