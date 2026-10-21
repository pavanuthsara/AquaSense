enum FeedingSource { scheduled, manual }

enum FeedingOutcome {
  processing,
  commandSent,
  delivered,
  skippedLowAppetite,
  skippedLowConfidence,
  skippedStaleObservation,
  skippedCountInconsistent,
  blockedAutomation,
  blockedCooldown,
  blockedUnhealthyDevice,
  blockedCalibration,
  failed,
}

class UpcomingFeedingSession {
  const UpcomingFeedingSession({
    required this.tankId,
    required this.tankName,
    required this.scheduledFor,
    this.groupId,
    this.groupName,
  });

  final String tankId;
  final String tankName;
  final String? groupId;
  final String? groupName;
  final DateTime scheduledFor;
}

class UnhealthyTankDevice {
  const UnhealthyTankDevice({
    required this.tankId,
    required this.tankName,
    required this.type,
    required this.state,
    this.lastHeartbeatAt,
  });

  final String tankId;
  final String tankName;
  final String type;
  final String state;
  final DateTime? lastHeartbeatAt;
}

class FeedingHistoryItem {
  const FeedingHistoryItem({
    required this.id,
    required this.tankId,
    required this.tankName,
    required this.scheduledFor,
    required this.source,
    required this.outcome,
    this.groupId,
    this.groupName,
    this.portionUnits,
    this.commandSentAt,
    this.feedbackAt,
    this.reason,
  });

  final String id;
  final String tankId;
  final String tankName;
  final String? groupId;
  final String? groupName;
  final DateTime scheduledFor;
  final FeedingSource source;
  final FeedingOutcome outcome;
  final double? portionUnits;
  final DateTime? commandSentAt;
  final DateTime? feedbackAt;
  final String? reason;
}

class FeedingHistoryPage {
  const FeedingHistoryPage({required this.items, this.nextCursor});

  final List<FeedingHistoryItem> items;
  final String? nextCursor;
}

class FeedingDashboard {
  const FeedingDashboard({
    required this.generatedAt,
    required this.totalTanks,
    required this.automatedTanks,
    required this.upcomingCount,
    required this.pendingCommands,
    required this.delivered,
    required this.skipped,
    required this.blocked,
    required this.failed,
    required this.unhealthyDeviceCount,
    required this.upcoming,
    required this.unhealthyDevices,
    required this.recentSessions,
  });

  final DateTime generatedAt;
  final int totalTanks;
  final int automatedTanks;
  final int upcomingCount;
  final int pendingCommands;
  final int delivered;
  final int skipped;
  final int blocked;
  final int failed;
  final int unhealthyDeviceCount;
  final List<UpcomingFeedingSession> upcoming;
  final List<UnhealthyTankDevice> unhealthyDevices;
  final List<FeedingHistoryItem> recentSessions;
}
