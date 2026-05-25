import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/chat/chat_models.dart';
import 'package:shamell_flutter/core/chat/ratchet_models.dart';
import 'package:shamell_flutter/core/chat/chat_service.dart';
import 'package:shamell_flutter/core/chat/shamell_chat_page.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';

const _baseUrl = 'https://api.example.com';
const _meId = 'device_self';
const _peerId = 'peer_1';

String _curveKeyB64(int seed) => base64Encode(
      Uint8List.fromList(
        List<int>.generate(32, (i) => ((seed + i) % 251) + 1),
      ),
    );

ChatIdentity _buildMe() => ChatIdentity(
      id: _meId,
      publicKeyB64: _curveKeyB64(1),
      privateKeyB64: _curveKeyB64(97),
      fingerprint: 'fp-self',
    );

ChatContact _buildPeer() => ChatContact(
      id: _peerId,
      publicKeyB64: _curveKeyB64(33),
      fingerprint: 'fp-peer',
      name: 'Peer',
    );

Uint8List _bytes(int seed) => Uint8List.fromList(
      List<int>.generate(32, (i) => ((seed + i) % 251) + 1),
    );

class _FakeChatEntrypointService extends ChatService {
  _FakeChatEntrypointService({
    this.registerDeviceError,
    this.resolveDeviceError,
    this.redeemInviteError,
  }) : super(_baseUrl);

  final Object? registerDeviceError;
  final Object? resolveDeviceError;
  final Object? redeemInviteError;
  int resolveDeviceCallCount = 0;
  int redeemInviteCallCount = 0;
  int fetchInboxPagedCallCount = 0;
  int listGroupsPagedCallCount = 0;
  int streamInboxCallCount = 0;
  int streamGroupInboxCallCount = 0;
  int streamTypingSignalsCallCount = 0;

  @override
  bool get libsignalKeyApiEnabled => false;

  @override
  Future<ChatContact> registerDevice(ChatIdentity me) async {
    final error = registerDeviceError;
    if (error != null) throw error;
    return _buildPeer();
  }

  @override
  Future<ChatContact> resolveDevice(String id) async {
    resolveDeviceCallCount += 1;
    final error = resolveDeviceError;
    if (error != null) throw error;
    return _buildPeer();
  }

  @override
  Future<String> redeemContactInviteTokenEnsured(
    String rawToken, {
    int attempts = 2,
  }) async {
    redeemInviteCallCount += 1;
    final error = redeemInviteError;
    if (error != null) throw error;
    return _peerId;
  }

  @override
  Future<List<ChatMessage>> fetchInboxPaged({
    required String deviceId,
    String? sinceIso,
    String? sinceId,
    int batchSize = 200,
    int maxPages = 25,
    int? retainLatestCount,
  }) async {
    fetchInboxPagedCallCount += 1;
    return <ChatMessage>[];
  }

  @override
  Future<List<ChatGroup>> listGroupsPaged({
    required String deviceId,
    int batchSize = 200,
    int maxPages = 25,
  }) async {
    listGroupsPagedCallCount += 1;
    return <ChatGroup>[];
  }

  @override
  Stream<List<ChatMessage>> streamInbox({required String deviceId}) {
    streamInboxCallCount += 1;
    return const Stream<List<ChatMessage>>.empty();
  }

  @override
  Stream<ChatGroupInboxUpdate> streamGroupInbox({required String deviceId}) {
    streamGroupInboxCallCount += 1;
    return const Stream<ChatGroupInboxUpdate>.empty();
  }

  @override
  Stream<ChatTypingSignal> streamTypingSignals({required String deviceId}) {
    streamTypingSignalsCallCount += 1;
    return const Stream<ChatTypingSignal>.empty();
  }
}

