import 'tank.dart';

enum AppetiteCheckStatus {
  pending,
  checking,
  completed,
  insufficientData,
  failed,
  timedOut,
}

class AppetiteCheck {
  const AppetiteCheck({
    required this.id,
    required this.tankId,
    required this.status,
    required this.requestedAt,
    required this.expiresAt,
    this.appetiteResult,
    this.confidence,
    this.observedAt,
    this.modelVersion,
    this.message,
  });

  final String id;
  final String tankId;
  final AppetiteCheckStatus status;
  final DateTime requestedAt;
  final DateTime expiresAt;
  final AppetiteResult? appetiteResult;
  final double? confidence;
  final DateTime? observedAt;
  final String? modelVersion;
  final String? message;

  bool get isActive =>
      status == AppetiteCheckStatus.pending ||
      status == AppetiteCheckStatus.checking;

  factory AppetiteCheck.fromJson(Map<String, dynamic> json) {
    return AppetiteCheck(
      id: json['id'] as String,
      tankId: json['tankId'] as String,
      status: switch (json['status']) {
        'PENDING' => AppetiteCheckStatus.pending,
        'CHECKING' => AppetiteCheckStatus.checking,
        'COMPLETED' => AppetiteCheckStatus.completed,
        'INSUFFICIENT_DATA' => AppetiteCheckStatus.insufficientData,
        'FAILED' => AppetiteCheckStatus.failed,
        'TIMED_OUT' => AppetiteCheckStatus.timedOut,
        _ => throw const FormatException('Unknown appetite check status'),
      },
      requestedAt: DateTime.parse(json['requestedAt'] as String),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      appetiteResult: switch (json['appetiteResult']) {
        'HIGH' => AppetiteResult.high,
        'LOW' => AppetiteResult.low,
        null => null,
        _ => throw const FormatException('Unknown appetite label'),
      },
      confidence: (json['confidence'] as num?)?.toDouble(),
      observedAt: json['observedAt'] == null
          ? null
          : DateTime.parse(json['observedAt'] as String),
      modelVersion: json['modelVersion'] as String?,
      message: json['message'] as String?,
    );
  }
}
