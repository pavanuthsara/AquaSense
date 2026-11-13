import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../domain/disease_classifier.dart';
import '../domain/disease_prediction.dart';
import 'image_preprocessor.dart';

/// Runs the bundled guppy disease model on the phone.
///
/// The model is loaded the first time a photo is checked, so app start-up
/// stays fast and screens that never use it pay nothing.
class TfliteDiseaseClassifier implements DiseaseClassifier {
  TfliteDiseaseClassifier({
    this.modelAsset = 'assets/models/guppy_disease.tflite',
    this.labelsAsset = 'assets/models/guppy_disease_labels.txt',
    this.modelVersion = bundledModelVersion,
    AssetBundle? assetBundle,
  }) : _assetBundle = assetBundle ?? rootBundle;

  final String modelAsset;
  final String labelsAsset;
  final String modelVersion;
  final AssetBundle _assetBundle;

  Interpreter? _interpreter;
  List<String>? _labels;
  Future<void>? _loading;

  Future<void> _ensureLoaded() {
    return _loading ??= _load().catchError((Object error) {
      // Allow a later retry if loading failed.
      _loading = null;
      throw error is DiseaseClassifierException
          ? error
          : const DiseaseClassifierException(
              'The disease model could not be loaded on this phone.',
              code: 'model_load_failed',
            );
    });
  }

  Future<void> _load() async {
    final labelText = await _assetBundle.loadString(labelsAsset);
    final labels = labelText
        .split(RegExp(r'\s+'))
        .where((label) => label.isNotEmpty)
        .toList(growable: false);
    final modelData = await _assetBundle.load(modelAsset);
    final interpreter = Interpreter.fromBuffer(
      modelData.buffer.asUint8List(
        modelData.offsetInBytes,
        modelData.lengthInBytes,
      ),
      options: InterpreterOptions()..threads = 2,
    )..allocateTensors();

    final outputCount = interpreter.getOutputTensor(0).shape.last;
    if (outputCount != labels.length) {
      interpreter.close();
      throw DiseaseClassifierException(
        'The model gives $outputCount answers but the labels file has '
        '${labels.length}.',
        code: 'labels_mismatch',
      );
    }
    _interpreter = interpreter;
    _labels = labels;
  }

  @override
  Future<DiseasePrediction> classify(Uint8List imageBytes) async {
    await _ensureLoaded();
    final interpreter = _interpreter!;
    final input = interpreter.getInputTensor(0);
    final output = interpreter.getOutputTensor(0);

    // Input shape is [1, height, width, 3]. The model is square.
    final size = input.shape[1];
    final asFloat = input.type == TensorType.float32;
    if (!asFloat && input.type != TensorType.uint8) {
      throw DiseaseClassifierException(
        'The model expects ${input.type.name} input, which is not supported.',
        code: 'unsupported_model',
      );
    }

    // Decoding and resizing a photo is slow, so it runs off the UI thread.
    final prepared = await compute(
      prepareImageForModel,
      ImagePreparationRequest(
        imageBytes: imageBytes,
        size: size,
        asFloat: asFloat,
      ),
    );

    final stopwatch = Stopwatch()..start();
    try {
      input.data = prepared.buffer.asUint8List(
        prepared.offsetInBytes,
        prepared.lengthInBytes,
      );
      interpreter.invoke();
    } on Object {
      throw const DiseaseClassifierException(
        'The disease model could not check this photo.',
        code: 'inference_failed',
      );
    }
    stopwatch.stop();

    final scores = scoresFromOutputBytes(
      output.data,
      isFloat: output.type == TensorType.float32,
      scale: output.params.scale,
      zeroPoint: output.params.zeroPoint,
    );
    return DiseasePrediction.fromScores(
      labels: _labels!,
      scores: scores,
      modelVersion: modelVersion,
      inferenceTime: stopwatch.elapsed,
      checkedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> dispose() async {
    _interpreter?.close();
    _interpreter = null;
    _loading = null;
  }
}

/// Turns the model's raw output bytes into one score per label.
///
/// A float model already gives probabilities. A uint8 (quantised) model gives
/// whole numbers that are turned back into probabilities with
/// `(value - zeroPoint) * scale`, as `predict_pi.py` does.
@visibleForTesting
List<double> scoresFromOutputBytes(
  Uint8List bytes, {
  required bool isFloat,
  double scale = 1,
  int zeroPoint = 0,
}) {
  if (isFloat) {
    final copy = Uint8List.fromList(bytes);
    return Float32List.view(copy.buffer).toList(growable: false);
  }
  return [for (final value in bytes) (value - zeroPoint) * scale];
}
