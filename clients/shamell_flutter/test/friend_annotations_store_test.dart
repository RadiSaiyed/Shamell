import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/friend_annotations_store.dart';

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
    await clearFriendAnnotations();
  });

  test(
      'friend annotations ignore legacy SharedPreferences when secure storage is readable and fallback is disabled',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'friends.aliases': '{"u1":"Alice"}',
      'friends.tags': '{"u1":"vip,team"}',
      'friends.close': '{"u1":true,"u2":false}',
    });

    final snapshot = await loadFriendAnnotations();

    expect(snapshot.aliases, isEmpty);
    expect(snapshot.tags, isEmpty);
    expect(snapshot.closeFriendIds, isEmpty);
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('friends.aliases'), isNull);
    expect(sp.getString('friends.tags'), isNull);
    expect(sp.getString('friends.close'), isNull);
    expect(secStore, isEmpty);
  });

  test(
      'friend annotations allow legacy SharedPreferences when secure storage read fails',
      () async {
    throwOnSecureRead = true;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'friends.aliases': '{"u1":"Alice"}',
      'friends.tags': '{"u1":"vip,team"}',
      'friends.close': '{"u1":true,"u2":false}',
    });

    final snapshot = await loadFriendAnnotations();
    expect(snapshot.aliases, <String, String>{'u1': 'Alice'});
    expect(snapshot.tags, <String, String>{'u1': 'vip,team'});
    expect(snapshot.closeFriendIds, <String>{'u1'});
  });

  test('friend annotations are isolated per canonical api origin', () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    await saveFriendAliases(<String, String>{'u1': 'Alice'});
    await saveFriendTags(<String, String>{'u1': 'vip'});
    await saveCloseFriendIds(<String>{'u1'});

    await sp.setString('base_url', 'https://api.two.example');
    expect(await loadFriendAliases(), isEmpty);
    expect(await loadFriendTags(), isEmpty);
    expect(await loadCloseFriendIds(), isEmpty);

    await saveFriendAliases(<String, String>{'u2': 'Bob'});
    await saveFriendTags(<String, String>{'u2': 'work'});
    await saveCloseFriendIds(<String>{'u2'});

    await sp.setString('base_url', 'https://api.one.example');
    expect(await loadFriendAliases(), <String, String>{'u1': 'Alice'});
    expect(await loadFriendTags(), <String, String>{'u1': 'vip'});
    expect(await loadCloseFriendIds(), <String>{'u1'});

    await sp.setString('base_url', 'https://api.two.example');
    expect(await loadFriendAliases(), <String, String>{'u2': 'Bob'});
    expect(await loadFriendTags(), <String, String>{'u2': 'work'});
    expect(await loadCloseFriendIds(), <String>{'u2'});
  });

  test(
      'legacy global friend annotations do not rebind into canonical api origin',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      'friends.aliases': '{"u1":"Alice"}',
      'friends.tags': '{"u1":"vip"}',
      'friends.close': '{"u1":true}',
    });

    expect(await loadFriendAliases(), isEmpty);
    expect(await loadFriendTags(), isEmpty);
    expect(await loadCloseFriendIds(), isEmpty);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('friends.aliases'), isNull);
    expect(sp.getString('friends.tags'), isNull);
    expect(sp.getString('friends.close'), isNull);
  });

  test('friend annotations save, load, and clear through secure storage',
      () async {
    await saveFriendAliases(<String, String>{'u1': 'Alice', 'u2': 'Bob'});
    await saveFriendTags(<String, String>{'u1': 'vip', 'u2': 'work'});
    await saveCloseFriendIds(<String>{'u1', 'u2'});

    expect(
      await loadFriendAliases(),
      <String, String>{'u1': 'Alice', 'u2': 'Bob'},
    );
    expect(
      await loadFriendTags(),
      <String, String>{'u1': 'vip', 'u2': 'work'},
    );
    expect(await loadCloseFriendIds(), <String>{'u1', 'u2'});

    await clearFriendAnnotations();

    expect(await loadFriendAliases(), isEmpty);
    expect(await loadFriendTags(), isEmpty);
    expect(await loadCloseFriendIds(), isEmpty);
  });

  test('clearFriendAnnotations removes scoped values across all origins',
      () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    await saveFriendAliases(<String, String>{'u1': 'Alice'});
    await saveCloseFriendIds(<String>{'u1'});

    await sp.setString('base_url', 'https://api.two.example');
    await saveFriendAliases(<String, String>{'u2': 'Bob'});
    await saveCloseFriendIds(<String>{'u2'});

    await clearFriendAnnotations();

    await sp.setString('base_url', 'https://api.one.example');
    expect(await loadFriendAliases(), isEmpty);
    expect(await loadCloseFriendIds(), isEmpty);

    await sp.setString('base_url', 'https://api.two.example');
    expect(await loadFriendAliases(), isEmpty);
    expect(await loadCloseFriendIds(), isEmpty);
  });

  test('friend annotations honor explicit baseUrl override over global scope',
      () async {
    const scopedOrigin = 'https://api.two.example';
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await saveFriendAliases(
      <String, String>{'u2': 'Bob'},
      baseUrlOverride: scopedOrigin,
    );
    await saveFriendTags(
      <String, String>{'u2': 'work'},
      baseUrlOverride: scopedOrigin,
    );
    await saveCloseFriendIds(
      <String>{'u2'},
      baseUrlOverride: scopedOrigin,
    );

    expect(await loadFriendAliases(), isEmpty);
    expect(await loadFriendTags(), isEmpty);
    expect(await loadCloseFriendIds(), isEmpty);

    expect(
      await loadFriendAliases(baseUrlOverride: scopedOrigin),
      <String, String>{'u2': 'Bob'},
    );
    expect(
      await loadFriendTags(baseUrlOverride: scopedOrigin),
      <String, String>{'u2': 'work'},
    );
    expect(
      await loadCloseFriendIds(baseUrlOverride: scopedOrigin),
      <String>{'u2'},
    );
  });

  test('saveFriendAliasAndTagsForPeer updates only the targeted peer',
      () async {
    const scopedOrigin = 'https://api.two.example';

    await saveFriendAliases(
      <String, String>{'u1': 'Alice', 'u2': 'Bob'},
      baseUrlOverride: scopedOrigin,
    );
    await saveFriendTags(
      <String, String>{'u1': 'vip', 'u2': 'work'},
      baseUrlOverride: scopedOrigin,
    );

    await saveFriendAliasAndTagsForPeer(
      peerId: 'u1',
      alias: 'Alice Updated',
      tags: '',
      baseUrlOverride: scopedOrigin,
    );

    expect(
      await loadFriendAliases(baseUrlOverride: scopedOrigin),
      <String, String>{'u1': 'Alice Updated', 'u2': 'Bob'},
    );
    expect(
      await loadFriendTags(baseUrlOverride: scopedOrigin),
      <String, String>{'u2': 'work'},
    );
  });

  test('saveFriendAnnotationsSnapshot persists alias and tag maps together',
      () async {
    const scopedOrigin = 'https://api.two.example';

    await saveFriendAnnotationsSnapshot(
      aliases: <String, String>{'u1': 'Alice', 'u2': 'Bob'},
      tags: <String, String>{'u1': 'vip', 'u2': 'work'},
      baseUrlOverride: scopedOrigin,
    );

    expect(
      await loadFriendAliases(baseUrlOverride: scopedOrigin),
      <String, String>{'u1': 'Alice', 'u2': 'Bob'},
    );
    expect(
      await loadFriendTags(baseUrlOverride: scopedOrigin),
      <String, String>{'u1': 'vip', 'u2': 'work'},
    );
  });

  test('saveCloseFriendForPeer updates only the targeted peer', () async {
    const scopedOrigin = 'https://api.two.example';

    await saveCloseFriendIds(
      <String>{'u1', 'u2'},
      baseUrlOverride: scopedOrigin,
    );

    await saveCloseFriendForPeer(
      peerId: 'u1',
      isClose: false,
      baseUrlOverride: scopedOrigin,
    );

    expect(
      await loadCloseFriendIds(baseUrlOverride: scopedOrigin),
      <String>{'u2'},
    );
  });

  test('saveCloseFriendForPeer can add the first close friend', () async {
    const scopedOrigin = 'https://api.two.example';

    await saveCloseFriendForPeer(
      peerId: 'u1',
      isClose: true,
      baseUrlOverride: scopedOrigin,
    );

    expect(
      await loadCloseFriendIds(baseUrlOverride: scopedOrigin),
      <String>{'u1'},
    );
  });
}
