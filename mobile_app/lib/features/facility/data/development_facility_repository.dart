import '../domain/facility.dart';
import '../domain/appetite_check.dart';
import '../domain/facility_repository.dart';
import '../domain/facility_team.dart';
import '../domain/feeder_calibration.dart';
import '../domain/feeding_monitoring.dart';
import '../domain/tank_group.dart';
import '../domain/tank.dart';

class DevelopmentFacilityRepository implements FacilityRepository {
  @override
  Future<AppetiteCheck> requestAppetiteCheck({
    required String facilityId,
    required String tankId,
  }) async {
    throw const FacilityException(
      'Live appetite checks require a backend connection. Sign in with Google and connect your laptop camera process.',
    );
  }

  @override
  Future<AppetiteCheck> getAppetiteCheck({
    required String facilityId,
    required String tankId,
    required String checkId,
  }) async {
    throw const FacilityException(
      'Live appetite checks require a backend connection.',
    );
  }

  final List<Facility> _facilities = [];
  final Map<String, Facility> _creationRequests = {};
  final Map<String, List<FacilityMember>> _members = {};
  final List<FacilityInvitation> _invitations = [];
  final Map<String, List<TankGroup>> _tankGroups = {};
  final Map<String, List<Tank>> _tanks = {};
  final Map<String, List<FeederCalibration>> _calibrations = {};
  final Map<String, TankScheduleMode> _tankScheduleModes = {};
  final Map<String, List<String>> _tankOverrideTimes = {};
  final Map<String, Map<TankDeviceType, TankDeviceComponent>> _tankDevices = {};

  @override
  Future<Facility> createFacility({
    required String name,
    required String timeZone,
    required String idempotencyKey,
  }) async {
    final existing = _creationRequests[idempotencyKey];
    if (existing != null) {
      if (existing.name != name.trim() || existing.timeZone != timeZone) {
        throw const FacilityException(
          'That setup request was already used with different details.',
          code: 'idempotency_conflict',
        );
      }
      return existing;
    }

    final facility = Facility(
      id: 'development-facility-${_facilities.length + 1}',
      name: name.trim(),
      timeZone: timeZone,
      role: FacilityRole.owner,
      createdAt: DateTime.now().toUtc(),
    );
    _facilities.add(facility);
    _members[facility.id] = [
      FacilityMember(
        id: 'development-owner-membership-${_facilities.length}',
        userId: 'development-owner',
        email: 'owner@aquasense.local',
        displayName: 'Development Owner',
        role: FacilityRole.owner,
        joinedAt: facility.createdAt,
      ),
    ];
    _creationRequests[idempotencyKey] = facility;
    return facility;
  }

  @override
  Future<Facility> getFacility(String facilityId) async {
    return _facilities.firstWhere(
      (facility) => facility.id == facilityId,
      orElse: () => throw const FacilityException(
        'The aquarium is no longer available.',
        code: 'facility_not_found',
      ),
    );
  }

  @override
  Future<List<Facility>> listFacilities() async =>
      List.unmodifiable(_facilities);

  @override
  Future<List<String>> listTimeZones() async => const [
    'Asia/Colombo',
    'Asia/Kolkata',
    'Asia/Singapore',
    'Australia/Sydney',
    'Europe/London',
    'UTC',
  ];

  @override
  Future<Facility> acceptInvitation(String invitationId) async {
    final index = _invitations.indexWhere((item) => item.id == invitationId);
    if (index == -1 ||
        _invitations[index].status != FacilityInvitationStatus.pending) {
      throw const FacilityException(
        'That invitation is no longer available.',
        code: 'invitation_unavailable',
      );
    }
    _invitations[index] = _invitations[index].copyWith(
      status: FacilityInvitationStatus.accepted,
    );
    return getFacility(_invitations[index].facilityId);
  }

