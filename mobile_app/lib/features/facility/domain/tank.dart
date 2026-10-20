enum TankStatus { active, paused, archived }

enum TankObservationState { noData, current, stale }

enum TankDeviceStatus { notConfigured, online, offline, stale, unhealthy }

enum TankScheduleMode { inherited, override }

class Tank {
  const Tank({
    required this.id,
    required this.facilityId,
    required this.name,
    required this.code,
    required this.expectedGuppyCount,
    required this.tags,
    required this.automationEnabled,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.scheduleMode = TankScheduleMode.inherited,
    this.detectedGuppyCount,
    this.detectionConfidence,
    this.countObservedAt,
    this.groupId,
    this.groupName,
    this.notes,
    this.archivedAt,
  });

  final String id;
  final String facilityId;
  final String name;
  final String code;
  final int expectedGuppyCount;
  final int? detectedGuppyCount;
  final double? detectionConfidence;
  final DateTime? countObservedAt;
  final String? groupId;
  final String? groupName;
  final List<String> tags;
  final bool automationEnabled;
  final TankScheduleMode scheduleMode;
  final TankStatus status;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;

  Tank copyWith({
    String? name,
    String? code,
    int? expectedGuppyCount,
    String? groupId,
    bool clearGroup = false,
    String? groupName,
    List<String>? tags,
    bool? automationEnabled,
    TankScheduleMode? scheduleMode,
    TankStatus? status,
    String? notes,
    DateTime? updatedAt,
    DateTime? archivedAt,
  }) {
    return Tank(
      id: id,
      facilityId: facilityId,
      name: name ?? this.name,
      code: code ?? this.code,
      expectedGuppyCount: expectedGuppyCount ?? this.expectedGuppyCount,
      detectedGuppyCount: detectedGuppyCount,
      detectionConfidence: detectionConfidence,
      countObservedAt: countObservedAt,
      groupId: clearGroup ? null : groupId ?? this.groupId,
      groupName: clearGroup ? null : groupName ?? this.groupName,
      tags: tags ?? this.tags,
      automationEnabled: automationEnabled ?? this.automationEnabled,
      scheduleMode: scheduleMode ?? this.scheduleMode,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      archivedAt: archivedAt ?? this.archivedAt,
    );
  }
}

class TankDraft {
  const TankDraft({
    required this.name,
    required this.code,
    required this.expectedGuppyCount,
    required this.tags,
    required this.automationEnabled,
    required this.notes,
    this.groupId,
  });

  final String name;
  final String code;
  final int expectedGuppyCount;
  final String? groupId;
  final List<String> tags;
  final bool automationEnabled;
  final String notes;
}

class TankPage {
  const TankPage({
    required this.items,
    required this.page,
    required this.size,
    required this.totalItems,
    required this.totalPages,
  });

  final List<Tank> items;
  final int page;
  final int size;
  final int totalItems;
  final int totalPages;

  bool get hasNextPage => page + 1 < totalPages;
}

class TankActivity {
  const TankActivity({
    required this.type,
    required this.title,
    required this.occurredAt,
  });

  final String type;
  final String title;
  final DateTime occurredAt;
}

class TankDetail {
  const TankDetail({
    required this.tank,
    required this.observationState,
    required this.deviceStatus,
    required this.feedingTimes,
    required this.recentActivity,
    this.scheduleMode = TankScheduleMode.inherited,
    this.inheritedFeedingTimes = const [],
    this.lastFeedingAt,
    this.nextFeedingAt,
  });

  final Tank tank;
  final TankObservationState observationState;
  final TankDeviceStatus deviceStatus;
  final TankScheduleMode scheduleMode;
  final List<String> inheritedFeedingTimes;
  final List<String> feedingTimes;
  final DateTime? lastFeedingAt;
  final DateTime? nextFeedingAt;
  final List<TankActivity> recentActivity;
}
