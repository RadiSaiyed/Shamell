import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/chat/chat_models.dart';
import 'package:shamell_flutter/core/chat/chat_service.dart';
import 'package:shamell_flutter/core/group_chats_page.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/v2_chat_strangler.dart';

const _groupBaseUrl = 'https://api.example.com';
const _groupId = 'group_1';
const _deviceId = 'device_1';

Widget _groupTestApp({
  required ChatService service,
  required VoidCallback onCriticalSessionFailure,
  Future<void> Function(String groupId, String themeKey)?
      saveChatThemeForGroupOverride,
  Future<void> Function(String groupId, int unreadCount)?
      saveUnreadCountForGroupOverride,
  Future<int> Function(String groupId)? loadUnreadCountForGroupOverride,
  Future<void> Function(String groupId, DateTime ts)?
      saveGroupSeenForGroupOverride,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: L10n.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      L10n.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: GroupChatPage(
      baseUrl: _groupBaseUrl,
      groupId: _groupId,
      groupName: 'Security Group',
      serviceOverride: service,
      onCriticalSessionFailure: onCriticalSessionFailure,
      saveChatThemeForGroupOverride: saveChatThemeForGroupOverride,
      saveUnreadCountForGroupOverride: saveUnreadCountForGroupOverride,
      loadUnreadCountForGroupOverride: loadUnreadCountForGroupOverride,
      saveGroupSeenForGroupOverride: saveGroupSeenForGroupOverride,
    ),
  );
}

Future<void> _saveIdentity() async {
  await ChatLocalStore().saveIdentity(
    const ChatIdentity(
      id: _deviceId,
      publicKeyB64: 'pubkey',
      privateKeyB64: 'privkey',
      fingerprint: 'fingerprint',
    ),
    baseUrlOverride: _groupBaseUrl,
  );
}

class _FakeGroupChatService extends ChatService {
  _FakeGroupChatService({
    this.listGroupsError,
    this.fetchGroupByIdHandler,
    this.listGroupMembersError,
    this.listGroupMembersPagedHandler,
    this.fetchGroupPrefForGroupHandler,
    this.updateGroupError,
    this.setGroupRoleError,
    this.inviteGroupMembersError,
    this.leaveGroupError,
    this.setGroupPrefsError,
    this.listGroupKeyEventsError,
    this.listGroupKeyEventsPagedHandler,
    this.rotateGroupKeyError,
    this.sendGroupMessageError,
    this.sendGroupMessageGate,
    this.fetchGroupInboxHandler,
    this.resolveDeviceError,
  }) : super(_groupBaseUrl);

  final Object? listGroupsError;
  final Future<ChatGroup?> Function({
    required String deviceId,
    required String groupId,
    int batchSize,
    int? maxPages,
  })? fetchGroupByIdHandler;
  final Object? listGroupMembersError;
  final Future<List<ChatGroupMember>> Function({
    required String groupId,
    required String deviceId,
    int batchSize,
    int maxPages,
  })? listGroupMembersPagedHandler;
  final Future<ChatGroupPrefs?> Function({
    required String deviceId,
    required String groupId,
    int batchSize,
    int maxPages,
  })? fetchGroupPrefForGroupHandler;
  final Object? updateGroupError;
  final Object? setGroupRoleError;
  final Object? inviteGroupMembersError;
  final Object? leaveGroupError;
  final Object? setGroupPrefsError;
  final Object? listGroupKeyEventsError;
  final Future<List<ChatGroupKeyEvent>> Function({
    required String groupId,
    required String deviceId,
    int batchSize,
    int maxPages,
  })? listGroupKeyEventsPagedHandler;
  final Object? rotateGroupKeyError;
  final Object? sendGroupMessageError;
  final Completer<void>? sendGroupMessageGate;
  final List<ChatGroupMessage> Function({
    String? sinceId,
    String? beforeId,
  })? fetchGroupInboxHandler;
  final Object? resolveDeviceError;
  int fetchGroupInboxCallCount = 0;
  final List<String?> fetchGroupInboxSinceIds = <String?>[];
  final List<String?> fetchGroupInboxBeforeIds = <String?>[];
  int fetchGroupByIdCallCount = 0;
  int fetchGroupPrefsCallCount = 0;
  int fetchGroupPrefForGroupCallCount = 0;
  int listGroupMembersPagedCallCount = 0;
  int listGroupKeyEventsPagedCallCount = 0;
  int sendGroupMessageCallCount = 0;
  int resolveDeviceCallCount = 0;
  int sendDirectMessageCallCount = 0;
  final List<String> resolvedDeviceIds = <String>[];
  final List<String> directMessagePeerIds = <String>[];

