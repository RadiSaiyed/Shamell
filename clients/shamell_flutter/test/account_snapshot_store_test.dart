import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/account_snapshot_store.dart';

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
    await wipeCachedAccountSnapshots();
  });

  test(
      'home snapshot ignores legacy SharedPreferences when secure storage is readable',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'home_snapshot': '{"wallet":{"wallet_id":"legacy-wallet"}}',
    });

    final first = await loadCachedHomeSnapshotRaw();
    final second = await loadCachedHomeSnapshotRaw();

    expect(first, isNull);
    expect(second, isNull);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('home_snapshot'), isNull);
  });

  test('home snapshot allows legacy fallback when secure reads fail', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'home_snapshot': '{"wallet":{"wallet_id":"legacy-wallet"}}',
    });
    throwOnSecureRead = true;

    final value = await loadCachedHomeSnapshotRaw();

    expect(value, contains('legacy-wallet'));
  });

  test('wallet snapshot saves, loads, and wipes via secure storage', () async {
    await saveCachedWalletSnapshotRaw(
      'wallet-123',
      '{"wallet":{"wallet_id":"wallet-123","balance_cents":42}}',
    );

    expect(
      await loadCachedWalletSnapshotRaw('wallet-123'),
      contains('"balance_cents":42'),
    );

    await wipeCachedAccountSnapshots();

    expect(await loadCachedWalletSnapshotRaw('wallet-123'), isNull);
  });

  test(
      'wallet linked cards ignore legacy prefs when secure storage is readable',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'wallet_linked_cards': <String>[
        '{"label":"Personal","last4":"4242","brand":"visa"}',
      ],
    });

    final migrated = await loadCachedWalletLinkedCardsRawList();
    expect(migrated, isEmpty);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getStringList('wallet_linked_cards'), isNull);

    await wipeCachedAccountSnapshots();
    expect(await loadCachedWalletLinkedCardsRawList(), isEmpty);
  });

  test('wallet linked cards allow legacy fallback when secure reads fail',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'wallet_linked_cards': <String>[
        '{"label":"Personal","last4":"4242","brand":"visa"}',
      ],
    });
    throwOnSecureRead = true;

    final migrated = await loadCachedWalletLinkedCardsRawList();

    expect(migrated, hasLength(1));
    expect(migrated.first, contains('"last4":"4242"'));
  });

  test('account snapshots stay isolated across canonical API origins',
      () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    await saveCachedHomeSnapshotRaw('{"wallet":{"wallet_id":"one"}}');
    await saveCachedWalletSnapshotRaw(
      'wallet-123',
      '{"wallet":{"wallet_id":"wallet-123","balance_cents":11}}',
    );
    await saveCachedWalletLinkedCardsRawList(<String>[
      '{"label":"Primary","last4":"1111"}',
    ]);

    await sp.setString('base_url', 'https://api.two.example');
    expect(await loadCachedHomeSnapshotRaw(), isNull);
    expect(await loadCachedWalletSnapshotRaw('wallet-123'), isNull);
    expect(await loadCachedWalletLinkedCardsRawList(), isEmpty);

    await saveCachedHomeSnapshotRaw('{"wallet":{"wallet_id":"two"}}');

    await sp.setString('base_url', 'https://api.one.example');
    expect(await loadCachedHomeSnapshotRaw(), contains('"wallet_id":"one"'));
    expect(
      await loadCachedWalletSnapshotRaw('wallet-123'),
      contains('"balance_cents":11'),
    );
    expect(await loadCachedWalletLinkedCardsRawList(), hasLength(1));

    await sp.setString('base_url', 'https://api.two.example');
    expect(await loadCachedHomeSnapshotRaw(), contains('"wallet_id":"two"'));
    expect(await loadCachedWalletSnapshotRaw('wallet-123'), isNull);
  });

  test('home snapshots honor explicit baseUrl override over global scope',
      () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.two.example');

    await saveCachedHomeSnapshotRaw(
      '{"wallet":{"wallet_id":"one"}}',
      sp: sp,
      baseUrlOverride: 'https://api.one.example',
    );
    await saveCachedHomeSnapshotRaw(
      '{"wallet":{"wallet_id":"two"}}',
      sp: sp,
      baseUrlOverride: 'https://api.two.example',
    );

    expect(
      await loadCachedHomeSnapshotRaw(
        sp: sp,
        baseUrlOverride: 'https://api.one.example',
      ),
      contains('"wallet_id":"one"'),
    );
    expect(
      await loadCachedHomeSnapshotRaw(
        sp: sp,
        baseUrlOverride: 'https://api.two.example',
      ),
      contains('"wallet_id":"two"'),
    );
  });

  test(
      'wallet snapshot and linked cards honor explicit baseUrl override over global scope',
      () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.two.example');

    await saveCachedWalletSnapshotRaw(
      'wallet-123',
      '{"wallet":{"wallet_id":"wallet-123","balance_cents":11}}',
      sp: sp,
      baseUrlOverride: 'https://api.one.example',
    );
    await saveCachedWalletSnapshotRaw(
      'wallet-123',
      '{"wallet":{"wallet_id":"wallet-123","balance_cents":22}}',
      sp: sp,
      baseUrlOverride: 'https://api.two.example',
    );
    await saveCachedWalletLinkedCardsRawList(
      <String>[
        '{"label":"Origin One","last4":"1111","brand":"visa"}',
      ],
      sp: sp,
      baseUrlOverride: 'https://api.one.example',
    );
    await saveCachedWalletLinkedCardsRawList(
      <String>[
        '{"label":"Origin Two","last4":"2222","brand":"visa"}',
      ],
      sp: sp,
      baseUrlOverride: 'https://api.two.example',
    );

    expect(
      await loadCachedWalletSnapshotRaw(
        'wallet-123',
        sp: sp,
        baseUrlOverride: 'https://api.one.example',
      ),
      contains('"balance_cents":11'),
    );
    expect(
      await loadCachedWalletSnapshotRaw(
        'wallet-123',
        sp: sp,
        baseUrlOverride: 'https://api.two.example',
      ),
      contains('"balance_cents":22'),
    );
    expect(
      await loadCachedWalletLinkedCardsRawList(
        sp: sp,
        baseUrlOverride: 'https://api.one.example',
      ),
      hasLength(1),
    );
    expect(
      await loadCachedWalletLinkedCardsRawList(
        sp: sp,
        baseUrlOverride: 'https://api.one.example',
      ),
      contains(contains('"last4":"1111"')),
    );
    expect(
      await loadCachedWalletLinkedCardsRawList(
        sp: sp,
        baseUrlOverride: 'https://api.two.example',
      ),
      contains(contains('"last4":"2222"')),
    );
  });

  test('legacy global snapshots do not rebind into trusted canonical origins',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      'home_snapshot': '{"wallet":{"wallet_id":"legacy-home"}}',
      'wallet_snapshot_wallet-123':
          '{"wallet":{"wallet_id":"wallet-123","balance_cents":77}}',
      'wallet_linked_cards': <String>[
        '{"label":"Legacy","last4":"9999","brand":"visa"}',
      ],
    });

    final home = await loadCachedHomeSnapshotRaw();
    final wallet = await loadCachedWalletSnapshotRaw('wallet-123');
    final cards = await loadCachedWalletLinkedCardsRawList();

    expect(home, isNull);
    expect(wallet, isNull);
    expect(cards, isEmpty);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('home_snapshot'), isNull);
    expect(sp.getString('wallet_snapshot_wallet-123'), isNull);
    expect(sp.getStringList('wallet_linked_cards'), isNull);
  });
}