  @override
  Future<FacilityInvitation> inviteWorker({
    required String facilityId,
    required String email,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (_invitations.any(
      (item) =>
          item.facilityId == facilityId &&
          item.email == normalizedEmail &&
          item.status == FacilityInvitationStatus.pending,
    )) {
      throw const FacilityException(
        'An active invitation already exists for that email.',
        code: 'invitation_already_pending',
      );
    }
    final facility = await getFacility(facilityId);
    final now = DateTime.now().toUtc();
    final invitation = FacilityInvitation(
      id: 'development-invitation-${_invitations.length + 1}',
      facilityId: facilityId,
      facilityName: facility.name,
      email: normalizedEmail,
      status: FacilityInvitationStatus.pending,
      expiresAt: now.add(const Duration(days: 7)),
      createdAt: now,
    );
    _invitations.add(invitation);
    return invitation;
  }

  @override
  Future<List<FacilityInvitation>> listFacilityInvitations(
    String facilityId,
  ) async => List.unmodifiable(
    _invitations.where((item) => item.facilityId == facilityId),
  );

  @override
  Future<List<FacilityMember>> listMembers(String facilityId) async {
    final existing = _members[facilityId];
    if (existing != null) {
      return List.unmodifiable(existing);
    }
    final facility = await getFacility(facilityId);
    return [
      FacilityMember(
        id: 'development-owner-membership-${facility.id}',
        userId: 'development-owner',
        email: 'owner@aquasense.local',
        displayName: 'Development Owner',
        role: facility.role,
        joinedAt: facility.createdAt,
      ),
    ];
  }

  @override
  Future<List<FacilityInvitation>> listMyPendingInvitations() async =>
      List.unmodifiable(
        _invitations.where(
          (item) => item.status == FacilityInvitationStatus.pending,
        ),
      );

  @override
  Future<void> removeWorker({
    required String facilityId,
    required String membershipId,
  }) async {
    _members[facilityId]?.removeWhere((item) => item.id == membershipId);
  }

  @override
  Future<void> revokeInvitation({
    required String facilityId,
    required String invitationId,
  }) async {
    final index = _invitations.indexWhere(
      (item) => item.id == invitationId && item.facilityId == facilityId,
    );
    if (index != -1) {
      _invitations[index] = _invitations[index].copyWith(
        status: FacilityInvitationStatus.revoked,
      );
    }
  }

  @override
  Future<List<TankGroup>> listTankGroups(String facilityId) async {
    await getFacility(facilityId);
    final groups = [...?_tankGroups[facilityId]]
      ..sort((first, second) {
        if (first.archived != second.archived) {
          return first.archived ? 1 : -1;
        }
        return first.name.toLowerCase().compareTo(second.name.toLowerCase());
      });
    return List.unmodifiable(groups);
  }

  @override
  Future<TankGroup> createTankGroup({
    required String facilityId,
    required String name,
  }) async {
    _requireOwner(facilityId);
    final groups = _tankGroups.putIfAbsent(facilityId, () => []);
    final cleanName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    _rejectDuplicate(groups, cleanName);
    final now = DateTime.now().toUtc();
    final group = TankGroup(
      id: 'development-group-${groups.length + 1}',
      facilityId: facilityId,
      name: cleanName,
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
    final groups = _tankGroups[facilityId] ?? [];
    final index = groups.indexWhere((group) => group.id == groupId);
    if (index == -1) {
      throw const FacilityException(
        'The tank group was not found.',
        code: 'tank_group_not_found',
      );
    }
    final existing = groups[index];
    if (existing.archived) {
      throw const FacilityException(
        'An archived tank group cannot be renamed.',
        code: 'group_archived',
      );
    }
    final cleanName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    _rejectDuplicate(groups, cleanName, excludingId: groupId);
    final updated = existing.copyWith(
      name: cleanName,
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
    final groups = _tankGroups[facilityId] ?? [];
    final index = groups.indexWhere((group) => group.id == groupId);
    if (index == -1) {
      throw const FacilityException(
        'The tank group was not found.',
        code: 'tank_group_not_found',
      );
    }
    final existing = groups[index];
    if (existing.tankCount > 0) {
      throw const FacilityException(
        'Move or archive every tank in this group before archiving it.',
        code: 'group_not_empty',
      );
    }
    if (existing.archived) {
      return existing;
    }
    final now = DateTime.now().toUtc();
    final archived = existing.copyWith(
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
    final groups = _tankGroups[facilityId] ?? [];
    final index = groups.indexWhere((group) => group.id == groupId);
    if (index == -1) {
      throw const FacilityException(
        'The tank group was not found.',
        code: 'tank_group_not_found',
      );
    }
    final existing = groups[index];
    if (existing.archived) {
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
    final updated = existing.copyWith(
      feedingTimes: List.unmodifiable(cleanTimes),
      feedingAutomationEnabled: automationEnabled,
      clearNextSession: true,
      updatedAt: DateTime.now().toUtc(),
    );
    groups[index] = updated;
    return updated;
  }

  Facility _requireOwner(String facilityId) {
    final facility = _facilities.firstWhere(
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
    return facility;
  }

  void _rejectDuplicate(
    List<TankGroup> groups,
    String name, {
    String? excludingId,
  }) {
    if (groups.any(
      (group) =>
          !group.archived &&
          group.id != excludingId &&
          group.name.toLowerCase() == name.toLowerCase(),
    )) {
      throw const FacilityException(
        'An active tank group already uses that name.',
        code: 'tank_group_name_exists',
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
    await getFacility(facilityId);
    final query = search?.trim().toLowerCase();
    final normalizedTag = tag?.toLowerCase();
    final filtered = (_tanks[facilityId] ?? const <Tank>[]).where((tank) {
      final matchesStatus = status == null
          ? tank.status != TankStatus.archived
          : tank.status == status;
      final matchesSearch = query == null || query.isEmpty
          ? true
          : tank.name.toLowerCase().contains(query) ||
                tank.code.toLowerCase().contains(query);
      final matchesGroup = unassigned
          ? tank.groupId == null
          : groupId == null || tank.groupId == groupId;
      final matchesTag = normalizedTag == null || normalizedTag.isEmpty
          ? true
          : tank.tags.contains(normalizedTag);
      return matchesStatus && matchesSearch && matchesGroup && matchesTag;
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
    await getFacility(facilityId);
    final tank = _findTank(facilityId, tankId);
    final mode = _tankScheduleModes[tankId] ?? TankScheduleMode.inherited;
    TankGroup? group;
    for (final item in _tankGroups[facilityId] ?? const <TankGroup>[]) {
      if (item.id == tank.groupId) {
        group = item;
        break;
      }
    }
    final feedingTimes = mode == TankScheduleMode.override
        ? _tankOverrideTimes[tankId] ?? const <String>[]
        : group?.feedingTimes ?? const <String>[];
    final deviceHealth = await getTankDeviceHealth(
      facilityId: facilityId,
      tankId: tankId,
    );
    return TankDetail(
      tank: tank.copyWith(scheduleMode: mode),
      observationState: tank.countObservedAt == null
          ? TankObservationState.noData
          : TankObservationState.current,
      deviceStatus: deviceHealth.overallState,
      deviceHealth: deviceHealth,
      scheduleMode: mode,
      inheritedFeedingTimes: group?.feedingTimes ?? const [],
      feedingTimes: feedingTimes,
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
    _findTank(facilityId, tankId);
    final configured = _tankDevices[tankId] ?? const {};
    final components = TankDeviceType.values
        .map(
          (type) =>
              configured[type] ??
              TankDeviceComponent(
                type: type,
                state: TankDeviceStatus.notConfigured,
              ),
        )
        .toList(growable: false);
    final states = components.map((item) => item.state).toSet();
    final overall = states.contains(TankDeviceStatus.notConfigured)
        ? TankDeviceStatus.notConfigured
        : states.contains(TankDeviceStatus.unhealthy)
        ? TankDeviceStatus.unhealthy
        : states.contains(TankDeviceStatus.offline)
        ? TankDeviceStatus.offline
        : states.contains(TankDeviceStatus.stale)
        ? TankDeviceStatus.stale
        : TankDeviceStatus.online;
    return TankHardwareHealth(
      overallState: overall,
      feedingAllowed: overall == TankDeviceStatus.online,
      components: components,
    );
  }

  @override
  Future<ProvisionedTankDevice> provisionTankDevice({
    required String facilityId,
    required String tankId,
    required TankDeviceType type,
  }) async {
    _requireOwner(facilityId);
    _findTank(facilityId, tankId);
    final now = DateTime.now().toUtc();
    final deviceId = 'development-${type.name}-$tankId';
    _tankDevices.putIfAbsent(tankId, () => {})[type] = TankDeviceComponent(
      type: type,
      deviceId: deviceId,
      state: TankDeviceStatus.offline,
    );
    return ProvisionedTankDevice(
      deviceId: deviceId,
      type: type,
      heartbeatToken: 'development-token-${type.name}',
      createdAt: now,
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
    final tank = _findTank(facilityId, tankId);
    if (tank.status == TankStatus.archived) {
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
    _tankScheduleModes[tankId] = mode;
    if (mode == TankScheduleMode.override) {
      _tankOverrideTimes[tankId] = List.unmodifiable(cleanTimes);
    } else {
      _tankOverrideTimes.remove(tankId);
    }
    return getTankDetail(facilityId: facilityId, tankId: tankId);
  }

  @override
  Future<List<String>> listTankTags(String facilityId) async {
    await getFacility(facilityId);
    final tags =
        (_tanks[facilityId] ?? const <Tank>[])
            .where((tank) => tank.status != TankStatus.archived)
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
    final tanks = _tanks.putIfAbsent(facilityId, () => []);
    _rejectTankCode(tanks, draft.code);
    final group = _activeGroup(facilityId, draft.groupId);
    final now = DateTime.now().toUtc();
    final tank = Tank(
      id: 'development-tank-${tanks.length + 1}',
      facilityId: facilityId,
      name: draft.name.trim(),
      code: draft.code.trim(),
      expectedGuppyCount: draft.expectedGuppyCount,
      groupId: group?.id,
      groupName: group?.name,
      tags: _cleanTankTags(draft.tags),
      automationEnabled: group != null && draft.automationEnabled,
      status: group != null && draft.automationEnabled
          ? TankStatus.active
          : TankStatus.paused,
      notes: draft.notes.trim().isEmpty ? null : draft.notes.trim(),
      createdAt: now,
      updatedAt: now,
    );
    tanks.add(tank);
    if (group != null) {
      _changeGroupCount(facilityId, group.id, 1);
    }
    return tank;
  }

  @override
  Future<Tank> updateTank({
    required String facilityId,
    required String tankId,
    required TankDraft draft,
  }) async {
    _requireOwner(facilityId);
    final tanks = _tanks[facilityId] ?? [];
    final index = tanks.indexWhere((tank) => tank.id == tankId);
    if (index == -1) {
      throw const FacilityException(
        'The tank was not found.',
        code: 'tank_not_found',
      );
    }
    final existing = tanks[index];
    _rejectTankCode(tanks, draft.code, excludingId: tankId);
    final group = _activeGroup(facilityId, draft.groupId);
    if (existing.groupId != group?.id) {
      if (existing.groupId != null) {
        _changeGroupCount(facilityId, existing.groupId!, -1);
      }
      if (group != null) {
        _changeGroupCount(facilityId, group.id, 1);
      }
    }
    final updated = existing.copyWith(
      name: draft.name.trim(),
      code: draft.code.trim(),
      expectedGuppyCount: draft.expectedGuppyCount,
      groupId: group?.id,
      clearGroup: group == null,
      groupName: group?.name,
      tags: _cleanTankTags(draft.tags),
      automationEnabled:
          (group != null ||
              _tankScheduleModes[tankId] == TankScheduleMode.override) &&
          draft.automationEnabled,
      status:
          (group != null ||
                  _tankScheduleModes[tankId] == TankScheduleMode.override) &&
              draft.automationEnabled
          ? TankStatus.active
          : TankStatus.paused,
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
    final tanks = _tanks[facilityId] ?? [];
    final index = tanks.indexWhere((tank) => tank.id == tankId);
    if (index == -1) {
      throw const FacilityException(
        'The tank was not found.',
        code: 'tank_not_found',
      );
    }
    final existing = tanks[index];
    if (existing.status == TankStatus.archived) {
      return existing;
    }
    if (existing.groupId != null) {
      _changeGroupCount(facilityId, existing.groupId!, -1);
    }
    final now = DateTime.now().toUtc();
    final archived = existing.copyWith(
      automationEnabled: false,
      status: TankStatus.archived,
      archivedAt: now,
      updatedAt: now,
    );
    tanks[index] = archived;
    return archived;
  }

  @override
  Future<FeederCalibration?> getFeederCalibration(String facilityId) async {
    await getFacility(facilityId);
    final items = _calibrations[facilityId] ?? const [];
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
    final items = _calibrations.putIfAbsent(facilityId, () => []);
    final calibration = FeederCalibration(
      id: 'development-calibration-${items.length + 1}',
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
    final tank = _findTank(facilityId, tankId);
    return calculatePortionPreview(
      calibration: await getFeederCalibration(facilityId),
      fishCount:
          fishCount ?? tank.detectedGuppyCount ?? tank.expectedGuppyCount,
    );
  }

  @override
  Future<FeedingDashboard> getFeedingDashboard(String facilityId) async {
    await getFacility(facilityId);
    final active = (_tanks[facilityId] ?? const <Tank>[])
        .where((tank) => tank.status != TankStatus.archived)
        .toList();
    return FeedingDashboard(
      generatedAt: DateTime.now().toUtc(),
      totalTanks: active.length,
      automatedTanks: active.where((tank) => tank.automationEnabled).length,
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
    await getFacility(facilityId);
    return const FeedingHistoryPage(items: []);
  }

  Tank _findTank(String facilityId, String tankId) {
    return (_tanks[facilityId] ?? const <Tank>[]).firstWhere(
      (tank) => tank.id == tankId,
      orElse: () => throw const FacilityException(
        'The tank was not found.',
        code: 'tank_not_found',
      ),
    );
  }

  TankGroup? _activeGroup(String facilityId, String? groupId) {
    if (groupId == null) {
      return null;
    }
    return (_tankGroups[facilityId] ?? const <TankGroup>[]).firstWhere(
      (group) => group.id == groupId && !group.archived,
      orElse: () => throw const FacilityException(
        'Select an active tank group from this aquarium.',
        code: 'invalid_tank_group',
      ),
    );
  }

  void _changeGroupCount(String facilityId, String groupId, int change) {
    final groups = _tankGroups[facilityId] ?? [];
    final index = groups.indexWhere((group) => group.id == groupId);
    if (index != -1) {
      groups[index] = groups[index].copyWith(
        tankCount: groups[index].tankCount + change,
        updatedAt: DateTime.now().toUtc(),
      );
    }
  }

  void _rejectTankCode(List<Tank> tanks, String code, {String? excludingId}) {
    if (tanks.any(
      (tank) =>
          tank.id != excludingId &&
          tank.code.toLowerCase() == code.trim().toLowerCase(),
    )) {
      throw const FacilityException(
        'A tank in this aquarium already uses that code.',
        code: 'tank_code_exists',
      );
    }
  }

  List<String> _cleanTankTags(List<String> tags) =>
      tags
          .map((tag) => tag.trim().toLowerCase())
          .where((tag) => tag.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
}
