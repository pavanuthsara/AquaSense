import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/facility.dart';
import '../domain/facility_repository.dart';
import '../domain/feeder_calibration.dart';
import '../domain/tank.dart';

class PortionPreviewScreen extends StatefulWidget {
  const PortionPreviewScreen({
    required this.facility,
    required this.tank,
    required this.repository,
    super.key,
  });

  final Facility facility;
  final Tank tank;
  final FacilityRepository repository;

  @override
  State<PortionPreviewScreen> createState() => _PortionPreviewScreenState();
}

class _PortionPreviewScreenState extends State<PortionPreviewScreen> {
  late final TextEditingController _fishCount;
  PortionPreview? _preview;
  Object? _error;
  bool _loading = true;

  bool get _isOwner => widget.facility.role == FacilityRole.owner;

  @override
  void initState() {
    super.initState();
    _fishCount = TextEditingController(
      text: (widget.tank.detectedGuppyCount ?? widget.tank.expectedGuppyCount)
          .toString(),
    );
    _load();
  }

  @override
  void dispose() {
    _fishCount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final count = int.tryParse(_fishCount.text);
    if (count == null || count < 0 || count > 1000000) {
      setState(() {
        _loading = false;
        _error = const FacilityException(
          'Enter a fish count from 0 to 1,000,000.',
        );
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final preview = await widget.repository.getPortionPreview(
        facilityId: widget.facility.id,
        tankId: widget.tank.id,
        fishCount: count,
      );
      if (mounted) {
        setState(() {
          _preview = preview;
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

  Future<void> _configure() async {
    final current = _preview?.calibration;
    final draft = await showDialog<FeederCalibrationDraft>(
      context: context,
      builder: (_) => _CalibrationDialog(current: current),
    );
    if (draft == null || !mounted) return;
    try {
      await widget.repository.createFeederCalibration(
        facilityId: widget.facility.id,
        draft: draft,
      );
      await _load();
    } on FacilityException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.tank.name} portion')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Portion preview',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Preview uses calibrated feeder units. Physical mass has not been validated.',
            ),
            const SizedBox(height: 18),
            TextField(
              key: const Key('portion-fish-count'),
              controller: _fishCount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Fish count',
                suffixIcon: IconButton(
                  key: const Key('refresh-portion-preview'),
                  tooltip: 'Update preview',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.calculate_outlined),
                ),
              ),
              onSubmitted: (_) => _load(),
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Text(
                _error is FacilityException
                    ? (_error! as FacilityException).message
                    : 'The portion preview could not be loaded.',
                key: const Key('portion-preview-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else
              _PreviewCard(preview: _preview!),
            const SizedBox(height: 18),
            if (_isOwner)
              OutlinedButton.icon(
                key: const Key('configure-feeder-calibration'),
                onPressed: _configure,
                icon: const Icon(Icons.tune_rounded),
                label: Text(
                  _preview?.configured == true
                      ? 'Publish new calibration version'
                      : 'Configure feeder units',
                ),
              )
            else
              const Text(
                'Only an aquarium owner can change feeder calibration.',
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.preview});
  final PortionPreview preview;

  @override
  Widget build(BuildContext context) {
    if (!preview.configured) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Text(
            'No feeder calibration is configured. A portion cannot be calculated yet.',
            key: Key('calibration-not-configured'),
          ),
        ),
      );
    }
    final calibration = preview.calibration!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${_units(preview.portionUnits!)} feeder units',
              key: const Key('portion-result'),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              '${preview.fishCount} fish × ${_units(calibration.unitsPerFish)} '
              '= ${_units(preview.rawUnits!)} feeder units',
            ),
            const SizedBox(height: 6),
            Text('Calibration version ${calibration.version}'),
            Text(
              'Bounds: ${_units(calibration.minimumUnits)}–'
              '${_units(calibration.maximumUnits)} feeder units',
            ),
            if (preview.limit == PortionLimit.minimum)
              const Text('Minimum portion applied.'),
            if (preview.limit == PortionLimit.maximum)
              const Text('Maximum portion applied.'),
            if (preview.limit == PortionLimit.zeroFish)
              const Text('Zero fish results in no feeder movement.'),
          ],
        ),
      ),
    );
  }

  static String _units(double value) => value.toStringAsFixed(4);
}

class _CalibrationDialog extends StatefulWidget {
  const _CalibrationDialog({this.current});
  final FeederCalibration? current;

  @override
  State<_CalibrationDialog> createState() => _CalibrationDialogState();
}

class _CalibrationDialogState extends State<_CalibrationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _rate;
  late final TextEditingController _minimum;
  late final TextEditingController _maximum;

  @override
  void initState() {
    super.initState();
    _rate = TextEditingController(
      text: widget.current?.unitsPerFish.toString(),
    );
    _minimum = TextEditingController(
      text: widget.current?.minimumUnits.toString(),
    );
    _maximum = TextEditingController(
      text: widget.current?.maximumUnits.toString(),
    );
  }

  @override
  void dispose() {
    _rate.dispose();
    _minimum.dispose();
    _maximum.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.current == null ? 'Configure feeder' : 'New version'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(_rate, 'Units per fish', 'calibration-rate'),
              const SizedBox(height: 12),
              _field(_minimum, 'Minimum units', 'calibration-minimum'),
              const SizedBox(height: 12),
              _field(_maximum, 'Maximum units', 'calibration-maximum'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('save-feeder-calibration'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final rate = double.parse(_rate.text);
            final minimum = double.parse(_minimum.text);
            final maximum = double.parse(_maximum.text);
            if (minimum > maximum) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Minimum units cannot exceed maximum units.'),
                ),
              );
              return;
            }
            Navigator.of(context).pop(
              FeederCalibrationDraft(
                unitsPerFish: rate,
                minimumUnits: minimum,
                maximumUnits: maximum,
              ),
            );
          },
          child: const Text('Publish'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label, String key) {
    return TextFormField(
      key: Key(key),
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, suffixText: 'units'),
      validator: (value) {
        final parsed = double.tryParse(value ?? '');
        return parsed == null || parsed <= 0
            ? 'Enter a value above zero.'
            : null;
      },
    );
  }
}
