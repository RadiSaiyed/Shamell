import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/biometric_preference_store.dart';

String _scopedBiometricSecureKey(String scope) =>
    'security.require_biometrics.v2.$scope';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secStore = <String, String>{};
  var throwOnSecureRead = false;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      secChannel,
      (call) async {
        final args = (call.arguments as Map?) ?? const <String, Object?>{};
        final key = (args['key'] ?? '').toString();
        switch (call.method) {
          case 'write':
            secStore[key] = (args['value'] ?? '').toString();
            return null;
          case 'read':
            if (throwOnSecureRead) {
              throw PlatformException(code: 'secure-read-failed');
            }
            return secStore[key];
          case 'delete':
            secStore.remove(key);
            return null;
          case 'deleteAll':
            secStore.clear();
            return null;
          case 'readAll':
            return Map<String, String>.from(secStore);
          case 'containsKey':
            return secStore.containsKey(key);
          default:
            return null;
        }
      },
    );
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secChannel, null);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    secStore.clear();
    throwOnSecureRead = false;
    await clearRequireBiometricsPreference();
  });

  test('biometric preference ignores legacy SharedPreferences by default',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kRequireBiometricsPrefKey: true,
    });

    expect(await loadRequireBiometricsPreference(), isFalse);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getBool(kRequireBiometricsPrefKey), isNull);
    expect(secStore[_scopedBiometricSecureKey('unknown')], isNull);
  });

  test('biometric preference allows legacy fallback when secure reads fail',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kRequireBiometricsPrefKey: true,
    });
    throwOnSecureRead = true;

    expect(await loadRequireBiometricsPreference(), isTrue);
  });

  test('biometric preference saves and clears through secure storage',
      () async {
    expect(await saveRequireBiometricsPreference(true), isTrue);
    expect(await loadRequireBiometricsPreference(), isTrue);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getBool(kRequireBiometricsPrefKey), isNull);

    await clearRequireBiometricsPreference();
    expect(await loadRequireBiometricsPreference(), isFalse);
  });

  test('biometric preference stays isolated across canonical API origins',
      () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');

    expect(await saveRequireBiometricsPreference(true), isTrue);
    expect(await loadRequireBiometricsPreference(), isTrue);

    await sp.setString('base_url', 'https://api.two.example');
    expect(await loadRequireBiometricsPreference(), isFalse);

    await sp.setString('base_url', 'https://api.one.example');
    expect(await loadRequireBiometricsPreference(), isTrue);
  });

  test('biometric preference override stays bound to explicit baseUrl scope',
      () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');

    expect(
      await saveRequireBiometricsPreference(
        true,
        sp: sp,
        baseUrlOverride: 'https://API.two.example/',
      ),
      isTrue,
    );

    expect(
      await loadRequireBiometricsPreference(
        sp: sp,
        baseUrlOverride: 'https://api.two.example',
      ),
      isTrue,
    );
    expect(await loadRequireBiometricsPreference(sp: sp), isFalse);
    expect(secStore[_scopedBiometricSecureKey('https://api.two.example')], '1');
    expect(
        secStore[_scopedBiometricSecureKey('https://api.one.example')], isNull);
  });

  test(
      'legacy global biometric preference does not rebind into canonical scope',
      () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.example.com');
    await sp.setBool(kRequireBiometricsPrefKey, true);
    secStore['security.require_biometrics.v1'] = '1';

    expect(await loadRequireBiometricsPreference(), isFalse);
    expect(sp.getBool(kRequireBiometricsPrefKey), isNull);
    expect(secStore['security.require_biometrics.v1'], isNull);
    expect(
      secStore[_scopedBiometricSecureKey('https://api.example.com')],
      isNull,
    );
  });
}
