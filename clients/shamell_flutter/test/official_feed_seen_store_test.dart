import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/official_feed_seen_store.dart';

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
    await clearOfficialFeedSeenMap();
  });

  test(
      'official feed seen map ignores legacy SharedPreferences when secure storage is readable and fallback is disabled',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kOfficialFeedSeenLegacyKey:
          '{"official-1":"2026-03-13T00:00:00Z","official-2":"2026-03-12T00:00:00Z"}',
    });

    expect(await loadOfficialFeedSeenMap(), isEmpty);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString(kOfficialFeedSeenLegacyKey), isNull);
    expect(secStore, isEmpty);
  });

  test(
      'official feed seen map allows legacy SharedPreferences when secure storage read fails',
      () async {
    throwOnSecureRead = true;
    SharedPreferences.setMockInitialValues(<String, Object>{
      kOfficialFeedSeenLegacyKey:
          '{"official-1":"2026-03-13T00:00:00Z","official-2":"2026-03-12T00:00:00Z"}',
    });

    expect(await loadOfficialFeedSeenMap(), <String, String>{
      'official-1': '2026-03-13T00:00:00Z',
      'official-2': '2026-03-12T00:00:00Z',
    });
  });

  test('official feed seen map reloads from secure storage and clears',
      () async {
    secStore[_scopedKeyFor('unknown')] =
        '{"official-1":"2026-03-13T00:00:00Z"}';

    expect(await loadOfficialFeedSeenMap(), <String, String>{
      'official-1': '2026-03-13T00:00:00Z',
    });
    expect(await loadOfficialFeedSeenMap(), <String, String>{
      'official-1': '2026-03-13T00:00:00Z',
    });

    await clearOfficialFeedSeenMap();
    expect(await loadOfficialFeedSeenMap(), isEmpty);
  });

  test('official feed seen map stays isolated across canonical API origins',
      () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    secStore[_scopedKeyFor('https://api.one.example')] =
        '{"official-1":"2026-03-13T00:00:00Z"}';

    expect(await loadOfficialFeedSeenMap(), <String, String>{
      'official-1': '2026-03-13T00:00:00Z',
    });

    await sp.setString('base_url', 'https://api.two.example');
    expect(await loadOfficialFeedSeenMap(), isEmpty);

    secStore[_scopedKeyFor('https://api.two.example')] =
        '{"official-2":"2026-03-12T00:00:00Z"}';
    expect(await loadOfficialFeedSeenMap(), <String, String>{
      'official-2': '2026-03-12T00:00:00Z',
    });
  });

  test(
      'official feed seen map honors explicit baseUrl override over global scope',
      () async {
    const originOne = 'https://api.one.example';
    const originTwo = 'https://api.two.example';
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': originTwo,
    });

    secStore[_scopedKeyFor(originOne)] =
        '{"official-1":"2026-03-13T00:00:00Z"}';
    secStore[_scopedKeyFor(originTwo)] =
        '{"official-2":"2026-03-12T00:00:00Z"}';

    expect(
      await loadOfficialFeedSeenMap(baseUrlOverride: originOne),
      <String, String>{'official-1': '2026-03-13T00:00:00Z'},
    );
    expect(
      await loadOfficialFeedSeenMap(baseUrlOverride: originTwo),
      <String, String>{'official-2': '2026-03-12T00:00:00Z'},
    );

    await clearOfficialFeedSeenMap(baseUrlOverride: originOne);

    expect(await loadOfficialFeedSeenMap(baseUrlOverride: originOne), isEmpty);
    expect(
      await loadOfficialFeedSeenMap(baseUrlOverride: originTwo),
      <String, String>{'official-2': '2026-03-12T00:00:00Z'},
    );
  });

  test(
      'legacy global official feed state does not rebind into trusted canonical origins',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      kOfficialFeedSeenLegacyKey: '{"official-1":"2026-03-13T00:00:00Z"}',
    });

    expect(await loadOfficialFeedSeenMap(), isEmpty);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString(kOfficialFeedSeenLegacyKey), isNull);
  });
}

String _scopedKeyFor(String scope) {
  final suffix = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
  return 'official.feed_seen.v2.$suffix';
}
