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

    test('advice is plain language; studies stay in the method section', () {
      final advisory = DevelopmentExportRepository.sampleAdvisory();
      final citation = RegExp(r'et al|\(\d{4}\)|\b(19|20)\d{2}\b');

      for (final dose in [
        ...advisory.recommendation.doses,
        ...advisory.recommendation.notSimulated,
      ]) {
        expect(dose.why, isNotEmpty);
        expect(citation.hasMatch(dose.why), isFalse, reason: dose.why);
        expect(citation.hasMatch(dose.caution), isFalse, reason: dose.caution);
      }
      final method = advisory.method!;
      expect(method.steps, isNotEmpty);
      expect(method.sources.first.title, contains('Pramod'));
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
        'mode': 'suggest',
      });
    });

    test('check mode sends the exporter\'s own packing', () {
      const request = ExportShipmentRequest(
        species: ExportSpecies.guppy,
        fishMassG: 0.3,
        waterL: 0.4,
        gasL: 1.2,
        durationH: 36,
        tempLowC: 24,
        tempHighC: 28,
        mode: PlanningMode.check,
        fishPerBag: 150,
        checkAnaesthetic: BagAnaesthetic.ms222,
      );

      final json = request.toJson();
      expect(json['mode'], 'check');
      expect(json['fishPerBag'], 150);
      expect(json['checkAnaesthetic'], 'ms222_40mgL');
      expect(json['checkZeolite'], false);
      expect(json.containsKey('bags'), isFalse);
    });

    test('parses a failed verdict', () {
      final json = jsonDecode(sampleAdvisoryJson) as Map<String, dynamic>
        ..['verdict'] = {
          'mode': 'check',
          'meets_target': false,
          'message': 'Your packing is NOT safe',
          'recommended_fish_per_bag': 48,
          'recommended_bags': 21,
        };
      final advisory = TransitAdvisory.fromJson(json);

      expect(advisory.mode, PlanningMode.check);
      expect(advisory.verdict!.meetsTarget, isFalse);
      expect(advisory.verdict!.recommendedBags, 21);
    });
  });

  group('HTTP repository', () {
    test(
      'posts the shipment to the facility endpoint with the token',
      () async {
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
      },
    );

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
    testWidgets('plans a shipment and shows the full advisory', (tester) async {
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
      // The submit button is pinned below the form, so no scrolling needed.
      await tester.tap(find.byKey(const Key('export-submit-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('export-plan-summary')), findsOneWidget);
      expect(find.byKey(const Key('export-fish-per-bag')), findsOneWidget);
      expect(find.text('Before you pack'), findsOneWidget);
      // The sample advisory flags unpacking as dangerous.
      expect(find.text('Take care when opening the bags'), findsOneWidget);

      await tester.tap(find.text('Journey'));
      await tester.pumpAndSettle();
      expect(find.text('Fish alive'), findsOneWidget);

      await tester.tap(find.byKey(const Key('export-journey-oxygen')));
      await tester.pumpAndSettle();
      expect(find.text('Oxygen dissolved in the water'), findsOneWidget);

      await tester.tap(find.text('Unpacking').first);
      await tester.pumpAndSettle();
      expect(find.text('How to unpack'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Dubai order'), findsOneWidget);
    });

    testWidgets('check mode shows the safety verdict', (tester) async {
      final json = jsonDecode(sampleAdvisoryJson) as Map<String, dynamic>
        ..['verdict'] = {
          'mode': 'check',
          'meets_target': false,
          'message': 'Your packing is NOT safe: survival can fall to 56%.',
          'recommended_fish_per_bag': 48,
          'recommended_plan_label': 'fast 48 h + MS-222',
          'recommended_bags': 21,
        };
      await tester.pumpWidget(
        MaterialApp(
          home: ExportAdvisoryScreen(
            detail: ExportAdvisoryDetail(
              id: 'plan-check',
              createdAt: DateTime.utc(2026, 10, 22),
              advisory: TransitAdvisory.fromJson(json),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('export-plan-verdict')), findsOneWidget);
      expect(
        find.text('Your packing is NOT safe: survival can fall to 56%.'),
        findsOneWidget,
      );
      expect(find.text('What is in your bag'), findsOneWidget);
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
