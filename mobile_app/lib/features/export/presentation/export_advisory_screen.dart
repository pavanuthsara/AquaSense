import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/export_advisory.dart';
import 'timeline_chart.dart';

/// The full transit advisory: packing plan, what to add and how much, how
/// the oxygen is used, how fast fish may die, water chemistry, temperature
/// limits and how to unpack.
class ExportAdvisoryScreen extends StatelessWidget {
  const ExportAdvisoryScreen({required this.detail, super.key});

  final ExportAdvisoryDetail detail;

  @override
  Widget build(BuildContext context) {
    final advisory = detail.advisory;
    final title = detail.label ?? 'Shipment plan';
    if (!advisory.feasible) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _Banner(
              icon: Icons.block_rounded,
              text: advisory.recommendation.summary,
              danger: true,
            ),
            ..._warnings(advisory),
          ],
        ),
      );
    }
    return DefaultTabController(
      length: 7,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          bottom: const TabBar(
            key: Key('export-advisory-tabs'),
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Plan'),
              Tab(text: 'Oxygen'),
              Tab(text: 'Survival'),
              Tab(text: 'Water'),
              Tab(text: 'Temperature'),
              Tab(text: 'Unpacking'),
              Tab(text: 'Options'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _PlanTab(advisory: advisory),
            _OxygenTab(advisory: advisory),
            _SurvivalTab(advisory: advisory),
            _WaterTab(advisory: advisory),
            _TemperatureTab(advisory: advisory),
            _UnpackingTab(advisory: advisory),
            _OptionsTab(advisory: advisory),
          ],
        ),
      ),
    );
  }
}

List<Widget> _warnings(TransitAdvisory advisory) => [
  for (final warning in advisory.warnings) ...[
    const SizedBox(height: 12),
    _Banner(icon: Icons.info_outline_rounded, text: warning),
  ],
];

class _TabBody extends StatelessWidget {
  const _TabBody({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: children,
    );
  }
}

class _PlanTab extends StatelessWidget {
  const _PlanTab({required this.advisory});

