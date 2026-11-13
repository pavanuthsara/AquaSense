import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_app/app/theme/aquasense_theme.dart';
import 'package:mobile_app/features/disease_check/domain/disease_classifier.dart';
import 'package:mobile_app/features/disease_check/domain/fish_photo_source.dart';
import 'package:mobile_app/features/disease_check/presentation/disease_check_screen.dart';

import 'fakes/fake_disease_classifier.dart';
import 'fakes/fake_fish_photo_source.dart';

final _photo = img.encodePng(img.Image(width: 8, height: 6, numChannels: 3));

Widget _app(FakeDiseaseClassifier classifier, FakeFishPhotoSource source) {
  return MaterialApp(
    theme: AquaSenseTheme.light,
    home: DiseaseCheckScreen(classifier: classifier, photoSource: source),
  );
}

void main() {
  testWidgets('start screen shows photo tips and both photo buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(FakeDiseaseClassifier(), FakeFishPhotoSource()),
    );

    expect(find.text('Check a guppy for white spot'), findsOneWidget);
    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
    expect(find.textContaining('Screening aid only'), findsOneWidget);
  });

  testWidgets('a white spot photo shows the result and advice', (tester) async {
    final classifier = FakeDiseaseClassifier(healthy: 0.03, whiteSpot: 0.97);
    final source = FakeFishPhotoSource(photo: _photo);
    await tester.pumpWidget(_app(classifier, source));

    await tester.tap(find.byKey(const Key('disease-take-photo')));
    await tester.pumpAndSettle();

    expect(source.cameraCalls, 1);
    expect(classifier.calls, 1);
    expect(
      find.descendant(
        of: find.byKey(const Key('disease-result-card')),
        matching: find.text('White spot'),
      ),
      findsWidgets,
    );
    expect(find.text('What to do'), findsOneWidget);
    expect(find.text('97%'), findsOneWidget);
    expect(find.text('3%'), findsOneWidget);
  });

  testWidgets('a healthy photo from the gallery shows healthy', (tester) async {
    final classifier = FakeDiseaseClassifier(healthy: 0.99, whiteSpot: 0.01);
    final source = FakeFishPhotoSource(photo: _photo);
    await tester.pumpWidget(_app(classifier, source));

    await tester.tap(find.byKey(const Key('disease-pick-photo')));
    await tester.pumpAndSettle();

    expect(source.galleryCalls, 1);
    expect(
      find.descendant(
        of: find.byKey(const Key('disease-result-card')),
        matching: find.text('Healthy'),
      ),
      findsWidgets,
    );
  });

  testWidgets('a low score says not sure and repeats the photo tips', (
    tester,
  ) async {
    final classifier = FakeDiseaseClassifier(healthy: 0.45, whiteSpot: 0.55);
    await tester.pumpWidget(
      _app(classifier, FakeFishPhotoSource(photo: _photo)),
    );

    await tester.tap(find.byKey(const Key('disease-take-photo')));
    await tester.pumpAndSettle();

    expect(find.text('Not sure'), findsOneWidget);
    expect(find.text('Take another photo'), findsOneWidget);
    expect(find.text('For a better photo'), findsOneWidget);
    expect(find.text('What to do'), findsNothing);
  });

  testWidgets('cancelling the camera stays on the start screen', (
    tester,
  ) async {
    final classifier = FakeDiseaseClassifier();
    await tester.pumpWidget(_app(classifier, FakeFishPhotoSource()));

    await tester.tap(find.byKey(const Key('disease-take-photo')));
    await tester.pumpAndSettle();

    expect(classifier.calls, 0);
    expect(find.text('Take photo'), findsOneWidget);
  });

  testWidgets('a model error can be retried with the same photo', (
    tester,
  ) async {
    final classifier = FakeDiseaseClassifier()
      ..error = const DiseaseClassifierException('Model failed to load.');
    await tester.pumpWidget(
      _app(classifier, FakeFishPhotoSource(photo: _photo)),
    );

    await tester.tap(find.byKey(const Key('disease-take-photo')));
    await tester.pumpAndSettle();

    expect(find.text('The check did not work'), findsOneWidget);
    expect(find.text('Model failed to load.'), findsOneWidget);

    classifier.error = null;
    await tester.ensureVisible(find.byKey(const Key('disease-retry')));
    await tester.tap(find.byKey(const Key('disease-retry')));
    await tester.pumpAndSettle();

    expect(classifier.calls, 2);
    expect(find.byKey(const Key('disease-result-card')), findsOneWidget);
  });

  testWidgets('a camera error is explained', (tester) async {
    await tester.pumpWidget(
      _app(
        FakeDiseaseClassifier(),
        FakeFishPhotoSource(
          error: const FishPhotoException('The camera could not be opened.'),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('disease-take-photo')));
    await tester.pumpAndSettle();

    expect(find.text('The camera could not be opened.'), findsOneWidget);
  });

  testWidgets('check another fish goes back to the start', (tester) async {
    await tester.pumpWidget(
      _app(FakeDiseaseClassifier(), FakeFishPhotoSource(photo: _photo)),
    );
    await tester.tap(find.byKey(const Key('disease-take-photo')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('disease-check-another')));
    await tester.tap(find.byKey(const Key('disease-check-another')));
    await tester.pumpAndSettle();

    expect(find.text('Take photo'), findsOneWidget);
  });
}
