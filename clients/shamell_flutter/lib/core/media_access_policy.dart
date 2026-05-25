import 'package:flutter/material.dart';

import 'app_surface.dart';
import 'l10n.dart';

/// Customer ride builds must stay fail-closed for camera and microphone.
///
/// The standalone rider app is audited as not having customer camera/mic
/// access, so any runtime entry point that could trigger those APIs must be
/// gated off even if UI wiring regresses later.
bool shamellRideCustomerMediaLocked([ShamellAppSurface? surface]) =>
    shamellIsRideRiderSurface(surface);

bool shamellAllowsCameraCapture([ShamellAppSurface? surface]) =>
    !shamellRideCustomerMediaLocked(surface);

bool shamellAllowsMicrophoneCapture([ShamellAppSurface? surface]) =>
    !shamellRideCustomerMediaLocked(surface);

bool shamellAllowsRealtimeCalls([ShamellAppSurface? surface]) =>
    !shamellRideCustomerMediaLocked(surface);

String shamellRestrictedMediaMessage(
  BuildContext context, {
  required bool camera,
  required bool microphone,
}) {
  final isArabic = L10n.of(context).isArabic;
  if (camera && microphone) {
    return isArabic
        ? 'الكاميرا والميكروفون معطّلان في تطبيق سرتشات رايد.'
        : 'Camera and microphone are disabled in SyrChat Ride.';
  }
  if (camera) {
    return isArabic
        ? 'الوصول إلى الكاميرا معطّل في تطبيق سرتشات رايد.'
        : 'Camera access is disabled in SyrChat Ride.';
  }
  return isArabic
      ? 'الوصول إلى الميكروفون معطّل في تطبيق سرتشات رايد.'
      : 'Microphone access is disabled in SyrChat Ride.';
}

void shamellShowRestrictedMediaSnack(
  BuildContext context, {
  required bool camera,
  required bool microphone,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        shamellRestrictedMediaMessage(
          context,
          camera: camera,
          microphone: microphone,
        ),
      ),
    ),
  );
}
