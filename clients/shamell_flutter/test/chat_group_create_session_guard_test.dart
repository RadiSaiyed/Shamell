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

class _FakeChatGroupCreateService extends ChatService {
  _FakeChatGroupCreateService({
    this.createGroupError,
    this.inviteGroupMembersError,
  }) : super(_baseUrl);

  final Object? createGroupError;
  final Object? inviteGroupMembersError;

  @override
  bool get libsignalKeyApiEnabled => false;

  @override
  Future<ChatGroup> createGroup({
    required String deviceId,
    required String name,
    List<String> memberIds = const <String>[],
    String? groupId,
  }) async {
    final error = createGroupError;
    if (error != null) throw error;
    return ChatGroup(
      id: 'group_1',
      name: name,
      creatorId: deviceId,
      memberCount: 1,
    );
  }

  @override
  Future<ChatGroup> inviteGroupMembers({
    required String groupId,
    required String inviterId,
    required List<String> memberIds,
  }) async {
    final error = inviteGroupMembersError;
    if (error != null) throw error;
    return ChatGroup(
      id: groupId,
      name: 'Security Group',
      creatorId: inviterId,
      memberCount: 1 + memberIds.length,
    );
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
  const criticalCreateError = ChatHttpException(
    op: 'group create',
    statusCode: 401,
    body: '{"detail":"auth session required"}',
  );
  const criticalInviteError = ChatHttpException(
    op: 'group invite',
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

  testWidgets('ShamellChatPage reauths on critical standalone group create',
      (tester) async {
    final service =
        _FakeChatGroupCreateService(createGroupError: criticalCreateError);
    var reauthTriggered = false;
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () => reauthTriggered = true,
    );

    await state.debugCreateStandaloneGroup('Security Group');
    await tester.pump();

    expect(reauthTriggered, isTrue);
  });

  testWidgets('ShamellChatPage reauths on critical peer-group invite',
      (tester) async {
    final service = _FakeChatGroupCreateService(
      inviteGroupMembersError: criticalInviteError,
    );
    var reauthTriggered = false;
    final dynamic state = await _pumpChatPage(
      tester,
      service: service,
      onCritical: () => reauthTriggered = true,
    );

    await state.debugCreatePeerGroup(name: 'Security Group', peerId: _peerId);
    await tester.pump();

    expect(reauthTriggered, isTrue);
  });
}
