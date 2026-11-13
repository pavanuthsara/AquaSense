import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/disease_check/data/tflite_disease_classifier.dart';

void main() {
  test('float output bytes become scores', () {
    final bytes = Float32List.fromList([0.25, 0.75]).buffer.asUint8List();

    expect(scoresFromOutputBytes(bytes, isFloat: true), [0.25, 0.75]);
  });

  test('quantised output uses scale and zero point', () {
    final bytes = Uint8List.fromList([0, 255]);

    final scores = scoresFromOutputBytes(
      bytes,
      isFloat: false,
      scale: 1 / 255,
      zeroPoint: 0,
    );

    expect(scores[0], 0);
    expect(scores[1], closeTo(1, 1e-9));
  });
}
