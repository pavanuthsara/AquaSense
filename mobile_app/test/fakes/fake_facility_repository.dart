import 'package:mobile_app/features/facility/domain/facility.dart';
import 'package:mobile_app/features/facility/domain/facility_repository.dart';
import 'package:mobile_app/features/facility/domain/facility_team.dart';
import 'package:mobile_app/features/facility/domain/feeder_calibration.dart';
import 'package:mobile_app/features/facility/domain/feeding_monitoring.dart';
import 'package:mobile_app/features/facility/domain/tank_group.dart';
import 'package:mobile_app/features/facility/domain/tank.dart';

class FakeFacilityRepository implements FacilityRepository {
  FakeFacilityRepository({
    List<Facility>? facilities,
    List<FacilityInvitation>? invitations,
    Map<String, List<FacilityMember>>? members,
    Map<String, List<TankGroup>>? tankGroups,
    List<Tank>? tanks,
    Map<String, TankDetail>? tankDetails,
    Map<String, List<FeederCalibration>>? calibrations,
    Map<String, FeedingDashboard>? dashboards,
    Map<String, List<FeedingHistoryItem>>? feedingHistory,
    this.listError,
    this.createFailures = 0,
  }) : facilities = facilities ?? [],
       invitations = invitations ?? [],
       members = members ?? {},
       tankGroups = tankGroups ?? {},
       tanks = tanks ?? [],
       tankDetails = tankDetails ?? {},
       calibrations = calibrations ?? {},
       dashboards = dashboards ?? {},
       feedingHistory = feedingHistory ?? {};

  final List<Facility> facilities;
  final List<FacilityInvitation> invitations;
  final Map<String, List<FacilityMember>> members;
  final Map<String, List<TankGroup>> tankGroups;
  final List<Tank> tanks;
  final Map<String, TankDetail> tankDetails;
  final Map<String, List<FeederCalibration>> calibrations;
  final Map<String, FeedingDashboard> dashboards;
  final Map<String, List<FeedingHistoryItem>> feedingHistory;
  Object? listError;
  int createFailures;
  int listCalls = 0;
  int createCalls = 0;
  int getCalls = 0;
  int listTankGroupsCalls = 0;
  final List<String> creationKeys = [];
  final Set<String> inaccessibleFacilityIds = {};

  static Facility facility({
    String id = 'facility-1',
    String name = 'Test Aquarium',
    String timeZone = 'Asia/Colombo',
    FacilityRole role = FacilityRole.owner,
  }) {
    return Facility(
      id: id,
      name: name,
      timeZone: timeZone,
      role: role,
      createdAt: DateTime.utc(2026, 10, 15),
    );
  }

  @override
  Future<Facility> createFacility({
    required String name,
    required String timeZone,
    required String idempotencyKey,
  }) async {
    createCalls += 1;
    creationKeys.add(idempotencyKey);
    if (createFailures > 0) {
      createFailures -= 1;
      throw const FacilityException('Temporary setup failure.');
    }
    final existing = facilities.cast<Facility?>().firstWhere(
      (facility) => facility?.name == name && facility?.timeZone == timeZone,
      orElse: () => null,
    );
    if (existing != null) {
      return existing;
    }
    final created = facility(
      id: 'facility-${facilities.length + 1}',
      name: name,
      timeZone: timeZone,
    );
    facilities.add(created);
    return created;
  }

  @override
  Future<Facility> getFacility(String facilityId) async {
    getCalls += 1;
    if (inaccessibleFacilityIds.remove(facilityId)) {
      facilities.removeWhere((facility) => facility.id == facilityId);
      throw const FacilityException(
        'The aquarium is no longer available.',
        code: 'facility_not_found',
      );
    }
    return facilities.firstWhere(
      (facility) => facility.id == facilityId,
      orElse: () => throw const FacilityException(
        'The aquarium is no longer available.',
        code: 'facility_not_found',
      ),
    );
  }

  @override
  Future<List<Facility>> listFacilities() async {
    listCalls += 1;
    final error = listError;
    if (error != null) {
      throw error;
    }
    return List.unmodifiable(facilities);
  }

