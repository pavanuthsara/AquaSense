import 'dart:typed_data';

/// The whole-video answer. Matches `overall` in check_video.py.
enum VideoAnswer { whiteSpotFound, healthy, notSure }

/// Per-fish answers, as strings matching check_video.py (`fish_answer`).
const String answerWhiteSpot = 'white spot';
const String answerHealthy = 'healthy';
const String answerNotSure = 'not sure';

/// One fish's result over all the frames it was seen in.
class VideoFishResult {
  const VideoFishResult({
    required this.id,
    required this.answer,
    required this.meanScore,
    required this.framesScored,
    this.thumbnail,
  });

  final int id;
  final String answer;
  final double meanScore;
  final int framesScored;

  /// Encoded (PNG/JPEG) crop of this fish from its most confident frame, for
  /// display. Null in pure-Dart tests, filled by the UI orchestrator.
  final Uint8List? thumbnail;
}

/// The result of checking one video.
class VideoCheckResult {
  const VideoCheckResult({
    required this.answer,
    required this.fish,
    required this.framesChecked,
    required this.timeTaken,
  });

  final VideoAnswer answer;
  final List<VideoFishResult> fish;
  final int framesChecked;
  final Duration timeTaken;

  int get whiteSpotCount =>
      fish.where((f) => f.answer == answerWhiteSpot).length;
  int get healthyCount => fish.where((f) => f.answer == answerHealthy).length;
  int get notSureCount => fish.where((f) => f.answer == answerNotSure).length;

  /// True when no fish was seen in enough frames to judge.
  bool get noFishSeen => fish.isEmpty;
}
