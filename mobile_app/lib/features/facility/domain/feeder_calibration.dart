enum PortionLimit { notConfigured, none, minimum, maximum, zeroFish }

class FeederCalibration {
  const FeederCalibration({
    required this.id,
    required this.version,
    required this.unitsPerFish,
    required this.minimumUnits,
    required this.maximumUnits,
    required this.createdAt,
  });

  final String id;
  final int version;
  final double unitsPerFish;
  final double minimumUnits;
  final double maximumUnits;
  final DateTime createdAt;
}

class FeederCalibrationDraft {
  const FeederCalibrationDraft({
    required this.unitsPerFish,
    required this.minimumUnits,
    required this.maximumUnits,
  });

  final double unitsPerFish;
  final double minimumUnits;
  final double maximumUnits;
}

class PortionPreview {
  const PortionPreview({
    required this.configured,
    required this.fishCount,
    required this.limit,
    this.calibration,
    this.rawUnits,
    this.portionUnits,
  });

  final bool configured;
  final int fishCount;
  final FeederCalibration? calibration;
  final double? rawUnits;
  final double? portionUnits;
  final PortionLimit limit;
}

PortionPreview calculatePortionPreview({
  required FeederCalibration? calibration,
  required int fishCount,
}) {
  if (calibration == null) {
    return PortionPreview(
      configured: false,
      fishCount: fishCount,
      limit: PortionLimit.notConfigured,
    );
  }
  final rawScaled = _scaled(calibration.unitsPerFish) * fishCount;
  final minimumScaled = _scaled(calibration.minimumUnits);
  final maximumScaled = _scaled(calibration.maximumUnits);
  final raw = _unscaled(rawScaled);
  if (fishCount == 0) {
    return PortionPreview(
      configured: true,
      fishCount: fishCount,
      calibration: calibration,
      rawUnits: raw,
      portionUnits: 0,
      limit: PortionLimit.zeroFish,
    );
  }
  if (rawScaled < minimumScaled) {
    return PortionPreview(
      configured: true,
      fishCount: fishCount,
      calibration: calibration,
      rawUnits: raw,
      portionUnits: _unscaled(minimumScaled),
      limit: PortionLimit.minimum,
    );
  }
  if (rawScaled > maximumScaled) {
    return PortionPreview(
      configured: true,
      fishCount: fishCount,
      calibration: calibration,
      rawUnits: raw,
      portionUnits: _unscaled(maximumScaled),
      limit: PortionLimit.maximum,
    );
  }
  return PortionPreview(
    configured: true,
    fishCount: fishCount,
    calibration: calibration,
    rawUnits: raw,
    portionUnits: raw,
    limit: PortionLimit.none,
  );
}

int _scaled(double value) => (value * 10000).round();

double _unscaled(int value) => value / 10000;
