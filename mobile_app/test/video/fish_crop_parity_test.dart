import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_app/features/disease_check/data/crop_preprocessor.dart';
import 'package:mobile_app/features/disease_check/domain/decoded_frame.dart';
import 'package:mobile_app/features/disease_check/domain/fish_box.dart';

const _dir = 'test/fixtures/video_parity';
const _labels = ['healthy', 'not_fish', 'white_spot'];

DecodedFrame _frame(int k) {
  final image = img.decodeImage(File('$_dir/frame_$k.png').readAsBytesSync())!;
  return DecodedFrame(
    width: image.width,
    height: image.height,
    rgb: Uint8List.fromList(image.getBytes(order: img.ChannelOrder.rgb)),
    timeMs: 0,
  );
}

List<dynamic> _crops(int k) =>
    jsonDecode(File('$_dir/crops_$k.json').readAsStringSync()) as List<dynamic>;

void main() {
  group('cropBoxWithMargin matches Python crop_box', () {
    for (final k in [1, 2, 3]) {
      test('frame $k', () {
        final frame = _frame(k);
        for (final raw in _crops(k)) {
          final entry = raw as Map<String, dynamic>;
          if (entry['too_small'] == true) continue;
          final b = (entry['box'] as List).cast<num>();
          final box = FishBox(
            x0: b[0].toInt(),
            y0: b[1].toInt(),
            x1: b[2].toInt(),
            y1: b[3].toInt(),
            score: 1,
          );
          final cb = cropBoxWithMargin(box, frame.width, frame.height);
          final expected = (entry['crop_box'] as List).cast<num>();
          expect([cb.x0, cb.y0, cb.x1, cb.y1], expected);
        }
      });
    }

    test('clamps at the frame borders and truncates toward zero', () {
      // Box touching the top-left and bottom-right of a 100x100 frame.
      final box = const FishBox(x0: 0, y0: 0, x1: 100, y1: 100, score: 1);
      final cb = cropBoxWithMargin(box, 100, 100);
      expect([cb.x0, cb.y0, cb.x1, cb.y1], [0, 0, 100, 100]);
    });
  });

  group('prepareCropInput matches crop_input_k_j.png', () {
    for (final k in [1, 2, 3]) {
      test('frame $k', () {
        final frame = _frame(k);
        final crops = _crops(k);
        for (var j = 0; j < crops.length; j++) {
          final entry = crops[j] as Map<String, dynamic>;
          if (entry['too_small'] == true) continue;
          final b = (entry['box'] as List).cast<num>();
          final box = FishBox(
            x0: b[0].toInt(),
            y0: b[1].toInt(),
            x1: b[2].toInt(),
            y1: b[3].toInt(),
            score: 1,
          );
          final cb = cropBoxWithMargin(box, frame.width, frame.height);
          final prepared = prepareCropInput(cropRegion(frame, cb));
          final ref = img.decodeImage(
            File('$_dir/crop_input_${k}_$j.png').readAsBytesSync(),
          )!;
          final refBytes = ref.getBytes(order: img.ChannelOrder.rgb);
          var total = 0.0;
          for (var i = 0; i < prepared.length; i++) {
            total += (prepared[i] - refBytes[i].toDouble()).abs();
          }
          final meanAbs = total / prepared.length;
          // ignore: avoid_print
          print(
            'crop $k/$j mean abs pixel diff: ${meanAbs.toStringAsFixed(4)}',
          );
          expect(meanAbs, lessThanOrEqualTo(2.0));
        }
      });
    }
  });

  group('white-spot score and not_fish', () {
    for (final k in [1, 2, 3]) {
      test('frame $k matches the saved probs', () {
        for (final raw in _crops(k)) {
          final entry = raw as Map<String, dynamic>;
          if (entry['too_small'] == true) continue;
          final probs = (entry['probs'] as List)
              .map((v) => (v as num).toDouble())
              .toList();
          expect(
            whiteSpotScoreFrom(probs, _labels),
            closeTo((entry['white_spot_score'] as num).toDouble(), 1e-6),
          );
          expect(isNotFishFrom(probs, _labels), entry['not_fish']);
        }
      });
    }

    test('not_fish argmax rule', () {
      expect(isNotFishFrom([0.1, 0.8, 0.1], _labels), isTrue);
      expect(isNotFishFrom([0.1, 0.2, 0.7], _labels), isFalse);
      // renormalised score ignores the not_fish mass
      expect(whiteSpotScoreFrom([0.2, 0.5, 0.6], _labels), closeTo(0.75, 1e-9));
    });
  });
}
