import 'dart:math' as math;
import 'dart:typed_data';

import '../domain/fish_box.dart';
import '../domain/video_check_settings.dart';

/// IoU of two float `[x, y, w, h]` rectangles, as `cv2.dnn.NMSBoxes` uses.
double rectIou(List<double> a, List<double> b) {
  final ix = math.max(
    0.0,
    math.min(a[0] + a[2], b[0] + b[2]) - math.max(a[0], b[0]),
  );
  final iy = math.max(
    0.0,
    math.min(a[1] + a[3], b[1] + b[3]) - math.max(a[1], b[1]),
  );
  final inter = ix * iy;
  final union = a[2] * a[3] + b[2] * b[3] - inter;
  return union <= 0 ? 0.0 : inter / union;
}

/// Greedy non-max suppression, matching `cv2.dnn.NMSBoxes(boxes, scores,
/// scoreThreshold, iouThreshold)`: sort by score high to low, keep a box unless
/// its IoU with an already-kept box exceeds [iouThreshold]. [rects] are
/// `[x, y, w, h]`. Returns the kept indices, in score order.
List<int> nonMaxSuppression(
  List<List<double>> rects,
  List<double> scores,
  double iouThreshold,
) {
  final order = List<int>.generate(rects.length, (i) => i)
    ..sort((a, b) => scores[b].compareTo(scores[a]));
  final kept = <int>[];
  for (final i in order) {
    var suppressed = false;
    for (final k in kept) {
      if (rectIou(rects[i], rects[k]) > iouThreshold) {
        suppressed = true;
        break;
      }
    }
    if (!suppressed) kept.add(i);
  }
  return kept;
}

/// Turns the fish finder's raw output into boxes in video pixels, exactly as
/// `FishFinder.__call__` does in `check_video.py`.
///
/// [rawOutput] is the model output flattened in `[5, N]` order: the five rows
/// are cx, cy, w, h, score, each with `N` columns. Boxes are decoded for the
/// given frame size using the same letterbox maths as [prepareDetectorInput].
List<FishBox> decodeDetections(
  Float32List rawOutput,
  int frameWidth,
  int frameHeight, {
  int inputSize = fishFinderInputSize,
  double confidence = fishFinderConfidence,
  double nmsIou = fishFinderNmsIou,
}) {
  final n = rawOutput.length ~/ 5;
  double row(int r, int c) => rawOutput[r * n + c];

  final s = inputSize / math.max(frameWidth, frameHeight);
  final nw = (frameWidth * s).round();
  final nh = (frameHeight * s).round();
  final left = (inputSize - nw) ~/ 2;
  final top = (inputSize - nh) ~/ 2;

  // Keep columns above the confidence threshold.
  final kept = <int>[];
  for (var c = 0; c < n; c++) {
    if (row(4, c) >= confidence) kept.add(c);
  }
  if (kept.isEmpty) return const [];

  // Normalised 0-1 output: scale up to the square (same test as Python, over
  // the kept columns only).
  var maxCxW = 0.0;
  for (final c in kept) {
    maxCxW = math.max(maxCxW, math.max(row(0, c), row(2, c)));
  }
  final mul = maxCxW <= 2.0 ? inputSize.toDouble() : 1.0;

  final rects = <List<double>>[];
  final scores = <double>[];
  for (final c in kept) {
    final cx = row(0, c) * mul;
    final cy = row(1, c) * mul;
    final w = row(2, c) * mul;
    final h = row(3, c) * mul;
    rects.add([(cx - w / 2 - left) / s, (cy - h / 2 - top) / s, w / s, h / s]);
    scores.add(row(4, c));
  }

  final boxes = <FishBox>[];
  for (final i in nonMaxSuppression(rects, scores, nmsIou)) {
    final r = rects[i];
    boxes.add(
      FishBox(
        x0: math.max(0, r[0].truncate()),
        y0: math.max(0, r[1].truncate()),
        x1: math.min(frameWidth, (r[0] + r[2]).truncate()),
        y1: math.min(frameHeight, (r[1] + r[3]).truncate()),
        score: scores[i],
      ),
    );
  }
  return boxes;
}
