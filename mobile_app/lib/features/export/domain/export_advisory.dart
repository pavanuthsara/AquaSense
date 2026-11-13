/// Transit advisory for an export shipment (AquaSense component 4).
///
/// The advisory explains everything the exporter needs, not only a fish
/// count: how oxygen is used, how fast fish may die, which chemicals to add
/// and how much, water chemistry, temperature limits and unpacking risk.
library;

class ExportException implements Exception {
  const ExportException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

enum ExportSpecies {
  guppy('guppy', 'Guppy', 0.3),
  tigerBarb('tiger_barb', 'Tiger barb', 12);

  const ExportSpecies(this.key, this.label, this.typicalMassG);

  final String key;
  final String label;
  final double typicalMassG;

  static ExportSpecies fromKey(String? key) => ExportSpecies.values.firstWhere(
    (species) => species.key == key,
    orElse: () => ExportSpecies.guppy,
  );
}

/// How the exporter wants to plan.
enum PlanningMode {
  /// The simulator chooses fish per bag (and so the number of bags).
  suggest('suggest', 'Suggest'),

  /// The exporter fixes the number of bags.
  fixedBags('fixed_bags', 'Set bags'),

  /// The exporter enters their own fish per bag and add-ons.
  check('check', 'Check mine');

  const PlanningMode(this.key, this.label);

  final String key;
  final String label;

  static PlanningMode fromKey(String? key) => PlanningMode.values.firstWhere(
    (mode) => mode.key == key,
    orElse: () => PlanningMode.suggest,
  );
}

/// Anaesthetic the exporter puts in their own bags (check mode).
enum BagAnaesthetic {
  none(null, 'None'),
  ms222('ms222_40mgL', 'MS-222'),
  benzocaine('benzocaine_20mgL', 'Benzocaine');

  const BagAnaesthetic(this.key, this.label);

  final String? key;
  final String label;
}

class ExportShipmentRequest {
  const ExportShipmentRequest({
    required this.species,
    required this.fishMassG,
    required this.waterL,
    required this.gasL,
    required this.durationH,
    required this.tempLowC,
    required this.tempHighC,
    this.label,
    this.totalFish,
    this.targetSurvivalPct = 95,
    this.allowAnaesthetic = true,
    this.allowZeolite = true,
    this.maxFastingH = 48,
    this.mode = PlanningMode.suggest,
    this.bags,
    this.fishPerBag,
    this.checkFastingH = 24,
    this.checkZeolite = false,
    this.checkAnaesthetic = BagAnaesthetic.none,
  });

  final String? label;
  final ExportSpecies species;
  final double fishMassG;
  final int? totalFish;
  final double waterL;
  final double gasL;
  final double durationH;
  final double tempLowC;
  final double tempHighC;
  final double targetSurvivalPct;
  final bool allowAnaesthetic;
  final bool allowZeolite;
  final double maxFastingH;
  final PlanningMode mode;
  final int? bags;
  final int? fishPerBag;
  final double checkFastingH;
  final bool checkZeolite;
  final BagAnaesthetic checkAnaesthetic;

  Map<String, dynamic> toJson() => {
    if (label != null && label!.trim().isNotEmpty) 'label': label!.trim(),
    'species': species.key,
    'fishMassG': fishMassG,
    if (totalFish != null) 'totalFish': totalFish,
    'waterL': waterL,
    'gasL': gasL,
    'durationH': durationH,
    'tempLowC': tempLowC,
    'tempHighC': tempHighC,
    'targetSurvivalPct': targetSurvivalPct,
    'allowAnaesthetic': allowAnaesthetic,
    'allowZeolite': allowZeolite,
    'maxFastingH': maxFastingH,
    'mode': mode.key,
    if (mode == PlanningMode.fixedBags && bags != null) 'bags': bags,
    if (mode == PlanningMode.check) ...{
      'fishPerBag': fishPerBag,
      'checkFastingH': checkFastingH,
      'checkZeolite': checkZeolite,
      if (checkAnaesthetic.key != null)
        'checkAnaesthetic': checkAnaesthetic.key,
    },
  };
}

class ExportAdvisorySummary {
  const ExportAdvisorySummary({
    required this.id,
    required this.species,
    required this.durationHours,
    required this.feasible,
    required this.createdAt,
    this.label,
    this.mode = PlanningMode.suggest,
    this.meetsTarget = true,
    this.fishPerBag,
    this.bagsNeeded,
    this.survivalPct,
    this.worstSurvivalPct,
  });

