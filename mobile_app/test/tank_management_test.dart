import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app/app.dart';
import 'package:mobile_app/app/config/app_environment.dart';
import 'package:mobile_app/features/facility/domain/facility.dart';
import 'package:mobile_app/features/facility/domain/tank.dart';
import 'package:mobile_app/features/facility/domain/tank_group.dart';
import 'package:mobile_app/features/onboarding/domain/onboarding_repository.dart';

import 'fakes/fake_authentication_repository.dart';
import 'fakes/fake_facility_repository.dart';
import 'fakes/fake_facility_selection_store.dart';

void main() {
  Widget buildApp(FakeFacilityRepository repository) {
    return AquaSenseApp(
      environment: const AppEnvironment.test(),
      onboardingRepository: _CompletedOnboardingRepository(),
      authenticationRepository: FakeAuthenticationRepository(
        restoredSession: FakeAuthenticationRepository.session(),
      ),
      facilityRepository: repository,
      facilitySelectionStore: FakeFacilitySelectionStore(),
    );
  }

  testWidgets('owner can create inspect edit and archive a tank', (
    tester,
  ) async {
    final facility = FakeFacilityRepository.facility(name: 'Owner Reef');
    final repository = FakeFacilityRepository(
      facilities: [facility],
      tankGroups: {
        facility.id: [_group(facility.id)],
      },
    );
    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('tanks-button')));
    await tester.pumpAndSettle();
    expect(find.text('No matching tanks'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-tank-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('tank-name-field')),
      'Nursery 1',
    );
    await tester.enterText(find.byKey(const Key('tank-code-field')), 'N-001');
    await tester.enterText(
      find.byKey(const Key('tank-expected-count-field')),
      '80',
    );
    await tester.enterText(
      find.byKey(const Key('tank-tags-field')),
      'breeding, priority',
    );
    await tester.tap(find.byKey(const Key('tank-group-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nursery').last);
    await _scrollFormToEnd(tester);
    await tester.tap(find.byKey(const Key('save-tank-button')));
    await tester.pumpAndSettle();

    final created = repository.tanks.single;
    expect(created.groupId, 'group-1');
    expect(created.tags, ['breeding', 'priority']);
    expect(find.text('Nursery 1'), findsOneWidget);

    await tester.tap(find.byKey(Key('tank-${created.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Tank information'), findsOneWidget);
    expect(find.byKey(const Key('edit-tank-button')), findsOneWidget);
    expect(find.byKey(const Key('archive-tank-button')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('tank-actions-${created.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('tank-expected-count-field')),
      '85',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await _scrollFormToEnd(tester);
    await tester.tap(find.byKey(const Key('save-tank-button')));
    await tester.pumpAndSettle();

    expect(repository.tanks.single.expectedGuppyCount, 85);
    expect(find.textContaining('85 expected'), findsOneWidget);

    await tester.tap(find.byKey(Key('tank-actions-${created.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-list-archive-tank')));
    await tester.pumpAndSettle();

    expect(repository.tanks.single.status, TankStatus.archived);
    expect(find.text('No matching tanks'), findsOneWidget);
  });

  testWidgets('one thousand tanks remain paginated and searchable', (
    tester,
  ) async {
    final facility = FakeFacilityRepository.facility(name: 'Scale Reef');
    final tanks = List.generate(
      1000,
      (index) => _tank(
        facilityId: facility.id,
        id: 'tank-$index',
        name: 'Tank ${index.toString().padLeft(4, '0')}',
        code: 'T-${index.toString().padLeft(4, '0')}',
      ),
    );
    final repository = FakeFacilityRepository(
      facilities: [facility],
      tanks: tanks,
    );
    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tanks-button')));
    await tester.pumpAndSettle();

    expect(find.text('1000 tanks'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('load-more-tanks-button')),
      500,
      scrollable: _verticalScrollable(),
    );
    expect(find.byKey(const Key('load-more-tanks-button')), findsOneWidget);

    await tester.drag(_verticalScrollable(), const Offset(0, 5000));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('tank-search-field')),
      'T-0999',
    );
    await tester.tap(find.byKey(const Key('tank-search-button')));
    await tester.pumpAndSettle();

    expect(find.text('1 tanks'), findsOneWidget);
    expect(find.text('Tank 0999'), findsOneWidget);
    expect(find.byKey(const Key('load-more-tanks-button')), findsNothing);
  });

  testWidgets('worker can inspect operational states without owner actions', (
    tester,
  ) async {
    final facility = FakeFacilityRepository.facility(
      name: 'Worker Reef',
      role: FacilityRole.worker,
    );
    final tank = _tank(
      facilityId: facility.id,
      id: 'tank-1',
      name: 'Nursery 1',
      code: 'N-001',
      groupId: 'group-1',
      groupName: 'Nursery',
      tags: const ['breeding'],
      detectedCount: 76,
      confidence: 0.92,
      observedAt: DateTime.utc(2026, 10, 19, 6),
    );
    final repository = FakeFacilityRepository(
      facilities: [facility],
      tanks: [tank],
      tankDetails: {
        tank.id: TankDetail(
          tank: tank,
          observationState: TankObservationState.stale,
          deviceStatus: TankDeviceStatus.offline,
          scheduleMode: TankScheduleMode.override,
          feedingTimes: const ['08:00', '16:00'],
          lastFeedingAt: DateTime.utc(2026, 10, 19, 8),
          nextFeedingAt: DateTime.utc(2026, 10, 19, 16),
          recentActivity: [
            TankActivity(
              type: 'COUNT_OBSERVED',
              title: 'Guppy count observed',
              occurredAt: DateTime.utc(2026, 10, 19, 6),
            ),
          ],
        ),
      },
    );
    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tanks-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('add-tank-button')), findsNothing);
    expect(find.byKey(const Key('tank-actions-tank-1')), findsNothing);
    await tester.tap(find.byKey(const Key('tank-tank-1')));
    await tester.pumpAndSettle();

    expect(find.text('Hardware offline'), findsOneWidget);
    expect(find.text('Count stale'), findsOneWidget);
    expect(find.text('76'), findsOneWidget);
    expect(find.text('92%'), findsOneWidget);
    expect(find.byKey(const Key('edit-tank-button')), findsNothing);
    expect(find.byKey(const Key('archive-tank-button')), findsNothing);
    expect(find.byKey(const Key('edit-tank-schedule-button')), findsNothing);

    await tester.scrollUntilVisible(
      find.text('08:00, 16:00'),
      180,
      scrollable: _verticalScrollable(),
    );
    expect(find.text('08:00, 16:00'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Guppy count observed'),
      180,
      scrollable: _verticalScrollable(),
    );
    expect(find.text('Guppy count observed'), findsOneWidget);
  });

  testWidgets('owner can replace inherited times with a tank override', (
    tester,
  ) async {
    final facility = FakeFacilityRepository.facility(name: 'Schedule Reef');
    final group = _group(facility.id).copyWith(
      feedingTimes: const ['08:00', '16:00'],
      feedingAutomationEnabled: true,
    );
    final tank = _tank(
      facilityId: facility.id,
      id: 'tank-schedule',
      name: 'Schedule Tank',
      code: 'S-001',
      groupId: group.id,
      groupName: group.name,
    );
    final repository = FakeFacilityRepository(
      facilities: [facility],
      tankGroups: {
        facility.id: [group],
      },
      tanks: [tank],
    );
    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tanks-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tank-tank-schedule')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('edit-tank-schedule-button')));
    await tester.pumpAndSettle();
    expect(find.text('Inherited from Nursery'), findsOneWidget);
    await tester.tap(find.text('Tank override'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remove-tank-feeding-time-08:00')));
    await tester.tap(find.byKey(const Key('save-tank-feeding-schedule')));
    await tester.pumpAndSettle();

    final updated = repository.tankDetails[tank.id]!;
    expect(updated.scheduleMode, TankScheduleMode.override);
    expect(updated.feedingTimes, ['16:00']);
    await tester.scrollUntilVisible(
      find.text('Tank override'),
      180,
      scrollable: _verticalScrollable(),
    );
    expect(find.text('Tank override'), findsOneWidget);
    expect(find.text('16:00'), findsOneWidget);

    await tester.tap(find.byKey(const Key('edit-tank-schedule-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inherit group'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tank-feeding-time-08:00')), findsOneWidget);
    expect(find.byKey(const Key('tank-feeding-time-16:00')), findsOneWidget);
    await tester.tap(find.byKey(const Key('save-tank-feeding-schedule')));
    await tester.pumpAndSettle();
    expect(
      repository.tankDetails[tank.id]!.scheduleMode,
      TankScheduleMode.inherited,
    );
    expect(repository.tankDetails[tank.id]!.feedingTimes, ['08:00', '16:00']);
  });
}

TankGroup _group(String facilityId) => TankGroup(
  id: 'group-1',
  facilityId: facilityId,
  name: 'Nursery',
  tankCount: 0,
  archived: false,
  createdAt: DateTime.utc(2026, 10, 19),
  updatedAt: DateTime.utc(2026, 10, 19),
);

Tank _tank({
  required String facilityId,
  required String id,
  required String name,
  required String code,
  String? groupId,
  String? groupName,
  List<String> tags = const [],
  int? detectedCount,
  double? confidence,
  DateTime? observedAt,
}) => Tank(
  id: id,
  facilityId: facilityId,
  name: name,
  code: code,
  expectedGuppyCount: 80,
  detectedGuppyCount: detectedCount,
  detectionConfidence: confidence,
  countObservedAt: observedAt,
  groupId: groupId,
  groupName: groupName,
  tags: tags,
  automationEnabled: true,
  status: TankStatus.active,
  createdAt: DateTime.utc(2026, 10, 18),
  updatedAt: DateTime.utc(2026, 10, 19),
);

class _CompletedOnboardingRepository implements OnboardingRepository {
  @override
  Future<void> completeOnboarding() async {}

  @override
  Future<bool> hasCompletedOnboarding() async => true;
}

Finder _verticalScrollable() => find
    .byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    )
    .hitTestable()
    .first;

Finder _formScrollable() => find
    .descendant(
      of: find.byKey(const Key('tank-form-scroll')),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _scrollFormToEnd(WidgetTester tester) async {
  final position = tester.state<ScrollableState>(_formScrollable()).position;
  position.jumpTo(position.maxScrollExtent);
  await tester.pumpAndSettle();
}
