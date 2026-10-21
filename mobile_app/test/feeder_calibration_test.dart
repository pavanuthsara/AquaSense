import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/facility/domain/feeder_calibration.dart';

void main() {
  final calibration = FeederCalibration(
    id: 'calibration-1',
    version: 1,
    unitsPerFish: 0.1,
    minimumUnits: 1,
    maximumUnits: 5,
    createdAt: DateTime.utc(2026, 10, 20),
  );

  test('portion calculation applies identical bounded feeder-unit rules', () {
    final minimum = calculatePortionPreview(
      calibration: calibration,
      fishCount: 1,
    );
    final normal = calculatePortionPreview(
      calibration: calibration,
      fishCount: 20,
    );
    final maximum = calculatePortionPreview(
      calibration: calibration,
      fishCount: 80,
    );
    final zero = calculatePortionPreview(
      calibration: calibration,
      fishCount: 0,
    );

    expect(minimum.rawUnits, 0.1);
    expect(minimum.portionUnits, 1);
    expect(minimum.limit, PortionLimit.minimum);
    expect(normal.portionUnits, 2);
    expect(normal.limit, PortionLimit.none);
    expect(maximum.portionUnits, 5);
    expect(maximum.limit, PortionLimit.maximum);
    expect(zero.portionUnits, 0);
    expect(zero.limit, PortionLimit.zeroFish);
  });
}
