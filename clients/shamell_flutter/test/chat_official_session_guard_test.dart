import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/capabilities.dart';
import 'package:shamell_flutter/core/chat/chat_models.dart';
import 'package:shamell_flutter/core/chat/chat_service.dart';
import 'package:shamell_flutter/core/chat/shamell_chat_page.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';

const _baseUrl = 'https://api.example.com';
const _invalidBaseUrl = 'https://evil.test@api.example.com/app';

String _scopedChatPrefKey(String prefix, String scope) {
  final suffix = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
  return '$prefix$suffix';
}

const _officialCaps = ShamellCapabilities(
  chat: true,
  payments: true,
  friends: true,
  moments: false,
  officialAccounts: true,
  channels: false,
  serviceNotifications: false,
  paymentsPhoneTargets: false,
);

const _officialServiceCaps = ShamellCapabilities(
  chat: true,
  payments: true,
  friends: true,
  moments: false,
  officialAccounts: true,
  channels: false,
  serviceNotifications: true,
  paymentsPhoneTargets: false,
);

Future<void> _pumpChatPage(
  WidgetTester tester, {
  required http.Client client,
  http.Client? accountClient,
  required VoidCallback onCritical,
  String baseUrl = _baseUrl,
  ShamellCapabilities capabilities = _officialCaps,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ShamellChatPage(
        baseUrl: baseUrl,
        runStartupTasks: false,
        officialHttpClient: client,
        accountHttpClient: accountClient,
        onCriticalOfficialSessionFailure: onCritical,
      ),
    ),
  );
  await tester.pump();
  final dynamic state = tester.state(find.byType(ShamellChatPage));
  state.debugSetCapabilities(capabilities);
}

