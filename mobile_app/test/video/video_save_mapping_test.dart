import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/disease_check/domain/disease_prediction.dart';
import 'package:mobile_app/features/disease_check/domain/video_check_result.dart';
import 'package:mobile_app/features/disease_check/domain/video_save_mapping.dart';

VideoCheckResult _result(VideoAnswer answer, List<VideoFishResult> fish) =>
    VideoCheckResult(
      answer: answer,
      fish: fish,
      framesChecked: 40,
      timeTaken: const Duration(seconds: 7),
    );

VideoFishResult _fish(int id, String answer, double mean) =>
    VideoFishResult(id: id, answer: answer, meanScore: mean, framesScored: 5);

void main() {
  test('white spot: label white_spot, confidence = highest sick mean', () {
    final p = videoResultToPrediction(
      _result(VideoAnswer.whiteSpotFound, [
        _fish(1, answerWhiteSpot, 0.8),
        _fish(2, answerWhiteSpot, 0.95),
        _fish(3, answerHealthy, 0.1),
      ]),
    );
    expect(p.topLabel, 'white_spot');
    expect(p.confidence, closeTo(0.95, 1e-9));
    expect(p.isUncertain, isFalse);
    expect(p.modelVersion, videoModelVersion);
  });

  test(
    'healthy: label healthy, confidence = 1 - highest mean, not uncertain',
    () {
      final p = videoResultToPrediction(
        _result(VideoAnswer.healthy, [
          _fish(1, answerHealthy, 0.2),
          _fish(2, answerHealthy, 0.35),
        ]),
      );
      expect(p.topLabel, 'healthy');
      expect(p.confidence, closeTo(0.65, 1e-9));
      expect(p.isUncertain, isFalse);
    },
  );

  test('not sure: label healthy, uncertain true', () {
    final p = videoResultToPrediction(
      _result(VideoAnswer.notSure, [
        _fish(1, answerHealthy, 0.3),
        _fish(2, answerNotSure, 0.55),
      ]),
    );
    expect(p.topLabel, 'healthy');
    expect(p.confidence, closeTo(0.45, 1e-9)); // 1 - 0.55
    expect(p.isUncertain, isTrue);
  });

  test('no fish seen: healthy label, uncertain', () {
    final p = videoResultToPrediction(_result(VideoAnswer.notSure, []));
    expect(p.topLabel, 'healthy');
    expect(p.confidence, 1.0);
    expect(p.isUncertain, isFalse); // 1 - 0 = 1.0 (no fish)
  });

  test('note summarises the result', () {
    final note = videoResultNote(
      _result(VideoAnswer.whiteSpotFound, [
        _fish(1, answerWhiteSpot, 0.9),
        _fish(2, answerHealthy, 0.1),
        _fish(3, answerNotSure, 0.5),
      ]),
    );
    expect(
      note,
      'Video: 3 fish (1 white spot, 1 healthy, 1 not sure), 40 frames',
    );
  });
}
