import 'package:flutter/material.dart';

import '../../facility/domain/facility.dart';
import '../domain/export_advisory.dart';
import '../domain/export_repository.dart';
import 'export_advisory_screen.dart';
import 'export_plan_form_screen.dart';

/// Saved shipment plans for one aquarium, newest first.
class ExportPlansScreen extends StatefulWidget {
  const ExportPlansScreen({
    required this.facility,
    required this.repository,
    super.key,
  });

  final Facility facility;
  final ExportRepository repository;

  @override
  State<ExportPlansScreen> createState() => _ExportPlansScreenState();
}

class _ExportPlansScreenState extends State<ExportPlansScreen> {
  List<ExportAdvisorySummary>? _plans;
  String? _error;
  String? _openingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final plans = await widget.repository.listAdvisories(widget.facility.id);
      if (mounted) setState(() => _plans = plans);
    } on ExportException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Shipment plans could not be loaded.');
      }
    }
  }

  Future<void> _newPlan() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ExportPlanFormScreen(
          facility: widget.facility,
          repository: widget.repository,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _open(ExportAdvisorySummary plan) async {
    if (_openingId != null) return;
    setState(() => _openingId = plan.id);
    try {
      final detail = await widget.repository.getAdvisory(
        facilityId: widget.facility.id,
        advisoryId: plan.id,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ExportAdvisoryScreen(detail: detail),
        ),
      );
    } on ExportException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plans = _plans;
    Widget body;
    if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    } else if (plans == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (plans.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 48,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'No shipment plans yet',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Plan an export to see how many fish to pack per bag, what '
                'to add, how fast oxygen is used, and how many fish may be '
                'lost on the way.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: plans.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final plan = plans[index];
            return Card(
              child: ListTile(
                key: Key('export-plan-${plan.id}'),
                onTap: () => _open(plan),
                leading: _openingId == plan.id
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        plan.feasible
                            ? Icons.inventory_2_outlined
                            : Icons.block_rounded,
                      ),
                title: Text(
                  plan.label ??
                      '${plan.species.label}, '
                          '${plan.durationHours.toStringAsFixed(0)} h',
                ),
                subtitle: Text(_subtitle(plan)),
                trailing: const Icon(Icons.chevron_right_rounded),
              ),
            );
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Export planning')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('export-new-plan-button'),
        onPressed: _newPlan,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Plan a shipment'),
      ),
      body: SafeArea(child: body),
    );
  }

  String _subtitle(ExportAdvisorySummary plan) {
    if (!plan.feasible) return 'Not feasible as planned';
    final parts = <String>[
      if (plan.fishPerBag != null) '${plan.fishPerBag} fish/bag',
      if (plan.bagsNeeded != null) '${plan.bagsNeeded} bags',
      if (plan.survivalPct != null)
        '${plan.survivalPct!.toStringAsFixed(1)}% alive',
    ];
    return parts.join(' · ');
  }
}