  final TransitAdvisory advisory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rec = advisory.recommendation;
    final mortality = advisory.mortality;
    final saved =
        (rec.bagsNeededWithoutChemicals != null && rec.bagsNeeded != null)
        ? rec.bagsNeededWithoutChemicals! - rec.bagsNeeded!
        : null;
    return _TabBody(
      children: [
        _Banner(
          key: const Key('export-plan-summary'),
          icon: Icons.inventory_2_outlined,
          text: rec.summary,
          positive: true,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _StatTile(
              label: 'Fish per bag',
              value: '${rec.fishPerBag ?? '—'}',
              note: rec.densityGPerL == null
                  ? null
                  : '${rec.densityGPerL!.toStringAsFixed(0)} g/L',
            ),
            if (rec.bagsNeeded != null)
              _StatTile(
                label: 'Bags needed',
                value: '${rec.bagsNeeded}',
                note: saved != null && saved > 0
                    ? '$saved fewer than without chemicals'
                    : null,
              ),
            if (mortality != null) ...[
              _StatTile(
                label: 'Alive after unpacking',
                value:
                    '${mortality.survivalAfterUnpackingPct.toStringAsFixed(1)}%',
                note:
                    'worst ${mortality.worstSurvivalAfterUnpackingPct.toStringAsFixed(1)}%',
              ),
              _StatTile(
                label: 'Expected losses per bag',
                value: mortality.expectedDeadPerBag.toStringAsFixed(1),
                note:
                    'worst ${mortality.expectedDeadPerBagWorst.toStringAsFixed(1)}',
              ),
            ],
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'What to add — and how much',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        for (final dose in rec.doses) _DoseCard(dose: dose),
        if (rec.fishPerBagWithoutChemicals != null) ...[
          const SizedBox(height: 4),
          Text(
            'Without any chemicals: ${rec.fishPerBagWithoutChemicals} fish per bag'
            '${rec.bagsNeededWithoutChemicals == null ? '' : ' (${rec.bagsNeededWithoutChemicals} bags)'}.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
        if (rec.notSimulated.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Other options (evidence only, not simulated)',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          for (final option in rec.notSimulated)
            _DoseCard(dose: option, muted: true),
        ],
        ..._warnings(advisory),
      ],
    );
  }
}

class _DoseCard extends StatelessWidget {
  const _DoseCard({required this.dose, this.muted = false});

  final AddonDose dose;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: muted ? theme.colorScheme.surfaceContainerLow : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dose.name,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              dose.perBag == null
                  ? dose.amount
                  : '${dose.amount}  →  ${dose.perBag}',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text('Why: ${dose.evidence}', style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              'Caution: ${dose.caution}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OxygenTab extends StatelessWidget {
  const _OxygenTab({required this.advisory});

  final TransitAdvisory advisory;

  @override
  Widget build(BuildContext context) {
    final oxygen = advisory.oxygen;
    final timeline = advisory.timeline;
    if (oxygen == null || timeline == null) return const _Missing();
    final critical = oxygen.hoursToCriticalDo;
    return _TabBody(
      children: [
        _Banner(icon: Icons.air_rounded, text: oxygen.explanation),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _StatTile(
              label: 'O₂ use, first 6 h',
              value: '${oxygen.useRateFirst6h.toStringAsFixed(2)} mg/h',
              note: 'handling stress',
            ),
            _StatTile(
              label: 'O₂ use, average',
              value: '${oxygen.useRateAverage.toStringAsFixed(2)} mg/h',
              note: '${oxygen.usePerFish.toStringAsFixed(3)} mg per fish',
            ),
            _StatTile(
              label: 'O₂ gas left at arrival',
              value: '${oxygen.gasLeftPct.toStringAsFixed(0)}%',
            ),
            _StatTile(
              label: 'Water O₂ below critical',
              value: critical == null
                  ? 'Never'
                  : 'Hour ${critical.toStringAsFixed(0)}',
              note: 'critical = ${oxygen.doCritical.toStringAsFixed(0)} mg/L',
            ),
          ],
        ),
        const SizedBox(height: 24),
        TimelineChart(
          title: 'Oxygen dissolved in the water',
          unit: 'mg/L',
          hours: timeline.median.hours,
          median: timeline.median.doMgL,
          worst: timeline.worst.doMgL,
          worstHours: timeline.worst.hours,
          threshold: oxygen.doCritical,
          thresholdLabel: 'Critical level',
          openedAtHour: timeline.median.openedAtHour,
          minY: 0,
        ),
        const SizedBox(height: 24),
        TimelineChart(
          title: 'Oxygen gas left in the bag',
          unit: '% of packed',
          hours: timeline.median.hours,
          median: timeline.median.gasO2Pct,
          worst: timeline.worst.gasO2Pct,
          worstHours: timeline.worst.hours,
          minY: 0,
          maxY: 105,
          decimals: 0,
        ),
      ],
    );
  }
}

class _SurvivalTab extends StatelessWidget {
  const _SurvivalTab({required this.advisory});

