import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/export_advisory.dart';
import 'timeline_chart.dart';

/// The full transit advisory. The overview answers "how do I pack and is it
/// safe"; the other tabs explain the journey, unpacking and alternatives.
class ExportAdvisoryScreen extends StatefulWidget {
  const ExportAdvisoryScreen({required this.detail, super.key});

  final ExportAdvisoryDetail detail;

  @override
  State<ExportAdvisoryScreen> createState() => _ExportAdvisoryScreenState();
}

enum _JourneyMetric {
  survival('Survival', Icons.favorite_outline_rounded),
  oxygen('Oxygen', Icons.air_rounded),
  water('Water quality', Icons.science_outlined),
  temperature('Temperature', Icons.thermostat_rounded);

  const _JourneyMetric(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _ExportAdvisoryScreenState extends State<ExportAdvisoryScreen>
    with SingleTickerProviderStateMixin {
  static const _journeyTab = 1;
  static const _unpackingTab = 2;

  late final _tabs = TabController(length: 4, vsync: this);
  var _metric = _JourneyMetric.survival;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _showJourney(_JourneyMetric metric) {
    setState(() => _metric = metric);
    _tabs.animateTo(_journeyTab);
  }

  @override
  Widget build(BuildContext context) {
    final advisory = widget.detail.advisory;
    final title = widget.detail.label ?? 'Shipment plan';
    if (!advisory.feasible) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: _InfeasibleBody(advisory: advisory),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        bottom: TabBar(
          key: const Key('export-advisory-tabs'),
          controller: _tabs,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Journey'),
            Tab(text: 'Unpacking'),
            Tab(text: 'Options'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _OverviewTab(
            advisory: advisory,
            onShowJourney: _showJourney,
            onShowUnpacking: () => _tabs.animateTo(_unpackingTab),
          ),
          _JourneyTab(
            advisory: advisory,
            metric: _metric,
            onMetricChanged: (metric) => setState(() => _metric = metric),
          ),
          _UnpackingTab(advisory: advisory),
          _OptionsTab(advisory: advisory),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overview

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.advisory,
    required this.onShowJourney,
    required this.onShowUnpacking,
  });

  final TransitAdvisory advisory;
  final ValueChanged<_JourneyMetric> onShowJourney;
  final VoidCallback onShowUnpacking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rec = advisory.recommendation;
    final unpacking = advisory.unpacking;
    return _TabBody(
      children: [
        _VerdictCard(advisory: advisory),
        if (unpacking != null && unpacking.danger) ...[
          const SizedBox(height: 12),
          _Banner(
            icon: Icons.warning_amber_rounded,
            title: 'Take care when opening the bags',
            text: unpacking.explanation,
            tone: _Tone.danger,
            action: TextButton(
              onPressed: onShowUnpacking,
              child: const Text('How to unpack safely'),
            ),
          ),
        ],
        _SectionTitle(
          advisory.mode == PlanningMode.check
              ? 'What is in your bag'
              : 'Before you pack',
        ),
        if (rec.doses.isEmpty)
          Text(
            'Nothing needs to be added to the bags.',
            style: theme.textTheme.bodyMedium,
          ),
        for (var i = 0; i < rec.doses.length; i++)
          _DoseCard(dose: rec.doses[i], step: i + 1),
        if (rec.fishPerBagWithoutChemicals != null) _ChemicalsGain(rec: rec),
        const _SectionTitle('At a glance'),
        _GlanceCard(advisory: advisory, onShowJourney: onShowJourney),
        if (rec.notSimulated.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ExpandableCard(
            icon: Icons.menu_book_outlined,
            title: 'Other add-ons to consider',
            subtitle: 'Backed by studies, but not simulated in this plan',
            children: [
              for (final option in rec.notSimulated) _DoseDetails(dose: option),
            ],
          ),
        ],
        if (advisory.warnings.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ExpandableCard(
            key: const Key('export-advisory-notes'),
            icon: Icons.info_outline_rounded,
            title: 'About this estimate',
            subtitle:
                '${advisory.warnings.length} '
                '${advisory.warnings.length == 1 ? 'note' : 'notes'} on '
                'accuracy',
            children: [
              for (final warning in advisory.warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 6, right: 10),
                        child: Icon(Icons.circle, size: 6),
                      ),
                      Expanded(
                        child: Text(
                          warning,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
        if (advisory.method != null) ...[
          const SizedBox(height: 12),
          _MethodCard(method: advisory.method!),
        ],
      ],
    );
  }
}

/// How the numbers are worked out, kept out of the advice itself.
class _MethodCard extends StatelessWidget {
  const _MethodCard({required this.method});

  final MethodSection method;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium?.copyWith(height: 1.4);
    final heading = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w700,
    );
    return _ExpandableCard(
      key: const Key('export-advisory-method'),
      icon: Icons.calculate_outlined,
      title: 'How we work this out',
      subtitle: 'The method, how sure we are, and the studies behind it',
      children: [
        for (var i = 0; i < method.steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 11,
                  child: Text(
                    '${i + 1}',
                    style: theme.textTheme.labelSmall,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(method.steps[i], style: body)),
              ],
            ),
          ),
        if (method.confidence.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('How sure we are', style: heading),
          const SizedBox(height: 6),
          for (final note in method.confidence)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('• $note', style: body),
            ),
        ],
        if (method.sources.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Studies used', style: heading),
          const SizedBox(height: 6),
          for (final source in method.sources)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.title,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    source.usedFor,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// The answer in one card: fish per bag, bags and expected survival.
class _VerdictCard extends StatelessWidget {
  const _VerdictCard({required this.advisory});

  final TransitAdvisory advisory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rec = advisory.recommendation;
    final mortality = advisory.mortality;
    final verdict = advisory.verdict;
    final mode = advisory.mode;
    final meetsTarget =
        verdict?.meetsTarget ??
        (mortality == null ||
            mortality.worstSurvivalAfterUnpackingPct >=
                advisory.targetSurvivalPct);
    final target = _pct(advisory.targetSurvivalPct);
    final unsafe = mode != PlanningMode.suggest && !meetsTarget;
    final onCard = unsafe ? scheme.onErrorContainer : scheme.onPrimaryContainer;
    return Container(
      key: const Key('export-plan-summary'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: unsafe ? scheme.errorContainer : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Pill(
            icon: meetsTarget
                ? Icons.check_circle_rounded
                : Icons.error_outline_rounded,
            label: meetsTarget
                ? 'Meets your $target alive target'
                : mode == PlanningMode.suggest
                ? 'Worst case is below your $target target'
                : 'Not safe: below your $target target',
            tone: meetsTarget
                ? _Tone.ok
                : unsafe
                ? _Tone.danger
                : _Tone.warn,
          ),
          if (mode != PlanningMode.suggest && verdict != null) ...[
            const SizedBox(height: 12),
            Text(
              verdict.message,
              key: const Key('export-plan-verdict'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: onCard,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (rec.fishPerBag == null)
            Text(
              rec.summary,
              style: theme.textTheme.titleMedium?.copyWith(color: onCard),
            )
          else ...[
            Text(
              switch (mode) {
                PlanningMode.suggest => 'Pack',
                PlanningMode.fixedBags => 'Your bags hold',
                PlanningMode.check => 'You pack',
              },
              style: theme.textTheme.titleMedium?.copyWith(color: onCard),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${rec.fishPerBag}',
                  key: const Key('export-fish-per-bag'),
                  style: theme.textTheme.displayMedium?.copyWith(
                    color: onCard,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'fish per bag',
                    style: theme.textTheme.titleLarge?.copyWith(color: onCard),
                  ),
                ),
              ],
            ),
            if (rec.planLabel != null) ...[
              const SizedBox(height: 4),
              Text(
                'with ${rec.planLabel}'
                '${rec.densityGPerL == null ? '' : ' · ${rec.densityGPerL!.toStringAsFixed(0)} g of fish per litre'}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: onCard.withValues(alpha: 0.8),
                ),
              ),
            ],
          ],
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(16),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  if (rec.bagsNeeded != null)
                    _VerdictFigure(value: '${rec.bagsNeeded}', label: 'bags'),
                  if (mortality != null) ...[
                    if (rec.bagsNeeded != null) const _FigureDivider(),
                    _VerdictFigure(
                      value: _pct(mortality.survivalAfterUnpackingPct),
                      label: 'alive',
                      note:
                          'worst ${_pct(mortality.worstSurvivalAfterUnpackingPct)}',
                    ),
                    const _FigureDivider(),
                    _VerdictFigure(
                      value: mortality.expectedDeadPerBag.toStringAsFixed(1),
                      label: 'lost per bag',
                      note:
                          'worst ${mortality.expectedDeadPerBagWorst.toStringAsFixed(1)}',
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (mode != PlanningMode.suggest &&
              verdict != null &&
              verdict.recommendedFishPerBag != null) ...[
            const SizedBox(height: 12),
            Text(
              'Recommended plan: ${verdict.recommendedFishPerBag} fish per bag'
              '${verdict.recommendedPlanLabel == null ? '' : ' with ${verdict.recommendedPlanLabel}'}'
              '${verdict.recommendedBags == null ? '' : ' → ${verdict.recommendedBags} bags'}.',
              key: const Key('export-recommended-comparison'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: onCard.withValues(alpha: 0.85),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VerdictFigure extends StatelessWidget {
  const _VerdictFigure({required this.value, required this.label, this.note});

  final String value;
  final String label;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(label, style: theme.textTheme.bodySmall),
          if (note != null)
            Text(
              note!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _FigureDivider extends StatelessWidget {
  const _FigureDivider();

  @override
  Widget build(BuildContext context) {
    return VerticalDivider(
      width: 1,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

class _ChemicalsGain extends StatelessWidget {
  const _ChemicalsGain({required this.rec});

  final PackingRecommendation rec;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final savedBags =
        (rec.bagsNeededWithoutChemicals != null && rec.bagsNeeded != null)
        ? rec.bagsNeededWithoutChemicals! - rec.bagsNeeded!
        : null;
    final withoutBags = rec.bagsNeededWithoutChemicals == null
        ? ''
        : ' (${rec.bagsNeededWithoutChemicals} bags)';
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.savings_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Without chemicals you could pack '
              '${rec.fishPerBagWithoutChemicals} fish per bag$withoutBags.'
              '${savedBags != null && savedBags > 0 ? ' This plan saves $savedBags ${savedBags == 1 ? 'bag' : 'bags'}.' : ''}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoseCard extends StatelessWidget {
  const _DoseCard({required this.dose, required this.step});

  final AddonDose dose;
  final int step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            child: Text('$step', style: const TextStyle(fontSize: 14)),
          ),
          title: Text(
            dose.name,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: dose.perBag ?? dose.amount,
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (dose.perBag != null)
                    TextSpan(text: '  ·  ${dose.amount}'),
                ],
              ),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          children: [_DoseDetails(dose: dose, showName: false)],
        ),
      ),
    );
  }
}

/// Why an add-on helps and what to watch out for.
class _DoseDetails extends StatelessWidget {
  const _DoseDetails({required this.dose, this.showName = true});

  final AddonDose dose;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showName) ...[
            Text(
              '${dose.name} · ${dose.amount}',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
          ],
          _LabeledNote(
            icon: Icons.lightbulb_outline_rounded,
            label: 'Why',
            text: dose.why,
          ),
          if (dose.caution.isNotEmpty) ...[
            const SizedBox(height: 8),
            _LabeledNote(
              icon: Icons.report_gmailerrorred_rounded,
              label: 'Take care',
              text: dose.caution,
              color: _Tone.warn.color,
            ),
          ],
        ],
      ),
    );
  }
}

class _LabeledNote extends StatelessWidget {
  const _LabeledNote({
    required this.icon,
    required this.label,
    required this.text,
    this.color,
  });

  final IconData icon;
  final String label;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$label: ',
                  style: TextStyle(color: accent, fontWeight: FontWeight.w700),
                ),
                TextSpan(text: text),
              ],
            ),
            style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
          ),
        ),
      ],
    );
  }
}

/// One line per risk, coloured by how serious it is. Tapping opens the
/// matching chart in the Journey tab.
class _GlanceCard extends StatelessWidget {
  const _GlanceCard({required this.advisory, required this.onShowJourney});

