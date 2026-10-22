import 'package:mobile_app/features/disease_check/domain/decoded_frame.dart';
import 'package:mobile_app/features/disease_check/domain/fish_box.dart';
import 'package:mobile_app/features/disease_check/domain/fish_detector.dart';

/// Returns the same preset boxes for every frame.
class FakeFishDetector implements FishDetector {
  FakeFishDetector(this.boxes);

  final List<FishBox> boxes;
  bool disposed = false;

  @override
  Future<List<FishBox>> detect(DecodedFrame frame) async => boxes;

  @override
  Future<void> dispose() async => disposed = true;
}