  factory ExportAdvisorySummary.fromJson(Map<String, dynamic> json) {
    return ExportAdvisorySummary(
      id: json['id'] as String,
      label: json['label'] as String?,
      species: ExportSpecies.fromKey(json['species'] as String?),
      durationHours: _double(json['durationHours']) ?? 0,
      feasible: json['feasible'] as bool? ?? false,
      mode: PlanningMode.fromKey(json['mode'] as String?),
      meetsTarget: json['meetsTarget'] as bool? ?? true,
      fishPerBag: _int(json['fishPerBag']),
      bagsNeeded: _int(json['bagsNeeded']),
      survivalPct: _double(json['survivalPct']),
      worstSurvivalPct: _double(json['worstSurvivalPct']),
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
    );
  }

  final String id;
  final String? label;
  final ExportSpecies species;
  final double durationHours;
  final bool feasible;
  final PlanningMode mode;
  final bool meetsTarget;
  final int? fishPerBag;
  final int? bagsNeeded;
  final double? survivalPct;
  final double? worstSurvivalPct;
  final DateTime createdAt;
}

class ExportAdvisoryDetail {
  const ExportAdvisoryDetail({
    required this.id,
    required this.createdAt,
    required this.advisory,
    this.label,
  });

  factory ExportAdvisoryDetail.fromJson(Map<String, dynamic> json) {
    return ExportAdvisoryDetail(
      id: json['id'] as String,
      label: json['label'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      advisory: TransitAdvisory.fromJson(
        json['advisory'] as Map<String, dynamic>,
      ),
    );
  }

  final String id;
  final String? label;
  final DateTime createdAt;
  final TransitAdvisory advisory;
}

class TransitAdvisory {
  const TransitAdvisory({
    required this.feasible,
    required this.speciesName,
    required this.targetSurvivalPct,
    required this.warnings,
    required this.recommendation,
    required this.options,
    this.survivalBand,
    this.oxygen,
    this.mortality,
    this.chemistry,
    this.unpacking,
    this.temperature,
    this.timeline,
    this.durationH = 0,
    this.tempLowC = 0,
    this.tempHighC = 0,
    this.verdict,
    this.method,
  });

  factory TransitAdvisory.fromJson(Map<String, dynamic> json) {
    final request = _map(json['request']);
    final species = _map(json['species']);
    return TransitAdvisory(
      feasible: json['feasible'] as bool? ?? false,
      speciesName: species['name'] as String? ?? '',
      targetSurvivalPct: _double(json['target_survival_pct']) ?? 95,
      warnings: _strings(json['warnings']),
      recommendation: PackingRecommendation.fromJson(
        _map(json['recommendation']),
      ),
      options: _list(
        json['options'],
      ).map((item) => PackingOption.fromJson(_map(item))).toList(),
      survivalBand: json['survival_band_pct'] == null
          ? null
          : SurvivalBand.fromJson(_map(json['survival_band_pct'])),
      oxygen: json['oxygen'] == null
          ? null
          : OxygenSection.fromJson(_map(json['oxygen'])),
      mortality: json['mortality'] == null
          ? null
          : MortalitySection.fromJson(_map(json['mortality'])),
      chemistry: json['chemistry'] == null
          ? null
          : ChemistrySection.fromJson(_map(json['chemistry'])),
      unpacking: json['unpacking'] == null
          ? null
          : UnpackingSection.fromJson(_map(json['unpacking'])),
      temperature: json['temperature'] == null
          ? null
          : TemperatureSection.fromJson(_map(json['temperature'])),
      timeline: json['timeline'] == null
          ? null
          : AdvisoryTimeline.fromJson(_map(json['timeline'])),
      durationH: _double(request['duration_h']) ?? 0,
      tempLowC: _double(request['temp_low_c']) ?? 0,
      tempHighC: _double(request['temp_high_c']) ?? 0,
      verdict: json['verdict'] == null
          ? null
          : PackingVerdict.fromJson(_map(json['verdict'])),
      method: json['method'] == null
          ? null
          : MethodSection.fromJson(_map(json['method'])),
    );
  }

