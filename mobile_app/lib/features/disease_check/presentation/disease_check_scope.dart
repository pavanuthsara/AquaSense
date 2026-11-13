import 'package:flutter/widgets.dart';

import '../domain/disease_check_repository.dart';
import '../domain/disease_classifier.dart';
import '../domain/fish_crop_classifier.dart';
import '../domain/fish_detector.dart';
import '../domain/fish_photo_source.dart';
import '../domain/fish_video_source.dart';
import '../domain/video_frame_extractor.dart';

/// Makes the disease-check parts available to every screen below it.
class DiseaseCheckScope extends InheritedWidget {
  const DiseaseCheckScope({
    required this.classifier,
    required this.repository,
    required this.photoSource,
    required this.fishDetector,
    required this.fishCropClassifier,
    required this.videoSource,
    required this.frameExtractor,
    required super.child,
    super.key,
  });

  final DiseaseClassifier classifier;
  final DiseaseCheckRepository repository;
  final FishPhotoSource photoSource;
  final FishDetector fishDetector;
  final FishCropClassifier fishCropClassifier;
  final FishVideoSource videoSource;
  final VideoFrameExtractor frameExtractor;

  static DiseaseCheckScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<DiseaseCheckScope>();
    assert(scope != null, 'DiseaseCheckScope was not found.');
    return scope!;
  }

  @override
  bool updateShouldNotify(DiseaseCheckScope oldWidget) {
    return classifier != oldWidget.classifier ||
        repository != oldWidget.repository ||
        photoSource != oldWidget.photoSource ||
        fishDetector != oldWidget.fishDetector ||
        fishCropClassifier != oldWidget.fishCropClassifier ||
        videoSource != oldWidget.videoSource ||
        frameExtractor != oldWidget.frameExtractor;
  }
}
