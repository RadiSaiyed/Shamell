import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shamell_flutter/core/chat/chat_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Captured request details so each test can assert on URL / method /
/// body of the call the service made. Mirrors what MockClient gives
/// the test in a slightly tighter shape.
class _Captured {
  String method = '';
  Uri url = Uri();
  String body = '';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // `_headers` reads the session cookie via flutter_secure_storage,
  // which talks to a platform channel that's not bound in plain VM
  // tests. Mock it with an in-memory store so each request just sees
  // "no cookie" — fine for URL/body-shape assertions.
  const secChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secChannel, (call) async {
      switch (call.method) {
        case 'read':
        case 'containsKey':
          return null;
        case 'readAll':
          return <String, String>{};
        default:
          return null;
      }
    });
    // session_cookie_store also caches the session token in
    // SharedPreferences as a fallback. Mock it to an empty store so
    // _headers' lookup short-circuits cleanly.
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secChannel, null);
  });

  late _Captured captured;
  late http.Client mockClient;

  setUp(() {
    captured = _Captured();
  });

  http.Client makeClient(int status, [Object? body]) {
    return MockClient((req) async {
      captured.method = req.method;
      captured.url = req.url;
      captured.body = req.body;
      final responseBody = body == null
          ? ''
          : (body is String ? body : jsonEncode(body));
      return http.Response(responseBody, status);
    });
  }

  group('ChatService.setGroupMessageReaction', () {
    test('POSTs to /chat/groups/:gid/messages/:mid/reactions with emoji',
        () async {
      mockClient = makeClient(200, {'ok': true});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );

      await svc.setGroupMessageReaction(
        deviceId: 'DEV1',
        groupId: 'grp_xyz',
        messageId: 'msg-1',
        emoji: '👍',
      );

      expect(captured.method, 'POST');
      expect(captured.url.path,
          '/chat/groups/grp_xyz/messages/msg-1/reactions');
      final decoded = jsonDecode(captured.body) as Map<String, Object?>;
      expect(decoded['device_id'], 'DEV1');
      expect(decoded['emoji'], '👍');
      expect(decoded.containsKey('remove'), isFalse);
    });

    test('null/empty emoji sends remove=true', () async {
      mockClient = makeClient(200, {'ok': true});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );

      await svc.setGroupMessageReaction(
        deviceId: 'DEV1',
        groupId: 'grp_xyz',
        messageId: 'msg-1',
        emoji: '',
      );
      final decoded = jsonDecode(captured.body) as Map<String, Object?>;
      expect(decoded['remove'], isTrue);
      expect(decoded.containsKey('emoji'), isFalse);
    });
  });

  group('ChatService.listMessageEditHistory', () {
    test('GETs the right URL and parses the response array', () async {
      mockClient = makeClient(200, [
        {
          'message_id': 'msg-1',
          'revision': 1,
          'editor_device_id': 'DEV1',
          'nonce_b64': 'abc',
          'box_b64': 'def',
          'edited_at': '2026-05-14T08:00:00.000000Z',
        },
        {
          'message_id': 'msg-1',
          'revision': 2,
          'editor_device_id': 'DEV1',
          'nonce_b64': 'aaa',
          'box_b64': 'bbb',
          'edited_at': '2026-05-14T09:00:00.000000Z',
        },
      ]);
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      final res = await svc.listMessageEditHistory(
        deviceId: 'DEV1',
        messageId: 'msg-1',
      );
      expect(captured.method, 'GET');
      expect(captured.url.path, '/chat/messages/msg-1/edit_history');
      expect(captured.url.queryParameters['device_id'], 'DEV1');
      expect(res, hasLength(2));
      expect(res.first['revision'], 1);
      expect(res.last['revision'], 2);
    });

    test('non-list payload returns empty list', () async {
      mockClient = makeClient(200, {'something': 'else'});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      final res = await svc.listMessageEditHistory(
        deviceId: 'DEV1',
        messageId: 'msg-1',
      );
      expect(res, isEmpty);
    });
  });

  group('ChatService.postTypingSignal', () {
    test('POSTs started kind', () async {
      mockClient = makeClient(200, {'ok': true});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.postTypingSignal(
        deviceId: 'DEV1',
        peerId: 'DEV2',
        kind: 'started',
      );
      expect(captured.method, 'POST');
      expect(captured.url.path, '/chat/messages/typing');
      final decoded = jsonDecode(captured.body) as Map<String, Object?>;
      expect(decoded['device_id'], 'DEV1');
      expect(decoded['peer_id'], 'DEV2');
      expect(decoded['kind'], 'started');
    });

    test('throws on 4xx so the chat page can debounce errors', () async {
      mockClient = makeClient(422, 'invalid kind');
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      expect(
        () => svc.postTypingSignal(
          deviceId: 'DEV1',
          peerId: 'DEV2',
          kind: 'WAT',
        ),
        throwsA(isA<ChatHttpException>()),
      );
    });
  });

  group('ChatService.postGroupTypingSignal', () {
    test('POSTs to /chat/groups/:gid/typing with kind', () async {
      mockClient = makeClient(200, {'ok': true});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.postGroupTypingSignal(
        deviceId: 'DEV1',
        groupId: 'grp_xyz',
        kind: 'stopped',
      );
      expect(captured.url.path, '/chat/groups/grp_xyz/typing');
      final decoded = jsonDecode(captured.body) as Map<String, Object?>;
      expect(decoded['kind'], 'stopped');
      expect(decoded.containsKey('peer_id'), isFalse);
    });
  });

  group('ChatService.fetchConversationStats', () {
    test('returns the parsed map on 200', () async {
      mockClient = makeClient(200, {
        'device_id': 'DEV1',
        'peer_id': 'DEV2',
        'total': 42,
        'unread': 3,
        'pinned': 1,
        'latest_seq': 99,
      });
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      final stats = await svc.fetchConversationStats(
        deviceId: 'DEV1',
        peerId: 'DEV2',
      );
      expect(stats, isNotNull);
      expect(stats!['total'], 42);
      expect(stats['unread'], 3);
      expect(stats['pinned'], 1);
      expect(stats['latest_seq'], 99);
    });

    test('returns null on 4xx without throwing — chat list keeps stale tile',
        () async {
      mockClient = makeClient(401, 'unauthorized');
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      final stats = await svc.fetchConversationStats(
        deviceId: 'DEV1',
        peerId: 'DEV2',
      );
      expect(stats, isNull);
    });

    test('returns null on network error without throwing', () async {
      mockClient = MockClient((req) async {
        throw http.ClientException('network down');
      });
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      final stats = await svc.fetchConversationStats(
        deviceId: 'DEV1',
        peerId: 'DEV2',
      );
      expect(stats, isNull);
    });
  });

  group('ChatService.fetchGroupConversationStats', () {
    test('GETs the right URL', () async {
      mockClient = makeClient(200, {'group_id': 'grp_xyz', 'total': 5});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      final stats = await svc.fetchGroupConversationStats(
        deviceId: 'DEV1',
        groupId: 'grp_xyz',
      );
      expect(captured.url.path, '/chat/groups/grp_xyz/conversation_stats');
      expect(stats!['total'], 5);
    });
  });

  group('ChatService.setGroupMessagePin', () {
    test('POSTs the right payload', () async {
      mockClient = makeClient(200, {'ok': true});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.setGroupMessagePin(
        deviceId: 'DEV1',
        groupId: 'grp_xyz',
        messageId: 'msg-1',
        pinned: true,
      );
      expect(captured.url.path, '/chat/groups/grp_xyz/messages/msg-1/pin');
      final decoded = jsonDecode(captured.body) as Map<String, Object?>;
      expect(decoded['device_id'], 'DEV1');
      expect(decoded['pinned'], isTrue);
    });

    test('throws ChatHttpException on 409 (too-many-pinned)', () async {
      mockClient = makeClient(409, 'too many pinned');
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      expect(
        () => svc.setGroupMessagePin(
          deviceId: 'DEV1',
          groupId: 'grp_xyz',
          messageId: 'msg-1',
          pinned: true,
        ),
        throwsA(isA<ChatHttpException>()),
      );
    });
  });

  group('ChatService.setMessageBookmark', () {
    test('bookmarked=true POSTs kind + optional note', () async {
      mockClient = makeClient(200, {'ok': true});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.setMessageBookmark(
        deviceId: 'DEV1',
        messageId: 'msg-1',
        bookmarked: true,
        note: 'follow up later',
        kind: 'direct',
      );
      expect(captured.method, 'POST');
      expect(captured.url.path, '/chat/messages/msg-1/bookmark');
      final decoded = jsonDecode(captured.body) as Map<String, Object?>;
      expect(decoded['device_id'], 'DEV1');
      expect(decoded['bookmarked'], isTrue);
      expect(decoded['kind'], 'direct');
      expect(decoded['note'], 'follow up later');
    });

    test('bookmarked=false omits kind+note', () async {
      mockClient = makeClient(200, {'ok': true});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.setMessageBookmark(
        deviceId: 'DEV1',
        messageId: 'msg-1',
        bookmarked: false,
      );
      final decoded = jsonDecode(captured.body) as Map<String, Object?>;
      expect(decoded['bookmarked'], isFalse);
      expect(decoded.containsKey('kind'), isFalse);
      expect(decoded.containsKey('note'), isFalse);
    });

    test('whitespace-only note is dropped', () async {
      mockClient = makeClient(200, {'ok': true});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.setMessageBookmark(
        deviceId: 'DEV1',
        messageId: 'msg-1',
        bookmarked: true,
        note: '   ',
      );
      final decoded = jsonDecode(captured.body) as Map<String, Object?>;
      expect(decoded.containsKey('note'), isFalse);
    });

    test('group kind threads through', () async {
      mockClient = makeClient(200, {'ok': true});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.setMessageBookmark(
        deviceId: 'DEV1',
        messageId: 'msg-1',
        bookmarked: true,
        kind: 'group',
      );
      final decoded = jsonDecode(captured.body) as Map<String, Object?>;
      expect(decoded['kind'], 'group');
    });
  });

  group('ChatService.listMessageBookmarks', () {
    test('GET with kind filter + limit', () async {
      mockClient = makeClient(200, []);
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.listMessageBookmarks(
        deviceId: 'DEV1',
        kind: 'group',
        limit: 25,
      );
      expect(captured.url.path, '/chat/messages/bookmarks');
      expect(captured.url.queryParameters['device_id'], 'DEV1');
      expect(captured.url.queryParameters['kind'], 'group');
      expect(captured.url.queryParameters['limit'], '25');
    });

    test('omits kind when null', () async {
      mockClient = makeClient(200, []);
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.listMessageBookmarks(deviceId: 'DEV1');
      expect(captured.url.queryParameters.containsKey('kind'), isFalse);
    });

    test('parses array response', () async {
      mockClient = makeClient(200, [
        {
          'message_id': 'msg-1',
          'device_id': 'DEV1',
          'kind': 'direct',
          'note': 'remember this',
          'created_at': '2026-05-14T10:00:00.000000Z',
          'updated_at': '2026-05-14T10:00:00.000000Z',
        },
      ]);
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      final res = await svc.listMessageBookmarks(deviceId: 'DEV1');
      expect(res, hasLength(1));
      expect(res.first['note'], 'remember this');
    });
  });

  group('ChatService.setConversationSnooze', () {
    test('POSTs peer_id + seconds + optional reason', () async {
      mockClient = makeClient(200, {'ok': true});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.setConversationSnooze(
        deviceId: 'DEV1',
        peerId: 'DEV2',
        seconds: 1800,
        reason: 'In meeting',
      );
      expect(captured.url.path, '/chat/messages/snooze');
      final decoded = jsonDecode(captured.body) as Map<String, Object?>;
      expect(decoded['device_id'], 'DEV1');
      expect(decoded['peer_id'], 'DEV2');
      expect(decoded['seconds'], 1800);
      expect(decoded['reason'], 'In meeting');
    });

    test('seconds=0 (clear) omits reason', () async {
      mockClient = makeClient(200, {'ok': true});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.setConversationSnooze(
        deviceId: 'DEV1',
        peerId: 'DEV2',
        seconds: 0,
      );
      final decoded = jsonDecode(captured.body) as Map<String, Object?>;
      expect(decoded['seconds'], 0);
      expect(decoded.containsKey('reason'), isFalse);
    });
  });

  group('ChatService.setGroupConversationSnooze', () {
    test('POSTs to /chat/groups/:gid/snooze', () async {
      mockClient = makeClient(200, {'ok': true});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.setGroupConversationSnooze(
        deviceId: 'DEV1',
        groupId: 'grp_xyz',
        seconds: 3600,
      );
      expect(captured.url.path, '/chat/groups/grp_xyz/snooze');
      final decoded = jsonDecode(captured.body) as Map<String, Object?>;
      expect(decoded['seconds'], 3600);
      expect(decoded.containsKey('peer_id'), isFalse);
    });
  });

  group('ChatService.listConversationSnoozes', () {
    test('parses array response', () async {
      mockClient = makeClient(200, [
        {
          'device_id': 'DEV1',
          'peer_id': 'DEV2',
          'group_id': null,
          'snoozed_until': '2026-05-14T18:00:00.000000Z',
          'reason': 'In meeting',
        },
      ]);
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      final res = await svc.listConversationSnoozes(deviceId: 'DEV1');
      expect(res, hasLength(1));
      expect(res.first['peer_id'], 'DEV2');
      expect(res.first['snoozed_until'], '2026-05-14T18:00:00.000000Z');
    });
  });

  group('ChatService.setSavedReply', () {
    test('POSTs slug + label + body', () async {
      mockClient = makeClient(200, {'ok': true});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.setSavedReply(
        deviceId: 'DEV1',
        slug: 'ack',
        label: 'Got it',
        body: 'Got it, thanks!',
      );
      expect(captured.url.path, '/chat/messages/saved_replies');
      final decoded = jsonDecode(captured.body) as Map<String, Object?>;
      expect(decoded['slug'], 'ack');
      expect(decoded['label'], 'Got it');
      expect(decoded['body'], 'Got it, thanks!');
    });
  });

  group('ChatService.deleteSavedReply', () {
    test('DELETEs to /chat/messages/saved_replies/:slug', () async {
      mockClient = makeClient(200, {'ok': true});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.deleteSavedReply(deviceId: 'DEV1', slug: 'ack');
      expect(captured.method, 'DELETE');
      expect(captured.url.path, '/chat/messages/saved_replies/ack');
      expect(captured.url.queryParameters['device_id'], 'DEV1');
    });
  });

  group('ChatService.listSavedReplies', () {
    test('parses array response with label + body', () async {
      mockClient = makeClient(200, [
        {
          'slug': 'ack',
          'label': 'Got it',
          'body': 'Got it, thanks!',
          'created_at': '2026-05-14T10:00:00.000000Z',
          'updated_at': '2026-05-14T10:00:00.000000Z',
        },
      ]);
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      final res = await svc.listSavedReplies(deviceId: 'DEV1');
      expect(res, hasLength(1));
      expect(res.first['slug'], 'ack');
      expect(res.first['body'], 'Got it, thanks!');
    });
  });

  ChatDirectSendEnvelope envelopeFixture({
    String senderId = 'DEV1',
    String recipientId = 'DEV2',
  }) =>
      ChatDirectSendEnvelope(
        senderId: senderId,
        recipientId: recipientId,
        protocolVersion: 'v2_libsignal',
        senderPubkeyB64: 'AAAA' * 8, // 32 chars, passes server min
        senderDhPubB64: 'BBBB' * 4,
        nonceB64: 'CCCC' * 3,
        boxB64: 'DDDDDDDD',
        sealedSender: true,
        senderHint: 'fp-123',
        keyId: 'k-1',
        prevKeyId: null,
        expireAfterSeconds: 3600,
      );

  group('ChatService.scheduleMessage', () {
    test('POSTs the full envelope + scheduled_for', () async {
      mockClient = makeClient(200, {
        'ok': true,
        'id': 'sched-uuid-1',
        'sender_id': 'DEV1',
        'peer_id': 'DEV2',
        'scheduled_for': '2026-05-15T09:00:00.000000Z',
      });
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      final res = await svc.scheduleMessage(
        deviceId: 'DEV1',
        peerId: 'DEV2',
        envelope: envelopeFixture(),
        scheduledFor: DateTime.utc(2026, 5, 15, 9, 0, 0),
      );
      expect(captured.method, 'POST');
      expect(captured.url.path, '/chat/messages/scheduled');
      final decoded = jsonDecode(captured.body) as Map<String, Object?>;
      expect(decoded['device_id'], 'DEV1');
      expect(decoded['peer_id'], 'DEV2');
      expect(decoded.containsKey('group_id'), isFalse);
      // Envelope fields propagate verbatim — that's what the server
      // worker re-INSERTs at delivery time.
      expect(decoded['protocol_version'], 'v2_libsignal');
      expect(decoded['sender_pubkey_b64'], 'AAAA' * 8);
      expect(decoded['sender_dh_pub_b64'], 'BBBB' * 4);
      expect(decoded['nonce_b64'], 'CCCC' * 3);
      expect(decoded['box_b64'], 'DDDDDDDD');
      expect(decoded['sealed_sender'], true);
      expect(decoded['sender_hint'], 'fp-123');
      expect(decoded['key_id'], 'k-1');
      expect(decoded.containsKey('prev_key_id'), isFalse);
      expect(decoded['expire_after_seconds'], 3600);
      // ISO 8601 with explicit UTC marker.
      expect((decoded['scheduled_for'] as String).endsWith('Z'), isTrue);
      expect(res['id'], 'sched-uuid-1');
    });

    test('uses group_id branch when supplied', () async {
      mockClient = makeClient(200, {'ok': true, 'id': 'x'});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.scheduleMessage(
        deviceId: 'DEV1',
        groupId: 'grp_xyz',
        envelope: envelopeFixture(),
        scheduledFor: DateTime.utc(2026, 6, 1, 12, 0, 0),
      );
      final decoded = jsonDecode(captured.body) as Map<String, Object?>;
      expect(decoded['group_id'], 'grp_xyz');
      expect(decoded.containsKey('peer_id'), isFalse);
    });

    test('throws ChatHttpException on 409 (over-cap)', () async {
      mockClient = makeClient(409, {'error': 'too many pending'});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await expectLater(
        () => svc.scheduleMessage(
          deviceId: 'DEV1',
          peerId: 'DEV2',
          envelope: envelopeFixture(),
          scheduledFor: DateTime.utc(2026, 5, 15),
        ),
        throwsA(isA<ChatHttpException>()),
      );
    });
  });

  group('ChatService.listScheduledMessages', () {
    test('default omits include_terminal / due_only flags', () async {
      mockClient = makeClient(200, []);
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.listScheduledMessages(deviceId: 'DEV1');
      expect(captured.method, 'GET');
      expect(captured.url.path, '/chat/messages/scheduled');
      expect(captured.url.queryParameters['device_id'], 'DEV1');
      expect(captured.url.queryParameters.containsKey('include_terminal'),
          isFalse);
      expect(captured.url.queryParameters.containsKey('due_only'), isFalse);
    });

    test('dueOnly=true appends the query flag', () async {
      mockClient = makeClient(200, []);
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.listScheduledMessages(deviceId: 'DEV1', dueOnly: true);
      expect(captured.url.queryParameters['due_only'], 'true');
    });

    test('includeTerminal=true appends the query flag', () async {
      mockClient = makeClient(200, []);
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.listScheduledMessages(
          deviceId: 'DEV1', includeTerminal: true);
      expect(captured.url.queryParameters['include_terminal'], 'true');
    });

    test('parses array of scheduled rows', () async {
      mockClient = makeClient(200, [
        {
          'id': 'sched-1',
          'peer_id': 'DEV2',
          'group_id': null,
          'payload_b64': '3q2+7w==',
          'payload_kind': 'text',
          'scheduled_for': '2026-05-15T09:00:00.000000Z',
          'created_at': '2026-05-14T18:00:00.000000Z',
          'updated_at': '2026-05-14T18:00:00.000000Z',
          'sent_at': null,
          'cancelled_at': null,
          'attempt_count': 0,
        },
      ]);
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      final rows = await svc.listScheduledMessages(deviceId: 'DEV1');
      expect(rows, hasLength(1));
      expect(rows.first['id'], 'sched-1');
      expect(rows.first['payload_b64'], '3q2+7w==');
      expect(rows.first['sent_at'], isNull);
    });
  });

  group('ChatService.cancelScheduledMessage', () {
    test('DELETEs /chat/messages/scheduled/:id with device_id query',
        () async {
      mockClient = makeClient(200, {'ok': true, 'id': 'sched-1'});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.cancelScheduledMessage(deviceId: 'DEV1', id: 'sched-1');
      expect(captured.method, 'DELETE');
      expect(captured.url.path, '/chat/messages/scheduled/sched-1');
      expect(captured.url.queryParameters['device_id'], 'DEV1');
    });

    test('throws on 404 (id not owned by caller)', () async {
      mockClient = makeClient(404, {'error': 'not found'});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await expectLater(
        () => svc.cancelScheduledMessage(deviceId: 'DEV1', id: 'no-such'),
        throwsA(isA<ChatHttpException>()),
      );
    });
  });

  group('ChatService.markScheduledMessageSent', () {
    test('POSTs /chat/messages/scheduled/:id/sent with delivered_msg_id',
        () async {
      mockClient = makeClient(200, {'ok': true, 'id': 'sched-1'});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.markScheduledMessageSent(
        deviceId: 'DEV1',
        id: 'sched-1',
        deliveredMsgId: 'msg-abc',
      );
      expect(captured.method, 'POST');
      expect(captured.url.path, '/chat/messages/scheduled/sched-1/sent');
      final decoded = jsonDecode(captured.body) as Map<String, Object?>;
      expect(decoded['device_id'], 'DEV1');
      expect(decoded['delivered_msg_id'], 'msg-abc');
    });

    test('omits delivered_msg_id when null', () async {
      mockClient = makeClient(200, {'ok': true});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.markScheduledMessageSent(deviceId: 'DEV1', id: 'sched-1');
      final decoded = jsonDecode(captured.body) as Map<String, Object?>;
      expect(decoded.containsKey('delivered_msg_id'), isFalse);
    });
  });

  group('ChatService.createPoll', () {
    test('POSTs message_id + question + options', () async {
      mockClient = makeClient(200, {
        'id': 'poll-1',
        'message_id': 'msg-abc',
        'question': 'Lunch?',
        'options': [
          {'idx': 0, 'label': 'Pizza', 'votes': 0},
          {'idx': 1, 'label': 'Sushi', 'votes': 0},
        ],
      });
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      final res = await svc.createPoll(
        deviceId: 'DEV1',
        messageId: 'msg-abc',
        question: 'Lunch?',
        options: const ['Pizza', 'Sushi'],
      );
      expect(captured.method, 'POST');
      expect(captured.url.path, '/chat/messages/msg-abc/poll');
      final decoded = jsonDecode(captured.body) as Map<String, Object?>;
      expect(decoded['question'], 'Lunch?');
      expect(decoded['options'], <String>['Pizza', 'Sushi']);
      expect(decoded['multi_select'], false);
      expect(decoded.containsKey('closes_at'), isFalse);
      expect(res['id'], 'poll-1');
    });

    test('passes through multi_select + closes_at', () async {
      mockClient = makeClient(200, {});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.createPoll(
        deviceId: 'DEV1',
        messageId: 'msg-abc',
        question: 'Pick all that apply',
        options: const ['A', 'B', 'C'],
        multiSelect: true,
        anonymous: true,
        closesAt: DateTime.utc(2026, 6, 1, 12, 0, 0),
      );
      final decoded = jsonDecode(captured.body) as Map<String, Object?>;
      expect(decoded['multi_select'], true);
      expect(decoded['anonymous'], true);
      expect((decoded['closes_at'] as String).endsWith('Z'), isTrue);
    });

    test('throws ChatHttpException on 400 (bad options count)', () async {
      mockClient = makeClient(400, {'error': 'need 2..=10 options'});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await expectLater(
        () => svc.createPoll(
          deviceId: 'DEV1',
          messageId: 'msg-abc',
          question: 'q',
          options: const ['solo'],
        ),
        throwsA(isA<ChatHttpException>()),
      );
    });
  });

  group('ChatService.votePoll', () {
    test('POSTs option_idxs', () async {
      mockClient = makeClient(200, {'ok': true, 'option_idxs': [1]});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.votePoll(
        deviceId: 'DEV1',
        pollId: 'poll-1',
        optionIdxs: const [1],
      );
      expect(captured.method, 'POST');
      expect(captured.url.path, '/chat/polls/poll-1/vote');
      final decoded = jsonDecode(captured.body) as Map<String, Object?>;
      expect(decoded['option_idxs'], <int>[1]);
    });

    test('empty option_idxs clears votes', () async {
      mockClient = makeClient(200, {'ok': true, 'option_idxs': []});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.votePoll(
        deviceId: 'DEV1',
        pollId: 'poll-1',
        optionIdxs: const [],
      );
      final decoded = jsonDecode(captured.body) as Map<String, Object?>;
      expect(decoded['option_idxs'], <int>[]);
    });
  });

  group('ChatService.getPoll', () {
    test('GETs /chat/polls/:id with device_id query', () async {
      mockClient = makeClient(200, {
        'id': 'poll-1',
        'question': 'q',
        'options': <Object?>[],
        'my_votes': <int>[],
        'total_voters': 0,
        'closed': false,
      });
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      final res = await svc.getPoll(deviceId: 'DEV1', pollId: 'poll-1');
      expect(captured.method, 'GET');
      expect(captured.url.path, '/chat/polls/poll-1');
      expect(captured.url.queryParameters['device_id'], 'DEV1');
      expect(res['id'], 'poll-1');
    });
  });

  group('ChatService.closePoll', () {
    test('DELETEs /chat/polls/:id', () async {
      mockClient = makeClient(200, {'ok': true});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.closePoll(deviceId: 'DEV1', pollId: 'poll-1');
      expect(captured.method, 'DELETE');
      expect(captured.url.path, '/chat/polls/poll-1');
      expect(captured.url.queryParameters['device_id'], 'DEV1');
    });
  });

  group('ChatService.createStory', () {
    test('POSTs kind + text', () async {
      mockClient = makeClient(200, {
        'id': 'story-1',
        'author_id': 'DEV1',
        'kind': 'text',
      });
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      final res = await svc.createStory(
        deviceId: 'DEV1',
        kind: 'text',
        text: 'Good morning!',
      );
      expect(captured.method, 'POST');
      expect(captured.url.path, '/chat/stories');
      final decoded = jsonDecode(captured.body) as Map<String, Object?>;
      expect(decoded['kind'], 'text');
      expect(decoded['text'], 'Good morning!');
      expect(decoded.containsKey('attachment_b64'), isFalse);
      expect(res['id'], 'story-1');
    });

    test('image story passes attachment fields', () async {
      mockClient = makeClient(200, {});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.createStory(
        deviceId: 'DEV1',
        kind: 'image',
        attachmentB64: 'iVBORw0KGgo=',
        attachmentMime: 'image/png',
      );
      final decoded = jsonDecode(captured.body) as Map<String, Object?>;
      expect(decoded['kind'], 'image');
      expect(decoded['attachment_b64'], 'iVBORw0KGgo=');
      expect(decoded['attachment_mime'], 'image/png');
    });

    test('throws ChatHttpException on 409 over-cap', () async {
      mockClient = makeClient(409, {'error': 'too many live stories'});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await expectLater(
        () => svc.createStory(
          deviceId: 'DEV1',
          text: 'x',
        ),
        throwsA(isA<ChatHttpException>()),
      );
    });
  });

  group('ChatService.listStories', () {
    test('GETs /chat/stories?device_id=...', () async {
      mockClient = makeClient(200, [
        {
          'id': 's1',
          'author_id': 'DEV2',
          'kind': 'text',
          'text': 'hi',
          'is_mine': false,
        }
      ]);
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      final rows = await svc.listStories(deviceId: 'DEV1');
      expect(captured.method, 'GET');
      expect(captured.url.path, '/chat/stories');
      expect(captured.url.queryParameters['device_id'], 'DEV1');
      expect(rows, hasLength(1));
      expect(rows.first['id'], 's1');
    });
  });

  group('ChatService.markStoryViewed', () {
    test('POSTs /chat/stories/:id/view', () async {
      mockClient = makeClient(200, {'ok': true});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.markStoryViewed(deviceId: 'DEV1', storyId: 's1');
      expect(captured.method, 'POST');
      expect(captured.url.path, '/chat/stories/s1/view');
      final decoded = jsonDecode(captured.body) as Map<String, Object?>;
      expect(decoded['device_id'], 'DEV1');
    });
  });

  group('ChatService.deleteStory', () {
    test('DELETEs /chat/stories/:id', () async {
      mockClient = makeClient(200, {'ok': true});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.deleteStory(deviceId: 'DEV1', storyId: 's1');
      expect(captured.method, 'DELETE');
      expect(captured.url.path, '/chat/stories/s1');
      expect(captured.url.queryParameters['device_id'], 'DEV1');
    });
  });

  group('ChatService.getPollByMessage', () {
    test('GETs /chat/messages/:mid/poll on hit', () async {
      mockClient = makeClient(200, {
        'id': 'poll-1',
        'message_id': 'msg-abc',
        'question': 'Lunch?',
        'options': <Object?>[],
      });
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      final res = await svc.getPollByMessage(
        deviceId: 'DEV1',
        messageId: 'msg-abc',
      );
      expect(captured.method, 'GET');
      expect(captured.url.path, '/chat/messages/msg-abc/poll');
      expect(res['id'], 'poll-1');
    });

    test('throws 404 ChatHttpException when the message has no poll',
        () async {
      mockClient = makeClient(404, {'error': 'no poll for message'});
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await expectLater(
        () => svc.getPollByMessage(deviceId: 'DEV1', messageId: 'msg-abc'),
        throwsA(isA<ChatHttpException>().having(
          (e) => e.statusCode,
          'statusCode',
          404,
        )),
      );
    });
  });

  group('ChatService.listGroupMessagePins', () {
    test('GETs without group_id when none provided', () async {
      mockClient = makeClient(200, []);
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.listGroupMessagePins(deviceId: 'DEV1');
      expect(captured.url.queryParameters.containsKey('group_id'), isFalse);
    });

    test('includes group_id when provided', () async {
      mockClient = makeClient(200, []);
      final svc = ChatService(
        'https://api.example.com',
        httpClient: mockClient,
      );
      await svc.listGroupMessagePins(
        deviceId: 'DEV1',
        groupId: 'grp_xyz',
      );
      expect(captured.url.queryParameters['group_id'], 'grp_xyz');
    });
  });
}