  @override
  Future<List<String>> listTimeZones() async => const [
    'Asia/Colombo',
    'Europe/London',
    'UTC',
  ];

  @override
  Future<Facility> acceptInvitation(String invitationId) async {
    final index = invitations.indexWhere((item) => item.id == invitationId);
    if (index == -1) {
      throw const FacilityException('Invitation not found.');
    }
    final invitation = invitations[index];
    invitations.removeAt(index);
    final existing = facilities.cast<Facility?>().firstWhere(
      (item) => item?.id == invitation.facilityId,
      orElse: () => null,
    );
    if (existing != null) {
      return existing;
    }
    final accepted = facility(
      id: invitation.facilityId,
      name: invitation.facilityName,
      role: FacilityRole.worker,
    );
    facilities.add(accepted);
    return accepted;
  }

  @override
  Future<FacilityInvitation> inviteWorker({
    required String facilityId,
    required String email,
  }) async {
    final aquarium = await getFacility(facilityId);
    final now = DateTime.now().toUtc();
    final invitation = FacilityInvitation(
      id: 'invitation-${invitations.length + 1}',
      facilityId: facilityId,
      facilityName: aquarium.name,
      email: email.trim().toLowerCase(),
      status: FacilityInvitationStatus.pending,
      expiresAt: now.add(const Duration(days: 7)),
      createdAt: now,
    );
    invitations.add(invitation);
    return invitation;
  }

  @override
  Future<List<FacilityInvitation>> listFacilityInvitations(
    String facilityId,
  ) async => List.unmodifiable(
    invitations.where((item) => item.facilityId == facilityId),
  );

  @override
  Future<List<FacilityMember>> listMembers(String facilityId) async =>
      List.unmodifiable(members[facilityId] ?? const []);

  @override
  Future<List<FacilityInvitation>> listMyPendingInvitations() async =>
      List.unmodifiable(
        invitations.where(
          (item) => item.status == FacilityInvitationStatus.pending,
        ),
      );

  @override
  Future<void> removeWorker({
    required String facilityId,
    required String membershipId,
  }) async {
    members[facilityId]?.removeWhere((item) => item.id == membershipId);
  }

  @override
  Future<void> revokeInvitation({
    required String facilityId,
    required String invitationId,
  }) async {
    final index = invitations.indexWhere(
      (item) => item.facilityId == facilityId && item.id == invitationId,
    );
    if (index != -1) {
      invitations[index] = invitations[index].copyWith(
        status: FacilityInvitationStatus.revoked,
      );
    }
  }

  @override
  Future<List<TankGroup>> listTankGroups(String facilityId) async {
    listTankGroupsCalls += 1;
    final result = List<TankGroup>.unmodifiable(
      tankGroups[facilityId] ?? const [],
    );
    return result;
  }

  @override
  Future<TankGroup> createTankGroup({
    required String facilityId,
    required String name,
  }) async {
    _requireOwner(facilityId);
    final groups = tankGroups.putIfAbsent(facilityId, () => []);
    final now = DateTime.now().toUtc();
    final group = TankGroup(
      id: 'group-${groups.length + 1}',
      facilityId: facilityId,
      name: name.trim(),
      tankCount: 0,
      archived: false,
      createdAt: now,
      updatedAt: now,
    );
    groups.add(group);
    return group;
  }

  @override
  Future<TankGroup> renameTankGroup({
    required String facilityId,
    required String groupId,
    required String name,
  }) async {
    _requireOwner(facilityId);
    final groups = tankGroups[facilityId] ?? [];
    final index = groups.indexWhere((group) => group.id == groupId);
    if (index == -1) {
      throw const FacilityException(
        'The tank group was not found.',
        code: 'tank_group_not_found',
      );
    }
    final updated = groups[index].copyWith(
      name: name.trim(),
      updatedAt: DateTime.now().toUtc(),
    );
    groups[index] = updated;
    return updated;
  }