Future<dynamic> _pumpChatPage(
  WidgetTester tester, {
  required ChatService service,
  required VoidCallback onCritical,
  http.Client? accountHttpClient,
  Future<void> Function()? ensurePushTokenOverride,
  Future<bool> Function()? deviceLoginApprovalAuthPrompt,
  VoidCallback? onCriticalDeviceLoginSessionFailure,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ShamellChatPage(
        baseUrl: _baseUrl,
        runStartupTasks: false,
        accountHttpClient: accountHttpClient,
        ensurePushTokenOverride: ensurePushTokenOverride,
        deviceLoginApprovalAuthPrompt: deviceLoginApprovalAuthPrompt,
        onCriticalDeviceLoginSessionFailure:
            onCriticalDeviceLoginSessionFailure,
        serviceOverride: service,
        onCriticalChatSessionFailure: onCritical,
      ),
    ),
  );
  await tester.pump();
  final dynamic state = tester.state(find.byType(ShamellChatPage));
  state.debugSeedDirectThread(me: _buildMe(), peer: _buildPeer());
  await tester.pump();
  return state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secStore = <String, String>{};
  const criticalRegisterError = ChatHttpException(
    op: 'registerDevice',
    statusCode: 401,
    body: '{"detail":"auth session required"}',
  );
  const criticalResolveError = ChatHttpException(
    op: 'resolveDevice',
    statusCode: 401,
    body: '{"detail":"auth session required"}',
  );
  const criticalInviteError = ChatHttpException(
    op: 'redeemInvite',
    statusCode: 401,
    body: '{"detail":"auth session required"}',
  );

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

  testWidgets('ShamellChatPage reauths on critical register-device failure',
      (tester) async {
    final service = _FakeChatEntrypointService(
      registerDeviceError: criticalRegisterError,
    );
    var reauthTriggered = false;
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () => reauthTriggered = true,
    );

    await state.debugRegisterChatDevice();
    await tester.pump();

    expect(reauthTriggered, isTrue);
  });

  testWidgets(
      'ShamellChatPage restore identity reuses the register refresh path once',
      (tester) async {
    final service = _FakeChatEntrypointService();
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      ensurePushTokenOverride: () async {},
      onCritical: () {},
    );
    const passphrase = 'restore-passphrase';
    final backup = state.debugBuildIdentityBackupPayload(
      identity: _buildMe(),
      passphrase: passphrase,
    );

    await state.debugRestoreIdentityFromBackupPayload(
      backup: backup,
      passphrase: passphrase,
    );
    await tester.pump();

    expect(service.fetchInboxPagedCallCount, 1);
    expect(service.listGroupsPagedCallCount, 1);
    expect(service.streamInboxCallCount, 1);
    expect(service.streamGroupInboxCallCount, 1);
    expect(service.streamTypingSignalsCallCount, 1);
  });

  testWidgets(
      'ShamellChatPage restore identity clears stale direct-session state after identity change',
      (tester) async {
    final service = _FakeChatEntrypointService();
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      ensurePushTokenOverride: () async {},
      onCritical: () {},
    );
    await state.debugSeedRatchetForPeer(
      _peerId,
      RatchetState(
        rootKey: _bytes(1),
        sendChainKey: _bytes(33),
        recvChainKey: _bytes(65),
        sendCount: 2,
        recvCount: 1,
        pn: 0,
        skipped: <String, String>{},
        peerIdentity: _buildPeer().fingerprint,
        dhPriv: _bytes(97),
        dhPub: _bytes(129),
        peerDhPub: _bytes(161),
        peerDhPubB64: _curveKeyB64(193),
      ),
    );
    expect(state.debugHasRatchetForCurrentPeer(), isTrue);

    const passphrase = 'restore-rotated-passphrase';
    final rotatedMe = ChatIdentity(
      id: 'device_restored_rotated',
      publicKeyB64: _curveKeyB64(5),
      privateKeyB64: _curveKeyB64(111),
      fingerprint: 'fp-self-restored-rotated',
    );
    final backup = state.debugBuildIdentityBackupPayload(
      identity: rotatedMe,
      passphrase: passphrase,
    );

    await state.debugRestoreIdentityFromBackupPayload(
      backup: backup,
      passphrase: passphrase,
    );
    await tester.pump();

    expect(state.debugHasRatchetForCurrentPeer(), isFalse);
  });

  testWidgets('ShamellChatPage reauths on critical resolve-peer failure',
      (tester) async {
    final service = _FakeChatEntrypointService(
      resolveDeviceError: criticalResolveError,
    );
    var reauthTriggered = false;
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () => reauthTriggered = true,
    );

    await state.debugResolvePeerId('peer_2');
    await tester.pump();

    expect(reauthTriggered, isTrue);
  });

  testWidgets('ShamellChatPage reauths on critical invite QR redeem failure',
      (tester) async {
    final service = _FakeChatEntrypointService(
      redeemInviteError: criticalInviteError,
    );
    var reauthTriggered = false;
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () => reauthTriggered = true,
    );

    await state.debugOpenChatFromInviteQr(
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    await tester.pump();

    expect(reauthTriggered, isTrue);
  });

  testWidgets(
      'ShamellChatPage rejects malformed invite QR token before redeem bootstrap/network',
      (tester) async {
    final service = _FakeChatEntrypointService();
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () {},
    );

    await state.debugOpenChatFromInviteQr('not-a-valid-token');
    await tester.pump();

    expect(service.redeemInviteCallCount, 0);
    expect(service.resolveDeviceCallCount, 0);
    expect(find.text('Invalid invite token.'), findsOneWidget);
  });

  testWidgets(
      'ShamellChatPage resolves invite QR peer only once after redeem succeeds',
      (tester) async {
    final service = _FakeChatEntrypointService();
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () {},
    );

    await state.debugOpenChatFromInviteQr(
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    await tester.pump();

    expect(service.resolveDeviceCallCount, 1);
  });

  testWidgets(
      'ShamellChatPage rejects malformed device-login token before auth prompt or network',
      (tester) async {
    var calls = 0;
    var prompts = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 200);
    });
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatEntrypointService(),
      onCritical: () {},
      accountHttpClient: client,
      deviceLoginApprovalAuthPrompt: () async {
        prompts++;
        return true;
      },
    );

    await state.debugConfirmDeviceLogin('not-a-token', label: 'Demo');
    await tester.pump();

    expect(calls, 0);
    expect(prompts, 0);
    expect(find.text('Invalid device-login token.'), findsOneWidget);
  });

  testWidgets(
      'ShamellChatPage ignores duplicate device-login approvals while approval is in flight',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 200);
    });
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatEntrypointService(),
      onCritical: () {},
      accountHttpClient: client,
      deviceLoginApprovalAuthPrompt: () async => true,
    );

    final first = state.debugConfirmDeviceLogin(
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      label: 'Demo',
    ) as Future<void>;
    final second = state.debugConfirmDeviceLogin(
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      label: 'Demo',
    ) as Future<void>;

    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pump();
    await first;
    await second;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(calls, 1);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
      'ShamellChatPage surfaces sanitized HTTP errors for device-login approve failures',
      (tester) async {
    final client = MockClient((request) async {
      return http.Response('{"detail":"rate limit exceeded"}', 429);
    });
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatEntrypointService(),
      onCritical: () {},
      accountHttpClient: client,
      deviceLoginApprovalAuthPrompt: () async => true,
    );

    final approve = state.debugConfirmDeviceLogin(
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      label: 'Demo',
    );
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pump();
    await approve;
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Too many requests. Try again later.'), findsOneWidget);
  });

  testWidgets(
      'ShamellChatPage surfaces sanitized transport errors for device-login approve failures',
      (tester) async {
    final client = MockClient((request) async {
      throw http.ClientException('connection reset');
    });
    final dynamic state = await _pumpChatPage(
      tester,
      service: _FakeChatEntrypointService(),
      onCritical: () {},
      accountHttpClient: client,
      deviceLoginApprovalAuthPrompt: () async => true,
    );

    final approve = state.debugConfirmDeviceLogin(
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      label: 'Demo',
    );
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pump();
    await approve;
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Network error.'), findsOneWidget);
  });
}
