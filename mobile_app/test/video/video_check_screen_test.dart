import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/disease_check/data/video_check_runner.dart';
import 'package:mobile_app/features/disease_check/domain/decoded_frame.dart';
import 'package:mobile_app/features/disease_check/domain/disease_classifier.dart';
import 'package:mobile_app/features/disease_check/domain/fish_box.dart';
import 'package:mobile_app/features/disease_check/domain/picked_video.dart';
import 'package:mobile_app/features/disease_check/presentation/disease_check_screen.dart';

import '../fakes/fake_disease_classifier.dart';
import '../fakes/fake_fish_crop_classifier.dart';
import '../fakes/fake_fish_detector.dart';
import '../fakes/fake_fish_photo_source.dart';
import '../fakes/fake_fish_video_source.dart';
import '../fakes/fake_video_frame_extractor.dart';

List<DecodedFrame> _frames(int n) => [
  for (var i = 0; i < n; i++)
    DecodedFrame(
      width: 300,
      height: 300,
      rgb: Uint8List(300 * 300 * 3),
      timeMs: i * 500,
    ),
];

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpVideoScreen(
  WidgetTester tester, {
  required FakeFishCropClassifier classifier,
  int frames = 4,
}) async {
  final runner = VideoCheckRunner(
    detector: FakeFishDetector(const [
      FishBox(x0: 10, y0: 10, x1: 210, y1: 210, score: 0.9),
    ]),
    classifier: classifier,
    extractor: FakeVideoFrameExtractor(_frames(frames)),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: DiseaseCheckScreen(
        classifier: FakeDiseaseClassifier(),
        photoSource: FakeFishPhotoSource(),
        videoRunner: runner,
        videoSource: FakeFishVideoSource(
          recorded: const PickedVideo(path: 'clip.mp4'),
          picked: const PickedVideo(path: 'clip.mp4'),
        ),
      ),
    ),
  );
  // Switch to the Video tab.
  await tester.tap(find.text('Video'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the mode toggle reveals the video controls', (tester) async {
    await _pumpVideoScreen(tester, classifier: FakeFishCropClassifier());
    expect(find.byKey(const Key('video-record')), findsOneWidget);
    expect(find.byKey(const Key('video-choose')), findsOneWidget);
    expect(find.byKey(const Key('video-closeup-switch')), findsOneWidget);
  });

  testWidgets('a recorded video with sick fish shows white spot found', (
    tester,
  ) async {
    await _pumpVideoScreen(
      tester,
      classifier: FakeFishCropClassifier(score: 0.9),
    );
    await tester.tap(find.byKey(const Key('video-record')));
    await _settle(tester);
    expect(find.byKey(const Key('video-result')), findsOneWidget);
    expect(find.text('White spot found'), findsOneWidget);
    expect(find.byKey(const Key('video-fish-1')), findsOneWidget);
  });

  testWidgets('healthy fish show a healthy answer', (tester) async {
    await _pumpVideoScreen(
      tester,
      classifier: FakeFishCropClassifier(score: 0.1),
    );
    await tester.tap(find.byKey(const Key('video-choose')));
    await _settle(tester);
    expect(find.text('Healthy'), findsOneWidget);
  });

  testWidgets('borderline scores show not sure', (tester) async {
    await _pumpVideoScreen(
      tester,
      classifier: FakeFishCropClassifier(score: 0.5),
    );
    await tester.tap(find.byKey(const Key('video-record')));
    await _settle(tester);
    expect(find.text('Not sure'), findsOneWidget);
  });

  testWidgets('cancel during checking returns to the start', (tester) async {
    final gate = Completer<void>();
    final classifier = FakeFishCropClassifier(score: 0.9, gate: gate);
    await _pumpVideoScreen(tester, classifier: classifier);
    await tester.tap(find.byKey(const Key('video-record')));
    await tester.pump(); // enter checking; classify is gated
    expect(find.byKey(const Key('video-cancel')), findsOneWidget);
    await tester.tap(find.byKey(const Key('video-cancel')));
    await tester.runAsync(() async {
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.byKey(const Key('video-record')), findsOneWidget);
    expect(find.byKey(const Key('video-result')), findsNothing);
  });

  testWidgets('a classifier error shows try again', (tester) async {
    await _pumpVideoScreen(
      tester,
      classifier: FakeFishCropClassifier(
        error: const DiseaseClassifierException('model failed'),
      ),
    );
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('video-record')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.byKey(const Key('video-try-again')), findsOneWidget);
    expect(find.text('model failed'), findsOneWidget);
  });
}
