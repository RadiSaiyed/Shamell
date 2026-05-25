import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/call_signaling.dart';
import 'package:shamell_flutter/core/chat/chat_service.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    secStore.clear();
    await clearSessionCookie();
    await ChatLocalStore().wipeSecrets();
  });

  test('remote signaling requires bound session cookie', () {
    expect(
      shamellCallSignalingRequiresBoundSessionCookie(
        'https://api.example.com',
      ),
      isTrue,
    );
  });

  test('localhost signaling may skip session cookie in debug flows', () {
    expect(
      shamellCallSignalingRequiresBoundSessionCookie(
        'http://localhost:8080',
      ),
      isFalse,
    );
  });

  test('credentialed localhost signaling still requires bound session cookie',
      () {
    expect(
      shamellCallSignalingRequiresBoundSessionCookie(
        'http://evil.test@localhost:8080',
      ),
      isTrue,
    );
  });

  test('trusted signaling base parser rejects credentialed localhost urls', () {
    expect(
      shamellTrustedCallSignalingBaseUri('http://evil.test@localhost:8080'),
      isNull,
    );
    expect(
      shamellTrustedCallSignalingBaseUri('http://localhost:8080'),
      isNotNull,
    );
  });

  test('call signaling ws uri omits implicit default port', () {
    final trusted = shamellTrustedCallSignalingBaseUri(
      'https://api.shamell.online',
    )!;
    final wsUri = shamellCallSignalingWsUri(
      trustedBaseUri: trusted,
      deviceId: 'dev-1',
    );
    expect(wsUri.toString(),
        'wss://api.shamell.online/ws/call/signaling?device_id=dev-1');
    expect(wsUri.hasPort, isFalse);
  });

  test('call signaling ws uri preserves explicit custom port', () {
    final trusted = shamellTrustedCallSignalingBaseUri(
      'https://api.shamell.online:8443',
    )!;
    final wsUri = shamellCallSignalingWsUri(
      trustedBaseUri: trusted,
      deviceId: 'dev-1',
    );
    expect(
      wsUri.toString(),
      'wss://api.shamell.online:8443/ws/call/signaling?device_id=dev-1',
    );
    expect(wsUri.hasPort, isTrue);
    expect(wsUri.port, 8443);
  });

  test('call signaling ws uri drops explicit zero port', () {
    final wsUri = shamellCallSignalingWsUri(
      trustedBaseUri: Uri(
        scheme: 'https',
        host: 'api.shamell.online',
        port: 0,
      ),
      deviceId: 'dev-1',
    );
    expect(
      wsUri.toString(),
      'wss://api.shamell.online/ws/call/signaling?device_id=dev-1',
    );
    expect(wsUri.hasPort, isFalse);
  });

  test('critical signaling error detail requires reauth', () {
    expect(
      shamellCallSignalingEventRequiresReauth(<String, dynamic>{
        'type': 'error',
        'detail': 'client_device_id mismatch',
      }),
      isTrue,
    );
  });

  test('generic signaling error does not require reauth', () {
    expect(
      shamellCallSignalingEventRequiresReauth(<String, dynamic>{
        'type': 'error',
        'reason': 'insecure_transport',
      }),
      isFalse,
    );
  });

  test('signaling send returns false when socket is not connected', () async {
    final client = CallSignalingClient('https://api.example.com');

    expect(
      await client.send(<String, Object?>{'type': 'invite', 'call_id': 'c1'}),
      isFalse,
    );
    expect(
      await client.sendInvite(
        callId: 'c1',
        fromDeviceId: 'dev-a',
        toDeviceId: 'dev-b',
      ),
      isFalse,
    );
    expect(
      await client.sendAnswer(
        callId: 'c1',
        fromDeviceId: 'dev-a',
        toDeviceId: 'dev-b',
      ),
      isFalse,
    );
  });

  test(
      'localhost signaling headers add client-ip hint, cookie, and device auth',
      () async {
    const baseUrl = 'http://127.0.0.1:8080';
    const deviceId = 'dev-1';
    await setSessionTokenForBaseUrl(
      baseUrl,
      '0123456789abcdef0123456789abcdef',
    );
    await ChatLocalStore().saveDeviceAuthToken(
      deviceId,
      'chat-device-token',
      baseUrlOverride: baseUrl,
    );

    final headers = await shamellCallSignalingHeadersForBaseUrl(
      baseUrl,
      deviceId: deviceId,
    );

    expect(headers['x-shamell-client-ip'], '127.0.0.1');
    expect(
      headers['cookie'],
      '__Host-sa_session=0123456789abcdef0123456789abcdef',
    );
    expect(headers['X-Chat-Device-Id'], deviceId);
    expect(headers['X-Chat-Device-Token'], 'chat-device-token');
  });
}
