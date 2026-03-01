import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';

void main() {
  const token = '0123456789abcdef0123456789abcdef';

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await clearSessionCookie();
  });

  test('setSessionTokenForBaseUrl rejects insecure non-localhost base URLs',
      () async {
    await setSessionTokenForBaseUrl('http://api.shamell.online', token);

    expect(await getSessionTokenForBaseUrl('http://api.shamell.online'), isNull);
    expect(await getSessionTokenForBaseUrl('https://api.shamell.online'), isNull);
  });

  test('setSessionTokenForBaseUrl accepts https base URLs', () async {
    await setSessionTokenForBaseUrl('https://api.shamell.online', token);

    expect(await getSessionTokenForBaseUrl('https://api.shamell.online'), token);
    expect(await getSessionTokenForBaseUrl('https://other.shamell.online'), isNull);
  });

  test('setSessionTokenForBaseUrl accepts localhost http base URLs', () async {
    await setSessionTokenForBaseUrl('http://127.0.0.1:8080', token);

    expect(await getSessionTokenForBaseUrl('http://127.0.0.1:8080'), token);
  });

  test('setSessionTokenForBaseUrl rejects non-http localhost-like schemes',
      () async {
    await setSessionTokenForBaseUrl('ws://127.0.0.1:8080', token);

    expect(await getSessionTokenForBaseUrl('ws://127.0.0.1:8080'), isNull);
    expect(await getSessionTokenForBaseUrl('http://127.0.0.1:8080'), isNull);
  });
}
