import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../domain/decoded_frame.dart';
import '../domain/disease_classifier.dart';
import '../domain/fish_crop_classifier.dart';
import 'crop_preprocessor.dart';

/// Runs the bundled 3-class white-spot model on one fish crop.
///
/// Loaded lazily on the first crop. The letterbox runs in a background isolate;
/// only the native `invoke` runs on the calling isolate.
class TfliteFishCropClassifier implements FishCropClassifier {
  TfliteFishCropClassifier({
    this.modelAsset = 'assets/models/guppy_video_model.tflite',
    this.labelsAsset = 'assets/models/guppy_video_labels.txt',
    AssetBundle? assetBundle,
  }) : _assetBundle = assetBundle ?? rootBundle;

  final String modelAsset;
  final String labelsAsset;
  final AssetBundle _assetBundle;

  Interpreter? _interpreter;
  List<String>? _labels;
  Future<void>? _loading;

  Future<void> _ensureLoaded() {
    return _loading ??= _load().catchError((Object error) {
      _loading = null;
      throw error is DiseaseClassifierException
          ? error
          : const DiseaseClassifierException(
              'The white-spot model could not be loaded on this phone.',
              code: 'crop_model_load_failed',
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

    final outputs = interpreter.getOutputTensor(0).shape.last;
    if (outputs != labels.length) {
      interpreter.close();
      throw DiseaseClassifierException(
        'The video model gives $outputs answers but the labels file has '
        '${labels.length}.',
        code: 'crop_labels_mismatch',
      );
    }
    _interpreter = interpreter;
    _labels = labels;
  }

  @override
  Future<FishCropResult> classify(DecodedFrame crop) async {
    await _ensureLoaded();
    final interpreter = _interpreter!;
    final input = interpreter.getInputTensor(0);
    if (input.type != TensorType.float32) {
      throw DiseaseClassifierException(
        'The video model expects ${input.type.name} input, which is not '
        'supported.',
        code: 'crop_unsupported_model',
      );
    }

    final prepared = await compute(prepareCropInput, crop);
    final output = interpreter.getOutputTensor(0);
    try {
      input.data = prepared.buffer.asUint8List(
        prepared.offsetInBytes,
        prepared.lengthInBytes,
      );
      interpreter.invoke();
    } on Object {
      throw const DiseaseClassifierException(
        'The white-spot model could not check this fish.',
        code: 'crop_inference_failed',
      );
    }

    final copy = Uint8List.fromList(output.data);
    final probs = Float32List.view(copy.buffer).toList(growable: false);
    final labels = _labels!;
    return FishCropResult(
      whiteSpotScore: whiteSpotScoreFrom(probs, labels),
      isNotFish: isNotFishFrom(probs, labels),
      probs: probs,
    );
  }

  @override
  Future<void> dispose() async {
    _interpreter?.close();
    _interpreter = null;
    _loading = null;
  }
}
