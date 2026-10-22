import 'dart:math' as math;

/// A fish box in real video pixels, with the finder's confidence.
///
/// Coordinates match `(x0, y0, x1, y1)` in the reference `check_video.py`:
/// top-left inclusive, bottom-right exclusive.
class FishBox {
  const FishBox({
    required this.x0,
    required this.y0,
    required this.x1,
    required this.y1,
    required this.score,
  });

  final int x0;
  final int y0;
  final int x1;
  final int y1;
  final double score;

  int get width => x1 - x0;
  int get height => y1 - y0;
  int get shorterSide => math.min(width, height);
  double get centreX => (x0 + x1) / 2;
  double get centreY => (y0 + y1) / 2;

  /// Intersection-over-union with [other], as in `iou()` in check_video.py.
  double iou(FishBox other) {
    final ix = math.max(0, math.min(x1, other.x1) - math.max(x0, other.x0));
    final iy = math.max(0, math.min(y1, other.y1) - math.max(y0, other.y0));
    final inter = ix * iy;
    final union = width * height + other.width * other.height - inter;
    return union == 0 ? 0.0 : inter / union;
  }

  @override
  String toString() =>
      'FishBox($x0, $y0, $x1, $y1, ${score.toStringAsFixed(3)})';
}
