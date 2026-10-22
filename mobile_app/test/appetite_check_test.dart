import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/facility/domain/appetite_check.dart';
import 'package:mobile_app/features/facility/domain/tank.dart';
import 'package:mobile_app/features/facility/presentation/appetite_check_card.dart';

import 'fakes/fake_facility_repository.dart';

void main() {
  Widget card(FakeFacilityRepository repository) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: AppetiteCheckCard(
          facilityId: 'facility-1',
          tankId: 'tank-1',
          repository: repository,
        ),
      ),
    ),
  );

  for (final label in AppetiteResult.values) {
    testWidgets(
      'fresh check displays ${label.name} after pending and checking',
      (tester) async {
        final repository = _CheckRepository([
          _check(AppetiteCheckStatus.checking),
          _check(AppetiteCheckStatus.completed, label: label),
        ]);
        await tester.pumpWidget(card(repository));
        await tester.tap(
          find.byKey(const Key('check-current-appetite-button')),
        );
        await tester.pump();
        expect(find.text('Waiting for the camera process…'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('check-current-appetite-button')),
              )
              .onPressed,
          isNull,
        );
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(find.text('Observing fish movement…'), findsOneWidget);
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(
          find.text(
            label == AppetiteResult.high ? 'High appetite' : 'Low appetite',
          ),
          findsOneWidget,
        );
        expect(find.text('Model probability: 87%'), findsOneWidget);
        expect(repository.requests, 1);
        expect(repository.polls, 2);
        expect(repository.lastTank, 'tank-1');
        expect(find.byType(LinearProgressIndicator), findsNothing);
      },
    );
  }

  testWidgets('insufficient tracking never displays Low appetite', (
    tester,
  ) async {
    final repository = _CheckRepository([
      _check(
        AppetiteCheckStatus.insufficientData,
        message: 'Not enough fish tracked. Try again.',
      ),
    ]);
    await tester.pumpWidget(card(repository));
    await tester.tap(find.byKey(const Key('check-current-appetite-button')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Not enough fish tracked. Try again.'), findsOneWidget);
    expect(find.byKey(const Key('current-appetite-label')), findsNothing);
  });

  testWidgets('camera timeout permits another check', (tester) async {
    final repository = _CheckRepository([
      _check(
        AppetiteCheckStatus.timedOut,
        message: 'Camera process is offline. Try again.',
      ),
    ]);
    await tester.pumpWidget(card(repository));
    await tester.tap(find.byKey(const Key('check-current-appetite-button')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Camera process is offline. Try again.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('check-current-appetite-button')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('connection error is shown and polling stops on dispose', (
    tester,
  ) async {
    await tester.pumpWidget(card(FakeFacilityRepository()));
    await tester.tap(find.byKey(const Key('check-current-appetite-button')));
    await tester.pump();
    expect(find.text('No camera process is connected.'), findsOneWidget);

    final repository = _CheckRepository([_check(AppetiteCheckStatus.checking)]);
    await tester.pumpWidget(card(repository));
    await tester.tap(find.byKey(const Key('check-current-appetite-button')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    expect(repository.polls, 0);
  });
}

AppetiteCheck _check(
  AppetiteCheckStatus status, {
  AppetiteResult? label,
  String? message,
}) => AppetiteCheck(
  id: 'check-1',
  tankId: 'tank-1',
  status: status,
  requestedAt: DateTime.now().toUtc(),
  expiresAt: DateTime.now().toUtc().add(const Duration(seconds: 60)),
  appetiteResult: label,
  confidence: label == null ? null : 0.87,
  observedAt: label == null ? null : DateTime.now().toUtc(),
  message: message,
);

class _CheckRepository extends FakeFacilityRepository {
  _CheckRepository(this.results);
  final List<AppetiteCheck> results;
  int requests = 0;
  int polls = 0;
  String? lastTank;

  @override
  Future<AppetiteCheck> requestAppetiteCheck({
    required String facilityId,
    required String tankId,
  }) async {
    requests++;
    lastTank = tankId;
    return _check(AppetiteCheckStatus.pending);
  }

  @override
  Future<AppetiteCheck> getAppetiteCheck({
    required String facilityId,
    required String tankId,
    required String checkId,
  }) async {
    polls++;
    return results.removeAt(0);
  }
}
