import 'dart:math' as math;

import 'disease_prediction.dart';
import 'video_check_result.dart';

/// Turns a video result into the [DiseasePrediction] saved to history, matching
/// the DIS-017 rule:
///   predictedLabel = white_spot if any fish is white spot, else healthy
///   confidence     = highest mean among white-spot fish, or for healthy
///                    (1 - highest mean among the fish)
///   uncertain      = the video answer is NOT SURE  (here: confidence < 0.6)
///   modelVersion   = the video model version
DiseasePrediction videoResultToPrediction(
  VideoCheckResult result, {
  DateTime? checkedAt,
}) {
  final whiteSpotMeans = result.fish
      .where((f) => f.answer == answerWhiteSpot)
      .map((f) => f.meanScore);

  final String label;
  final double confidence;
  if (whiteSpotMeans.isNotEmpty) {
    label = 'white_spot';
    confidence = whiteSpotMeans.reduce(math.max);
  } else {
    label = 'healthy';
    final maxMean = result.fish.isEmpty
        ? 0.0
        : result.fish.map((f) => f.meanScore).reduce(math.max);
    confidence = 1 - maxMean;
  }

  return DiseasePrediction(
    scores: [LabelScore(label: label, score: confidence.clamp(0.0, 1.0))],
    modelVersion: videoModelVersion,
    inferenceTime: result.timeTaken,
    checkedAt: checkedAt ?? DateTime.now().toUtc(),
  );
}

/// A pre-filled note describing the video result, for the save panel.
String videoResultNote(VideoCheckResult result) {
  return 'Video: ${result.fish.length} fish '
      '(${result.whiteSpotCount} white spot, ${result.healthyCount} healthy, '
      '${result.notSureCount} not sure), ${result.framesChecked} frames';
}
