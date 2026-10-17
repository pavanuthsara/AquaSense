import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app/app.dart';
import 'package:mobile_app/app/config/app_environment.dart';
import 'package:mobile_app/features/facility/domain/facility.dart';
import 'package:mobile_app/features/onboarding/domain/onboarding_repository.dart';

import 'fakes/fake_authentication_repository.dart';
import 'fakes/fake_facility_repository.dart';
import 'fakes/fake_facility_selection_store.dart';

void main() {
  Widget buildApp(
    FakeFacilityRepository repository,
    FakeFacilitySelectionStore selectionStore,
  ) {
    return AquaSenseApp(
      environment: const AppEnvironment.test(),
      onboardingRepository: _CompletedOnboardingRepository(),
      authenticationRepository: FakeAuthenticationRepository(
        restoredSession: FakeAuthenticationRepository.session(),
      ),
      facilityRepository: repository,
      facilitySelectionStore: selectionStore,
    );
  }

  List<Facility> twoFacilities() => [
    FakeFacilityRepository.facility(id: 'facility-one', name: 'Blue Reef'),
    FakeFacilityRepository.facility(
      id: 'facility-two',
      name: 'Guppy House',
      timeZone: 'UTC',
    ),
  ];

  testWidgets('restores the signed-in user last selected aquarium', (
    tester,
  ) async {
    final selectionStore = FakeFacilitySelectionStore({
      'test-owner': 'facility-two',
    });

    await tester.pumpWidget(
      buildApp(
        FakeFacilityRepository(facilities: twoFacilities()),
        selectionStore,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Guppy House'), findsOneWidget);
    expect(find.text('UTC'), findsOneWidget);
    expect(selectionStore.reads, ['test-owner']);
  });

  testWidgets('switches aquarium only after access is verified and saves it', (
    tester,
  ) async {
    final repository = FakeFacilityRepository(facilities: twoFacilities());
    final selectionStore = FakeFacilitySelectionStore();
    await tester.pumpWidget(buildApp(repository, selectionStore));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('facility-switcher-button')));
    await tester.pumpAndSettle();
    expect(find.text('Switch aquarium'), findsOneWidget);

    await tester.tap(find.byKey(const Key('facility-choice-facility-two')));
    await tester.pumpAndSettle();

    expect(find.text('Guppy House'), findsOneWidget);
    expect(repository.getCalls, 1);
    expect(selectionStore.selections['test-owner'], 'facility-two');
  });

  testWidgets('falls back safely when the saved aquarium was removed', (
    tester,
  ) async {
    final selectionStore = FakeFacilitySelectionStore({
      'test-owner': 'removed-facility',
    });
    await tester.pumpWidget(
      buildApp(
        FakeFacilityRepository(facilities: twoFacilities()),
        selectionStore,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Blue Reef'), findsOneWidget);
    expect(selectionStore.selections['test-owner'], 'facility-one');
    expect(
      find.textContaining(
        'previously selected aquarium is no longer accessible',
      ),
      findsOneWidget,
    );
  });

  testWidgets('does not enter an aquarium that became inaccessible', (
    tester,
  ) async {
    final repository = FakeFacilityRepository(facilities: twoFacilities());
    final selectionStore = FakeFacilitySelectionStore();
    await tester.pumpWidget(buildApp(repository, selectionStore));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('facility-switcher-button')));
    await tester.pumpAndSettle();
    repository.inaccessibleFacilityIds.add('facility-two');
    await tester.tap(find.byKey(const Key('facility-choice-facility-two')));
    await tester.pumpAndSettle();

    expect(find.text('Blue Reef'), findsOneWidget);
    expect(selectionStore.selections['test-owner'], 'facility-one');
    expect(
      find.textContaining('That aquarium is no longer accessible'),
      findsOneWidget,
    );
  });

  testWidgets('creates another aquarium and switches to it', (tester) async {
    final repository = FakeFacilityRepository(
      facilities: [
        FakeFacilityRepository.facility(id: 'facility-one', name: 'Blue Reef'),
      ],
    );
    final selectionStore = FakeFacilitySelectionStore();
    await tester.pumpWidget(buildApp(repository, selectionStore));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('facility-switcher-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-aquarium-button')));
    await tester.pumpAndSettle();

    expect(find.text('Create another aquarium'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Aquarium name'),
      'New Hatchery',
    );
    await tester.ensureVisible(find.text('Create aquarium'));
    await tester.tap(find.text('Create aquarium'));
    await tester.pumpAndSettle();

    expect(find.text('New Hatchery'), findsOneWidget);
    expect(repository.facilities, hasLength(2));
    expect(selectionStore.selections['test-owner'], 'facility-2');
  });
}

class _CompletedOnboardingRepository implements OnboardingRepository {
  @override
  Future<void> completeOnboarding() async {}

  @override
  Future<bool> hasCompletedOnboarding() async => true;
}
