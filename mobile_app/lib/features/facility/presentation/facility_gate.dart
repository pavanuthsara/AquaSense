import 'package:flutter/material.dart';

import '../domain/facility.dart';
import '../domain/facility_repository.dart';
import 'facility_home_screen.dart';
import 'facility_repository_scope.dart';
import 'facility_setup_screen.dart';

class FacilityGate extends StatefulWidget {
  const FacilityGate({super.key});

  @override
  State<FacilityGate> createState() => _FacilityGateState();
}

class _FacilityGateState extends State<FacilityGate> {
  FacilityRepository? _repository;
  Future<List<Facility>>? _facilities;
  Facility? _selectedFacility;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repository = FacilityRepositoryScope.of(context);
    if (_repository != repository) {
      _repository = repository;
      _facilities = repository.listFacilities();
      _selectedFacility = null;
    }
  }

  void _retry() {
    setState(() {
      _facilities = _repository!.listFacilities();
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedFacility = _selectedFacility;
    if (selectedFacility != null) {
      return FacilityHomeScreen(facility: selectedFacility);
    }

    return FutureBuilder<List<Facility>>(
      future: _facilities,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _FacilityLoadingScreen();
        }
        if (snapshot.hasError) {
          final error = snapshot.error;
          return _FacilityLoadErrorScreen(
            message: error is FacilityException
                ? error.message
                : 'Your aquariums could not be loaded.',
            onRetry: _retry,
          );
        }

        final facilities = snapshot.data ?? const <Facility>[];
        if (facilities.isEmpty) {
          return FacilitySetupScreen(
            repository: _repository!,
            onCreated: (facility) {
              setState(() => _selectedFacility = facility);
            },
          );
        }
        return FacilityHomeScreen(facility: facilities.first);
      },
    );
  }
}

class _FacilityLoadingScreen extends StatelessWidget {
  const _FacilityLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.water_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 18),
            const Text('Loading your aquariums'),
            const SizedBox(height: 18),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class _FacilityLoadErrorScreen extends StatelessWidget {
  const _FacilityLoadErrorScreen({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off_rounded,
                  size: 52,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 18),
                Text(
                  'Could not load aquariums',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