  final bool feasible;
  final String speciesName;
  final double targetSurvivalPct;
  final List<String> warnings;
  final PackingRecommendation recommendation;
  final List<PackingOption> options;
  final SurvivalBand? survivalBand;
  final OxygenSection? oxygen;
  final MortalitySection? mortality;
  final ChemistrySection? chemistry;
  final UnpackingSection? unpacking;
  final TemperatureSection? temperature;
  final AdvisoryTimeline? timeline;
  final double durationH;
  final double tempLowC;
  final double tempHighC;
  final PackingVerdict? verdict;
  final MethodSection? method;

  PlanningMode get mode => verdict?.mode ?? PlanningMode.suggest;
}

/// How the advisory is worked out, in plain words, with the studies behind
/// it. Kept apart from the advice itself.
class MethodSection {
  const MethodSection({
    required this.steps,
    required this.confidence,
    required this.sources,
  });

  factory MethodSection.fromJson(Map<String, dynamic> json) => MethodSection(
    steps: _strings(json['steps']),
    confidence: _strings(json['confidence']),
    sources: _list(json['sources'])
        .map(_map)
        .map(
          (source) => MethodSource(
            title: source['title'] as String? ?? '',
            usedFor: source['used_for'] as String? ?? '',
          ),
        )
        .toList(),
  );

  final List<String> steps;
  final List<String> confidence;
  final List<MethodSource> sources;
}

class MethodSource {
  const MethodSource({required this.title, required this.usedFor});

  final String title;
  final String usedFor;
}

/// Whether the shown packing reaches the survival target, plus the
/// recommended plan for comparison.
class PackingVerdict {
  const PackingVerdict({
    required this.mode,
    required this.meetsTarget,
    required this.message,
    this.survivalMedianPct,
    this.survivalWorstPct,
    this.expectedDeadTotal,
    this.recommendedFishPerBag,
    this.recommendedBags,
    this.recommendedPlanLabel,
  });

  factory PackingVerdict.fromJson(Map<String, dynamic> json) => PackingVerdict(
    mode: PlanningMode.fromKey(json['mode'] as String?),
    meetsTarget: json['meets_target'] as bool? ?? false,
    message: json['message'] as String? ?? '',
    survivalMedianPct: _double(json['survival_median_pct']),
    survivalWorstPct: _double(json['survival_worst_pct']),
    expectedDeadTotal: _int(json['expected_dead_total']),
    recommendedFishPerBag: _int(json['recommended_fish_per_bag']),
    recommendedBags: _int(json['recommended_bags']),
    recommendedPlanLabel: json['recommended_plan_label'] as String?,
  );

  final PlanningMode mode;
  final bool meetsTarget;
  final String message;
  final double? survivalMedianPct;
  final double? survivalWorstPct;
  final int? expectedDeadTotal;
  final int? recommendedFishPerBag;
  final int? recommendedBags;
  final String? recommendedPlanLabel;
}

class PackingRecommendation {
  const PackingRecommendation({
    required this.summary,
    required this.doses,
    required this.notSimulated,
    this.planLabel,
    this.fishPerBag,
    this.densityGPerL,
    this.bagsNeeded,
    this.fishPerBagWithoutChemicals,
    this.bagsNeededWithoutChemicals,
  });

  factory PackingRecommendation.fromJson(Map<String, dynamic> json) {
    return PackingRecommendation(
      summary: json['summary'] as String? ?? '',
      planLabel: json['plan_label'] as String?,
      fishPerBag: _int(json['fish_per_bag']),
      densityGPerL: _double(json['density_g_per_l']),
      bagsNeeded: _int(json['bags_needed']),
      fishPerBagWithoutChemicals: _int(json['fish_per_bag_without_chemicals']),
      bagsNeededWithoutChemicals: _int(json['bags_needed_without_chemicals']),
      doses: _list(
        json['doses'],
      ).map((item) => AddonDose.fromJson(_map(item))).toList(),
      notSimulated: _list(
        json['not_simulated_options'],
      ).map((item) => AddonDose.fromJson(_map(item))).toList(),
    );
  }

