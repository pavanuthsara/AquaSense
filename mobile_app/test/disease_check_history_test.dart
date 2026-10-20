import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_app/app/theme/aquasense_theme.dart';
import 'package:mobile_app/features/auth/domain/auth_models.dart';
import 'package:mobile_app/features/auth/domain/auth_session_storage.dart';
import 'package:mobile_app/features/disease_check/data/development_disease_check_repository.dart';
import 'package:mobile_app/features/disease_check/data/http_disease_check_repository.dart';
import 'package:mobile_app/features/disease_check/domain/disease_check_repository.dart';
import 'package:mobile_app/features/disease_check/domain/disease_prediction.dart';
import 'package:mobile_app/features/disease_check/presentation/disease_history_screen.dart';
import 'package:mobile_app/features/disease_check/presentation/save_disease_check_panel.dart';

import 'fakes/fake_disease_check_repository.dart';

DiseasePrediction _prediction({double whiteSpot = 0.97, DateTime? checkedAt}) {
  return DiseasePrediction.fromScores(
    labels: const ['healthy', 'white_spot'],
    scores: [1 - whiteSpot, whiteSpot],
    modelVersion: bundledModelVersion,
    inferenceTime: const Duration(milliseconds: 30),
    checkedAt: checkedAt ?? DateTime.utc(2026, 10, 20, 9),
  );
}

