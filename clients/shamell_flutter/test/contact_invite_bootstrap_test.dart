import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/chat/chat_service.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_secure_storage uses a platform MethodChannel; unit tests need a mock.
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
    await ChatLocalStore().wipeSecrets();
    await setSessionTokenForBaseUrl(
      'http://127.0.0.1:8080',
      '0123456789abcdef0123456789abcdef',
    );
  });

  test('redeemContactInviteToken bootstraps chat device when missing',
      () async {
    final calls = <String>[];
    String? registeredDeviceId;
    String? redeemHeaderDeviceId;
    String? keyRegisterSigAlg;
    String? keyRegisterSigningPubkeyB64;
    String? keyRegisterSignedPrekeySigB64;

    final mock = MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      if (req.url.path == '/chat/devices/register') {
        final body = jsonDecode(req.body) as Map;
        registeredDeviceId = (body['device_id'] ?? '').toString();
        return http.Response(
          jsonEncode({
            'device_id': registeredDeviceId,
            'public_key_b64': (body['public_key_b64'] ?? '').toString(),
            'auth_token': 'tok-1',
            'name': body['name'],
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      if (req.url.path == '/chat/keys/register') {
        final body = jsonDecode(req.body) as Map<String, Object?>;
        keyRegisterSigAlg = (body['signed_prekey_sig_alg'] ?? '').toString();
        keyRegisterSigningPubkeyB64 =
            (body['identity_signing_pubkey_b64'] ?? '').toString();
        keyRegisterSignedPrekeySigB64 =
            (body['signed_prekey_sig_b64'] ?? '').toString();
        return http.Response('{}', 200);
      }
      if (req.url.path == '/chat/keys/prekeys/upload') {
        return http.Response('{}', 200);
      }
      if (req.url.path == '/contacts/invites/redeem') {
        redeemHeaderDeviceId =
            req.headers['X-Chat-Device-Id'] ?? req.headers['x-chat-device-id'];
        return http.Response(
          jsonEncode({'device_id': 'PEER-1'}),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });

    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    final peerId = await svc.redeemContactInviteToken('a' * 64);

    expect(peerId, 'PEER-1');
    expect(registeredDeviceId, isNotNull);
    expect(redeemHeaderDeviceId, registeredDeviceId);
    expect(keyRegisterSigAlg, 'ed25519');
    expect((keyRegisterSigningPubkeyB64 ?? '').trim().isNotEmpty, isTrue);
    expect((keyRegisterSignedPrekeySigB64 ?? '').trim().isNotEmpty, isTrue);

    // Also ensure the device token is persisted for subsequent authenticated chat requests.
    final me = await ChatLocalStore().loadIdentity();
    expect(me, isNotNull);
    final tok = await ChatLocalStore().loadDeviceAuthToken(me!.id);
    expect(tok, 'tok-1');

    // Should register + bootstrap keys before redeem (best effort).
    expect(calls.first, 'POST /chat/devices/register');
    expect(calls.last, 'POST /contacts/invites/redeem');
  });

  test('redeemContactInviteToken does not re-bootstrap on subsequent calls',
      () async {
    final calls = <String>[];
    var redeemCount = 0;

    final mock = MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      if (req.url.path == '/chat/devices/register') {
        final body = jsonDecode(req.body) as Map;
        final did = (body['device_id'] ?? '').toString();
        return http.Response(
          jsonEncode({
            'device_id': did,
            'public_key_b64': (body['public_key_b64'] ?? '').toString(),
            'auth_token': 'tok-1',
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      if (req.url.path == '/chat/keys/register') {
        return http.Response('{}', 200);
      }
      if (req.url.path == '/chat/keys/prekeys/upload') {
        return http.Response('{}', 200);
      }
      if (req.url.path == '/contacts/invites/redeem') {
        redeemCount += 1;
        return http.Response(
          jsonEncode({'device_id': 'PEER-$redeemCount'}),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });

    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    await svc.redeemContactInviteToken('a' * 64);
    final firstLen = calls.length;
    await svc.redeemContactInviteToken('b' * 64);
    final delta = calls.sublist(firstLen);

    // After the first successful bootstrap, follow-up redeems should not re-register
    // the device or re-upload key material.
    expect(delta, <String>['POST /contacts/invites/redeem']);
  });
}
