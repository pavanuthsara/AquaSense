/// Fixed numbers for the video white-spot check.
///
/// Every value here mirrors a constant in the research project's reference
/// script `video_check/check_video.py`. The Dart video pipeline must give the
/// same answers as that script, so do not change a number here without
/// changing it there (and re-generating the parity fixtures in DIS-012).
///
/// See also [[disease_prediction]] for the photo-mode constants.
library;

/// Margin added around a detected fish before it is cropped for the white-spot
/// model, as a fraction of the box size. `PAD` in check_video.py.
const double videoCropPadFraction = 0.12;

/// A fish score at or above this is "white spot"; at or below `1 - this` it is
/// "healthy"; in between it is "not sure". `SURE` in check_video.py.
const double videoSureThreshold = 0.6;

/// Boxes whose shorter side (in real video pixels) is below this are too small
/// to judge for spots. `MIN_FISH_PX` in check_video.py.
const int videoMinFishPixels = 48;

/// A fish needs at least this many scored frames before it gets an answer.
/// `MIN_FRAMES` in check_video.py.
const int videoMinFrames = 3;

/// Minimum detector box score kept before non-max suppression. `conf=0.4` on
/// `FishFinder` in check_video.py.
const double fishFinderConfidence = 0.4;

/// Non-max-suppression IoU threshold for the fish finder. The second threshold
/// passed to `cv2.dnn.NMSBoxes(..., 0.5)` in check_video.py.
const double fishFinderNmsIou = 0.5;

/// Frames checked per second of video. `--fps` default in check_video.py.
const double videoFramesPerSecond = 2.0;

/// Longest span of a clip the app checks. Clips are trimmed to this.
const Duration videoMaxDuration = Duration(seconds: 30);

/// Two boxes in neighbouring checked frames are the same fish when their IoU is
/// above this. First test in `same_fish` in check_video.py.
const double sameFishIouThreshold = 0.2;

/// ...or when their centres are closer than this fraction of the larger box
/// dimension. Second test in `same_fish` in check_video.py.
const double sameFishCentreFraction = 0.75;

/// A track may only match a box within this many checked frames of its last
/// sighting. `n_checked - tr["last"] <= 3` in check_video.py.
const int trackMaxFrameGap = 3;

/// Square input side of the fish-finder model (NCHW, 512x512).
const int fishFinderInputSize = 512;

/// Grey letterbox padding value for the fish-finder input. `114` in
/// check_video.py.
const int fishFinderPadValue = 114;

/// Square input side of the white-spot crop model (NHWC, 224x224).
const int fishCropInputSize = 224;
