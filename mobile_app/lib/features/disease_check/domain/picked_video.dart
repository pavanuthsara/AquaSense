/// A video the user recorded or chose, ready to be checked.
class PickedVideo {
  const PickedVideo({required this.path});

  /// Local file path of the video on the device.
  final String path;
}
