import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app/app.dart';
import 'package:mobile_app/app/config/app_environment.dart';
import 'package:mobile_app/features/onboarding/domain/onboarding_repository.dart';

import 'fakes/fake_authentication_repository.dart';
import 'fakes/fake_facility_repository.dart';

void main() {
  Widget buildApp(
    FakeAuthenticationRepository authenticationRepository, {
    FakeFacilityRepository? facilityRepository,
  }) {
    return AquaSenseApp(
      environment: const AppEnvironment.test(),
      onboardingRepository: _CompletedOnboardingRepository(),
      authenticationRepository: authenticationRepository,
      facilityRepository: facilityRepository ?? FakeFacilityRepository(),
    );
  }

  testWidgets(
    'signed-out user sees Google sign-in and development disclosure',
    (tester) async {
      await tester.pumpWidget(buildApp(FakeAuthenticationRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Welcome to AquaSense'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(
        find.textContaining('Development mode uses a local test account'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Google sign-in shows loading then opens authenticated home', (
    tester,
  ) async {
    final repository = FakeAuthenticationRepository(
      delay: const Duration(milliseconds: 500),
    );
    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue with Google'));
    await tester.pump();
    expect(find.text('Connecting securely…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Name your first aquarium'), findsOneWidget);
    expect(repository.signInCalls, 1);
  });

  testWidgets('cancelled Google sign-in returns to an informative state', (
    tester,
  ) async {
    final repository = FakeAuthenticationRepository(
      behavior: FakeGoogleSignInBehavior.cancelled,
    );
    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(find.text('Google sign-in was cancelled.'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('connection failure is shown and can be retried', (tester) async {
    final repository = FakeAuthenticationRepository(
      behavior: FakeGoogleSignInBehavior.failure,
    );
    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.text('Test connection failure.'), findsOneWidget);

    repository.behavior = FakeGoogleSignInBehavior.success;
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.text('Name your first aquarium'), findsOneWidget);
    expect(repository.signInCalls, 2);
  });

  testWidgets('saved session opens home and sign-out returns to sign-in', (
    tester,
  ) async {
    final repository = FakeAuthenticationRepository(
      restoredSession: FakeAuthenticationRepository.session(),
    );
    await tester.pumpWidget(
      buildApp(
        repository,
        facilityRepository: FakeFacilityRepository(
          facilities: [FakeFacilityRepository.facility()],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test Aquarium'), findsOneWidget);
    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to AquaSense'), findsOneWidget);
    expect(repository.signOutCalls, 1);
  });
}

class _CompletedOnboardingRepository implements OnboardingRepository {
  @override
  Future<void> completeOnboarding() async {}

  @override
  Future<bool> hasCompletedOnboarding() async => true;
}