  final String summary;
  final String? planLabel;
  final int? fishPerBag;
  final double? densityGPerL;
  final int? bagsNeeded;
  final int? fishPerBagWithoutChemicals;
  final int? bagsNeededWithoutChemicals;
  final List<AddonDose> doses;
  final List<AddonDose> notSimulated;
}

class AddonDose {
  const AddonDose({
    required this.addon,
    required this.name,
    required this.amount,
    required this.evidence,
    required this.caution,
    this.perBag,
    this.simulated = true,
    this.why = '',
    this.source,
  });

  factory AddonDose.fromJson(Map<String, dynamic> json) {
    return AddonDose(
      addon: json['addon'] as String? ?? '',
      name: json['name'] as String? ?? '',
      amount: json['amount'] as String? ?? '',
      perBag: json['per_bag'] as String?,
      simulated: json['simulated'] as bool? ?? false,
      evidence: json['evidence'] as String? ?? '',
      caution: json['caution'] as String? ?? '',
      why: json['why'] as String? ?? json['evidence'] as String? ?? '',
      source: json['source'] as String?,
    );
  }

  final String addon;
  final String name;
  final String amount;
  final String? perBag;
  final bool simulated;
  final String evidence;
  final String caution;

  /// Plain-language reason, shown to the exporter.
  final String why;

  /// The studies behind it, shown only in "How we work this out".
  final String? source;
}

class PackingOption {
  const PackingOption({
    required this.key,
    required this.label,
    required this.maxFishPerBag,
    required this.recommended,
    this.selected = false,
    this.gainVsBasicPct,
  });

  factory PackingOption.fromJson(Map<String, dynamic> json) {
    return PackingOption(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      maxFishPerBag: _int(json['max_fish_per_bag']) ?? 0,
      recommended: json['recommended'] as bool? ?? false,
      selected: json['selected'] as bool? ?? false,
      gainVsBasicPct: _double(json['gain_vs_basic_pct']),
    );
  }

  final String key;
  final String label;
  final int maxFishPerBag;
  final bool recommended;
  final bool selected;
  final double? gainVsBasicPct;
}

class SurvivalBand {
  const SurvivalBand({
    required this.min,
    required this.p10,
    required this.median,
    required this.max,
  });

  factory SurvivalBand.fromJson(Map<String, dynamic> json) => SurvivalBand(
    min: _double(json['min']) ?? 0,
    p10: _double(json['p10']) ?? 0,
    median: _double(json['median']) ?? 0,
    max: _double(json['max']) ?? 0,
  );

  final double min;
  final double p10;
  final double median;
  final double max;
}

class OxygenSection {
  const OxygenSection({
    required this.explanation,
    required this.useRateFirst6h,
    required this.useRateAverage,
    required this.usePerFish,
    required this.gasLeftPct,
    required this.minWaterDo,
    required this.doCritical,
    required this.limiting,
    this.hoursToCriticalDo,
    this.hoursToCriticalDoWorst,
  });

  factory OxygenSection.fromJson(Map<String, dynamic> json) => OxygenSection(
    explanation: json['explanation'] as String? ?? '',
    useRateFirst6h: _double(json['use_rate_first_6h_mg_per_h']) ?? 0,
    useRateAverage: _double(json['use_rate_average_mg_per_h']) ?? 0,
    usePerFish: _double(json['use_per_fish_mg_per_h']) ?? 0,
    gasLeftPct: _double(json['gas_o2_left_pct']) ?? 0,
    minWaterDo: _double(json['min_water_do_mgL']) ?? 0,
    doCritical: _double(json['do_critical_mgL']) ?? 3,
    limiting: json['limiting'] as String? ?? 'none',
    hoursToCriticalDo: _double(json['hours_to_critical_do']),
    hoursToCriticalDoWorst: _double(json['hours_to_critical_do_worst']),
  );

