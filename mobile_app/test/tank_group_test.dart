import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app/app.dart';
import 'package:mobile_app/app/config/app_environment.dart';
import 'package:mobile_app/features/facility/domain/facility.dart';
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

  testWidgets('owner can create rename and archive an empty tank group', (
    tester,
  ) async {
    final facility = FakeFacilityRepository.facility(name: 'Owner Reef');
    final repository = FakeFacilityRepository(facilities: [facility]);
    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('tank-groups-button')));
    await tester.pumpAndSettle();
    expect(find.text('No tank groups yet'), findsOneWidget);
    expect(repository.listTankGroupsCalls, 1);

    await tester.tap(find.byKey(const Key('add-tank-group-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('tank-group-name-field')),
      'Nursery',
    );
    await tester.tap(find.byKey(const Key('save-tank-group-button')));
    await tester.pumpAndSettle();

    expect(repository.tankGroups[facility.id], hasLength(1));
    expect(repository.listTankGroupsCalls, 2);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Nursery'), findsOneWidget);
    final groupId = repository.tankGroups[facility.id]!.single.id;

    await tester.tap(find.byKey(Key('tank-group-actions-$groupId')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('tank-group-name-field')),
      'Juvenile',
    );
    await tester.tap(find.byKey(const Key('save-tank-group-button')));
    await tester.pumpAndSettle();

    expect(repository.tankGroups[facility.id]!.single.name, 'Juvenile');
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Juvenile'), findsOneWidget);

    await tester.tap(find.byKey(Key('tank-group-actions-$groupId')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-archive-group')));
    await tester.pumpAndSettle();

    expect(repository.tankGroups[facility.id]!.single.archived, isTrue);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('0 tanks · Archived'), findsOneWidget);
  });

  testWidgets('worker can view groups without owner management controls', (
    tester,
  ) async {
    final facility = FakeFacilityRepository.facility(
      name: 'Worker Reef',
      role: FacilityRole.worker,
    );
    final repository = FakeFacilityRepository(
      facilities: [facility],
      tankGroups: {
        facility.id: [_group(facilityId: facility.id, tankCount: 24)],
      },
    );
    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();

    expect(find.byTooltip('View tank groups'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tank-groups-button')));
    await tester.pumpAndSettle();

    expect(find.text('Nursery'), findsOneWidget);
    expect(find.text('24 tanks'), findsOneWidget);
    expect(find.byKey(const Key('add-tank-group-button')), findsNothing);
    expect(find.byKey(const Key('tank-group-actions-group-1')), findsNothing);
  });

  testWidgets('owner can pause a configured group feeding schedule', (
    tester,
  ) async {
    final facility = FakeFacilityRepository.facility(name: 'Schedule Reef');
    final repository = FakeFacilityRepository(
      facilities: [facility],
      tankGroups: {
        facility.id: [
          _group(
            facilityId: facility.id,
            tankCount: 20,
            feedingTimes: const ['08:00', '16:00'],
            feedingAutomationEnabled: true,
            nextSessionAt: DateTime.parse('2026-10-20T02:30:00Z'),
          ),
        ],
      },
    );
    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tank-groups-button')));
    await tester.pumpAndSettle();

    expect(find.text('08:00, 16:00 · Automatic'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tank-group-group-1')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Asia/Colombo.'), findsOneWidget);
    expect(find.byKey(const Key('group-feeding-time-08:00')), findsOneWidget);
    expect(find.byKey(const Key('group-next-session')), findsOneWidget);
    await tester.tap(find.byKey(const Key('remove-group-feeding-time-08:00')));
    await tester.tap(find.byKey(const Key('group-feeding-automation-switch')));
    await tester.tap(find.byKey(const Key('save-group-feeding-schedule')));
    await tester.pumpAndSettle();

    final updated = repository.tankGroups[facility.id]!.single;
    expect(updated.feedingTimes, ['16:00']);
    expect(updated.feedingAutomationEnabled, isFalse);
    expect(updated.nextSessionAt, isNull);
    expect(find.text('16:00 · Paused'), findsOneWidget);
  });

  testWidgets('worker can inspect a group schedule but cannot edit it', (
    tester,
  ) async {
    final facility = FakeFacilityRepository.facility(
      name: 'Worker Schedule Reef',
      role: FacilityRole.worker,
    );
    final repository = FakeFacilityRepository(
      facilities: [facility],
      tankGroups: {
        facility.id: [
          _group(
            facilityId: facility.id,
            tankCount: 24,
            feedingTimes: const ['07:30', '17:30'],
            feedingAutomationEnabled: true,
          ),
        ],
      },
    );
    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tank-groups-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tank-group-group-1')));
    await tester.pumpAndSettle();

    expect(
      find.text('Workers can view this schedule but cannot change it.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('group-feeding-time-07:30')), findsOneWidget);
    expect(find.byKey(const Key('add-group-feeding-time')), findsNothing);
    expect(find.byKey(const Key('save-group-feeding-schedule')), findsNothing);
    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const Key('group-feeding-automation-switch')),
    );
    expect(toggle.onChanged, isNull);
  });

  testWidgets('occupied group explains why archive is unavailable', (
    tester,
  ) async {
    final facility = FakeFacilityRepository.facility(name: 'Count Reef');
    final repository = FakeFacilityRepository(
      facilities: [facility],
      tankGroups: {
        facility.id: [_group(facilityId: facility.id, tankCount: 3)],
      },
    );
    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tank-groups-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('tank-group-actions-group-1')));
    await tester.pumpAndSettle();

    expect(find.text('Move tanks before archiving'), findsOneWidget);
    expect(find.text('3 tanks'), findsOneWidget);
  });
}

TankGroup _group({
  required String facilityId,
  required int tankCount,
  List<String> feedingTimes = const [],
  bool feedingAutomationEnabled = false,
  DateTime? nextSessionAt,
}) {
  return TankGroup(
    id: 'group-1',
    facilityId: facilityId,
    name: 'Nursery',
    tankCount: tankCount,
    archived: false,
    feedingTimes: feedingTimes,
    feedingAutomationEnabled: feedingAutomationEnabled,
    nextSessionAt: nextSessionAt,
    createdAt: DateTime.utc(2026, 10, 19),
    updatedAt: DateTime.utc(2026, 10, 19),
  );
}

class _CompletedOnboardingRepository implements OnboardingRepository {
  @override
  Future<void> completeOnboarding() async {}

  @override
  Future<bool> hasCompletedOnboarding() async => true;
}