  @override
  Future<List<ChatGroup>> listGroups({required String deviceId}) async {
    final error = listGroupsError;
    if (error != null) throw error;
    return const <ChatGroup>[
      ChatGroup(
        id: _groupId,
        name: 'Security Group',
        creatorId: _deviceId,
        memberCount: 2,
      ),
    ];
  }

  @override
  Future<ChatGroup?> fetchGroupById({
    required String deviceId,
    required String groupId,
    int batchSize = 200,
    int? maxPages,
  }) async {
    fetchGroupByIdCallCount += 1;
    final handler = fetchGroupByIdHandler;
    if (handler != null) {
      return handler(
        deviceId: deviceId,
        groupId: groupId,
        batchSize: batchSize,
        maxPages: maxPages,
      );
    }
    final error = listGroupsError;
    if (error != null) throw error;
    return const ChatGroup(
      id: _groupId,
      name: 'Security Group',
      creatorId: _deviceId,
      memberCount: 2,
    );
  }

  @override
  Future<List<ChatGroupPrefs>> fetchGroupPrefs({
    required String deviceId,
    int limit = 200,
    String? afterGroupId,
  }) async {
    fetchGroupPrefsCallCount += 1;
    return const <ChatGroupPrefs>[
      ChatGroupPrefs(groupId: _groupId, muted: false, pinned: false),
    ];
  }

  @override
  Future<ChatGroupPrefs?> fetchGroupPrefForGroup({
    required String deviceId,
    required String groupId,
    int batchSize = 200,
    int maxPages = 25,
  }) async {
    fetchGroupPrefForGroupCallCount += 1;
    final handler = fetchGroupPrefForGroupHandler;
    if (handler != null) {
      return handler(
        deviceId: deviceId,
        groupId: groupId,
        batchSize: batchSize,
        maxPages: maxPages,
      );
    }
    return const ChatGroupPrefs(
      groupId: _groupId,
      muted: false,
      pinned: false,
    );
  }

  @override
  Future<List<ChatGroupMessage>> fetchGroupInbox({
    required String groupId,
    required String deviceId,
    int limit = 50,
    String? sinceIso,
    String? sinceId,
    String? beforeCreatedAt,
    String? beforeId,
  }) async {
    fetchGroupInboxCallCount += 1;
    fetchGroupInboxSinceIds.add(sinceId);
    fetchGroupInboxBeforeIds.add(beforeId);
    final handler = fetchGroupInboxHandler;
    if (handler == null) {
      return const <ChatGroupMessage>[];
    }
    return handler(
      sinceId: sinceId,
      beforeId: beforeId,
    );
  }

  @override
  Future<List<ChatGroupMember>> listGroupMembers({
    required String groupId,
    required String deviceId,
  }) async {
    final error = listGroupMembersError;
    if (error != null) throw error;
    return const <ChatGroupMember>[
      ChatGroupMember(deviceId: _deviceId, role: 'admin'),
      ChatGroupMember(deviceId: 'device_2', role: 'member'),
    ];
  }

  @override
  Future<List<ChatGroupMember>> listGroupMembersPaged({
    required String groupId,
    required String deviceId,
    int batchSize = 200,
    int maxPages = 25,
  }) async {
    listGroupMembersPagedCallCount += 1;
    final handler = listGroupMembersPagedHandler;
    if (handler != null) {
      return handler(
        groupId: groupId,
        deviceId: deviceId,
        batchSize: batchSize,
        maxPages: maxPages,
      );
    }
    return listGroupMembers(groupId: groupId, deviceId: deviceId);
  }

  @override
  Future<ChatGroup> updateGroup({
    required String groupId,
    required String actorId,
    String? name,
    String? avatarB64,
    String? avatarMime,
  }) async {
    final error = updateGroupError;
    if (error != null) throw error;
    return ChatGroup(
      id: groupId,
      name: name ?? 'Security Group',
      creatorId: actorId,
      memberCount: 2,
      avatarB64: avatarB64,
      avatarMime: avatarMime,
    );
  }

