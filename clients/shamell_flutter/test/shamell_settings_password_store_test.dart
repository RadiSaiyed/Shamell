import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/local_password_hash.dart';
import 'package:shamell_flutter/core/shamell_settings_password_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secStore = <String, String>{};

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
    await clearStoredLocalPasswordHash();
  });

  test('local password hash stays isolated across API origins', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.alpha.example',
    });

    final alphaHash = hashLocalPassword('alpha-secret');
    expect(await saveStoredLocalPasswordHash(alphaHash), isTrue);
    expect(await loadStoredLocalPasswordHash(), alphaHash);

    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.beta.example');
    expect(await loadStoredLocalPasswordHash(), isNull);

    final betaHash = hashLocalPassword('beta-secret');
    expect(await saveStoredLocalPasswordHash(betaHash), isTrue);
    expect(await loadStoredLocalPasswordHash(), betaHash);

    await sp.setString('base_url', 'https://api.alpha.example');
    expect(await loadStoredLocalPasswordHash(), alphaHash);
  });

  test('local password hash honors explicit baseUrl override scope', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.alpha.example',
    });

    final betaHash = hashLocalPassword('beta-secret');
    expect(
      await saveStoredLocalPasswordHash(
        betaHash,
        baseUrlOverride: 'https://api.beta.example',
      ),
      isTrue,
    );
    expect(
      await loadStoredLocalPasswordHash(
        baseUrlOverride: 'https://api.beta.example',
      ),
      betaHash,
    );
    expect(await loadStoredLocalPasswordHash(), isNull);
  });

  test('clearing current password scope honors explicit baseUrl override',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.alpha.example',
    });

    final alphaHash = hashLocalPassword('alpha-secret');
    final betaHash = hashLocalPassword('beta-secret');
    expect(await saveStoredLocalPasswordHash(alphaHash), isTrue);
    expect(
      await saveStoredLocalPasswordHash(
        betaHash,
        baseUrlOverride: 'https://api.beta.example',
      ),
      isTrue,
    );

    await clearStoredLocalPasswordHashForCurrentScope(
      baseUrlOverride: 'https://api.beta.example',
    );

    expect(
      await loadStoredLocalPasswordHash(
        baseUrlOverride: 'https://api.beta.example',
      ),
      isNull,
    );
    expect(await loadStoredLocalPasswordHash(), alphaHash);
  });

  test('legacy global password hash migrates only in unknown scope', () async {
    final legacyHash = hashLocalPassword('legacy-secret');
    secStore['shamell.security.password_hash.v1'] = legacyHash;

    expect(await loadStoredLocalPasswordHash(), legacyHash);
    expect(secStore['shamell.security.password_hash.v1'], isNull);
    expect(
      secStore['shamell.security.password_hash.v2.unknown'],
      legacyHash,
    );
  });

  test('legacy global password hash does not rebind into canonical origins',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
    });
    final legacyHash = hashLocalPassword('legacy-secret');
    secStore['shamell.security.password_hash.v1'] = legacyHash;

    expect(await loadStoredLocalPasswordHash(), isNull);
    expect(secStore['shamell.security.password_hash.v1'], isNull);
    expect(secStore.containsKey('shamell.security.password_hash.v2.unknown'),
        isFalse);
    expect(
      secStore.containsKey(
          'shamell.security.password_hash.v2.https://api.example.com'),
      isFalse,
    );
  });

  test('malformed scoped password hash is cleared and rejected', () async {
    secStore['shamell.security.password_hash.v2.unknown'] = 'not-a-hash';

    expect(await loadStoredLocalPasswordHash(), isNull);
    expect(
      secStore.containsKey('shamell.security.password_hash.v2.unknown'),
      isFalse,
    );
  });

  test('malformed legacy global password hash is discarded', () async {
    secStore['shamell.security.password_hash.v1'] = 'not-a-hash';

    expect(await loadStoredLocalPasswordHash(), isNull);
    expect(secStore['shamell.security.password_hash.v1'], isNull);
    expect(
      secStore.containsKey('shamell.security.password_hash.v2.unknown'),
      isFalse,
    );
  });
}