  final TransitAdvisory advisory;
  final ValueChanged<_JourneyMetric> onShowJourney;

  @override
  Widget build(BuildContext context) {
    final oxygen = advisory.oxygen;
    final mortality = advisory.mortality;
    final chemistry = advisory.chemistry;
    final temperature = advisory.temperature;
    final rows = <Widget>[
      if (mortality != null)
        _GlanceRow(
          tone:
              mortality.worstSurvivalAfterUnpackingPct >=
                  advisory.targetSurvivalPct
              ? _Tone.ok
              : _Tone.warn,
          title: mortality.hoursToFirstLoss == null
              ? 'No losses expected'
              : 'Losses start around hour '
                    '${mortality.hoursToFirstLoss!.toStringAsFixed(0)}',
          detail: mortality.mainCause.isEmpty
              ? null
              : 'Main cause: ${mortality.mainCause}',
          onTap: () => onShowJourney(_JourneyMetric.survival),
        ),
      if (oxygen != null)
        _GlanceRow(
          tone: oxygen.hoursToCriticalDo != null
              ? _Tone.danger
              : oxygen.hoursToCriticalDoWorst != null
              ? _Tone.warn
              : _Tone.ok,
          title: oxygen.hoursToCriticalDo != null
              ? 'Oxygen runs low at hour '
                    '${oxygen.hoursToCriticalDo!.toStringAsFixed(0)}'
              : oxygen.hoursToCriticalDoWorst != null
              ? 'Oxygen runs low in the worst case'
              : 'Enough oxygen for the whole trip',
          detail:
              '${oxygen.gasLeftPct.toStringAsFixed(0)} % of the oxygen gas '
              'is left at arrival',
          onTap: () => onShowJourney(_JourneyMetric.oxygen),
        ),
      if (chemistry != null)
        _GlanceRow(
          tone: chemistry.maxCo2 > _co2Harmful ? _Tone.warn : _Tone.ok,
          title: chemistry.maxCo2 > _co2Harmful
              ? 'CO₂ builds up to ${chemistry.maxCo2.toStringAsFixed(0)} mg/L'
              : 'CO₂ stays below the harmful level',
          detail:
              'Harmful above ${_co2Harmful.toStringAsFixed(0)} mg/L · pH '
              'falls to ${chemistry.finalPh.toStringAsFixed(1)}',
          onTap: () => onShowJourney(_JourneyMetric.water),
        ),
      if (temperature != null)
        _GlanceRow(
          tone:
              temperature.maxSafeTempC != null &&
                  temperature.maxSafeTempC! < advisory.tempHighC
              ? _Tone.danger
              : _Tone.ok,
          title:
              temperature.maxSafeTempC != null &&
                  temperature.maxSafeTempC! < advisory.tempHighC
              ? 'Too warm above ${temperature.maxSafeTempC!.toStringAsFixed(0)} °C'
              : 'Temperature stays in the safe range',
          detail: temperature.advice,
          onTap: () => onShowJourney(_JourneyMetric.temperature),
        ),
    ];
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 52),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _GlanceRow extends StatelessWidget {
  const _GlanceRow({
    required this.tone,
    required this.title,
    required this.onTap,
    this.detail,
  });

  final _Tone tone;
  final String title;
  final String? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(tone.icon, color: tone.color, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (detail != null)
                    Text(
                      detail!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfeasibleBody extends StatelessWidget {
  const _InfeasibleBody({required this.advisory});

  final TransitAdvisory advisory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const tips = [
      'Shorten the journey or pick a faster route.',
      'Keep the bags cooler, for example in an insulated box.',
      'Use more water or oxygen per bag.',
      'Allow anaesthetics or zeolite if the importing country permits them.',
      'Lower the survival target, if your buyer agrees.',
    ];
    return _TabBody(
      children: [
        _Banner(
          icon: Icons.block_rounded,
          title: 'This shipment is not safe as planned',
          text: advisory.recommendation.summary,
          tone: _Tone.danger,
        ),
        const _SectionTitle('What you can change'),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                for (final tip in tips)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.tips_and_updates_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(tip, style: theme.textTheme.bodyMedium),
                  ),
              ],
            ),
          ),
        ),
        for (final warning in advisory.warnings) ...[
          const SizedBox(height: 12),
          _Banner(icon: Icons.info_outline_rounded, text: warning),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Journey

const _co2Harmful = 20.0;
const _nh3Safe = 0.02;

class _JourneyTab extends StatelessWidget {
  const _JourneyTab({
    required this.advisory,
    required this.metric,
    required this.onMetricChanged,
  });

  final TransitAdvisory advisory;
  final _JourneyMetric metric;
  final ValueChanged<_JourneyMetric> onMetricChanged;

  @override
  Widget build(BuildContext context) {
    final timeline = advisory.timeline;
    if (timeline == null) return const _Missing();
    final content = switch (metric) {
      _JourneyMetric.survival => _survival(context, timeline),
      _JourneyMetric.oxygen => _oxygen(timeline),
      _JourneyMetric.water => _water(timeline),
      _JourneyMetric.temperature => _temperature(timeline),
    };
    return Column(
      children: [
        SizedBox(
          height: 60,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            children: [
              for (final option in _JourneyMetric.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: Key('export-journey-${option.name}'),
                    avatar: Icon(option.icon, size: 18),
                    label: Text(option.label),
                    selected: option == metric,
                    showCheckmark: false,
                    onSelected: (_) => onMetricChanged(option),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _TabBody(
            key: PageStorageKey('export-journey-${metric.name}'),
            top: 8,
            children: content,
          ),
        ),
      ],
    );
  }

  List<Widget> _survival(BuildContext context, AdvisoryTimeline timeline) {
    final theme = Theme.of(context);
    final mortality = advisory.mortality;
    if (mortality == null) return const [_Missing()];
    final lowest = [
      ...timeline.worst.alivePct.whereType<double>(),
      advisory.targetSurvivalPct,
    ].reduce(math.min);
    final causes = mortality.causeSharePct.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      _Banner(icon: Icons.timeline_rounded, text: mortality.explanation),
      const SizedBox(height: 12),
      _ChartCard(
        child: TimelineChart(
          title: 'Fish alive',
          unit: '%',
          hours: timeline.median.hours,
          median: timeline.median.alivePct,
          worst: timeline.worst.alivePct,
          worstHours: timeline.worst.hours,
          threshold: advisory.targetSurvivalPct,
          thresholdLabel: 'Your target',
          openedAtHour: timeline.median.openedAtHour,
          minY: math.max(0.0, lowest - 3),
          maxY: 100.5,
        ),
      ),
      _ChartCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Alive at each stage',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
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
                _row(theme, ['After', 'Typical', 'Worst case'], header: true),
                for (final checkpoint in mortality.checkpoints)
                  _row(theme, [
                    '${checkpoint.hour.toStringAsFixed(0)} h',
                    _pct(checkpoint.median),
                    _pct(checkpoint.worst),
                  ]),
              ],
            ),
          ],
        ),
      ),
      _ChartCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What causes the losses',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            for (final entry in causes) ...[
              Row(
                children: [
                  Expanded(child: Text(_sentence(entry.key))),
                  Text(
                    '${entry.value.toStringAsFixed(0)} %',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: (entry.value / 100).clamp(0.0, 1.0).toDouble(),
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    ];
  }

  TableRow _row(ThemeData theme, List<String> cells, {bool header = false}) {
    return TableRow(
      children: [
        for (final cell in cells)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              cell,
              style: header
                  ? theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    )
                  : theme.textTheme.bodyMedium,
            ),
          ),
      ],
    );
  }

