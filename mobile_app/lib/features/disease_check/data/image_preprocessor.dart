import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../domain/disease_classifier.dart';

/// What the model needs: a square image of [size] x [size] pixels.
class ImagePreparationRequest {
  const ImagePreparationRequest({
    required this.imageBytes,
    required this.size,
    this.asFloat = true,
  });

  /// The photo as JPEG or PNG bytes.
  final Uint8List imageBytes;
  final int size;

  /// True for a float32 model input, false for a uint8 one.
  final bool asFloat;
}

/// Prepares a photo exactly the way the training images were prepared.
///
/// This mirrors `ImageOps.pad(image, (size, size), color=(0, 0, 0))` in the
/// research project's `predict_pi.py`:
///
/// 1. Decode the photo and turn it upright using its EXIF rotation.
/// 2. Shrink it so the longer side equals [size], keeping its shape.
/// 3. Put it in the middle of a black square (letterboxing).
/// 4. Return the red, green and blue values of every pixel, row by row,
///    as numbers from 0 to 255. They are NOT divided by 255, because the
///    model does its own scaling.
///
/// The result is a [Float32List] or [Uint8List] of length size * size * 3.
/// It is a top-level function so it can run in a background isolate.
TypedData prepareImageForModel(ImagePreparationRequest request) {
  final decoded = img.decodeImage(request.imageBytes);
  if (decoded == null) {
    throw const DiseaseClassifierException(
      'This photo could not be opened. Try a different photo.',
      code: 'unreadable_image',
    );
  }
  final letterboxed = letterbox(decoded, request.size);

  final size = request.size;
  final bytes = Uint8List(size * size * 3);
  var index = 0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final pixel = letterboxed.getPixel(x, y);
      bytes[index++] = pixel.r.toInt();
      bytes[index++] = pixel.g.toInt();
      bytes[index++] = pixel.b.toInt();
    }
  }
  if (!request.asFloat) {
    return bytes;
  }
  final floats = Float32List(bytes.length);
  for (var i = 0; i < bytes.length; i++) {
    floats[i] = bytes[i].toDouble();
  }
  return floats;
}

/// Fits [image] inside a black [size] x [size] square, centred.
img.Image letterbox(img.Image image, int size) {
  final upright = img.bakeOrientation(image);
  final rgb = upright.numChannels == 3 && upright.format == img.Format.uint8
      ? upright
      : upright.convert(format: img.Format.uint8, numChannels: 3);

  // Same rounding as Pillow's ImageOps.contain.
  final double scale = rgb.width >= rgb.height
      ? size / rgb.width
      : size / rgb.height;
  final newWidth = (rgb.width * scale).round().clamp(1, size);
  final newHeight = (rgb.height * scale).round().clamp(1, size);

  final resized = img.copyResize(
    rgb,
    width: newWidth,
    height: newHeight,
    interpolation: img.Interpolation.cubic,
  );

  final square = img.Image(width: size, height: size, numChannels: 3);
  // Same centring as Pillow's ImageOps.pad.
  final left = ((size - newWidth) / 2).round();
  final top = ((size - newHeight) / 2).round();
  img.compositeImage(square, resized, dstX: left, dstY: top);
  return square;
}