  final String explanation;
  final double useRateFirst6h;
  final double useRateAverage;
  final double usePerFish;
  final double gasLeftPct;
  final double minWaterDo;
  final double doCritical;
  final String limiting;
  final double? hoursToCriticalDo;
  final double? hoursToCriticalDoWorst;
}

class SurvivalCheckpoint {
  const SurvivalCheckpoint({
    required this.hour,
    required this.median,
    required this.worst,
  });

  factory SurvivalCheckpoint.fromJson(Map<String, dynamic> json) =>
      SurvivalCheckpoint(
        hour: _double(json['hour']) ?? 0,
        median: _double(json['median']) ?? 0,
        worst: _double(json['worst']) ?? 0,
      );

  final double hour;
  final double median;
  final double worst;
}

class MortalitySection {
  const MortalitySection({
    required this.explanation,
    required this.checkpoints,
    required this.survivalAtArrivalPct,
    required this.survivalAfterUnpackingPct,
    required this.worstSurvivalAfterUnpackingPct,
    required this.expectedDeadPerBag,
    required this.expectedDeadPerBagWorst,
    required this.mainCause,
    required this.causeSharePct,
    this.hoursToFirstLoss,
    this.hoursToFirstLossWorst,
  });

  factory MortalitySection.fromJson(Map<String, dynamic> json) {
    final shares = _map(json['cause_share_pct']);
    return MortalitySection(
      explanation: json['explanation'] as String? ?? '',
      checkpoints: _list(
        json['survival_at_checkpoints_pct'],
      ).map((item) => SurvivalCheckpoint.fromJson(_map(item))).toList(),
      survivalAtArrivalPct: _double(json['survival_at_arrival_pct']) ?? 0,
      survivalAfterUnpackingPct:
          _double(json['survival_after_unpacking_pct']) ?? 0,
      worstSurvivalAfterUnpackingPct:
          _double(json['worst_survival_after_unpacking_pct']) ?? 0,
      expectedDeadPerBag: _double(json['expected_dead_per_bag']) ?? 0,
      expectedDeadPerBagWorst:
          _double(json['expected_dead_per_bag_worst']) ?? 0,
      mainCause: json['main_cause'] as String? ?? '',
      causeSharePct: {
        for (final entry in shares.entries)
          entry.key: _double(entry.value) ?? 0,
      },
      hoursToFirstLoss: _double(json['hours_to_first_1pct_loss']),
      hoursToFirstLossWorst: _double(json['hours_to_first_1pct_loss_worst']),
    );
  }

  final String explanation;
  final List<SurvivalCheckpoint> checkpoints;
  final double survivalAtArrivalPct;
  final double survivalAfterUnpackingPct;
  final double worstSurvivalAfterUnpackingPct;
  final double expectedDeadPerBag;
  final double expectedDeadPerBagWorst;
  final String mainCause;
  final Map<String, double> causeSharePct;
  final double? hoursToFirstLoss;
  final double? hoursToFirstLossWorst;
}

class ChemistrySection {
  const ChemistrySection({
    required this.explanation,
    required this.maxCo2,
    required this.finalPh,
    required this.finalTan,
    required this.maxNh3Transit,
  });

  factory ChemistrySection.fromJson(Map<String, dynamic> json) =>
      ChemistrySection(
        explanation: json['explanation'] as String? ?? '',
        maxCo2: _double(json['max_co2_mgL']) ?? 0,
        finalPh: _double(json['final_ph']) ?? 0,
        finalTan: _double(json['final_tan_mgL']) ?? 0,
        maxNh3Transit: _double(json['max_nh3_transit_mgL']) ?? 0,
      );

  final String explanation;
  final double maxCo2;
  final double finalPh;
  final double finalTan;
  final double maxNh3Transit;
}

class UnpackingSection {
  const UnpackingSection({
    required this.explanation,
    required this.steps,
    required this.danger,
    required this.phAfterOpening,
    required this.peakNh3,
    required this.peakNh3Worst,
  });

