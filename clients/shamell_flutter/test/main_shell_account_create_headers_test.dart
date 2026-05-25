import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/runtime_base_scope.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import 'package:shamell_flutter/main.dart' show shamellBuildHeaders;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secStore = <String, String>{};
  const baseUrl = 'https://api.example.com';
  const sessionToken = '0123456789abcdef0123456789abcdef';

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
    secStore.clear();
    await clearSessionCookie();
    shamellSetActiveRuntimeBaseUrl(null);
    await setSessionTokenForBaseUrl(baseUrl, sessionToken);
  });

  test('account-create headers omit local session cookie', () async {
    final headers = await shamellBuildHeaders(
      json: true,
      baseUrl: baseUrl,
      includeSessionCookie: false,
    );

    expect(headers['content-type'], 'application/json');
    expect(headers.containsKey('cookie'), isFalse);
  });

  test('normal authenticated headers still include local session cookie',
      () async {
    final headers = await shamellBuildHeaders(
      json: true,
      baseUrl: baseUrl,
    );

    expect(headers['content-type'], 'application/json');
    expect(headers['cookie'], '__Host-sa_session=$sessionToken');
  });

  test(
      'normal authenticated headers include session cookie from active runtime base when baseUrl is omitted',
      () async {
    shamellSetActiveRuntimeBaseUrl(baseUrl);
    final headers = await shamellBuildHeaders(
      json: true,
    );

    expect(headers['content-type'], 'application/json');
    expect(headers['cookie'], '__Host-sa_session=$sessionToken');
  });

  test('headers reject credentialed or path-prefixed base urls', () async {
    final credentialed = await shamellBuildHeaders(
      json: true,
      baseUrl: 'https://user:pass@api.example.com',
    );
    final pathPrefixed = await shamellBuildHeaders(
      json: true,
      baseUrl: 'https://api.example.com/admin',
    );

    expect(credentialed['content-type'], 'application/json');
    expect(credentialed.containsKey('cookie'), isFalse);
    expect(credentialed.containsKey('x-shamell-client-ip'), isFalse);

    expect(pathPrefixed['content-type'], 'application/json');
    expect(pathPrefixed.containsKey('cookie'), isFalse);
    expect(pathPrefixed.containsKey('x-shamell-client-ip'), isFalse);
  });

  test('localhost dev header only attaches for canonical localhost base',
      () async {
    final localhost = await shamellBuildHeaders(
      baseUrl: 'http://127.0.0.1:8080',
      includeSessionCookie: false,
    );
    final credentialedLocalhost = await shamellBuildHeaders(
      baseUrl: 'http://api.example.com@127.0.0.1:8080',
      includeSessionCookie: false,
    );

    expect(localhost['x-shamell-client-ip'], '127.0.0.1');
    expect(credentialedLocalhost.containsKey('x-shamell-client-ip'), isFalse);
  });
}
