import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app/app.dart';
import 'package:mobile_app/app/config/app_environment.dart';
import 'package:mobile_app/features/onboarding/domain/onboarding_repository.dart';

import 'fakes/fake_authentication_repository.dart';
import 'fakes/fake_facility_repository.dart';

void main() {
  Widget buildApp(FakeFacilityRepository facilityRepository) {
    return AquaSenseApp(
      environment: const AppEnvironment.test(),
      onboardingRepository: _CompletedOnboardingRepository(),
      authenticationRepository: FakeAuthenticationRepository(
        restoredSession: FakeAuthenticationRepository.session(),
      ),
      facilityRepository: facilityRepository,
    );
  }

  testWidgets('first-time owner sees aquarium setup', (tester) async {
    await tester.pumpWidget(buildApp(FakeFacilityRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Name your first aquarium'), findsOneWidget);
    expect(find.text('Aquarium name'), findsOneWidget);
    expect(find.text('Asia/Colombo'), findsOneWidget);
    expect(find.text('Create aquarium'), findsOneWidget);
  });

  testWidgets('aquarium name is required', (tester) async {
    await tester.pumpWidget(buildApp(FakeFacilityRepository()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Create aquarium'));
    await tester.tap(find.text('Create aquarium'));
    await tester.pump();

    expect(find.text('Enter an aquarium name.'), findsOneWidget);
  });

  testWidgets('creating first aquarium opens facility-aware empty home', (
    tester,
  ) async {
    final repository = FakeFacilityRepository();
    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Aquarium name'),
      'Blue Reef Hatchery',
    );
    await tester.ensureVisible(find.text('Create aquarium'));
    await tester.tap(find.text('Create aquarium'));
    await tester.pumpAndSettle();

    expect(find.text('Blue Reef Hatchery'), findsOneWidget);
    expect(find.text('Your aquarium is ready'), findsOneWidget);
    expect(find.text('1 owner'), findsOneWidget);
    expect(repository.facilities, hasLength(1));
  });

  testWidgets('returning owner enters existing aquarium home', (tester) async {
    await tester.pumpWidget(
      buildApp(
        FakeFacilityRepository(
          facilities: [
            FakeFacilityRepository.facility(name: 'Existing Aquarium'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Existing Aquarium'), findsOneWidget);
    expect(find.text('Name your first aquarium'), findsNothing);
  });

  testWidgets('retrying unchanged creation reuses idempotency key', (
    tester,
  ) async {
    final repository = FakeFacilityRepository(createFailures: 1);
    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Aquarium name'),
      'Retry Reef',
    );
    await tester.ensureVisible(find.text('Create aquarium'));
    await tester.tap(find.text('Create aquarium'));
    await tester.pumpAndSettle();
    expect(find.text('Temporary setup failure.'), findsOneWidget);

    await tester.ensureVisible(find.text('Create aquarium'));
    await tester.tap(find.text('Create aquarium'));
    await tester.pumpAndSettle();

    expect(find.text('Retry Reef'), findsOneWidget);
    expect(repository.creationKeys, hasLength(2));
    expect(repository.creationKeys[1], repository.creationKeys[0]);
  });

  testWidgets('facility loading failure can be retried', (tester) async {
    final repository = FakeFacilityRepository(
      listError: const FacilityExceptionForTest(),
    );
    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();

    expect(find.text('Could not load aquariums'), findsOneWidget);
    repository.listError = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('Name your first aquarium'), findsOneWidget);
    expect(repository.listCalls, 2);
  });
}

class FacilityExceptionForTest implements Exception {
  const FacilityExceptionForTest();
}

class _CompletedOnboardingRepository implements OnboardingRepository {
  @override
  Future<void> completeOnboarding() async {}

  @override
  Future<bool> hasCompletedOnboarding() async => true;
}
