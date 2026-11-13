/// Below this top score the app says "Not sure" instead of naming a result.
///
/// Matches `UNCERTAIN_BELOW` in the research project's `predict_pi.py`.
const double uncertainBelow = 0.6;

/// Version of the bundled model, saved with every result so old checks can be
/// told apart after the model is retrained.
const String bundledModelVersion = 'guppy-white-spot-2026-10-16';

/// Version of the bundled 3-class video white-spot model (healthy / not_fish /
/// white_spot). Saved with every video-check result. See [[video_check_settings]].
const String videoModelVersion = 'guppy-video-v5-2026-10-19';

/// Version of the bundled YOLO11n fish-finder model used by the video check.
const String fishFinderVersion = 'fish-finder-yolo11n-2026-10-19';

/// The model's score for one class, between 0 and 1.
class LabelScore {
  const LabelScore({required this.label, required this.score});

  final String label;
  final double score;
}

/// What the model said about one photo.
class DiseasePrediction {
  const DiseasePrediction({
    required this.scores,
    required this.modelVersion,
    required this.inferenceTime,
    required this.checkedAt,
  }) : assert(scores.length > 0);

  /// Builds a prediction from the model's labels and raw output scores.
  ///
  /// Scores are sorted from highest to lowest, so [topLabel] is the answer.
  factory DiseasePrediction.fromScores({
    required List<String> labels,
    required List<double> scores,
    required String modelVersion,
    required Duration inferenceTime,
    required DateTime checkedAt,
  }) {
    if (labels.isEmpty || labels.length != scores.length) {
      throw ArgumentError(
        'The model returned ${scores.length} scores for ${labels.length} '
        'labels.',
      );
    }
    final pairs = [
      for (var i = 0; i < labels.length; i++)
        LabelScore(label: labels[i], score: scores[i].clamp(0.0, 1.0)),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return DiseasePrediction(
      scores: List.unmodifiable(pairs),
      modelVersion: modelVersion,
      inferenceTime: inferenceTime,
      checkedAt: checkedAt,
    );
  }

  /// Every class with its score, highest first.
  final List<LabelScore> scores;
  final String modelVersion;

  /// How long the model itself took to run.
  final Duration inferenceTime;
  final DateTime checkedAt;

  String get topLabel => scores.first.label;
  double get confidence => scores.first.score;

  /// True when the best score is too low to trust.
  bool get isUncertain => confidence < uncertainBelow;
}
