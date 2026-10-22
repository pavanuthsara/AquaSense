import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../domain/decoded_frame.dart';
import '../domain/fish_box.dart';
import '../domain/video_check_settings.dart';

/// The crop rectangle around a fish, in video pixels (x1/y1 exclusive).
class CropBox {
  const CropBox(this.x0, this.y0, this.x1, this.y1);
  final int x0;
  final int y0;
  final int x1;
  final int y1;
  int get width => x1 - x0;
  int get height => y1 - y0;
}

/// The crop rectangle for a box, with a [videoCropPadFraction] margin, clamped
/// to the frame. Matches step 4 of check_video.py (Python `int()` truncates
/// toward zero).
CropBox cropBoxWithMargin(
  FishBox box,
  int frameWidth,
  int frameHeight, {
  double pad = videoCropPadFraction,
}) {
  final pw = box.width * pad;
  final ph = box.height * pad;
  return CropBox(
    math.max(0, (box.x0 - pw).truncate()),
    math.max(0, (box.y0 - ph).truncate()),
    math.min(frameWidth, (box.x1 + pw).truncate()),
    math.min(frameHeight, (box.y1 + ph).truncate()),
  );
}

/// Cuts [region] out of [frame] as its own [DecodedFrame].
DecodedFrame cropRegion(DecodedFrame frame, CropBox region) {
  final w = region.width;
  final h = region.height;
  final out = Uint8List(w * h * 3);
  var dst = 0;
  for (var y = 0; y < h; y++) {
    var src = ((region.y0 + y) * frame.width + region.x0) * 3;
    for (var x = 0; x < w; x++) {
      out[dst++] = frame.rgb[src++];
      out[dst++] = frame.rgb[src++];
      out[dst++] = frame.rgb[src++];
    }
  }
  return DecodedFrame(width: w, height: h, rgb: out, timeMs: frame.timeMs);
}

/// Prepares a fish crop for the white-spot model, exactly as
/// `SpotModel.__call__` does in check_video.py: scale so the longer side is
/// 224 (AREA resize), centre with FLOOR division on a BLACK 224x224 square,
/// RGB, float 0..255 (NOT divided by 255), channels last (NHWC).
///
/// This is deliberately NOT the photo-mode preprocessing (which uses cubic
/// resize and rounded centring). Top-level so it can run in an isolate.
Float32List prepareCropInput(DecodedFrame crop) {
  const size = fishCropInputSize;
  final source = img.Image.fromBytes(
    width: crop.width,
    height: crop.height,
    bytes: crop.rgb.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );

  final s = size / (crop.width > crop.height ? crop.width : crop.height);
  final nw = math.max(1, (crop.width * s).round());
  final nh = math.max(1, (crop.height * s).round());
  final left = (size - nw) ~/ 2;
  final top = (size - nh) ~/ 2;

  // cv2.INTER_AREA has no exact match in package:image; average is closest.
  final resized = img.copyResize(
    source,
    width: nw,
    height: nh,
    interpolation: img.Interpolation.average,
  );
  final square = img.Image(width: size, height: size, numChannels: 3); // black
  img.compositeImage(square, resized, dstX: left, dstY: top);

  final hwc = square.getBytes(order: img.ChannelOrder.rgb);
  final out = Float32List(size * size * 3);
  for (var i = 0; i < out.length; i++) {
    out[i] = hwc[i].toDouble();
  }
  return out;
}

/// White-spot score renormalised over the two fish classes only, matching
/// `spot = probs[white_spot] / (probs[white_spot] + probs[healthy])`.
double whiteSpotScoreFrom(List<double> probs, List<String> labels) {
  final spot = probs[labels.indexOf('white_spot')];
  final healthy = probs[labels.indexOf('healthy')];
  return spot / math.max(1e-6, spot + healthy);
}

/// True when the 3-class model's top answer is `not_fish`.
bool isNotFishFrom(List<double> probs, List<String> labels) {
  final notFish = labels.indexOf('not_fish');
  if (notFish < 0) return false;
  var argmax = 0;
  for (var i = 1; i < probs.length; i++) {
    if (probs[i] > probs[argmax]) argmax = i;
  }
  return argmax == notFish;
}
