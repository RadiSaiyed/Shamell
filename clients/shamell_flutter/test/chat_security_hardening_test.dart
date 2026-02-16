import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/chat/shamell_chat_info_page.dart';
import 'package:shamell_flutter/core/chat/chat_models.dart';
import 'package:shamell_flutter/core/chat/chat_service.dart';
import 'package:shamell_flutter/core/chat/safety_number.dart';
import 'package:shamell_flutter/core/device_id.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/logout_wipe.dart';
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

  test('desktop secure storage is enabled by default', () {
    expect(shamellDesktopSecureStorageDefault, isTrue);
  });

  test('chat protocol send version is v2_libsignal (no fallback)', () {
    expect(shamellChatProtocolSendVersion, 'v2_libsignal');
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

  test('session bootstrap metadata persists TOFU signing-key pin', () async {
    final store = ChatLocalStore();
    const pinnedSigningKeyB64 = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
    await store.saveSessionBootstrapMeta(
      'peer-1',
      protocolFloor: 'v2_libsignal',
      signedPrekeyId: 77,
      oneTimePrekeyId: 88,
      v2Only: true,
      identitySigningPubkeyB64: pinnedSigningKeyB64,
    );

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

    await store.deleteSessionBootstrapMeta('peer-1');
    expect(await store.loadSessionBootstrapMeta('peer-1'), isEmpty);
    expect(await store.loadPinnedIdentitySigningPubkey('peer-1'), isNull);
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

    await svc.sendMessage(
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

  test('peer is encrypted at rest in SharedPreferences', () async {
    final store = ChatLocalStore();
    final peer = ChatContact(
      id: 'dev-2',
      publicKeyB64: 'pk',
      fingerprint: 'fp',
      name: 'Alice',
      verified: false,
    );
    await store.savePeer(peer);
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('chat.peer');
    expect(raw, isNotNull);
    final decoded = jsonDecode(raw!) as Map<String, Object?>;
    expect(decoded['v'], 1);
    expect((decoded['nonce_b64'] ?? '').toString().trim().isNotEmpty, isTrue);
    expect((decoded['box_b64'] ?? '').toString().trim().isNotEmpty, isTrue);
    final loaded = await store.loadPeer();
    expect(loaded?.id, 'dev-2');
  });

  test('legacy plaintext peer is migrated to ciphertext on load', () async {
    final peer = ChatContact(
      id: 'dev-legacy',
      publicKeyB64: 'pk',
      fingerprint: 'fp',
      name: 'Legacy',
      verified: false,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      'chat.peer': jsonEncode(peer.toMap()),
    });
    final store = ChatLocalStore();
    final loaded = await store.loadPeer();
    expect(loaded?.id, 'dev-legacy');
    final sp = await SharedPreferences.getInstance();
    final migrated = sp.getString('chat.peer') ?? '';
    expect(migrated, isNot(jsonEncode(peer.toMap())));
    final decoded = jsonDecode(migrated) as Map<String, Object?>;
    expect(decoded['v'], 1);
  });

  test('logout wipe clears account data but preserves device prefs', () async {
    const baseUrl = 'https://api.shamell.online';
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', baseUrl);
    await sp.setString('wallet_id', 'w1');
    await sp.setStringList('roles', <String>['admin']);
    await sp.setString(kStableDeviceIdPrefKey, 'install-1');
    await sp.setString('ui.theme_mode', 'dark');
    await sp.setBool('require_biometrics', true);

    // Seed chat secrets in secure storage.
    final store = ChatLocalStore();
    await store.saveGroupKey('grp-1', base64Encode(List<int>.filled(32, 3)));
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
    expect(sp2.getString(kStableDeviceIdPrefKey), 'install-1');
    expect(sp2.getString('ui.theme_mode'), 'dark');
    expect(sp2.getBool('require_biometrics'), isTrue);

    expect(sp2.getString('wallet_id'), isNull);
    expect(sp2.getStringList('roles'), isNull);
    expect(await getSessionTokenForBaseUrl(baseUrl), isNull);
    expect(secStore.keys.any((k) => k.startsWith('chat.')), isFalse);
  });

  testWidgets('ChatInfo security actions require confirmation', (tester) async {
    bool marked = false;
    bool reset = false;

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
}
