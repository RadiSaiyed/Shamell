import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import 'core/app_surface.dart';

const String _firebaseApiKey = String.fromEnvironment(
  'SHAMELL_FIREBASE_API_KEY',
  defaultValue: '',
);
const String _firebaseMessagingSenderId = String.fromEnvironment(
  'SHAMELL_FIREBASE_MESSAGING_SENDER_ID',
  defaultValue: '',
);
const String _firebaseProjectId = String.fromEnvironment(
  'SHAMELL_FIREBASE_PROJECT_ID',
  defaultValue: '',
);
const String _firebaseStorageBucket = String.fromEnvironment(
  'SHAMELL_FIREBASE_STORAGE_BUCKET',
  defaultValue: '',
);
const String _firebaseAuthDomain = String.fromEnvironment(
  'SHAMELL_FIREBASE_AUTH_DOMAIN',
  defaultValue: '',
);
const String _firebaseMeasurementId = String.fromEnvironment(
  'SHAMELL_FIREBASE_MEASUREMENT_ID',
  defaultValue: '',
);
const String _firebaseAndroidAppIdSuperapp = String.fromEnvironment(
  'SHAMELL_FIREBASE_ANDROID_APP_ID_SUPERAPP',
  defaultValue: '',
);
const String _firebaseAndroidAppIdRide = String.fromEnvironment(
  'SHAMELL_FIREBASE_ANDROID_APP_ID_RIDE',
  defaultValue: '',
);
const String _firebaseAndroidAppIdDriver = String.fromEnvironment(
  'SHAMELL_FIREBASE_ANDROID_APP_ID_DRIVER',
  defaultValue: '',
);
const String _firebaseAndroidAppIdOperator = String.fromEnvironment(
  'SHAMELL_FIREBASE_ANDROID_APP_ID_OPERATOR',
  defaultValue: '',
);
const String _firebaseAndroidAppIdBusOperator = String.fromEnvironment(
  'SHAMELL_FIREBASE_ANDROID_APP_ID_BUS_OPERATOR',
  defaultValue: '',
);
const String _firebaseAndroidAppIdSyrCom = String.fromEnvironment(
  'SHAMELL_FIREBASE_ANDROID_APP_ID_SYRCOM',
  defaultValue: '',
);
const String _firebaseIosAppIdSuperapp = String.fromEnvironment(
  'SHAMELL_FIREBASE_IOS_APP_ID_SUPERAPP',
  defaultValue: '',
);
const String _firebaseIosAppIdRide = String.fromEnvironment(
  'SHAMELL_FIREBASE_IOS_APP_ID_RIDE',
  defaultValue: '',
);
const String _firebaseIosAppIdDriver = String.fromEnvironment(
  'SHAMELL_FIREBASE_IOS_APP_ID_DRIVER',
  defaultValue: '',
);
const String _firebaseIosAppIdOperator = String.fromEnvironment(
  'SHAMELL_FIREBASE_IOS_APP_ID_OPERATOR',
  defaultValue: '',
);
const String _firebaseIosAppIdBusOperator = String.fromEnvironment(
  'SHAMELL_FIREBASE_IOS_APP_ID_BUS_OPERATOR',
  defaultValue: '',
);
const String _firebaseIosAppIdSyrCom = String.fromEnvironment(
  'SHAMELL_FIREBASE_IOS_APP_ID_SYRCOM',
  defaultValue: '',
);
const String _firebaseWebAppId = String.fromEnvironment(
  'SHAMELL_FIREBASE_WEB_APP_ID',
  defaultValue: '',
);
const String _firebaseMacosAppId = String.fromEnvironment(
  'SHAMELL_FIREBASE_MACOS_APP_ID',
  defaultValue: '',
);
const String _firebaseIosBundleIdSuperapp = String.fromEnvironment(
  'SHAMELL_FIREBASE_IOS_BUNDLE_ID_SUPERAPP',
  defaultValue: '',
);
const String _firebaseIosBundleIdRide = String.fromEnvironment(
  'SHAMELL_FIREBASE_IOS_BUNDLE_ID_RIDE',
  defaultValue: '',
);
const String _firebaseIosBundleIdDriver = String.fromEnvironment(
  'SHAMELL_FIREBASE_IOS_BUNDLE_ID_DRIVER',
  defaultValue: '',
);
const String _firebaseIosBundleIdOperator = String.fromEnvironment(
  'SHAMELL_FIREBASE_IOS_BUNDLE_ID_OPERATOR',
  defaultValue: '',
);
const String _firebaseIosBundleIdBusOperator = String.fromEnvironment(
  'SHAMELL_FIREBASE_IOS_BUNDLE_ID_BUS_OPERATOR',
  defaultValue: '',
);
const String _firebaseIosBundleIdSyrCom = String.fromEnvironment(
  'SHAMELL_FIREBASE_IOS_BUNDLE_ID_SYRCOM',
  defaultValue: '',
);

String? _usableFirebaseValue(String raw) {
  final value = raw.trim();
  if (value.isEmpty) {
    return null;
  }
  final normalized = value.toLowerCase();
  if (normalized.contains('replace_with_') ||
      normalized.contains('placeholder') ||
      value == '000000000000' ||
      normalized.contains(':000000000000:')) {
    return null;
  }
  return value;
}

