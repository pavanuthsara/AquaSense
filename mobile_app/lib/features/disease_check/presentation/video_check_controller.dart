import 'package:flutter/foundation.dart';

import '../data/video_check_runner.dart';
import '../domain/disease_classifier.dart';
import '../domain/fish_video_source.dart';
import '../domain/picked_video.dart';
import '../domain/video_check_result.dart';

enum VideoCheckStage { start, checking, result, error }

/// Holds the state of one video white-spot check.
class VideoCheckController extends ChangeNotifier {
  VideoCheckController({
    required VideoCheckRunner runner,
    required FishVideoSource videoSource,
  }) : _runner = runner,
       _videoSource = videoSource;

  final VideoCheckRunner _runner;
  final FishVideoSource _videoSource;

  VideoCheckStage _stage = VideoCheckStage.start;
  bool _closeUp = false;
  int _framesDone = 0;
  int _framesTotal = 0;
  VideoCheckResult? _result;
  String? _errorMessage;
  PickedVideo? _lastVideo;
  VideoCheckCancelToken? _cancel;
  bool _disposed = false;

  VideoCheckStage get stage => _stage;
  bool get closeUp => _closeUp;
  int get framesDone => _framesDone;
  int get framesTotal => _framesTotal;
  VideoCheckResult? get result => _result;
  String? get errorMessage => _errorMessage;

  set closeUp(bool value) {
    if (_stage == VideoCheckStage.checking || _closeUp == value) return;
    _closeUp = value;
    _notify();
  }

  Future<void> recordVideo() => _pickThenRun(_videoSource.recordVideo);

  Future<void> pickVideo() => _pickThenRun(_videoSource.pickVideo);

  /// Cancels a check in progress and goes back to the start.
  void cancel() {
    _cancel?.cancel();
  }

  void reset() {
    _stage = VideoCheckStage.start;
    _framesDone = 0;
    _framesTotal = 0;
    _result = null;
    _errorMessage = null;
    _notify();
  }

  Future<void> _pickThenRun(Future<PickedVideo?> Function() pick) async {
    if (_stage == VideoCheckStage.checking) return;
    final PickedVideo? video;
    try {
      video = await pick();
    } on Object {
      _fail('The video could not be opened. Try another one.');
      return;
    }
    if (video == null) return; // cancelled
    _lastVideo = video;
    await _run(video);
  }

  Future<void> _run(PickedVideo video) async {
    final cancel = VideoCheckCancelToken();
    _cancel = cancel;
    _stage = VideoCheckStage.checking;
    _framesDone = 0;
    _framesTotal = 0;
    _result = null;
    _errorMessage = null;
    _notify();
    try {
      final result = await _runner.run(
        video,
        closeUp: _closeUp,
        cancel: cancel,
        onProgress: (done, total) {
          _framesDone = done;
          _framesTotal = total;
          _notify();
        },
      );
      if (cancel.isCancelled) {
        reset();
        return;
      }
      _result = result;
      _stage = VideoCheckStage.result;
      _notify();
    } on DiseaseClassifierException catch (error) {
      _fail(error.message);
    } on Object {
      _fail('Something went wrong while checking this video.');
    }
  }

  /// Runs the check again on the last video, for example after an error.
  Future<void> retry() async {
    final video = _lastVideo;
    if (video == null) {
      reset();
      return;
    }
    await _run(video);
  }

  void _fail(String message) {
    _stage = VideoCheckStage.error;
    _errorMessage = message;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel();
    super.dispose();
  }
}
