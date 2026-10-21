import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_app/features/auth/domain/auth_models.dart';
import 'package:mobile_app/features/auth/domain/auth_session_storage.dart';
import 'package:mobile_app/features/export/data/development_export_repository.dart';
import 'package:mobile_app/features/export/data/http_export_repository.dart';
import 'package:mobile_app/features/export/data/sample_advisory.dart';
import 'package:mobile_app/features/export/domain/export_advisory.dart';
import 'package:mobile_app/features/export/presentation/export_advisory_screen.dart';
import 'package:mobile_app/features/export/presentation/export_plans_screen.dart';
import 'package:mobile_app/features/facility/domain/facility.dart';

void main() {
  final facility = Facility(
    id: 'facility-1',
    name: 'Blue Reef',
    timeZone: 'Asia/Colombo',
    role: FacilityRole.owner,
    createdAt: DateTime.utc(2026, 10, 1),
  );

  group('advisory parsing', () {
    test('parses every section of the simulator output', () {
      final advisory = DevelopmentExportRepository.sampleAdvisory();

      expect(advisory.feasible, isTrue);
      expect(advisory.recommendation.fishPerBag, greaterThan(0));
      expect(advisory.recommendation.doses, isNotEmpty);
      expect(advisory.recommendation.doses.first.name, isNotEmpty);
      expect(advisory.oxygen!.explanation, contains('mg'));
      expect(advisory.mortality!.checkpoints, isNotEmpty);
      expect(advisory.unpacking!.steps, isNotEmpty);
      expect(advisory.temperature!.curve, isNotEmpty);
      expect(advisory.options.where((option) => option.recommended).length, 1);

      final median = advisory.timeline!.median;
      expect(median.doMgL.length, median.hours.length);
      expect(median.alivePct.length, median.hours.length);
      expect(median.openedAtHour, isNotNull);
    });

    test('keeps gaps in series as null', () {
      final json = jsonDecode(sampleAdvisoryJson) as Map<String, dynamic>;
      final gas = json['timeline']['median']['gas_o2_pct'] as List<dynamic>;
      final advisory = TransitAdvisory.fromJson(json);

      expect(gas.contains(null), isTrue);
      expect(advisory.timeline!.median.gasO2Pct.contains(null), isTrue);
    });

    test('request serialises to the backend field names', () {
      const request = ExportShipmentRequest(
        label: '  Dubai order ',
        species: ExportSpecies.tigerBarb,
        fishMassG: 12,
        totalFish: 600,
        waterL: 1,
        gasL: 0.33,
        durationH: 48,
        tempLowC: 22,
        tempHighC: 26,
        allowZeolite: false,
      );

      expect(request.toJson(), {
        'label': 'Dubai order',
        'species': 'tiger_barb',
        'fishMassG': 12.0,
        'totalFish': 600,
        'waterL': 1.0,
        'gasL': 0.33,
        'durationH': 48.0,
        'tempLowC': 22.0,
        'tempHighC': 26.0,
        'targetSurvivalPct': 95.0,
        'allowAnaesthetic': true,
        'allowZeolite': false,
        'maxFastingH': 48.0,
      });
    });
  });

  group('HTTP repository', () {
    test('posts the shipment to the facility endpoint with the token', () async {
      late http.Request captured;
      final repository = HttpExportRepository(
        apiBaseUrl: 'https://api.example.com',
        sessionStorage: _MemorySessionStorage(),
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            '{"id":"plan-1","label":null,"createdAt":"2026-10-21T08:00:00Z",'
            '"request":{},"advisory":$sampleAdvisoryJson}',
            201,
          );
        }),
      );

      final detail = await repository.createAdvisory(
        facilityId: 'facility-1',
        request: const ExportShipmentRequest(
          species: ExportSpecies.guppy,
          fishMassG: 0.3,
          waterL: 0.4,
          gasL: 1.2,
          durationH: 36,
          tempLowC: 24,
          tempHighC: 28,
        ),
      );

      expect(captured.method, 'POST');
      expect(
        captured.url.path,
        '/api/v1/facilities/facility-1/export-advisories',
      );
      expect(captured.headers['authorization'], 'Bearer access-token');
      expect(jsonDecode(captured.body)['species'], 'guppy');
      expect(detail.id, 'plan-1');
      expect(detail.advisory.recommendation.fishPerBag, greaterThan(0));
    });

    test('maps server errors to readable messages', () async {
      final repository = HttpExportRepository(
        apiBaseUrl: 'https://api.example.com',
        sessionStorage: _MemorySessionStorage(),
        client: MockClient(
          (_) async => http.Response(
            '{"code":"export_simulator_unavailable",'
            '"message":"The transit simulator is not available right now."}',
            503,
          ),
        ),
      );

      await expectLater(
        repository.listAdvisories('facility-1'),
        throwsA(
          isA<ExportException>().having(
            (error) => error.code,
            'code',
            'export_simulator_unavailable',
          ),
        ),
      );
    });

    test('requires a signed-in session', () async {
      final repository = HttpExportRepository(
        apiBaseUrl: 'https://api.example.com',
        sessionStorage: _MemorySessionStorage(hasSession: false),
        client: MockClient((_) async => http.Response('[]', 200)),
      );

      await expectLater(
        repository.listAdvisories('facility-1'),
        throwsA(isA<ExportException>()),
      );
    });
  });

  group('screens', () {
    testWidgets('plans a shipment and shows the full advisory', (
      tester,
    ) async {
      final repository = DevelopmentExportRepository(delay: Duration.zero);
      await tester.pumpWidget(
        MaterialApp(
          home: ExportPlansScreen(facility: facility, repository: repository),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No shipment plans yet'), findsOneWidget);

      await tester.tap(find.byKey(const Key('export-new-plan-button')));
      await tester.pumpAndSettle();
      expect(find.text('Plan a shipment'), findsWidgets);

      await tester.enterText(
        find.byKey(const Key('export-label-field')),
        'Dubai order',
      );
      final submit = find.byKey(const Key('export-submit-button'));
      await tester.scrollUntilVisible(
        submit,
        300,
        scrollable: find.descendant(
          of: find.byKey(const Key('export-form-scroll')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('export-plan-summary')), findsOneWidget);
      expect(find.text('What to add — and how much'), findsOneWidget);

      await tester.tap(find.text('Oxygen'));
      await tester.pumpAndSettle();
      expect(find.text('Oxygen dissolved in the water'), findsOneWidget);

      await tester.tap(find.text('Survival'));
      await tester.pumpAndSettle();
      expect(find.text('Fish alive'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Dubai order'), findsOneWidget);
    });

    testWidgets('shows an infeasible plan without the tabs', (tester) async {
      final json = jsonDecode(sampleAdvisoryJson) as Map<String, dynamic>
        ..['feasible'] = false
        ..['recommendation'] = {'summary': 'No plan keeps 95% alive.'};
      await tester.pumpWidget(
        MaterialApp(
          home: ExportAdvisoryScreen(
            detail: ExportAdvisoryDetail(
              id: 'plan-x',
              createdAt: DateTime.utc(2026, 10, 21),
              advisory: TransitAdvisory.fromJson(json),
            ),
          ),
        ),
      );

      expect(find.text('No plan keeps 95% alive.'), findsOneWidget);
      expect(find.byKey(const Key('export-advisory-tabs')), findsNothing);
    });
  });
}

class _MemorySessionStorage implements AuthSessionStorage {
  _MemorySessionStorage({this.hasSession = true});

  final bool hasSession;

  @override
  Future<void> clear() async {}

  @override
  Future<AuthTokens?> readTokens() async {
    if (!hasSession) return null;
    return AuthTokens(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
  }

  @override
  Future<void> writeTokens(AuthTokens tokens) async {}
}