String? _firebaseAndroidAppIdForSurface(ShamellAppSurface surface) {
  switch (surface) {
    case ShamellAppSurface.ride:
      return _usableFirebaseValue(_firebaseAndroidAppIdRide);
    case ShamellAppSurface.driver:
      return _usableFirebaseValue(_firebaseAndroidAppIdDriver);
    case ShamellAppSurface.operator:
      return _usableFirebaseValue(_firebaseAndroidAppIdOperator);
    case ShamellAppSurface.busOperator:
      return _usableFirebaseValue(_firebaseAndroidAppIdBusOperator);
    case ShamellAppSurface.hotelOperator:
      // Hotel operator flavor ships without Firebase (no push, no analytics)
      // until a real Android app is registered in the shamell Firebase
      // project for online.shamell.hoteloperator.
      return null;
    case ShamellAppSurface.carrier:
      // Same status as hotelOperator: no Firebase app registered yet
      // for online.shamell.carrier. Phase 3 (carrier endpoints + push
      // notifications for load offers) will provision one.
      return null;
    case ShamellAppSurface.syrcom:
      return _usableFirebaseValue(_firebaseAndroidAppIdSyrCom);
    case ShamellAppSurface.superapp:
      return _usableFirebaseValue(_firebaseAndroidAppIdSuperapp);
  }
}

String? _firebaseIosAppIdForSurface(ShamellAppSurface surface) {
  switch (surface) {
    case ShamellAppSurface.ride:
      return _usableFirebaseValue(_firebaseIosAppIdRide);
    case ShamellAppSurface.driver:
      return _usableFirebaseValue(_firebaseIosAppIdDriver);
    case ShamellAppSurface.operator:
      return _usableFirebaseValue(_firebaseIosAppIdOperator);
    case ShamellAppSurface.busOperator:
      return _usableFirebaseValue(_firebaseIosAppIdBusOperator);
    case ShamellAppSurface.hotelOperator:
      return null;
    case ShamellAppSurface.carrier:
      return null;
    case ShamellAppSurface.syrcom:
      return _usableFirebaseValue(_firebaseIosAppIdSyrCom);
    case ShamellAppSurface.superapp:
      return _usableFirebaseValue(_firebaseIosAppIdSuperapp);
  }
}

String? _firebaseIosBundleIdForSurface(ShamellAppSurface surface) {
  switch (surface) {
    case ShamellAppSurface.ride:
      return _usableFirebaseValue(_firebaseIosBundleIdRide);
    case ShamellAppSurface.driver:
      return _usableFirebaseValue(_firebaseIosBundleIdDriver);
    case ShamellAppSurface.operator:
      return _usableFirebaseValue(_firebaseIosBundleIdOperator);
    case ShamellAppSurface.busOperator:
      return _usableFirebaseValue(_firebaseIosBundleIdBusOperator);
    case ShamellAppSurface.hotelOperator:
      return null;
    case ShamellAppSurface.carrier:
      return null;
    case ShamellAppSurface.syrcom:
      return _usableFirebaseValue(_firebaseIosBundleIdSyrCom);
    case ShamellAppSurface.superapp:
      return _usableFirebaseValue(_firebaseIosBundleIdSuperapp);
  }
}

FirebaseOptions? _firebaseOptions({
  required String? appId,
  String? authDomain,
  String? measurementId,
  String? iosBundleId,
}) {
  final apiKey = _usableFirebaseValue(_firebaseApiKey);
  final messagingSenderId = _usableFirebaseValue(_firebaseMessagingSenderId);
  final projectId = _usableFirebaseValue(_firebaseProjectId);
  final resolvedAppId = _usableFirebaseValue(appId ?? '');
  if (apiKey == null ||
      messagingSenderId == null ||
      projectId == null ||
      resolvedAppId == null) {
    return null;
  }
  return FirebaseOptions(
    apiKey: apiKey,
    appId: resolvedAppId,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    storageBucket: _usableFirebaseValue(_firebaseStorageBucket),
    authDomain: _usableFirebaseValue(authDomain ?? ''),
    measurementId: _usableFirebaseValue(measurementId ?? ''),
    iosBundleId: _usableFirebaseValue(iosBundleId ?? ''),
  );
}

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    final options = currentPlatformOrNull;
    if (options != null) {
      return options;
    }
    throw UnsupportedError(
      'No Firebase options are configured for $defaultTargetPlatform and '
      'surface ${shamellActiveAppSurface.name}. Provide real flavor '
      'google-services files or SHAMELL_FIREBASE_* dart-defines.',
    );
  }

  static FirebaseOptions? get currentPlatformOrNull {
    if (kIsWeb) {
      return _firebaseOptions(
        appId: _firebaseWebAppId,
        authDomain: _firebaseAuthDomain,
        measurementId: _firebaseMeasurementId,
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _firebaseOptions(
          appId: _firebaseAndroidAppIdForSurface(shamellActiveAppSurface),
        );
      case TargetPlatform.iOS:
        return _firebaseOptions(
          appId: _firebaseIosAppIdForSurface(shamellActiveAppSurface),
          iosBundleId: _firebaseIosBundleIdForSurface(shamellActiveAppSurface),
        );
      case TargetPlatform.macOS:
        return _firebaseOptions(
          appId: _firebaseMacosAppId,
        );
      default:
        return null;
    }
  }
}
