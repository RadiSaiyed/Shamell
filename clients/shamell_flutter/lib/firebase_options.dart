// Generated-style placeholder for Firebase web options.
// Recommended: replace this file by running `flutterfire configure` which
// generates real values for all platforms.
// For quick Web testing, you can pass --dart-define values for the below keys.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    throw UnsupportedError(
      'DefaultFirebaseOptions is only provided for Web in this stub. '
      'Run `flutterfire configure` to generate full options for all platforms.',
    );
  }

  // Web options: configured for project "syriasuperapp" (provided by you)
  static final FirebaseOptions web = const FirebaseOptions(
    apiKey: 'AIzaSyBv1agGjRsWTTkRijdtRm36LPITqxpJkhQ',
    appId: '1:202621626273:web:c9e3a8d3f2958335fb0de0',
    messagingSenderId: '202621626273',
    projectId: 'syriasuperapp',
    authDomain: 'syriasuperapp.firebaseapp.com',
    storageBucket: 'syriasuperapp.firebasestorage.app',
    measurementId: 'G-931JEKJ26W',
  );
}
