import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../domain/decoded_frame.dart';
import '../domain/disease_classifier.dart';
import '../domain/fish_box.dart';
import '../domain/fish_detector.dart';
import '../domain/video_check_settings.dart';
import 'detection_decoder.dart';
import 'detector_preprocessor.dart';

/// Runs the bundled YOLO11n fish finder on the phone.
///
/// Loaded lazily on the first frame, so app start-up and photo mode pay
/// nothing. The heavy letterbox runs in a background isolate; only the native
/// `invoke` runs on the calling isolate.
class TfliteFishDetector implements FishDetector {
  TfliteFishDetector({
    this.modelAsset = 'assets/models/fish_detector.tflite',
    AssetBundle? assetBundle,
  }) : _assetBundle = assetBundle ?? rootBundle;

  final String modelAsset;
  final AssetBundle _assetBundle;

  Interpreter? _interpreter;
  int _outputRows = 0;
  int _outputCols = 0;
  Future<void>? _loading;

  Future<void> _ensureLoaded() {
    return _loading ??= _load().catchError((Object error) {
      _loading = null;
      throw error is DiseaseClassifierException
          ? error
          : const DiseaseClassifierException(
              'The fish finder could not be loaded on this phone.',
              code: 'fish_finder_load_failed',
            );
    });
  }

  Future<void> _load() async {
    final modelData = await _assetBundle.load(modelAsset);
    final interpreter = Interpreter.fromBuffer(
      modelData.buffer.asUint8List(
        modelData.offsetInBytes,
        modelData.lengthInBytes,
      ),
      options: InterpreterOptions()..threads = 4,
    )..allocateTensors();

    final input = interpreter.getInputTensor(0);
    final shape = input.shape; // expect [1, 3, 512, 512] (NCHW)
    final nchw = shape.length == 4 && shape[1] == 3;
    final size = nchw ? shape[2] : (shape.length == 4 ? shape[1] : 0);
    if (!nchw || size != fishFinderInputSize) {
      interpreter.close();
      throw DiseaseClassifierException(
        'The fish finder expects a $fishFinderInputSize NCHW input but the '
        'model is ${shape.join('x')}.',
        code: 'fish_finder_shape',
      );
    }

    // Output is [1, 5, N] (rows cx,cy,w,h,score) or the transpose [1, N, 5].
    final outShape = interpreter.getOutputTensor(0).shape;
    final a = outShape[outShape.length - 2];
    final b = outShape[outShape.length - 1];
    if (a != 5 && b != 5) {
      interpreter.close();
      throw DiseaseClassifierException(
        'The fish finder output ${outShape.join('x')} has no size-5 box axis.',
        code: 'fish_finder_output',
      );
    }
    _outputRows = a;
    _outputCols = b;
    _interpreter = interpreter;
  }

  @override
  Future<List<FishBox>> detect(DecodedFrame frame) async {
    await _ensureLoaded();
    final interpreter = _interpreter!;

    final prepared = await compute(prepareDetectorInput, frame);

    final output = interpreter.getOutputTensor(0);
    try {
      interpreter.getInputTensor(0).data = prepared.buffer.asUint8List(
        prepared.offsetInBytes,
        prepared.lengthInBytes,
      );
      interpreter.invoke();
    } on Object {
      throw const DiseaseClassifierException(
        'The fish finder could not check this frame.',
        code: 'fish_finder_inference_failed',
      );
    }

    final raw = _asFiveByN(output.data, output.type == TensorType.float32);
    return decodeDetections(raw, frame.width, frame.height);
  }

  /// Returns the model output flattened in `[5, N]` order, transposing the
  /// `[N, 5]` layout if the model emits it that way.
  Float32List _asFiveByN(Uint8List bytes, bool isFloat) {
    final copy = Uint8List.fromList(bytes);
    final flat = isFloat
        ? Float32List.view(copy.buffer)
        : Float32List.fromList([for (final v in bytes) v.toDouble()]);
    if (_outputRows == 5) return flat; // already [5, N]
    // Model gave [N, 5]: transpose to [5, N].
    final n = _outputCols == 5 ? _outputRows : flat.length ~/ 5;
    final out = Float32List(5 * n);
    for (var i = 0; i < n; i++) {
      for (var r = 0; r < 5; r++) {
        out[r * n + i] = flat[i * 5 + r];
      }
    }
    return out;
  }

  @override
  Future<void> dispose() async {
    _interpreter?.close();
    _interpreter = null;
    _loading = null;
  }
}