Future<void> _saveIdentity({
  String baseUrl = _baseUrl,
  String deviceId = 'device_self',
}) async {
  await ChatLocalStore().saveIdentity(
    ChatIdentity(
      id: deviceId,
      publicKeyB64: 'pubkey',
      privateKeyB64: 'privkey',
      fingerprint: 'fingerprint',
    ),
    baseUrlOverride: baseUrl,
  );
}

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
  });

  testWidgets('ShamellChatPage reauths on critical official follow toggle',
      (tester) async {
    var reauthTriggered = false;
    await setSessionTokenForBaseUrl(
      _baseUrl,
      '0123456789abcdef0123456789abcdef',
    );
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://api.example.com/official_accounts/official_1/follow',
      );
      expect(request.method, 'POST');
      final idempotency = request.headers['Idempotency-Key'] ??
          request.headers['idempotency-key'];
      expect(idempotency, isNotNull);
      expect(idempotency!, startsWith('official-follow-'));
      return http.Response('{"detail":"auth session required"}', 401);
    });

    await _pumpChatPage(
      tester,
      client: client,
      onCritical: () => reauthTriggered = true,
    );

    final dynamic state = tester.state(find.byType(ShamellChatPage));
    await state.debugToggleOfficialFollowFromChat(
      officialId: 'official_1',
      kind: 'service',
      followed: false,
    );
    await tester.pump();

    expect(reauthTriggered, isTrue);
  });

  testWidgets(
      'ShamellChatPage official follow sends localhost client-ip hint and cookie',
      (tester) async {
    const baseUrl = 'http://localhost:8080';
    const sessionToken = '0123456789abcdef0123456789abcdef';
    await setSessionTokenForBaseUrl(baseUrl, sessionToken);
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'http://localhost:8080/official_accounts/official_1/follow',
      );
      expect(request.method, 'POST');
      final idempotency = request.headers['Idempotency-Key'] ??
          request.headers['idempotency-key'];
      expect(idempotency, isNotNull);
      expect(idempotency!, startsWith('official-follow-'));
      expect(request.headers['cookie'], '__Host-sa_session=$sessionToken');
      expect(request.headers['x-shamell-client-ip'], '127.0.0.1');
      return http.Response('{}', 200);
    });

    await _pumpChatPage(
      tester,
      client: client,
      baseUrl: baseUrl,
      onCritical: () {},
    );

    final dynamic state = tester.state(find.byType(ShamellChatPage));
    await state.debugToggleOfficialFollowFromChat(
      officialId: 'official_1',
      kind: 'service',
      followed: false,
    );
    await tester.pump();
  });

  testWidgets('ShamellChatPage reauths on critical official peer lookup',
      (tester) async {
    var reauthTriggered = false;
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://api.example.com/official_accounts?followed_only=false&chat_peer_id=peer_1',
      );
      return http.Response('{"detail":"auth session required"}', 401);
    });

    await _pumpChatPage(
      tester,
      client: client,
      onCritical: () => reauthTriggered = true,
    );

    final dynamic state = tester.state(find.byType(ShamellChatPage));
    await state.debugLoadOfficialForPeer('peer_1');
    await tester.pump();

    expect(reauthTriggered, isTrue);
  });

  testWidgets('ShamellChatPage reauths on critical official peers sync',
      (tester) async {
    var reauthTriggered = false;
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://api.example.com/official_accounts?followed_only=false&has_chat_peer=true&limit=200',
      );
      return http.Response('{"detail":"auth session required"}', 401);
    });

    await _pumpChatPage(
      tester,
      client: client,
      onCritical: () => reauthTriggered = true,
    );

    final dynamic state = tester.state(find.byType(ShamellChatPage));
    await state.debugLoadOfficialPeers();
    await tester.pump();

    expect(reauthTriggered, isTrue);
  });

  testWidgets('ShamellChatPage paginates official peers sync across slices',
      (tester) async {
    final requests = <Uri>[];
    final firstPage = List.generate(200, (index) {
      return <String, Object?>{
        'id': 'official_${index.toString().padLeft(3, '0')}',
        'name': 'Official ${index.toString().padLeft(3, '0')}',
        'chat_peer_id': 'peer_${index.toString().padLeft(3, '0')}',
        'featured': index == 0,
        'followed': index == 199,
        'last_item': index == 199
            ? <String, Object?>{'ts': '2026-03-18T10:00:00Z'}
            : null,
      };
    });
    final client = MockClient((request) async {
      requests.add(request.url);
      if (request.url.path != '/official_accounts') {
        fail('unexpected request: ${request.url}');
      }
      final beforeId = request.url.queryParameters['before_id'];
      if (beforeId == null) {
        expect(request.url.queryParameters['followed_only'], 'false');
        expect(request.url.queryParameters['has_chat_peer'], 'true');
        expect(request.url.queryParameters['limit'], '200');
        return http.Response(
          jsonEncode(<String, Object?>{'accounts': firstPage}),
          200,
        );
      }
      expect(beforeId, 'official_199');
      expect(request.url.queryParameters['before_featured'], 'false');
      expect(request.url.queryParameters['before_name'], 'Official 199');
      return http.Response(
        jsonEncode(<String, Object?>{
          'accounts': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'official_200',
              'name': 'Official 200',
              'chat_peer_id': 'peer_200',
              'featured': false,
              'followed': true,
              'last_item': <String, Object?>{'ts': '2026-03-19T10:00:00Z'},
            },
          ],
        }),
        200,
      );
    });

    await _pumpChatPage(
      tester,
      client: client,
      onCritical: () {},
    );

    final dynamic state = tester.state(find.byType(ShamellChatPage));
    await state.debugLoadOfficialPeers();
    await tester.pump();

    expect(requests, hasLength(2));
    final Map<String, Object?> peerState = state.debugOfficialPeerState();
    expect(peerState['officialPeerIds'], contains('peer_200'));
    expect(peerState['officialPeerUnreadFeeds'], contains('peer_200'));
    expect(peerState['featuredOfficialPeerIds'], contains('peer_000'));
    expect(
      (peerState['officialPeerToAccountId'] as Map<String, String>)['peer_200'],
      'official_200',
    );
  });

  testWidgets(
      'ShamellChatPage accepts minimal public official auto-reply text shape',
      (tester) async {
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://api.example.com/official_accounts/official_1/auto_replies',
      );
      return http.Response('{"text":"Welcome to SyrChat"}', 200);
    });

    await _pumpChatPage(
      tester,
      client: client,
      onCritical: () {},
    );

    final dynamic state = tester.state(find.byType(ShamellChatPage));
    final List<Map<String, dynamic>> rules =
        await state.debugLoadOfficialAutoReplies('official_1');

    expect(rules, <Map<String, dynamic>>[
      <String, dynamic>{'text': 'Welcome to SyrChat'},
    ]);
  });

  testWidgets(
      'ShamellChatPage keeps legacy public official auto-reply rules fallback',
      (tester) async {
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://api.example.com/official_accounts/official_1/auto_replies',
      );
      return http.Response(
        '{"rules":[{"text":"Welcome to SyrChat"}]}',
        200,
      );
    });

    await _pumpChatPage(
      tester,
      client: client,
      onCritical: () {},
    );

    final dynamic state = tester.state(find.byType(ShamellChatPage));
    final List<Map<String, dynamic>> rules =
        await state.debugLoadOfficialAutoReplies('official_1');

    expect(rules, <Map<String, dynamic>>[
      <String, dynamic>{'text': 'Welcome to SyrChat'},
    ]);
  });

  testWidgets(
      'ShamellChatPage reauths on critical official notification modes sync',
      (tester) async {
    var reauthTriggered = false;
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://api.example.com/official_accounts/notifications?official_ids=official_1',
      );
      return http.Response('{"detail":"auth session required"}', 401);
    });

    await _pumpChatPage(
      tester,
      client: client,
      onCritical: () => reauthTriggered = true,
    );

    final dynamic state = tester.state(find.byType(ShamellChatPage));
    await state.debugSyncOfficialNotificationModesFromServer(
      <String, String>{'peer_1': 'official_1'},
    );
    await tester.pump();

    expect(reauthTriggered, isTrue);
  });

  testWidgets(
      'ShamellChatPage resets missing official notification modes to full on sync',
      (tester) async {
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://api.example.com/official_accounts/notifications?official_ids=official_1',
      );
      return http.Response('{"modes":{}}', 200);
    });

    await _pumpChatPage(
      tester,
      client: client,
      onCritical: () {},
    );

    final dynamic state = tester.state(find.byType(ShamellChatPage));
    await state.debugSetStoredOfficialNotificationMode(
      'peer_1',
      OfficialNotificationMode.muted,
    );
    expect(
      await state.debugLoadStoredOfficialNotificationMode('peer_1'),
      'muted',
    );

    await state.debugSyncOfficialNotificationModesFromServer(
      <String, String>{'peer_1': 'official_1'},
    );
    await tester.pump();

    expect(
      await state.debugLoadStoredOfficialNotificationMode('peer_1'),
      'full',
    );
  });

  testWidgets(
      'ShamellChatPage resets local official notification state on unfollow',
      (tester) async {
    await setSessionTokenForBaseUrl(
      _baseUrl,
      '0123456789abcdef0123456789abcdef',
    );
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://api.example.com/official_accounts/official_1/unfollow',
      );
      expect(request.method, 'POST');
      return http.Response('{"ok":true}', 200);
    });

    final store = ChatLocalStore();
    await store.saveContacts(
      const <ChatContact>[
        ChatContact(
          id: 'peer-official',
          publicKeyB64: 'pk',
          fingerprint: 'fp',
          name: 'Official',
          muted: true,
        ),
      ],
      baseUrlOverride: _baseUrl,
    );
    await store.setOfficialNotifMode(
      'peer-official',
      OfficialNotificationMode.muted,
    );

    await _pumpChatPage(
      tester,
      client: client,
      onCritical: () {},
    );

    final dynamic state = tester.state(find.byType(ShamellChatPage));
    await state.debugToggleOfficialFollowFromChat(
      officialId: 'official_1',
      kind: 'service',
      followed: true,
    );
    await tester.pump();

    expect(
      await state.debugLoadStoredOfficialNotificationMode('peer-official'),
      'full',
    );
    final contacts = await store.loadContacts(baseUrlOverride: _baseUrl);
    expect(contacts.singleWhere((c) => c.id == 'peer-official').muted, isFalse);
  });

  testWidgets(
      'ShamellChatPage reads stored official notification mode from explicit baseUrl scope',
      (tester) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    final store = ChatLocalStore();
    await store.setOfficialNotifMode(
      'peer-official',
      OfficialNotificationMode.summary,
      baseUrlOverride: _baseUrl,
    );

    await _pumpChatPage(
      tester,
      client: MockClient((_) async => http.Response('{}', 200)),
      onCritical: () {},
    );

    final dynamic state = tester.state(find.byType(ShamellChatPage));
    expect(
      await state.debugLoadStoredOfficialNotificationMode('peer-official'),
      'summary',
    );
  });

  testWidgets('ShamellChatPage loads chat themes from explicit baseUrl scope',
      (tester) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    final store = ChatLocalStore();
    await store.saveChatThemes(
      <String, String>{'peer-themed': 'green'},
      baseUrlOverride: _baseUrl,
    );

    await _pumpChatPage(
      tester,
      client: MockClient((_) async => http.Response('{}', 200)),
      onCritical: () {},
    );

    final dynamic state = tester.state(find.byType(ShamellChatPage));
    await state.debugLoadChatThemes();
    await tester.pump();

    expect(state.debugChatThemeForPeer('peer-themed'), 'green');
  });

  testWidgets(
      'ShamellChatPage loads and saves notify preview in explicit baseUrl scope',
      (tester) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    final store = ChatLocalStore();
    await store.setNotifyPreview(true);
    await store.setNotifyPreview(false, baseUrlOverride: _baseUrl);

    await _pumpChatPage(
      tester,
      client: MockClient((_) async => http.Response('{}', 200)),
      onCritical: () {},
    );

    final dynamic state = tester.state(find.byType(ShamellChatPage));
    expect(state.debugNotifyPreviewEnabled(), isFalse);

    await state.debugSetNotifyPreview(false);

    expect(
      await store.loadNotifyPreview(baseUrlOverride: _baseUrl),
      isFalse,
    );
    expect(await store.loadNotifyPreview(), isTrue);
    expect(
      secStore[_scopedChatPrefKey('notify.preview.v2.', _baseUrl)],
      '0',
    );
  });

  testWidgets(
      'ShamellChatPage clears auto-follow markers on unfollow so service autofollow can follow again',
      (tester) async {
    final requests = <String>[];
    await setSessionTokenForBaseUrl(
      _baseUrl,
      '0123456789abcdef0123456789abcdef',
    );
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url}');
      return http.Response('{"ok":true}', 200);
    });

    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', _baseUrl);
    final store = ChatLocalStore();
    await store.markOfficialAutofollowed('official_1');
    await store.markOfficialAutochat('peer-official');
    await store.markOfficialAutoreplyShown('peer-official');

    await _pumpChatPage(
      tester,
      client: client,
      onCritical: () {},
    );

    final dynamic state = tester.state(find.byType(ShamellChatPage));
    await state.debugToggleOfficialFollowFromChat(
      officialId: 'official_1',
      kind: 'service',
      followed: true,
    );
    await tester.pump();

    await state.debugEnsureServiceOfficialFollow(
      officialId: 'official_1',
      chatPeerId: 'peer-official',
    );
    await tester.pump();

    expect(
      requests,
      <String>[
        'POST https://api.example.com/official_accounts/official_1/unfollow',
        'POST https://api.example.com/official_accounts/official_1/follow',
      ],
    );
  });

  testWidgets('ShamellChatPage reauths on critical service official autofollow',
      (tester) async {
    var reauthTriggered = false;
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://api.example.com/official_accounts/official_1/follow',
      );
      expect(request.method, 'POST');
      final idempotency = request.headers['Idempotency-Key'] ??
          request.headers['idempotency-key'];
      expect(idempotency, isNotNull);
      expect(idempotency!, startsWith('official-follow-'));
      return http.Response('{"detail":"auth session required"}', 401);
    });

    await _pumpChatPage(
      tester,
      client: client,
      onCritical: () => reauthTriggered = true,
    );

    final dynamic state = tester.state(find.byType(ShamellChatPage));
    await state.debugEnsureServiceOfficialFollow(
      officialId: 'official_1',
      chatPeerId: 'peer_1',
    );
    await tester.pump();

    expect(reauthTriggered, isTrue);
  });

  testWidgets(
      'ShamellChatPage skips malformed base-url network dispatch for official follow toggle',
      (tester) async {
    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url}');
      return http.Response('{}', 200);
    });

    await _pumpChatPage(
      tester,
      client: client,
      baseUrl: _invalidBaseUrl,
      onCritical: () {},
    );

    final dynamic state = tester.state(find.byType(ShamellChatPage));
    await state.debugToggleOfficialFollowFromChat(
      officialId: 'official_1',
      kind: 'service',
      followed: false,
    );
    await tester.pump();

    expect(requests, isEmpty);
  });

  testWidgets(
      'ShamellChatPage skips malformed base-url network dispatch for official peer lookup',
      (tester) async {
    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url}');
      return http.Response('{}', 200);
    });

    await _pumpChatPage(
      tester,
      client: client,
      baseUrl: _invalidBaseUrl,
      onCritical: () {},
    );

    final dynamic state = tester.state(find.byType(ShamellChatPage));
    await state.debugLoadOfficialForPeer('peer_1');
    await tester.pump();

    expect(requests, isEmpty);
  });

  testWidgets(
      'ShamellChatPage scopes official notification mode sync to loaded official accounts',
      (tester) async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      return http.Response('{"modes":{}}', 200);
    });

    await _pumpChatPage(
      tester,
      client: client,
      onCritical: () {},
    );

    final dynamic state = tester.state(find.byType(ShamellChatPage));
    await state.debugSyncOfficialNotificationModesFromServer(
      <String, String>{
        'peer_b': 'official_2',
        'peer_a': 'official_1',
        'peer_dup': 'official_2',
      },
    );
    await tester.pump();

    expect(requests, hasLength(1));
    expect(
      requests.single.toString(),
      'https://api.example.com/official_accounts/notifications?official_ids=official_1%2Cofficial_2',
    );
  });

  testWidgets(
      'ShamellChatPage skips malformed base-url network dispatch for official notification modes sync',
      (tester) async {
    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url}');
      return http.Response('{}', 200);
    });

    await _pumpChatPage(
      tester,
      client: client,
      baseUrl: _invalidBaseUrl,
      onCritical: () {},
    );

    final dynamic state = tester.state(find.byType(ShamellChatPage));
    await state.debugSyncOfficialNotificationModesFromServer(
      <String, String>{'peer_1': 'official_1'},
    );
    await tester.pump();

    expect(requests, isEmpty);
  });

  testWidgets(
      'ShamellChatPage skips malformed base-url network dispatch for service notifications badge',
      (tester) async {
    final requests = <String>[];
    final accountClient = MockClient((request) async {
      requests.add('${request.method} ${request.url}');
      return http.Response('{}', 200);
    });

    await _pumpChatPage(
      tester,
      client: MockClient((_) async => http.Response('{}', 200)),
      accountClient: accountClient,
      baseUrl: _invalidBaseUrl,
      capabilities: _officialServiceCaps,
      onCritical: () {},
    );

    final dynamic state = tester.state(find.byType(ShamellChatPage));
    await state.debugLoadServiceNotificationsBadge();
    await tester.pump();

    expect(requests, isEmpty);
  });

  testWidgets('ShamellChatPage limits devices summary probe to two devices',
      (tester) async {
    await _saveIdentity(deviceId: 'device_self');
    final officialClient = MockClient((request) async {
      fail('unexpected official request: ${request.url}');
    });
    late Uri requestUri;
    final accountClient = MockClient((request) async {
      requestUri = request.url;
      return http.Response(
        jsonEncode(<String, Object?>{
          'devices': <Map<String, Object?>>[
            <String, Object?>{
              'device_id': 'device_self',
              'device_type': 'phone',
            },
            <String, Object?>{
              'device_id': 'device_other',
              'platform': 'tablet',
            },
          ],
        }),
        200,
      );
    });

    await _pumpChatPage(
      tester,
      client: officialClient,
      accountClient: accountClient,
      onCritical: () {},
    );

    final dynamic state = tester.state(find.byType(ShamellChatPage));
    await state.debugLoadDevicesSummary();
    await tester.pump();

    expect(
      requestUri.toString(),
      'https://api.example.com/auth/devices?limit=2',
    );
    final summary = state.debugDevicesSummaryState() as Map<String, Object?>;
    expect(summary['hasOtherDevices'], isTrue);
    expect(summary['otherDeviceLabel'], 'tablet');
  });

  testWidgets(
      'ShamellChatPage devices summary probe sends localhost client-ip hint and cookie',
      (tester) async {
    const baseUrl = 'http://localhost:8080';
    const sessionToken = '0123456789abcdef0123456789abcdef';
    await setSessionTokenForBaseUrl(baseUrl, sessionToken);
    await _saveIdentity(baseUrl: baseUrl, deviceId: 'device_self');
    final officialClient = MockClient((_) async => http.Response('{}', 200));
    late Uri requestUri;
    final accountClient = MockClient((request) async {
      requestUri = request.url;
      expect(request.headers['cookie'], '__Host-sa_session=$sessionToken');
      expect(request.headers['x-shamell-client-ip'], '127.0.0.1');
      return http.Response(
        jsonEncode(<String, Object?>{
          'devices': <Map<String, Object?>>[
            <String, Object?>{
              'device_id': 'device_self',
              'device_type': 'phone',
            },
            <String, Object?>{
              'device_id': 'device_other',
              'platform': 'tablet',
            },
          ],
        }),
        200,
      );
    });

    await _pumpChatPage(
      tester,
      client: officialClient,
      accountClient: accountClient,
      baseUrl: baseUrl,
      capabilities: _officialServiceCaps,
      onCritical: () {},
    );

    final dynamic state = tester.state(find.byType(ShamellChatPage));
    await state.debugLoadDevicesSummary();
    await tester.pump();

    expect(requestUri.toString(), 'http://localhost:8080/auth/devices?limit=2');
  });

  testWidgets(
      'ShamellChatPage skips malformed base-url network dispatch for device-login approve deeplink',
      (tester) async {
    final requests = <String>[];
    final accountClient = MockClient((request) async {
      requests.add('${request.method} ${request.url}');
      return http.Response('{}', 200);
    });

    await _pumpChatPage(
      tester,
      client: MockClient((_) async => http.Response('{}', 200)),
      accountClient: accountClient,
      baseUrl: _invalidBaseUrl,
      onCritical: () {},
    );

    final dynamic state = tester.state(find.byType(ShamellChatPage));
    await state.debugConfirmDeviceLogin('token_1', label: 'Laptop');
    await tester.pump();

    expect(requests, isEmpty);
  });
}
