import 'package:flutter/widgets.dart';

import 'authentication_controller.dart';

class AuthenticationScope extends InheritedNotifier<AuthenticationController> {
  const AuthenticationScope({
    required AuthenticationController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static AuthenticationController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AuthenticationScope>();
    assert(scope != null, 'AuthenticationScope was not found.');
    return scope!.notifier!;
  }
}