  @override
  Future<TankGroup> archiveTankGroup({
    required String facilityId,
    required String groupId,
  }) async {
    _requireOwner(facilityId);
    final groups = tankGroups[facilityId] ?? [];
    final index = groups.indexWhere((group) => group.id == groupId);
    if (index == -1) {
      throw const FacilityException(
        'The tank group was not found.',
        code: 'tank_group_not_found',
      );
    }
    if (groups[index].tankCount > 0) {
      throw const FacilityException(
        'Move or archive every tank in this group before archiving it.',
        code: 'group_not_empty',
      );
    }
    final now = DateTime.now().toUtc();
    final archived = groups[index].copyWith(
      archived: true,
      archivedAt: now,
      updatedAt: now,
    );
    groups[index] = archived;
    return archived;
  }

  @override
  Future<TankGroup> updateTankGroupFeedingSchedule({
    required String facilityId,
    required String groupId,
    required List<String> times,
    required bool automationEnabled,
  }) async {
    _requireOwner(facilityId);
    final groups = tankGroups[facilityId] ?? [];
    final index = groups.indexWhere((group) => group.id == groupId);
    if (index == -1) {
      throw const FacilityException(
        'The tank group was not found.',
        code: 'tank_group_not_found',
      );
    }
    if (groups[index].archived) {
      throw const FacilityException(
        'An archived tank group cannot have its feeding schedule changed.',
        code: 'group_archived',
      );
    }
    final cleanTimes = times.toSet().toList()..sort();
    if (cleanTimes.isEmpty) {
      throw const FacilityException(
        'Add at least one daily feeding time.',
        code: 'invalid_feeding_schedule',
      );
    }
    final updated = groups[index].copyWith(
      feedingTimes: List.unmodifiable(cleanTimes),
      feedingAutomationEnabled: automationEnabled,
      clearNextSession: !automationEnabled,
      updatedAt: DateTime.now().toUtc(),
    );
    groups[index] = updated;
    return updated;
  }

  void _requireOwner(String facilityId) {
    final facility = facilities.firstWhere(
      (item) => item.id == facilityId,
      orElse: () => throw const FacilityException(
        'The aquarium is no longer available.',
        code: 'facility_not_found',
      ),
    );
    if (facility.role != FacilityRole.owner) {
      throw const FacilityException(
        'Only an aquarium owner can manage tank groups.',
        code: 'owner_required',
      );
    }
  }

  @override
  Future<TankPage> listTanks({
    required String facilityId,
    required int page,
    int size = 50,
    String? search,
    TankStatus? status,
    String? groupId,
    bool unassigned = false,
    String? tag,
  }) async {
    final term = search?.trim().toLowerCase();
    final normalizedTag = tag?.toLowerCase();
    final filtered = tanks.where((tank) {
      if (tank.facilityId != facilityId) return false;
      if (status == null && tank.status == TankStatus.archived) return false;
      if (status != null && tank.status != status) return false;
      if (term != null &&
          term.isNotEmpty &&
          !tank.name.toLowerCase().contains(term) &&
          !tank.code.toLowerCase().contains(term)) {
        return false;
      }
      if (unassigned && tank.groupId != null) return false;
      if (!unassigned && groupId != null && tank.groupId != groupId) {
        return false;
      }
      if (normalizedTag != null && !tank.tags.contains(normalizedTag)) {
        return false;
      }
      return true;
    }).toList()..sort((a, b) => a.name.compareTo(b.name));
    final pageSize = size.clamp(1, 100);
    final start = page * pageSize;
    final items = start >= filtered.length
        ? const <Tank>[]
        : filtered.sublist(start, (start + pageSize).clamp(0, filtered.length));
    return TankPage(
      items: List.unmodifiable(items),
      page: page,
      size: pageSize,
      totalItems: filtered.length,
      totalPages: filtered.isEmpty ? 0 : (filtered.length / pageSize).ceil(),
    );
  }

