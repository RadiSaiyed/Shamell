import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import 'package:shamell_flutter/core/superapp_api.dart';

class _RecordingClient extends http.BaseClient {
  String? lastMethod;
  Uri? lastUri;
  Map<String, String>? lastHeaders;
  String? lastBody;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastMethod = request.method;
    lastUri = request.url;
    lastHeaders = Map<String, String>.from(request.headers);
    if (request is http.Request) {
      lastBody = request.body;
    }
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode('{"ok":true}')),
      200,
      request: request,
      headers: const <String, String>{
        'content-type': 'application/json',
      },
    );
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

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
    await clearSessionCookie();
  });

  test('light api falls back to configured API base URL when unset', () {
    final api = SuperappAPI.light(baseUrl: '');

    expect(
      api.uri('payments/admin/credits').toString(),
      'https://api.shamell.online/payments/admin/credits',
    );
  });

  test('superapp kv storage is namespaced into secure storage on mobile',
      () async {
    final api = SuperappAPI.light(baseUrl: 'https://api.example.com');

    await api.kvSetString('draft', 'value-1');
    await api.kvSetBool('enabled', true);
    await api.kvSetInt('count', 7);
    await api.kvSetStringList('items', <String>['a', 'b']);

    expect(await api.kvGetString('draft'), 'value-1');
    expect(await api.kvGetBool('enabled'), isTrue);
    expect(await api.kvGetInt('count'), 7);
    expect(await api.kvGetStringList('items'), <String>['a', 'b']);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('draft'), isNull);
    expect(sp.getBool('enabled'), isNull);
    expect(sp.getInt('count'), isNull);
    expect(sp.getStringList('items'), isNull);
    expect(
      sp.getKeys().where((key) => key.startsWith('superapp.kv.')),
      isEmpty,
    );
    final draftKey = secStore.keys.singleWhere((key) =>
        key.startsWith('superapp.kv.') && key.endsWith('.global.draft'));
    expect(draftKey, endsWith('.global.draft'));
    expect(secStore[draftKey], contains('"t":"string"'));
    expect(secStore[draftKey], contains('"v":"value-1"'));
    expect(
      secStore.keys.singleWhere((key) =>
          key.startsWith('superapp.kv.') && key.endsWith('.global.enabled')),
      endsWith('.global.enabled'),
    );
    expect(
      secStore.keys.singleWhere((key) =>
          key.startsWith('superapp.kv.') && key.endsWith('.global.count')),
      endsWith('.global.count'),
    );
    expect(
      secStore.keys.singleWhere((key) =>
          key.startsWith('superapp.kv.') && key.endsWith('.global.items')),
      endsWith('.global.items'),
    );
  });

  test('superapp kv rejects invalid storage keys', () async {
    final api = SuperappAPI.light(baseUrl: 'https://api.example.com');
    final sp = await SharedPreferences.getInstance();

    await api.kvSetString('../wallet_id', 'should-not-write');
    expect(await api.kvGetString('../wallet_id'), isNull);
    expect(sp.getKeys(), isEmpty);
    expect(secStore, isEmpty);
  });

  test('superapp kv remove only clears namespaced keys', () async {
    final api = SuperappAPI.light(baseUrl: 'https://api.example.com');
    final sp = await SharedPreferences.getInstance();
    await sp.setString('draft', 'app-owned');
    await api.kvSetString('draft', 'mini-app');

    await api.kvRemove('draft');

    expect(sp.getString('draft'), 'app-owned');
    expect(
      sp.getKeys().where((key) => key.startsWith('superapp.kv.')),
      isEmpty,
    );
    expect(
      secStore.keys.where((key) => key.startsWith('superapp.kv.')),
      isEmpty,
    );
  });

  test('superapp kv stays isolated across API origins and wallets', () async {
    final one = SuperappAPI.light(
      baseUrl: 'https://api.one.example',
      walletId: 'wallet-1',
    );
    final two = SuperappAPI.light(
      baseUrl: 'https://api.two.example',
      walletId: 'wallet-2',
    );

    await one.kvSetString('draft', 'value-one');
    await two.kvSetString('draft', 'value-two');

    expect(await one.kvGetString('draft'), 'value-one');
    expect(await two.kvGetString('draft'), 'value-two');
  });

  test('superapp clearPersistedState removes kv state across scopes', () async {
    final one = SuperappAPI.light(
      baseUrl: 'https://api.one.example',
      walletId: 'wallet-1',
    );
    final two = SuperappAPI.light(
      baseUrl: 'https://api.two.example',
      walletId: 'wallet-2',
    );
    final sp = await SharedPreferences.getInstance();

    await one.kvSetString('draft', 'value-one');
    await two.kvSetString('draft', 'value-two');
    expect(
      secStore.keys.where((key) => key.startsWith('superapp.kv.')),
      isNotEmpty,
    );

    await SuperappAPI.clearPersistedState(sp: sp);

    expect(await one.kvGetString('draft'), isNull);
    expect(await two.kvGetString('draft'), isNull);
    expect(
      sp.getKeys().where((key) => key.startsWith('superapp.kv.')),
      isEmpty,
    );
    expect(
      secStore.keys.where((key) => key.startsWith('superapp.kv.')),
      isEmpty,
    );
  });

  test('superapp kv ignores legacy prefs by default on mobile', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'superapp.kv.aHR0cHM6Ly9hcGkuZXhhbXBsZS5jb20.global.draft': 'legacy',
    });
    final api = SuperappAPI.light(baseUrl: 'https://api.example.com');
    final sp = await SharedPreferences.getInstance();

    expect(await api.kvGetString('draft'), isNull);
    expect(
      sp.getKeys().where((key) => key.startsWith('superapp.kv.')),
      isEmpty,
    );
    expect(
      secStore.values.where((value) => value.contains('"v":"legacy"')),
      isEmpty,
    );
  });

  test('superapp kv allows legacy prefs when secure reads fail', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'superapp.kv.aHR0cHM6Ly9hcGkuZXhhbXBsZS5jb20.global.draft': 'legacy',
    });
    throwOnSecureRead = true;
    final api = SuperappAPI.light(baseUrl: 'https://api.example.com');
    final sp = await SharedPreferences.getInstance();

    expect(await api.kvGetString('draft'), 'legacy');
    expect(
      sp.getKeys().where((key) => key.startsWith('superapp.kv.')),
      isEmpty,
    );
    expect(
      secStore.values.where((value) => value.contains('"v":"legacy"')),
      isNotEmpty,
    );
  });

  test('superapp launch uri allows bounded http(s) and tel/mailto only', () {
    final base = Uri.parse('https://api.example.com/base/');

    expect(
      SuperappAPI.normalizeSuperappLaunchUri(
        Uri.parse('https://safe.example.com/x'),
        baseUri: base,
      )?.toString(),
      'https://safe.example.com/x',
    );
    expect(
      SuperappAPI.normalizeSuperappLaunchUri(
        Uri.parse('/docs'),
        baseUri: base,
      )?.toString(),
      'https://api.example.com/docs',
    );
    expect(
      SuperappAPI.normalizeSuperappLaunchUri(
        Uri.parse('tel:+15551234567'),
        baseUri: base,
      )?.toString(),
      'tel:+15551234567',
    );
    expect(
      SuperappAPI.normalizeSuperappLaunchUri(
        Uri.parse('mailto:help@shamell.test'),
        baseUri: base,
      )?.toString(),
      'mailto:help@shamell.test',
    );
    expect(
      SuperappAPI.normalizeSuperappLaunchUri(
        Uri.parse('http://127.0.0.1:8080/devtools'),
        baseUri: base,
      )?.toString(),
      'http://127.0.0.1:8080/devtools',
    );
  });

  test('superapp launch uri rejects unsafe schemes and credentialed urls', () {
    final base = Uri.parse('https://api.example.com/base/');

    expect(
      SuperappAPI.normalizeSuperappLaunchUri(
        Uri.parse('javascript:alert(1)'),
        baseUri: base,
      ),
      isNull,
    );
    expect(
      SuperappAPI.normalizeSuperappLaunchUri(
        Uri.parse('data:text/html,<script>alert(1)</script>'),
        baseUri: base,
      ),
      isNull,
    );
    expect(
      SuperappAPI.normalizeSuperappLaunchUri(
        Uri.parse('file:///tmp/x'),
        baseUri: base,
      ),
      isNull,
    );
    expect(
      SuperappAPI.normalizeSuperappLaunchUri(
        Uri.parse('intent://evil.test/#Intent;scheme=https;end'),
        baseUri: base,
      ),
      isNull,
    );
    expect(
      SuperappAPI.normalizeSuperappLaunchUri(
        Uri.parse('https://user:pass@evil.test/x'),
        baseUri: base,
      ),
      isNull,
    );
    expect(
      SuperappAPI.normalizeSuperappLaunchUri(
        Uri.parse('http://evil.test/plaintext'),
        baseUri: base,
      ),
      isNull,
    );
  });

  test('superapp request uri allows same-origin http(s) only', () {
    final base = Uri.parse('https://api.example.com/base/');

    expect(
      SuperappAPI.normalizeSuperappRequestUri(
        Uri.parse('/me/home_snapshot'),
        baseUri: base,
      )?.toString(),
      'https://api.example.com/me/home_snapshot',
    );
    expect(
      SuperappAPI.normalizeSuperappRequestUri(
        Uri.parse('https://api.example.com/payments/transfer'),
        baseUri: base,
      )?.toString(),
      'https://api.example.com/payments/transfer',
    );
  });

  test('superapp request uri rejects cross-origin and credentialed urls', () {
    final base = Uri.parse('https://api.example.com/base/');

    expect(
      SuperappAPI.normalizeSuperappRequestUri(
        Uri.parse('https://evil.test/x'),
        baseUri: base,
      ),
      isNull,
    );
    expect(
      SuperappAPI.normalizeSuperappRequestUri(
        Uri.parse('https://user:pass@api.example.com/x'),
        baseUri: base,
      ),
      isNull,
    );
    expect(
      SuperappAPI.normalizeSuperappRequestUri(
        Uri.parse('mailto:help@example.com'),
        baseUri: base,
      ),
      isNull,
    );
  });

  test('superapp session headers reject cross-origin targets', () async {
    final api = SuperappAPI.light(baseUrl: 'https://api.example.com');

    await expectLater(
      api.sessionHeaders(uri: Uri.parse('https://evil.test/x')),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('superapp request helpers reject cross-origin targets', () async {
    final api = SuperappAPI.light(baseUrl: 'https://api.example.com');

    await expectLater(
      api.getUri(Uri.parse('https://evil.test/x')),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      api.postUri(Uri.parse('https://evil.test/x')),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('superapp request helpers use configured transport client and close it',
      () async {
    final client = _RecordingClient();
    final api = SuperappAPI.light(
      baseUrl: 'https://api.example.com',
      httpClientFactory: () => client,
    );

    final response = await api.postUri(
      Uri.parse('/modules/state'),
      headers: const <String, String>{'x-test': '1'},
      body: '{"draft":true}',
    );

    expect(response.statusCode, 200);
    expect(client.lastMethod, 'POST');
    expect(client.lastUri?.toString(), 'https://api.example.com/modules/state');
    expect(client.lastHeaders?['x-test'], '1');
    expect(client.lastBody, '{"draft":true}');
    expect(client.closed, isTrue);
  });

  test('superapp session headers add localhost client-ip hint and cookie',
      () async {
    const baseUrl = 'http://127.0.0.1:8080';
    await setSessionTokenForBaseUrl(
      baseUrl,
      '0123456789abcdef0123456789abcdef',
    );
    final api = SuperappAPI.light(baseUrl: baseUrl);

    final headers = await api.sessionHeaders(
      uri: Uri.parse('http://127.0.0.1:8080/me/home_snapshot'),
      json: true,
    );

    expect(headers['content-type'], 'application/json');
    expect(headers['x-shamell-client-ip'], '127.0.0.1');
    expect(
      headers['cookie'],
      '__Host-sa_session=0123456789abcdef0123456789abcdef',
    );
  });
}
