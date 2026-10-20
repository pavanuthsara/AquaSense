import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_app/app/app.dart';
import 'package:mobile_app/app/config/app_environment.dart';
import 'package:mobile_app/features/onboarding/domain/onboarding_repository.dart';

import 'fakes/fake_authentication_repository.dart';
import 'fakes/fake_disease_check_repository.dart';
import 'fakes/fake_disease_classifier.dart';
import 'fakes/fake_facility_repository.dart';
import 'fakes/fake_facility_selection_store.dart';
import 'fakes/fake_fish_photo_source.dart';

void main() {
  testWidgets('owner checks a fish from home, saves it and sees history', (
    tester,
  ) async {
    final repository = FakeDiseaseCheckRepository();
    await tester.pumpWidget(
      AquaSenseApp(
        environment: const AppEnvironment.test(),
        onboardingRepository: _CompletedOnboardingRepository(),
        authenticationRepository: FakeAuthenticationRepository(
          restoredSession: FakeAuthenticationRepository.session(),
        ),
        facilityRepository: FakeFacilityRepository(
          facilities: [FakeFacilityRepository.facility(name: 'Blue Reef')],
        ),
        facilitySelectionStore: FakeFacilitySelectionStore(),
        diseaseClassifier: FakeDiseaseClassifier(),
        diseaseCheckRepository: repository,
        fishPhotoSource: FakeFishPhotoSource(
          photo: img.encodePng(img.Image(width: 8, height: 6)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('open-disease-check')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('open-disease-check')));
    await tester.pumpAndSettle();
    expect(find.text('Check a guppy for white spot'), findsOneWidget);

    await tester.tap(find.byKey(const Key('disease-take-photo')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('disease-result-card')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('disease-tank-field')));
    await tester.enterText(
      find.byKey(const Key('disease-tank-field')),
      'Tank A3',
    );
    await tester.ensureVisible(find.byKey(const Key('disease-save')));
    await tester.tap(find.byKey(const Key('disease-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('disease-saved')), findsOneWidget);

    final saved = await repository.listChecks(facilityId: 'facility-1');
    expect(saved.single.predictedLabel, 'white_spot');
    expect(saved.single.tankLabel, 'Tank A3');

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('open-disease-history')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('open-disease-history')));
    await tester.pumpAndSettle();

    expect(find.text('Fish health history'), findsOneWidget);
    expect(find.text('Tank A3 · by Test Owner'), findsOneWidget);
  });
}

class _CompletedOnboardingRepository implements OnboardingRepository {
  @override
  Future<void> completeOnboarding() async {}

  @override
  Future<bool> hasCompletedOnboarding() async => true;
}
