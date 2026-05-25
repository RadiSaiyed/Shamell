import 'dart:async';

import 'package:flutter/material.dart';

import 'device_binding_guard.dart';
import 'logout_wipe.dart';

PageRoute<void> _shamellImmediateLoginRoute(WidgetBuilder builder) {
  return PageRouteBuilder<void>(
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
  );
}

Future<bool> shamellForceReauthIfCriticalAccountSessionHttpFailure(
  BuildContext context, {
  required int statusCode,
  String? rawBody,
  required WidgetBuilder loginPageBuilder,
}) async {
  if (!shamellIsCriticalAccountSessionHttpFailure(
    statusCode: statusCode,
    rawBody: rawBody,
  )) {
    return false;
  }
  unawaited(
    wipeLocalAccountData(
      preserveDevicePrefs: true,
    ).catchError((_) {}),
  );
  if (context.mounted) {
    unawaited(Navigator.of(context).pushAndRemoveUntil(
      _shamellImmediateLoginRoute(loginPageBuilder),
      (route) => false,
    ));
  }
  return true;
}

Future<bool> shamellForceReauthIfCriticalDeviceBindingDrift(
  BuildContext context, {
  required Object error,
  required WidgetBuilder loginPageBuilder,
}) async {
  if (!shamellIsCriticalAccountSessionError(error)) return false;
  unawaited(
    wipeLocalAccountData(
      preserveDevicePrefs: true,
    ).catchError((_) {}),
  );
  if (context.mounted) {
    unawaited(Navigator.of(context).pushAndRemoveUntil(
      _shamellImmediateLoginRoute(loginPageBuilder),
      (route) => false,
    ));
  }
  return true;
}
