import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/chat/chat_models.dart';
import 'package:shamell_flutter/core/chat/chat_service.dart';
import 'package:shamell_flutter/core/chat/shamell_chat_page.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import 'package:shamell_flutter/core/v2_chat_strangler.dart';

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

String _sessionHashFor(String a, String b) {
  final combined = (a.compareTo(b) <= 0) ? '$a$b' : '$b$a';
  return crypto.sha256.convert(utf8.encode('sess|$combined')).toString();
}

ChatMessage _forwardableMessage() => ChatMessage(
      id: 'forward_src',
      senderId: _peerId,
      recipientId: _meId,
      senderPubKeyB64: _curveKeyB64(33),
      nonceB64: '',
      boxB64: base64Encode(utf8.encode(jsonEncode({'text': 'forward me'}))),
      trustedLocalPlaintext: true,
    );

ChatMessage _recallableMessage() => ChatMessage(
      id: 'recall_src',
      senderId: _peerId,
      recipientId: _meId,
      senderPubKeyB64: _curveKeyB64(33),
      nonceB64: '',
      boxB64: base64Encode(utf8.encode(jsonEncode({'text': 'recall me'}))),
      trustedLocalPlaintext: true,
    );

ChatMessage _threadMessage(
  String id,
  Map<String, Object?> payload, {
  DateTime? createdAt,
}) =>
    ChatMessage(
      id: id,
      senderId: _peerId,
      recipientId: _meId,
      senderPubKeyB64: _curveKeyB64(33),
      nonceB64: '',
      boxB64: base64Encode(utf8.encode(jsonEncode(payload))),
      trustedLocalPlaintext: true,
      createdAt: createdAt ?? DateTime.utc(2026, 1, 1, 12),
    );

class _FakeDirectChatService extends ChatService {
  _FakeDirectChatService({
    this.sendError,
    this.ensureError,
    List<Object?>? sendErrorsByCall,
    this.onEnsure,
  })  : _sendErrorsByCall = List<Object?>.from(
          sendErrorsByCall ?? const <Object?>[],
        ),
        super(_baseUrl);

  final Object? sendError;
  final Object? ensureError;
  final Future<void> Function()? onEnsure;
  final List<Object?> _sendErrorsByCall;
  int sendCalls = 0;
  int ensureCalls = 0;
  final List<int?> sentKeyIds = <int?>[];
  final List<String?> sentSessionHashes = <String?>[];
  final List<String?> sentSenderHints = <String?>[];

  @override
  bool get libsignalKeyApiEnabled => false;

  @override
  Future<void> ensureAccountChatReady() async {
    ensureCalls += 1;
    final ensureAction = onEnsure;
    if (ensureAction != null) {
      await ensureAction();
    }
    final error = ensureError;
    if (error != null) throw error;
  }

  @override
  Future<ChatMessage> sendMessage({
    required ChatIdentity me,
    required ChatContact peer,
    required String plainText,
    int? expireAfterSeconds,
    bool sealedSender = true,
    String? senderHint,
    Uint8List? sessionKey,
    int? keyId,
    int? prevKeyId,
    String? senderDhPubB64,
    ChatDirectSendEnvelope? preparedEnvelope,
    V2ChatFlowVariant metricVariant = V2ChatFlowVariant.legacy,
  }) async {
    sendCalls += 1;
    sentKeyIds.add(keyId);
    sentSenderHints.add(senderHint);
    try {
      final decoded = jsonDecode(plainText);
      if (decoded is Map) {
        sentSessionHashes.add((decoded['session_hash'] ?? '').toString());
      } else {
        sentSessionHashes.add(null);
      }
    } catch (_) {
      sentSessionHashes.add(null);
    }
    final error = _sendErrorsByCall.isNotEmpty
        ? _sendErrorsByCall.removeAt(0)
        : sendError;
    if (error != null) throw error;
    return ChatMessage(
      id: 'sent_$sendCalls',
      senderId: me.id,
      recipientId: peer.id,
      senderPubKeyB64: me.publicKeyB64,
      nonceB64: '',
      boxB64: base64Encode(utf8.encode(plainText)),
      trustedLocalPlaintext: true,
      sealedSender: sealedSender,
      senderHint: senderHint,
      keyId: keyId,
      prevKeyId: prevKeyId,
      senderDhPubB64: senderDhPubB64,
    );
  }
}

