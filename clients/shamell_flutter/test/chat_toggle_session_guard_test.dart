import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/chat/chat_models.dart';
import 'package:shamell_flutter/core/chat/chat_service.dart';
import 'package:shamell_flutter/core/chat/shamell_chat_page.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';

const _baseUrl = 'https://api.example.com';
const _meId = 'device_self';
const _peerId = 'peer_1';
const _groupId = 'group_1';

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

ChatGroup _buildGroup() => const ChatGroup(
      id: _groupId,
      name: 'Security Group',
      creatorId: _meId,
      memberCount: 2,
    );

class _FakeChatToggleService extends ChatService {
  _FakeChatToggleService({
    this.setPrefsError,
    this.setHiddenError,
    this.setBlockError,
    this.setGroupPrefsError,
  }) : super(_baseUrl);

  final Object? setPrefsError;
  final Object? setHiddenError;
  final Object? setBlockError;
  final Object? setGroupPrefsError;

  @override
  bool get libsignalKeyApiEnabled => false;

  @override
  Future<void> setPrefs({
    required String deviceId,
    required String peerId,
    bool? muted,
    bool? starred,
    bool? pinned,
  }) async {
    final error = setPrefsError;
    if (error != null) throw error;
  }

  @override
  Future<void> setHidden({
    required String deviceId,
    required String peerId,
    required bool hidden,
  }) async {
    final error = setHiddenError;
    if (error != null) throw error;
  }

  @override
  Future<void> setBlock({
    required String deviceId,
    required String peerId,
    required bool blocked,
    bool hidden = false,
  }) async {
    final error = setBlockError;
    if (error != null) throw error;
  }

  @override
  Future<void> setGroupPrefs({
    required String deviceId,
    required String groupId,
    bool? muted,
    bool? pinned,
  }) async {
    final error = setGroupPrefsError;
    if (error != null) throw error;
  }
}

Future<dynamic> _pumpChatPage(
  WidgetTester tester, {
  required ChatService service,
  required VoidCallback onCritical,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ShamellChatPage(
        baseUrl: _baseUrl,
        runStartupTasks: false,
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
  const criticalPrefsError = ChatHttpException(
    op: 'prefs update',
    statusCode: 401,
    body: '{"detail":"auth session required"}',
  );
  const criticalBlockError = ChatHttpException(
    op: 'block update',
    statusCode: 401,
    body: '{"detail":"auth session required"}',
  );
  const criticalGroupPrefsError = ChatHttpException(
    op: 'group prefs update',
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

  testWidgets('ShamellChatPage reauths on critical peer mute failure',
      (tester) async {
    final service = _FakeChatToggleService(setPrefsError: criticalPrefsError);
    var reauthTriggered = false;
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () => reauthTriggered = true,
    );

    await state.debugSetPeerMuted(true);
    await tester.pump();

    expect(reauthTriggered, isTrue);
  });

  testWidgets('ShamellChatPage reauths on critical peer pin failure',
      (tester) async {
    final service = _FakeChatToggleService(setPrefsError: criticalPrefsError);
    var reauthTriggered = false;
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () => reauthTriggered = true,
    );

    await state.debugSetPeerPinned(true);
    await tester.pump();

    expect(reauthTriggered, isTrue);
  });

  testWidgets('ShamellChatPage reauths on critical peer hide failure',
      (tester) async {
    final service = _FakeChatToggleService(setHiddenError: criticalBlockError);
    var reauthTriggered = false;
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () => reauthTriggered = true,
    );

    await state.debugSetPeerHidden(true);
    await tester.pump();

    expect(reauthTriggered, isTrue);
  });

  testWidgets('ShamellChatPage reauths on critical peer block failure',
      (tester) async {
    final service = _FakeChatToggleService(setBlockError: criticalBlockError);
    var reauthTriggered = false;
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () => reauthTriggered = true,
    );

    await state.debugSetPeerBlocked(true);
    await tester.pump();

    expect(reauthTriggered, isTrue);
  });

  testWidgets('ShamellChatPage reauths on critical group mute failure',
      (tester) async {
    final service =
        _FakeChatToggleService(setGroupPrefsError: criticalGroupPrefsError);
    var reauthTriggered = false;
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () => reauthTriggered = true,
    );

    await state.debugSetGroupMuted(_buildGroup(), true);
    await tester.pump();

    expect(reauthTriggered, isTrue);
  });

  testWidgets('ShamellChatPage reauths on critical group pin failure',
      (tester) async {
    final service =
        _FakeChatToggleService(setGroupPrefsError: criticalGroupPrefsError);
    var reauthTriggered = false;
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () => reauthTriggered = true,
    );

    await state.debugSetGroupPinned(_buildGroup(), true);
    await tester.pump();

    expect(reauthTriggered, isTrue);
  });
}
