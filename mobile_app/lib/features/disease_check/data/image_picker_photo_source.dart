import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../domain/fish_photo_source.dart';

/// Gets a fish photo from the phone camera or gallery.
///
/// Photos are shrunk to at most [maxSide] pixels while they are picked. The
/// model only looks at a small square, and a full 12 MP photo would make the
/// check slow and use a lot of memory.
class ImagePickerPhotoSource implements FishPhotoSource {
  ImagePickerPhotoSource({ImagePicker? picker, this.maxSide = 1024})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;
  final double maxSide;

  @override
  Future<Uint8List?> takePhoto() => _pick(ImageSource.camera);

  @override
  Future<Uint8List?> pickFromGallery() => _pick(ImageSource.gallery);

  Future<Uint8List?> _pick(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: maxSide,
        maxHeight: maxSide,
        imageQuality: 92,
      );
      return file?.readAsBytes();
    } on PlatformException catch (error) {
      throw FishPhotoException(
        source == ImageSource.camera
            ? 'The camera could not be opened (${error.code}). Check that '
                  'AquaSense is allowed to use the camera.'
            : 'The gallery could not be opened (${error.code}).',
      );
    }
  }
}
