import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app/app.dart';
import 'package:mobile_app/app/config/app_environment.dart';
import 'package:mobile_app/app/routing/app_routes.dart';
import 'package:mobile_app/features/onboarding/domain/onboarding_repository.dart';

import 'fakes/fake_authentication_repository.dart';
import 'fakes/fake_facility_repository.dart';
import 'fakes/fake_facility_selection_store.dart';

void main() {
  Widget buildApp(
    FakeOnboardingRepository repository, {
    FakeAuthenticationRepository? authenticationRepository,
  }) {
    return AquaSenseApp(
      environment: const AppEnvironment.test(),
      onboardingRepository: repository,
      authenticationRepository:
          authenticationRepository ?? FakeAuthenticationRepository(),
      facilityRepository: FakeFacilityRepository(
        facilities: [FakeFacilityRepository.facility()],
      ),
      facilitySelectionStore: FakeFacilitySelectionStore(),
    );
  }

  testWidgets('first launch shows AquaSense onboarding and theme', (
    tester,
  ) async {
    final repository = FakeOnboardingRepository();

    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();

    expect(find.text('All tanks, one clear view'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.bySemanticsLabel('Page 1 of 3'), findsOneWidget);

    final context = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(context).useMaterial3, isTrue);
    expect(Theme.of(context).colorScheme.primary, isNot(Colors.deepPurple));
  });

  testWidgets('onboarding advances through all three approved pages', (
    tester,
  ) async {
    final repository = FakeOnboardingRepository();

    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Feed by appetite, not only the clock'), findsOneWidget);
    expect(find.bySemanticsLabel('Page 2 of 3'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Stay informed and in control'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    expect(find.bySemanticsLabel('Page 3 of 3'), findsOneWidget);

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(repository.completed, isTrue);
    expect(repository.completionWrites, 1);
    expect(find.text('Welcome to AquaSense'), findsOneWidget);
  });

  testWidgets('skip completes onboarding and opens sign-in', (tester) async {
    final repository = FakeOnboardingRepository();

    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(repository.completed, isTrue);
    expect(find.text('Welcome to AquaSense'), findsOneWidget);
  });

  testWidgets('returning user bypasses onboarding', (tester) async {
    final repository = FakeOnboardingRepository(completed: true);

    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to AquaSense'), findsOneWidget);
    expect(find.text('All tanks, one clear view'), findsNothing);
  });

  testWidgets('onboarding can be replayed from the home placeholder', (
    tester,
  ) async {
    final repository = FakeOnboardingRepository(completed: true);

    await tester.pumpWidget(
      buildApp(
        repository,
        authenticationRepository: FakeAuthenticationRepository(
          restoredSession: FakeAuthenticationRepository.session(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pushNamed(AppRoutes.home);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('View onboarding again'));
    await tester.pumpAndSettle();
    expect(find.text('All tanks, one clear view'), findsOneWidget);
    expect(find.byTooltip('Close onboarding'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Test Aquarium'), findsOneWidget);
    expect(repository.completed, isTrue);
  });

  testWidgets('unknown routes show a recoverable not-found screen', (
    tester,
  ) async {
    final repository = FakeOnboardingRepository(completed: true);

    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pushNamed('/missing');
    await tester.pumpAndSettle();

    expect(find.text('Page not found'), findsOneWidget);
    expect(find.text('We could not open /missing.'), findsOneWidget);
    expect(find.text('Return to start'), findsOneWidget);
  });
}

class FakeOnboardingRepository implements OnboardingRepository {
  FakeOnboardingRepository({this.completed = false});

  bool completed;
  int completionWrites = 0;

  @override
  Future<void> completeOnboarding() async {
    completed = true;
    completionWrites += 1;
  }

  @override
  Future<bool> hasCompletedOnboarding() async => completed;
}