  List<Widget> _oxygen(AdvisoryTimeline timeline) {
    final oxygen = advisory.oxygen;
    if (oxygen == null) return const [_Missing()];
    final critical = oxygen.hoursToCriticalDo;
    return [
      _Banner(icon: Icons.air_rounded, text: oxygen.explanation),
      const SizedBox(height: 12),
      _StatGrid(
        tiles: [
          _StatTile(
            label: 'Oxygen gas left at arrival',
            value: '${oxygen.gasLeftPct.toStringAsFixed(0)} %',
          ),
          _StatTile(
            label: 'Water oxygen gets critical',
            value: critical == null
                ? 'Never'
                : 'Hour ${critical.toStringAsFixed(0)}',
            note: 'below ${oxygen.doCritical.toStringAsFixed(0)} mg/L',
          ),
          _StatTile(
            label: 'Use in the first 6 h',
            value: '${oxygen.useRateFirst6h.toStringAsFixed(2)} mg/h',
            note: 'higher from handling stress',
          ),
          _StatTile(
            label: 'Average use',
            value: '${oxygen.useRateAverage.toStringAsFixed(2)} mg/h',
            note: '${oxygen.usePerFish.toStringAsFixed(3)} mg/h per fish',
          ),
        ],
      ),
      const SizedBox(height: 12),
      _ChartCard(
        child: TimelineChart(
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
      ),
      _ChartCard(
        child: TimelineChart(
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
      ),
    ];
  }

  List<Widget> _water(AdvisoryTimeline timeline) {
    final chemistry = advisory.chemistry;
    if (chemistry == null) return const [_Missing()];
    final opened = timeline.median.openedAtHour;
    return [
      _Banner(icon: Icons.science_outlined, text: chemistry.explanation),
      const SizedBox(height: 12),
      _StatGrid(
        tiles: [
          _StatTile(
            label: 'Highest CO₂',
            value: '${chemistry.maxCo2.toStringAsFixed(0)} mg/L',
            note: 'harmful above ${_co2Harmful.toStringAsFixed(0)}',
            tone: chemistry.maxCo2 > _co2Harmful ? _Tone.warn : null,
          ),
          _StatTile(
            label: 'pH at arrival',
            value: chemistry.finalPh.toStringAsFixed(2),
          ),
          _StatTile(
            label: 'Highest toxic ammonia',
            value: '${chemistry.maxNh3Transit.toStringAsFixed(3)} mg/L',
            note: 'during the trip',
            tone: chemistry.maxNh3Transit > _nh3Safe ? _Tone.warn : null,
          ),
          _StatTile(
            label: 'Total ammonia at arrival',
            value: '${chemistry.finalTan.toStringAsFixed(1)} mg/L',
          ),
        ],
      ),
      const SizedBox(height: 12),
      _ChartCard(
        child: TimelineChart(
          title: 'Carbon dioxide (CO₂)',
          unit: 'mg/L',
          hours: timeline.median.hours,
          median: timeline.median.co2MgL,
          worst: timeline.worst.co2MgL,
          worstHours: timeline.worst.hours,
          threshold: _co2Harmful,
          thresholdLabel: 'Harmful above',
          openedAtHour: opened,
          minY: 0,
        ),
      ),
      _ChartCard(
        child: TimelineChart(
          title: 'pH',
          unit: '',
          hours: timeline.median.hours,
          median: timeline.median.ph,
          worst: timeline.worst.ph,
          worstHours: timeline.worst.hours,
          openedAtHour: opened,
          decimals: 2,
        ),
      ),
      _ChartCard(
        child: TimelineChart(
          title: 'Toxic ammonia (NH₃)',
          unit: 'mg/L',
          hours: timeline.median.hours,
          median: timeline.median.nh3MgL,
          worst: timeline.worst.nh3MgL,
          worstHours: timeline.worst.hours,
          threshold: _nh3Safe,
          thresholdLabel: 'Safe limit',
          openedAtHour: opened,
          minY: 0,
          decimals: 3,
        ),
      ),
      _ChartCard(
        child: TimelineChart(
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
      ),
    ];
  }

  List<Widget> _temperature(AdvisoryTimeline timeline) {
    final temperature = advisory.temperature;
    if (temperature == null) return const [_Missing()];
    final band = advisory.survivalBand;
    return [
      _Banner(icon: Icons.thermostat_rounded, text: temperature.advice),
      if (band != null) ...[
        const SizedBox(height: 12),
        _StatGrid(
          tiles: [
            _StatTile(label: 'Typical journey', value: _pct(band.median)),
            _StatTile(
              label: 'Worst journey',
              value: _pct(band.min),
              tone: band.min < advisory.targetSurvivalPct ? _Tone.warn : null,
            ),
            _StatTile(label: '9 in 10 journeys above', value: _pct(band.p10)),
            _StatTile(label: 'Best journey', value: _pct(band.max)),
          ],
        ),
      ],
      const SizedBox(height: 12),
      _ChartCard(
        child: TimelineChart(
          title: 'Fish alive at each temperature',
          unit: '% alive',
          xLabel: '°C',
          hours: [for (final point in temperature.curve) point.tempC],
          median: [for (final point in temperature.curve) point.survivalPct],
          threshold: advisory.targetSurvivalPct,
          thresholdLabel: 'Your target',
          minY: 0,
          maxY: 100.5,
        ),
      ),
      _ChartCard(
        child: TimelineChart(
          title: 'Temperature in the simulated journeys',
          unit: '°C',
          hours: timeline.median.hours,
          median: timeline.median.tempC,
          worst: timeline.worst.tempC,
          worstHours: timeline.worst.hours,
          openedAtHour: timeline.median.openedAtHour,
        ),
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Unpacking

class _UnpackingTab extends StatelessWidget {
  const _UnpackingTab({required this.advisory});

  final TransitAdvisory advisory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unpacking = advisory.unpacking;
    final timeline = advisory.timeline;
    if (unpacking == null || timeline == null) return const _Missing();
    return _TabBody(
      children: [
        _Banner(
          icon: unpacking.danger
              ? Icons.warning_amber_rounded
              : Icons.check_circle_outline_rounded,
          title: unpacking.danger
              ? 'Ammonia turns toxic when the bag is opened'
              : 'Unpacking is low risk',
          text: unpacking.explanation,
          tone: unpacking.danger ? _Tone.danger : _Tone.ok,
        ),
        const _SectionTitle('How to unpack'),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Column(
              children: [
                for (var i = 0; i < unpacking.steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: scheme.primary,
                          foregroundColor: scheme.onPrimary,
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              unpacking.steps[i],
                              style: theme.textTheme.bodyLarge?.copyWith(
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _ChartCard(
          child: TimelineChart(
            title: 'Toxic ammonia before and after opening',
            unit: 'mg/L',
            hours: timeline.median.hours,
            median: timeline.median.nh3MgL,
            worst: timeline.worst.nh3MgL,
            worstHours: timeline.worst.hours,
            threshold: _nh3Safe,
            thresholdLabel: 'Safe limit',
            openedAtHour: timeline.median.openedAtHour,
            minY: 0,
            decimals: 3,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Options

class _OptionsTab extends StatelessWidget {
  const _OptionsTab({required this.advisory});

  final TransitAdvisory advisory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = [...advisory.options]
      ..sort((a, b) => b.maxFishPerBag.compareTo(a.maxFishPerBag));
    final most = options.isEmpty ? 1 : math.max(options.first.maxFishPerBag, 1);
    final recommended = options.where((option) => option.recommended);
    final others = options.where((option) => !option.recommended);
    final best = recommended.isEmpty ? null : recommended.first;
    return _TabBody(
      children: [
        Text(
          'Every combination AquaSense tried, by the most fish per bag that '
          'still meet your target on the warmest day. An add-on is only '
          'recommended if it fits at least 5 % more fish.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        if (best != null) _OptionCard(option: best, most: most),
        if (others.isNotEmpty) ...[
          if (best != null) const _SectionTitle('Other combinations'),
          for (final option in others)
            _OptionCard(option: option, most: most, recommended: best),
        ],
      ],
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.option,
    required this.most,
    this.recommended,
  });

  final PackingOption option;
  final int most;

  /// The recommended option, to explain why a fuller one was not chosen.
  final PackingOption? recommended;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final extra = recommended == null
        ? 0
        : option.maxFishPerBag - recommended!.maxFishPerBag;
    final String? note;
    if (extra > 0) {
      note =
          'Only $extra more fish than the '
          'recommended plan, for an extra add-on';
    } else if (option.gainVsBasicPct != null && option.gainVsBasicPct! > 0) {
      note =
          '+${option.gainVsBasicPct!.toStringAsFixed(0)} % more fish than '
          'fasting only';
    } else {
      note = null;
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: option.recommended ? scheme.primaryContainer : null,
      shape: option.recommended
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: scheme.primary, width: 1.5),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (option.recommended) ...[
                        const _Pill(
                          icon: Icons.star_rounded,
                          label: 'Recommended',
                          tone: _Tone.ok,
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (option.selected && !option.recommended) ...[
                        const _Pill(
                          icon: Icons.visibility_outlined,
                          label: 'Shown plan',
                          tone: _Tone.warn,
                        ),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        _sentence(option.label),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (note != null)
                        Text(
                          note,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${option.maxFishPerBag}',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text('per bag', style: theme.textTheme.labelSmall),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: option.maxFishPerBag / most,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
              backgroundColor: scheme.surfaceContainerHighest,
              color: option.recommended
                  ? scheme.primary
                  : ExportChartColors.median.withValues(alpha: 0.55),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared pieces

enum _Tone {
  ok(Color(0xFF2E7D32), Icons.check_circle_rounded),
  warn(Color(0xFFB45F06), Icons.error_rounded),
  danger(Color(0xFFC62828), Icons.cancel_rounded);

  const _Tone(this.color, this.icon);

  final Color color;
  final IconData icon;
}

String _pct(double value) => '${value.toStringAsFixed(1)} %';

String _sentence(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

class _TabBody extends StatelessWidget {
  const _TabBody({required this.children, this.top = 16, super.key});

  final List<Widget> children;
  final double top;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(16, top, 16, 32),
      children: children,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
      child: Text(
        text,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _ExpandableCard extends StatelessWidget {
  const _ExpandableCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(16, 4, 10, 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          leading: Icon(icon, color: theme.colorScheme.primary),
          title: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          children: children,
        ),
      ),
    );
  }
}

/// Two equal columns of stat tiles, whatever the screen width.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.tiles});

  final List<_StatTile> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    this.note,
    this.tone,
  });

  final String label;
  final String value;
  final String? note;
  final _Tone? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: tone?.color,
              ),
            ),
            if (note != null) ...[
              const SizedBox(height: 2),
              Text(
                note!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.tone});

  final IconData icon;
  final String label;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
      decoration: BoxDecoration(
        color: tone.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: tone.color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: tone.color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    this.title,
    this.tone,
    this.action,
  });

  final IconData icon;
  final String text;
  final String? title;
  final _Tone? tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final danger = tone == _Tone.danger;
    final background = danger
        ? scheme.errorContainer
        : tone == _Tone.ok
        ? _Tone.ok.color.withValues(alpha: 0.1)
        : scheme.surfaceContainerHigh;
    final foreground = danger ? scheme.onErrorContainer : scheme.onSurface;
    final iconColor = tone?.color ?? scheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(text, style: TextStyle(color: foreground, height: 1.4)),
                if (action != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: action,
                    ),
                  ),
              ],
            ),
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
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Center(child: Text('Not available for this plan.')),
    );
  }
}
