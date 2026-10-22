import 'dart:math' as math;
import 'dart:typed_data';

import 'fish_box.dart';
import 'video_check_result.dart';
import 'video_check_settings.dart';

/// The verdict for one white-spot score, as `verdict(p)` in check_video.py.
String verdict(double p) {
  if (p >= videoSureThreshold) return answerWhiteSpot;
  if (p <= 1 - videoSureThreshold) return answerHealthy;
  return answerNotSure;
}

/// One fish's answer from all its scores, as `fish_answer` in check_video.py:
/// the average must reach 0.6 AND at least half the frames must be at 0.6, so
/// one or two confident frames cannot decide alone.
String fishAnswer(List<double> scores) {
  final mean = scores.reduce((a, b) => a + b) / scores.length;
  final v = verdict(mean);
  if (v == answerWhiteSpot) {
    final sure = scores.where((s) => s >= videoSureThreshold).length;
    if (sure / scores.length < 0.5) return answerNotSure;
  }
  return v;
}

/// The whole-video answer from the per-fish answers, as `overall` in
/// check_video.py.
VideoAnswer videoAnswer(List<String> answers) {
  if (answers.contains(answerWhiteSpot)) return VideoAnswer.whiteSpotFound;
  if (answers.isNotEmpty && answers.every((a) => a == answerHealthy)) {
    return VideoAnswer.healthy;
  }
  return VideoAnswer.notSure;
}

/// Two boxes in neighbouring checked frames are the same fish, as `same_fish`
/// in check_video.py.
bool sameFish(FishBox a, FishBox b) {
  if (a.iou(b) > sameFishIouThreshold) return true;
  final d = math.sqrt(
    math.pow(a.centreX - b.centreX, 2) + math.pow(a.centreY - b.centreY, 2),
  );
  final span = [
    a.width,
    a.height,
    b.width,
    b.height,
  ].reduce(math.max).toDouble();
  return d < sameFishCentreFraction * span;
}

/// One detected box in a checked frame, with its white-spot score (null when
/// the box was too small to judge). `not_fish` boxes are dropped before here.
class CheckedBox {
  const CheckedBox({required this.box, this.score, this.thumbnail});
  final FishBox box;
  final double? score;

  /// Encoded crop of this fish for display, if the caller has the pixels.
  final Uint8List? thumbnail;
}

class _Track {
  _Track(this.id, this.box, this.last);
  final int id;
  FishBox box;
  int last;
  final List<double> scores = [];
  Uint8List? bestThumbnail;
  double bestScore = -1;
}

/// Follows each fish across the checked frames and votes a per-fish and a
/// whole-video answer, exactly as the main loop of check_video.py does.
///
/// Feed one checked frame at a time with [addFrame] (boxes in detection order,
/// `not_fish` already dropped), then read [result].
class VideoCheckAnalyzer {
  final List<_Track> _tracks = [];
  int _n = 0;

  int get framesChecked => _n;

  /// Processes one checked frame. Returns the fish id assigned to each box, in
  /// the order given.
  List<int> addFrame(List<CheckedBox> boxes) {
    _n += 1;
    final ids = <int>[];
    for (final checked in boxes) {
      final box = checked.box;
      _Track? match;
      for (final tr in _tracks) {
        if (_n - tr.last <= trackMaxFrameGap &&
            tr.last != _n &&
            sameFish(tr.box, box)) {
          match = tr;
          break;
        }
      }
      match ??= (_tracks..add(_Track(_tracks.length + 1, box, _n))).last;
      match.box = box;
      match.last = _n;
      if (checked.score != null) {
        match.scores.add(checked.score!);
        if (checked.thumbnail != null && checked.score! > match.bestScore) {
          match.bestScore = checked.score!;
          match.bestThumbnail = checked.thumbnail;
        }
      }
      ids.add(match.id);
    }
    return ids;
  }

  /// Builds the result from the tracks with at least [videoMinFrames] scores.
  VideoCheckResult result({Duration timeTaken = Duration.zero}) {
    final fish = <VideoFishResult>[];
    for (final tr in _tracks) {
      if (tr.scores.length < videoMinFrames) continue;
      final mean = tr.scores.reduce((a, b) => a + b) / tr.scores.length;
      fish.add(
        VideoFishResult(
          id: tr.id,
          answer: fishAnswer(tr.scores),
          meanScore: mean,
          framesScored: tr.scores.length,
          thumbnail: tr.bestThumbnail,
        ),
      );
    }
    return VideoCheckResult(
      answer: videoAnswer(fish.map((f) => f.answer).toList()),
      fish: fish,
      framesChecked: _n,
      timeTaken: timeTaken,
    );
  }
}
