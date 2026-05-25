import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/favorites_page.dart';
import 'package:shamell_flutter/core/favorites_store.dart';

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
    await clearFavoriteItems();
  });

  test(
      'favorites ignore legacy SharedPreferences in unknown scope when secure storage is readable and fallback is disabled',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'favorites_items': '[{"text":"saved message","msgId":"m1"}]',
    });

    final items = await loadFavoriteItems();
    final sp = await SharedPreferences.getInstance();

    expect(items, isEmpty);
    expect(sp.getString('favorites_items'), isNull);
    expect(secStore, isEmpty);
  });

  test(
      'favorites allow legacy SharedPreferences when secure storage read fails',
      () async {
    throwOnSecureRead = true;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'favorites_items': '[{"text":"saved message","msgId":"m1"}]',
    });

    final items = await loadFavoriteItems();
    expect(items, hasLength(1));
    expect(items.first['msgId'], 'm1');
  });

  test('favorites are isolated per canonical api origin', () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    await saveFavoriteItems(<Map<String, dynamic>>[
      <String, dynamic>{'text': 'One', 'msgId': 'm1'},
    ]);

    await sp.setString('base_url', 'https://api.two.example');
    expect(await loadFavoriteItems(), isEmpty);

    await saveFavoriteItems(<Map<String, dynamic>>[
      <String, dynamic>{'text': 'Two', 'msgId': 'm2'},
    ]);

    await sp.setString('base_url', 'https://api.one.example');
    final first = await loadFavoriteItems();
    expect(first, hasLength(1));
    expect(first.first['msgId'], 'm1');

    await sp.setString('base_url', 'https://api.two.example');
    final second = await loadFavoriteItems();
    expect(second, hasLength(1));
    expect(second.first['msgId'], 'm2');
  });

  test('legacy global favorites do not rebind into canonical api origin',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      'favorites_items': '[{"text":"saved message","msgId":"m1"}]',
    });

    expect(await loadFavoriteItems(), isEmpty);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('favorites_items'), isNull);
  });

  test('favorites save, size, and clear through secure storage', () async {
    await saveFavoriteItems(<Map<String, dynamic>>[
      <String, dynamic>{'text': 'Pinned location', 'kind': 'location'},
    ]);

    final items = await loadFavoriteItems();
    expect(items, hasLength(1));
    expect(await favoriteItemsStorageBytes(), greaterThan(0));

    await clearFavoriteItems();
    expect(await loadFavoriteItems(), isEmpty);
    expect(await favoriteItemsStorageBytes(), 0);
  });

  test('legacy mini-app favorites are canonicalized as mini-programs',
      () async {
    await saveFavoriteItems(<Map<String, dynamic>>[
      <String, dynamic>{
        'kind': 'mini_app',
        'mini_app_id': 'coach_bus',
        'title': 'Coach',
      },
    ]);

    final items = await loadFavoriteItems();

    expect(items, hasLength(1));
    expect(items.first['kind'], 'mini_program');
    expect(items.first['appId'], 'coach_bus');
    expect(items.first['sourceModule'], 'mini_programs');
    expect(items.first['sourceId'], 'coach_bus');
  });

  test('legacy mini-app favorite targets remove canonical entries', () async {
    await saveFavoriteItems(<Map<String, dynamic>>[
      <String, dynamic>{
        'kind': 'mini_app',
        'mini_app_id': 'taxi',
        'title': 'Taxi',
      },
    ]);

    await removeFavoriteItemEntry(<String, dynamic>{
      'kind': 'mini_app',
      'mini_app_id': 'taxi',
      'title': 'Taxi',
    });

    expect(await loadFavoriteItems(), isEmpty);
  });

  test('clearFavoriteItems removes scoped favorites across all origins',
      () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    await saveFavoriteItems(<Map<String, dynamic>>[
      <String, dynamic>{'text': 'One', 'msgId': 'm1'},
    ]);

    await sp.setString('base_url', 'https://api.two.example');
    await saveFavoriteItems(<Map<String, dynamic>>[
      <String, dynamic>{'text': 'Two', 'msgId': 'm2'},
    ]);

    await clearFavoriteItems();

    await sp.setString('base_url', 'https://api.one.example');
    expect(await loadFavoriteItems(), isEmpty);

    await sp.setString('base_url', 'https://api.two.example');
    expect(await loadFavoriteItems(), isEmpty);
  });

  test('favorites honor explicit baseUrl override over global scope', () async {
    const originOne = 'https://api.one.example';
    const originTwo = 'https://api.two.example';
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', originOne);
    await saveFavoriteItems(
      <Map<String, dynamic>>[
        <String, dynamic>{'text': 'One', 'msgId': 'm1'},
      ],
      baseUrlOverride: originOne,
    );
    await saveFavoriteItems(
      <Map<String, dynamic>>[
        <String, dynamic>{'text': 'Two', 'msgId': 'm2'},
      ],
      baseUrlOverride: originTwo,
    );

    expect((await loadFavoriteItems()).first['msgId'], 'm1');
    expect(
      (await loadFavoriteItems(baseUrlOverride: originTwo)).first['msgId'],
      'm2',
    );
    expect(
      await favoriteItemsStorageBytes(baseUrlOverride: originTwo),
      greaterThan(0),
    );

    await saveFavoriteItems(
      const <Map<String, dynamic>>[],
      baseUrlOverride: originTwo,
    );

    expect(await loadFavoriteItems(baseUrlOverride: originTwo), isEmpty);
    expect((await loadFavoriteItems(baseUrlOverride: originOne)).first['msgId'],
        'm1');
  });

  test('removeFavoriteItemsByMessageId removes only matching entries',
      () async {
    await saveFavoriteItems(<Map<String, dynamic>>[
      <String, dynamic>{'text': 'One', 'msgId': 'm1'},
      <String, dynamic>{'text': 'Two', 'msgId': 'm2'},
      <String, dynamic>{'text': 'Other without msg'},
    ]);

    await removeFavoriteItemsByMessageId('m1');

    expect(
      await loadFavoriteItems(),
      <Map<String, dynamic>>[
        <String, dynamic>{'text': 'Two', 'msgId': 'm2'},
        <String, dynamic>{'text': 'Other without msg'},
      ],
    );
  });

  test('appendFavoriteItem prepends while preserving existing entries',
      () async {
    await saveFavoriteItems(<Map<String, dynamic>>[
      <String, dynamic>{'text': 'Older', 'msgId': 'm1'},
    ]);

    await appendFavoriteItem(<String, dynamic>{
      'text': 'Newer',
      'msgId': 'm2',
    });

    final items = await loadFavoriteItems();

    expect(items, hasLength(2));
    expect(items.first['text'], 'Newer');
    expect(items.first['msgId'], 'm2');
    expect(items.first['id'], isA<String>());
    expect(items[1], <String, dynamic>{'text': 'Older', 'msgId': 'm1'});
  });

  test('insertFavoriteItemAt inserts at requested index', () async {
    await saveFavoriteItems(<Map<String, dynamic>>[
      <String, dynamic>{'text': 'First', 'msgId': 'm1'},
      <String, dynamic>{'text': 'Third', 'msgId': 'm3'},
    ]);

    await insertFavoriteItemAt(1, <String, dynamic>{
      'text': 'Second',
      'msgId': 'm2',
    });

    final items = await loadFavoriteItems();

    expect(items, hasLength(3));
    expect(items[0], <String, dynamic>{'text': 'First', 'msgId': 'm1'});
    expect(items[1]['text'], 'Second');
    expect(items[1]['msgId'], 'm2');
    expect(items[1]['id'], isA<String>());
    expect(items[2], <String, dynamic>{'text': 'Third', 'msgId': 'm3'});
  });

  test('removeFavoriteItemEntry removes only the matching entry', () async {
    await saveFavoriteItems(<Map<String, dynamic>>[
      <String, dynamic>{'text': 'Same', 'msgId': 'm1', 'chatId': 'peer-1'},
      <String, dynamic>{'text': 'Same', 'msgId': 'm2', 'chatId': 'peer-1'},
      <String, dynamic>{'text': 'Other', 'msgId': 'm3'},
    ]);

    await removeFavoriteItemEntry(<String, dynamic>{
      'text': 'Same',
      'msgId': 'm2',
      'chatId': 'peer-1',
    });

    expect(
      await loadFavoriteItems(),
      <Map<String, dynamic>>[
        <String, dynamic>{'text': 'Same', 'msgId': 'm1', 'chatId': 'peer-1'},
        <String, dynamic>{'text': 'Other', 'msgId': 'm3'},
      ],
    );
  });

  test('addFavoriteItemQuick appends message favorite through store contract',
      () async {
    await saveFavoriteItems(<Map<String, dynamic>>[
      <String, dynamic>{'text': 'Older', 'msgId': 'm1'},
    ]);

    await addFavoriteItemQuick(
      'Saved message',
      chatId: 'peer-1',
      msgId: 'm2',
    );

    final items = await loadFavoriteItems();
    expect(items, hasLength(2));
    expect(items.first['text'], 'Saved message');
    expect(items.first['chatId'], 'peer-1');
    expect(items.first['msgId'], 'm2');
    expect(items[1]['msgId'], 'm1');
  });

  test(
      'addFavoriteLocationQuick appends location favorite through store contract',
      () async {
    await saveFavoriteItems(<Map<String, dynamic>>[
      <String, dynamic>{'text': 'Older', 'msgId': 'm1'},
    ]);

    await addFavoriteLocationQuick(
      36.8,
      10.1,
      label: 'Tunis',
      chatId: 'peer-1',
      msgId: 'm2',
    );

    final items = await loadFavoriteItems();
    expect(items, hasLength(2));
    expect(items.first['text'], 'Tunis');
    expect(items.first['kind'], 'location');
    expect(items.first['chatId'], 'peer-1');
    expect(items.first['msgId'], 'm2');
    expect(items[1]['msgId'], 'm1');
  });
}
