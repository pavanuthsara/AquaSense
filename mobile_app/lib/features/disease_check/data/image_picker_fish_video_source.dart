import 'package:image_picker/image_picker.dart';

import '../domain/fish_video_source.dart';
import '../domain/picked_video.dart';
import '../domain/video_check_settings.dart';

/// Records and picks videos with `image_picker`. Clips are capped at
/// [videoMaxDuration] at the source.
class ImagePickerFishVideoSource implements FishVideoSource {
  ImagePickerFishVideoSource({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<PickedVideo?> recordVideo() => _pick(ImageSource.camera);

  @override
  Future<PickedVideo?> pickVideo() => _pick(ImageSource.gallery);

  Future<PickedVideo?> _pick(ImageSource source) async {
    final file = await _picker.pickVideo(
      source: source,
      maxDuration: videoMaxDuration,
    );
    return file == null ? null : PickedVideo(path: file.path);
  }
}
