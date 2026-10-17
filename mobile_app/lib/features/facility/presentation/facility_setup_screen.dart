import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/routing/app_routes.dart';
import '../../auth/presentation/authentication_scope.dart';
import '../domain/facility.dart';
import '../domain/facility_repository.dart';

class FacilitySetupScreen extends StatefulWidget {
  const FacilitySetupScreen({
    required this.repository,
    required this.onCreated,
    this.isFirstFacility = true,
    super.key,
  });

  final FacilityRepository repository;
  final Future<void> Function(Facility) onCreated;
  final bool isFirstFacility;

  @override
  State<FacilitySetupScreen> createState() => _FacilitySetupScreenState();
}

class _FacilitySetupScreenState extends State<FacilitySetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  late Future<List<String>> _timeZones;
  String? _selectedTimeZone;
  String? _requestFingerprint;
  String? _idempotencyKey;
  String? _errorMessage;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _timeZones = widget.repository.listTimeZones();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _retryTimeZones() {
    setState(() {
      _errorMessage = null;
      _timeZones = widget.repository.listTimeZones();
    });
  }

  Future<void> _createFacility() async {
    if (!_formKey.currentState!.validate() || _selectedTimeZone == null) {
      return;
    }

    final name = _nameController.text.trim();
    final fingerprint = '$name\u0000$_selectedTimeZone';
    if (_requestFingerprint != fingerprint) {
      _requestFingerprint = fingerprint;
      _idempotencyKey = _newRequestKey();
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      final facility = await widget.repository.createFacility(
        name: name,
        timeZone: _selectedTimeZone!,
        idempotencyKey: _idempotencyKey!,
      );
      if (mounted) {
        await widget.onCreated(facility);
      }
    } on FacilityException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'The aquarium could not be created. Try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  String _newRequestKey() {
    final random = Random.secure();
    return '${DateTime.now().microsecondsSinceEpoch}-${random.nextInt(1 << 32)}';
  }

  @override
  Widget build(BuildContext context) {
    final authentication = AuthenticationScope.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isFirstFacility ? 'Set up AquaSense' : 'Add aquarium',
        ),
        actions: [
          IconButton(
            tooltip: 'View onboarding again',
            onPressed: () => Navigator.of(context).pushNamed(
              AppRoutes.onboarding,
              arguments: const OnboardingRouteArguments(isReplay: true),
            ),
            icon: const Icon(Icons.help_outline_rounded),
          ),
          if (widget.isFirstFacility)
            IconButton(
              tooltip: 'Sign out',
              onPressed: _isSaving ? null : authentication.signOut,
              icon: const Icon(Icons.logout_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Icon(
                        Icons.waves_rounded,
                        size: 40,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      widget.isFirstFacility
                          ? 'Name your first aquarium'
                          : 'Create another aquarium',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'This creates the workspace where your tanks, workers, '
                      'schedules, and feeding records will live.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _nameController,
                      enabled: !_isSaving,
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: [LengthLimitingTextInputFormatter(120)],
                      decoration: const InputDecoration(
                        labelText: 'Aquarium name',
                        hintText: 'For example, Blue Reef Hatchery',
                        prefixIcon: Icon(Icons.business_rounded),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter an aquarium name.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),
                    FutureBuilder<List<String>>(
                      future: _timeZones,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const _TimeZoneLoadingField();
                        }
                        if (snapshot.hasError || snapshot.data!.isEmpty) {
                          return _TimeZoneErrorField(onRetry: _retryTimeZones);
                        }
                        final zones = snapshot.data!;
                        _selectedTimeZone ??= zones.contains('Asia/Colombo')
                            ? 'Asia/Colombo'
                            : zones.first;
                        return DropdownButtonFormField<String>(
                          value: _selectedTimeZone,
                          isExpanded: true,
                          menuMaxHeight: 340,
                          decoration: const InputDecoration(
                            labelText: 'Facility time zone',
                            prefixIcon: Icon(Icons.schedule_rounded),
                          ),
                          items: zones
                              .map(
                                (zone) => DropdownMenuItem(
                                  value: zone,
                                  child: Text(
                                    zone.replaceAll('_', ' '),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: _isSaving
                              ? null
                              : (value) {
                                  setState(() => _selectedTimeZone = value);
                                },
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Feeding schedules will use this time zone.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 18),
                      _SetupError(message: _errorMessage!),
                    ],
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _createFacility,
                      icon: _isSaving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_forward_rounded),
                      label: Text(
                        _isSaving ? 'Creating aquarium…' : 'Create aquarium',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeZoneLoadingField extends StatelessWidget {
  const _TimeZoneLoadingField();

  @override
  Widget build(BuildContext context) {
    return const InputDecorator(
      decoration: InputDecoration(
        labelText: 'Facility time zone',
        prefixIcon: Icon(Icons.schedule_rounded),
      ),
      child: LinearProgressIndicator(),
    );
  }
}

class _TimeZoneErrorField extends StatelessWidget {
  const _TimeZoneErrorField({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh_rounded),
      label: const Text('Reload time zones'),
    );
  }
}

class _SetupError extends StatelessWidget {
  const _SetupError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(message, style: TextStyle(color: colors.onErrorContainer)),
    );
  }
}
