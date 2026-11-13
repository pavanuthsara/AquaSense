import 'package:flutter/foundation.dart';

import '../domain/disease_classifier.dart';
import '../domain/disease_prediction.dart';
import '../domain/fish_photo_source.dart';

enum DiseaseCheckStage { start, checking, result, error }

/// Holds the state of one disease check: photo, model answer, or error.
class DiseaseCheckController extends ChangeNotifier {
  DiseaseCheckController({
    required DiseaseClassifier classifier,
    required FishPhotoSource photoSource,
  }) : _classifier = classifier,
       _photoSource = photoSource;

  final DiseaseClassifier _classifier;
  final FishPhotoSource _photoSource;

  DiseaseCheckStage _stage = DiseaseCheckStage.start;
  Uint8List? _photo;
  DiseasePrediction? _prediction;
  String? _errorMessage;
  bool _disposed = false;

  DiseaseCheckStage get stage => _stage;
  Uint8List? get photo => _photo;
  DiseasePrediction? get prediction => _prediction;
  String? get errorMessage => _errorMessage;

  Future<void> takePhoto() => _checkFrom(_photoSource.takePhoto);

  Future<void> pickFromGallery() => _checkFrom(_photoSource.pickFromGallery);

  /// Runs the model again on the same photo, for example after an error.
  Future<void> retry() async {
    final photo = _photo;
    if (photo == null) {
      reset();
      return;
    }
    await _classify(photo);
  }

  /// Goes back to the start to check another fish.
  void reset() {
    _stage = DiseaseCheckStage.start;
    _photo = null;
    _prediction = null;
    _errorMessage = null;
    _notify();
  }

  Future<void> _checkFrom(Future<Uint8List?> Function() pick) async {
    if (_stage == DiseaseCheckStage.checking) {
      return;
    }
    final Uint8List? photo;
    try {
      photo = await pick();
    } on FishPhotoException catch (error) {
      _fail(error.message);
      return;
    }
    if (photo == null) {
      // The user cancelled; keep whatever was on screen.
      return;
    }
    _photo = photo;
    await _classify(photo);
  }

  Future<void> _classify(Uint8List photo) async {
    _stage = DiseaseCheckStage.checking;
    _prediction = null;
    _errorMessage = null;
    _notify();
    try {
      _prediction = await _classifier.classify(photo);
      _stage = DiseaseCheckStage.result;
      _notify();
    } on DiseaseClassifierException catch (error) {
      _fail(error.message);
    } on Object {
      _fail('Something went wrong while checking this photo.');
    }
  }

  void _fail(String message) {
    _stage = DiseaseCheckStage.error;
    _errorMessage = message;
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