Future<dynamic> _pumpDirectChatPage(
  WidgetTester tester, {
  required ChatService service,
  required VoidCallback onCritical,
  Uint8List? presetAttachmentBytes,
  String? presetAttachmentMime,
  String? presetAttachmentName,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ShamellChatPage(
        baseUrl: _baseUrl,
        runStartupTasks: false,
        serviceOverride: service,
        onCriticalChatSessionFailure: onCritical,
        presetAttachmentBytes: presetAttachmentBytes,
        presetAttachmentMime: presetAttachmentMime,
        presetAttachmentName: presetAttachmentName,
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
  const criticalSendError = ChatHttpException(
    op: 'send',
    statusCode: 401,
    body: '{"detail":"auth session required"}',
  );
  const criticalEnsureError = ChatHttpException(
    op: 'ensureAccountChatReady',
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

  testWidgets('ShamellChatPage reauths on critical composer send failure',
      (tester) async {
    final service = _FakeDirectChatService(
      sendError: criticalSendError,
      ensureError: criticalEnsureError,
    );
    var reauthTriggered = false;
    final dynamic state = await _pumpDirectChatPage(
      tester,
      service: service,
      onCritical: () => reauthTriggered = true,
    );

    await state.debugSendComposerMessage('hello');
    await tester.pump();

    expect(service.sendCalls, 1);
    expect(service.ensureCalls, 1);
    expect(reauthTriggered, isTrue);
  });

  testWidgets(
      'ShamellChatPage clears stale direct-session state after identity rotation recovery',
      (tester) async {
    final rotatedMe = ChatIdentity(
      id: 'device_rotated',
      publicKeyB64: _curveKeyB64(5),
      privateKeyB64: _curveKeyB64(111),
      fingerprint: 'fp-self-rotated',
    );
    final oldHash =
        _sessionHashFor(_buildMe().fingerprint, _buildPeer().fingerprint);
    final newHash =
        _sessionHashFor(rotatedMe.fingerprint, _buildPeer().fingerprint);
    final service = _FakeDirectChatService(
      onEnsure: () async {
        await ChatLocalStore().saveIdentity(rotatedMe);
      },
    );

    final dynamic state = await _pumpDirectChatPage(
      tester,
      service: service,
      onCritical: () {},
    );

    state.debugPrimeDirectSessionState();
    expect(state.debugCurrentSessionHash, oldHash);
    expect(state.debugHasRatchetForCurrentPeer(), isTrue);

    final recovery = await state.debugRecoverSendAuthState();
    await tester.pump();

    expect(recovery.recovered, isTrue);
    expect(recovery.reauthTriggered, isFalse);
    expect(service.ensureCalls, 1);
    expect(state.debugCurrentSessionHash, isNull);
    expect(state.debugHasRatchetForCurrentPeer(), isFalse);

    await state.debugSendComposerMessage('hello');
    await tester.pump();

    expect(service.sendCalls, 1);
    expect(service.sentKeyIds, <int?>[0]);
    expect(service.sentSenderHints, <String?>[rotatedMe.fingerprint]);
    expect(service.sentSessionHashes, <String?>[newHash]);
  });

  testWidgets('ShamellChatPage reauths on critical quick text send failure',
      (tester) async {
    final service = _FakeDirectChatService(sendError: criticalSendError);
    var reauthTriggered = false;
    final dynamic state = await _pumpDirectChatPage(
      tester,
      service: service,
      onCritical: () => reauthTriggered = true,
    );

    await state.debugSendDirectTextQuick('hello');
    await tester.pump();

    expect(service.sendCalls, 1);
    expect(reauthTriggered, isTrue);
  });

  testWidgets('ShamellChatPage reauths on critical voice send failure',
      (tester) async {
    final service = _FakeDirectChatService(sendError: criticalSendError);
    var reauthTriggered = false;
    final dynamic state = await _pumpDirectChatPage(
      tester,
      service: service,
      onCritical: () => reauthTriggered = true,
    );

    await state.debugSendDirectVoice(Uint8List.fromList(<int>[1, 2, 3]), 2);
    await tester.pump();

    expect(service.sendCalls, 1);
    expect(reauthTriggered, isTrue);
  });

  testWidgets('ShamellChatPage reauths on critical location send failure',
      (tester) async {
    final service = _FakeDirectChatService(sendError: criticalSendError);
    var reauthTriggered = false;
    final dynamic state = await _pumpDirectChatPage(
      tester,
      service: service,
      onCritical: () => reauthTriggered = true,
    );

    await state.debugSendDirectLocation(36.8, 10.1, label: 'Tunis');
    await tester.pump();

    expect(service.sendCalls, 1);
    expect(reauthTriggered, isTrue);
  });

  testWidgets('ShamellChatPage reauths on critical contact-card send failure',
      (tester) async {
    final service = _FakeDirectChatService(sendError: criticalSendError);
    var reauthTriggered = false;
    final dynamic state = await _pumpDirectChatPage(
      tester,
      service: service,
      onCritical: () => reauthTriggered = true,
    );

    await state.debugSendDirectContactCard('friend_1');
    await tester.pump();

    expect(service.sendCalls, 1);
    expect(reauthTriggered, isTrue);
  });

  testWidgets('ShamellChatPage reauths on critical forward failure',
      (tester) async {
    final service = _FakeDirectChatService(sendError: criticalSendError);
    var reauthTriggered = false;
    final dynamic state = await _pumpDirectChatPage(
      tester,
      service: service,
      onCritical: () => reauthTriggered = true,
    );

    await state
        .debugForwardDirectMessages(<ChatMessage>[_forwardableMessage()]);
    await tester.pump();

    expect(service.sendCalls, 1);
    expect(reauthTriggered, isTrue);
  });

  testWidgets('ShamellChatPage reauths on critical recall failure',
      (tester) async {
    final service = _FakeDirectChatService(sendError: criticalSendError);
    var reauthTriggered = false;
    final dynamic state = await _pumpDirectChatPage(
      tester,
      service: service,
      onCritical: () => reauthTriggered = true,
    );

    await state.debugSendRecallForMessage(_recallableMessage());
    await tester.pump();

    expect(service.sendCalls, 1);
    expect(reauthTriggered, isTrue);
  });

  testWidgets(
      'ShamellChatPage renders pinned message previews without duplicate bubble keys',
      (tester) async {
    final dynamic state = await _pumpDirectChatPage(
      tester,
      service: _FakeDirectChatService(),
      onCritical: () {},
    );
    final pinnedMessage = _threadMessage(
      'pinned_preview',
      <String, Object?>{'text': 'Pinned preview'},
    );

    state.debugSeedDirectThread(
      me: _buildMe(),
      peer: _buildPeer(),
      messages: <ChatMessage>[pinnedMessage],
    );
    await tester.pump();

    await state.debugSetPinnedMessageForPeer(
      _peerId,
      pinnedMessage.id,
      true,
    );
    await tester.pump();

    expect(
        state.debugIsMessagePinnedForPeer(_peerId, pinnedMessage.id), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'ShamellChatPage renders preset non-image composer attachments as file previews',
      (tester) async {
    final dynamic state = await _pumpDirectChatPage(
      tester,
      service: _FakeDirectChatService(),
      onCritical: () {},
      presetAttachmentBytes: Uint8List.fromList(utf8.encode('not-an-image')),
      presetAttachmentMime: 'application/pdf',
      presetAttachmentName: 'contract.pdf',
    );

    state.debugSeedDirectThread(me: _buildMe(), peer: _buildPeer());
    await tester.pump();

    expect(find.text('contract.pdf'), findsOneWidget);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'ShamellChatPage opens the pinned messages sheet and jumps to the selected message',
      (tester) async {
    final dynamic state = await _pumpDirectChatPage(
      tester,
      service: _FakeDirectChatService(),
      onCritical: () {},
    );
    final messages = <ChatMessage>[
      _threadMessage('pin_1', <String, Object?>{'text': 'Pinned one'}),
      _threadMessage('pin_2', <String, Object?>{'text': 'Pinned two'}),
      _threadMessage('pin_3', <String, Object?>{'text': 'Pinned three'}),
      _threadMessage('pin_4', <String, Object?>{'text': 'Pinned four'}),
    ];

    state.debugSeedDirectThread(
      me: _buildMe(),
      peer: _buildPeer(),
      messages: messages,
    );
    await tester.pump();
    expect(state.debugThreadMessageRenderKeyCount(), 0);

    for (final message in messages) {
      await state.debugSetPinnedMessageForPeer(_peerId, message.id, true);
    }
    await tester.pump();

    await tester.tap(find.text('View all'));
    await tester.pumpAndSettle();

    final sheetFinder = find.byType(BottomSheet);
    expect(sheetFinder, findsOneWidget);
    final pinnedOneInSheet = find.descendant(
      of: sheetFinder,
      matching: find.text('Pinned one'),
    );
    expect(pinnedOneInSheet, findsOneWidget);
    final pinnedOneTile = find.ancestor(
      of: pinnedOneInSheet,
      matching: find.byType(InkWell),
    );
    expect(pinnedOneTile, findsWidgets);

    await tester.tap(pinnedOneTile.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(state.debugHighlightedMessageId(), 'pin_1');
    expect(state.debugThreadMessageRenderKeyCount(), 1);
    expect(tester.takeException(), isNull);
  });
}
