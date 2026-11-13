import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_app/features/disease_check/data/detection_decoder.dart';
import 'package:mobile_app/features/disease_check/data/detector_preprocessor.dart';
import 'package:mobile_app/features/disease_check/domain/decoded_frame.dart';

const _dir = 'test/fixtures/video_parity';

DecodedFrame _frame(int k) {
  final image = img.decodeImage(File('$_dir/frame_$k.png').readAsBytesSync())!;
  final rgb = image.getBytes(order: img.ChannelOrder.rgb);
  return DecodedFrame(
    width: image.width,
    height: image.height,
    rgb: Uint8List.fromList(rgb),
    timeMs: 0,
  );
}

Float32List _binFloats(int k) {
  final bytes = File('$_dir/det_output_$k.bin').readAsBytesSync();
  return Float32List.view(Uint8List.fromList(bytes).buffer);
}

List<dynamic> _json(String name) =>
    jsonDecode(File('$_dir/$name').readAsStringSync()) as List<dynamic>;

void main() {
  group('prepareDetectorInput matches the Python letterbox', () {
    for (final k in [1, 2, 3]) {
      test('frame $k mean abs pixel diff <= 2.0', () {
        final prepared = prepareDetectorInput(_frame(k));
        final ref = img.decodeImage(
          File('$_dir/det_input_$k.png').readAsBytesSync(),
        )!;
        expect(ref.width, 512);
        final refBytes = ref.getBytes(order: img.ChannelOrder.rgb);
        const plane = 512 * 512;

        var total = 0.0;
        for (var y = 0; y < 512; y++) {
          for (var x = 0; x < 512; x++) {
            final pixel = y * 512 + x;
            for (var c = 0; c < 3; c++) {
              final dart = prepared[c * plane + pixel] * 255.0;
              final refValue = refBytes[pixel * 3 + c].toDouble();
              total += (dart - refValue).abs();
            }
          }
        }
        final meanAbs = total / (3 * plane);
        // ignore: avoid_print
        print('frame $k mean abs pixel diff: ${meanAbs.toStringAsFixed(4)}');
        expect(meanAbs, lessThanOrEqualTo(2.0));
      });
    }

    test('grey letterbox padding is placed like Python', () {
      // frame 1 is 720x1280 -> s=0.4, nw=288, nh=512, left=112, top=0.
      final prepared = prepareDetectorInput(_frame(1));
      const plane = 512 * 512;
      double value(int x, int y, int c) =>
          prepared[c * plane + y * 512 + x] * 255.0;
      // Left bar column is grey 114, centre column is not.
      expect(value(10, 256, 0), closeTo(114, 1.5));
      expect(value(500, 256, 0), closeTo(114, 1.5));
      expect(value(256, 256, 0), isNot(closeTo(114, 1.5)));
    });
  });

  group('decodeDetections matches boxes_k.json', () {
    for (final k in [1, 2, 3]) {
      test('frame $k boxes within 1 px', () {
        final frame = _frame(k);
        final boxes = decodeDetections(
          _binFloats(k),
          frame.width,
          frame.height,
        );
        final expected = _json('boxes_$k.json');
        expect(boxes.length, expected.length);
        for (var i = 0; i < boxes.length; i++) {
          final e = (expected[i] as List).cast<num>();
          expect(
            (boxes[i].x0 - e[0]).abs(),
            lessThanOrEqualTo(1),
            reason: 'x0',
          );
          expect(
            (boxes[i].y0 - e[1]).abs(),
            lessThanOrEqualTo(1),
            reason: 'y0',
          );
          expect(
            (boxes[i].x1 - e[2]).abs(),
            lessThanOrEqualTo(1),
            reason: 'x1',
          );
          expect(
            (boxes[i].y1 - e[3]).abs(),
            lessThanOrEqualTo(1),
            reason: 'y1',
          );
          expect(boxes[i].score, closeTo(e[4].toDouble(), 1e-4));
        }
      });
    }
  });

  group('non-max suppression', () {
    test('drops a lower-scoring box that overlaps a kept one', () {
      final rects = [
        [0.0, 0.0, 10.0, 10.0],
        [1.0, 1.0, 10.0, 10.0], // ~0.68 IoU with the first
      ];
      final kept = nonMaxSuppression(rects, [0.9, 0.8], 0.5);
      expect(kept, [0]);
    });

    test('keeps boxes that do not overlap', () {
      final rects = [
        [0.0, 0.0, 10.0, 10.0],
        [100.0, 100.0, 10.0, 10.0],
      ];
      final kept = nonMaxSuppression(rects, [0.5, 0.9], 0.5);
      expect(kept.toSet(), {0, 1});
      expect(kept.first, 1); // score order: higher first
    });

    test('keeps a box whose IoU is below the threshold', () {
      final rects = [
        [0.0, 0.0, 10.0, 10.0],
        [8.0, 0.0, 10.0, 10.0], // IoU = 2/18 = 0.111 < 0.5
      ];
      final kept = nonMaxSuppression(rects, [0.9, 0.8], 0.5);
      expect(kept.toSet(), {0, 1});
    });

    test('rectIou is 0 for disjoint boxes', () {
      expect(rectIou([0, 0, 5, 5], [100, 100, 5, 5]), 0.0);
    });
  });
}
