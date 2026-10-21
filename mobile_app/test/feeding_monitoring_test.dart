import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app/app.dart';
import 'package:mobile_app/app/config/app_environment.dart';
import 'package:mobile_app/features/facility/domain/feeding_monitoring.dart';
import 'package:mobile_app/features/onboarding/domain/onboarding_repository.dart';

import 'fakes/fake_authentication_repository.dart';
import 'fakes/fake_facility_repository.dart';
import 'fakes/fake_facility_selection_store.dart';

void main() {
  testWidgets('dashboard opens cursor-paginated feeding history', (
    tester,
  ) async {
    final facility = FakeFacilityRepository.facility();
    final history = List.generate(
      30,
      (index) => FeedingHistoryItem(
        id: 'session-$index',
        tankId: 'tank-${index % 2}',
        tankName: 'Tank ${index % 2 + 1}',
        groupId: 'group-1',
        groupName: 'Nursery',
        scheduledFor: DateTime.utc(
          2026,
          10,
          21,
          8,
        ).subtract(Duration(minutes: index)),
        source: FeedingSource.scheduled,
        outcome: index == 0 ? FeedingOutcome.failed : FeedingOutcome.delivered,
        reason: index == 0 ? 'motor jam' : null,
      ),
    );
    final dashboard = FeedingDashboard(
      generatedAt: DateTime.utc(2026, 10, 21, 9),
      totalTanks: 12,
      automatedTanks: 10,
      upcomingCount: 4,
      pendingCommands: 1,
      delivered: 8,
      skipped: 2,
      blocked: 1,
      failed: 1,
      unhealthyDeviceCount: 1,
      upcoming: [
        UpcomingFeedingSession(
          tankId: 'tank-1',
          tankName: 'Tank 1',
          groupName: 'Nursery',
          scheduledFor: DateTime.utc(2026, 10, 21, 10),
        ),
      ],
      unhealthyDevices: const [],
      recentSessions: history.take(5).toList(),
    );
    final repository = FakeFacilityRepository(
      facilities: [facility],
      dashboards: {facility.id: dashboard},
      feedingHistory: {facility.id: history},
    );

    await tester.pumpWidget(
      AquaSenseApp(
        environment: const AppEnvironment.test(),
        onboardingRepository: _CompletedOnboardingRepository(),
        authenticationRepository: FakeAuthenticationRepository(
          restoredSession: FakeAuthenticationRepository.session(),
        ),
        facilityRepository: repository,
        facilitySelectionStore: FakeFacilitySelectionStore(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.text('Feeding operations'), findsOneWidget);
    expect(find.text('Active tanks'), findsOneWidget);
    expect(find.text('Next 24 hours'), findsOneWidget);
    expect(find.text('1 device(s) need attention.'), findsOneWidget);

    final historyButton = find.byKey(const Key('feeding-history-button'));
    await tester.ensureVisible(historyButton);
    await tester.pumpAndSettle();
    await tester.tap(historyButton);
    await tester.pumpAndSettle();

    expect(find.text('Feeding history'), findsOneWidget);
    expect(find.textContaining('Failed'), findsOneWidget);
    expect(find.textContaining('motor jam'), findsOneWidget);
    final loadMore = find.byKey(const Key('feeding-history-load-more'));
    await tester.scrollUntilVisible(
      loadMore,
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(loadMore);
    await tester.pumpAndSettle();
    expect(find.text('Tank 2'), findsWidgets);
    expect(find.byKey(const Key('feeding-history-load-more')), findsNothing);
  });
}

class _CompletedOnboardingRepository implements OnboardingRepository {
  @override
  Future<void> completeOnboarding() async {}

  @override
  Future<bool> hasCompletedOnboarding() async => true;
}
