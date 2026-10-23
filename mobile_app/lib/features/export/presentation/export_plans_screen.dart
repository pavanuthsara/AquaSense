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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  Icons.inventory_2_outlined,
                  size: 36,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'No shipment plans yet',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Plan an export to find out how many fish to pack per bag, '
                'what to add to the water, and how many fish may be lost on '
                'the way.',
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          itemCount: plans.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final plan = plans[index];
            return _PlanCard(
              key: Key('export-plan-${plan.id}'),
              plan: plan,
              opening: _openingId == plan.id,
              onTap: () => _open(plan),
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
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.opening,
    required this.onTap,
    super.key,
  });

  final ExportAdvisorySummary plan;
  final bool opening;
  final VoidCallback onTap;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final created = plan.createdAt.toLocal();
    final ok = plan.feasible && plan.meetsTarget;
    final details =
        '${plan.species.label} · ${plan.durationHours.toStringAsFixed(0)} h '
        'trip · ${created.day} ${_months[created.month - 1]} ${created.year}';
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: ok
                    ? scheme.primaryContainer
                    : scheme.errorContainer,
                foregroundColor: ok
                    ? scheme.onPrimaryContainer
                    : scheme.onErrorContainer,
                child: opening
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        !plan.feasible
                            ? Icons.block_rounded
                            : plan.meetsTarget
                            ? Icons.inventory_2_outlined
                            : Icons.warning_amber_rounded,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.label ??
                          '${plan.species.label}, '
                              '${plan.durationHours.toStringAsFixed(0)} h',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      details,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (!plan.feasible)
                      Text(
                        'Not safe as planned. Open to see what to change.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (plan.mode != PlanningMode.suggest)
                            _Fact(
                              plan.meetsTarget
                                  ? '${plan.mode.label} · safe'
                                  : '${plan.mode.label} · NOT safe',
                              danger: !plan.meetsTarget,
                            ),
                          if (plan.fishPerBag != null)
                            _Fact('${plan.fishPerBag} fish/bag'),
                          if (plan.bagsNeeded != null)
                            _Fact('${plan.bagsNeeded} bags'),
                          if (plan.survivalPct != null)
                            _Fact(
                              '${plan.survivalPct!.toStringAsFixed(1)}% alive',
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.text, {this.danger = false});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: danger ? scheme.errorContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: danger ? scheme.onErrorContainer : null,
        ),
      ),
    );
  }
}
