import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app/app.dart';
import 'package:mobile_app/app/config/app_environment.dart';
import 'package:mobile_app/features/onboarding/domain/onboarding_repository.dart';

import 'fakes/fake_authentication_repository.dart';
import 'fakes/fake_facility_repository.dart';
import 'fakes/fake_facility_selection_store.dart';

void main() {
  Widget buildApp(
    FakeAuthenticationRepository authenticationRepository, {
    FakeFacilityRepository? facilityRepository,
    AppEnvironment environment = const AppEnvironment.test(),
  }) {
    return AquaSenseApp(
      environment: environment,
      onboardingRepository: _CompletedOnboardingRepository(),
      authenticationRepository: authenticationRepository,
      facilityRepository: facilityRepository ?? FakeFacilityRepository(),
      facilitySelectionStore: FakeFacilitySelectionStore(),
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

    expect(
      find.textContaining('Google sign-in did not complete.'),
      findsOneWidget,
    );
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

  const emailEnvironment = AppEnvironment(
    name: AppEnvironmentName.test,
    apiBaseUrl: 'https://api.example.com',
  );

  testWidgets('email login is available without Google configuration', (
    tester,
  ) async {
    final repository = FakeAuthenticationRepository(
      delay: const Duration(milliseconds: 500),
    );
    await tester.pumpWidget(
      buildApp(repository, environment: emailEnvironment),
    );
    await tester.pumpAndSettle();
    expect(find.text('Continue with Google'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      ' owner@example.com ',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      '  long-password-123  ',
    );
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(find.text('Please wait…'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(repository.emailSignInCalls, 1);
    expect(repository.lastEmail, 'owner@example.com');
    expect(repository.lastPassword, '  long-password-123  ');
    expect(find.text('Name your first aquarium'), findsOneWidget);
  });

  testWidgets('create account validates name password and confirmation', (
    tester,
  ) async {
    final repository = FakeAuthenticationRepository();
    await tester.pumpWidget(
      buildApp(repository, environment: emailEnvironment),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('New to AquaSense? Create account'));
    await tester.tap(find.text('New to AquaSense? Create account'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your name.'), findsOneWidget);
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(repository.createAccountCalls, 0);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Full name'),
      ' New Owner ',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'new@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'short',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm password'),
      'different',
    );
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Use at least 12 characters.'), findsOneWidget);
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(repository.createAccountCalls, 0);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'long-password-123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm password'),
      'long-password-123',
    );
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(repository.createAccountCalls, 1);
    expect(repository.lastDisplayName, 'New Owner');
    expect(find.text('Name your first aquarium'), findsOneWidget);
  });

  testWidgets('email failure is shown and can be retried', (tester) async {
    final repository = FakeAuthenticationRepository(
      behavior: FakeGoogleSignInBehavior.failure,
    );
    await tester.pumpWidget(
      buildApp(repository, environment: emailEnvironment),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'owner@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'long-password-123',
    );
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Email or password is incorrect.'), findsOneWidget);
    repository.behavior = FakeGoogleSignInBehavior.success;
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(repository.emailSignInCalls, 2);
    expect(find.text('Name your first aquarium'), findsOneWidget);
  });

  testWidgets('Google and email are both available when Google is configured', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        FakeAuthenticationRepository(),
        environment: const AppEnvironment(
          name: AppEnvironmentName.test,
          apiBaseUrl: 'https://api.example.com',
          googleServerClientId: 'google-client',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
  });
}

class _CompletedOnboardingRepository implements OnboardingRepository {
  @override
  Future<void> completeOnboarding() async {}

  @override
  Future<bool> hasCompletedOnboarding() async => true;
}