  final TransitAdvisory advisory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mortality = advisory.mortality;
    final timeline = advisory.timeline;
    if (mortality == null || timeline == null) return const _Missing();
    final lowest = [
      ...timeline.worst.alivePct.whereType<double>(),
      advisory.targetSurvivalPct,
    ].reduce(math.min);
    return _TabBody(
      children: [
        _Banner(icon: Icons.timeline_rounded, text: mortality.explanation),
        const SizedBox(height: 20),
        TimelineChart(
          title: 'Fish alive',
          unit: '%',
          hours: timeline.median.hours,
          median: timeline.median.alivePct,
          worst: timeline.worst.alivePct,
          worstHours: timeline.worst.hours,
          threshold: advisory.targetSurvivalPct,
          thresholdLabel: 'Target',
          openedAtHour: timeline.median.openedAtHour,
          minY: math.max(0.0, lowest - 3),
          maxY: 100.5,
        ),
        const SizedBox(height: 24),
        Text('Alive at each stage', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Table(
          key: const Key('export-survival-table'),
          border: TableBorder(
            horizontalInside: BorderSide(
              color: theme.colorScheme.outlineVariant,
            ),
          ),
          columnWidths: const {0: FlexColumnWidth(1.2)},
          children: [
            _row(theme, ['Hour', 'Median', 'Worst case'], header: true),
            for (final checkpoint in mortality.checkpoints)
              _row(theme, [
                checkpoint.hour.toStringAsFixed(0),
                '${checkpoint.median.toStringAsFixed(1)}%',
                '${checkpoint.worst.toStringAsFixed(1)}%',
              ]),
          ],
        ),
        const SizedBox(height: 24),
        Text('What causes the deaths', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final entry in mortality.causeSharePct.entries) ...[
          Row(
            children: [
              Expanded(child: Text(entry.key)),
              Text('${entry.value.toStringAsFixed(0)}%'),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: (entry.value / 100).clamp(0.0, 1.0).toDouble(),
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  TableRow _row(ThemeData theme, List<String> cells, {bool header = false}) {
    return TableRow(
      children: [
        for (final cell in cells)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              cell,
              style: header
                  ? theme.textTheme.labelLarge
                  : theme.textTheme.bodyMedium,
            ),
          ),
      ],
    );
  }
}

class _WaterTab extends StatelessWidget {
  const _WaterTab({required this.advisory});

  final TransitAdvisory advisory;

  @override
  Widget build(BuildContext context) {
    final chemistry = advisory.chemistry;
    final timeline = advisory.timeline;
    if (chemistry == null || timeline == null) return const _Missing();
    final opened = timeline.median.openedAtHour;
    return _TabBody(
      children: [
        _Banner(icon: Icons.science_outlined, text: chemistry.explanation),
        const SizedBox(height: 20),
        TimelineChart(
          title: 'Carbon dioxide (CO₂)',
          unit: 'mg/L',
          hours: timeline.median.hours,
          median: timeline.median.co2MgL,
          worst: timeline.worst.co2MgL,
          worstHours: timeline.worst.hours,
          threshold: 20,
          thresholdLabel: 'Harmful above',
          openedAtHour: opened,
          minY: 0,
        ),
        const SizedBox(height: 24),
        TimelineChart(
          title: 'pH',
          unit: '',
          hours: timeline.median.hours,
          median: timeline.median.ph,
          worst: timeline.worst.ph,
          worstHours: timeline.worst.hours,
          openedAtHour: opened,
          decimals: 2,
        ),
        const SizedBox(height: 24),
        TimelineChart(
          title: 'Toxic ammonia (NH₃)',
          unit: 'mg/L',
          hours: timeline.median.hours,
          median: timeline.median.nh3MgL,
          worst: timeline.worst.nh3MgL,
          worstHours: timeline.worst.hours,
          threshold: 0.02,
          thresholdLabel: 'Safe limit',
          openedAtHour: opened,
          minY: 0,
          decimals: 3,
        ),
        const SizedBox(height: 24),
        TimelineChart(
          title: 'Total ammonia',
          unit: 'mg/L',
          hours: timeline.median.hours,
          median: timeline.median.tanMgL,
          worst: timeline.worst.tanMgL,
          worstHours: timeline.worst.hours,
          openedAtHour: opened,
          minY: 0,
          decimals: 2,
        ),
      ],
    );
  }
}

class _TemperatureTab extends StatelessWidget {
  const _TemperatureTab({required this.advisory});

  final TransitAdvisory advisory;

  @override
  Widget build(BuildContext context) {
    final temperature = advisory.temperature;
    final timeline = advisory.timeline;
    if (temperature == null || timeline == null) return const _Missing();
    final band = advisory.survivalBand;
    return _TabBody(
      children: [
        _Banner(icon: Icons.thermostat_rounded, text: temperature.advice),
        if (band != null) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _StatTile(
                label: 'Worst journey',
                value: '${band.min.toStringAsFixed(1)}%',
              ),
              _StatTile(
                label: '9 in 10 journeys above',
                value: '${band.p10.toStringAsFixed(1)}%',
              ),
              _StatTile(
                label: 'Typical journey',
                value: '${band.median.toStringAsFixed(1)}%',
              ),
              _StatTile(
                label: 'Best journey',
                value: '${band.max.toStringAsFixed(1)}%',
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        TimelineChart(
          title: 'Fish alive after unpacking vs temperature (this plan)',
          unit: '% alive',
          xLabel: '°C',
          hours: [for (final point in temperature.curve) point.tempC],
          median: [for (final point in temperature.curve) point.survivalPct],
          threshold: advisory.targetSurvivalPct,
          thresholdLabel: 'Target',
          minY: 0,
          maxY: 100.5,
        ),
        const SizedBox(height: 24),
        TimelineChart(
          title: 'Temperature in the journeys simulated',
          unit: '°C',
          hours: timeline.median.hours,
          median: timeline.median.tempC,
          worst: timeline.worst.tempC,
          worstHours: timeline.worst.hours,
          openedAtHour: timeline.median.openedAtHour,
        ),
      ],
    );
  }
}

class _UnpackingTab extends StatelessWidget {
  const _UnpackingTab({required this.advisory});

  final TransitAdvisory advisory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unpacking = advisory.unpacking;
    final timeline = advisory.timeline;
    if (unpacking == null || timeline == null) return const _Missing();
    return _TabBody(
      children: [
        _Banner(
          icon: unpacking.danger
              ? Icons.warning_amber_rounded
              : Icons.check_circle_outline_rounded,
          text: unpacking.explanation,
          danger: unpacking.danger,
        ),
        const SizedBox(height: 20),
        TimelineChart(
          title: 'Toxic ammonia before and after opening',
          unit: 'mg/L',
          hours: timeline.median.hours,
          median: timeline.median.nh3MgL,
          worst: timeline.worst.nh3MgL,
          worstHours: timeline.worst.hours,
          threshold: 0.02,
          thresholdLabel: 'Safe limit',
          openedAtHour: timeline.median.openedAtHour,
          minY: 0,
          decimals: 3,
        ),
        const SizedBox(height: 24),
        Text('How to unpack', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (var i = 0; i < unpacking.steps.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
            title: Text(unpacking.steps[i]),
          ),
      ],
    );
  }
}

class _OptionsTab extends StatelessWidget {
  const _OptionsTab({required this.advisory});

  final TransitAdvisory advisory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = [...advisory.options]
      ..sort((a, b) => b.maxFishPerBag.compareTo(a.maxFishPerBag));
    final most = options.isEmpty ? 1 : math.max(options.first.maxFishPerBag, 1);
    return _TabBody(
      children: [
        Text(
          'Most fish per bag that stay above the target at the hot end of '
          'the temperature range. Add-ons are only recommended when they '
          'gain at least 5 %.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        for (final option in options) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  option.label,
                  style: option.recommended
                      ? theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        )
                      : theme.textTheme.bodyMedium,
                ),
              ),
              if (option.recommended)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Chip(
                    label: Text('Recommended'),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              Text(
                '${option.maxFishPerBag}',
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: option.maxFishPerBag / most,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
            color: option.recommended
                ? ExportChartColors.worst
                : ExportChartColors.median,
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.note});

  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 156,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              const SizedBox(height: 6),
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (note != null) ...[
                const SizedBox(height: 2),
                Text(
                  note!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    this.danger = false,
    this.positive = false,
    super.key,
  });

  final IconData icon;
  final String text;
  final bool danger;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = danger
        ? scheme.errorContainer
        : positive
        ? scheme.primaryContainer
        : scheme.surfaceContainerHigh;
    final foreground = danger
        ? scheme.onErrorContainer
        : positive
        ? scheme.onPrimaryContainer
        : scheme.onSurface;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foreground),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: TextStyle(color: foreground, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _Missing extends StatelessWidget {
  const _Missing();

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Not available for this plan.'));
  }
}
