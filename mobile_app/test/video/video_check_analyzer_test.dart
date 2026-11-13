import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/disease_check/domain/fish_box.dart';
import 'package:mobile_app/features/disease_check/domain/video_check_analyzer.dart';
import 'package:mobile_app/features/disease_check/domain/video_check_result.dart';

const _dir = 'test/fixtures/video_parity';

FishBox _box(int x0, int y0, int x1, int y1) =>
    FishBox(x0: x0, y0: y0, x1: x1, y1: y1, score: 1);

void main() {
  group('per-fish vote', () {
    test('one very confident frame cannot make a fish white spot', () {
      // mean 0.714 >= 0.6, but only 2 of 5 frames are >= 0.6 -> not sure.
      expect(fishAnswer([0.9, 0.9, 0.59, 0.59, 0.59]), answerNotSure);
    });

    test('a confident majority is white spot', () {
      expect(fishAnswer([0.9, 0.8, 0.7, 0.2]), answerWhiteSpot);
    });

    test('low scores are healthy', () {
      expect(fishAnswer([0.1, 0.2, 0.3]), answerHealthy);
    });

    test('verdict thresholds', () {
      expect(verdict(0.6), answerWhiteSpot);
      expect(verdict(0.4), answerHealthy);
      expect(verdict(0.5), answerNotSure);
    });

    test('video answer rules', () {
      expect(
        videoAnswer(['white spot', 'healthy']),
        VideoAnswer.whiteSpotFound,
      );
      expect(videoAnswer(['healthy', 'healthy']), VideoAnswer.healthy);
      expect(videoAnswer(['healthy', 'not sure']), VideoAnswer.notSure);
      expect(videoAnswer([]), VideoAnswer.notSure);
    });
  });

  group('tracking', () {
    test('a fish needs at least 3 scored frames', () {
      final a = VideoCheckAnalyzer();
      a.addFrame([CheckedBox(box: _box(0, 0, 50, 50), score: 0.9)]);
      a.addFrame([CheckedBox(box: _box(1, 1, 51, 51), score: 0.9)]);
      expect(a.result().fish, isEmpty);
      a.addFrame([CheckedBox(box: _box(2, 2, 52, 52), score: 0.9)]);
      expect(a.result().fish.single.framesScored, 3);
    });

    test('a gap of 4 checked frames starts a new track', () {
      final a = VideoCheckAnalyzer();
      final ids1 = a.addFrame([
        CheckedBox(box: _box(0, 0, 50, 50), score: 0.9),
      ]);
      a.addFrame([]); // 2
      a.addFrame([]); // 3
      a.addFrame([]); // 4
      final ids5 = a.addFrame([
        CheckedBox(box: _box(0, 0, 50, 50), score: 0.9),
      ]);
      expect(ids1.single, 1);
      expect(ids5.single, 2); // gap 4 > 3 -> new fish
    });

    test('two boxes in the same frame never merge into one fish', () {
      final a = VideoCheckAnalyzer();
      final ids = a.addFrame([
        CheckedBox(box: _box(0, 0, 50, 50), score: 0.9),
        CheckedBox(box: _box(1, 1, 51, 51), score: 0.9), // overlaps the first
      ]);
      expect(ids, [1, 2]);
    });

    test('too-small boxes join a track without a score', () {
      final a = VideoCheckAnalyzer();
      a.addFrame([CheckedBox(box: _box(0, 0, 50, 50))]); // no score
      a.addFrame([CheckedBox(box: _box(1, 1, 51, 51), score: 0.9)]);
      final result = a.result();
      expect(result.fish, isEmpty); // only 1 score, below the 3-frame minimum
    });
  });

  test('replays check_video.py CSV to the same ids and answers', () {
    final lines = File('$_dir/checked.csv').readAsLinesSync();
    final header = lines.first.split(',');
    final col = {for (var i = 0; i < header.length; i++) header[i]: i};

    // Group rows by time_s. Checked frames are every 0.5 s, but frames with no
    // detections are not in the CSV, so the true frame number (Python's
    // n_checked) is reconstructed from time_s: n = round(t / 0.5) + 1. Empty
    // frames are fed as [] so the gap logic matches.
    final byTime = <String, List<List<String>>>{};
    var maxN = 1;
    for (final line in lines.skip(1)) {
      if (line.trim().isEmpty) continue;
      final r = line.split(',');
      final t = r[col['time_s']!];
      (byTime[t] ??= <List<String>>[]).add(r);
      final n = (double.parse(t) / 0.5).round() + 1;
      if (n > maxN) maxN = n;
    }

    final analyzer = VideoCheckAnalyzer();
    for (var n = 1; n <= maxN; n++) {
      final key = ((n - 1) * 0.5).toString();
      final rows = byTime[key] ?? const [];
      final fed = <CheckedBox>[];
      final expectedIds = <int>[];
      for (final r in rows) {
        if (r[col['frame_answer']!] == 'not a fish') continue; // dropped
        final box = _box(
          int.parse(r[col['x0']!]),
          int.parse(r[col['y0']!]),
          int.parse(r[col['x1']!]),
          int.parse(r[col['y1']!]),
        );
        final raw = r[col['white_spot_score']!];
        fed.add(
          CheckedBox(box: box, score: raw.isEmpty ? null : double.parse(raw)),
        );
        expectedIds.add(int.parse(r[col['fish']!]));
      }
      final ids = analyzer.addFrame(fed);
      expect(ids, expectedIds, reason: 'fish ids at t=$key (frame $n)');
    }

    final result = analyzer.result();
    final expected =
        jsonDecode(File('$_dir/expected_answers.json').readAsStringSync())
            as Map<String, dynamic>;

    final gotById = {for (final f in result.fish) f.id: f.answer};
    final expectedById = {
      for (final f in (expected['fish'] as List))
        (f as Map)['fish'] as int: f['answer'] as String,
    };
    expect(gotById, expectedById);

    const answerText = {
      VideoAnswer.whiteSpotFound: 'WHITE SPOT FOUND',
      VideoAnswer.healthy: 'HEALTHY',
      VideoAnswer.notSure: 'NOT SURE',
    };
    expect(
      (expected['video_answer'] as String).startsWith(
        answerText[result.answer]!,
      ),
      isTrue,
    );
  });
}