  factory UnpackingSection.fromJson(Map<String, dynamic> json) =>
      UnpackingSection(
        explanation: json['explanation'] as String? ?? '',
        steps: _strings(json['steps']),
        danger: json['danger'] as bool? ?? false,
        phAfterOpening: _double(json['ph_after_opening']) ?? 0,
        peakNh3: _double(json['peak_nh3_mgL']) ?? 0,
        peakNh3Worst: _double(json['peak_nh3_mgL_worst']) ?? 0,
      );

  final String explanation;
  final List<String> steps;
  final bool danger;
  final double phAfterOpening;
  final double peakNh3;
  final double peakNh3Worst;
}

class TemperaturePoint {
  const TemperaturePoint(this.tempC, this.survivalPct);

  final double tempC;
  final double survivalPct;
}

class TemperatureSection {
  const TemperatureSection({
    required this.advice,
    required this.curve,
    this.maxSafeTempC,
  });

  factory TemperatureSection.fromJson(Map<String, dynamic> json) =>
      TemperatureSection(
        advice: json['advice'] as String? ?? '',
        maxSafeTempC: _double(json['max_safe_constant_temp_c']),
        curve: _list(json['curve'])
            .map(_map)
            .map(
              (point) => TemperaturePoint(
                _double(point['temp_c']) ?? 0,
                _double(point['survival_pct']) ?? 0,
              ),
            )
            .toList(),
      );

  final String advice;
  final double? maxSafeTempC;
  final List<TemperaturePoint> curve;
}

/// One simulated journey, sampled about hourly.
class TimelineSeries {
  const TimelineSeries({
    required this.hours,
    required this.doMgL,
    required this.gasO2Pct,
    required this.tanMgL,
    required this.co2MgL,
    required this.ph,
    required this.nh3MgL,
    required this.alivePct,
    required this.tempC,
    required this.opened,
  });

  factory TimelineSeries.fromJson(Map<String, dynamic> json) => TimelineSeries(
    hours: _hours(json['t_h']),
    doMgL: _series(json['do_mgL']),
    gasO2Pct: _series(json['gas_o2_pct']),
    tanMgL: _series(json['tan_mgL']),
    co2MgL: _series(json['co2_mgL']),
    ph: _series(json['ph']),
    nh3MgL: _series(json['nh3_mgL']),
    alivePct: _series(json['alive_pct']),
    tempC: _series(json['temp_c']),
    opened: _list(json['opened']).map((value) => value == 1).toList(),
  );

  final List<double> hours;
  final List<double?> doMgL;
  final List<double?> gasO2Pct;
  final List<double?> tanMgL;
  final List<double?> co2MgL;
  final List<double?> ph;
  final List<double?> nh3MgL;
  final List<double?> alivePct;
  final List<double?> tempC;
  final List<bool> opened;

  double? get openedAtHour {
    for (var i = 0; i < opened.length && i < hours.length; i++) {
      if (opened[i]) return hours[i];
    }
    return null;
  }
}

class AdvisoryTimeline {
  const AdvisoryTimeline({
    required this.median,
    required this.worst,
    required this.worstLabel,
  });

  factory AdvisoryTimeline.fromJson(Map<String, dynamic> json) =>
      AdvisoryTimeline(
        median: TimelineSeries.fromJson(_map(json['median'])),
        worst: TimelineSeries.fromJson(_map(json['worst'])),
        worstLabel: json['worst_label'] as String? ?? 'worst case',
      );

  final TimelineSeries median;
  final TimelineSeries worst;
  final String worstLabel;
}

Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : const <String, dynamic>{};

List<dynamic> _list(Object? value) =>
    value is List<dynamic> ? value : const <dynamic>[];

List<String> _strings(Object? value) =>
    _list(value).whereType<String>().toList(growable: false);

double? _double(Object? value) => value is num ? value.toDouble() : null;

int? _int(Object? value) => value is num ? value.round() : null;

/// Values that may contain gaps (null), e.g. headspace O2 after opening.
List<double?> _series(Object? value) =>
    _list(value).map(_double).toList(growable: false);

List<double> _hours(Object? value) =>
    _list(value).map((item) => _double(item) ?? 0).toList(growable: false);
