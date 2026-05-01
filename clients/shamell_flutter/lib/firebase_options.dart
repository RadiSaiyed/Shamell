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

  // Web options placeholder for Shamell.
  // Replace with real values via `flutterfire configure` before production use.
  static final FirebaseOptions web = const FirebaseOptions(
    apiKey: 'REPLACE_WITH_FIREBASE_API_KEY',
    appId: '1:000000000000:web:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'online-shamell-app',
    authDomain: 'online-shamell-app.firebaseapp.com',
    storageBucket: 'online-shamell-app.firebasestorage.app',
    measurementId: 'G-REPLACE_ME',
  );
}