  @override
  Future<TankDetail> getTankDetail({
    required String facilityId,
    required String tankId,
  }) async {
    final configured = tankDetails[tankId];
    if (configured != null && configured.tank.facilityId == facilityId) {
      return configured;
    }
    final tank = _tank(facilityId, tankId);
    final inheritedTimes = (tankGroups[facilityId] ?? const <TankGroup>[])
        .where((group) => group.id == tank.groupId)
        .expand((group) => group.feedingTimes)
        .toList();
    return TankDetail(
      tank: tank,
      observationState: tank.countObservedAt == null
          ? TankObservationState.noData
          : TankObservationState.current,
      deviceStatus: TankDeviceStatus.notConfigured,
      inheritedFeedingTimes: inheritedTimes,
      feedingTimes: inheritedTimes,
      recentActivity: [
        TankActivity(
          type: 'TANK_CREATED',
          title: 'Tank created',
          occurredAt: tank.createdAt,
        ),
      ],
    );
  }

  @override
  Future<TankHardwareHealth> getTankDeviceHealth({
    required String facilityId,
    required String tankId,
  }) async {
    final detail = await getTankDetail(facilityId: facilityId, tankId: tankId);
    return detail.deviceHealth ??
        TankHardwareHealth(
          overallState: detail.deviceStatus,
          feedingAllowed: detail.deviceStatus == TankDeviceStatus.online,
          components: TankDeviceType.values
              .map(
                (type) =>
                    TankDeviceComponent(type: type, state: detail.deviceStatus),
              )
              .toList(),
        );
  }

