import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app/app.dart';
import 'package:mobile_app/app/config/app_environment.dart';
import 'package:mobile_app/app/routing/app_routes.dart';

void main() {
  Widget buildApp() {
    return const AquaSenseApp(environment: AppEnvironment.test());
  }

  testWidgets('starts with AquaSense onboarding and theme', (tester) async {
    await tester.pumpWidget(buildApp());

    expect(find.text('Smarter feeding starts here'), findsOneWidget);
    expect(find.text('Continue to sign in'), findsOneWidget);

    final context = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(context).useMaterial3, isTrue);
    expect(Theme.of(context).colorScheme.primary, isNot(Colors.deepPurple));
  });

  testWidgets('named routes open sign-in and home placeholders', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pushNamed(AppRoutes.signIn);
    await tester.pumpAndSettle();
    expect(find.text('Sign in to your aquarium'), findsOneWidget);

    navigator.pushNamed(AppRoutes.home);
    await tester.pumpAndSettle();
    expect(find.text('Your aquarium overview'), findsOneWidget);
  });

  testWidgets('unknown routes show a recoverable not-found screen', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pushNamed('/missing');
    await tester.pumpAndSettle();

    expect(find.text('Page not found'), findsOneWidget);
    expect(find.text('We could not open /missing.'), findsOneWidget);
    expect(find.text('Return to start'), findsOneWidget);
  });
}
