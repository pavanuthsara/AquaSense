import 'dart:math';

import 'package:flutter/material.dart';

import '../domain/disease_check_repository.dart';
import '../domain/disease_prediction.dart';

/// Lets the user add a tank name and note and save a result to the
/// aquarium's history.
///
/// The request key is created once per result and reused if saving fails and
/// is retried, so a result is never saved twice.
class SaveDiseaseCheckPanel extends StatefulWidget {
  const SaveDiseaseCheckPanel({
    required this.facilityId,
    required this.prediction,
    required this.repository,
    this.initialNote = '',
    super.key,
  });

  final String facilityId;
  final DiseasePrediction prediction;
  final DiseaseCheckRepository repository;

  /// Pre-filled note text (used by the video check to summarise the result).
  final String initialNote;

  @override
  State<SaveDiseaseCheckPanel> createState() => _SaveDiseaseCheckPanelState();
}

class _SaveDiseaseCheckPanelState extends State<SaveDiseaseCheckPanel> {
  final _tankController = TextEditingController();
  final _noteController = TextEditingController();
  late String _requestKey = _newRequestKey();
  bool _saving = false;
  bool _saved = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _noteController.text = widget.initialNote;
  }

  @override
  void didUpdateWidget(SaveDiseaseCheckPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.prediction, widget.prediction)) {
      _requestKey = _newRequestKey();
      _saved = false;
      _error = null;
      _noteController.text = widget.initialNote;
    }
  }

  @override
  void dispose() {
    _tankController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String _newRequestKey() {
    final random = Random.secure();
    return 'disease-${DateTime.now().microsecondsSinceEpoch}-'
        '${random.nextInt(1 << 32)}';
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.saveCheck(
        facilityId: widget.facilityId,
        prediction: widget.prediction,
        idempotencyKey: _requestKey,
        tankLabel: _tankController.text,
        note: _noteController.text,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _saved = true;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Saved to this aquarium\'s history.')),
        );
    } on DiseaseCheckException catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_saved) {
      return Card(
        key: const Key('disease-saved'),
        child: ListTile(
          leading: Icon(
            Icons.cloud_done_rounded,
            color: theme.colorScheme.primary,
          ),
          title: const Text('Saved to history'),
          subtitle: const Text('Everyone in this aquarium can see it.'),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Save this result',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Only the result is saved, not the photo.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('disease-tank-field'),
              controller: _tankController,
              enabled: !_saving,
              maxLength: 80,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Tank (optional)',
                hintText: 'For example Tank A3',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('disease-note-field'),
              controller: _noteController,
              enabled: !_saving,
              maxLength: 500,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                counterText: '',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('disease-save-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const Key('disease-save'),
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_alt_rounded),
              label: Text(
                _error == null ? 'Save to history' : 'Try saving again',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
