import 'dart:async';

import 'package:mobile_app/features/disease_check/domain/decoded_frame.dart';
import 'package:mobile_app/features/disease_check/domain/fish_crop_classifier.dart';

/// Answers every crop with a fixed white-spot score.
class FakeFishCropClassifier implements FishCropClassifier {
  FakeFishCropClassifier({
    this.score = 0.9,
    this.isNotFish = false,
    this.error,
    this.gate,
  });

  double score;
  bool isNotFish;
  Object? error;

  /// When set, classify waits on this before answering (for cancel tests).
  Completer<void>? gate;
  bool disposed = false;

  @override
  Future<FishCropResult> classify(DecodedFrame crop) async {
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return FishCropResult(
      whiteSpotScore: score,
      isNotFish: isNotFish,
      probs: [1 - score, 0, score],
    );
  }

  @override
  Future<void> dispose() async => disposed = true;
}
