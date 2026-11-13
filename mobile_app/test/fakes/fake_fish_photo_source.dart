import 'dart:typed_data';

import 'package:mobile_app/features/disease_check/domain/fish_photo_source.dart';

/// Returns [photo] (or null, like a cancelled picker) without any platform UI.
class FakeFishPhotoSource implements FishPhotoSource {
  FakeFishPhotoSource({this.photo, this.error});

  Uint8List? photo;
  Object? error;
  int cameraCalls = 0;
  int galleryCalls = 0;

  @override
  Future<Uint8List?> takePhoto() async {
    cameraCalls += 1;
    if (error != null) {
      throw error!;
    }
    return photo;
  }

  @override
  Future<Uint8List?> pickFromGallery() async {
    galleryCalls += 1;
    if (error != null) {
      throw error!;
    }
    return photo;
  }
}
