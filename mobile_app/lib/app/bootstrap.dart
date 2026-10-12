import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/widgets/app_error_view.dart';
import 'app.dart';
import 'config/app_environment.dart';

Future<void> bootstrap({AppEnvironment? environment}) async {
  WidgetsFlutterBinding.ensureInitialized();

  final resolvedEnvironment = environment ?? AppEnvironment.fromDartDefines();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'AquaSense application',
      ),
    );
    return true;
  };

  ErrorWidget.builder = (details) =>
      const AppErrorView(message: 'This screen could not be displayed.');

  runZonedGuarded(
    () => runApp(AquaSenseApp(environment: resolvedEnvironment)),
    (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'AquaSense application zone',
        ),
      );
    },
  );
}
