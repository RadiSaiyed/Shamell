import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/chat/chat_models.dart';
import 'package:shamell_flutter/core/chat/chat_service.dart';
import 'package:shamell_flutter/core/group_chats_page.dart';
import 'package:shamell_flutter/core/l10n.dart';

const _groupsBaseUrl = 'https://api.example.com';
const _groupsDeviceId = 'device_1';

Widget _groupsTestApp({
  required ChatService service,
  required VoidCallback onCriticalSessionFailure,
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
    home: GroupChatsPage(
      baseUrl: _groupsBaseUrl,
      serviceOverride: service,
      onCriticalSessionFailure: onCriticalSessionFailure,
    ),
  );
}

Future<void> _saveIdentity() async {
  await ChatLocalStore().saveIdentity(
    const ChatIdentity(
      id: _groupsDeviceId,
      publicKeyB64: 'pubkey',
      privateKeyB64: 'privkey',
      fingerprint: 'fingerprint',
    ),
    baseUrlOverride: _groupsBaseUrl,
  );
}

class _FakeGroupChatsService extends ChatService {
  _FakeGroupChatsService({
    this.listGroupsError,
    this.createGroupError,
  }) : super(_groupsBaseUrl);

  final Object? listGroupsError;
  final Object? createGroupError;
  int listGroupsCallCount = 0;
  int listGroupsPageCallCount = 0;
  final List<String?> listGroupsBeforeIds = <String?>[];
  String? lastListGroupsBeforeCreatedAt;
  int lastListGroupsLimit = 0;
  Future<List<ChatGroup>> Function({
    required String deviceId,
    required int limit,
    String? beforeCreatedAt,
    String? beforeId,
  })? listGroupsPageHandler;

  @override
  Future<List<ChatGroup>> listGroups({required String deviceId}) async {
    listGroupsCallCount += 1;
    final error = listGroupsError;
    if (error != null) throw error;
    return const <ChatGroup>[];
  }

  @override
  Future<List<ChatGroup>> listGroupsPage({
    required String deviceId,
    int limit = 200,
    String? beforeCreatedAt,
    String? beforeId,
  }) async {
    listGroupsPageCallCount += 1;
    listGroupsBeforeIds.add(beforeId);
    lastListGroupsBeforeCreatedAt = beforeCreatedAt;
    lastListGroupsLimit = limit;
    final handler = listGroupsPageHandler;
    if (handler != null) {
      return handler(
        deviceId: deviceId,
        limit: limit,
        beforeCreatedAt: beforeCreatedAt,
        beforeId: beforeId,
      );
    }
    final error = listGroupsError;
    if (error != null) throw error;
    return const <ChatGroup>[];
  }

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
      id: groupId ?? 'group_1',
      name: name,
      creatorId: deviceId,
      memberCount: 1,
    );
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

  testWidgets('GroupChatsPage reauths on critical group list failure',
      (tester) async {
    var reauthTriggered = false;
    await tester.pumpWidget(
      _groupsTestApp(
        service: _FakeGroupChatsService(
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

  testWidgets('GroupChatsPage reauths on critical group create failure',
      (tester) async {
    var reauthTriggered = false;
    await tester.pumpWidget(
      _groupsTestApp(
        service: _FakeGroupChatsService(
          createGroupError: const ChatHttpException(
            op: 'group create',
            statusCode: 401,
            body: '{"detail":"auth session required"}',
          ),
        ),
        onCriticalSessionFailure: () => reauthTriggered = true,
      ),
    );

    await tester.pump();
    await tester.pump();

    final dynamic state = tester.state(find.byType(GroupChatsPage));
    await state.debugCreateGroup('Alpha');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(reauthTriggered, isTrue);
  });

  testWidgets('GroupChatsPage loads first page only and fetches more on demand',
      (tester) async {
    final service = _FakeGroupChatsService();
    final firstPage = List<ChatGroup>.generate(
      100,
      (index) => ChatGroup(
        id: 'group_${index.toString().padLeft(3, '0')}',
        name: 'Group ${index.toString().padLeft(3, '0')}',
        creatorId: _groupsDeviceId,
        createdAt: DateTime.utc(2026, 3, 19, 12).subtract(
          Duration(minutes: index),
        ),
      ),
    );
    final secondPage = <ChatGroup>[
      ChatGroup(
        id: 'group_100',
        name: 'Group 100',
        creatorId: _groupsDeviceId,
        createdAt: DateTime.utc(2026, 3, 19, 10, 19),
      ),
    ];
    service.listGroupsPageHandler = ({
      required String deviceId,
      required int limit,
      String? beforeCreatedAt,
      String? beforeId,
    }) async {
      expect(deviceId, _groupsDeviceId);
      expect(limit, 100);
      if (beforeId == null) {
        expect(beforeCreatedAt, isNull);
        return firstPage;
      }
      expect(beforeId, 'group_099');
      expect(
        beforeCreatedAt,
        firstPage.last.createdAt!.toUtc().toIso8601String(),
      );
      return secondPage;
    };

    await tester.pumpWidget(
      _groupsTestApp(
        service: service,
        onCriticalSessionFailure: () {},
      ),
    );

    await tester.pump();
    await tester.pump();

    final dynamic state = tester.state(find.byType(GroupChatsPage));
    expect(service.listGroupsCallCount, 0);
    expect(service.listGroupsPageCallCount, 1);
    expect(state.debugHasMoreGroups(), isTrue);
    expect(state.debugGroupsBeforeId(), 'group_099');
    expect(find.text('Group 000'), findsOneWidget);
    expect(find.text('Group 100'), findsNothing);

    await state.debugLoadMoreGroups();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(service.listGroupsPageCallCount, 2);
    expect(service.listGroupsBeforeIds, <String?>[null, 'group_099']);
    expect(find.text('Group 100'), findsOneWidget);
    expect(state.debugHasMoreGroups(), isFalse);
  });
}