Widget _wrap(Widget child) => MaterialApp(
  theme: AquaSenseTheme.light,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  group('HttpDiseaseCheckRepository', () {
    test('saves only the result with the request key', () async {
      late http.Request captured;
      final repository = HttpDiseaseCheckRepository(
        apiBaseUrl: 'https://api.example.com/base',
        sessionStorage: _MemorySessionStorage(),
        client: MockClient((request) async {
          captured = request;
          return http.Response(_recordJson, 201);
        }),
      );

      final record = await repository.saveCheck(
        facilityId: 'facility-1',
        prediction: _prediction(),
        idempotencyKey: 'key-123',
        tankLabel: '  Tank A3 ',
        note: '   ',
      );

      expect(captured.method, 'POST');
      expect(
        captured.url.path,
        '/base/api/v1/facilities/facility-1/disease-checks',
      );
      expect(captured.headers['authorization'], 'Bearer access-token');
      expect(captured.headers['idempotency-key'], 'key-123');
      expect(captured.body, contains('"predictedLabel":"white_spot"'));
      expect(captured.body, contains('"uncertain":false'));
      expect(captured.body, contains('"tankLabel":"Tank A3"'));
      expect(captured.body, isNot(contains('note')));
      expect(record.predictedLabel, 'white_spot');
      expect(record.checkedByName, 'Damith');
    });

    test('lists checks with a limit and surfaces server errors', () async {
      late http.Request captured;
      final repository = HttpDiseaseCheckRepository(
        apiBaseUrl: 'https://api.example.com',
        sessionStorage: _MemorySessionStorage(),
        client: MockClient((request) async {
          captured = request;
          if (request.url.queryParameters['limit'] == '5') {
            return http.Response('[$_recordJson]', 200);
          }
          return http.Response(
            '{"code":"facility_not_found","message":"Not accessible"}',
            404,
          );
        }),
      );

      final records = await repository.listChecks(
        facilityId: 'facility-1',
        limit: 5,
      );
      expect(captured.url.queryParameters['limit'], '5');
      expect(records.single.tankLabel, 'Tank A3');

      await expectLater(
        repository.listChecks(facilityId: 'facility-1', limit: 6),
        throwsA(
          isA<DiseaseCheckException>().having(
            (e) => e.code,
            'code',
            'facility_not_found',
          ),
        ),
      );
    });

    test('missing session stops the request', () async {
      final repository = HttpDiseaseCheckRepository(
        apiBaseUrl: 'https://api.example.com',
        sessionStorage: _MemorySessionStorage(hasSession: false),
        client: MockClient((request) async => http.Response('[]', 200)),
      );

      await expectLater(
        repository.listChecks(facilityId: 'facility-1'),
        throwsA(
          isA<DiseaseCheckException>().having(
            (e) => e.code,
            'code',
            'missing_session',
          ),
        ),
      );
    });
  });

  test('development repository does not duplicate a retried save', () async {
    final repository = DevelopmentDiseaseCheckRepository();
    final prediction = _prediction();

    final first = await repository.saveCheck(
      facilityId: 'f',
      prediction: prediction,
      idempotencyKey: 'same',
    );
    final second = await repository.saveCheck(
      facilityId: 'f',
      prediction: prediction,
      idempotencyKey: 'same',
    );

    expect(second.id, first.id);
    expect(await repository.listChecks(facilityId: 'f'), hasLength(1));
  });

  testWidgets('a failed save is retried with the same request key', (
    tester,
  ) async {
    final repository = FakeDiseaseCheckRepository(saveFailures: 1);
    await tester.pumpWidget(
      _wrap(
        SaveDiseaseCheckPanel(
          facilityId: 'facility-1',
          prediction: _prediction(),
          repository: repository,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('disease-tank-field')),
      'Tank B2',
    );
    await tester.tap(find.byKey(const Key('disease-save')));
    await tester.pumpAndSettle();

    expect(find.text('Temporary save failure.'), findsOneWidget);
    expect(find.text('Try saving again'), findsOneWidget);

    await tester.tap(find.byKey(const Key('disease-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('disease-saved')), findsOneWidget);
    expect(repository.requestKeys, hasLength(2));
    expect(repository.requestKeys.toSet(), hasLength(1));
    expect(repository.tankLabels.last, 'Tank B2');
    final saved = await repository.listChecks(facilityId: 'facility-1');
    expect(saved.single.tankLabel, 'Tank B2');
  });

  testWidgets('history lists saved checks newest first', (tester) async {
    final repository = FakeDiseaseCheckRepository();
    await repository.saveCheck(
      facilityId: 'facility-1',
      prediction: _prediction(
        whiteSpot: 0.02,
        checkedAt: DateTime.utc(2026, 10, 19, 8),
      ),
      idempotencyKey: 'older',
      tankLabel: 'Tank A1',
    );
    await repository.saveCheck(
      facilityId: 'facility-1',
      prediction: _prediction(checkedAt: DateTime.utc(2026, 10, 20, 8)),
      idempotencyKey: 'newer',
      tankLabel: 'Tank C4',
      note: 'Spots on tail',
    );
    await repository.saveCheck(
      facilityId: 'other-facility',
      prediction: _prediction(),
      idempotencyKey: 'other',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AquaSenseTheme.light,
        home: DiseaseHistoryScreen(
          facilityId: 'facility-1',
          facilityName: 'Blue Reef',
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final whiteSpot = tester.getTopLeft(find.text('White spot'));
    final healthy = tester.getTopLeft(find.text('Healthy'));
    expect(whiteSpot.dy, lessThan(healthy.dy));
    expect(find.text('Tank C4 · by Test Owner'), findsOneWidget);
    expect(find.text('Spots on tail'), findsOneWidget);
    expect(find.textContaining('Tank A1'), findsOneWidget);
    expect(find.byType(Card), findsNWidgets(2));
  });

  testWidgets('history shows an empty state and load errors', (tester) async {
    final repository = FakeDiseaseCheckRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: DiseaseHistoryScreen(
          facilityId: 'facility-1',
          facilityName: 'Blue Reef',
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No checks saved yet'), findsOneWidget);

    repository.listError = const DiseaseCheckException('Server is down.');
    await tester.pumpWidget(
      MaterialApp(
        home: DiseaseHistoryScreen(
          key: const Key('second'),
          facilityId: 'facility-1',
          facilityName: 'Blue Reef',
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load history'), findsOneWidget);
    expect(find.text('Server is down.'), findsOneWidget);
  });
}

const _recordJson = '''
{
  "id": "check-1",
  "facilityId": "facility-1",
  "predictedLabel": "white_spot",
  "confidence": 0.97,
  "uncertain": false,
  "modelVersion": "guppy-white-spot-2026-10-16",
  "tankLabel": "Tank A3",
  "note": null,
  "checkedByName": "Damith",
  "checkedAt": "2026-10-20T09:00:00Z"
}
''';

class _MemorySessionStorage implements AuthSessionStorage {
  _MemorySessionStorage({this.hasSession = true});

  final bool hasSession;

  @override
  Future<void> clear() async {}

  @override
  Future<AuthTokens?> readTokens() async {
    if (!hasSession) {
      return null;
    }
    return AuthTokens(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
  }

  @override
  Future<void> writeTokens(AuthTokens tokens) async {}
}
