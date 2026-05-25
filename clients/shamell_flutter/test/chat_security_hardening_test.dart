import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/account_identity_store.dart';
import 'package:shamell_flutter/core/account_privilege_store.dart';
import 'package:shamell_flutter/core/biometric_preference_store.dart';
import 'package:shamell_flutter/core/chat/shamell_chat_info_page.dart';
import 'package:shamell_flutter/core/chat/chat_models.dart';
import 'package:shamell_flutter/core/chat/outbound_ratchet_bootstrap.dart';
import 'package:shamell_flutter/core/chat/chat_service.dart';
import 'package:shamell_flutter/core/chat/safety_number.dart';
import 'package:shamell_flutter/core/call_signaling.dart';
import 'package:shamell_flutter/core/device_id.dart';
import 'package:shamell_flutter/core/favorites_store.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/logout_wipe.dart';
import 'package:shamell_flutter/core/safe_clipboard.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';

const _testBaseUrl = 'https://api.example.com';

class _CloseTrackingClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      const Stream<List<int>>.empty(),
      200,
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

  String curveKeyB64(int seed) => base64Encode(
        Uint8List.fromList(
          List<int>.generate(32, (i) => ((seed + i) % 251) + 1),
        ),
      );

  String scopedChatPrefKey(String prefix, String scope) {
    final suffix = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
    return '$prefix$suffix';
  }

  String scopedChatEntityPrefKey(String prefix, String scope, String entityId) {
    final suffix = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
    return '$prefix$suffix.$entityId';
  }

  // flutter_secure_storage uses a platform MethodChannel; unit tests need a mock.
  const secChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secStore = <String, String>{};
  void installSecureStorageHandler({
    bool throwOnAccess = false,
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      secChannel,
      (call) async {
        if (throwOnAccess) {
          throw PlatformException(code: 'secure-store-unavailable');
        }
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
  }

  setUpAll(() async {
    installSecureStorageHandler();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secChannel, null);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    secStore.clear();
    await clearStableDeviceId();
    await ChatLocalStore().wipeSecrets();
  });

  test('group send fails closed when no group key exists', () async {
    final service = ChatService('http://127.0.0.1:8080');

    await expectLater(
      service.sendGroupMessage(
        groupId: 'grp-1',
        senderId: 'dev-1',
        text: 'plaintext should never be sent',
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('group encryption key missing'),
        ),
      ),
    );
  });

  test('chat service close honors http client ownership', () {
    final externalClient = _CloseTrackingClient();
    final externalService = ChatService(
      'http://127.0.0.1:8080',
      httpClient: externalClient,
    );

    externalService.close();
    expect(externalClient.closed, isFalse);

    final ownedClient = _CloseTrackingClient();
    final ownedService = ChatService(
      'http://127.0.0.1:8080',
      httpClient: ownedClient,
      ownsHttpClient: true,
    );

    ownedService.close();
    ownedService.close();
    expect(ownedClient.closed, isTrue);
  });

  test('chat service websocket rotation keeps the http client alive', () {
    final ownedClient = _CloseTrackingClient();
    final service = ChatService(
      'http://127.0.0.1:8080',
      httpClient: ownedClient,
      ownsHttpClient: true,
    );

    service.closeLiveSockets();

    expect(ownedClient.closed, isFalse);

    service.close();
    expect(ownedClient.closed, isTrue);
  });

  test('group inbox blocks unsealed (legacy) messages', () {
    final m = ChatGroupMessage(
      id: 'm1',
      groupId: 'g1',
      senderId: 'dev-legacy',
      text: 'PLAINTEXT SHOULD NEVER RENDER',
      kind: 'legacy',
      createdAt: DateTime.now(),
    );
    final key = Uint8List.fromList(List<int>.filled(32, 7));
    final out = shamellDecryptOrBlockGroupMessage(m, key);
    expect(out.kind, 'system');
    expect(out.text.toLowerCase(), contains('blocked'));
    expect(out.text, isNot(contains('PLAINTEXT')));
  });

  test('sealed group message without ciphertext never shows server text', () {
    final m = ChatGroupMessage(
      id: 'm2',
      groupId: 'g1',
      senderId: 'dev-1',
      text: 'SERVER TEXT MUST NOT DISPLAY',
      kind: 'sealed',
      nonceB64: null,
      boxB64: null,
      createdAt: DateTime.now(),
    );
    final key = Uint8List.fromList(List<int>.filled(32, 7));
    final out = shamellDecryptOrBlockGroupMessage(m, key);
    expect(out.kind, 'sealed');
    expect(out.text, isNot(contains('SERVER TEXT')));
    expect(out.text, isEmpty);
  });

  test('chat secrets are never stored in SharedPreferences fallback', () async {
    final store = ChatLocalStore();
    // 32 bytes group key in base64 (any value is fine for this test).
    final keyB64 = base64Encode(List<int>.filled(32, 7));
    await store.saveGroupKey('grp-1', keyB64);
    final sp = await SharedPreferences.getInstance();
    expect(
        sp.getKeys().any((k) => k.startsWith('chat.sec.fallback.')), isFalse);
  });

  test('shamell-id contact resolution rejects invalid identifiers', () async {
    final service = ChatService('http://127.0.0.1:8080');

    await expectLater(
      service.resolveContactByShamellId('invalid'),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('invalid shamell id'),
        ),
      ),
    );
  });

  test('desktop secure storage is enabled by default', () {
    expect(shamellDesktopSecureStorageDefault, isTrue);
  });

  test('chat protocol send version is v2_libsignal (no fallback)', () {
    expect(shamellChatProtocolSendVersion, 'v2_libsignal');
  });

  test(
      'account chat bootstrap is serialized across ChatService instances sharing one base',
      () async {
    await setSessionTokenForBaseUrl(_testBaseUrl, 'a' * 32);
    await saveStoredShamellUserId(
      'ABCDEFGH',
      baseUrlOverride: _testBaseUrl,
    );
    await saveStableDeviceId(
      'test-client-device-001',
      baseUrlOverride: _testBaseUrl,
    );

    final registerStarted = Completer<void>();
    final releaseRegister = Completer<void>();
    final registeredDeviceIds = <String>[];
    var registerCalls = 0;
    var bootstrapCalls = 0;

    final mock = MockClient((req) async {
      if (req.url.path == '/chat/devices/register') {
        registerCalls += 1;
        final body = jsonDecode(req.body) as Map<String, Object?>;
        registeredDeviceIds.add((body['device_id'] ?? '').toString());
        if (!registerStarted.isCompleted) {
          registerStarted.complete();
        }
        await releaseRegister.future;
        return http.Response(
          jsonEncode(<String, Object?>{
            'device_id': body['device_id'],
            'public_key_b64': body['public_key_b64'],
            'auth_token': 'b' * 64,
            'name': body['name'],
          }),
          200,
        );
      }
      if (req.url.path == '/chat/keys/bootstrap') {
        bootstrapCalls += 1;
        return http.Response('{}', 200);
      }
      return http.Response('{}', 200);
    });

    final first =
        ChatService(_testBaseUrl, httpClient: mock).ensureAccountChatReady();
    await registerStarted.future;
    final second =
        ChatService(_testBaseUrl, httpClient: mock).ensureAccountChatReady();
    releaseRegister.complete();

    await Future.wait<void>(<Future<void>>[first, second]);

    expect(registerCalls, 1);
    expect(bootstrapCalls, 1);
    expect(registeredDeviceIds, hasLength(1));
  });

  test('ChatService fails closed on credentialed or path-prefixed base URLs',
      () async {
    var requests = 0;
    final mock = MockClient((req) async {
      requests += 1;
      return http.Response('{}', 200);
    });
    final service = ChatService(
      'http://user:pass@localhost:8080/prefix?x=1#frag',
      httpClient: mock,
    );

    await expectLater(
      () => service.resolveDevice('peer-1'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Invalid chat base URL'),
        ),
      ),
    );
    expect(requests, 0);
  });

  test('direct inbox envelope guard accepts only sealed v2 envelopes', () {
    expect(
      shamellAcceptDirectInboxEnvelope(<String, Object?>{
        'protocol_version': 'v2_libsignal',
        'sealed_sender': true,
        'nonce_b64': 'AQ==',
        'box_b64': 'Ag==',
      }),
      isTrue,
    );

    expect(
      shamellAcceptDirectInboxEnvelope(<String, Object?>{
        'protocol_version': 'v1_legacy',
        'sealed_sender': true,
        'nonce_b64': 'AQ==',
        'box_b64': 'Ag==',
      }),
      isFalse,
    );
    expect(
      shamellAcceptDirectInboxEnvelope(<String, Object?>{
        'protocol_version': 'v2_libsignal',
        'sealed_sender': false,
        'nonce_b64': 'AQ==',
        'box_b64': 'Ag==',
      }),
      isFalse,
    );
    expect(
      shamellAcceptDirectInboxEnvelope(<String, Object?>{
        'protocol_version': 'v2_libsignal',
        'sealed_sender': true,
        'nonce_b64': '',
        'box_b64': 'Ag==',
      }),
      isFalse,
    );
  });

  test('fetchInbox drops non-v2 or unsealed direct envelopes', () async {
    final mock = MockClient((req) async {
      if (req.url.path == '/chat/messages/inbox') {
        return http.Response(
          jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'id': 'legacy-1',
              'sender_id': 'peer-1',
              'recipient_id': 'me-1',
              'sender_pubkey_b64': '',
              'nonce_b64': 'AQ==',
              'box_b64': 'Ag==',
              'protocol_version': 'v1_legacy',
              'sealed_sender': true,
            },
            <String, Object?>{
              'id': 'unsealed-1',
              'sender_id': 'peer-1',
              'recipient_id': 'me-1',
              'sender_pubkey_b64': '',
              'nonce_b64': 'AQ==',
              'box_b64': 'Ag==',
              'protocol_version': 'v2_libsignal',
              'sealed_sender': false,
            },
            <String, Object?>{
              'id': 'ok-v2',
              'sender_id': 'peer-1',
              'recipient_id': 'me-1',
              'sender_pubkey_b64': '',
              'nonce_b64': 'AQ==',
              'box_b64': 'Ag==',
              'protocol_version': 'v2_libsignal',
              'sealed_sender': true,
              'created_at': DateTime.now().toUtc().toIso8601String(),
            },
          ]),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });

    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    final inbox = await svc.fetchInbox(deviceId: 'me-1');
    expect(inbox, hasLength(1));
    expect(inbox.single.id, 'ok-v2');
    expect(inbox.single.sealedSender, isTrue);
  });

  test('fetchInbox forwards stable cursor query parameters', () async {
    late Uri requestUri;
    final mock = MockClient((req) async {
      requestUri = req.url;
      return http.Response(
        '[]',
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    await svc.fetchInbox(
      deviceId: 'me-1',
      sinceIso: '2026-03-18T10:00:00Z',
      sinceId: 'msg-002',
      limit: 25,
    );

    expect(requestUri.path, '/chat/messages/inbox');
    expect(requestUri.queryParameters['device_id'], 'me-1');
    expect(requestUri.queryParameters['since_iso'], '2026-03-18T10:00:00Z');
    expect(requestUri.queryParameters['since_id'], 'msg-002');
    expect(requestUri.queryParameters['limit'], '25');
  });

  test('fetchInbox forwards stable before cursor query parameters', () async {
    late Uri requestUri;
    final mock = MockClient((req) async {
      requestUri = req.url;
      return http.Response(
        '[]',
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    await svc.fetchInbox(
      deviceId: 'me-1',
      beforeCreatedAt: '2026-03-18T10:00:00Z',
      beforeId: 'msg-002',
      limit: 25,
    );

    expect(requestUri.path, '/chat/messages/inbox');
    expect(requestUri.queryParameters['device_id'], 'me-1');
    expect(
      requestUri.queryParameters['before_created_at'],
      '2026-03-18T10:00:00Z',
    );
    expect(requestUri.queryParameters['before_id'], 'msg-002');
    expect(requestUri.queryParameters['limit'], '25');
  });

  test('fetchThreadHistory forwards peer and stable before cursor query',
      () async {
    late Uri requestUri;
    final mock = MockClient((req) async {
      requestUri = req.url;
      return http.Response(
        '[]',
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    await svc.fetchThreadHistory(
      deviceId: 'me-1',
      peerId: 'peer-9',
      beforeCreatedAt: '2026-03-18T10:00:00Z',
      beforeId: 'msg-002',
      limit: 25,
    );

    expect(requestUri.path, '/chat/messages/thread');
    expect(requestUri.queryParameters['device_id'], 'me-1');
    expect(requestUri.queryParameters['peer_id'], 'peer-9');
    expect(
      requestUri.queryParameters['before_created_at'],
      '2026-03-18T10:00:00Z',
    );
    expect(requestUri.queryParameters['before_id'], 'msg-002');
    expect(requestUri.queryParameters['limit'], '25');
  });

  test(
      'fetchThreadHistory accepts redacted sealed-sender payloads from the BFF contract',
      () async {
    final mock = MockClient((req) async {
      expect(req.url.path, '/chat/messages/thread');
      return http.Response(
        jsonEncode(<Map<String, Object?>>[
          <String, Object?>{
            'id': 'm-thread-out',
            'sender_id': null,
            'recipient_id': 'peer-9',
            'protocol_version': 'v2_libsignal',
            'sender_pubkey_b64': null,
            'nonce_b64': 'AQ==',
            'box_b64': 'Ag==',
            'created_at': '2026-03-18T10:00:00Z',
            'sealed_sender': true,
            'sender_hint': 'fp-me',
            'sender_fingerprint': 'fp-me',
          },
          <String, Object?>{
            'id': 'm-thread-in',
            'sender_id': null,
            'recipient_id': 'me-1',
            'protocol_version': 'v2_libsignal',
            'sender_pubkey_b64': null,
            'nonce_b64': 'AQ==',
            'box_b64': 'Ag==',
            'created_at': '2026-03-18T10:00:01Z',
            'sealed_sender': true,
            'sender_hint': 'fp-peer',
            'sender_fingerprint': 'fp-peer',
          },
        ]),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    final messages = await svc.fetchThreadHistory(
      deviceId: 'me-1',
      peerId: 'peer-9',
      limit: 25,
    );

    expect(messages, hasLength(2));
    expect(messages[0].id, 'm-thread-out');
    expect(messages[0].senderId, isEmpty);
    expect(messages[0].recipientId, 'peer-9');
    expect(messages[0].sealedSender, isTrue);
    expect(messages[0].senderHint, 'fp-me');
    expect(messages[1].id, 'm-thread-in');
    expect(messages[1].senderId, isEmpty);
    expect(messages[1].recipientId, 'me-1');
    expect(messages[1].sealedSender, isTrue);
    expect(messages[1].senderHint, 'fp-peer');
  });

  test('fetchInboxPaged paginates forward and keeps latest window', () async {
    final requests = <Map<String, String>>[];
    final mock = MockClient((req) async {
      requests.add(Map<String, String>.from(req.url.queryParameters));
      final sinceId = req.url.queryParameters['since_id'];
      final body = switch (sinceId) {
        'msg-002' => jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'id': 'msg-003',
              'sender_id': 'peer-1',
              'recipient_id': 'me-1',
              'protocol_version': 'v2_libsignal',
              'sealed_sender': true,
              'nonce_b64': 'AQ==',
              'box_b64': 'Ag==',
              'created_at': '2026-03-18T10:00:02Z',
            },
          ]),
        _ => jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'id': 'msg-001',
              'sender_id': 'peer-1',
              'recipient_id': 'me-1',
              'protocol_version': 'v2_libsignal',
              'sealed_sender': true,
              'nonce_b64': 'AQ==',
              'box_b64': 'Ag==',
              'created_at': '2026-03-18T10:00:00Z',
            },
            <String, Object?>{
              'id': 'msg-002',
              'sender_id': 'peer-1',
              'recipient_id': 'me-1',
              'protocol_version': 'v2_libsignal',
              'sealed_sender': true,
              'nonce_b64': 'AQ==',
              'box_b64': 'Ag==',
              'created_at': '2026-03-18T10:00:01Z',
            },
          ]),
      };
      return http.Response(
        body,
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    final inbox = await svc.fetchInboxPaged(
      deviceId: 'me-1',
      sinceIso: '2026-03-18T09:59:59Z',
      sinceId: 'msg-000',
      batchSize: 2,
      maxPages: 4,
      retainLatestCount: 2,
    );

    expect(inbox.map((m) => m.id).toList(), <String>['msg-002', 'msg-003']);
    expect(requests, hasLength(2));
    expect(requests.first['since_id'], 'msg-000');
    expect(requests.last['since_id'], 'msg-002');
    expect(requests.last['since_iso'], '2026-03-18T10:00:01.000Z');
  });

  test('fetchInboxPaged backfills older direct messages without cursor',
      () async {
    final requests = <Map<String, String>>[];
    final mock = MockClient((req) async {
      requests.add(Map<String, String>.from(req.url.queryParameters));
      final beforeId = req.url.queryParameters['before_id'];
      final body = switch (beforeId) {
        'msg-002' => jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'id': 'msg-001',
              'sender_id': 'peer-1',
              'recipient_id': 'me-1',
              'protocol_version': 'v2_libsignal',
              'sealed_sender': true,
              'nonce_b64': 'AQ==',
              'box_b64': 'Ag==',
              'created_at': '2026-03-18T09:59:59Z',
            },
          ]),
        _ => jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'id': 'msg-003',
              'sender_id': 'peer-1',
              'recipient_id': 'me-1',
              'protocol_version': 'v2_libsignal',
              'sealed_sender': true,
              'nonce_b64': 'AQ==',
              'box_b64': 'Ag==',
              'created_at': '2026-03-18T10:00:01Z',
            },
            <String, Object?>{
              'id': 'msg-002',
              'sender_id': 'peer-1',
              'recipient_id': 'me-1',
              'protocol_version': 'v2_libsignal',
              'sealed_sender': true,
              'nonce_b64': 'AQ==',
              'box_b64': 'Ag==',
              'created_at': '2026-03-18T10:00:00Z',
            },
          ]),
      };
      return http.Response(
        body,
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    final inbox = await svc.fetchInboxPaged(
      deviceId: 'me-1',
      batchSize: 2,
      maxPages: 4,
    );

    expect(inbox.map((m) => m.id).toList(),
        <String>['msg-001', 'msg-002', 'msg-003']);
    expect(requests, hasLength(2));
    expect(requests.first['before_id'], isNull);
    expect(requests.last['before_id'], 'msg-002');
    expect(requests.last['before_created_at'], '2026-03-18T10:00:00.000Z');
  });

  test('fetchGroupInbox forwards stable cursor query parameters', () async {
    late Uri requestUri;
    final mock = MockClient((req) async {
      requestUri = req.url;
      return http.Response(
        '[]',
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    await svc.fetchGroupInbox(
      groupId: 'group-1',
      deviceId: 'me-1',
      sinceIso: '2026-03-18T10:00:00Z',
      sinceId: 'msg-002',
      limit: 25,
    );

    expect(requestUri.path, '/chat/groups/group-1/messages/inbox');
    expect(requestUri.queryParameters['device_id'], 'me-1');
    expect(requestUri.queryParameters['since_iso'], '2026-03-18T10:00:00Z');
    expect(requestUri.queryParameters['since_id'], 'msg-002');
    expect(requestUri.queryParameters['limit'], '25');
  });

  test('fetchGroupInbox forwards stable before cursor query parameters',
      () async {
    late Uri requestUri;
    final mock = MockClient((req) async {
      requestUri = req.url;
      return http.Response(
        '[]',
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    await svc.fetchGroupInbox(
      groupId: 'group-1',
      deviceId: 'me-1',
      beforeCreatedAt: '2026-03-18T10:00:00Z',
      beforeId: 'msg-002',
      limit: 25,
    );

    expect(requestUri.path, '/chat/groups/group-1/messages/inbox');
    expect(requestUri.queryParameters['device_id'], 'me-1');
    expect(
      requestUri.queryParameters['before_created_at'],
      '2026-03-18T10:00:00Z',
    );
    expect(requestUri.queryParameters['before_id'], 'msg-002');
    expect(requestUri.queryParameters['limit'], '25');
  });

  test('fetchGroupInboxPaged paginates older slices and keeps latest window',
      () async {
    final requests = <Map<String, String>>[];
    final mock = MockClient((req) async {
      requests.add(Map<String, String>.from(req.url.queryParameters));
      final beforeId = req.url.queryParameters['before_id'];
      final body = switch (beforeId) {
        null => jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'id': 'msg-002',
              'group_id': 'group-1',
              'sender_id': 'peer-1',
              'text': 'second',
              'created_at': '2026-03-18T10:00:01Z',
            },
            <String, Object?>{
              'id': 'msg-003',
              'group_id': 'group-1',
              'sender_id': 'peer-1',
              'text': 'third',
              'created_at': '2026-03-18T10:00:02Z',
            },
          ]),
        'msg-002' => jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'id': 'msg-001',
              'group_id': 'group-1',
              'sender_id': 'peer-1',
              'text': 'first',
              'created_at': '2026-03-18T10:00:00Z',
            },
          ]),
        _ => '[]',
      };
      return http.Response(
        body,
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    final msgs = await svc.fetchGroupInboxPaged(
      groupId: 'group-1',
      deviceId: 'me-1',
      batchSize: 2,
      retainLatestCount: 2,
    );

    expect(msgs.map((m) => m.id).toList(), <String>['msg-002', 'msg-003']);
    expect(requests, hasLength(2));
    expect(requests[0]['before_id'], isNull);
    expect(requests[0]['limit'], '2');
    expect(requests[1]['before_id'], 'msg-002');
    expect(requests[1]['before_created_at'], '2026-03-18T10:00:01.000Z');
  });

  test('fetchPrefs forwards stable after_peer_id query parameters', () async {
    late Uri requestUri;
    final mock = MockClient((req) async {
      requestUri = req.url;
      return http.Response(
        '{"prefs":[]}',
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    await svc.fetchPrefs(
      deviceId: 'me-1',
      limit: 25,
      afterPeerId: 'peer-002',
    );

    expect(requestUri.path, '/chat/devices/me-1/prefs');
    expect(requestUri.queryParameters['limit'], '25');
    expect(requestUri.queryParameters['after_peer_id'], 'peer-002');
  });

  test('fetchPrefsPaged paginates slices and keeps stable order', () async {
    final requests = <Map<String, String>>[];
    final mock = MockClient((req) async {
      requests.add(Map<String, String>.from(req.url.queryParameters));
      final afterPeerId = req.url.queryParameters['after_peer_id'];
      final body = switch (afterPeerId) {
        'peer-002' => jsonEncode(<String, Object?>{
            'prefs': <Map<String, Object?>>[
              <String, Object?>{
                'peer_id': 'peer-003',
                'muted': true,
                'starred': false,
                'pinned': false,
              },
            ],
          }),
        _ => jsonEncode(<String, Object?>{
            'prefs': <Map<String, Object?>>[
              <String, Object?>{
                'peer_id': 'peer-001',
                'muted': false,
                'starred': false,
                'pinned': false,
              },
              <String, Object?>{
                'peer_id': 'peer-002',
                'muted': true,
                'starred': false,
                'pinned': true,
              },
            ],
          }),
      };
      return http.Response(
        body,
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    final prefs = await svc.fetchPrefsPaged(
      deviceId: 'me-1',
      batchSize: 2,
      maxPages: 4,
    );

    expect(prefs.map((p) => p.peerId).toList(), <String>[
      'peer-001',
      'peer-002',
      'peer-003',
    ]);
    expect(requests, hasLength(2));
    expect(requests.first['after_peer_id'], isNull);
    expect(requests.last['after_peer_id'], 'peer-002');
  });

  test('fetchGroupPrefs forwards stable after_group_id query parameters',
      () async {
    late Uri requestUri;
    final mock = MockClient((req) async {
      requestUri = req.url;
      return http.Response(
        '[]',
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    await svc.fetchGroupPrefs(
      deviceId: 'me-1',
      limit: 25,
      afterGroupId: 'grp-002',
    );

    expect(requestUri.path, '/chat/devices/me-1/group_prefs');
    expect(requestUri.queryParameters['limit'], '25');
    expect(requestUri.queryParameters['after_group_id'], 'grp-002');
  });

  test('fetchGroupPrefsPaged paginates slices and keeps stable order',
      () async {
    final requests = <Map<String, String>>[];
    final mock = MockClient((req) async {
      requests.add(Map<String, String>.from(req.url.queryParameters));
      final afterGroupId = req.url.queryParameters['after_group_id'];
      final body = switch (afterGroupId) {
        'grp-002' => jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'group_id': 'grp-003',
              'muted': true,
              'pinned': false,
            },
          ]),
        _ => jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'group_id': 'grp-001',
              'muted': false,
              'pinned': false,
            },
            <String, Object?>{
              'group_id': 'grp-002',
              'muted': true,
              'pinned': true,
            },
          ]),
      };
      return http.Response(
        body,
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    final prefs = await svc.fetchGroupPrefsPaged(
      deviceId: 'me-1',
      batchSize: 2,
      maxPages: 4,
    );

    expect(prefs.map((p) => p.groupId).toList(), <String>[
      'grp-001',
      'grp-002',
      'grp-003',
    ]);
    expect(requests, hasLength(2));
    expect(requests.first['after_group_id'], isNull);
    expect(requests.last['after_group_id'], 'grp-002');
  });

  test('fetchGroupPrefForGroup paginates until the target group is found',
      () async {
    final requests = <Map<String, String>>[];
    final mock = MockClient((req) async {
      requests.add(Map<String, String>.from(req.url.queryParameters));
      final afterGroupId = req.url.queryParameters['after_group_id'];
      final body = switch (afterGroupId) {
        'grp-002' => jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'group_id': 'grp-003',
              'muted': true,
              'pinned': false,
            },
          ]),
        _ => jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'group_id': 'grp-001',
              'muted': false,
              'pinned': false,
            },
            <String, Object?>{
              'group_id': 'grp-002',
              'muted': false,
              'pinned': true,
            },
          ]),
      };
      return http.Response(
        body,
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    final pref = await svc.fetchGroupPrefForGroup(
      deviceId: 'me-1',
      groupId: 'grp-003',
      batchSize: 2,
      maxPages: 4,
    );

    expect(pref, isNotNull);
    expect(pref!.groupId, 'grp-003');
    expect(pref.muted, isTrue);
    expect(requests, hasLength(2));
    expect(requests.first['after_group_id'], isNull);
    expect(requests.last['after_group_id'], 'grp-002');
  });

  test('fetchGroupById paginates until the target group is found', () async {
    final requests = <Map<String, String>>[];
    final mock = MockClient((req) async {
      requests.add(Map<String, String>.from(req.url.queryParameters));
      final beforeId = req.url.queryParameters['before_id'];
      final body = switch (beforeId) {
        'grp-002' => jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'group_id': 'grp-003',
              'name': 'Third',
              'creator_id': 'me-1',
              'created_at': '2026-03-18T09:58:00Z',
            },
          ]),
        _ => jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'group_id': 'grp-001',
              'name': 'First',
              'creator_id': 'me-1',
              'created_at': '2026-03-18T10:00:00Z',
            },
            <String, Object?>{
              'group_id': 'grp-002',
              'name': 'Second',
              'creator_id': 'me-1',
              'created_at': '2026-03-18T09:59:00Z',
            },
          ]),
      };
      return http.Response(
        body,
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    final group = await svc.fetchGroupById(
      deviceId: 'me-1',
      groupId: 'grp-003',
      batchSize: 2,
    );

    expect(group, isNotNull);
    expect(group!.id, 'grp-003');
    expect(group.name, 'Third');
    expect(requests, hasLength(2));
    expect(requests.first['before_id'], isNull);
    expect(requests.last['before_id'], 'grp-002');
    expect(
      requests.last['before_created_at'],
      '2026-03-18T09:59:00.000Z',
    );
  });

  test('listGroupsPage forwards stable before cursor query parameters',
      () async {
    late Uri requestUri;
    final mock = MockClient((req) async {
      requestUri = req.url;
      return http.Response(
        '[]',
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    await svc.listGroupsPage(
      deviceId: 'me-1',
      limit: 25,
      beforeCreatedAt: '2026-03-18T10:00:00Z',
      beforeId: 'grp-002',
    );

    expect(requestUri.path, '/chat/groups/list');
    expect(requestUri.queryParameters['device_id'], 'me-1');
    expect(requestUri.queryParameters['limit'], '25');
    expect(
      requestUri.queryParameters['before_created_at'],
      '2026-03-18T10:00:00Z',
    );
    expect(requestUri.queryParameters['before_id'], 'grp-002');
  });

  test('listGroupsPaged paginates older slices and keeps stable order',
      () async {
    final requests = <Map<String, String>>[];
    final mock = MockClient((req) async {
      requests.add(Map<String, String>.from(req.url.queryParameters));
      final beforeId = req.url.queryParameters['before_id'];
      final body = switch (beforeId) {
        'grp-002' => jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'group_id': 'grp-003',
              'name': 'Third',
              'creator_id': 'me-1',
              'created_at': '2026-03-18T09:58:00Z',
            },
          ]),
        _ => jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'group_id': 'grp-001',
              'name': 'First',
              'creator_id': 'me-1',
              'created_at': '2026-03-18T10:00:00Z',
            },
            <String, Object?>{
              'group_id': 'grp-002',
              'name': 'Second',
              'creator_id': 'me-1',
              'created_at': '2026-03-18T09:59:00Z',
            },
          ]),
      };
      return http.Response(
        body,
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    final groups = await svc.listGroupsPaged(
      deviceId: 'me-1',
      batchSize: 2,
      maxPages: 4,
    );

    expect(groups.map((g) => g.id).toList(), <String>[
      'grp-001',
      'grp-002',
      'grp-003',
    ]);
    expect(requests, hasLength(2));
    expect(requests.first['before_id'], isNull);
    expect(requests.last['before_id'], 'grp-002');
    expect(
      requests.last['before_created_at'],
      '2026-03-18T09:59:00.000Z',
    );
  });

  test('listGroupMembersPage forwards stable after cursor query parameters',
      () async {
    late Uri requestUri;
    final mock = MockClient((req) async {
      requestUri = req.url;
      return http.Response(
        '[]',
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    await svc.listGroupMembersPage(
      groupId: 'group-1',
      deviceId: 'me-1',
      limit: 25,
      afterJoinedAt: '2026-03-18T10:00:00Z',
      afterDeviceId: 'dev-002',
    );

    expect(requestUri.path, '/chat/groups/group-1/members');
    expect(requestUri.queryParameters['device_id'], 'me-1');
    expect(requestUri.queryParameters['limit'], '25');
    expect(
      requestUri.queryParameters['after_joined_at'],
      '2026-03-18T10:00:00Z',
    );
    expect(requestUri.queryParameters['after_device_id'], 'dev-002');
  });

  test('listGroupMembersPaged paginates newer slices and keeps stable order',
      () async {
    final requests = <Map<String, String>>[];
    final mock = MockClient((req) async {
      requests.add(Map<String, String>.from(req.url.queryParameters));
      final afterDeviceId = req.url.queryParameters['after_device_id'];
      final body = switch (afterDeviceId) {
        'dev-002' => jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'device_id': 'dev-003',
              'role': 'member',
              'joined_at': '2026-03-18T10:02:00Z',
            },
          ]),
        _ => jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'device_id': 'dev-001',
              'role': 'admin',
              'joined_at': '2026-03-18T10:00:00Z',
            },
            <String, Object?>{
              'device_id': 'dev-002',
              'role': 'member',
              'joined_at': '2026-03-18T10:01:00Z',
            },
          ]),
      };
      return http.Response(
        body,
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    final members = await svc.listGroupMembersPaged(
      groupId: 'group-1',
      deviceId: 'me-1',
      batchSize: 2,
      maxPages: 4,
    );

    expect(members.map((m) => m.deviceId).toList(), <String>[
      'dev-001',
      'dev-002',
      'dev-003',
    ]);
    expect(requests, hasLength(2));
    expect(requests.first['after_device_id'], isNull);
    expect(requests.last['after_device_id'], 'dev-002');
    expect(
      requests.last['after_joined_at'],
      '2026-03-18T10:01:00.000Z',
    );
  });

  test('listGroupKeyEventsPage forwards stable before_version query parameter',
      () async {
    late Uri requestUri;
    final mock = MockClient((req) async {
      requestUri = req.url;
      return http.Response(
        '[]',
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    await svc.listGroupKeyEventsPage(
      groupId: 'group-1',
      deviceId: 'me-1',
      limit: 25,
      beforeVersion: 41,
    );

    expect(requestUri.path, '/chat/groups/group-1/keys/events');
    expect(requestUri.queryParameters['device_id'], 'me-1');
    expect(requestUri.queryParameters['limit'], '25');
    expect(requestUri.queryParameters['before_version'], '41');
  });

  test('listGroupKeyEventsPaged paginates older slices and keeps stable order',
      () async {
    final requests = <Map<String, String>>[];
    final mock = MockClient((req) async {
      requests.add(Map<String, String>.from(req.url.queryParameters));
      final beforeVersion = req.url.queryParameters['before_version'];
      final body = switch (beforeVersion) {
        '4' => jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'group_id': 'group-1',
              'version': 3,
              'actor_id': 'dev-003',
              'created_at': '2026-03-18T09:58:00Z',
            },
          ]),
        _ => jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'group_id': 'group-1',
              'version': 5,
              'actor_id': 'dev-001',
              'created_at': '2026-03-18T10:00:00Z',
            },
            <String, Object?>{
              'group_id': 'group-1',
              'version': 4,
              'actor_id': 'dev-002',
              'created_at': '2026-03-18T09:59:00Z',
            },
          ]),
      };
      return http.Response(
        body,
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    final events = await svc.listGroupKeyEventsPaged(
      groupId: 'group-1',
      deviceId: 'me-1',
      batchSize: 2,
      maxPages: 5,
    );

    expect(events.map((event) => event.version).toList(), <int>[5, 4, 3]);
    expect(requests, hasLength(2));
    expect(requests.first['before_version'], isNull);
    expect(requests.last['before_version'], '4');
  });

  test('fetchKeyBundle preserves critical http details', () async {
    final mock = MockClient((req) async {
      if (req.url.path == '/chat/keys/bundle/peer-1') {
        return http.Response('{"detail":"auth session required"}', 401);
      }
      return http.Response('{}', 404);
    });
    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);

    await expectLater(
      () => svc.fetchKeyBundle(targetDeviceId: 'peer-1'),
      throwsA(
        isA<ChatHttpException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.body, 'body', contains('auth session required')),
      ),
    );
  });

  test('outbound ratchet bootstrap preserves critical key-bundle http failures',
      () async {
    final store = ChatLocalStore();
    final mock = MockClient((req) async {
      if (req.url.path == '/chat/keys/bundle/peer-1') {
        return http.Response('{"detail":"auth session required"}', 401);
      }
      return http.Response('{}', 404);
    });
    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    final bootstrapper = ChatOutboundRatchetBootstrapper(
      service: svc,
      store: store,
    );

    await expectLater(
      () => bootstrapper.nextOutboundSendContext(
        me: ChatIdentity(
          id: 'me-1',
          publicKeyB64: base64Encode(List<int>.filled(32, 11)),
          privateKeyB64: base64Encode(List<int>.filled(32, 19)),
          fingerprint: 'fp-me-1',
        ),
        peer: ChatContact(
          id: 'peer-1',
          publicKeyB64: base64Encode(List<int>.filled(32, 23)),
          fingerprint: 'fp-peer-1',
        ),
      ),
      throwsA(
        isA<ChatHttpException>()
            .having((e) => e.op, 'op', 'fetchKeyBundle')
            .having((e) => e.statusCode, 'statusCode', 401),
      ),
    );
  });

  test(
      'outbound ratchet bootstrap refreshes key-bundle even with local bootstrap metadata',
      () async {
    final store = ChatLocalStore();
    var fetchKeyBundleCalls = 0;
    final mock = MockClient((req) async {
      if (req.url.path == '/chat/keys/bundle/peer-1') {
        fetchKeyBundleCalls += 1;
        return http.Response('{}', 500);
      }
      return http.Response('{}', 404);
    });
    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    await store.saveSessionBootstrapMeta(
      'peer-1',
      protocolFloor: 'v2_libsignal',
      signedPrekeyId: 5,
      oneTimePrekeyId: 6,
      v2Only: true,
      identitySigningPubkeyB64: base64Encode(List<int>.filled(32, 31)),
      baseUrlOverride: svc.baseUrl,
    );
    final bootstrapper = ChatOutboundRatchetBootstrapper(
      service: svc,
      store: store,
    );

    await expectLater(
      () => bootstrapper.nextOutboundSendContext(
        me: ChatIdentity(
          id: 'me-1',
          publicKeyB64: base64Encode(List<int>.filled(32, 11)),
          privateKeyB64: base64Encode(List<int>.filled(32, 19)),
          fingerprint: 'fp-me-1',
        ),
        peer: ChatContact(
          id: 'peer-1',
          publicKeyB64: base64Encode(List<int>.filled(32, 23)),
          fingerprint: fingerprintForKey(
            base64Encode(List<int>.filled(32, 23)),
          ),
        ),
      ),
      throwsA(
        isA<ChatHttpException>().having(
          (e) => e.statusCode,
          'statusCode',
          500,
        ),
      ),
    );
    expect(fetchKeyBundleCalls, 1);
  });

  test(
      'outbound ratchet bootstrap auto-recovers signing-key rotation for unverified peers',
      () async {
    final store = ChatLocalStore();
    final oldIdentityKey = base64Encode(List<int>.filled(32, 23));
    final newIdentityKey = base64Encode(List<int>.filled(32, 41));
    final oldSigningKey = base64Encode(List<int>.filled(32, 31));
    final newSigningKey = base64Encode(List<int>.filled(32, 71));
    final oldFingerprint = fingerprintForKey(oldIdentityKey);
    final newFingerprint = fingerprintForKey(newIdentityKey);
    final staleRatchet = <String, Object>{
      'rk': oldIdentityKey,
      'ck_s': oldIdentityKey,
      'ck_r': oldIdentityKey,
      'ns': 1,
      'nr': 1,
      'pn': 0,
      'skipped': <String, String>{},
      'peer': 'stale-fingerprint',
      'dh_priv': oldIdentityKey,
      'dh_pub': oldIdentityKey,
      'peer_dh': oldIdentityKey,
      'peer_dh_b64': oldIdentityKey,
      'max_skip': 50,
    };
    await store.saveRatchet(
      'peer-1',
      staleRatchet,
      baseUrlOverride: 'http://127.0.0.1:8080',
    );
    await store.saveSessionBootstrapMeta(
      'peer-1',
      protocolFloor: 'v2_libsignal',
      signedPrekeyId: 4,
      oneTimePrekeyId: 8,
      v2Only: true,
      identitySigningPubkeyB64: oldSigningKey,
      baseUrlOverride: 'http://127.0.0.1:8080',
    );

    final mock = MockClient((req) async {
      if (req.url.path == '/chat/keys/bundle/peer-1') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'device_id': 'peer-1',
            'identity_key_b64': newIdentityKey,
            'identity_signing_pubkey_b64': newSigningKey,
            'signed_prekey_id': 9,
            'signed_prekey_b64': base64Encode(List<int>.filled(32, 51)),
            'signed_prekey_sig_b64': base64Encode(List<int>.filled(64, 12)),
            'one_time_prekey_id': 10,
            'one_time_prekey_b64': base64Encode(List<int>.filled(32, 52)),
            'protocol_floor': 'v2_libsignal',
            'supports_v2': true,
            'v2_only': true,
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });
    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    final bootstrapper = ChatOutboundRatchetBootstrapper(
      service: svc,
      store: store,
    );

    final next = await bootstrapper.nextOutboundSendContext(
      me: ChatIdentity(
        id: 'me-1',
        publicKeyB64: base64Encode(List<int>.filled(32, 11)),
        privateKeyB64: base64Encode(List<int>.filled(32, 19)),
        fingerprint: 'fp-me-1',
      ),
      peer: ChatContact(
        id: 'peer-1',
        publicKeyB64: oldIdentityKey,
        fingerprint: oldFingerprint,
        verified: false,
      ),
    );

    expect(next.peer.publicKeyB64, newIdentityKey);
    expect(next.peer.fingerprint, newFingerprint);
    expect(
      await store.loadPinnedIdentitySigningPubkey(
        'peer-1',
        baseUrlOverride: svc.baseUrl,
      ),
      newSigningKey,
    );
    final savedRatchet = await store.loadRatchet(
      'peer-1',
      baseUrlOverride: svc.baseUrl,
    );
    expect(savedRatchet['peer'], newFingerprint);
  });

  test(
      'outbound ratchet bootstrap blocks signing-key rotation for verified peer',
      () async {
    final store = ChatLocalStore();
    final identityKey = base64Encode(List<int>.filled(32, 23));
    final oldSigningKey = base64Encode(List<int>.filled(32, 31));
    final newSigningKey = base64Encode(List<int>.filled(32, 71));
    await store.saveSessionBootstrapMeta(
      'peer-1',
      protocolFloor: 'v2_libsignal',
      signedPrekeyId: 4,
      oneTimePrekeyId: 8,
      v2Only: true,
      identitySigningPubkeyB64: oldSigningKey,
      baseUrlOverride: 'http://127.0.0.1:8080',
    );

    final mock = MockClient((req) async {
      if (req.url.path == '/chat/keys/bundle/peer-1') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'device_id': 'peer-1',
            'identity_key_b64': identityKey,
            'identity_signing_pubkey_b64': newSigningKey,
            'signed_prekey_id': 9,
            'signed_prekey_b64': base64Encode(List<int>.filled(32, 51)),
            'signed_prekey_sig_b64': base64Encode(List<int>.filled(64, 12)),
            'one_time_prekey_id': 10,
            'one_time_prekey_b64': base64Encode(List<int>.filled(32, 52)),
            'protocol_floor': 'v2_libsignal',
            'supports_v2': true,
            'v2_only': true,
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });
    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    final bootstrapper = ChatOutboundRatchetBootstrapper(
      service: svc,
      store: store,
    );

    await expectLater(
      () => bootstrapper.nextOutboundSendContext(
        me: ChatIdentity(
          id: 'me-1',
          publicKeyB64: base64Encode(List<int>.filled(32, 11)),
          privateKeyB64: base64Encode(List<int>.filled(32, 19)),
          fingerprint: 'fp-me-1',
        ),
        peer: ChatContact(
          id: 'peer-1',
          publicKeyB64: identityKey,
          fingerprint: fingerprintForKey(identityKey),
          verified: true,
        ),
      ),
      throwsA(
        isA<ChatSigningKeyPinViolation>().having(
          (e) => e.reason,
          'reason',
          contains('changed'),
        ),
      ),
    );
  });

  test('registerDevice rethrows critical libsignal bootstrap auth failures',
      () async {
    final me = ChatIdentity(
      id: 'me-1',
      publicKeyB64: curveKeyB64(17),
      privateKeyB64: curveKeyB64(71),
      fingerprint: 'fp-me-1',
    );
    final mock = MockClient((req) async {
      if (req.url.path == '/chat/devices/register') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'device_id': me.id,
            'public_key_b64': me.publicKeyB64,
            'auth_token': 'device-token',
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (req.url.path == '/chat/keys/register') {
        return http.Response('{"detail":"auth session required"}', 401);
      }
      return http.Response('{}', 404);
    });
    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);

    await expectLater(
      () => svc.registerDevice(me),
      throwsA(
        isA<ChatHttpException>()
            .having((e) => e.op, 'op', 'keysRegister')
            .having((e) => e.statusCode, 'statusCode', 401),
      ),
    );

    expect(await ChatLocalStore().isDeviceKeyBootstrapped(me.id), isFalse);
  });

  test('registerDevice rethrows invalid libsignal bootstrap contract failures',
      () async {
    final me = ChatIdentity(
      id: 'me-3',
      publicKeyB64: curveKeyB64(29),
      privateKeyB64: curveKeyB64(83),
      fingerprint: 'fp-me-3',
    );
    final mock = MockClient((req) async {
      if (req.url.path == '/chat/devices/register') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'device_id': me.id,
            'public_key_b64': me.publicKeyB64,
            'auth_token': 'device-token',
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (req.url.path == '/chat/keys/register') {
        return http.Response(
          '{"detail":"invalid signed_prekey signature"}',
          400,
        );
      }
      return http.Response('{}', 404);
    });
    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);

    await expectLater(
      () => svc.registerDevice(me),
      throwsA(
        isA<ChatHttpException>()
            .having((e) => e.op, 'op', 'keysRegister')
            .having((e) => e.statusCode, 'statusCode', 400),
      ),
    );

    expect(await ChatLocalStore().isDeviceKeyBootstrapped(me.id), isFalse);
  });

  test('registerDevice still tolerates missing libsignal key api', () async {
    final me = ChatIdentity(
      id: 'me-4',
      publicKeyB64: curveKeyB64(23),
      privateKeyB64: curveKeyB64(79),
      fingerprint: 'fp-me-4',
    );
    final mock = MockClient((req) async {
      if (req.url.path == '/chat/devices/register') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'device_id': me.id,
            'public_key_b64': me.publicKeyB64,
            'auth_token': 'device-token',
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (req.url.path == '/chat/keys/register') {
        return http.Response('{}', 404);
      }
      return http.Response('{}', 404);
    });
    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);

    final registered = await svc.registerDevice(me);

    expect(registered.id, me.id);
    expect(
      await ChatLocalStore().isDeviceKeyBootstrapped(
        me.id,
        baseUrlOverride: 'http://127.0.0.1:8080',
      ),
      isTrue,
    );
  });

  test('registerDevice uses base-scoped stable client device id', () async {
    const storedOrigin = 'https://api.one.example';
    const activeOrigin = 'http://127.0.0.1:8080';
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', storedOrigin);
    expect(
      await saveStableDeviceId(
        'device-stored',
        sp: sp,
        baseUrlOverride: storedOrigin,
      ),
      isTrue,
    );
    expect(
      await saveStableDeviceId(
        'device-active',
        sp: sp,
        baseUrlOverride: activeOrigin,
      ),
      isTrue,
    );

    final me = ChatIdentity(
      id: 'me-scoped',
      publicKeyB64: curveKeyB64(41),
      privateKeyB64: curveKeyB64(97),
      fingerprint: 'fp-me-scoped',
    );
    final mock = MockClient((req) async {
      if (req.url.path == '/chat/devices/register') {
        final body = jsonDecode(req.body) as Map<String, Object?>;
        expect(req.headers['x-shamell-client-ip'], '127.0.0.1');
        expect(body['client_device_id'], 'device-active');
        return http.Response(
          jsonEncode(<String, Object?>{
            'device_id': me.id,
            'public_key_b64': me.publicKeyB64,
            'auth_token': 'device-token',
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (req.url.path == '/chat/keys/register') {
        return http.Response('{}', 404);
      }
      return http.Response('{}', 404);
    });

    final svc = ChatService(activeOrigin, httpClient: mock);
    final registered = await svc.registerDevice(me);

    expect(registered.id, me.id);
  });

  test(
      'ensureAccountChatReady rotates chat identity on device-id conflict without forcing account bootstrap',
      () async {
    const baseUrl = 'http://127.0.0.1:8080';
    await setSessionTokenForBaseUrl(
      baseUrl,
      '0123456789abcdef0123456789abcdef',
    );

    final registerDeviceIds = <String>[];
    var accountBootstrapCalls = 0;
    final mock = MockClient((req) async {
      if (req.url.path == '/chat/devices/register') {
        final body = jsonDecode(req.body) as Map<String, Object?>;
        final did = (body['device_id'] ?? '').toString();
        registerDeviceIds.add(did);
        if (registerDeviceIds.length == 1) {
          return http.Response(
            '{"detail":"device_id already in use"}',
            403,
            headers: const {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode(<String, Object?>{
            'device_id': did,
            'public_key_b64': (body['public_key_b64'] ?? '').toString(),
            'auth_token': 'device-token',
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (req.url.path == '/chat/keys/register') {
        return http.Response('{}', 404);
      }
      if (req.url.path == '/auth/account/create/challenge' ||
          req.url.path == '/auth/account/create') {
        accountBootstrapCalls += 1;
        return http.Response('{}', 200);
      }
      return http.Response('{}', 404);
    });
    final svc = ChatService(baseUrl, httpClient: mock);

    await svc.ensureAccountChatReady();

    expect(registerDeviceIds, hasLength(2));
    expect(registerDeviceIds.first, isNot(registerDeviceIds.last));
    expect(accountBootstrapCalls, 0);
    final me = await ChatLocalStore().loadIdentity(baseUrlOverride: baseUrl);
    expect(me, isNotNull);
    expect(me!.id, registerDeviceIds.last);
    expect(
      await ChatLocalStore().loadDeviceAuthToken(
        me.id,
        baseUrlOverride: baseUrl,
      ),
      'device-token',
    );
  });

  test(
      'ensureAccountChatReady fails closed when account bootstrap resets during register auth recovery',
      () async {
    const baseUrl = 'http://127.0.0.1:8080';
    await setSessionTokenForBaseUrl(
        baseUrl, '0123456789abcdef0123456789abcdef');

    var registerCalls = 0;
    final mock = MockClient((req) async {
      if (req.url.path == '/chat/devices/register') {
        registerCalls += 1;
        return http.Response('{"detail":"auth session required"}', 401);
      }
      if (req.url.path == '/auth/account/create/challenge') {
        return http.Response('', 404);
      }
      if (req.url.path == '/auth/account/create') {
        return http.Response('{"detail":"auth session required"}', 401);
      }
      return http.Response('{}', 404);
    });
    final svc = ChatService(baseUrl, httpClient: mock);

    await expectLater(
      () => svc.ensureAccountChatReady(),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('auth session required'),
        ),
      ),
    );

    expect(registerCalls, 1);
    expect(await getSessionCookieHeader(baseUrl), isNull);
  });

  test(
      'ensureAccountChatReady clears session instead of legacy account bootstrap on register auth failure',
      () async {
    const baseUrl = 'http://127.0.0.1:8080';
    await setSessionTokenForBaseUrl(
        baseUrl, '0123456789abcdef0123456789abcdef');

    var registerCalls = 0;
    final mock = MockClient((req) async {
      if (req.url.path == '/chat/devices/register') {
        registerCalls += 1;
        return http.Response('{"detail":"auth session required"}', 401);
      }
      if (req.url.path == '/auth/account/create/challenge') {
        return http.Response('', 404);
      }
      if (req.url.path == '/auth/account/create') {
        return http.Response('{"detail":"attestation required"}', 401);
      }
      return http.Response('{}', 404);
    });
    final svc = ChatService(baseUrl, httpClient: mock);

    await expectLater(
      () => svc.ensureAccountChatReady(),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('auth session required'),
        ),
      ),
    );

    expect(registerCalls, 1);
    expect(await getSessionCookieHeader(baseUrl), isNull);
  });

  test(
      'ensureAccountChatReady retries key bootstrap when a stored chat token exists but prekeys upload previously failed',
      () async {
    const baseUrl = 'http://127.0.0.1:8080';
    await setSessionTokenForBaseUrl(
      baseUrl,
      '0123456789abcdef0123456789abcdef',
    );

    var registerCalls = 0;
    var keyRegisterCalls = 0;
    var prekeysUploadCalls = 0;
    final mock = MockClient((req) async {
      if (req.url.path == '/chat/devices/register') {
        registerCalls += 1;
        final body = jsonDecode(req.body) as Map<String, Object?>;
        final did = (body['device_id'] ?? '').toString();
        final pk = (body['public_key_b64'] ?? '').toString();
        return http.Response(
          jsonEncode(<String, Object?>{
            'device_id': did,
            'public_key_b64': pk,
            'auth_token': 'device-token',
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (req.url.path == '/chat/keys/register') {
        keyRegisterCalls += 1;
        return http.Response('{}', 200);
      }
      if (req.url.path == '/chat/keys/prekeys/upload') {
        prekeysUploadCalls += 1;
        if (prekeysUploadCalls == 1) {
          return http.Response(
            '{"detail":"temporary upstream failure"}',
            503,
            headers: const {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 200);
      }
      return http.Response('{}', 404);
    });
    final svc = ChatService(baseUrl, httpClient: mock);

    await expectLater(
      () => svc.ensureAccountChatReady(),
      throwsA(
        isA<ChatHttpException>()
            .having((e) => e.op, 'op', 'prekeysUpload')
            .having((e) => e.statusCode, 'statusCode', 503),
      ),
    );

    final store = ChatLocalStore();
    final me = await store.loadIdentity(baseUrlOverride: baseUrl);
    expect(me, isNotNull);
    expect(
      await store.loadDeviceAuthToken(
        me!.id,
        baseUrlOverride: baseUrl,
      ),
      'device-token',
    );
    expect(
      await store.isDeviceKeyBootstrapped(
        me.id,
        baseUrlOverride: baseUrl,
      ),
      isFalse,
    );

    await svc.ensureAccountChatReady();

    expect(registerCalls, 1);
    expect(keyRegisterCalls, 2);
    expect(prekeysUploadCalls, 2);
    expect(
      await store.isDeviceKeyBootstrapped(
        me.id,
        baseUrlOverride: baseUrl,
      ),
      isTrue,
    );
  });

  test(
      'ensureAccountChatReady falls back to full device registration when stored chat auth drifts',
      () async {
    const baseUrl = 'http://127.0.0.1:8080';
    await setSessionTokenForBaseUrl(
      baseUrl,
      '0123456789abcdef0123456789abcdef',
    );

    final store = ChatLocalStore();
    final me = ChatIdentity(
      id: 'dev-drifted',
      publicKeyB64: curveKeyB64(37),
      privateKeyB64: curveKeyB64(73),
      fingerprint: 'fp-drifted',
    );
    await store.saveIdentity(me, baseUrlOverride: baseUrl);
    await store.saveDeviceAuthToken(
      me.id,
      'stale-token',
      baseUrlOverride: baseUrl,
    );

    var registerCalls = 0;
    var keyRegisterCalls = 0;
    final mock = MockClient((req) async {
      if (req.url.path == '/chat/devices/register') {
        registerCalls += 1;
        final body = jsonDecode(req.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode(<String, Object?>{
            'device_id': (body['device_id'] ?? '').toString(),
            'public_key_b64': (body['public_key_b64'] ?? '').toString(),
            'auth_token': 'fresh-token',
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (req.url.path == '/chat/keys/register') {
        keyRegisterCalls += 1;
        if (keyRegisterCalls == 1) {
          return http.Response(
            '{"detail":"unknown chat device auth"}',
            401,
            headers: const {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      }
      return http.Response('{}', 404);
    });
    final svc = ChatService(baseUrl, httpClient: mock);

    await svc.ensureAccountChatReady();

    expect(registerCalls, 1);
    expect(keyRegisterCalls, 2);
    expect(
      await store.loadDeviceAuthToken(
        me.id,
        baseUrlOverride: baseUrl,
      ),
      'fresh-token',
    );
    expect(
      await store.isDeviceKeyBootstrapped(
        me.id,
        baseUrlOverride: baseUrl,
      ),
      isTrue,
    );
  });

  test(
      'ensureAccountChatReady rotates local identity when stored chat registration belongs to a different SyrChat account',
      () async {
    const baseUrl = 'http://127.0.0.1:8080';
    await setSessionTokenForBaseUrl(
      baseUrl,
      '0123456789abcdef0123456789abcdef',
    );
    await saveStoredShamellUserId(
      '6ZYYRUUB',
      baseUrlOverride: baseUrl,
    );

    final store = ChatLocalStore();
    final staleIdentity = ChatIdentity(
      id: 'dev-mismatched',
      publicKeyB64: curveKeyB64(43),
      privateKeyB64: curveKeyB64(83),
      fingerprint: 'fp-mismatched',
    );
    await store.saveIdentity(staleIdentity, baseUrlOverride: baseUrl);
    await store.saveDeviceAuthToken(
      staleIdentity.id,
      'stale-token',
      baseUrlOverride: baseUrl,
    );
    await store.markDeviceKeyBootstrapped(
      staleIdentity.id,
      baseUrlOverride: baseUrl,
    );
    await store.saveRegisteredAccountShamellUserId(
      staleIdentity.id,
      'J8J4LYW7',
      baseUrlOverride: baseUrl,
    );

    var registerCalls = 0;
    final registeredDeviceIds = <String>[];
    final mock = MockClient((req) async {
      if (req.url.path == '/chat/devices/register') {
        registerCalls += 1;
        final body = jsonDecode(req.body) as Map<String, Object?>;
        final deviceId = (body['device_id'] ?? '').toString();
        registeredDeviceIds.add(deviceId);
        return http.Response(
          jsonEncode(<String, Object?>{
            'device_id': deviceId,
            'public_key_b64': (body['public_key_b64'] ?? '').toString(),
            'auth_token': 'fresh-token',
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (req.url.path == '/chat/keys/register') {
        return http.Response('{}', 404);
      }
      return http.Response('{}', 404);
    });
    final svc = ChatService(baseUrl, httpClient: mock);

    await svc.ensureAccountChatReady();

    expect(registerCalls, 1);
    expect(registeredDeviceIds.single, isNot(staleIdentity.id));

    final rotatedIdentity = await store.loadIdentity(baseUrlOverride: baseUrl);
    expect(rotatedIdentity, isNotNull);
    expect(rotatedIdentity!.id, registeredDeviceIds.single);
    expect(
      await store.loadRegisteredAccountShamellUserId(
        rotatedIdentity.id,
        baseUrlOverride: baseUrl,
      ),
      '6ZYYRUUB',
    );
    expect(
      await store.loadDeviceAuthToken(
        rotatedIdentity.id,
        baseUrlOverride: baseUrl,
      ),
      'fresh-token',
    );
  });

  test(
      'ensureAccountChatReady does not recreate account sessions during register auth recovery',
      () async {
    const baseUrl = 'http://127.0.0.1:8080';
    await setSessionTokenForBaseUrl(
      baseUrl,
      '0123456789abcdef0123456789abcdef',
    );

    final store = ChatLocalStore();
    final staleIdentity = ChatIdentity(
      id: 'dev-stale',
      publicKeyB64: curveKeyB64(41),
      privateKeyB64: curveKeyB64(79),
      fingerprint: 'fp-stale',
    );
    await store.saveIdentity(staleIdentity, baseUrlOverride: baseUrl);

    var registerCalls = 0;
    final registeredDeviceIds = <String>[];
    final mock = MockClient((req) async {
      if (req.url.path == '/chat/devices/register') {
        registerCalls += 1;
        final body = jsonDecode(req.body) as Map<String, Object?>;
        final deviceId = (body['device_id'] ?? '').toString();
        registeredDeviceIds.add(deviceId);
        if (registerCalls == 1) {
          return http.Response(
            '{"detail":"chat device ownership mismatch"}',
            403,
            headers: const {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode(<String, Object?>{
            'device_id': deviceId,
            'public_key_b64': (body['public_key_b64'] ?? '').toString(),
            'auth_token': 'fresh-token',
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (req.url.path == '/auth/account/create/challenge') {
        return http.Response(
          '{"enabled":false}',
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (req.url.path == '/auth/account/create') {
        return http.Response(
          '{"shamell_id":"QW8RTY6P"}',
          200,
          headers: const {
            'content-type': 'application/json',
            'set-cookie':
                '__host-sa_session=abcdef0123456789abcdef0123456789; Path=/; HttpOnly',
          },
        );
      }
      if (req.url.path == '/chat/keys/bootstrap') {
        return http.Response('{}', 404);
      }
      if (req.url.path == '/chat/keys/register') {
        return http.Response('{}', 200);
      }
      if (req.url.path == '/chat/keys/prekeys/upload') {
        return http.Response('{}', 200);
      }
      return http.Response('{}', 404);
    });
    final svc = ChatService(baseUrl, httpClient: mock);

    await expectLater(
      () => svc.ensureAccountChatReady(),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('auth session required'),
        ),
      ),
    );

    expect(registerCalls, 1);
    expect(registeredDeviceIds.single, staleIdentity.id);

    final persistedIdentity =
        await store.loadIdentity(baseUrlOverride: baseUrl);
    expect(persistedIdentity, isNotNull);
    expect(persistedIdentity!.id, staleIdentity.id);
    expect(await getSessionCookieHeader(baseUrl), isNull);
  });

  test(
      'ensureAccountChatReady prefers atomic key bootstrap when endpoint is available',
      () async {
    const baseUrl = 'http://127.0.0.1:8080';
    await setSessionTokenForBaseUrl(
      baseUrl,
      '0123456789abcdef0123456789abcdef',
    );

    var registerCalls = 0;
    var bootstrapCalls = 0;
    var keyRegisterCalls = 0;
    var prekeysUploadCalls = 0;
    final mock = MockClient((req) async {
      if (req.url.path == '/chat/devices/register') {
        registerCalls += 1;
        final body = jsonDecode(req.body) as Map<String, Object?>;
        final did = (body['device_id'] ?? '').toString();
        final pk = (body['public_key_b64'] ?? '').toString();
        return http.Response(
          jsonEncode(<String, Object?>{
            'device_id': did,
            'public_key_b64': pk,
            'auth_token': 'device-token',
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (req.url.path == '/chat/keys/bootstrap') {
        bootstrapCalls += 1;
        final body = jsonDecode(req.body) as Map<String, Object?>;
        expect((body['device_id'] ?? '').toString(), isNotEmpty);
        expect(body['prekeys'], isA<List<Object?>>());
        return http.Response('{}', 200);
      }
      if (req.url.path == '/chat/keys/register') {
        keyRegisterCalls += 1;
        return http.Response('{}', 200);
      }
      if (req.url.path == '/chat/keys/prekeys/upload') {
        prekeysUploadCalls += 1;
        return http.Response('{}', 200);
      }
      return http.Response('{}', 404);
    });
    final svc = ChatService(baseUrl, httpClient: mock);

    await svc.ensureAccountChatReady();

    final store = ChatLocalStore();
    final me = await store.loadIdentity(baseUrlOverride: baseUrl);
    expect(me, isNotNull);
    expect(registerCalls, 1);
    expect(bootstrapCalls, 1);
    expect(keyRegisterCalls, 0);
    expect(prekeysUploadCalls, 0);
    expect(
      await store.isDeviceKeyBootstrapped(
        me!.id,
        baseUrlOverride: baseUrl,
      ),
      isTrue,
    );
  });

  test(
      'ensureAccountChatReady refills low one-time prekey inventory once and throttles repeat checks',
      () async {
    const baseUrl = 'http://127.0.0.1:8080';
    await setSessionTokenForBaseUrl(
      baseUrl,
      '0123456789abcdef0123456789abcdef',
    );

    final store = ChatLocalStore();
    final me = ChatIdentity(
      id: 'dev-prekeys',
      publicKeyB64: curveKeyB64(37),
      privateKeyB64: curveKeyB64(73),
      fingerprint: 'fp-prekeys',
    );
    await store.saveIdentity(me, baseUrlOverride: baseUrl);
    await store.saveDeviceAuthToken(
      me.id,
      'device-token',
      baseUrlOverride: baseUrl,
    );
    await store.markDeviceKeyBootstrapped(
      me.id,
      baseUrlOverride: baseUrl,
    );

    var statusCalls = 0;
    var prekeysUploadCalls = 0;
    var registerCalls = 0;
    final mock = MockClient((req) async {
      if (req.url.path == '/chat/devices/register') {
        registerCalls += 1;
        return http.Response('{}', 200);
      }
      if (req.url.path == '/chat/keys/prekeys/status/${me.id}') {
        statusCalls += 1;
        return http.Response(
          jsonEncode(<String, Object?>{
            'device_id': me.id,
            'available_prekeys': 4,
            'recommended_upload': 60,
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (req.url.path == '/chat/keys/prekeys/upload') {
        prekeysUploadCalls += 1;
        final body = jsonDecode(req.body) as Map<String, Object?>;
        expect((body['device_id'] ?? '').toString(), me.id);
        expect((body['prekeys'] as List<Object?>).length, 60);
        return http.Response('{}', 200);
      }
      return http.Response('{}', 404);
    });
    final svc = ChatService(baseUrl, httpClient: mock);

    await svc.ensureAccountChatReady();
    await svc.ensureAccountChatReady();

    expect(registerCalls, 0);
    expect(statusCalls, 1);
    expect(prekeysUploadCalls, 1);
  });

  test(
      'ensureAccountChatReady re-registers device when prekey status reports auth drift',
      () async {
    const baseUrl = 'http://127.0.0.1:8080';
    await setSessionTokenForBaseUrl(
      baseUrl,
      '0123456789abcdef0123456789abcdef',
    );

    final store = ChatLocalStore();
    final me = ChatIdentity(
      id: 'dev-prekeys-drift',
      publicKeyB64: curveKeyB64(43),
      privateKeyB64: curveKeyB64(83),
      fingerprint: 'fp-prekeys-drift',
    );
    await store.saveIdentity(me, baseUrlOverride: baseUrl);
    await store.saveDeviceAuthToken(
      me.id,
      'stale-token',
      baseUrlOverride: baseUrl,
    );
    await store.markDeviceKeyBootstrapped(
      me.id,
      baseUrlOverride: baseUrl,
    );

    var statusCalls = 0;
    var registerCalls = 0;
    var keyRegisterCalls = 0;
    final mock = MockClient((req) async {
      if (req.url.path == '/chat/keys/prekeys/status/${me.id}') {
        statusCalls += 1;
        return http.Response(
          '{"detail":"unknown chat device auth"}',
          401,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (req.url.path == '/chat/devices/register') {
        registerCalls += 1;
        final body = jsonDecode(req.body) as Map<String, Object?>;
        expect((body['device_id'] ?? '').toString(), me.id);
        return http.Response(
          jsonEncode(<String, Object?>{
            'device_id': me.id,
            'public_key_b64': me.publicKeyB64,
            'auth_token': 'fresh-token',
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (req.url.path == '/chat/keys/register') {
        keyRegisterCalls += 1;
        return http.Response('{}', 404);
      }
      return http.Response('{}', 404);
    });
    final svc = ChatService(baseUrl, httpClient: mock);

    await svc.ensureAccountChatReady();

    expect(statusCalls, 1);
    expect(registerCalls, 1);
    expect(keyRegisterCalls, 1);
    expect(
      await store.loadDeviceAuthToken(
        me.id,
        baseUrlOverride: baseUrl,
      ),
      'fresh-token',
    );
    expect(
      await store.isDeviceKeyBootstrapped(
        me.id,
        baseUrlOverride: baseUrl,
      ),
      isTrue,
    );
  });

  test(
      'ensureAccountChatReady ignores missing prekey status endpoint on older servers',
      () async {
    const baseUrl = 'http://127.0.0.1:8080';
    await setSessionTokenForBaseUrl(
      baseUrl,
      '0123456789abcdef0123456789abcdef',
    );

    final store = ChatLocalStore();
    final me = ChatIdentity(
      id: 'dev-prekeys-legacy',
      publicKeyB64: curveKeyB64(41),
      privateKeyB64: curveKeyB64(79),
      fingerprint: 'fp-prekeys-legacy',
    );
    await store.saveIdentity(me, baseUrlOverride: baseUrl);
    await store.saveDeviceAuthToken(
      me.id,
      'device-token',
      baseUrlOverride: baseUrl,
    );
    await store.markDeviceKeyBootstrapped(
      me.id,
      baseUrlOverride: baseUrl,
    );

    var statusCalls = 0;
    var registerCalls = 0;
    var prekeysUploadCalls = 0;
    final mock = MockClient((req) async {
      if (req.url.path == '/chat/devices/register') {
        registerCalls += 1;
        return http.Response('{}', 200);
      }
      if (req.url.path == '/chat/keys/prekeys/status/${me.id}') {
        statusCalls += 1;
        return http.Response('{}', 404);
      }
      if (req.url.path == '/chat/keys/prekeys/upload') {
        prekeysUploadCalls += 1;
        return http.Response('{}', 200);
      }
      return http.Response('{}', 404);
    });
    final svc = ChatService(baseUrl, httpClient: mock);

    await svc.ensureAccountChatReady();

    expect(statusCalls, 1);
    expect(registerCalls, 0);
    expect(prekeysUploadCalls, 0);
  });

  test(
      'createContactInviteTokenEnsured fails closed when account bootstrap resets during invite auth recovery',
      () async {
    const baseUrl = 'http://127.0.0.1:8080';
    await setSessionTokenForBaseUrl(
        baseUrl, 'fedcba9876543210fedcba9876543210');

    var inviteCalls = 0;
    final mock = MockClient((req) async {
      if (req.url.path == '/chat/devices/register') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'device_id': 'me-1',
            'public_key_b64': curveKeyB64(31),
            'auth_token': 'device-token',
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (req.url.path == '/chat/keys/register') {
        return http.Response('{}', 404);
      }
      if (req.url.path == '/contacts/invites') {
        inviteCalls += 1;
        return http.Response('{"detail":"auth session required"}', 401);
      }
      if (req.url.path == '/auth/account/create/challenge') {
        return http.Response('', 404);
      }
      if (req.url.path == '/auth/account/create') {
        return http.Response('{"detail":"auth session required"}', 401);
      }
      return http.Response('{}', 404);
    });
    final svc = ChatService(baseUrl, httpClient: mock);

    await expectLater(
      () => svc.createContactInviteTokenEnsured(maxUses: 1),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('auth session required'),
        ),
      ),
    );

    expect(inviteCalls, 1);
    expect(await getSessionCookieHeader(baseUrl), isNull);
  });

  test(
      'createContactInviteTokenEnsured does not force account bootstrap on repeated ownership 403',
      () async {
    const baseUrl = 'http://127.0.0.1:8080';
    await setSessionTokenForBaseUrl(
      baseUrl,
      'fedcba9876543210fedcba9876543210',
    );

    var registerCalls = 0;
    var inviteCalls = 0;
    var accountBootstrapCalls = 0;
    final mock = MockClient((req) async {
      if (req.url.path == '/chat/devices/register') {
        registerCalls += 1;
        return http.Response(
          jsonEncode(<String, Object?>{
            'device_id': 'me-1',
            'public_key_b64': curveKeyB64(33 + registerCalls),
            'auth_token': 'device-token-$registerCalls',
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (req.url.path == '/chat/keys/register') {
        return http.Response('{}', 404);
      }
      if (req.url.path == '/contacts/invites') {
        inviteCalls += 1;
        return http.Response(
          '{"detail":"device not registered for authenticated user"}',
          403,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (req.url.path == '/auth/account/create/challenge' ||
          req.url.path == '/auth/account/create') {
        accountBootstrapCalls += 1;
        return http.Response('{}', 200);
      }
      return http.Response('{}', 404);
    });
    final svc = ChatService(baseUrl, httpClient: mock);

    await expectLater(
      () => svc.createContactInviteTokenEnsured(maxUses: 1),
      throwsA(
        isA<ChatHttpException>()
            .having((e) => e.op, 'op', 'createInvite')
            .having((e) => e.statusCode, 'statusCode', 403)
            .having(
              (e) => e.body,
              'body',
              contains('device not registered for authenticated user'),
            ),
      ),
    );

    expect(inviteCalls, 2);
    expect(registerCalls, 2);
    expect(accountBootstrapCalls, 0);
    expect(
      await getSessionCookieHeader(baseUrl),
      '__Host-sa_session=fedcba9876543210fedcba9876543210',
    );
  });

  test(
      'createContactInviteTokenEnsured clears session instead of legacy account bootstrap on invite auth failure',
      () async {
    const baseUrl = 'http://127.0.0.1:8080';
    await setSessionTokenForBaseUrl(
        baseUrl, 'fedcba9876543210fedcba9876543210');

    var inviteCalls = 0;
    final mock = MockClient((req) async {
      if (req.url.path == '/chat/devices/register') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'device_id': 'me-1',
            'public_key_b64': curveKeyB64(35),
            'auth_token': 'device-token',
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (req.url.path == '/chat/keys/register') {
        return http.Response('{}', 404);
      }
      if (req.url.path == '/contacts/invites') {
        inviteCalls += 1;
        return http.Response('{"detail":"auth session required"}', 401);
      }
      if (req.url.path == '/auth/account/create/challenge') {
        return http.Response('', 404);
      }
      if (req.url.path == '/auth/account/create') {
        return http.Response('{"detail":"attestation required"}', 401);
      }
      return http.Response('{}', 404);
    });
    final svc = ChatService(baseUrl, httpClient: mock);

    await expectLater(
      () => svc.createContactInviteTokenEnsured(maxUses: 1),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('auth session required'),
        ),
      ),
    );

    expect(inviteCalls, 1);
    expect(await getSessionCookieHeader(baseUrl), isNull);
  });

  test(
      'createContactInviteTokenEnsured clears critical 403 auth session failures without legacy bootstrap',
      () async {
    const baseUrl = 'http://127.0.0.1:8080';
    await setSessionTokenForBaseUrl(
      baseUrl,
      'fedcba9876543210fedcba9876543210',
    );

    var inviteCalls = 0;
    final mock = MockClient((req) async {
      if (req.url.path == '/chat/devices/register') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'device_id': 'me-1',
            'public_key_b64': curveKeyB64(39),
            'auth_token': 'device-token',
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (req.url.path == '/chat/keys/register') {
        return http.Response('{}', 404);
      }
      if (req.url.path == '/contacts/invites') {
        inviteCalls += 1;
        return http.Response(
          '{"detail":"auth session required"}',
          403,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });
    final svc = ChatService(baseUrl, httpClient: mock);

    await expectLater(
      () => svc.createContactInviteTokenEnsured(maxUses: 1),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('auth session required'),
        ),
      ),
    );

    expect(inviteCalls, 1);
    expect(await getSessionCookieHeader(baseUrl), isNull);
  });

  test(
      'redeemContactInviteTokenEnsured fails closed when account bootstrap resets during redeem auth recovery',
      () async {
    const baseUrl = 'http://127.0.0.1:8080';
    await setSessionTokenForBaseUrl(
        baseUrl, '00112233445566778899aabbccddeeff');

    var redeemCalls = 0;
    final mock = MockClient((req) async {
      if (req.url.path == '/chat/devices/register') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'device_id': 'me-1',
            'public_key_b64': curveKeyB64(37),
            'auth_token': 'device-token',
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (req.url.path == '/chat/keys/register') {
        return http.Response('{}', 404);
      }
      if (req.url.path == '/contacts/invites/redeem') {
        redeemCalls += 1;
        return http.Response('{"detail":"auth session required"}', 401);
      }
      if (req.url.path == '/auth/account/create/challenge') {
        return http.Response('', 404);
      }
      if (req.url.path == '/auth/account/create') {
        return http.Response('{"detail":"auth session required"}', 401);
      }
      return http.Response('{}', 404);
    });
    final svc = ChatService(baseUrl, httpClient: mock);

    await expectLater(
      () => svc.redeemContactInviteTokenEnsured(
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('auth session required'),
        ),
      ),
    );

    expect(redeemCalls, 1);
    expect(await getSessionCookieHeader(baseUrl), isNull);
  });

  test(
      'redeemContactInviteTokenEnsured rejects malformed token before bootstrap/network',
      () async {
    const baseUrl = 'http://127.0.0.1:8080';
    var calls = 0;
    final mock = MockClient((req) async {
      calls += 1;
      return http.Response('{}', 500);
    });
    final svc = ChatService(baseUrl, httpClient: mock);

    await expectLater(
      () => svc.redeemContactInviteTokenEnsured('not-a-valid-token'),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('invalid invite token'),
        ),
      ),
    );

    expect(calls, 0);
  });

  test('ensureAccountChatReady clears session when register is unauthorized',
      () async {
    const baseUrl = 'http://127.0.0.1:8080';
    await setSessionTokenForBaseUrl(
        baseUrl, '0123456789abcdef0123456789abcdef');

    var registerCalls = 0;
    final mock = MockClient((req) async {
      if (req.url.path == '/chat/devices/register') {
        registerCalls += 1;
        return http.Response('{"detail":"auth session required"}', 401);
      }
      if (req.url.path == '/auth/account/create/challenge') {
        return http.Response('', 404);
      }
      if (req.url.path == '/auth/account/create') {
        return http.Response(
          '{"ok":true}',
          200,
          headers: const <String, String>{
            'content-type': 'application/json',
            'set-cookie':
                '__Host-sa_session=ffffffffffffffffffffffffffffffff; Path=/; HttpOnly; Secure; SameSite=Lax',
          },
        );
      }
      return http.Response('{}', 404);
    });
    final svc = ChatService(baseUrl, httpClient: mock);

    await expectLater(
      () => svc.ensureAccountChatReady(),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('auth session required'),
        ),
      ),
    );

    expect(registerCalls, 1);
    expect(await getSessionCookieHeader(baseUrl), isNull);
  });

  test(
      'createContactInviteTokenEnsured clears session when invite is unauthorized',
      () async {
    const baseUrl = 'http://127.0.0.1:8080';
    await setSessionTokenForBaseUrl(
        baseUrl, 'fedcba9876543210fedcba9876543210');

    var inviteCalls = 0;
    final mock = MockClient((req) async {
      if (req.url.path == '/chat/devices/register') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'device_id': 'me-1',
            'public_key_b64': curveKeyB64(41),
            'auth_token': 'device-token',
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (req.url.path == '/chat/keys/register') {
        return http.Response('{}', 404);
      }
      if (req.url.path == '/contacts/invites') {
        inviteCalls += 1;
        return http.Response('{"detail":"auth session required"}', 401);
      }
      if (req.url.path == '/auth/account/create/challenge') {
        return http.Response('', 404);
      }
      if (req.url.path == '/auth/account/create') {
        return http.Response(
          '{"ok":true}',
          200,
          headers: const <String, String>{
            'content-type': 'application/json',
            'set-cookie':
                '__Host-sa_session=ffffffffffffffffffffffffffffffff; Path=/; HttpOnly; Secure; SameSite=Lax',
          },
        );
      }
      return http.Response('{}', 404);
    });
    final svc = ChatService(baseUrl, httpClient: mock);

    await expectLater(
      () => svc.createContactInviteTokenEnsured(maxUses: 1),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('auth session required'),
        ),
      ),
    );

    expect(inviteCalls, 1);
    expect(await getSessionCookieHeader(baseUrl), isNull);
  });

  test('peer key bundle guard accepts only strict v2-only bundles', () {
    const ok = ChatKeyBundle(
      deviceId: 'peer-1',
      identityKeyB64: 'AAAA',
      identitySigningPubkeyB64: 'BBBB',
      signedPrekeyId: 1,
      signedPrekeyB64: 'CCCC',
      signedPrekeySigB64: 'DDDD',
      protocolFloor: 'v2_libsignal',
      supportsV2: true,
      v2Only: true,
    );
    expect(shamellAcceptPeerKeyBundle(ok), isTrue);

    const legacy = ChatKeyBundle(
      deviceId: 'peer-1',
      identityKeyB64: 'AAAA',
      identitySigningPubkeyB64: 'BBBB',
      signedPrekeyId: 1,
      signedPrekeyB64: 'CCCC',
      signedPrekeySigB64: 'DDDD',
      protocolFloor: 'v1_legacy',
      supportsV2: false,
      v2Only: false,
    );
    expect(shamellAcceptPeerKeyBundle(legacy), isFalse);
  });

  test('fetchKeyBundle rejects insecure peer bundles', () async {
    final mock = MockClient((req) async {
      if (req.url.path == '/chat/keys/bundle/peer-1') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'device_id': 'peer-1',
            'identity_key_b64': 'AAAA',
            'identity_signing_pubkey_b64': 'BBBB',
            'signed_prekey_id': 10,
            'signed_prekey_b64': 'CCCC',
            'signed_prekey_sig_b64': 'DDDD',
            'protocol_floor': 'v1_legacy',
            'supports_v2': false,
            'v2_only': false,
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });
    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    await expectLater(
      () => svc.fetchKeyBundle(targetDeviceId: 'peer-1'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('insecure key bundle'),
        ),
      ),
    );
  });

  test('remote inbox JSON cannot enable trusted local plaintext mode', () {
    final m = ChatMessage.fromJson(<String, Object?>{
      'id': 'm-1',
      'sender_id': 'peer-1',
      'recipient_id': 'me-1',
      'sender_pubkey_b64': 'AAAA',
      'nonce_b64': 'AQ==',
      'box_b64': 'Ag==',
      'protocol_version': 'v2_libsignal',
      'sealed_sender': true,
      'trustedLocalPlaintext': true,
    });
    expect(m.trustedLocalPlaintext, isFalse);
  });

  test('trusted local plaintext flag is persisted only via local map path', () {
    final local = ChatMessage(
      id: 'm-local',
      senderId: 'peer-1',
      recipientId: 'me-1',
      senderPubKeyB64: 'AAAA',
      nonceB64: '',
      boxB64: base64Encode(utf8.encode('local-only')),
      trustedLocalPlaintext: true,
    );
    final restored = ChatMessage.fromMap(local.toMap());
    expect(restored.trustedLocalPlaintext, isTrue);
  });

  test(
      'sealed direct message direction falls back to recipient when sender is redacted',
      () {
    final outgoing = ChatMessage(
      id: 'm-out',
      senderId: '',
      recipientId: 'peer-1',
      senderPubKeyB64: 'AAAA',
      nonceB64: 'AQ==',
      boxB64: 'Ag==',
      sealedSender: true,
      senderHint: 'fp-me',
    );
    final incoming = ChatMessage(
      id: 'm-in',
      senderId: '',
      recipientId: 'me-1',
      senderPubKeyB64: 'AAAA',
      nonceB64: 'AQ==',
      boxB64: 'Ag==',
      sealedSender: true,
      senderHint: 'fp-peer',
    );

    expect(outgoing.isOwnFor('me-1'), isTrue);
    expect(outgoing.isIncomingFor('me-1'), isFalse);
    expect(outgoing.peerIdFor('me-1'), 'peer-1');

    expect(incoming.isOwnFor('me-1'), isFalse);
    expect(incoming.isIncomingFor('me-1'), isTrue);
    expect(incoming.peerIdFor('me-1'), isEmpty);
  });

  test('ChatHttpException.toString never includes the raw response body', () {
    final e = ChatHttpException(
      op: 'send',
      statusCode: 500,
      body: '{"detail":"internal auth required"}',
    );
    final s = e.toString();
    expect(s, contains('HTTP 500'));
    expect(s, isNot(contains('internal auth required')));
    expect(s, isNot(contains('detail')));
  });

  test(
      'identity, device auth tokens, and session bootstrap metadata persist under scoped storage',
      () async {
    final store = ChatLocalStore();
    const identity = ChatIdentity(
      id: 'dev-1',
      publicKeyB64: 'pk-1',
      privateKeyB64: 'sk-1',
      fingerprint: 'fp-1',
      displayName: 'Alice',
    );
    const pinnedSigningKeyB64 = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
    await store.saveIdentity(identity);
    await store.saveDeviceAuthToken('dev-1', 'tok-1');
    await store.markDeviceKeyBootstrapped('dev-1');
    await store.saveSessionBootstrapMeta(
      'peer-1',
      protocolFloor: 'v2_libsignal',
      signedPrekeyId: 77,
      oneTimePrekeyId: 88,
      v2Only: true,
      identitySigningPubkeyB64: pinnedSigningKeyB64,
    );

    expect((await store.loadIdentity())?.id, 'dev-1');
    expect(await store.loadDeviceAuthToken('dev-1'), 'tok-1');
    expect(await store.isDeviceKeyBootstrapped('dev-1'), isTrue);
    final meta = await store.loadSessionBootstrapMeta('peer-1');
    expect(meta['peer_id'], 'peer-1');
    expect(meta['protocol_floor'], 'v2_libsignal');
    expect(meta['signed_prekey_id'], 77);
    expect(meta['one_time_prekey_id'], 88);
    expect(meta['v2_only'], true);
    expect(
      await store.loadPinnedIdentitySigningPubkey('peer-1'),
      pinnedSigningKeyB64,
    );

    expect(
      secStore.containsKey(scopedChatPrefKey('chat.identity.v2.', 'unknown')),
      isTrue,
    );
    expect(
      secStore.containsKey(
        scopedChatEntityPrefKey('chat.device.token.v2.', 'unknown', 'dev-1'),
      ),
      isTrue,
    );
    expect(
      secStore.containsKey(
        scopedChatEntityPrefKey(
          'chat.session.bootstrap.v2.',
          'unknown',
          'peer-1',
        ),
      ),
      isTrue,
    );
    final sp = await SharedPreferences.getInstance();
    final bootstrappedRaw = sp.getString(
      scopedChatEntityPrefKey(
        'chat.device.keys.bootstrapped.v2.',
        'unknown',
        'dev-1',
      ),
    );
    expect(bootstrappedRaw, isNotNull);
    expect(
      (jsonDecode(bootstrappedRaw!) as Map<String, Object?>)['v'],
      1,
    );

    await store.deleteDeviceAuthToken('dev-1');
    expect(await store.loadDeviceAuthToken('dev-1'), isNull);
    expect(await store.isDeviceKeyBootstrapped('dev-1'), isFalse);

    await store.deleteSessionBootstrapMeta('peer-1');
    expect(await store.loadSessionBootstrapMeta('peer-1'), isEmpty);
    expect(await store.loadPinnedIdentitySigningPubkey('peer-1'), isNull);
  });

  test(
      'session keys, chain state, ratchets, and group keys persist under scoped secure storage',
      () async {
    final store = ChatLocalStore();
    await store.saveSessionKey('peer-1', 'session-key-1');
    await store.saveChain('peer-1', <String, Object>{
      'step': 1,
      'dh': 'abc',
    });
    await store.saveRatchet('peer-1', <String, Object>{
      'count': 2,
      'dh': 'ratchet',
    });
    await store.saveGroupKey('grp-1', 'group-key-1');

    expect(await store.loadSessionKeys(), <String, String>{
      'peer-1': 'session-key-1',
    });
    expect(await store.loadChains(), <String, Map<String, Object>>{
      'peer-1': <String, Object>{'step': 1, 'dh': 'abc'},
    });
    expect(await store.loadRatchet('peer-1'), <String, Object>{
      'count': 2,
      'dh': 'ratchet',
    });
    expect(await store.loadGroupKey('grp-1'), 'group-key-1');

    expect(
      secStore.containsKey(
        scopedChatPrefKey('chat.session.keys.v2.', 'unknown'),
      ),
      isTrue,
    );
    expect(
      secStore.containsKey(
        scopedChatPrefKey('chat.session.chain.v2.', 'unknown'),
      ),
      isTrue,
    );
    expect(
      secStore.containsKey(
        scopedChatEntityPrefKey('chat.ratchet.v2.', 'unknown', 'peer-1'),
      ),
      isTrue,
    );
    expect(
      secStore.containsKey(
        scopedChatEntityPrefKey('chat.grp.key.v2.', 'unknown', 'grp-1'),
      ),
      isTrue,
    );
  });

  test(
      'legacy global session keys, chain state, ratchets, and group keys migrate to scoped secure storage on unknown origin',
      () async {
    secStore['chat.session.keys'] = jsonEncode(<String, String>{
      'peer-legacy': 'session-key-legacy',
    });
    secStore['chat.session.chain'] = jsonEncode(<String, Map<String, Object>>{
      'peer-legacy': <String, Object>{'step': 5, 'dh': 'legacy-chain'},
    });
    secStore['chat.ratchet.peer-legacy'] = jsonEncode(<String, Object>{
      'count': 6,
      'dh': 'legacy-ratchet',
    });
    secStore['chat.grp.key.grp-legacy'] = 'group-key-legacy';

    final store = ChatLocalStore();
    expect(await store.loadSessionKeys(), <String, String>{
      'peer-legacy': 'session-key-legacy',
    });
    expect(await store.loadChains(), <String, Map<String, Object>>{
      'peer-legacy': <String, Object>{'step': 5, 'dh': 'legacy-chain'},
    });
    expect(await store.loadRatchet('peer-legacy'), <String, Object>{
      'count': 6,
      'dh': 'legacy-ratchet',
    });
    expect(await store.loadGroupKey('grp-legacy'), 'group-key-legacy');

    expect(secStore.containsKey('chat.session.keys'), isFalse);
    expect(secStore.containsKey('chat.session.chain'), isFalse);
    expect(secStore.containsKey('chat.ratchet.peer-legacy'), isFalse);
    expect(secStore.containsKey('chat.grp.key.grp-legacy'), isFalse);
    expect(
      secStore.containsKey(
        scopedChatPrefKey('chat.session.keys.v2.', 'unknown'),
      ),
      isTrue,
    );
    expect(
      secStore.containsKey(
        scopedChatPrefKey('chat.session.chain.v2.', 'unknown'),
      ),
      isTrue,
    );
    expect(
      secStore.containsKey(
        scopedChatEntityPrefKey(
          'chat.ratchet.v2.',
          'unknown',
          'peer-legacy',
        ),
      ),
      isTrue,
    );
    expect(
      secStore.containsKey(
        scopedChatEntityPrefKey(
          'chat.grp.key.v2.',
          'unknown',
          'grp-legacy',
        ),
      ),
      isTrue,
    );
  });

  test(
      'session keys, chain state, ratchets, and group keys stay isolated across canonical API origins',
      () async {
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.saveSessionKey('peer-1', 'session-key-one');
    await store.saveChain('peer-1', <String, Object>{
      'step': 1,
      'dh': 'chain-one',
    });
    await store.saveRatchet('peer-1', <String, Object>{
      'count': 2,
      'dh': 'ratchet-one',
    });
    await store.saveGroupKey('grp-1', 'group-key-one');

    await sp.setString('base_url', 'https://api.two.example');
    expect(await store.loadSessionKeys(), isEmpty);
    expect(await store.loadChains(), isEmpty);
    expect(await store.loadRatchet('peer-1'), isEmpty);
    expect(await store.loadGroupKey('grp-1'), isNull);

    await store.saveSessionKey('peer-1', 'session-key-two');
    await store.saveChain('peer-1', <String, Object>{
      'step': 11,
      'dh': 'chain-two',
    });
    await store.saveRatchet('peer-1', <String, Object>{
      'count': 12,
      'dh': 'ratchet-two',
    });
    await store.saveGroupKey('grp-1', 'group-key-two');

    await sp.setString('base_url', 'https://api.one.example');
    expect(await store.loadSessionKeys(), <String, String>{
      'peer-1': 'session-key-one',
    });
    expect(await store.loadChains(), <String, Map<String, Object>>{
      'peer-1': <String, Object>{'step': 1, 'dh': 'chain-one'},
    });
    expect(await store.loadRatchet('peer-1'), <String, Object>{
      'count': 2,
      'dh': 'ratchet-one',
    });
    expect(await store.loadGroupKey('grp-1'), 'group-key-one');

    await sp.setString('base_url', 'https://api.two.example');
    expect(await store.loadSessionKeys(), <String, String>{
      'peer-1': 'session-key-two',
    });
    expect(await store.loadChains(), <String, Map<String, Object>>{
      'peer-1': <String, Object>{'step': 11, 'dh': 'chain-two'},
    });
    expect(await store.loadRatchet('peer-1'), <String, Object>{
      'count': 12,
      'dh': 'ratchet-two',
    });
    expect(await store.loadGroupKey('grp-1'), 'group-key-two');
  });

  test(
      'session key and chain maps honor explicit baseUrl override over global scope',
      () async {
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.saveSessionKey('peer-1', 'session-key-one');
    await store.saveChain('peer-1', <String, Object>{
      'step': 1,
      'dh': 'chain-one',
    });

    await store.saveSessionKey(
      'peer-1',
      'session-key-two',
      baseUrlOverride: 'https://api.two.example',
    );
    await store.saveChain(
      'peer-1',
      <String, Object>{
        'step': 11,
        'dh': 'chain-two',
      },
      baseUrlOverride: 'https://api.two.example',
    );

    expect(await store.loadSessionKeys(), <String, String>{
      'peer-1': 'session-key-one',
    });
    expect(await store.loadChains(), <String, Map<String, Object>>{
      'peer-1': <String, Object>{'step': 1, 'dh': 'chain-one'},
    });
    expect(
      await store.loadSessionKeys(
        baseUrlOverride: 'https://api.two.example',
      ),
      <String, String>{'peer-1': 'session-key-two'},
    );
    expect(
      await store.loadChains(
        baseUrlOverride: 'https://api.two.example',
      ),
      <String, Map<String, Object>>{
        'peer-1': <String, Object>{'step': 11, 'dh': 'chain-two'},
      },
    );
  });

  test(
      'secure entity chat state honors explicit baseUrl override over global scope',
      () async {
    const scopedOrigin = 'https://api.two.example';
    const pinnedSigningKeyB64 = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.saveRatchet(
      'peer-1',
      <String, Object>{'count': 12, 'dh': 'ratchet-two'},
      baseUrlOverride: scopedOrigin,
    );
    await store.saveGroupKey(
      'grp-1',
      'group-key-two',
      baseUrlOverride: scopedOrigin,
    );
    await store.saveSessionBootstrapMeta(
      'peer-1',
      protocolFloor: 'v2_libsignal',
      signedPrekeyId: 77,
      oneTimePrekeyId: 88,
      v2Only: true,
      identitySigningPubkeyB64: pinnedSigningKeyB64,
      baseUrlOverride: scopedOrigin,
    );

    expect(await store.loadRatchet('peer-1'), isEmpty);
    expect(await store.loadGroupKey('grp-1'), isNull);
    expect(await store.loadSessionBootstrapMeta('peer-1'), isEmpty);
    expect(await store.loadPinnedIdentitySigningPubkey('peer-1'), isNull);

    expect(
      await store.loadRatchet('peer-1', baseUrlOverride: scopedOrigin),
      <String, Object>{'count': 12, 'dh': 'ratchet-two'},
    );
    expect(
      await store.loadGroupKey('grp-1', baseUrlOverride: scopedOrigin),
      'group-key-two',
    );
    final meta = await store.loadSessionBootstrapMeta(
      'peer-1',
      baseUrlOverride: scopedOrigin,
    );
    expect(meta['protocol_floor'], 'v2_libsignal');
    expect(meta['signed_prekey_id'], 77);
    expect(
      await store.loadPinnedIdentitySigningPubkey(
        'peer-1',
        baseUrlOverride: scopedOrigin,
      ),
      pinnedSigningKeyB64,
    );

    await store.deleteRatchet('peer-1', baseUrlOverride: scopedOrigin);
    await store.deleteGroupKey('grp-1', baseUrlOverride: scopedOrigin);
    await store.deleteSessionBootstrapMeta(
      'peer-1',
      baseUrlOverride: scopedOrigin,
    );

    expect(
      await store.loadRatchet('peer-1', baseUrlOverride: scopedOrigin),
      isEmpty,
    );
    expect(
      await store.loadGroupKey('grp-1', baseUrlOverride: scopedOrigin),
      isNull,
    );
    expect(
      await store.loadSessionBootstrapMeta(
        'peer-1',
        baseUrlOverride: scopedOrigin,
      ),
      isEmpty,
    );
  });

  test(
      'legacy global session keys, chain state, ratchets, and group keys do not rebind into trusted canonical origins',
      () async {
    secStore['chat.session.keys'] = jsonEncode(<String, String>{
      'peer-legacy': 'session-key-legacy',
    });
    secStore['chat.session.chain'] = jsonEncode(<String, Map<String, Object>>{
      'peer-legacy': <String, Object>{'step': 5, 'dh': 'legacy-chain'},
    });
    secStore['chat.ratchet.peer-legacy'] = jsonEncode(<String, Object>{
      'count': 6,
      'dh': 'legacy-ratchet',
    });
    secStore['chat.grp.key.grp-legacy'] = 'group-key-legacy';
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
    });

    final store = ChatLocalStore();
    expect(await store.loadSessionKeys(), isEmpty);
    expect(await store.loadChains(), isEmpty);
    expect(await store.loadRatchet('peer-legacy'), isEmpty);
    expect(await store.loadGroupKey('grp-legacy'), isNull);

    expect(secStore.containsKey('chat.session.keys'), isFalse);
    expect(secStore.containsKey('chat.session.chain'), isFalse);
    expect(secStore.containsKey('chat.ratchet.peer-legacy'), isFalse);
    expect(secStore.containsKey('chat.grp.key.grp-legacy'), isFalse);
  });

  test('call log persists under scoped encrypted storage', () async {
    final store = ChatCallStore();
    final entry = ChatCallLogEntry(
      id: 'call-1',
      peerId: 'peer-1',
      ts: DateTime.utc(2026, 3, 14, 10, 0, 0),
      direction: 'out',
      kind: 'voice',
      accepted: true,
      duration: const Duration(seconds: 42),
    );

    await store.append(entry);

    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(scopedChatPrefKey('chat.calllog.v2.', 'unknown'));
    expect(raw, isNotNull);
    expect((jsonDecode(raw!) as Map<String, Object?>)['v'], 1);

    final loaded = await store.load();
    expect(loaded.map((call) => call.id).toList(), <String>['call-1']);
  });

  test(
      'legacy plaintext call log migrates to scoped ciphertext on unknown origin',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'chat.calllog': jsonEncode(<Map<String, Object?>>[
        ChatCallLogEntry(
          id: 'call-legacy',
          peerId: 'peer-legacy',
          ts: DateTime.utc(2026, 3, 14, 9, 0, 0),
          direction: 'in',
          kind: 'video',
          accepted: false,
          duration: Duration.zero,
        ).toMap(),
      ]),
    });

    final store = ChatCallStore();
    final loaded = await store.load();
    expect(loaded.map((call) => call.id).toList(), <String>['call-legacy']);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('chat.calllog'), isNull);
    final migrated =
        sp.getString(scopedChatPrefKey('chat.calllog.v2.', 'unknown'));
    expect(migrated, isNotNull);
    expect((jsonDecode(migrated!) as Map<String, Object?>)['v'], 1);
  });

  test('call log stays isolated across canonical API origins', () async {
    final store = ChatCallStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.append(
      ChatCallLogEntry(
        id: 'call-one',
        peerId: 'peer-1',
        ts: DateTime.utc(2026, 3, 14, 8, 0, 0),
        direction: 'out',
        kind: 'voice',
        accepted: true,
        duration: const Duration(seconds: 10),
      ),
    );

    await sp.setString('base_url', 'https://api.two.example');
    expect(await store.load(), isEmpty);

    await store.append(
      ChatCallLogEntry(
        id: 'call-two',
        peerId: 'peer-2',
        ts: DateTime.utc(2026, 3, 14, 9, 0, 0),
        direction: 'in',
        kind: 'video',
        accepted: false,
        duration: Duration.zero,
      ),
    );

    await sp.setString('base_url', 'https://api.one.example');
    expect((await store.load()).map((call) => call.id).toList(),
        <String>['call-one']);

    await sp.setString('base_url', 'https://api.two.example');
    expect((await store.load()).map((call) => call.id).toList(),
        <String>['call-two']);
  });

  test('call log honors explicit baseUrlOverride scope', () async {
    final store = ChatCallStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.append(
      ChatCallLogEntry(
        id: 'call-one',
        peerId: 'peer-1',
        ts: DateTime.utc(2026, 3, 14, 8, 0, 0),
        direction: 'out',
        kind: 'voice',
        accepted: true,
        duration: const Duration(seconds: 10),
      ),
    );

    await store.append(
      ChatCallLogEntry(
        id: 'call-two',
        peerId: 'peer-2',
        ts: DateTime.utc(2026, 3, 14, 9, 0, 0),
        direction: 'in',
        kind: 'video',
        accepted: false,
        duration: Duration.zero,
      ),
      baseUrlOverride: 'https://api.two.example',
    );

    expect((await store.load()).map((call) => call.id).toList(),
        <String>['call-one']);
    expect(
      (await store.load(baseUrlOverride: 'https://api.two.example'))
          .map((call) => call.id)
          .toList(),
      <String>['call-two'],
    );
  });

  test('chat history clear helper includes call logs and legacy reactions',
      () async {
    final keys = shamellChatHistoryPrefKeysToClear(<String>{
      'chat.calllog',
      scopedChatPrefKey('chat.calllog.v2.', 'https://api.example.com'),
      'chat.group_message_reactions.group-legacy',
      scopedChatPrefKey(
        'chat.group_message_reactions.v2.',
        'https://api.example.com',
      ),
    });

    expect(keys, contains('chat.calllog'));
    expect(
      keys,
      contains(
          scopedChatPrefKey('chat.calllog.v2.', 'https://api.example.com')),
    );
    expect(keys, contains('chat.group_message_reactions.group-legacy'));
    expect(
      keys,
      contains(
        scopedChatPrefKey(
          'chat.group_message_reactions.v2.',
          'https://api.example.com',
        ),
      ),
    );
  });

  test('chat history clear helper also clears local favorites', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      'chat.calllog': jsonEncode(<Map<String, Object?>>[
        ChatCallLogEntry(
          id: 'call-1',
          peerId: 'peer-1',
          ts: DateTime.utc(2026, 3, 14, 9, 0, 0),
          direction: 'in',
          kind: 'voice',
          accepted: true,
          duration: const Duration(seconds: 3),
        ).toMap(),
      ]),
    });

    await saveFavoriteItems(<Map<String, dynamic>>[
      <String, dynamic>{'text': 'saved message', 'msgId': 'm1'},
    ]);

    final sp = await SharedPreferences.getInstance();
    expect(await favoriteItemsStorageBytes(), greaterThan(0));
    expect(sp.getString('chat.calllog'), isNotNull);

    await shamellClearLocalChatHistory(sp: sp);

    expect(await loadFavoriteItems(), isEmpty);
    expect(await favoriteItemsStorageBytes(), 0);
    expect(sp.getString('chat.calllog'), isNull);
  });

  test(
      'chat history storage stats and clear honor explicit baseUrl override over global scope',
      () async {
    const originOne = 'https://api.one.example.com';
    const originTwo = 'https://api.two.example.com';
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': originTwo,
      scopedChatEntityPrefKey('chat.msgs.v2.', originOne, 'peer-one'): 'abcd',
      scopedChatEntityPrefKey('chat.msgs.v2.', originTwo, 'peer-two'):
          'other-direct',
      scopedChatEntityPrefKey('chat.grp.msgs.v2.', originOne, 'group-one'):
          'efghij',
      scopedChatPrefKey('chat.pinned_messages.v2.', originOne): 'pin',
      scopedChatPrefKey('chat.calllog.v2.', originOne): 'call',
    });

    await saveFavoriteItems(<Map<String, dynamic>>[
      <String, dynamic>{'text': 'origin one favorite', 'msgId': 'm1'},
    ], baseUrlOverride: originOne);
    await saveFavoriteItems(<Map<String, dynamic>>[
      <String, dynamic>{'text': 'origin two favorite', 'msgId': 'm2'},
    ], baseUrlOverride: originTwo);

    final sp = await SharedPreferences.getInstance();
    final snapshot = await shamellLoadLocalChatHistoryStorageSnapshot(
      baseUrl: originOne,
      sp: sp,
    );
    expect(snapshot.chatThreads, 1);
    expect(snapshot.groupThreads, 1);
    expect(snapshot.chatBytes, 8);
    expect(snapshot.groupBytes, 6);
    expect(snapshot.pinnedBytes, 3);

    final originTwoFavoritesBytes =
        await favoriteItemsStorageBytes(baseUrlOverride: originTwo);
    expect(originTwoFavoritesBytes, greaterThan(0));

    await shamellClearLocalChatHistory(
      sp: sp,
      baseUrlOverride: originOne,
    );

    expect(
      sp.getString(
        scopedChatEntityPrefKey('chat.msgs.v2.', originOne, 'peer-one'),
      ),
      isNull,
    );
    expect(
      sp.getString(
        scopedChatEntityPrefKey('chat.msgs.v2.', originTwo, 'peer-two'),
      ),
      isNotNull,
    );
    expect(
      sp.getString(scopedChatPrefKey('chat.calllog.v2.', originOne)),
      isNull,
    );
    expect(await favoriteItemsStorageBytes(baseUrlOverride: originOne), 0);
    expect(
      await favoriteItemsStorageBytes(baseUrlOverride: originTwo),
      originTwoFavoritesBytes,
    );
  });

  test('chat call log helper recognizes both legacy and scoped keys', () {
    expect(shamellIsChatCallLogPrefKey('chat.calllog'), isTrue);
    expect(
      shamellIsChatCallLogPrefKey(
        scopedChatPrefKey('chat.calllog.v2.', 'https://api.example.com'),
      ),
      isTrue,
    );
    expect(shamellIsChatCallLogPrefKey('chat.msgs.peer-1'), isFalse);
  });

  test('legacy global call log does not rebind into trusted canonical origins',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      'chat.calllog': jsonEncode(<Map<String, Object?>>[
        ChatCallLogEntry(
          id: 'call-legacy',
          peerId: 'peer-legacy',
          ts: DateTime.utc(2026, 3, 14, 9, 0, 0),
          direction: 'in',
          kind: 'video',
          accepted: false,
          duration: Duration.zero,
        ).toMap(),
      ]),
    });

    final store = ChatCallStore();
    expect(await store.load(), isEmpty);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('chat.calllog'), isNull);
  });

  test(
      'legacy global identity, device auth token, key bootstrap marker, and session bootstrap metadata migrate to scoped storage on unknown origin',
      () async {
    const identity = ChatIdentity(
      id: 'dev-legacy',
      publicKeyB64: 'pk-legacy',
      privateKeyB64: 'sk-legacy',
      fingerprint: 'fp-legacy',
      displayName: 'Legacy',
    );
    secStore['chat.identity'] = jsonEncode(identity.toMap());
    secStore['chat.device.token.dev-legacy'] = 'tok-legacy';
    secStore['chat.session.bootstrap.peer-legacy'] = jsonEncode(
      <String, Object?>{
        'peer_id': 'peer-legacy',
        'protocol_floor': 'v2_libsignal',
        'signed_prekey_id': 5,
        'one_time_prekey_id': 6,
        'v2_only': true,
        'identity_signing_pubkey_b64':
            'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
        'bootstrapped_at': DateTime.utc(2026, 3, 14).toIso8601String(),
      },
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      'chat.device.keys.bootstrapped.dev-legacy': true,
    });

    final store = ChatLocalStore();
    expect((await store.loadIdentity())?.id, 'dev-legacy');
    expect(await store.loadDeviceAuthToken('dev-legacy'), 'tok-legacy');
    expect(await store.isDeviceKeyBootstrapped('dev-legacy'), isTrue);
    expect(
      (await store.loadSessionBootstrapMeta('peer-legacy'))['peer_id'],
      'peer-legacy',
    );

    expect(secStore.containsKey('chat.identity'), isFalse);
    expect(secStore.containsKey('chat.device.token.dev-legacy'), isFalse);
    expect(secStore.containsKey('chat.session.bootstrap.peer-legacy'), isFalse);
    expect(
      secStore.containsKey(scopedChatPrefKey('chat.identity.v2.', 'unknown')),
      isTrue,
    );
    expect(
      secStore.containsKey(
        scopedChatEntityPrefKey(
          'chat.device.token.v2.',
          'unknown',
          'dev-legacy',
        ),
      ),
      isTrue,
    );
    expect(
      secStore.containsKey(
        scopedChatEntityPrefKey(
          'chat.session.bootstrap.v2.',
          'unknown',
          'peer-legacy',
        ),
      ),
      isTrue,
    );
    final sp = await SharedPreferences.getInstance();
    expect(sp.getBool('chat.device.keys.bootstrapped.dev-legacy'), isNull);
    final bootstrappedRaw = sp.getString(
      scopedChatEntityPrefKey(
        'chat.device.keys.bootstrapped.v2.',
        'unknown',
        'dev-legacy',
      ),
    );
    expect(bootstrappedRaw, isNotNull);
    expect(
      (jsonDecode(bootstrappedRaw!) as Map<String, Object?>)['v'],
      1,
    );
  });

  test(
      'identity, device auth tokens, key bootstrap markers, and session bootstrap metadata stay isolated across canonical API origins',
      () async {
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.saveIdentity(
      const ChatIdentity(
        id: 'dev-one',
        publicKeyB64: 'pk-one',
        privateKeyB64: 'sk-one',
        fingerprint: 'fp-one',
      ),
    );
    await store.saveDeviceAuthToken('dev-1', 'tok-one');
    await store.markDeviceKeyBootstrapped('dev-1');
    await store.saveSessionBootstrapMeta(
      'peer-1',
      protocolFloor: 'v2_libsignal',
      signedPrekeyId: 11,
      oneTimePrekeyId: 12,
      v2Only: true,
    );

    await sp.setString('base_url', 'https://api.two.example');
    expect(await store.loadIdentity(), isNull);
    expect(await store.loadDeviceAuthToken('dev-1'), isNull);
    expect(await store.isDeviceKeyBootstrapped('dev-1'), isFalse);
    expect(await store.loadSessionBootstrapMeta('peer-1'), isEmpty);

    await store.saveIdentity(
      const ChatIdentity(
        id: 'dev-two',
        publicKeyB64: 'pk-two',
        privateKeyB64: 'sk-two',
        fingerprint: 'fp-two',
      ),
    );
    await store.saveDeviceAuthToken('dev-1', 'tok-two');
    await store.markDeviceKeyBootstrapped('dev-1');
    await store.saveSessionBootstrapMeta(
      'peer-1',
      protocolFloor: 'v2_libsignal',
      signedPrekeyId: 21,
      oneTimePrekeyId: 22,
      v2Only: true,
    );

    await sp.setString('base_url', 'https://api.one.example');
    expect((await store.loadIdentity())?.id, 'dev-one');
    expect(await store.loadDeviceAuthToken('dev-1'), 'tok-one');
    expect(await store.isDeviceKeyBootstrapped('dev-1'), isTrue);
    expect(
      (await store.loadSessionBootstrapMeta('peer-1'))['signed_prekey_id'],
      11,
    );

    await sp.setString('base_url', 'https://api.two.example');
    expect((await store.loadIdentity())?.id, 'dev-two');
    expect(await store.loadDeviceAuthToken('dev-1'), 'tok-two');
    expect(await store.isDeviceKeyBootstrapped('dev-1'), isTrue);
    expect(
      (await store.loadSessionBootstrapMeta('peer-1'))['signed_prekey_id'],
      21,
    );
  });

  test(
      'override-scoped chat identity and device credentials do not bleed into the stored base_url scope',
      () async {
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.saveIdentity(
      const ChatIdentity(
        id: 'dev-one',
        publicKeyB64: 'pk-one',
        privateKeyB64: 'sk-one',
        fingerprint: 'fp-one',
      ),
    );
    await store.saveDeviceAuthToken('dev-shared', 'tok-one');
    await store.markDeviceKeyBootstrapped('dev-shared');

    await store.saveIdentity(
      const ChatIdentity(
        id: 'dev-two',
        publicKeyB64: 'pk-two',
        privateKeyB64: 'sk-two',
        fingerprint: 'fp-two',
      ),
      baseUrlOverride: 'https://api.two.example',
    );
    await store.saveDeviceAuthToken(
      'dev-shared',
      'tok-two',
      baseUrlOverride: 'https://api.two.example',
    );
    await store.markDeviceKeyBootstrapped(
      'dev-shared',
      baseUrlOverride: 'https://api.two.example',
    );

    expect((await store.loadIdentity())?.id, 'dev-one');
    expect(await store.loadDeviceAuthToken('dev-shared'), 'tok-one');
    expect(await store.isDeviceKeyBootstrapped('dev-shared'), isTrue);

    expect(
      (await store.loadIdentity(
        baseUrlOverride: 'https://api.two.example',
      ))
          ?.id,
      'dev-two',
    );
    expect(
      await store.loadDeviceAuthToken(
        'dev-shared',
        baseUrlOverride: 'https://api.two.example',
      ),
      'tok-two',
    );
    expect(
      await store.isDeviceKeyBootstrapped(
        'dev-shared',
        baseUrlOverride: 'https://api.two.example',
      ),
      isTrue,
    );
    expect(
      await CallSignalingClient.loadDeviceId(
        baseUrlOverride: 'https://api.two.example',
      ),
      'dev-two',
    );
  });

  test(
      'legacy global identity, device auth token, key bootstrap marker, and session bootstrap metadata do not rebind into trusted canonical origins',
      () async {
    const identity = ChatIdentity(
      id: 'dev-legacy',
      publicKeyB64: 'pk-legacy',
      privateKeyB64: 'sk-legacy',
      fingerprint: 'fp-legacy',
      displayName: 'Legacy',
    );
    secStore['chat.identity'] = jsonEncode(identity.toMap());
    secStore['chat.device.token.dev-legacy'] = 'tok-legacy';
    secStore['chat.session.bootstrap.peer-legacy'] = jsonEncode(
      <String, Object?>{
        'peer_id': 'peer-legacy',
        'protocol_floor': 'v2_libsignal',
        'signed_prekey_id': 5,
        'one_time_prekey_id': 6,
        'v2_only': true,
        'bootstrapped_at': DateTime.utc(2026, 3, 14).toIso8601String(),
      },
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      'chat.device.keys.bootstrapped.dev-legacy': true,
    });

    final store = ChatLocalStore();
    expect(await store.loadIdentity(), isNull);
    expect(await store.loadDeviceAuthToken('dev-legacy'), isNull);
    expect(await store.isDeviceKeyBootstrapped('dev-legacy'), isFalse);
    expect(await store.loadSessionBootstrapMeta('peer-legacy'), isEmpty);

    final sp = await SharedPreferences.getInstance();
    expect(secStore.containsKey('chat.identity'), isFalse);
    expect(secStore.containsKey('chat.device.token.dev-legacy'), isFalse);
    expect(secStore.containsKey('chat.session.bootstrap.peer-legacy'), isFalse);
    expect(sp.getBool('chat.device.keys.bootstrapped.dev-legacy'), isNull);
  });

  test('direct send uses sealed-sender by default and sets sender_hint',
      () async {
    final capturedBodies = <Map<String, Object?>>[];

    final mock = MockClient((req) async {
      if (req.url.path == '/chat/messages/send') {
        capturedBodies.add(jsonDecode(req.body) as Map<String, Object?>);
        return http.Response(
          jsonEncode(<String, Object?>{
            'id': 'm1',
            'sender_id': null,
            'recipient_id': 'peer-1',
            'sender_pubkey_b64': null,
            'nonce_b64': 'nonce',
            'box_b64': 'box',
            'created_at': DateTime.now().toIso8601String(),
            'sealed_sender': true,
            'sender_hint': 'fp-me',
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });

    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    const me = ChatIdentity(
      id: 'me-1',
      publicKeyB64: 'AAAA',
      privateKeyB64: 'IGNORED',
      fingerprint: 'fp-me',
    );
    const peer = ChatContact(
      id: 'peer-1',
      publicKeyB64: 'BBBB',
      fingerprint: 'fp-peer',
    );
    final sessionKey = Uint8List.fromList(List<int>.filled(32, 7));

    final sent = await svc.sendMessage(
      me: me,
      peer: peer,
      plainText: jsonEncode(<String, Object?>{'text': 'hi'}),
      sessionKey: sessionKey,
    );

    expect(capturedBodies, hasLength(1));
    final body = capturedBodies.single;
    expect(body['sealed_sender'], true);
    expect(body['sender_hint'], 'fp-me');
    expect(body['sender_fingerprint'], 'fp-me');
    expect(sent.senderId, isEmpty);
    expect(sent.recipientId, 'peer-1');
    expect(sent.senderPubKeyB64, isEmpty);
    expect(sent.sealedSender, isTrue);
    expect(sent.senderHint, 'fp-me');
  });

  test('prepared direct envelope reuses identical ciphertext across retries',
      () async {
    final capturedBodies = <Map<String, Object?>>[];

    final mock = MockClient((req) async {
      if (req.url.path == '/chat/messages/send') {
        capturedBodies.add(jsonDecode(req.body) as Map<String, Object?>);
        return http.Response(
          jsonEncode(<String, Object?>{
            'id': 'm-${capturedBodies.length}',
            'sender_id': null,
            'recipient_id': 'peer-1',
            'sender_pubkey_b64': null,
            'nonce_b64': 'nonce',
            'box_b64': 'box',
            'created_at': DateTime.now().toIso8601String(),
            'sealed_sender': true,
            'sender_hint': 'fp-me',
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });

    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    const me = ChatIdentity(
      id: 'me-1',
      publicKeyB64: 'AAAA',
      privateKeyB64: 'IGNORED',
      fingerprint: 'fp-me',
    );
    const peer = ChatContact(
      id: 'peer-1',
      publicKeyB64: 'BBBB',
      fingerprint: 'fp-peer',
    );
    final sessionKey = Uint8List.fromList(List<int>.filled(32, 7));
    final plainText = jsonEncode(<String, Object?>{
      'text': 'same-intent',
      'client_ts': '2026-03-18T12:00:00.000Z',
    });
    final envelope = svc.prepareDirectSendEnvelope(
      me: me,
      peer: peer,
      plainText: plainText,
      sessionKey: sessionKey,
      senderHint: me.fingerprint,
    );

    await svc.sendMessage(
      me: me,
      peer: peer,
      plainText: plainText,
      sessionKey: sessionKey,
      senderHint: me.fingerprint,
      preparedEnvelope: envelope,
    );
    await svc.sendMessage(
      me: me,
      peer: peer,
      plainText: plainText,
      sessionKey: sessionKey,
      senderHint: me.fingerprint,
      preparedEnvelope: envelope,
    );

    expect(capturedBodies, hasLength(2));
    expect(capturedBodies[0], capturedBodies[1]);
    expect(capturedBodies[0]['nonce_b64'], capturedBodies[1]['nonce_b64']);
    expect(capturedBodies[0]['box_b64'], capturedBodies[1]['box_b64']);
  });

  test('prepared direct envelope fails closed on actor mismatch', () async {
    var requests = 0;
    final mock = MockClient((req) async {
      requests += 1;
      return http.Response('{}', 200);
    });

    final svc = ChatService('http://127.0.0.1:8080', httpClient: mock);
    const me = ChatIdentity(
      id: 'me-1',
      publicKeyB64: 'AAAA',
      privateKeyB64: 'IGNORED',
      fingerprint: 'fp-me',
    );
    const otherMe = ChatIdentity(
      id: 'me-2',
      publicKeyB64: 'CCCC',
      privateKeyB64: 'IGNORED',
      fingerprint: 'fp-other',
    );
    const peer = ChatContact(
      id: 'peer-1',
      publicKeyB64: 'BBBB',
      fingerprint: 'fp-peer',
    );
    final sessionKey = Uint8List.fromList(List<int>.filled(32, 7));
    final plainText = jsonEncode(<String, Object?>{'text': 'hi'});
    final envelope = svc.prepareDirectSendEnvelope(
      me: me,
      peer: peer,
      plainText: plainText,
      sessionKey: sessionKey,
      senderHint: me.fingerprint,
    );

    await expectLater(
      svc.sendMessage(
        me: otherMe,
        peer: peer,
        plainText: plainText,
        sessionKey: sessionKey,
        senderHint: otherMe.fingerprint,
        preparedEnvelope: envelope,
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('actor mismatch'),
        ),
      ),
    );
    expect(requests, 0);
  });

  test('sendMessage fails closed when direct ciphertext exceeds backend cap',
      () async {
    final svc = ChatService('http://127.0.0.1:8080');
    const me = ChatIdentity(
      id: 'me-1',
      publicKeyB64: 'AAAA',
      privateKeyB64: 'IGNORED',
      fingerprint: 'fp-me',
    );
    const peer = ChatContact(
      id: 'peer-1',
      publicKeyB64: 'BBBB',
      fingerprint: 'fp-peer',
    );
    final sessionKey = Uint8List.fromList(List<int>.filled(32, 7));
    final oversizedPlain = 'x' * shamellDirectMessageCiphertextMaxB64Len;

    await expectLater(
      svc.sendMessage(
        me: me,
        peer: peer,
        plainText: oversizedPlain,
        sessionKey: sessionKey,
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('direct message too large'),
        ),
      ),
    );
  });

  test('safety number matches golden vector (Rust)', () {
    final aliceId = 'AB12CD34';
    final bobId = 'EF56GH78';
    final aliceKey =
        Uint8List.fromList(<int>[5, ...List<int>.filled(32, 0x61)]);
    final bobKey = Uint8List.fromList(<int>[5, ...List<int>.filled(32, 0x62)]);
    final sn = shamellSafetyNumber(
      localIdentifier: aliceId,
      localIdentityKey: aliceKey,
      remoteIdentifier: bobId,
      remoteIdentityKey: bobKey,
    );
    expect(
      sn,
      '173046012845324248619911109010023170662360669019855543763304',
    );

    final sn2 = shamellSafetyNumber(
      localIdentifier: bobId,
      localIdentityKey: bobKey,
      remoteIdentifier: aliceId,
      remoteIdentityKey: aliceKey,
    );
    expect(sn2, sn);
    expect(sn.length, 60);
    expect(sn.contains(RegExp(r'^[0-9]{60}$')), isTrue);
  });

  test('libsignal key api is guarded for staged release', () {
    expect(shamellLibsignalKeyApiDebugDefault, isTrue);
    expect(shamellLibsignalKeyApiReleaseDefault, isFalse);
  });

  test('peer and contacts are encrypted at rest in SharedPreferences',
      () async {
    final store = ChatLocalStore();
    final peer = ChatContact(
      id: 'dev-2',
      publicKeyB64: 'pk',
      fingerprint: 'fp',
      name: 'Alice',
      verified: false,
    );
    final contact = ChatContact(
      id: 'dev-3',
      publicKeyB64: 'pk-2',
      fingerprint: 'fp-2',
      name: 'Bob',
      verified: true,
    );
    await store.savePeer(peer);
    await store.saveContacts(<ChatContact>[contact]);
    final sp = await SharedPreferences.getInstance();
    for (final key in <String>[
      scopedChatPrefKey('chat.peer.v2.', 'unknown'),
      scopedChatPrefKey('chat.contacts.v2.', 'unknown'),
    ]) {
      final raw = sp.getString(key);
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, Object?>;
      expect(decoded['v'], 1);
      expect(
        (decoded['nonce_b64'] ?? '').toString().trim().isNotEmpty,
        isTrue,
      );
      expect((decoded['box_b64'] ?? '').toString().trim().isNotEmpty, isTrue);
    }
    final loaded = await store.loadPeer();
    expect(loaded?.id, 'dev-2');
    expect((await store.loadContacts()).map((entry) => entry.id).toList(),
        <String>['dev-3']);
  });

  test(
      'legacy plaintext peer and contacts migrate to scoped ciphertext on load',
      () async {
    final peer = ChatContact(
      id: 'dev-legacy',
      publicKeyB64: 'pk',
      fingerprint: 'fp',
      name: 'Legacy',
      verified: false,
    );
    final contact = ChatContact(
      id: 'dev-contact-legacy',
      publicKeyB64: 'pk-2',
      fingerprint: 'fp-2',
      name: 'Legacy Contact',
      verified: true,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      'chat.peer': jsonEncode(peer.toMap()),
      'chat.contacts': jsonEncode(<Map<String, Object?>>[contact.toMap()]),
    });
    final store = ChatLocalStore();
    final loaded = await store.loadPeer();
    expect(loaded?.id, 'dev-legacy');
    expect((await store.loadContacts()).map((entry) => entry.id).toList(),
        <String>['dev-contact-legacy']);
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('chat.peer'), isNull);
    expect(sp.getString('chat.contacts'), isNull);
    for (final key in <String>[
      scopedChatPrefKey('chat.peer.v2.', 'unknown'),
      scopedChatPrefKey('chat.contacts.v2.', 'unknown'),
    ]) {
      final migrated = sp.getString(key) ?? '';
      expect(migrated, isNotEmpty);
      final decoded = jsonDecode(migrated) as Map<String, Object?>;
      expect(decoded['v'], 1);
    }
  });

  test('peer and contacts stay isolated across canonical API origins',
      () async {
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.savePeer(
      ChatContact(
        id: 'dev-one',
        publicKeyB64: 'pk-one',
        fingerprint: 'fp-one',
        name: 'Alice',
        verified: false,
      ),
    );
    await store.saveContacts(<ChatContact>[
      ChatContact(
        id: 'contact-one',
        publicKeyB64: 'pk-c1',
        fingerprint: 'fp-c1',
        name: 'Ops',
        verified: true,
      ),
    ]);

    await sp.setString('base_url', 'https://api.two.example');
    expect(await store.loadPeer(), isNull);
    expect(await store.loadContacts(), isEmpty);

    await store.savePeer(
      ChatContact(
        id: 'dev-two',
        publicKeyB64: 'pk-two',
        fingerprint: 'fp-two',
        name: 'Bob',
        verified: true,
      ),
    );
    await store.saveContacts(<ChatContact>[
      ChatContact(
        id: 'contact-two',
        publicKeyB64: 'pk-c2',
        fingerprint: 'fp-c2',
        name: 'Finance',
        verified: false,
      ),
    ]);

    await sp.setString('base_url', 'https://api.one.example');
    expect((await store.loadPeer())?.id, 'dev-one');
    expect((await store.loadContacts()).map((entry) => entry.id).toList(),
        <String>['contact-one']);

    await sp.setString('base_url', 'https://api.two.example');
    expect((await store.loadPeer())?.id, 'dev-two');
    expect((await store.loadContacts()).map((entry) => entry.id).toList(),
        <String>['contact-two']);
  });

  test(
      'legacy global peer and contacts do not rebind into trusted canonical origins',
      () async {
    final peer = ChatContact(
      id: 'dev-legacy',
      publicKeyB64: 'pk',
      fingerprint: 'fp',
      name: 'Legacy',
      verified: false,
    );
    final contact = ChatContact(
      id: 'contact-legacy',
      publicKeyB64: 'pk-c',
      fingerprint: 'fp-c',
      name: 'Legacy Contact',
      verified: true,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      'chat.peer': jsonEncode(peer.toMap()),
      'chat.contacts': jsonEncode(<Map<String, Object?>>[contact.toMap()]),
    });

    final store = ChatLocalStore();
    expect(await store.loadPeer(), isNull);
    expect(await store.loadContacts(), isEmpty);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('chat.peer'), isNull);
    expect(sp.getString('chat.contacts'), isNull);
  });

  test('peer state honors explicit baseUrl override over global scope',
      () async {
    const scopedOrigin = 'https://api.two.example';
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.savePeer(
      ChatContact(
        id: 'dev-two',
        publicKeyB64: 'pk-two',
        fingerprint: 'fp-two',
        name: 'Bob',
        verified: true,
      ),
      baseUrlOverride: scopedOrigin,
    );

    expect(await store.loadPeer(), isNull);
    expect(
        (await store.loadPeer(baseUrlOverride: scopedOrigin))?.id, 'dev-two');

    await store.clearPeer(baseUrlOverride: scopedOrigin);
    expect(await store.loadPeer(baseUrlOverride: scopedOrigin), isNull);
  });

  test('contacts state honors explicit baseUrl override over global scope',
      () async {
    const scopedOrigin = 'https://api.two.example';
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.saveContacts(
      <ChatContact>[
        ChatContact(
          id: 'contact-two',
          publicKeyB64: 'pk-old',
          fingerprint: 'fp-old',
          name: 'Scoped Alice',
          verified: false,
        ),
      ],
      baseUrlOverride: scopedOrigin,
    );
    await store.upsertContact(
      ChatContact(
        id: 'contact-two',
        publicKeyB64: 'pk-new',
        fingerprint: 'fp-new',
        name: '',
        verified: true,
      ),
      baseUrlOverride: scopedOrigin,
    );

    expect(await store.loadContacts(), isEmpty);
    final contacts = await store.loadContacts(baseUrlOverride: scopedOrigin);
    expect(contacts.map((entry) => entry.id).toList(), <String>['contact-two']);
    expect(contacts.single.publicKeyB64, 'pk-new');
    expect(contacts.single.fingerprint, 'fp-new');
    expect(contacts.single.name, 'Scoped Alice');
  });

  test('drafts and pinned/recalled/archive chat metadata are encrypted at rest',
      () async {
    final store = ChatLocalStore();
    await store.saveDrafts(<String, String>{
      'peer-1': 'hello',
      'grp-1': 'follow up',
    });
    await store.savePinnedMessages(<String, Set<String>>{
      'peer-1': <String>{'m1', 'm2'},
    });
    await store.saveRecalledMessageIds(<String>{'m3'});
    await store.savePinnedChatOrder(<String>['peer-1', 'grp-1']);
    await store.saveArchivedGroups(<String>{'grp-2'});

    final sp = await SharedPreferences.getInstance();
    for (final key in <String>[
      scopedChatPrefKey('chat.drafts.v2.', 'unknown'),
      scopedChatPrefKey('chat.pinned_messages.v2.', 'unknown'),
      scopedChatPrefKey('chat.recalled_messages.v2.', 'unknown'),
      scopedChatPrefKey('chat.pinned_chats.v2.', 'unknown'),
      scopedChatPrefKey('chat.archived_groups.v2.', 'unknown'),
    ]) {
      final raw = sp.getString(key);
      expect(raw, isNotNull, reason: 'expected encrypted value for $key');
      final decoded = jsonDecode(raw!) as Map<String, Object?>;
      expect(decoded['v'], 1, reason: 'expected ciphertext envelope for $key');
    }

    expect(await store.loadDrafts(), <String, String>{
      'peer-1': 'hello',
      'grp-1': 'follow up',
    });
    expect(await store.loadPinnedMessages(), <String, Set<String>>{
      'peer-1': <String>{'m1', 'm2'},
    });
    expect(await store.loadRecalledMessageIds(), <String>{'m3'});
    expect(await store.loadPinnedChatOrder(), <String>['peer-1', 'grp-1']);
    expect(await store.loadArchivedGroups(), <String>{'grp-2'});
  });

  test(
      'legacy plaintext drafts and pinned/recalled/archive chat metadata migrate to scoped ciphertext on load',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'chat.drafts.v1': '{"peer-1":"hello","grp-1":"follow up"}',
      'chat.pinned_messages': '{"peer-1":["m1","m2"]}',
      'chat.recalled_messages': <String>['m3'],
      'chat.pinned_chats': <String>['peer-1', 'grp-1'],
      'chat.archived_groups': <String>['grp-2'],
    });

    final store = ChatLocalStore();

    expect(await store.loadDrafts(), <String, String>{
      'peer-1': 'hello',
      'grp-1': 'follow up',
    });
    expect(await store.loadPinnedMessages(), <String, Set<String>>{
      'peer-1': <String>{'m1', 'm2'},
    });
    expect(await store.loadRecalledMessageIds(), <String>{'m3'});
    expect(await store.loadPinnedChatOrder(), <String>['peer-1', 'grp-1']);
    expect(await store.loadArchivedGroups(), <String>{'grp-2'});

    final sp = await SharedPreferences.getInstance();
    for (final legacyKey in <String>[
      'chat.drafts.v1',
      'chat.pinned_messages',
      'chat.recalled_messages',
      'chat.pinned_chats',
      'chat.archived_groups',
    ]) {
      expect(sp.getString(legacyKey), isNull);
      expect(sp.getStringList(legacyKey), isNull);
    }
    for (final key in <String>[
      scopedChatPrefKey('chat.drafts.v2.', 'unknown'),
      scopedChatPrefKey('chat.pinned_messages.v2.', 'unknown'),
      scopedChatPrefKey('chat.recalled_messages.v2.', 'unknown'),
      scopedChatPrefKey('chat.pinned_chats.v2.', 'unknown'),
      scopedChatPrefKey('chat.archived_groups.v2.', 'unknown'),
    ]) {
      final migrated = sp.getString(key) ?? '';
      expect(migrated, isNotEmpty, reason: 'expected migrated ciphertext');
      final decoded = jsonDecode(migrated) as Map<String, Object?>;
      expect(decoded['v'], 1, reason: 'expected ciphertext envelope for $key');
    }
  });

  test(
      'drafts and pinned/recalled/archive chat metadata stay isolated across canonical API origins',
      () async {
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.saveDrafts(<String, String>{'peer-1': 'hello'});
    await store.savePinnedMessages(<String, Set<String>>{
      'peer-1': <String>{'m1'},
    });
    await store.saveRecalledMessageIds(<String>{'m2'});
    await store.savePinnedChatOrder(<String>['peer-1']);
    await store.saveArchivedGroups(<String>{'grp-1'});

    await sp.setString('base_url', 'https://api.two.example');
    expect(await store.loadDrafts(), isEmpty);
    expect(await store.loadPinnedMessages(), isEmpty);
    expect(await store.loadRecalledMessageIds(), isEmpty);
    expect(await store.loadPinnedChatOrder(), isEmpty);
    expect(await store.loadArchivedGroups(), isEmpty);

    await store.saveDrafts(<String, String>{'peer-2': 'follow up'});
    await store.savePinnedMessages(<String, Set<String>>{
      'peer-2': <String>{'m3'},
    });
    await store.saveRecalledMessageIds(<String>{'m4'});
    await store.savePinnedChatOrder(<String>['peer-2']);
    await store.saveArchivedGroups(<String>{'grp-2'});

    await sp.setString('base_url', 'https://api.one.example');
    expect(await store.loadDrafts(), <String, String>{'peer-1': 'hello'});
    expect(await store.loadPinnedMessages(), <String, Set<String>>{
      'peer-1': <String>{'m1'},
    });
    expect(await store.loadRecalledMessageIds(), <String>{'m2'});
    expect(await store.loadPinnedChatOrder(), <String>['peer-1']);
    expect(await store.loadArchivedGroups(), <String>{'grp-1'});

    await sp.setString('base_url', 'https://api.two.example');
    expect(await store.loadDrafts(), <String, String>{'peer-2': 'follow up'});
    expect(await store.loadPinnedMessages(), <String, Set<String>>{
      'peer-2': <String>{'m3'},
    });
    expect(await store.loadRecalledMessageIds(), <String>{'m4'});
    expect(await store.loadPinnedChatOrder(), <String>['peer-2']);
    expect(await store.loadArchivedGroups(), <String>{'grp-2'});
  });

  test('drafts honor explicit baseUrl override over global scope', () async {
    const scopedOrigin = 'https://api.two.example';
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.saveDrafts(
      <String, String>{'peer-2': 'follow up'},
      baseUrlOverride: scopedOrigin,
    );

    expect(await store.loadDrafts(), isEmpty);
    expect(
      await store.loadDrafts(baseUrlOverride: scopedOrigin),
      <String, String>{'peer-2': 'follow up'},
    );
  });

  test(
      'pinned and recalled chat metadata honor explicit baseUrl override over global scope',
      () async {
    const scopedOrigin = 'https://api.two.example';
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.savePinnedMessages(
      <String, Set<String>>{
        'peer-2': <String>{'m3'}
      },
      baseUrlOverride: scopedOrigin,
    );
    await store.saveRecalledMessageIds(
      <String>{'m4'},
      baseUrlOverride: scopedOrigin,
    );

    expect(await store.loadPinnedMessages(), isEmpty);
    expect(await store.loadRecalledMessageIds(), isEmpty);
    expect(
      await store.loadPinnedMessages(baseUrlOverride: scopedOrigin),
      <String, Set<String>>{
        'peer-2': <String>{'m3'}
      },
    );
    expect(
      await store.loadRecalledMessageIds(baseUrlOverride: scopedOrigin),
      <String>{'m4'},
    );
  });

  test(
      'pinned chat order and archived groups honor explicit baseUrl override over global scope',
      () async {
    const scopedOrigin = 'https://api.two.example';
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.savePinnedChatOrder(
      <String>['peer-2'],
      baseUrlOverride: scopedOrigin,
    );
    await store.saveArchivedGroups(
      <String>{'grp-2'},
      baseUrlOverride: scopedOrigin,
    );

    expect(await store.loadPinnedChatOrder(), isEmpty);
    expect(await store.loadArchivedGroups(), isEmpty);
    expect(
      await store.loadPinnedChatOrder(baseUrlOverride: scopedOrigin),
      <String>['peer-2'],
    );
    expect(
      await store.loadArchivedGroups(baseUrlOverride: scopedOrigin),
      <String>{'grp-2'},
    );
  });

  test(
      'legacy global drafts and pinned/recalled/archive chat metadata do not rebind into trusted canonical origins',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      'chat.drafts.v1': '{"peer-legacy":"hello"}',
      'chat.pinned_messages': '{"peer-legacy":["m1"]}',
      'chat.recalled_messages': <String>['m2'],
      'chat.pinned_chats': <String>['peer-legacy'],
      'chat.archived_groups': <String>['grp-legacy'],
    });

    final store = ChatLocalStore();
    expect(await store.loadDrafts(), isEmpty);
    expect(await store.loadPinnedMessages(), isEmpty);
    expect(await store.loadRecalledMessageIds(), isEmpty);
    expect(await store.loadPinnedChatOrder(), isEmpty);
    expect(await store.loadArchivedGroups(), isEmpty);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('chat.drafts.v1'), isNull);
    expect(sp.getString('chat.pinned_messages'), isNull);
    expect(sp.getStringList('chat.recalled_messages'), isNull);
    expect(sp.getStringList('chat.pinned_chats'), isNull);
    expect(sp.getStringList('chat.archived_groups'), isNull);
  });

  test(
      'direct/group transcript caches and group reactions persist under scoped encrypted keys',
      () async {
    final store = ChatLocalStore();
    const direct = ChatMessage(
      id: 'm1',
      senderId: 'peer-1',
      recipientId: 'me',
      senderPubKeyB64: 'pk',
      nonceB64: 'n',
      boxB64: 'b',
      createdAt: null,
    );
    final group = ChatGroupMessage(
      id: 'g1',
      groupId: 'grp-1',
      senderId: 'peer-1',
      text: 'hello',
      kind: 'text',
      nonceB64: 'n',
      boxB64: 'b',
      createdAt: DateTime.utc(2026, 3, 14, 13, 0, 0),
    );

    await store.saveMessages('peer-1', <ChatMessage>[direct]);
    await store.saveGroupMessages('grp-1', <ChatGroupMessage>[group]);
    await store.saveGroupMessageReactions('grp-1', <String, String>{
      'msg-1': '👍',
      'msg-2': '🔥',
    });

    expect(
      (await store.loadMessages('peer-1')).map((m) => m.id).toList(),
      <String>['m1'],
    );
    expect(
      (await store.loadGroupMessages('grp-1')).map((m) => m.id).toList(),
      <String>['g1'],
    );
    expect(
      await store.loadGroupMessageReactions('grp-1'),
      <String, String>{'msg-1': '👍', 'msg-2': '🔥'},
    );

    final sp = await SharedPreferences.getInstance();
    for (final key in <String>[
      scopedChatEntityPrefKey('chat.msgs.v2.', 'unknown', 'peer-1'),
      scopedChatEntityPrefKey('chat.grp.msgs.v2.', 'unknown', 'grp-1'),
      scopedChatEntityPrefKey(
        'chat.group_message_reactions.v2.',
        'unknown',
        'grp-1',
      ),
    ]) {
      final raw = sp.getString(key);
      expect(raw, isNotNull, reason: 'expected encrypted value for $key');
      expect((jsonDecode(raw!) as Map<String, Object?>)['v'], 1);
    }
  });

  test(
      'legacy plaintext direct/group transcript caches and group reactions migrate to scoped ciphertext on unknown origin',
      () async {
    final legacyDirect = ChatMessage(
      id: 'm-legacy',
      senderId: 'peer-legacy',
      recipientId: 'me',
      senderPubKeyB64: 'pk',
      nonceB64: 'n',
      boxB64: 'b',
      createdAt: DateTime.utc(2026, 3, 14, 12, 0, 0),
    );
    final legacyGroup = ChatGroupMessage(
      id: 'g-legacy',
      groupId: 'grp-legacy',
      senderId: 'peer-legacy',
      text: 'legacy hello',
      kind: 'text',
      nonceB64: 'n',
      boxB64: 'b',
      createdAt: DateTime.utc(2026, 3, 14, 13, 0, 0),
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      'chat.msgs.peer-legacy': jsonEncode(<Map<String, Object?>>[
        legacyDirect.toMap(),
      ]),
      'chat.grp.msgs.grp-legacy': jsonEncode(<Map<String, Object?>>[
        <String, Object?>{
          'id': legacyGroup.id,
          'group_id': legacyGroup.groupId,
          'sender_id': legacyGroup.senderId,
          'text': legacyGroup.text,
          'kind': legacyGroup.kind,
          'nonce_b64': legacyGroup.nonceB64,
          'box_b64': legacyGroup.boxB64,
          'attachment_b64': legacyGroup.attachmentB64,
          'attachment_mime': legacyGroup.attachmentMime,
          'voice_secs': legacyGroup.voiceSecs,
          'created_at': legacyGroup.createdAt?.toUtc().toIso8601String(),
          'expire_at': legacyGroup.expireAt?.toUtc().toIso8601String(),
        },
      ]),
      'chat.group_message_reactions.grp-legacy': '{"msg-1":"👍","msg-2":"🔥"}',
    });

    final store = ChatLocalStore();
    expect(
      (await store.loadMessages('peer-legacy')).map((m) => m.id).toList(),
      <String>['m-legacy'],
    );
    expect(
      (await store.loadGroupMessages('grp-legacy')).map((m) => m.id).toList(),
      <String>['g-legacy'],
    );
    expect(
      await store.loadGroupMessageReactions('grp-legacy'),
      <String, String>{'msg-1': '👍', 'msg-2': '🔥'},
    );

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('chat.msgs.peer-legacy'), isNull);
    expect(sp.getString('chat.grp.msgs.grp-legacy'), isNull);
    expect(sp.getString('chat.group_message_reactions.grp-legacy'), isNull);
    for (final key in <String>[
      scopedChatEntityPrefKey('chat.msgs.v2.', 'unknown', 'peer-legacy'),
      scopedChatEntityPrefKey('chat.grp.msgs.v2.', 'unknown', 'grp-legacy'),
      scopedChatEntityPrefKey(
        'chat.group_message_reactions.v2.',
        'unknown',
        'grp-legacy',
      ),
    ]) {
      final raw = sp.getString(key);
      expect(raw, isNotNull, reason: 'expected migrated ciphertext for $key');
      expect((jsonDecode(raw!) as Map<String, Object?>)['v'], 1);
    }
  });

  test(
      'direct/group transcript caches and group reactions stay isolated across canonical API origins',
      () async {
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.saveMessages(
      'peer-1',
      const <ChatMessage>[
        ChatMessage(
          id: 'm-one',
          senderId: 'peer-1',
          recipientId: 'me',
          senderPubKeyB64: 'pk',
          nonceB64: 'n',
          boxB64: 'b',
        ),
      ],
    );
    await store.saveGroupMessages(
      'grp-1',
      <ChatGroupMessage>[
        ChatGroupMessage(
          id: 'g-one',
          groupId: 'grp-1',
          senderId: 'peer-1',
          text: 'one',
          kind: 'text',
          nonceB64: 'n',
          boxB64: 'b',
          createdAt: DateTime.utc(2026, 3, 14, 13, 0, 0),
        ),
      ],
    );
    await store.saveGroupMessageReactions('grp-1', <String, String>{
      'msg-1': '👍',
    });

    await sp.setString('base_url', 'https://api.two.example');
    expect(await store.loadMessages('peer-1'), isEmpty);
    expect(await store.loadGroupMessages('grp-1'), isEmpty);
    expect(await store.loadGroupMessageReactions('grp-1'), isEmpty);

    await store.saveMessages(
      'peer-1',
      const <ChatMessage>[
        ChatMessage(
          id: 'm-two',
          senderId: 'peer-1',
          recipientId: 'me',
          senderPubKeyB64: 'pk',
          nonceB64: 'n',
          boxB64: 'b',
        ),
      ],
    );
    await store.saveGroupMessages(
      'grp-1',
      <ChatGroupMessage>[
        ChatGroupMessage(
          id: 'g-two',
          groupId: 'grp-1',
          senderId: 'peer-1',
          text: 'two',
          kind: 'text',
          nonceB64: 'n',
          boxB64: 'b',
          createdAt: DateTime.utc(2026, 3, 14, 14, 0, 0),
        ),
      ],
    );
    await store.saveGroupMessageReactions('grp-1', <String, String>{
      'msg-2': '🔥',
    });

    await sp.setString('base_url', 'https://api.one.example');
    expect(
      (await store.loadMessages('peer-1')).map((m) => m.id).toList(),
      <String>['m-one'],
    );
    expect(
      (await store.loadGroupMessages('grp-1')).map((m) => m.id).toList(),
      <String>['g-one'],
    );
    expect(
      await store.loadGroupMessageReactions('grp-1'),
      <String, String>{'msg-1': '👍'},
    );

    await sp.setString('base_url', 'https://api.two.example');
    expect(
      (await store.loadMessages('peer-1')).map((m) => m.id).toList(),
      <String>['m-two'],
    );
    expect(
      (await store.loadGroupMessages('grp-1')).map((m) => m.id).toList(),
      <String>['g-two'],
    );
    expect(
      await store.loadGroupMessageReactions('grp-1'),
      <String, String>{'msg-2': '🔥'},
    );
  });

  test(
      'direct/group transcript caches honor explicit baseUrl override over global scope',
      () async {
    const scopedOrigin = 'https://api.two.example';
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();
    const direct = ChatMessage(
      id: 'm-two',
      senderId: 'peer-1',
      recipientId: 'me',
      senderPubKeyB64: 'pk',
      nonceB64: 'n',
      boxB64: 'b',
    );
    final group = ChatGroupMessage(
      id: 'g-two',
      groupId: 'grp-1',
      senderId: 'peer-1',
      text: 'two',
      kind: 'text',
      nonceB64: 'n',
      boxB64: 'b',
      createdAt: DateTime.utc(2026, 3, 14, 14, 0, 0),
    );

    await sp.setString('base_url', 'https://api.one.example');
    await store.saveMessages(
      'peer-1',
      const <ChatMessage>[direct],
      baseUrlOverride: scopedOrigin,
    );
    await store.saveGroupMessages(
      'grp-1',
      <ChatGroupMessage>[group],
      baseUrlOverride: scopedOrigin,
    );

    expect(await store.loadMessages('peer-1'), isEmpty);
    expect(await store.loadGroupMessages('grp-1'), isEmpty);
    expect(
      (await store.loadMessages('peer-1', baseUrlOverride: scopedOrigin))
          .map((m) => m.id)
          .toList(),
      <String>['m-two'],
    );
    expect(
      (await store.loadGroupMessages('grp-1', baseUrlOverride: scopedOrigin))
          .map((m) => m.id)
          .toList(),
      <String>['g-two'],
    );

    await store.deleteMessages('peer-1', baseUrlOverride: scopedOrigin);
    await store.deleteGroupMessages('grp-1', baseUrlOverride: scopedOrigin);

    expect(
      await store.loadMessages('peer-1', baseUrlOverride: scopedOrigin),
      isEmpty,
    );
    expect(
      await store.loadGroupMessages('grp-1', baseUrlOverride: scopedOrigin),
      isEmpty,
    );
  });

  test(
      'group message reactions honor explicit baseUrl override over global scope',
      () async {
    const scopedOrigin = 'https://api.two.example';
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.saveGroupMessageReactions(
      'grp-1',
      <String, String>{'msg-2': '🔥'},
      baseUrlOverride: scopedOrigin,
    );

    expect(await store.loadGroupMessageReactions('grp-1'), isEmpty);
    expect(
      await store.loadGroupMessageReactions(
        'grp-1',
        baseUrlOverride: scopedOrigin,
      ),
      <String, String>{'msg-2': '🔥'},
    );
  });

  test(
      'legacy global direct/group transcript caches and group reactions do not rebind into trusted canonical origins',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      'chat.msgs.peer-legacy': jsonEncode(<Map<String, Object?>>[
        const ChatMessage(
          id: 'm-legacy',
          senderId: 'peer-legacy',
          recipientId: 'me',
          senderPubKeyB64: 'pk',
          nonceB64: 'n',
          boxB64: 'b',
        ).toMap(),
      ]),
      'chat.grp.msgs.grp-legacy': jsonEncode(<Map<String, Object?>>[
        <String, Object?>{
          'id': 'g-legacy',
          'group_id': 'grp-legacy',
          'sender_id': 'peer-legacy',
          'text': 'legacy hello',
          'kind': 'text',
          'nonce_b64': 'n',
          'box_b64': 'b',
          'created_at': DateTime.utc(2026, 3, 14, 13, 0, 0).toIso8601String(),
        },
      ]),
      'chat.group_message_reactions.grp-legacy': '{"msg-1":"👍"}',
    });

    final store = ChatLocalStore();
    expect(await store.loadMessages('peer-legacy'), isEmpty);
    expect(await store.loadGroupMessages('grp-legacy'), isEmpty);
    expect(await store.loadGroupMessageReactions('grp-legacy'), isEmpty);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('chat.msgs.peer-legacy'), isNull);
    expect(sp.getString('chat.grp.msgs.grp-legacy'), isNull);
    expect(sp.getString('chat.group_message_reactions.grp-legacy'), isNull);
    expect(
      sp.getString(
        scopedChatEntityPrefKey(
          'chat.msgs.v2.',
          'https://api.example.com',
          'peer-legacy',
        ),
      ),
      isNull,
    );
    expect(
      sp.getString(
        scopedChatEntityPrefKey(
          'chat.grp.msgs.v2.',
          'https://api.example.com',
          'grp-legacy',
        ),
      ),
      isNull,
    );
    expect(
      sp.getString(
        scopedChatEntityPrefKey(
          'chat.group_message_reactions.v2.',
          'https://api.example.com',
          'grp-legacy',
        ),
      ),
      isNull,
    );
  });

  test(
      'group seen, group names, unread counters, and official notif prefs are encrypted at rest',
      () async {
    final store = ChatLocalStore();
    await store.saveGroupSeen(<String, String>{
      'grp-1': '2026-03-13T00:00:00Z',
    });
    await store.saveGroupNames(<String, String>{'grp-1': 'Ops'});
    await store.saveUnread(<String, int>{'peer-1': 3});
    await store.setOfficialNotifMode(
      'peer-1',
      OfficialNotificationMode.summary,
    );

    expect(
      await store.loadGroupSeen(),
      <String, String>{'grp-1': '2026-03-13T00:00:00Z'},
    );
    expect(await store.loadGroupNames(), <String, String>{'grp-1': 'Ops'});
    expect(await store.loadUnread(), <String, int>{'peer-1': 3});
    expect(
      await store.loadOfficialNotifMode('peer-1'),
      OfficialNotificationMode.summary,
    );

    final sp = await SharedPreferences.getInstance();
    for (final key in <String>[
      scopedChatEntityPrefKey('chat.grp.seen.v3.', 'unknown', 'grp-1'),
      scopedChatPrefKey('chat.grp.names.v2.', 'unknown'),
      scopedChatEntityPrefKey('chat.unread.v3.', 'unknown', 'peer-1'),
      scopedChatPrefKey('official.notif.v2.', 'unknown'),
    ]) {
      final raw = sp.getString(key);
      expect(raw, isNotNull, reason: 'expected encrypted value for $key');
      final decoded = jsonDecode(raw!) as Map<String, Object?>;
      expect(decoded['v'], 1, reason: 'expected ciphertext envelope for $key');
    }
  });

  test(
      'legacy plaintext group seen, group names, unread counters, and official notif prefs migrate to ciphertext on load',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'chat.grp.seen': '{"grp-1":"2026-03-13T00:00:00Z"}',
      'chat.grp.names': '{"grp-1":"Ops"}',
      'chat.unread': '{"peer-1":3}',
      'official.notif': '{"peer-1":"summary"}',
    });

    final store = ChatLocalStore();
    expect(
      await store.loadGroupSeen(),
      <String, String>{'grp-1': '2026-03-13T00:00:00Z'},
    );
    expect(await store.loadGroupNames(), <String, String>{'grp-1': 'Ops'});
    expect(await store.loadUnread(), <String, int>{'peer-1': 3});
    expect(
      await store.loadOfficialNotifMode('peer-1'),
      OfficialNotificationMode.summary,
    );

    final sp = await SharedPreferences.getInstance();
    for (final legacyKey in <String>[
      'chat.grp.seen',
      'chat.grp.names',
      'chat.unread',
      'official.notif',
    ]) {
      expect(sp.getString(legacyKey), isNull);
    }
    for (final key in <String>[
      scopedChatEntityPrefKey('chat.grp.seen.v3.', 'unknown', 'grp-1'),
      scopedChatPrefKey('chat.grp.names.v2.', 'unknown'),
      scopedChatEntityPrefKey('chat.unread.v3.', 'unknown', 'peer-1'),
      scopedChatPrefKey('official.notif.v2.', 'unknown'),
    ]) {
      final migrated = sp.getString(key) ?? '';
      expect(migrated, isNotEmpty, reason: 'expected migrated ciphertext');
      final decoded = jsonDecode(migrated) as Map<String, Object?>;
      expect(decoded['v'], 1, reason: 'expected ciphertext envelope for $key');
    }
  });

  test(
      'group seen, group names, unread counters, and official notif prefs stay isolated across canonical API origins',
      () async {
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.saveGroupSeen(<String, String>{
      'grp-1': '2026-03-13T00:00:00Z',
    });
    await store.saveGroupNames(<String, String>{'grp-1': 'Ops'});
    await store.saveUnread(<String, int>{'peer-1': 3});
    await store.setOfficialNotifMode(
      'peer-1',
      OfficialNotificationMode.summary,
    );

    await sp.setString('base_url', 'https://api.two.example');
    expect(await store.loadGroupSeen(), isEmpty);
    expect(await store.loadGroupNames(), isEmpty);
    expect(await store.loadUnread(), isEmpty);
    expect(await store.loadOfficialNotifMode('peer-1'), isNull);

    await store.saveGroupSeen(<String, String>{
      'grp-2': '2026-03-14T00:00:00Z',
    });
    await store.saveGroupNames(<String, String>{'grp-2': 'Finance'});
    await store.saveUnread(<String, int>{'peer-2': 1});
    await store.setOfficialNotifMode(
      'peer-2',
      OfficialNotificationMode.full,
    );

    await sp.setString('base_url', 'https://api.one.example');
    expect(
      await store.loadGroupSeen(),
      <String, String>{'grp-1': '2026-03-13T00:00:00Z'},
    );
    expect(await store.loadGroupNames(), <String, String>{'grp-1': 'Ops'});
    expect(await store.loadUnread(), <String, int>{'peer-1': 3});
    expect(
      await store.loadOfficialNotifMode('peer-1'),
      OfficialNotificationMode.summary,
    );

    await sp.setString('base_url', 'https://api.two.example');
    expect(
      await store.loadGroupSeen(),
      <String, String>{'grp-2': '2026-03-14T00:00:00Z'},
    );
    expect(
      await store.loadGroupNames(),
      <String, String>{'grp-2': 'Finance'},
    );
    expect(await store.loadUnread(), <String, int>{'peer-2': 1});
    expect(
      await store.loadOfficialNotifMode('peer-2'),
      OfficialNotificationMode.full,
    );
  });

  test('official notif prefs honor explicit baseUrl override over global scope',
      () async {
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.setOfficialNotifMode(
      'peer-1',
      OfficialNotificationMode.summary,
      baseUrlOverride: 'https://api.two.example',
    );

    expect(
      await store.loadOfficialNotifMode(
        'peer-1',
        baseUrlOverride: 'https://api.two.example',
      ),
      OfficialNotificationMode.summary,
    );
    expect(await store.loadOfficialNotifMode('peer-1'), isNull);
    expect(
      (await SharedPreferences.getInstance()).getString(
        scopedChatPrefKey('official.notif.v2.', 'https://api.two.example'),
      ),
      isNotNull,
    );
  });

  test('unread counters honor explicit baseUrl override over global scope',
      () async {
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.saveUnread(
      <String, int>{'peer-1': 3},
      baseUrlOverride: 'https://api.two.example',
    );

    expect(
      await store.loadUnread(baseUrlOverride: 'https://api.two.example'),
      <String, int>{'peer-1': 3},
    );
    expect(await store.loadUnread(), isEmpty);
    expect(
      (await SharedPreferences.getInstance()).getString(
        scopedChatEntityPrefKey(
          'chat.unread.v3.',
          'https://api.two.example',
          'peer-1',
        ),
      ),
      isNotNull,
    );
  });

  test(
      'group seen and group names honor explicit baseUrl override over global scope',
      () async {
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.saveGroupSeen(
      <String, String>{'grp-1': '2026-03-13T00:00:00Z'},
      baseUrlOverride: 'https://api.two.example',
    );
    await store.saveGroupNames(
      <String, String>{'grp-1': 'Ops'},
      baseUrlOverride: 'https://api.two.example',
    );

    expect(
      await store.loadGroupSeen(baseUrlOverride: 'https://api.two.example'),
      <String, String>{'grp-1': '2026-03-13T00:00:00Z'},
    );
    expect(
      await store.loadGroupNames(baseUrlOverride: 'https://api.two.example'),
      <String, String>{'grp-1': 'Ops'},
    );
    expect(await store.loadGroupSeen(), isEmpty);
    expect(await store.loadGroupNames(), isEmpty);
    expect(
      (await SharedPreferences.getInstance()).getString(
        scopedChatEntityPrefKey(
          'chat.grp.seen.v3.',
          'https://api.two.example',
          'grp-1',
        ),
      ),
      isNotNull,
    );
    expect(
      (await SharedPreferences.getInstance()).getString(
        scopedChatPrefKey('chat.grp.names.v2.', 'https://api.two.example'),
      ),
      isNotNull,
    );
  });

  test('group notices honor explicit baseUrl override over global scope',
      () async {
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.saveGroupNotice(
      'grp-1',
      'Pinned incident bridge',
      baseUrlOverride: 'https://api.two.example',
    );

    expect(
      await store.loadGroupNotice(
        'grp-1',
        baseUrlOverride: 'https://api.two.example',
      ),
      'Pinned incident bridge',
    );
    expect(await store.loadGroupNotice('grp-1'), isNull);
    expect(
      (await SharedPreferences.getInstance()).getString(
        scopedChatEntityPrefKey(
          'chat.group_notice.v2.',
          'https://api.two.example',
          'grp-1',
        ),
      ),
      isNotNull,
    );
  });

  test('voice-played state honors explicit baseUrl override over global scope',
      () async {
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.markVoicePlayed(
      'peer-1',
      'voice-1',
      baseUrlOverride: 'https://api.two.example',
    );
    await store.markGroupVoicePlayed(
      'grp-1',
      'voice-2',
      baseUrlOverride: 'https://api.two.example',
    );

    expect(
      await store.loadVoicePlayed(
        'peer-1',
        baseUrlOverride: 'https://api.two.example',
      ),
      <String>{'voice-1'},
    );
    expect(
      await store.loadGroupVoicePlayed(
        'grp-1',
        baseUrlOverride: 'https://api.two.example',
      ),
      <String>{'voice-2'},
    );
    expect(await store.loadVoicePlayed('peer-1'), isEmpty);
    expect(await store.loadGroupVoicePlayed('grp-1'), isEmpty);
    expect(
      (await SharedPreferences.getInstance()).getString(
        scopedChatEntityPrefKey(
          'chat.voice.played.v2.',
          'https://api.two.example',
          'peer-1',
        ),
      ),
      isNotNull,
    );
    expect(
      (await SharedPreferences.getInstance()).getString(
        scopedChatEntityPrefKey(
          'chat.grp.voice.played.v2.',
          'https://api.two.example',
          'grp-1',
        ),
      ),
      isNotNull,
    );
  });

  test(
      'legacy global chat metadata does not rebind into trusted canonical origins',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      'chat.grp.seen': '{"grp-1":"2026-03-13T00:00:00Z"}',
      'chat.grp.names': '{"grp-1":"Ops"}',
      'chat.unread': '{"peer-1":3}',
      'official.notif': '{"peer-1":"summary"}',
    });

    final store = ChatLocalStore();
    expect(await store.loadGroupSeen(), isEmpty);
    expect(await store.loadGroupNames(), isEmpty);
    expect(await store.loadUnread(), isEmpty);
    expect(await store.loadOfficialNotifMode('peer-1'), isNull);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('chat.grp.seen'), isNull);
    expect(sp.getString('chat.grp.names'), isNull);
    expect(sp.getString('chat.unread'), isNull);
    expect(sp.getString('official.notif'), isNull);
  });

  test(
      'active peer, voice-played state, and group notices are encrypted at rest',
      () async {
    final store = ChatLocalStore();
    await store.setActivePeer('peer-1');
    await store.markVoicePlayed('peer-1', 'voice-1');
    await store.markGroupVoicePlayed('grp-1', 'voice-2');
    await store.saveGroupNotice('grp-1', 'Pinned incident bridge');

    expect(await store.loadActivePeer(), 'peer-1');
    expect(await store.loadVoicePlayed('peer-1'), <String>{'voice-1'});
    expect(await store.loadGroupVoicePlayed('grp-1'), <String>{'voice-2'});
    expect(await store.loadGroupNotice('grp-1'), 'Pinned incident bridge');

    final sp = await SharedPreferences.getInstance();
    for (final key in <String>[
      scopedChatPrefKey('chat.active.v2.', 'unknown'),
      scopedChatEntityPrefKey('chat.voice.played.v2.', 'unknown', 'peer-1'),
      scopedChatEntityPrefKey(
        'chat.grp.voice.played.v2.',
        'unknown',
        'grp-1',
      ),
      scopedChatEntityPrefKey('chat.group_notice.v2.', 'unknown', 'grp-1'),
    ]) {
      final raw = sp.getString(key);
      expect(raw, isNotNull, reason: 'expected encrypted value for $key');
      final decoded = jsonDecode(raw!) as Map<String, Object?>;
      expect(decoded['v'], 1, reason: 'expected ciphertext envelope for $key');
    }
  });

  test(
      'legacy plaintext active peer, voice-played state, and group notices migrate to ciphertext on load',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'chat.active': 'peer-legacy',
      'chat.voice.played.peer-legacy': <String>['voice-1', 'voice-2'],
      'chat.grp.voice.played.grp-legacy': <String>['voice-3'],
      'chat.group_notice.grp-legacy': 'Rotation tonight',
    });

    final store = ChatLocalStore();
    expect(await store.loadActivePeer(), 'peer-legacy');
    expect(
      await store.loadVoicePlayed('peer-legacy'),
      <String>{'voice-1', 'voice-2'},
    );
    expect(
      await store.loadGroupVoicePlayed('grp-legacy'),
      <String>{'voice-3'},
    );
    expect(await store.loadGroupNotice('grp-legacy'), 'Rotation tonight');

    final sp = await SharedPreferences.getInstance();
    for (final legacyKey in <String>[
      'chat.active',
      'chat.voice.played.peer-legacy',
      'chat.grp.voice.played.grp-legacy',
      'chat.group_notice.grp-legacy',
    ]) {
      expect(sp.getString(legacyKey), isNull);
    }
    for (final key in <String>[
      scopedChatPrefKey('chat.active.v2.', 'unknown'),
      scopedChatEntityPrefKey(
        'chat.voice.played.v2.',
        'unknown',
        'peer-legacy',
      ),
      scopedChatEntityPrefKey(
        'chat.grp.voice.played.v2.',
        'unknown',
        'grp-legacy',
      ),
      scopedChatEntityPrefKey(
        'chat.group_notice.v2.',
        'unknown',
        'grp-legacy',
      ),
    ]) {
      final migrated = sp.getString(key) ?? '';
      expect(migrated, isNotEmpty, reason: 'expected migrated ciphertext');
      final decoded = jsonDecode(migrated) as Map<String, Object?>;
      expect(decoded['v'], 1, reason: 'expected ciphertext envelope for $key');
    }
  });

  test(
      'active peer, voice-played state, and group notices stay isolated across canonical API origins',
      () async {
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.setActivePeer('peer-1');
    await store.markVoicePlayed('peer-1', 'voice-1');
    await store.markGroupVoicePlayed('grp-1', 'voice-2');
    await store.saveGroupNotice('grp-1', 'Pinned incident bridge');

    await sp.setString('base_url', 'https://api.two.example');
    expect(await store.loadActivePeer(), isNull);
    expect(await store.loadVoicePlayed('peer-1'), isEmpty);
    expect(await store.loadGroupVoicePlayed('grp-1'), isEmpty);
    expect(await store.loadGroupNotice('grp-1'), isNull);

    await store.setActivePeer('peer-2');
    await store.markVoicePlayed('peer-2', 'voice-3');
    await store.saveGroupNotice('grp-2', 'Finance notice');

    await sp.setString('base_url', 'https://api.one.example');
    expect(await store.loadActivePeer(), 'peer-1');
    expect(await store.loadVoicePlayed('peer-1'), <String>{'voice-1'});
    expect(await store.loadGroupVoicePlayed('grp-1'), <String>{'voice-2'});
    expect(await store.loadGroupNotice('grp-1'), 'Pinned incident bridge');

    await sp.setString('base_url', 'https://api.two.example');
    expect(await store.loadActivePeer(), 'peer-2');
    expect(await store.loadVoicePlayed('peer-2'), <String>{'voice-3'});
    expect(await store.loadGroupVoicePlayed('grp-1'), isEmpty);
    expect(await store.loadGroupNotice('grp-2'), 'Finance notice');
  });

  test(
      'active peer and chat themes honor explicit baseUrl override over global scope',
      () async {
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.setActivePeer(
      'peer-override',
      baseUrlOverride: 'https://api.two.example',
    );
    await store.saveChatThemes(
      <String, String>{'peer-override': 'green'},
      baseUrlOverride: 'https://api.two.example',
    );

    expect(
      await store.loadActivePeer(baseUrlOverride: 'https://api.two.example'),
      'peer-override',
    );
    expect(await store.loadActivePeer(), isNull);
    expect(
      await store.loadChatThemes(baseUrlOverride: 'https://api.two.example'),
      <String, String>{'peer-override': 'green'},
    );
    expect(await store.loadChatThemes(), isEmpty);
  });

  test(
      'legacy global active peer, voice-played state, and group notices do not rebind into trusted canonical origins',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      'chat.active': 'peer-legacy',
      'chat.voice.played.peer-legacy': <String>['voice-1', 'voice-2'],
      'chat.grp.voice.played.grp-legacy': <String>['voice-3'],
      'chat.group_notice.grp-legacy': 'Rotation tonight',
    });

    final store = ChatLocalStore();
    expect(await store.loadActivePeer(), isNull);
    expect(await store.loadVoicePlayed('peer-legacy'), isEmpty);
    expect(await store.loadGroupVoicePlayed('grp-legacy'), isEmpty);
    expect(await store.loadGroupNotice('grp-legacy'), isNull);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('chat.active'), isNull);
    expect(sp.getStringList('chat.voice.played.peer-legacy'), isNull);
    expect(sp.getStringList('chat.grp.voice.played.grp-legacy'), isNull);
    expect(sp.getString('chat.group_notice.grp-legacy'), isNull);
  });

  test(
      'official interaction flags and service-notification prefs are encrypted at rest',
      () async {
    final store = ChatLocalStore();
    await store.markOfficialAutofollowed('official-1');
    await store.markOfficialAutochat('peer-official-1');
    await store.markOfficialAutoreplyShown('peer-official-1');
    await store.saveServiceNotificationsHasUnread(true);
    await store.saveHideServiceNotificationsThread(true);

    expect(await store.hasOfficialAutofollowed('official-1'), isTrue);
    expect(await store.hasOfficialAutochat('peer-official-1'), isTrue);
    expect(await store.hasOfficialAutoreplyShown('peer-official-1'), isTrue);
    expect(await store.loadServiceNotificationsHasUnread(), isTrue);
    expect(await store.loadHideServiceNotificationsThread(), isTrue);

    final sp = await SharedPreferences.getInstance();
    for (final key in <String>[
      scopedChatEntityPrefKey(
        'official.autofollow.v2.',
        'unknown',
        'official-1',
      ),
      scopedChatEntityPrefKey(
        'official.autochat.v2.',
        'unknown',
        'peer-official-1',
      ),
      scopedChatEntityPrefKey(
        'official.autoreply.shown.v2.',
        'unknown',
        'peer-official-1',
      ),
      scopedChatPrefKey(
        'official_template_messages.has_unread.v2.',
        'unknown',
      ),
      scopedChatPrefKey(
        'chat.hide_service_notifications_thread.v2.',
        'unknown',
      ),
    ]) {
      final raw = sp.getString(key);
      expect(raw, isNotNull, reason: 'expected encrypted value for $key');
      final decoded = jsonDecode(raw!) as Map<String, Object?>;
      expect(decoded['v'], 1, reason: 'expected ciphertext envelope for $key');
    }
  });

  test(
      'legacy plaintext official interaction flags and service-notification prefs migrate to ciphertext on load',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'official.autofollow.official-legacy': true,
      'official.autochat.peer-official-legacy': true,
      'official.autoreply.shown.peer-official-legacy': true,
      'official_template_messages.has_unread': true,
      'chat.hide_service_notifications_thread': true,
    });

    final store = ChatLocalStore();
    expect(await store.hasOfficialAutofollowed('official-legacy'), isTrue);
    expect(await store.hasOfficialAutochat('peer-official-legacy'), isTrue);
    expect(
        await store.hasOfficialAutoreplyShown('peer-official-legacy'), isTrue);
    expect(await store.loadServiceNotificationsHasUnread(), isTrue);
    expect(await store.loadHideServiceNotificationsThread(), isTrue);

    final sp = await SharedPreferences.getInstance();
    for (final legacyKey in <String>[
      'official.autofollow.official-legacy',
      'official.autochat.peer-official-legacy',
      'official.autoreply.shown.peer-official-legacy',
      'official_template_messages.has_unread',
      'chat.hide_service_notifications_thread',
    ]) {
      expect(sp.getString(legacyKey), isNull);
    }
    for (final key in <String>[
      scopedChatEntityPrefKey(
        'official.autofollow.v2.',
        'unknown',
        'official-legacy',
      ),
      scopedChatEntityPrefKey(
        'official.autochat.v2.',
        'unknown',
        'peer-official-legacy',
      ),
      scopedChatEntityPrefKey(
        'official.autoreply.shown.v2.',
        'unknown',
        'peer-official-legacy',
      ),
      scopedChatPrefKey(
        'official_template_messages.has_unread.v2.',
        'unknown',
      ),
      scopedChatPrefKey(
        'chat.hide_service_notifications_thread.v2.',
        'unknown',
      ),
    ]) {
      final migrated = sp.getString(key) ?? '';
      expect(migrated, isNotEmpty, reason: 'expected migrated ciphertext');
      final decoded = jsonDecode(migrated) as Map<String, Object?>;
      expect(decoded['v'], 1, reason: 'expected ciphertext envelope for $key');
    }
  });

  test(
      'official interaction flags and service-notification prefs stay isolated across canonical API origins',
      () async {
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.markOfficialAutofollowed('official-1');
    await store.markOfficialAutochat('peer-official-1');
    await store.markOfficialAutoreplyShown('peer-official-1');
    await store.saveServiceNotificationsHasUnread(true);
    await store.saveHideServiceNotificationsThread(true);

    await sp.setString('base_url', 'https://api.two.example');
    expect(await store.hasOfficialAutofollowed('official-1'), isFalse);
    expect(await store.hasOfficialAutochat('peer-official-1'), isFalse);
    expect(await store.hasOfficialAutoreplyShown('peer-official-1'), isFalse);
    expect(await store.loadServiceNotificationsHasUnread(), isFalse);
    expect(await store.loadHideServiceNotificationsThread(), isFalse);

    await store.markOfficialAutofollowed('official-2');
    await store.markOfficialAutochat('peer-official-2');
    await store.markOfficialAutoreplyShown('peer-official-2');
    await store.saveServiceNotificationsHasUnread(true);

    await sp.setString('base_url', 'https://api.one.example');
    expect(await store.hasOfficialAutofollowed('official-1'), isTrue);
    expect(await store.hasOfficialAutochat('peer-official-1'), isTrue);
    expect(await store.hasOfficialAutoreplyShown('peer-official-1'), isTrue);
    expect(await store.loadServiceNotificationsHasUnread(), isTrue);
    expect(await store.loadHideServiceNotificationsThread(), isTrue);

    await sp.setString('base_url', 'https://api.two.example');
    expect(await store.hasOfficialAutofollowed('official-2'), isTrue);
    expect(await store.hasOfficialAutochat('peer-official-2'), isTrue);
    expect(await store.hasOfficialAutoreplyShown('peer-official-2'), isTrue);
    expect(await store.loadServiceNotificationsHasUnread(), isTrue);
    expect(await store.loadHideServiceNotificationsThread(), isFalse);
  });

  test(
      'official interaction flags honor explicit baseUrl override over global scope',
      () async {
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.markOfficialAutofollowed(
      'official-1',
      baseUrlOverride: 'https://api.two.example',
    );
    await store.markOfficialAutochat(
      'peer-official-1',
      baseUrlOverride: 'https://api.two.example',
    );
    await store.markOfficialAutoreplyShown(
      'peer-official-1',
      baseUrlOverride: 'https://api.two.example',
    );

    expect(
      await store.hasOfficialAutofollowed(
        'official-1',
        baseUrlOverride: 'https://api.two.example',
      ),
      isTrue,
    );
    expect(
      await store.hasOfficialAutochat(
        'peer-official-1',
        baseUrlOverride: 'https://api.two.example',
      ),
      isTrue,
    );
    expect(
      await store.hasOfficialAutoreplyShown(
        'peer-official-1',
        baseUrlOverride: 'https://api.two.example',
      ),
      isTrue,
    );
    expect(await store.hasOfficialAutofollowed('official-1'), isFalse);
    expect(await store.hasOfficialAutochat('peer-official-1'), isFalse);
    expect(await store.hasOfficialAutoreplyShown('peer-official-1'), isFalse);
    expect(
      (await SharedPreferences.getInstance()).getString(
        scopedChatEntityPrefKey(
          'official.autofollow.v2.',
          'https://api.two.example',
          'official-1',
        ),
      ),
      isNotNull,
    );
    expect(
      (await SharedPreferences.getInstance()).getString(
        scopedChatEntityPrefKey(
          'official.autochat.v2.',
          'https://api.two.example',
          'peer-official-1',
        ),
      ),
      isNotNull,
    );
    expect(
      (await SharedPreferences.getInstance()).getString(
        scopedChatEntityPrefKey(
          'official.autoreply.shown.v2.',
          'https://api.two.example',
          'peer-official-1',
        ),
      ),
      isNotNull,
    );
  });

  test(
      'service-notification prefs honor explicit baseUrl override over global scope',
      () async {
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.saveServiceNotificationsHasUnread(
      true,
      baseUrlOverride: 'https://api.two.example',
    );
    await store.saveHideServiceNotificationsThread(
      true,
      baseUrlOverride: 'https://api.two.example',
    );

    expect(
      await store.loadServiceNotificationsHasUnread(
        baseUrlOverride: 'https://api.two.example',
      ),
      isTrue,
    );
    expect(
      await store.loadHideServiceNotificationsThread(
        baseUrlOverride: 'https://api.two.example',
      ),
      isTrue,
    );

    expect(await store.loadServiceNotificationsHasUnread(), isFalse);
    expect(await store.loadHideServiceNotificationsThread(), isFalse);

    final scopedUnreadKey = scopedChatPrefKey(
      'official_template_messages.has_unread.v2.',
      'https://api.two.example',
    );
    final scopedHideKey = scopedChatPrefKey(
      'chat.hide_service_notifications_thread.v2.',
      'https://api.two.example',
    );
    expect((await SharedPreferences.getInstance()).getString(scopedUnreadKey),
        isNotNull);
    expect((await SharedPreferences.getInstance()).getString(scopedHideKey),
        isNotNull);
  });

  test(
      'legacy global official interaction flags and service-notification prefs do not rebind into trusted canonical origins',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      'official.autofollow.official-legacy': true,
      'official.autochat.peer-official-legacy': true,
      'official.autoreply.shown.peer-official-legacy': true,
      'official_template_messages.has_unread': true,
      'chat.hide_service_notifications_thread': true,
    });

    final store = ChatLocalStore();
    expect(await store.hasOfficialAutofollowed('official-legacy'), isFalse);
    expect(await store.hasOfficialAutochat('peer-official-legacy'), isFalse);
    expect(
      await store.hasOfficialAutoreplyShown('peer-official-legacy'),
      isFalse,
    );
    expect(await store.loadServiceNotificationsHasUnread(), isFalse);
    expect(await store.loadHideServiceNotificationsThread(), isFalse);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getBool('official.autofollow.official-legacy'), isNull);
    expect(sp.getBool('official.autochat.peer-official-legacy'), isNull);
    expect(sp.getBool('official.autoreply.shown.peer-official-legacy'), isNull);
    expect(sp.getBool('official_template_messages.has_unread'), isNull);
    expect(sp.getBool('chat.hide_service_notifications_thread'), isNull);
  });

  test('verified safety-state fingerprints are encrypted at rest', () async {
    final store = ChatLocalStore();
    await store.markVerified('peer-1', 'fp-verified-1');

    expect(await store.isVerified('peer-1', 'fp-verified-1'), isTrue);
    expect(await store.isVerified('peer-1', 'fp-other'), isFalse);

    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(
      scopedChatEntityPrefKey('chat.ver.v2.', 'unknown', 'peer-1'),
    );
    expect(raw, isNotNull);
    final decoded = jsonDecode(raw!) as Map<String, Object?>;
    expect(decoded['v'], 1);
  });

  test('legacy plaintext verified safety-state migrates to ciphertext on load',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'chat.ver.peer-legacy': 'fp-legacy',
    });

    final store = ChatLocalStore();
    expect(await store.isVerified('peer-legacy', 'fp-legacy'), isTrue);
    expect(await store.isVerified('peer-legacy', 'fp-other'), isFalse);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('chat.ver.peer-legacy'), isNull);
    final migrated = sp.getString(
          scopedChatEntityPrefKey('chat.ver.v2.', 'unknown', 'peer-legacy'),
        ) ??
        '';
    expect(migrated, isNotEmpty);
    final decoded = jsonDecode(migrated) as Map<String, Object?>;
    expect(decoded['v'], 1);
  });

  test(
      'verified safety-state fingerprints stay isolated across canonical API origins',
      () async {
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.markVerified('peer-1', 'fp-one');

    await sp.setString('base_url', 'https://api.two.example');
    expect(await store.isVerified('peer-1', 'fp-one'), isFalse);
    await store.markVerified('peer-1', 'fp-two');

    await sp.setString('base_url', 'https://api.one.example');
    expect(await store.isVerified('peer-1', 'fp-one'), isTrue);
    expect(await store.isVerified('peer-1', 'fp-two'), isFalse);

    await sp.setString('base_url', 'https://api.two.example');
    expect(await store.isVerified('peer-1', 'fp-two'), isTrue);
  });

  test(
      'verified safety-state honors explicit baseUrl override over global scope',
      () async {
    const scopedOrigin = 'https://api.two.example';
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.markVerified(
      'peer-1',
      'fp-two',
      baseUrlOverride: scopedOrigin,
    );

    expect(await store.isVerified('peer-1', 'fp-two'), isFalse);
    expect(
      await store.isVerified(
        'peer-1',
        'fp-two',
        baseUrlOverride: scopedOrigin,
      ),
      isTrue,
    );
    expect(
      (await SharedPreferences.getInstance()).getString(
        scopedChatEntityPrefKey('chat.ver.v2.', scopedOrigin, 'peer-1'),
      ),
      isNotNull,
    );
  });

  test(
      'legacy global verified safety-state does not rebind into trusted canonical origins',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      'chat.ver.peer-legacy': 'fp-legacy',
    });

    final store = ChatLocalStore();
    expect(await store.isVerified('peer-legacy', 'fp-legacy'), isFalse);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('chat.ver.peer-legacy'), isNull);
  });

  test('chat wallpaper themes are encrypted at rest', () async {
    final store = ChatLocalStore();
    await store.saveChatThemes(<String, String>{
      'peer-1': 'dark',
      'grp:grp-1': 'green',
    });

    expect(await store.loadChatThemes(), <String, String>{
      'peer-1': 'dark',
      'grp:grp-1': 'green',
    });

    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(
      scopedChatPrefKey('chat.wallpaper_theme.v2.', 'unknown'),
    );
    expect(raw, isNotNull);
    final decoded = jsonDecode(raw!) as Map<String, Object?>;
    expect(decoded['v'], 1);
  });

  test('legacy plaintext chat wallpaper themes migrate to ciphertext on load',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'chat.wallpaper_theme': '{"peer-legacy":"dark","grp:grp-legacy":"green"}',
    });

    final store = ChatLocalStore();
    expect(await store.loadChatThemes(), <String, String>{
      'peer-legacy': 'dark',
      'grp:grp-legacy': 'green',
    });

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('chat.wallpaper_theme'), isNull);
    final migrated = sp.getString(
          scopedChatPrefKey('chat.wallpaper_theme.v2.', 'unknown'),
        ) ??
        '';
    expect(migrated, isNotEmpty);
    final decoded = jsonDecode(migrated) as Map<String, Object?>;
    expect(decoded['v'], 1);
  });

  test('chat wallpaper themes stay isolated across canonical API origins',
      () async {
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.saveChatThemes(<String, String>{
      'peer-1': 'dark',
    });

    await sp.setString('base_url', 'https://api.two.example');
    expect(await store.loadChatThemes(), isEmpty);

    await store.saveChatThemes(<String, String>{
      'peer-2': 'green',
    });

    await sp.setString('base_url', 'https://api.one.example');
    expect(await store.loadChatThemes(), <String, String>{'peer-1': 'dark'});

    await sp.setString('base_url', 'https://api.two.example');
    expect(await store.loadChatThemes(), <String, String>{'peer-2': 'green'});
  });

  test(
      'legacy global chat wallpaper themes do not rebind into trusted canonical origins',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      'chat.wallpaper_theme': '{"peer-legacy":"dark","grp:grp-legacy":"green"}',
    });

    final store = ChatLocalStore();
    expect(await store.loadChatThemes(), isEmpty);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('chat.wallpaper_theme'), isNull);
  });

  test('chat notification preferences are persisted via scoped secure storage',
      () async {
    final store = ChatLocalStore();
    await store.setNotifyEnabled(false);
    await store.setNotifyPreview(true);
    await store.setNotifySound(false);
    await store.setNotifyVibrate(false);
    await store.setNotifyDndEnabled(true);
    await store.setNotifyDndSchedule(startMinutes: 23 * 60, endMinutes: 6 * 60);

    final prefs = await store.loadNotifyConfig();
    expect(
      prefs,
      (
        enabled: false,
        preview: true,
        sound: false,
        vibrate: false,
        dnd: true,
        dndStart: 23 * 60,
        dndEnd: 6 * 60,
      ),
    );

    final sp = await SharedPreferences.getInstance();
    expect(sp.getBool('chat.notify.enabled'), isNull);
    expect(sp.getBool('chat.notify.preview'), isNull);
    expect(sp.getBool('chat.notify.sound'), isNull);
    expect(sp.getBool('chat.notify.vibrate'), isNull);
    expect(sp.getBool('chat.notify.dnd'), isNull);
    expect(sp.getInt('chat.notify.dnd_start'), isNull);
    expect(sp.getInt('chat.notify.dnd_end'), isNull);
    expect(
      secStore.keys,
      containsAll(<String>[
        scopedChatPrefKey('notify.enabled.v2.', 'unknown'),
        scopedChatPrefKey('notify.preview.v2.', 'unknown'),
        scopedChatPrefKey('notify.sound.v2.', 'unknown'),
        scopedChatPrefKey('notify.vibrate.v2.', 'unknown'),
        scopedChatPrefKey('notify.dnd.v2.', 'unknown'),
        scopedChatPrefKey('notify.dnd_start.v2.', 'unknown'),
        scopedChatPrefKey('notify.dnd_end.v2.', 'unknown'),
      ]),
    );
  });

  test(
      'legacy plaintext chat notification preferences migrate off SharedPreferences',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'chat.notify.enabled': false,
      'chat.notify.preview': true,
      'chat.notify.sound': false,
      'chat.notify.vibrate': false,
      'chat.notify.dnd': true,
      'chat.notify.dnd_start': 1200,
      'chat.notify.dnd_end': 360,
    });

    final store = ChatLocalStore();
    final prefs = await store.loadNotifyConfig();
    expect(
      prefs,
      (
        enabled: false,
        preview: true,
        sound: false,
        vibrate: false,
        dnd: true,
        dndStart: 1200,
        dndEnd: 360,
      ),
    );

    final sp = await SharedPreferences.getInstance();
    expect(sp.getBool('chat.notify.enabled'), isNull);
    expect(sp.getBool('chat.notify.preview'), isNull);
    expect(sp.getBool('chat.notify.sound'), isNull);
    expect(sp.getBool('chat.notify.vibrate'), isNull);
    expect(sp.getBool('chat.notify.dnd'), isNull);
    expect(sp.getInt('chat.notify.dnd_start'), isNull);
    expect(sp.getInt('chat.notify.dnd_end'), isNull);
    expect(
      secStore.keys,
      containsAll(<String>[
        scopedChatPrefKey('notify.enabled.v2.', 'unknown'),
        scopedChatPrefKey('notify.preview.v2.', 'unknown'),
        scopedChatPrefKey('notify.sound.v2.', 'unknown'),
        scopedChatPrefKey('notify.vibrate.v2.', 'unknown'),
        scopedChatPrefKey('notify.dnd.v2.', 'unknown'),
        scopedChatPrefKey('notify.dnd_start.v2.', 'unknown'),
        scopedChatPrefKey('notify.dnd_end.v2.', 'unknown'),
      ]),
    );
  });

  test(
      'legacy global secure chat notification preferences migrate to scoped secure storage on unknown origin',
      () async {
    secStore['notify.enabled.v1'] = '0';
    secStore['notify.preview.v1'] = '1';
    secStore['notify.sound.v1'] = '0';
    secStore['notify.vibrate.v1'] = '0';
    secStore['notify.dnd.v1'] = '1';
    secStore['notify.dnd_start.v1'] = '1200';
    secStore['notify.dnd_end.v1'] = '360';

    final store = ChatLocalStore();
    final prefs = await store.loadNotifyConfig();
    expect(
      prefs,
      (
        enabled: false,
        preview: true,
        sound: false,
        vibrate: false,
        dnd: true,
        dndStart: 1200,
        dndEnd: 360,
      ),
    );

    expect(secStore.containsKey('notify.enabled.v1'), isFalse);
    expect(secStore.containsKey('notify.preview.v1'), isFalse);
    expect(secStore.containsKey('notify.sound.v1'), isFalse);
    expect(secStore.containsKey('notify.vibrate.v1'), isFalse);
    expect(secStore.containsKey('notify.dnd.v1'), isFalse);
    expect(secStore.containsKey('notify.dnd_start.v1'), isFalse);
    expect(secStore.containsKey('notify.dnd_end.v1'), isFalse);
    expect(
      secStore.keys,
      containsAll(<String>[
        scopedChatPrefKey('notify.enabled.v2.', 'unknown'),
        scopedChatPrefKey('notify.preview.v2.', 'unknown'),
        scopedChatPrefKey('notify.sound.v2.', 'unknown'),
        scopedChatPrefKey('notify.vibrate.v2.', 'unknown'),
        scopedChatPrefKey('notify.dnd.v2.', 'unknown'),
        scopedChatPrefKey('notify.dnd_start.v2.', 'unknown'),
        scopedChatPrefKey('notify.dnd_end.v2.', 'unknown'),
      ]),
    );
  });

  test(
      'chat notification preferences stay isolated across canonical API origins',
      () async {
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.setNotifyEnabled(false);
    await store.setNotifyPreview(true);
    await store.setNotifySound(false);
    await store.setNotifyVibrate(false);
    await store.setNotifyDndEnabled(true);
    await store.setNotifyDndSchedule(
      startMinutes: 23 * 60,
      endMinutes: 6 * 60,
    );

    await sp.setString('base_url', 'https://api.two.example');
    expect(
      await store.loadNotifyConfig(),
      (
        enabled: true,
        preview: false,
        sound: true,
        vibrate: true,
        dnd: false,
        dndStart: 22 * 60,
        dndEnd: 8 * 60,
      ),
    );

    await store.setNotifyEnabled(true);
    await store.setNotifyPreview(false);
    await store.setNotifySound(true);
    await store.setNotifyVibrate(true);
    await store.setNotifyDndEnabled(false);
    await store.setNotifyDndSchedule(
      startMinutes: 8 * 60,
      endMinutes: 20 * 60,
    );

    await sp.setString('base_url', 'https://api.one.example');
    expect(
      await store.loadNotifyConfig(),
      (
        enabled: false,
        preview: true,
        sound: false,
        vibrate: false,
        dnd: true,
        dndStart: 23 * 60,
        dndEnd: 6 * 60,
      ),
    );

    await sp.setString('base_url', 'https://api.two.example');
    expect(
      await store.loadNotifyConfig(),
      (
        enabled: true,
        preview: false,
        sound: true,
        vibrate: true,
        dnd: false,
        dndStart: 8 * 60,
        dndEnd: 20 * 60,
      ),
    );
  });

  test(
      'chat notification preferences honor explicit baseUrl override over global scope',
      () async {
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.setNotifyEnabled(
      false,
      baseUrlOverride: 'https://api.two.example',
    );
    await store.setNotifyPreview(
      true,
      baseUrlOverride: 'https://api.two.example',
    );
    await store.setNotifySound(
      false,
      baseUrlOverride: 'https://api.two.example',
    );
    await store.setNotifyVibrate(
      false,
      baseUrlOverride: 'https://api.two.example',
    );
    await store.setNotifyDndEnabled(
      true,
      baseUrlOverride: 'https://api.two.example',
    );
    await store.setNotifyDndSchedule(
      startMinutes: 23 * 60,
      endMinutes: 6 * 60,
      baseUrlOverride: 'https://api.two.example',
    );

    expect(
      await store.loadNotifyConfig(baseUrlOverride: 'https://api.two.example'),
      (
        enabled: false,
        preview: true,
        sound: false,
        vibrate: false,
        dnd: true,
        dndStart: 23 * 60,
        dndEnd: 6 * 60,
      ),
    );

    expect(
      await store.loadNotifyConfig(),
      (
        enabled: true,
        preview: false,
        sound: true,
        vibrate: true,
        dnd: false,
        dndStart: 22 * 60,
        dndEnd: 8 * 60,
      ),
    );

    expect(
      secStore.keys,
      containsAll(<String>[
        scopedChatPrefKey('notify.enabled.v2.', 'https://api.two.example'),
        scopedChatPrefKey('notify.preview.v2.', 'https://api.two.example'),
        scopedChatPrefKey('notify.sound.v2.', 'https://api.two.example'),
        scopedChatPrefKey('notify.vibrate.v2.', 'https://api.two.example'),
        scopedChatPrefKey('notify.dnd.v2.', 'https://api.two.example'),
        scopedChatPrefKey('notify.dnd_start.v2.', 'https://api.two.example'),
        scopedChatPrefKey('notify.dnd_end.v2.', 'https://api.two.example'),
      ]),
    );
    expect(
      secStore.keys.any(
        (key) => key.contains(
          scopedChatPrefKey('notify.enabled.v2.', 'https://api.one.example'),
        ),
      ),
      isFalse,
    );
  });

  test(
      'legacy global chat notification preferences do not rebind into trusted canonical origins',
      () async {
    secStore['notify.enabled.v1'] = '0';
    secStore['notify.preview.v1'] = '1';
    secStore['notify.sound.v1'] = '0';
    secStore['notify.vibrate.v1'] = '0';
    secStore['notify.dnd.v1'] = '1';
    secStore['notify.dnd_start.v1'] = '1200';
    secStore['notify.dnd_end.v1'] = '360';
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      'chat.notify.enabled': false,
      'chat.notify.preview': true,
      'chat.notify.sound': false,
      'chat.notify.vibrate': false,
      'chat.notify.dnd': true,
      'chat.notify.dnd_start': 1200,
      'chat.notify.dnd_end': 360,
    });

    final store = ChatLocalStore();
    expect(
      await store.loadNotifyConfig(),
      (
        enabled: true,
        preview: false,
        sound: true,
        vibrate: true,
        dnd: false,
        dndStart: 22 * 60,
        dndEnd: 8 * 60,
      ),
    );

    final sp = await SharedPreferences.getInstance();
    expect(sp.getBool('chat.notify.enabled'), isNull);
    expect(sp.getBool('chat.notify.preview'), isNull);
    expect(sp.getBool('chat.notify.sound'), isNull);
    expect(sp.getBool('chat.notify.vibrate'), isNull);
    expect(sp.getBool('chat.notify.dnd'), isNull);
    expect(sp.getInt('chat.notify.dnd_start'), isNull);
    expect(sp.getInt('chat.notify.dnd_end'), isNull);
    expect(secStore.containsKey('notify.enabled.v1'), isFalse);
    expect(secStore.containsKey('notify.preview.v1'), isFalse);
    expect(secStore.containsKey('notify.sound.v1'), isFalse);
    expect(secStore.containsKey('notify.vibrate.v1'), isFalse);
    expect(secStore.containsKey('notify.dnd.v1'), isFalse);
    expect(secStore.containsKey('notify.dnd_start.v1'), isFalse);
    expect(secStore.containsKey('notify.dnd_end.v1'), isFalse);
    expect(
      secStore.containsKey(
        scopedChatPrefKey('notify.enabled.v2.', 'https://api.example.com'),
      ),
      isFalse,
    );
  });

  test('clearNotifyPreferences removes notification prefs across all origins',
      () async {
    final store = ChatLocalStore();
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await store.setNotifyEnabled(false);
    await store.setNotifyPreview(true);
    await store.setNotifySound(false);
    await store.setNotifyVibrate(false);
    await store.setNotifyDndEnabled(true);
    await store.setNotifyDndSchedule(
      startMinutes: 23 * 60,
      endMinutes: 6 * 60,
    );

    await sp.setString('base_url', 'https://api.two.example');
    await store.setNotifyEnabled(true);
    await store.setNotifyPreview(false);
    await store.setNotifySound(true);
    await store.setNotifyVibrate(true);
    await store.setNotifyDndEnabled(false);
    await store.setNotifyDndSchedule(
      startMinutes: 8 * 60,
      endMinutes: 20 * 60,
    );

    await store.clearNotifyPreferences();

    await sp.setString('base_url', 'https://api.one.example');
    expect(
      await store.loadNotifyConfig(),
      (
        enabled: true,
        preview: false,
        sound: true,
        vibrate: true,
        dnd: false,
        dndStart: 22 * 60,
        dndEnd: 8 * 60,
      ),
    );

    await sp.setString('base_url', 'https://api.two.example');
    expect(
      await store.loadNotifyConfig(),
      (
        enabled: true,
        preview: false,
        sound: true,
        vibrate: true,
        dnd: false,
        dndStart: 22 * 60,
        dndEnd: 8 * 60,
      ),
    );
  });

  test('logout wipe clears account data and chat notification prefs', () async {
    const baseUrl = 'https://api.shamell.online';
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', baseUrl);
    await sp.setString('phone', '+963955000111');
    await saveStoredWalletId('w1');
    await saveStoredShamellUserId('ABCDEFGH');
    await saveAccountPrivilegeSnapshot(
      roles: <String>['admin'],
      isSuperadmin: true,
    );
    await saveStableDeviceId('install-1');
    await sp.setString('ui.theme_mode', 'dark');
    await saveRequireBiometricsPreference(true);

    // Seed chat secrets in secure storage.
    final store = ChatLocalStore();
    await store.saveGroupKey('grp-1', base64Encode(List<int>.filled(32, 3)));
    await store.saveGroupMessageReactions('grp-1', <String, String>{
      'msg-1': '👍',
    });
    await store.setActivePeer('peer-1');
    await store.markVoicePlayed('peer-1', 'voice-1');
    await store.markGroupVoicePlayed('grp-1', 'voice-2');
    await store.saveGroupNotice('grp-1', 'Pinned incident bridge');
    await store.markOfficialAutofollowed('official-1');
    await store.markOfficialAutochat('peer-official-1');
    await store.markOfficialAutoreplyShown('peer-official-1');
    await store.saveServiceNotificationsHasUnread(true);
    await store.saveHideServiceNotificationsThread(true);
    await store.markVerified('peer-1', 'fp-verified-1');
    await store.setNotifyEnabled(false);
    await store.setNotifyPreview(true);
    await store.setNotifySound(false);
    await store.setNotifyVibrate(false);
    await store.setNotifyDndEnabled(true);
    await store.setNotifyDndSchedule(
      startMinutes: 23 * 60,
      endMinutes: 6 * 60,
    );
    await store.saveChatThemes(<String, String>{
      'peer-1': 'dark',
      'grp:grp-1': 'green',
    });
    await store
        .saveGroupSeen(<String, String>{'grp-1': '2026-03-13T00:00:00Z'});
    await store.saveGroupNames(<String, String>{'grp-1': 'Ops'});
    await store.saveUnread(<String, int>{'peer-1': 3});
    await store.setOfficialNotifMode(
      'peer-1',
      OfficialNotificationMode.summary,
    );
    expect(secStore.keys.any((k) => k.startsWith('chat.')), isTrue);

    // Seed session cookie state and ensure it resolves.
    await setSessionTokenForBaseUrl(
      baseUrl,
      '0123456789abcdef0123456789abcdef',
    );
    expect(await getSessionTokenForBaseUrl(baseUrl), isNotNull);

    await wipeLocalAccountData(preserveDevicePrefs: true);

    final sp2 = await SharedPreferences.getInstance();
    expect(sp2.getString('base_url'), baseUrl);
    expect(sp2.getString(kStableDeviceIdPrefKey), isNull);
    expect(await loadStableDeviceId(), 'install-1');
    expect(sp2.getString('ui.theme_mode'), 'dark');
    expect(sp2.getBool(kRequireBiometricsPrefKey), isNull);
    expect(await loadRequireBiometricsPreference(), isTrue);
    expect(sp2.getBool('chat.notify.enabled'), isNull);
    expect(sp2.getBool('chat.notify.preview'), isNull);
    expect(sp2.getBool('chat.notify.sound'), isNull);
    expect(sp2.getBool('chat.notify.vibrate'), isNull);
    expect(sp2.getBool('chat.notify.dnd'), isNull);
    expect(sp2.getInt('chat.notify.dnd_start'), isNull);
    expect(sp2.getInt('chat.notify.dnd_end'), isNull);
    expect(
      await store.loadNotifyConfig(),
      (
        enabled: true,
        preview: false,
        sound: true,
        vibrate: true,
        dnd: false,
        dndStart: 22 * 60,
        dndEnd: 8 * 60,
      ),
    );

    expect(sp2.getString('wallet_id'), isNull);
    expect(await loadStoredWalletId(), isNull);
    expect(await loadStoredShamellUserId(), isNull);
    expect(sp2.getStringList('roles'), isNull);
    expect(sp2.getBool('is_superadmin'), isNull);
    expect(sp2.getString('phone'), isNull);
    expect(sp2.getString('chat.active'), isNull);
    expect(sp2.getString('chat.voice.played.peer-1'), isNull);
    expect(sp2.getString('chat.grp.voice.played.grp-1'), isNull);
    expect(sp2.getString('chat.group_notice.grp-1'), isNull);
    expect(sp2.getString('official.autofollow.official-1'), isNull);
    expect(sp2.getString('official.autochat.peer-official-1'), isNull);
    expect(sp2.getString('official.autoreply.shown.peer-official-1'), isNull);
    expect(sp2.getString('official_template_messages.has_unread'), isNull);
    expect(sp2.getString('chat.hide_service_notifications_thread'), isNull);
    expect(sp2.getString('chat.ver.peer-1'), isNull);
    expect(sp2.getString('chat.wallpaper_theme'), isNull);
    expect(sp2.getString('chat.group_message_reactions.grp-1'), isNull);
    expect(sp2.getString('chat.grp.seen'), isNull);
    expect(sp2.getString('chat.grp.names'), isNull);
    expect(sp2.getString('chat.unread'), isNull);
    expect(sp2.getString('official.notif'), isNull);
    final privileges = await loadAccountPrivilegeSnapshot();
    expect(privileges.roles, isEmpty);
    expect(privileges.isSuperadmin, isFalse);
    expect(await getSessionTokenForBaseUrl(baseUrl), isNull);
    expect(secStore.keys.any((k) => k.startsWith('chat.')), isFalse);
  });

  testWidgets('ChatInfo security actions require confirmation', (tester) async {
    bool marked = false;
    bool reset = false;
    // Force a taller-than-default test viewport. The default
    // 800x600 leaves the Safety / fingerprint ListTiles ~5 px past
    // the viewport so `tester.tap()` registers an off-screen warning
    // and silently misses, leaving the clipboard empty and the
    // test red. iPhone-15-Pro-ish viewport (~393×852 LP at 1.0 DPR)
    // is what the page is designed for — encode that explicitly so
    // the test reflects the production layout rather than the
    // accidentally-too-small Flutter default.
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: const [
          L10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ShamellChatInfoPage(
          myDisplayName: 'Me',
          displayName: 'Alice',
          peerId: 'AB12CD34',
          verified: false,
          peerFingerprint: 'peer-fp',
          myFingerprint: 'my-fp',
          safetyNumberFormatted: '12345 67890',
          safetyNumberRaw: '1234567890',
          onMarkVerified: () async => marked = true,
          onResetSession: () async => reset = true,
          onCreateGroupChat: () async {},
          onToggleCloseFriend: (_) async => true,
          onToggleMuted: (_) async {},
          onTogglePinned: (_) async {},
          onToggleHidden: (_) async {},
          onToggleBlocked: (_) async {},
          onOpenFavorites: () async {},
          onOpenMedia: () async {},
          onSearchInChat: () async {},
          onSaveRemarksTags: (_, __) async {},
          onSetTheme: (_) async {},
          onClearChatHistory: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Safety:'), findsOneWidget);
    expect(find.text('Mark verified'), findsOneWidget);

    await tester.tap(find.text('Mark verified'));
    await tester.pumpAndSettle();
    expect(find.text('Verify safety number'), findsOneWidget);

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(marked, isTrue);
    expect(find.text('Mark verified'), findsNothing);

    await tester.tap(find.text('Reset session'));
    await tester.pumpAndSettle();
    // "Reset session" appears as dialog title and in the action button; tap the button.
    await tester.tap(find.text('Reset session').last);
    await tester.pumpAndSettle();
    expect(reset, isTrue);
  });

  testWidgets('ChatInfo security copies auto-clear from clipboard',
      (tester) async {
    // Same fix as the "actions require confirmation" sibling above —
    // the page renders ~605px tall on a 800×600 default viewport, so
    // a tap on the second copy-icon misses by 5 px. Force a phone-
    // tall viewport that matches production layout.
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var clipboardText = '';
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            final args = Map<String, dynamic>.from(
                call.arguments as Map<Object?, Object?>);
            clipboardText = (args['text'] ?? '').toString();
            return null;
          case 'Clipboard.getData':
            return <String, dynamic>{'text': clipboardText};
          default:
            return null;
        }
      },
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: const [
          L10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ShamellChatInfoPage(
          myDisplayName: 'Me',
          displayName: 'Alice',
          peerId: 'AB12CD34',
          verified: false,
          peerFingerprint: 'peer-fp',
          myFingerprint: 'my-fp',
          safetyNumberFormatted: '12345 67890',
          safetyNumberRaw: '1234567890',
          onMarkVerified: () async {},
          onResetSession: () async {},
          onCreateGroupChat: () async {},
          onToggleCloseFriend: (_) async => true,
          onToggleMuted: (_) async {},
          onTogglePinned: (_) async {},
          onToggleHidden: (_) async {},
          onToggleBlocked: (_) async {},
          onOpenFavorites: () async {},
          onOpenMedia: () async {},
          onSearchInChat: () async {},
          onSaveRemarksTags: (_, __) async {},
          onSetTheme: (_) async {},
          onClearChatHistory: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Safety:'));
    await tester.pump();
    expect(clipboardText, '1234567890');

    await tester.pump(shamellSensitiveClipboardClearAfter());
    await tester.pump();
    expect(clipboardText, isEmpty);

    expect(find.byIcon(Icons.copy), findsNWidgets(3));
    await tester.tap(find.byIcon(Icons.copy).at(1));
    await tester.pump();
    expect(clipboardText, 'peer-fp');

    await tester.pump(shamellSensitiveClipboardClearAfter());
    await tester.pump();
    expect(clipboardText, isEmpty);
  });
}