  @override
  Future<void> setGroupRole({
    required String groupId,
    required String actorId,
    required String targetId,
    required String role,
  }) async {
    final error = setGroupRoleError;
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
      memberCount: 2 + memberIds.length,
    );
  }

  @override
  Future<void> leaveGroup({
    required String groupId,
    required String deviceId,
  }) async {
    final error = leaveGroupError;
    if (error != null) throw error;
  }

  @override
  Future<List<ChatGroupKeyEvent>> listGroupKeyEvents({
    required String groupId,
    required String deviceId,
    int limit = 20,
  }) async {
    final error = listGroupKeyEventsError;
    if (error != null) throw error;
    return const <ChatGroupKeyEvent>[];
  }

  @override
  Future<List<ChatGroupKeyEvent>> listGroupKeyEventsPaged({
    required String groupId,
    required String deviceId,
    int batchSize = 50,
    int maxPages = 20,
  }) async {
    listGroupKeyEventsPagedCallCount += 1;
    final handler = listGroupKeyEventsPagedHandler;
    if (handler != null) {
      return handler(
        groupId: groupId,
        deviceId: deviceId,
        batchSize: batchSize,
        maxPages: maxPages,
      );
    }
    return listGroupKeyEvents(
      groupId: groupId,
      deviceId: deviceId,
      limit: batchSize,
    );
  }

  @override
  Future<int> rotateGroupKey({
    required String groupId,
    required String actorId,
    String? keyFp,
  }) async {
    final error = rotateGroupKeyError;
    if (error != null) throw error;
    return 2;
  }

  @override
  Future<ChatGroupMessage> sendGroupMessage({
    required String groupId,
    required String senderId,
    String text = '',
    String? kind,
    String? attachmentB64,
    String? attachmentMime,
    int? voiceSecs,
    int? expireAfterSeconds,
    double? lat,
    double? lon,
    String? contactId,
    String? contactName,
  }) async {
    sendGroupMessageCallCount += 1;
    final gate = sendGroupMessageGate;
    if (gate != null) {
      await gate.future;
    }
    final error = sendGroupMessageError;
    if (error != null) throw error;
    return ChatGroupMessage(
      id: 'msg_1',
      groupId: groupId,
      senderId: senderId,
      text: text,
      kind: kind,
      attachmentB64: attachmentB64,
      attachmentMime: attachmentMime,
      voiceSecs: voiceSecs,
      lat: lat,
      lon: lon,
      contactId: contactId,
      contactName: contactName,
    );
  }

  @override
  Future<ChatContact> resolveDevice(String id) async {
    resolveDeviceCallCount += 1;
    resolvedDeviceIds.add(id);
    final error = resolveDeviceError;
    if (error != null) throw error;
    return ChatContact(
      id: id,
      publicKeyB64: 'pub-$id',
      fingerprint: 'fp-$id',
      name: 'Peer $id',
    );
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
    sendDirectMessageCallCount += 1;
    directMessagePeerIds.add(peer.id);
    return ChatMessage(
      id: 'dm_${sendDirectMessageCallCount}',
      senderId: me.id,
      recipientId: peer.id,
      senderPubKeyB64: me.publicKeyB64,
      nonceB64: 'nonce',
      boxB64: plainText,
      sealedSender: sealedSender,
      senderHint: senderHint,
      createdAt: DateTime.utc(2026, 3, 27, 0, 0, sendDirectMessageCallCount),
    );
  }

  @override
  Stream<ChatGroupInboxUpdate> streamGroupInbox({required String deviceId}) {
    return const Stream<ChatGroupInboxUpdate>.empty();
  }

  @override
  Stream<ChatTypingSignal> streamTypingSignals({required String deviceId}) {
    return const Stream<ChatTypingSignal>.empty();
  }
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
    await _saveIdentity();
  });

  testWidgets(
      'ChatLocalStore savePinnedChatOrderState updates only the targeted chat key',
      (tester) async {
    final store = ChatLocalStore();
    await store.savePinnedChatOrder(
      <String>['peer-2', 'grp:group-2'],
      baseUrlOverride: _groupBaseUrl,
    );

    await store.savePinnedChatOrderState(
      'grp:$_groupId',
      true,
      baseUrlOverride: _groupBaseUrl,
    );

    expect(
      await store.loadPinnedChatOrder(baseUrlOverride: _groupBaseUrl),
      <String>['grp:$_groupId', 'peer-2', 'grp:group-2'],
    );
  });

  testWidgets('GroupChatPage reauths on critical startup group load failure',
      (tester) async {
    var reauthTriggered = false;
    await tester.pumpWidget(
      _groupTestApp(
        service: _FakeGroupChatService(
          listGroupsError: const ChatHttpException(
            op: 'groups list',
            statusCode: 401,
            body: '{"detail":"auth session required"}',
          ),
        ),
        onCriticalSessionFailure: () => reauthTriggered = true,
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(reauthTriggered, isTrue);
  });

  testWidgets(
      'GroupChatPage paginates group inbox and keeps latest window on startup',
      (tester) async {
    List<ChatGroupMessage> makePage(int start, int end) {
      return List<ChatGroupMessage>.generate(end - start + 1, (index) {
        final number = start + index;
        return ChatGroupMessage(
          id: 'msg-${number.toString().padLeft(3, '0')}',
          groupId: _groupId,
          senderId: 'device_2',
          text: 'message $number',
          createdAt: DateTime.utc(2026, 3, 18, 10, 0, number),
        );
      });
    }

    final service = _FakeGroupChatService(
      fetchGroupInboxHandler: ({sinceId, beforeId}) {
        if (sinceId != null) {
          return const <ChatGroupMessage>[];
        }
        if (beforeId == null) {
          return makePage(4, 203);
        }
        if (beforeId == 'msg-004') {
          return makePage(1, 3);
        }
        return const <ChatGroupMessage>[];
      },
    );

    await tester.pumpWidget(
      _groupTestApp(
        service: service,
        onCriticalSessionFailure: () {},
      ),
    );

    await tester.pump();
    await tester.pump();

    final stored = await ChatLocalStore().loadGroupMessages(
      _groupId,
      baseUrlOverride: _groupBaseUrl,
    );

    expect(service.fetchGroupInboxCallCount, 2);
    expect(service.fetchGroupInboxSinceIds, <String?>[null, null]);
    expect(service.fetchGroupInboxBeforeIds, <String?>[null, 'msg-004']);
    expect(stored, hasLength(50));
    expect(stored.first.id, 'msg-154');
    expect(stored.last.id, 'msg-203');
  });

  testWidgets(
      'GroupChatPage loads older retained group history on demand after startup',
      (tester) async {
    List<ChatGroupMessage> makePage(int start, int end) {
      return List<ChatGroupMessage>.generate(end - start + 1, (index) {
        final number = start + index;
        return ChatGroupMessage(
          id: 'msg-${number.toString().padLeft(3, '0')}',
          groupId: _groupId,
          senderId: 'device_2',
          text: 'message $number',
          createdAt: DateTime.utc(2026, 3, 18, 10, 0, number),
        );
      });
    }

    final service = _FakeGroupChatService(
      fetchGroupInboxHandler: ({sinceId, beforeId}) {
        if (sinceId != null) {
          return const <ChatGroupMessage>[];
        }
        if (beforeId == null) {
          return makePage(4, 203);
        }
        if (beforeId == 'msg-004') {
          return makePage(1, 3);
        }
        if (beforeId == 'msg-154') {
          return makePage(1, 153);
        }
        return const <ChatGroupMessage>[];
      },
    );

    await tester.pumpWidget(
      _groupTestApp(
        service: service,
        onCriticalSessionFailure: () {},
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('Load older messages'), findsOneWidget);

    final dynamic state = tester.state(find.byType(GroupChatPage));
    expect(state.debugHasOlderMessages(), isTrue);

    await state.debugLoadOlderMessages();
    await tester.pump();

    final stored = await ChatLocalStore().loadGroupMessages(
      _groupId,
      baseUrlOverride: _groupBaseUrl,
    );

    expect(service.fetchGroupInboxBeforeIds, <String?>[
      null,
      'msg-004',
      'msg-154',
    ]);
    expect(stored, hasLength(203));
    expect(stored.first.id, 'msg-001');
    expect(stored.last.id, 'msg-203');
    expect(state.debugHasOlderMessages(), isFalse);
    expect(find.text('Load older messages'), findsNothing);
  });

  testWidgets('GroupChatPage reauths on critical group update failure',
      (tester) async {
    var reauthTriggered = false;
    await tester.pumpWidget(
      _groupTestApp(
        service: _FakeGroupChatService(
          updateGroupError: const ChatHttpException(
            op: 'group update',
            statusCode: 401,
            body: '{"detail":"auth session required"}',
          ),
        ),
        onCriticalSessionFailure: () => reauthTriggered = true,
      ),
    );

    await tester.pump();
    await tester.pump();

    final dynamic state = tester.state(find.byType(GroupChatPage));
    await state.debugUpdateGroup(name: 'Renamed Group');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(reauthTriggered, isTrue);
  });

  testWidgets('GroupChatPage reauths on critical members refresh failure',
      (tester) async {
    var reauthTriggered = false;
    await tester.pumpWidget(
      _groupTestApp(
        service: _FakeGroupChatService(
          listGroupMembersError: const ChatHttpException(
            op: 'group members',
            statusCode: 401,
            body: '{"detail":"auth session required"}',
          ),
        ),
        onCriticalSessionFailure: () => reauthTriggered = true,
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(reauthTriggered, isTrue);
  });

  testWidgets('GroupChatPage uses paged group members refresh', (tester) async {
    final service = _FakeGroupChatService(
      listGroupMembersPagedHandler: ({
        required String groupId,
        required String deviceId,
        int batchSize = 200,
        int maxPages = 25,
      }) async {
        return const <ChatGroupMember>[
          ChatGroupMember(deviceId: _deviceId, role: 'admin'),
          ChatGroupMember(deviceId: 'device_2', role: 'member'),
        ];
      },
    );
    await tester.pumpWidget(
      _groupTestApp(
        service: service,
        onCriticalSessionFailure: () {},
      ),
    );

    await tester.pump();
    await tester.pump();

    final dynamic state = tester.state(find.byType(GroupChatPage));
    await state.debugRefreshMembers();
    await tester.pump();

    expect(service.listGroupMembersPagedCallCount, greaterThanOrEqualTo(1));
  });

  testWidgets(
      'GroupChatPage stops retrying non-contact member discovery after fail-closed lookup',
      (tester) async {
    final service = _FakeGroupChatService(
      resolveDeviceError: const ChatHttpException(
        op: 'resolveDevice',
        statusCode: 404,
        body: '{"detail":"not found"}',
      ),
    );
    await tester.pumpWidget(
      _groupTestApp(
        service: service,
        onCriticalSessionFailure: () {},
      ),
    );

    await tester.pump();
    await tester.pump();

    final initialResolveCalls = service.resolveDeviceCallCount;
    expect(initialResolveCalls, greaterThan(0));

    final dynamic state = tester.state(find.byType(GroupChatPage));
    await state.debugRefreshMembers();
    await tester.pump();
    await tester.pump();

    expect(service.resolveDeviceCallCount, initialResolveCalls);
  });

  testWidgets(
      'GroupChatPage warns when group key rotation cannot share to non-contact members',
      (tester) async {
    final service = _FakeGroupChatService(
      resolveDeviceError: const ChatHttpException(
        op: 'resolveDevice',
        statusCode: 404,
        body: '{"detail":"not found"}',
      ),
    );
    await tester.pumpWidget(
      _groupTestApp(
        service: service,
        onCriticalSessionFailure: () {},
      ),
    );

    await tester.pump();
    await tester.pump();

    final initialResolveCalls = service.resolveDeviceCallCount;
    final dynamic state = tester.state(find.byType(GroupChatPage));
    await state.debugRotateGroupKey();
    await tester.pump();
    await tester.pump();

    expect(service.resolveDeviceCallCount, initialResolveCalls);
    expect(service.sendDirectMessageCallCount, 0);
    expect(state.debugErrorText(), contains('direct contact'));
  });

  testWidgets('GroupChatPage reauths on critical group role change failure',
      (tester) async {
    var reauthTriggered = false;
    await tester.pumpWidget(
      _groupTestApp(
        service: _FakeGroupChatService(
          setGroupRoleError: const ChatHttpException(
            op: 'group set role',
            statusCode: 401,
            body: '{"detail":"auth session required"}',
          ),
        ),
        onCriticalSessionFailure: () => reauthTriggered = true,
      ),
    );

    await tester.pump();
    await tester.pump();

    final dynamic state = tester.state(find.byType(GroupChatPage));
    await state.debugSetGroupRole(targetId: 'device_2', role: 'member');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(reauthTriggered, isTrue);
  });

  testWidgets('GroupChatPage reauths on critical group invite failure',
      (tester) async {
    var reauthTriggered = false;
    await tester.pumpWidget(
      _groupTestApp(
        service: _FakeGroupChatService(
          inviteGroupMembersError: const ChatHttpException(
            op: 'group invite',
            statusCode: 401,
            body: '{"detail":"auth session required"}',
          ),
        ),
        onCriticalSessionFailure: () => reauthTriggered = true,
      ),
    );

    await tester.pump();
    await tester.pump();

    final dynamic state = tester.state(find.byType(GroupChatPage));
    await state.debugInviteMembers(<String>['device_2']);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(reauthTriggered, isTrue);
  });

  testWidgets('GroupChatPage reauths on critical leave-group failure',
      (tester) async {
    var reauthTriggered = false;
    await tester.pumpWidget(
      _groupTestApp(
        service: _FakeGroupChatService(
          leaveGroupError: const ChatHttpException(
            op: 'group leave',
            statusCode: 401,
            body: '{"detail":"auth session required"}',
          ),
        ),
        onCriticalSessionFailure: () => reauthTriggered = true,
      ),
    );

    await tester.pump();
    await tester.pump();

    final dynamic state = tester.state(find.byType(GroupChatPage));
    await state.debugLeaveGroup();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(reauthTriggered, isTrue);
  });

  testWidgets(
      'GroupChatPage unarchives only the active group through the targeted store contract',
      (tester) async {
    final store = ChatLocalStore();
    await store.saveArchivedGroups(
      <String>{_groupId, 'group-2'},
      baseUrlOverride: _groupBaseUrl,
    );

    await tester.pumpWidget(
      _groupTestApp(
        service: _FakeGroupChatService(),
        onCriticalSessionFailure: () {},
      ),
    );

    await tester.pump();
    await tester.pump();

    final dynamic state = tester.state(find.byType(GroupChatPage));
    await state.debugUnarchiveGroupIfNeeded();

    expect(
      await store.loadArchivedGroups(baseUrlOverride: _groupBaseUrl),
      <String>{'group-2'},
    );
  });

  testWidgets('GroupChatPage reauths on critical group mute failure',
      (tester) async {
    var reauthTriggered = false;
    await tester.pumpWidget(
      _groupTestApp(
        service: _FakeGroupChatService(
          setGroupPrefsError: const ChatHttpException(
            op: 'group prefs update',
            statusCode: 401,
            body: '{"detail":"auth session required"}',
          ),
        ),
        onCriticalSessionFailure: () => reauthTriggered = true,
      ),
    );

    await tester.pump();
    await tester.pump();

    final dynamic state = tester.state(find.byType(GroupChatPage));
    await state.debugSetGroupMuted(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(reauthTriggered, isTrue);
  });

  testWidgets(
      'GroupChatPage resolves current group prefs via targeted paged lookup',
      (tester) async {
    final service = _FakeGroupChatService(
      fetchGroupPrefForGroupHandler: ({
        required String deviceId,
        required String groupId,
        int batchSize = 200,
        int maxPages = 25,
      }) async {
        return const ChatGroupPrefs(
          groupId: _groupId,
          muted: true,
          pinned: true,
        );
      },
    );

    await tester.pumpWidget(
      _groupTestApp(
        service: service,
        onCriticalSessionFailure: () {},
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(service.fetchGroupPrefForGroupCallCount, 1);
    expect(service.fetchGroupPrefsCallCount, 0);
  });

  testWidgets(
      'GroupChatPage resolves current group metadata via targeted group lookup',
      (tester) async {
    final service = _FakeGroupChatService(
      fetchGroupByIdHandler: ({
        required String deviceId,
        required String groupId,
        int batchSize = 200,
        int? maxPages,
      }) async {
        return const ChatGroup(
          id: _groupId,
          name: 'Renamed Security Group',
          creatorId: _deviceId,
          memberCount: 2,
        );
      },
    );

    await tester.pumpWidget(
      _groupTestApp(
        service: service,
        onCriticalSessionFailure: () {},
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(service.fetchGroupByIdCallCount, 1);
  });

  testWidgets(
      'GroupChatPage waits for group chat theme persistence before committing local theme state',
      (tester) async {
    final delayedThemeSave = Completer<void>();

    await tester.pumpWidget(
      _groupTestApp(
        service: _FakeGroupChatService(),
        onCriticalSessionFailure: () {},
        saveChatThemeForGroupOverride: (groupId, themeKey) async {
          await delayedThemeSave.future;
          await ChatLocalStore().saveChatThemeForGroup(
            groupId,
            themeKey,
            baseUrlOverride: _groupBaseUrl,
          );
        },
      ),
    );

    await tester.pump();
    await tester.pump();

    final dynamic state = tester.state(find.byType(GroupChatPage));
    final pending = state.debugSetChatThemeKey('dark');
    await tester.pump();

    expect(state.debugChatThemeKey(), 'default');

    delayedThemeSave.complete();
    await pending;
    await tester.pump();

    expect(state.debugChatThemeKey(), 'dark');
    expect(
      await ChatLocalStore().loadChatThemes(baseUrlOverride: _groupBaseUrl),
      <String, String>{'grp:$_groupId': 'dark'},
    );
  });

  testWidgets('GroupChatPage clears unread through the targeted group contract',
      (tester) async {
    final unreadCalls = <({String groupId, int unreadCount})>[];

    await tester.pumpWidget(
      _groupTestApp(
        service: _FakeGroupChatService(),
        onCriticalSessionFailure: () {},
        saveUnreadCountForGroupOverride: (groupId, unreadCount) async {
          unreadCalls.add((groupId: groupId, unreadCount: unreadCount));
        },
      ),
    );

    await tester.pump();
    await tester.pump();

    unreadCalls.clear();

    final dynamic state = tester.state(find.byType(GroupChatPage));
    await state.debugMarkSeenAndClearUnread();

    expect(
      unreadCalls,
      <({String groupId, int unreadCount})>[
        (groupId: _groupId, unreadCount: 0),
      ],
    );
  });

  testWidgets(
      'GroupChatPage loads unread count through the targeted group contract',
      (tester) async {
    final unreadCalls = <String>[];

    await tester.pumpWidget(
      _groupTestApp(
        service: _FakeGroupChatService(),
        onCriticalSessionFailure: () {},
        loadUnreadCountForGroupOverride: (groupId) async {
          unreadCalls.add(groupId);
          return 3;
        },
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(unreadCalls, <String>[_groupId]);
  });

  testWidgets('GroupChatPage marks seen through the targeted group contract',
      (tester) async {
    final seenCalls = <({String groupId, DateTime ts})>[];

    await tester.pumpWidget(
      _groupTestApp(
        service: _FakeGroupChatService(),
        onCriticalSessionFailure: () {},
        saveGroupSeenForGroupOverride: (groupId, ts) async {
          seenCalls.add((groupId: groupId, ts: ts));
        },
      ),
    );

    await tester.pump();
    await tester.pump();

    seenCalls.clear();

    final dynamic state = tester.state(find.byType(GroupChatPage));
    await state.debugMarkSeenAndClearUnread();

    expect(seenCalls, hasLength(1));
    expect(seenCalls.single.groupId, _groupId);
  });

  testWidgets('GroupChatPage reauths on critical group pin failure',
      (tester) async {
    var reauthTriggered = false;
    await tester.pumpWidget(
      _groupTestApp(
        service: _FakeGroupChatService(
          setGroupPrefsError: const ChatHttpException(
            op: 'group prefs update',
            statusCode: 401,
            body: '{"detail":"auth session required"}',
          ),
        ),
        onCriticalSessionFailure: () => reauthTriggered = true,
      ),
    );

    await tester.pump();
    await tester.pump();

    final dynamic state = tester.state(find.byType(GroupChatPage));
    await state.debugSetGroupPinned(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(reauthTriggered, isTrue);
  });

  testWidgets(
      'GroupChatPage updates pinned chat order through the targeted chat contract',
      (tester) async {
    final store = ChatLocalStore();
    await store.savePinnedChatOrder(
      <String>['peer-2', 'grp:group-2'],
      baseUrlOverride: _groupBaseUrl,
    );

    await tester.pumpWidget(
      _groupTestApp(
        service: _FakeGroupChatService(),
        onCriticalSessionFailure: () {},
      ),
    );

    await tester.pump();
    await tester.pump();

    final dynamic state = tester.state(find.byType(GroupChatPage));
    await state.debugSetGroupPinned(true);
    await tester.pump();

    expect(
      await store.loadPinnedChatOrder(baseUrlOverride: _groupBaseUrl),
      <String>['grp:$_groupId', 'peer-2', 'grp:group-2'],
    );
  });

  testWidgets('GroupChatPage reauths on critical key-events load failure',
      (tester) async {
    var reauthTriggered = false;
    await tester.pumpWidget(
      _groupTestApp(
        service: _FakeGroupChatService(
          listGroupKeyEventsError: const ChatHttpException(
            op: 'group key events',
            statusCode: 401,
            body: '{"detail":"auth session required"}',
          ),
        ),
        onCriticalSessionFailure: () => reauthTriggered = true,
      ),
    );

    await tester.pump();
    await tester.pump();

    final dynamic state = tester.state(find.byType(GroupChatPage));
    await state.debugLoadGroupKeyEvents();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(reauthTriggered, isTrue);
  });

  testWidgets('GroupChatPage paginates group key events history',
      (tester) async {
    final service = _FakeGroupChatService(
      listGroupKeyEventsPagedHandler: ({
        required groupId,
        required deviceId,
        batchSize = 50,
        maxPages = 20,
      }) async {
        expect(groupId, _groupId);
        expect(deviceId, _deviceId);
        expect(batchSize, 50);
        expect(maxPages, 20);
        return const <ChatGroupKeyEvent>[
          ChatGroupKeyEvent(
            groupId: _groupId,
            version: 3,
            actorId: _deviceId,
          ),
        ];
      },
    );

    await tester.pumpWidget(
      _groupTestApp(
        service: service,
        onCriticalSessionFailure: () {},
      ),
    );
    await tester.pump();
    await tester.pump();

    final dynamic state = tester.state(find.byType(GroupChatPage));
    await state.debugLoadGroupKeyEvents();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(service.listGroupKeyEventsPagedCallCount, greaterThanOrEqualTo(1));
  });

  testWidgets('GroupChatPage reauths on critical key-rotation failure',
      (tester) async {
    var reauthTriggered = false;
    await tester.pumpWidget(
      _groupTestApp(
        service: _FakeGroupChatService(
          rotateGroupKeyError: const ChatHttpException(
            op: 'group key rotate',
            statusCode: 401,
            body: '{"detail":"auth session required"}',
          ),
        ),
        onCriticalSessionFailure: () => reauthTriggered = true,
      ),
    );

    await tester.pump();
    await tester.pump();

    final dynamic state = tester.state(find.byType(GroupChatPage));
    await state.debugRotateGroupKey();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(reauthTriggered, isTrue);
  });

  testWidgets('GroupChatPage reauths on critical group text-send failure',
      (tester) async {
    var reauthTriggered = false;
    await tester.pumpWidget(
      _groupTestApp(
        service: _FakeGroupChatService(
          sendGroupMessageError: const ChatHttpException(
            op: 'group send',
            statusCode: 401,
            body: '{"detail":"auth session required"}',
          ),
        ),
        onCriticalSessionFailure: () => reauthTriggered = true,
      ),
    );

    await tester.pump();
    await tester.pump();

    final dynamic state = tester.state(find.byType(GroupChatPage));
    await state.debugSendTextQuick('hello');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(reauthTriggered, isTrue);
  });

  testWidgets(
      'GroupChatPage ignores concurrent group sends while one is in flight',
      (tester) async {
    final gate = Completer<void>();
    final service = _FakeGroupChatService(sendGroupMessageGate: gate);

    await tester.pumpWidget(
      _groupTestApp(
        service: service,
        onCriticalSessionFailure: () {},
      ),
    );

    await tester.pump();
    await tester.pump();

    final dynamic state = tester.state(find.byType(GroupChatPage));
    final firstSend = state.debugSendTextQuick('hello');
    final secondSend = state.debugSendTextQuick('hello');
    await tester.pump();

    expect(service.sendGroupMessageCallCount, 1);

    gate.complete();
    await firstSend;
    await secondSend;
    await tester.pump();

    expect(service.sendGroupMessageCallCount, 1);
  });
}
