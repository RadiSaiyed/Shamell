import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/account_identity_store.dart';

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
    await clearStoredAccountIdentity();
  });

  test(
      'legacy shared-preferences identity is ignored when secure storage is readable and fallback is disabled',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'wallet_id': 'wallet-legacy',
      'sa.user_id': 'ABCDEFGH',
    });

    expect(await loadStoredWalletId(), isNull);
    expect(await loadStoredShamellUserId(), isNull);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('wallet_id'), isNull);
    expect(sp.getString('sa.user_id'), isNull);
  });

  test(
      'legacy shared-preferences identity is allowed when secure storage read fails',
      () async {
    throwOnSecureRead = true;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'wallet_id': 'wallet-legacy',
      'sa.user_id': 'ABCDEFGH',
    });

    expect(await loadStoredWalletId(), 'wallet-legacy');
    expect(await loadStoredShamellUserId(), 'ABCDEFGH');

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('wallet_id'), 'wallet-legacy');
    expect(sp.getString('sa.user_id'), 'ABCDEFGH');
  });

  test('account identity is isolated per canonical api origin', () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    expect(await saveStoredWalletId('wallet-one'), isTrue);
    expect(await saveStoredShamellUserId('ABCDEFGH'), isTrue);

    await sp.setString('base_url', 'https://api.two.example');
    expect(await loadStoredWalletId(), isNull);
    expect(await loadStoredShamellUserId(), isNull);

    expect(await saveStoredWalletId('wallet-two'), isTrue);
    expect(await saveStoredShamellUserId('HGFEDCBA'), isTrue);

    await sp.setString('base_url', 'https://api.one.example');
    expect(await loadStoredWalletId(), 'wallet-one');
    expect(await loadStoredShamellUserId(), 'ABCDEFGH');

    await sp.setString('base_url', 'https://api.two.example');
    expect(await loadStoredWalletId(), 'wallet-two');
    expect(await loadStoredShamellUserId(), 'HGFEDCBA');
  });

  test('legacy global identity does not rebind into canonical api origin',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      'wallet_id': 'wallet-legacy',
      'sa.user_id': 'ABCDEFGH',
    });

    expect(await loadStoredWalletId(), isNull);
    expect(await loadStoredShamellUserId(), isNull);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('wallet_id'), isNull);
    expect(sp.getString('sa.user_id'), isNull);
  });

  test('account identity saves and clears through secure storage', () async {
    expect(await saveStoredWalletId('wallet-123'), isTrue);
    expect(await saveStoredShamellUserId('ABCDEFGH'), isTrue);

    expect(await loadStoredWalletId(), 'wallet-123');
    expect(await loadStoredShamellUserId(), 'ABCDEFGH');

    await clearStoredAccountIdentity();
    expect(await loadStoredWalletId(), isNull);
    expect(await loadStoredShamellUserId(), isNull);
  });

  test('account identity honors explicit baseUrl override over global scope',
      () async {
    const originOne = 'https://api.one.example';
    const originTwo = 'https://api.two.example';
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': originTwo,
    });

    expect(
      await saveStoredWalletId(
        'wallet-one',
        baseUrlOverride: originOne,
      ),
      isTrue,
    );
    expect(
      await saveStoredShamellUserId(
        'ABCDEFGH',
        baseUrlOverride: originOne,
      ),
      isTrue,
    );
    expect(
      await saveStoredWalletId(
        'wallet-two',
        baseUrlOverride: originTwo,
      ),
      isTrue,
    );
    expect(
      await saveStoredShamellUserId(
        'HGFEDCBA',
        baseUrlOverride: originTwo,
      ),
      isTrue,
    );

    expect(
      await loadStoredWalletId(baseUrlOverride: originOne),
      'wallet-one',
    );
    expect(
      await loadStoredShamellUserId(baseUrlOverride: originOne),
      'ABCDEFGH',
    );
    expect(
      await loadStoredWalletId(baseUrlOverride: originTwo),
      'wallet-two',
    );
    expect(
      await loadStoredShamellUserId(baseUrlOverride: originTwo),
      'HGFEDCBA',
    );

    await clearStoredWalletId(baseUrlOverride: originOne);
    await clearStoredShamellUserId(baseUrlOverride: originOne);

    expect(await loadStoredWalletId(baseUrlOverride: originOne), isNull);
    expect(await loadStoredShamellUserId(baseUrlOverride: originOne), isNull);
    expect(
      await loadStoredWalletId(baseUrlOverride: originTwo),
      'wallet-two',
    );
    expect(
      await loadStoredShamellUserId(baseUrlOverride: originTwo),
      'HGFEDCBA',
    );
  });

  test('clearStoredAccountIdentity removes identities across all origins',
      () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    expect(await saveStoredWalletId('wallet-one'), isTrue);
    expect(await saveStoredShamellUserId('ABCDEFGH'), isTrue);

    await sp.setString('base_url', 'https://api.two.example');
    expect(await saveStoredWalletId('wallet-two'), isTrue);
    expect(await saveStoredShamellUserId('HGFEDCBA'), isTrue);

    await clearStoredAccountIdentity(sp: sp);

    await sp.setString('base_url', 'https://api.one.example');
    expect(await loadStoredWalletId(sp: sp), isNull);
    expect(await loadStoredShamellUserId(sp: sp), isNull);

    await sp.setString('base_url', 'https://api.two.example');
    expect(await loadStoredWalletId(sp: sp), isNull);
    expect(await loadStoredShamellUserId(sp: sp), isNull);
  });
}
