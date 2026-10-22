import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/facility/domain/appetite_check.dart';
import 'package:mobile_app/features/facility/domain/facility.dart';
import 'package:mobile_app/features/facility/domain/tank.dart';
import 'package:mobile_app/features/facility/presentation/tank_detail_screen.dart';
import 'package:mobile_app/features/facility/presentation/tank_list_screen.dart';

import 'fakes/fake_facility_repository.dart';

void main() {
  for (final role in FacilityRole.values) {
    testWidgets(
      '${role.name} can open a tank and check appetite without scrolling',
      (tester) async {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final facility = FakeFacilityRepository.facility(role: role);
        final repository = _AppetiteRepository(facility);
        await tester.pumpWidget(
          MaterialApp(
            home: TankListScreen(facility: facility, repository: repository),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('tank-tank-1')));
        await tester.pumpAndSettle();
        final button = find.byKey(const Key('check-current-appetite-button'));
        expect(button.hitTestable(), findsOneWidget);
        expect(find.text('Check current appetite'), findsOneWidget);
        await tester.tap(button);
        await tester.pump();
        expect(repository.requestedFacility, facility.id);
        expect(repository.requestedTank, 'tank-1');
        expect(find.text('Waiting for the camera process…'), findsOneWidget);
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.text('High appetite'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'failed inventory does not claim zero tanks and retry restores the list',
    (tester) async {
      final facility = FakeFacilityRepository.facility();
      final repository = _RetryInventoryRepository(facility);
      await tester.pumpWidget(
        MaterialApp(
          home: TankListScreen(facility: facility, repository: repository),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Inventory request failed.'), findsOneWidget);
      expect(find.text('0 tanks'), findsNothing);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('1 tank'), findsOneWidget);
      expect(find.byKey(const Key('tank-tank-1')), findsOneWidget);
      expect(find.text('Inventory request failed.'), findsNothing);
    },
  );

  testWidgets('archived tanks do not offer a current appetite check', (
    tester,
  ) async {
    final facility = FakeFacilityRepository.facility();
    final repository = FakeFacilityRepository(
      facilities: [facility],
      tanks: [_tank(status: TankStatus.archived)],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TankDetailScreen(
          facility: facility,
          tankId: 'tank-1',
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('check-current-appetite-button')),
      findsNothing,
    );
  });
}

Tank _tank({TankStatus status = TankStatus.paused}) => Tank(
  id: 'tank-1',
  facilityId: 'facility-1',
  name: 'Nursery One',
  code: 'N-1',
  expectedGuppyCount: 50,
  tags: const [],
  automationEnabled: false,
  status: status,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

class _AppetiteRepository extends FakeFacilityRepository {
  _AppetiteRepository(Facility facility)
    : super(facilities: [facility], tanks: [_tank()]);

  String? requestedFacility;
  String? requestedTank;

  @override
  Future<AppetiteCheck> requestAppetiteCheck({
    required String facilityId,
    required String tankId,
  }) async {
    requestedFacility = facilityId;
    requestedTank = tankId;
    return _check(AppetiteCheckStatus.pending);
  }

  @override
  Future<AppetiteCheck> getAppetiteCheck({
    required String facilityId,
    required String tankId,
    required String checkId,
  }) async => _check(AppetiteCheckStatus.completed);

  AppetiteCheck _check(AppetiteCheckStatus status) => AppetiteCheck(
    id: 'check-1',
    tankId: 'tank-1',
    status: status,
    requestedAt: DateTime.now().toUtc(),
    expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 1)),
    appetiteResult: status == AppetiteCheckStatus.completed
        ? AppetiteResult.high
        : null,
  );
}

class _RetryInventoryRepository extends FakeFacilityRepository {
  _RetryInventoryRepository(Facility facility)
    : super(facilities: [facility], tanks: [_tank()]);

  bool _fail = true;
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
    if (_fail) {
      _fail = false;
      throw const FacilityException('Inventory request failed.');
    }
    return super.listTanks(
      facilityId: facilityId,
      page: page,
      size: size,
      search: search,
      status: status,
      groupId: groupId,
      unassigned: unassigned,
      tag: tag,
    );
  }
}
