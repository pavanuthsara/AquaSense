import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/appetite_check.dart';
import '../domain/facility.dart';
import '../domain/facility_repository.dart';
import '../domain/tank.dart';

class AppetiteCheckCard extends StatefulWidget {
  const AppetiteCheckCard({
    super.key,
    required this.facilityId,
    required this.tankId,
    required this.repository,
  });

  final String facilityId;
  final String tankId;
  final FacilityRepository repository;

  @override
  State<AppetiteCheckCard> createState() => _AppetiteCheckCardState();
}

class _AppetiteCheckCardState extends State<AppetiteCheckCard> {
  AppetiteCheck? _check;
  String? _error;
  bool _busy = false;
  Timer? _pollTimer;
  DateTime? _deadline;
  int _generation = 0;

  @override
  void dispose() {
    _generation++;
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AppetiteCheckCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tankId != widget.tankId ||
        oldWidget.facilityId != widget.facilityId ||
        oldWidget.repository != widget.repository) {
      _generation++;
      _pollTimer?.cancel();
      _busy = false;
      _check = null;
      _error = null;
    }
  }

  Future<void> _start() async {
    if (_busy) return;
    final generation = ++_generation;
    _deadline = DateTime.now().add(const Duration(seconds: 70));
    setState(() {
      _busy = true;
      _error = null;
      _check = null;
    });
    try {
      final check = await widget.repository
          .requestAppetiteCheck(
            facilityId: widget.facilityId,
            tankId: widget.tankId,
          )
          .timeout(const Duration(seconds: 10));
      if (!mounted || generation != _generation) return;
      _accept(check, generation);
    } catch (error) {
      _failed(error, generation);
    }
  }

  void _accept(AppetiteCheck check, int generation) {
    setState(() {
      _check = check;
      _busy = check.isActive;
    });
    if (check.isActive) {
      _pollTimer = Timer(
        const Duration(seconds: 1),
        () => _poll(check.id, generation),
      );
    }
  }

  Future<void> _poll(String checkId, int generation) async {
    if (!mounted || generation != _generation) return;
    if (DateTime.now().isAfter(_deadline!)) {
      _failed(
        const FacilityException(
          'The check took too long. Check the laptop camera connection and try again.',
        ),
        generation,
      );
      return;
    }
    try {
      final check = await widget.repository
          .getAppetiteCheck(
            facilityId: widget.facilityId,
            tankId: widget.tankId,
            checkId: checkId,
          )
          .timeout(const Duration(seconds: 10));
      if (!mounted || generation != _generation) return;
      _accept(check, generation);
    } catch (error) {
      _failed(error, generation);
    }
  }

  void _failed(Object error, int generation) {
    if (!mounted || generation != _generation) return;
    _pollTimer?.cancel();
    setState(() {
      _busy = false;
      _error = error is FacilityException
          ? error.message
          : 'Could not check appetite. Check your connection and try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final check = _check;
    final completed =
        check?.status == AppetiteCheckStatus.completed &&
        check?.appetiteResult != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current appetite',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Check before adding food. Keep the camera aimed at this tank for about 10 seconds.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('check-current-appetite-button'),
              onPressed: _busy ? null : _start,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Check current appetite'),
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(
                check?.status == AppetiteCheckStatus.checking
                    ? 'Observing fish movement…'
                    : 'Waiting for the camera process…',
              ),
            ],
            if (completed && !_busy && _error == null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  check!.appetiteResult == AppetiteResult.high
                      ? 'High appetite'
                      : 'Low appetite',
                  key: const Key('current-appetite-label'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              if (check.confidence != null)
                Text(
                  'Model probability: ${(check.confidence! * 100).toStringAsFixed(0)}%',
                ),
              if (check.observedAt != null)
                Text(
                  'Observed: ${check.observedAt!.toLocal().toString().split('.').first}',
                ),
              const SizedBox(height: 8),
              const Text(
                'Research estimate. The current model is not reliable enough for feeding decisions.',
              ),
            ],
            if (check != null &&
                !check.isActive &&
                !completed &&
                _error == null) ...[
              const SizedBox(height: 12),
              Text(
                check.message ??
                    'Appetite is unavailable. Check the camera and try again.',
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
