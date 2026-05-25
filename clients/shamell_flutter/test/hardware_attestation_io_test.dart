import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/hardware_attestation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('shamell/hardware_attestation');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('android emulator probe returns true when platform channel says so',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (call) async {
        if (call.method == 'android_is_emulator') {
          return true;
        }
        return null;
      },
    );

    expect(
      await HardwareAttestation.isProbablyAndroidEmulator(
        platformIsAndroid: true,
      ),
      isTrue,
    );
  });

  test('android secure id probe returns platform value', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (call) async {
        if (call.method == 'android_secure_id') {
          return '71a05a7e9af77a62';
        }
        return null;
      },
    );

    expect(
      await HardwareAttestation.tryGetAndroidSecureId(
        platformIsAndroid: true,
      ),
      '71a05a7e9af77a62',
    );
  });
}
