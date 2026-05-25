import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/chat/chat_service.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const baseUrl = 'http://127.0.0.1:8080';
  const sessionToken = '0123456789abcdef0123456789abcdef';
  const deviceId = 'SA4N7Q2YM9AYE3FVSXLLQ8WL';
  const deviceToken = 'chat-device-token';
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
    await clearSessionCookie();
    await setSessionTokenForBaseUrl(baseUrl, sessionToken);
  });

  test('chat websocket headers include scoped session cookie and device auth',
      () async {
    await ChatLocalStore().saveDeviceAuthToken(
      deviceId,
      deviceToken,
      baseUrlOverride: baseUrl,
    );

    final headers = await shamellChatWebSocketHeadersForBaseUrl(
      baseUrl,
      deviceId: deviceId,
    );

    expect(headers['cookie'], '__Host-sa_session=$sessionToken');
    expect(headers['x-shamell-client-ip'], '127.0.0.1');
    expect(headers['X-Chat-Device-Id'], deviceId);
    expect(headers['X-Chat-Device-Token'], deviceToken);
  });

  test('chat websocket headers keep cookie even when device token is missing',
      () async {
    final headers = await shamellChatWebSocketHeadersForBaseUrl(
      baseUrl,
      deviceId: deviceId,
    );

    expect(headers['cookie'], '__Host-sa_session=$sessionToken');
    expect(headers['x-shamell-client-ip'], '127.0.0.1');
    expect(headers.containsKey('X-Chat-Device-Id'), isFalse);
    expect(headers.containsKey('X-Chat-Device-Token'), isFalse);
  });
}
