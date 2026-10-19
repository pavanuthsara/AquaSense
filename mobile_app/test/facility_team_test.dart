import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app/app.dart';
import 'package:mobile_app/app/config/app_environment.dart';
import 'package:mobile_app/features/facility/domain/facility.dart';
import 'package:mobile_app/features/facility/domain/facility_team.dart';
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

  testWidgets('owner can invite a worker from team management', (tester) async {
    final facility = FakeFacilityRepository.facility(name: 'Owner Reef');
    final repository = FakeFacilityRepository(
      facilities: [facility],
      members: {
        facility.id: [_member(role: FacilityRole.owner)],
      },
    );
    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('facility-team-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('invite-worker-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('invite-worker-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('worker-email-field')),
      'Worker@Example.com',
    );
    await tester.tap(find.text('Send invitation'));
    await tester.pumpAndSettle();

    expect(repository.invitations, hasLength(1));
    expect(repository.invitations.single.email, 'worker@example.com');
    expect(
      repository.invitations.single.status,
      FacilityInvitationStatus.pending,
    );
  });

  testWidgets('worker can view team but cannot see owner actions', (
    tester,
  ) async {
    final facility = FakeFacilityRepository.facility(
      name: 'Worker Reef',
      role: FacilityRole.worker,
    );
    final repository = FakeFacilityRepository(
      facilities: [facility],
      members: {
        facility.id: [
          _member(role: FacilityRole.owner),
          _member(
            id: 'worker-membership',
            name: 'Test Worker',
            email: 'worker@example.com',
            role: FacilityRole.worker,
          ),
        ],
      },
    );
    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();

    expect(find.byTooltip('View aquarium team'), findsOneWidget);
    await tester.tap(find.byKey(const Key('facility-team-button')));
    await tester.pumpAndSettle();

    expect(find.text('Aquarium team'), findsOneWidget);
    expect(find.text('Test Worker'), findsOneWidget);
    expect(find.byKey(const Key('invite-worker-button')), findsNothing);
    expect(
      find.byKey(const Key('remove-worker-worker-membership')),
      findsNothing,
    );
    expect(find.text('Invitations'), findsNothing);
  });

  testWidgets('invited user can accept before belonging to any aquarium', (
    tester,
  ) async {
    final repository = FakeFacilityRepository(invitations: [_invitation()]);
    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();

    expect(find.text('You have been invited'), findsOneWidget);
    expect(find.text('Invited Reef'), findsOneWidget);
    await tester.tap(find.byKey(const Key('accept-invitation-invitation-1')));
    await tester.pumpAndSettle();

    expect(find.text('Invited Reef'), findsOneWidget);
    expect(find.byTooltip('View aquarium team'), findsOneWidget);
    expect(repository.facilities.single.role, FacilityRole.worker);
  });

  testWidgets(
    'existing user sees invitation badge and can join another aquarium',
    (tester) async {
      final repository = FakeFacilityRepository(
        facilities: [FakeFacilityRepository.facility(name: 'Current Reef')],
        invitations: [_invitation()],
      );
      await tester.pumpWidget(buildApp(repository));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('pending-invitations-button')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('pending-invitations-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('accept-invitation-invitation-1')));
      await tester.pumpAndSettle();

      expect(find.text('Invited Reef'), findsOneWidget);
      expect(repository.facilities, hasLength(2));
    },
  );
}

FacilityMember _member({
  String id = 'owner-membership',
  String name = 'Test Owner',
  String email = 'owner@example.com',
  required FacilityRole role,
}) {
  return FacilityMember(
    id: id,
    userId: 'user-$id',
    email: email,
    displayName: name,
    role: role,
    joinedAt: DateTime.utc(2026, 10, 19),
  );
}

FacilityInvitation _invitation() {
  return FacilityInvitation(
    id: 'invitation-1',
    facilityId: 'invited-facility',
    facilityName: 'Invited Reef',
    email: 'owner@example.com',
    status: FacilityInvitationStatus.pending,
    expiresAt: DateTime.utc(2026, 10, 26),
    createdAt: DateTime.utc(2026, 10, 19),
  );
}

class _CompletedOnboardingRepository implements OnboardingRepository {
  @override
  Future<void> completeOnboarding() async {}

  @override
  Future<bool> hasCompletedOnboarding() async => true;
}
