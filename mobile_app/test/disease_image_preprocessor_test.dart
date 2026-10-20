import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_app/features/disease_check/data/image_preprocessor.dart';
import 'package:mobile_app/features/disease_check/domain/disease_classifier.dart';

Uint8List whitePng(int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  return img.encodePng(image);
}

/// Red, green and blue of pixel (x, y) in a prepared tensor.
List<num> pixelAt(List<num> data, int size, int x, int y) {
  final i = (y * size + x) * 3;
  return [data[i], data[i + 1], data[i + 2]];
}

void main() {
  const size = 32;

  test('a wide photo gets black bars above and below', () {
    final data =
        prepareImageForModel(
              ImagePreparationRequest(imageBytes: whitePng(64, 32), size: size),
            )
            as Float32List;

    expect(data.length, size * size * 3);
    expect(pixelAt(data, size, 16, 0), [0, 0, 0]);
    expect(pixelAt(data, size, 16, size - 1), [0, 0, 0]);
    expect(pixelAt(data, size, 16, 16), [255, 255, 255]);
    expect(pixelAt(data, size, 0, 16), [255, 255, 255]);
  });

  test('a tall photo gets black bars left and right', () {
    final data =
        prepareImageForModel(
              ImagePreparationRequest(imageBytes: whitePng(32, 64), size: size),
            )
            as Float32List;

    expect(pixelAt(data, size, 0, 16), [0, 0, 0]);
    expect(pixelAt(data, size, size - 1, 16), [0, 0, 0]);
    expect(pixelAt(data, size, 16, 16), [255, 255, 255]);
    expect(pixelAt(data, size, 16, 0), [255, 255, 255]);
  });

  test('values stay between 0 and 255 and are not divided by 255', () {
    final data =
        prepareImageForModel(
              ImagePreparationRequest(imageBytes: whitePng(40, 40), size: size),
            )
            as Float32List;

    expect(data.reduce((a, b) => a > b ? a : b), 255);
    expect(data.every((v) => v >= 0 && v <= 255), isTrue);
  });

  test('uint8 models get a byte list', () {
    final data = prepareImageForModel(
      ImagePreparationRequest(
        imageBytes: whitePng(40, 20),
        size: size,
        asFloat: false,
      ),
    );

    expect(data, isA<Uint8List>());
    expect((data as Uint8List).length, size * size * 3);
  });

  test('a corrupt file gives a clear error', () {
    expect(
      () => prepareImageForModel(
        ImagePreparationRequest(
          imageBytes: Uint8List.fromList([1, 2, 3, 4]),
          size: size,
        ),
      ),
      throwsA(
        isA<DiseaseClassifierException>().having(
          (e) => e.code,
          'code',
          'unreadable_image',
        ),
      ),
    );
  });
}