  @override
  Future<ProvisionedTankDevice> provisionTankDevice({
    required String facilityId,
    required String tankId,
    required TankDeviceType type,
  }) async {
    _requireOwner(facilityId);
    await getTankDetail(facilityId: facilityId, tankId: tankId);
    return ProvisionedTankDevice(
      deviceId: 'device-${type.name}-$tankId',
      type: type,
      heartbeatToken: 'test-heartbeat-token',
      createdAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<TankDetail> updateTankFeedingSchedule({
    required String facilityId,
    required String tankId,
    required TankScheduleMode mode,
    required List<String> times,
  }) async {
    _requireOwner(facilityId);
    final current = await getTankDetail(facilityId: facilityId, tankId: tankId);
    if (current.tank.status == TankStatus.archived) {
      throw const FacilityException(
        'An archived tank cannot have its feeding schedule changed.',
        code: 'tank_archived',
      );
    }
    final cleanTimes = times.toSet().toList()..sort();
    if (mode == TankScheduleMode.override && cleanTimes.isEmpty) {
      throw const FacilityException(
        'Add at least one time to the tank override.',
        code: 'override_schedule_empty',
      );
    }
    final inheritedTimes = (tankGroups[facilityId] ?? const <TankGroup>[])
        .where((group) => group.id == current.tank.groupId)
        .expand((group) => group.feedingTimes)
        .toList();
    final updatedTank = current.tank.copyWith(scheduleMode: mode);
    final tankIndex = tanks.indexWhere(
      (tank) => tank.id == tankId && tank.facilityId == facilityId,
    );
    if (tankIndex != -1) tanks[tankIndex] = updatedTank;
    final updated = TankDetail(
      tank: updatedTank,
      observationState: current.observationState,
      deviceStatus: current.deviceStatus,
      scheduleMode: mode,
      inheritedFeedingTimes: inheritedTimes,
      feedingTimes: mode == TankScheduleMode.override
          ? List.unmodifiable(cleanTimes)
          : List.unmodifiable(inheritedTimes),
      lastFeedingAt: current.lastFeedingAt,
      nextFeedingAt: null,
      appetiteObservation: current.appetiteObservation,
      recentActivity: current.recentActivity,
    );
    tankDetails[tankId] = updated;
    return updated;
  }

  @override
  Future<List<String>> listTankTags(String facilityId) async {
    final tags =
        tanks
            .where(
              (tank) =>
                  tank.facilityId == facilityId &&
                  tank.status != TankStatus.archived,
            )
            .expand((tank) => tank.tags)
            .toSet()
            .toList()
          ..sort();
    return tags;
  }

  @override
  Future<Tank> createTank({
    required String facilityId,
    required TankDraft draft,
  }) async {
    _requireOwner(facilityId);
    _rejectCode(facilityId, draft.code);
    final group = _group(facilityId, draft.groupId);
    final now = DateTime.now().toUtc();
    final tank = Tank(
      id: 'tank-${tanks.length + 1}',
      facilityId: facilityId,
      name: draft.name.trim(),
      code: draft.code.trim(),
      expectedGuppyCount: draft.expectedGuppyCount,
      groupId: group?.id,
      groupName: group?.name,
      tags: _tags(draft.tags),
      automationEnabled: draft.automationEnabled,
      status: draft.automationEnabled ? TankStatus.active : TankStatus.paused,
      notes: draft.notes.trim().isEmpty ? null : draft.notes.trim(),
      createdAt: now,
      updatedAt: now,
    );
    tanks.add(tank);
    _changeCount(facilityId, group?.id, 1);
    return tank;
  }

  @override
  Future<Tank> updateTank({
    required String facilityId,
    required String tankId,
    required TankDraft draft,
  }) async {
    _requireOwner(facilityId);
    final index = tanks.indexWhere(
      (tank) => tank.id == tankId && tank.facilityId == facilityId,
    );
    if (index == -1) {
      throw const FacilityException(
        'The tank was not found.',
        code: 'tank_not_found',
      );
    }
    _rejectCode(facilityId, draft.code, excludingId: tankId);
    final existing = tanks[index];
    final group = _group(facilityId, draft.groupId);
    if (existing.groupId != group?.id) {
      _changeCount(facilityId, existing.groupId, -1);
      _changeCount(facilityId, group?.id, 1);
    }
    final updated = existing.copyWith(
      name: draft.name.trim(),
      code: draft.code.trim(),
      expectedGuppyCount: draft.expectedGuppyCount,
      groupId: group?.id,
      clearGroup: group == null,
      groupName: group?.name,
      tags: _tags(draft.tags),
      automationEnabled: draft.automationEnabled,
      status: draft.automationEnabled ? TankStatus.active : TankStatus.paused,
      notes: draft.notes.trim(),
      updatedAt: DateTime.now().toUtc(),
    );
    tanks[index] = updated;
    return updated;
  }

  @override
  Future<Tank> archiveTank({
    required String facilityId,
    required String tankId,
  }) async {
    _requireOwner(facilityId);
    final index = tanks.indexWhere(
      (tank) => tank.id == tankId && tank.facilityId == facilityId,
    );
    if (index == -1) {
      throw const FacilityException(
        'The tank was not found.',
        code: 'tank_not_found',
      );
    }
    if (tanks[index].status == TankStatus.archived) return tanks[index];
    _changeCount(facilityId, tanks[index].groupId, -1);
    final now = DateTime.now().toUtc();
    tanks[index] = tanks[index].copyWith(
      automationEnabled: false,
      status: TankStatus.archived,
      archivedAt: now,
      updatedAt: now,
    );
    return tanks[index];
  }

  @override
  Future<FeederCalibration?> getFeederCalibration(String facilityId) async {
    await getFacility(facilityId);
    final items = calibrations[facilityId] ?? const [];
    return items.isEmpty ? null : items.last;
  }

  @override
  Future<FeederCalibration> createFeederCalibration({
    required String facilityId,
    required FeederCalibrationDraft draft,
  }) async {
    _requireOwner(facilityId);
    if (draft.minimumUnits > draft.maximumUnits) {
      throw const FacilityException(
        'Minimum feeder units cannot exceed maximum feeder units.',
        code: 'invalid_calibration_bounds',
      );
    }
    final items = calibrations.putIfAbsent(facilityId, () => []);
    final calibration = FeederCalibration(
      id: 'calibration-${items.length + 1}',
      version: items.length + 1,
      unitsPerFish: draft.unitsPerFish,
      minimumUnits: draft.minimumUnits,
      maximumUnits: draft.maximumUnits,
      createdAt: DateTime.now().toUtc(),
    );
    items.add(calibration);
    return calibration;
  }

  @override
  Future<PortionPreview> getPortionPreview({
    required String facilityId,
    required String tankId,
    int? fishCount,
  }) async {
    final tank = _tank(facilityId, tankId);
    return calculatePortionPreview(
      calibration: await getFeederCalibration(facilityId),
      fishCount:
          fishCount ?? tank.detectedGuppyCount ?? tank.expectedGuppyCount,
    );
  }

  @override
  Future<FeedingDashboard> getFeedingDashboard(String facilityId) async {
    return dashboards[facilityId] ??
        FeedingDashboard(
          generatedAt: DateTime.now().toUtc(),
          totalTanks: tanks
              .where(
                (tank) =>
                    tank.facilityId == facilityId &&
                    tank.status != TankStatus.archived,
              )
              .length,
          automatedTanks: tanks
              .where(
                (tank) =>
                    tank.facilityId == facilityId && tank.automationEnabled,
              )
              .length,
          upcomingCount: 0,
          pendingCommands: 0,
          delivered: 0,
          skipped: 0,
          blocked: 0,
          failed: 0,
          unhealthyDeviceCount: 0,
          upcoming: const [],
          unhealthyDevices: const [],
          recentSessions: const [],
        );
  }

  @override
  Future<FeedingHistoryPage> listFeedingHistory({
    required String facilityId,
    String? tankId,
    String? groupId,
    FeedingSource? source,
    FeedingOutcome? outcome,
    DateTime? from,
    DateTime? to,
    String? cursor,
    int size = 25,
  }) async {
    var items = List<FeedingHistoryItem>.of(
      feedingHistory[facilityId] ?? const [],
    );
    if (tankId != null) {
      items = items.where((item) => item.tankId == tankId).toList();
    }
    if (groupId != null) {
      items = items.where((item) => item.groupId == groupId).toList();
    }
    if (source != null) {
      items = items.where((item) => item.source == source).toList();
    }
    if (outcome != null) {
      items = items.where((item) => item.outcome == outcome).toList();
    }
    if (from != null) {
      items = items.where((item) => !item.scheduledFor.isBefore(from)).toList();
    }
    if (to != null) {
      items = items.where((item) => item.scheduledFor.isBefore(to)).toList();
    }
    final offset = cursor == null ? 0 : int.tryParse(cursor) ?? 0;
    final end = (offset + size).clamp(0, items.length);
    return FeedingHistoryPage(
      items: items.sublist(offset.clamp(0, items.length), end),
      nextCursor: end < items.length ? '$end' : null,
    );
  }

  Tank _tank(String facilityId, String tankId) => tanks.firstWhere(
    (tank) => tank.facilityId == facilityId && tank.id == tankId,
    orElse: () => throw const FacilityException(
      'The tank was not found.',
      code: 'tank_not_found',
    ),
  );

  TankGroup? _group(String facilityId, String? groupId) {
    if (groupId == null) return null;
    return (tankGroups[facilityId] ?? const <TankGroup>[]).firstWhere(
      (group) => group.id == groupId && !group.archived,
      orElse: () => throw const FacilityException(
        'Select an active tank group from this aquarium.',
        code: 'invalid_tank_group',
      ),
    );
  }

  void _changeCount(String facilityId, String? groupId, int amount) {
    if (groupId == null) return;
    final groups = tankGroups[facilityId] ?? [];
    final index = groups.indexWhere((group) => group.id == groupId);
    if (index != -1) {
      groups[index] = groups[index].copyWith(
        tankCount: groups[index].tankCount + amount,
        updatedAt: DateTime.now().toUtc(),
      );
    }
  }

  void _rejectCode(String facilityId, String code, {String? excludingId}) {
    if (tanks.any(
      (tank) =>
          tank.facilityId == facilityId &&
          tank.id != excludingId &&
          tank.code.toLowerCase() == code.trim().toLowerCase(),
    )) {
      throw const FacilityException(
        'A tank in this aquarium already uses that code.',
        code: 'tank_code_exists',
      );
    }
  }

  List<String> _tags(List<String> values) =>
      values
          .map((tag) => tag.trim().toLowerCase())
          .where((tag) => tag.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
}
