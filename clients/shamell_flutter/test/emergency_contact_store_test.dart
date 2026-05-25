import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/emergency_contact_store.dart';

String _scopedEmergencyContactSecureKey(String prefix, String scope) =>
    '$prefix$scope';

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
              throw PlatformException(
                code: 'secure-read-failed',
                message: 'simulated secure storage read failure',
              );
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
    await clearEmergencyContactRecord();
  });

  test(
      'emergency contact ignores legacy SharedPreferences when secure storage is readable and fallback is disabled',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'shamell.security.emergency_contact.name': 'Alice',
      'shamell.security.emergency_contact.phone': '+1234567',
    });

    final record = await loadEmergencyContactRecord();
    final sp = await SharedPreferences.getInstance();

    expect(record.name, isEmpty);
    expect(record.phone, isEmpty);
    expect(sp.getString('shamell.security.emergency_contact.name'), isNull);
    expect(sp.getString('shamell.security.emergency_contact.phone'), isNull);
    expect(secStore, isEmpty);
  });

  test(
      'emergency contact allows legacy SharedPreferences when secure storage read fails',
      () async {
    throwOnSecureRead = true;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'shamell.security.emergency_contact.name': 'Alice',
      'shamell.security.emergency_contact.phone': '+1234567',
    });

    final record = await loadEmergencyContactRecord();
    final sp = await SharedPreferences.getInstance();

    expect(record.name, 'Alice');
    expect(record.phone, '+1234567');
    expect(sp.getString('shamell.security.emergency_contact.name'), 'Alice');
    expect(
        sp.getString('shamell.security.emergency_contact.phone'), '+1234567');
  });

  test('emergency contact migrates from secure storage', () async {
    secStore[_scopedEmergencyContactSecureKey(
      'shamell.security.emergency_contact.name.v2.',
      'unknown',
    )] = 'Alice';
    secStore[_scopedEmergencyContactSecureKey(
      'shamell.security.emergency_contact.phone.v2.',
      'unknown',
    )] = '+1234567';

    final record = await loadEmergencyContactRecord();
    final sp = await SharedPreferences.getInstance();

    expect(record.name, 'Alice');
    expect(record.phone, '+1234567');
    expect(sp.getString('shamell.security.emergency_contact.name'), isNull);
    expect(sp.getString('shamell.security.emergency_contact.phone'), isNull);
    expect(
      secStore[_scopedEmergencyContactSecureKey(
        'shamell.security.emergency_contact.name.v2.',
        'unknown',
      )],
      'Alice',
    );
    expect(
      secStore[_scopedEmergencyContactSecureKey(
        'shamell.security.emergency_contact.phone.v2.',
        'unknown',
      )],
      '+1234567',
    );
  });

  test('emergency contact saves and clears through secure storage', () async {
    final saved = await saveEmergencyContactRecord(
      name: 'Bob',
      phone: '+7654321',
    );
    expect(saved, isTrue);

    final record = await loadEmergencyContactRecord();
    expect(record.name, 'Bob');
    expect(record.phone, '+7654321');

    await clearEmergencyContactRecord();
    final cleared = await loadEmergencyContactRecord();
    expect(cleared.name, isEmpty);
    expect(cleared.phone, isEmpty);
  });

  test('emergency contact stays isolated across canonical API origins',
      () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');

    expect(
      await saveEmergencyContactRecord(name: 'Alice', phone: '+111'),
      isTrue,
    );
    expect((await loadEmergencyContactRecord()).name, 'Alice');

    await sp.setString('base_url', 'https://api.two.example');
    final isolated = await loadEmergencyContactRecord();
    expect(isolated.name, isEmpty);
    expect(isolated.phone, isEmpty);

    expect(
      await saveEmergencyContactRecord(name: 'Bob', phone: '+222'),
      isTrue,
    );
    expect((await loadEmergencyContactRecord()).name, 'Bob');

    await sp.setString('base_url', 'https://api.one.example');
    final firstOrigin = await loadEmergencyContactRecord();
    expect(firstOrigin.name, 'Alice');
    expect(firstOrigin.phone, '+111');
  });

  test(
      'legacy global emergency contact does not rebind into trusted canonical origins',
      () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.example.com');
    await sp.setString('shamell.security.emergency_contact.name', 'Legacy');
    await sp.setString('shamell.security.emergency_contact.phone', '+999');
    secStore['shamell.security.emergency_contact.name.v1'] = 'Legacy';
    secStore['shamell.security.emergency_contact.phone.v1'] = '+999';

    final record = await loadEmergencyContactRecord();

    expect(record.name, isEmpty);
    expect(record.phone, isEmpty);
    expect(sp.getString('shamell.security.emergency_contact.name'), isNull);
    expect(sp.getString('shamell.security.emergency_contact.phone'), isNull);
    expect(secStore['shamell.security.emergency_contact.name.v1'], isNull);
    expect(secStore['shamell.security.emergency_contact.phone.v1'], isNull);
    expect(
      secStore[_scopedEmergencyContactSecureKey(
        'shamell.security.emergency_contact.name.v2.',
        'https://api.example.com',
      )],
      isNull,
    );
    expect(
      secStore[_scopedEmergencyContactSecureKey(
        'shamell.security.emergency_contact.phone.v2.',
        'https://api.example.com',
      )],
      isNull,
    );
  });

  test(
      'emergency contact honors explicit baseUrl override over global scope and clears only current scope',
      () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.two.example');

    expect(
      await saveEmergencyContactRecord(
        name: 'Alice',
        phone: '+111',
        sp: sp,
        baseUrlOverride: 'https://api.one.example',
      ),
      isTrue,
    );
    expect(
      await saveEmergencyContactRecord(
        name: 'Bob',
        phone: '+222',
        sp: sp,
        baseUrlOverride: 'https://api.two.example',
      ),
      isTrue,
    );

    final originOne = await loadEmergencyContactRecord(
      sp: sp,
      baseUrlOverride: 'https://api.one.example',
    );
    final originTwo = await loadEmergencyContactRecord(
      sp: sp,
      baseUrlOverride: 'https://api.two.example',
    );
    expect(originOne.name, 'Alice');
    expect(originOne.phone, '+111');
    expect(originTwo.name, 'Bob');
    expect(originTwo.phone, '+222');

    await clearEmergencyContactRecord(
      sp: sp,
      baseUrlOverride: 'https://api.one.example',
    );

    final clearedOriginOne = await loadEmergencyContactRecord(
      sp: sp,
      baseUrlOverride: 'https://api.one.example',
    );
    final preservedOriginTwo = await loadEmergencyContactRecord(
      sp: sp,
      baseUrlOverride: 'https://api.two.example',
    );
    expect(clearedOriginOne.name, isEmpty);
    expect(clearedOriginOne.phone, isEmpty);
    expect(preservedOriginTwo.name, 'Bob');
    expect(preservedOriginTwo.phone, '+222');
  });
}
