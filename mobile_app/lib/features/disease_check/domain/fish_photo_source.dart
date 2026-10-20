import 'dart:typed_data';

/// Where the fish photo comes from: the camera or the phone's gallery.
abstract interface class FishPhotoSource {
  /// Returns the photo's bytes, or null if the user cancelled.
  Future<Uint8List?> takePhoto();

  /// Returns the photo's bytes, or null if the user cancelled.
  Future<Uint8List?> pickFromGallery();
}

class FishPhotoException implements Exception {
  const FishPhotoException(this.message);

  final String message;

  @override
  String toString() => message;
}
