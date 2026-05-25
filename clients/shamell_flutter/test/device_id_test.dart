import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/device_id.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const attestationChannel = MethodChannel('shamell/hardware_attestation');
  final secStore = <String, String>{};
  var throwOnSecureRead = false;
  String? mockAndroidSecureId;

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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      attestationChannel,
      (call) async {
        if (call.method == 'android_secure_id') {
          return mockAndroidSecureId;
        }
        return null;
      },
    );
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(attestationChannel, null);
  });

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    shamellAllowSyntheticAndroidSecureIdProbe = true;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    secStore.clear();
    throwOnSecureRead = false;
    mockAndroidSecureId = null;
    await clearStableDeviceId();
  });

  tearDown(() {
    shamellAllowSyntheticAndroidSecureIdProbe = false;
    debugDefaultTargetPlatformOverride = null;
  });

  test(
      'stable device id ignores legacy SharedPreferences by default in unknown scope',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kStableDeviceIdPrefKey: 'stable123',
    });

    expect(await loadStableDeviceId(), isNull);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString(kStableDeviceIdPrefKey), isNull);
  });

  test('stable device id allows legacy fallback when secure reads fail',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kStableDeviceIdPrefKey: 'stable123',
    });
    throwOnSecureRead = true;

    expect(await loadStableDeviceId(), 'stable123');
  });

  test('stable device id stays isolated across API origins', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.alpha.example',
    });

    expect(await saveStableDeviceId('device-alpha'), isTrue);
    expect(await loadStableDeviceId(), 'device-alpha');

    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.beta.example');
    expect(await loadStableDeviceId(), isNull);

    expect(await saveStableDeviceId('device-beta'), isTrue);
    expect(await loadStableDeviceId(), 'device-beta');

    await sp.setString('base_url', 'https://api.alpha.example');
    expect(await loadStableDeviceId(), 'device-alpha');
  });

  test('legacy global stable device id does not rebind into canonical origins',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      kStableDeviceIdPrefKey: 'legacy-device',
    });

    expect(await loadStableDeviceId(), isNull);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString(kStableDeviceIdPrefKey), isNull);
  });

  test('stable device id saves and clears through secure storage', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
    });

    expect(await saveStableDeviceId('device-123'), isTrue);
    expect(await loadStableDeviceId(), 'device-123');

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString(kStableDeviceIdPrefKey), isNull);

    await clearStableDeviceId();
    expect(await loadStableDeviceId(), isNull);
  });

  test('stable device id pins the attached trusted Android handset', () async {
    mockAndroidSecureId = '71a05a7e9af77a62';

    expect(
      await getOrCreateStableDeviceId(),
      'android-dev-trusted-71a05a7e9af77a62',
    );
    expect(await loadStableDeviceId(), 'android-dev-trusted-71a05a7e9af77a62');
    expect(
      await saveStableDeviceId('different-device'),
      isFalse,
    );
  });

  test('stable device id pins the app-visible trusted Android handset id',
      () async {
    mockAndroidSecureId = 'd28519355eec5c28';

    expect(
      await getOrCreateStableDeviceId(),
      'android-dev-trusted-71a05a7e9af77a62',
    );
    expect(await loadStableDeviceId(), 'android-dev-trusted-71a05a7e9af77a62');
    expect(
      await saveStableDeviceId('different-device'),
      isFalse,
    );
  });
}
