import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const token = '0123456789abcdef0123456789abcdef';

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await clearSessionCookie();
  });

  test('setSessionTokenForBaseUrl rejects insecure non-localhost base URLs',
      () async {
    await setSessionTokenForBaseUrl('http://api.shamell.online', token);

    expect(
        await getSessionTokenForBaseUrl('http://api.shamell.online'), isNull);
    expect(
        await getSessionTokenForBaseUrl('https://api.shamell.online'), isNull);
  });

  test('setSessionTokenForBaseUrl accepts https base URLs', () async {
    await setSessionTokenForBaseUrl('https://api.shamell.online', token);

    expect(
        await getSessionTokenForBaseUrl('https://api.shamell.online'), token);
    expect(await getSessionTokenForBaseUrl('https://other.shamell.online'),
        isNull);
  });

  test('session cookie store rejects credentialed and path-prefixed base URLs',
      () async {
    await setSessionTokenForBaseUrl('https://api.shamell.online', token);

    expect(
      await getSessionTokenForBaseUrl('https://user:pass@api.shamell.online'),
      isNull,
    );
    expect(
      await getSessionTokenForBaseUrl('https://api.shamell.online/admin'),
      isNull,
    );
    expect(
      await getSessionTokenForBaseUrl('https://api.shamell.online?x=1'),
      isNull,
    );
    expect(
      await getSessionCookieHeader('https://api.shamell.online#frag'),
      isNull,
    );
  });

  test('setSessionTokenForBaseUrl rejects credentialed or path-prefixed inputs',
      () async {
    await setSessionTokenForBaseUrl(
      'https://user:pass@api.shamell.online',
      token,
    );
    await setSessionTokenForBaseUrl('https://api.shamell.online/admin', token);
    await setSessionTokenForBaseUrl('https://api.shamell.online?x=1', token);

    expect(
        await getSessionTokenForBaseUrl('https://api.shamell.online'), isNull);
  });

  test('setSessionTokenForBaseUrl scopes sessions to the exact origin',
      () async {
    await setSessionTokenForBaseUrl('https://api.shamell.online:8443', token);

    expect(
      await getSessionTokenForBaseUrl('https://api.shamell.online:8443'),
      token,
    );
    expect(
        await getSessionTokenForBaseUrl('https://api.shamell.online'), isNull);
    expect(
      await getSessionTokenForBaseUrl('https://api.shamell.online:9443'),
      isNull,
    );
  });

  test('setSessionTokenForBaseUrl accepts localhost http base URLs', () async {
    await setSessionTokenForBaseUrl('http://127.0.0.1:8080', token);

    expect(await getSessionTokenForBaseUrl('http://127.0.0.1:8080'), token);
    expect(await getSessionTokenForBaseUrl('http://127.0.0.1:8081'), isNull);
  });

  test('setSessionTokenForBaseUrl rejects non-http localhost-like schemes',
      () async {
    await setSessionTokenForBaseUrl('ws://127.0.0.1:8080', token);

    expect(await getSessionTokenForBaseUrl('ws://127.0.0.1:8080'), isNull);
    expect(await getSessionTokenForBaseUrl('http://127.0.0.1:8080'), isNull);
  });

  test('legacy host-scoped session state does not bind to alternate ports',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'sa_cookie': '{"v":1,"host":"api.shamell.online","token":"$token"}',
    });

    expect(
      await getSessionTokenForBaseUrl('https://api.shamell.online:8443'),
      isNull,
    );
    expect(
        await getSessionTokenForBaseUrl('https://api.shamell.online'), token);
  });

  test('raw legacy session token does not rebind into canonical origins',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.shamell.online',
      'sa_cookie': token,
    });

    expect(
        await getSessionTokenForBaseUrl('https://api.shamell.online'), isNull);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('sa_cookie'), isNull);
  });

  test('raw legacy cookie header does not rebind into canonical origins',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.shamell.online',
      'sa_cookie': '__Host-sa_session=$token; Path=/; Secure; HttpOnly',
    });

    expect(
        await getSessionTokenForBaseUrl('https://api.shamell.online'), isNull);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('sa_cookie'), isNull);
  });

  test(
      'legacy shared-preferences session remains available on debug mobile when fallback is enabled',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'sa_cookie':
          '{"v":2,"origin":"https://api.shamell.online","token":"$token"}',
    });

    const storageChannel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, (call) async {
      if (call.method == 'read') return null;
      if (call.method == 'write') return null;
      if (call.method == 'delete') return null;
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(storageChannel, null);
    });

    expect(
      await getSessionTokenForBaseUrl('https://api.shamell.online'),
      token,
    );
  });

  test('debug mobile defaults legacy fallback to enabled', () {
    expect(
      shamellAllowLegacySessionFallbackForRuntime(
        releaseMode: false,
        isWeb: false,
        platform: TargetPlatform.android,
      ),
      isTrue,
    );
    expect(
      shamellAllowLegacySessionFallbackForRuntime(
        releaseMode: false,
        isWeb: false,
        platform: TargetPlatform.iOS,
      ),
      isTrue,
    );
  });

  test('release and web builds still fail closed for legacy fallback', () {
    expect(
      shamellAllowLegacySessionFallbackForRuntime(
        releaseMode: true,
        isWeb: false,
        platform: TargetPlatform.android,
      ),
      isFalse,
    );
    expect(
      shamellAllowLegacySessionFallbackForRuntime(
        releaseMode: false,
        isWeb: true,
        platform: TargetPlatform.android,
      ),
      isFalse,
    );
  });
}
