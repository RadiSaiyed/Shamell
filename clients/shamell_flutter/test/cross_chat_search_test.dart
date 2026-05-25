import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_message_payload.dart';
import 'package:shamell_flutter/core/chat/chat_models.dart';
import 'package:shamell_flutter/core/chat/cross_chat_search.dart';

/// Constructs a minimal `ChatMessage` for index-builder tests. The
/// builder only reads `id`, `createdAt`, plus whatever the decode +
/// preview callbacks need — we leave all encryption fields as empty
/// strings since the decode callback is mocked.
ChatMessage _msg(String id, {DateTime? at, String text = ''}) {
  return ChatMessage(
    id: id,
    senderId: 'sender_${id}',
    recipientId: 'recipient_${id}',
    senderPubKeyB64: '',
    nonceB64: '',
    boxB64: '',
    createdAt: at,
  );
}

DecodedChatMessagePayload _decoded(String text) {
  return DecodedChatMessagePayload(
    text: text,
    attachment: null,
    mime: null,
  );
}

void main() {
  group('CrossChatSearchIndex.matches', () {
    test('empty query returns empty list (no "show everything")', () {
      final index = CrossChatSearchIndex(entries: [
        const CrossChatSearchEntry(
          messageId: 'm1',
          conversationId: 'alice',
          isGroup: false,
          haystack: 'hello world',
        ),
      ]);
      expect(index.matches(''), isEmpty);
      expect(index.matches('   '), isEmpty);
    });

    test('substring match across haystack returns the entry', () {
      final index = CrossChatSearchIndex(entries: [
        const CrossChatSearchEntry(
          messageId: 'm1',
          conversationId: 'alice',
          isGroup: false,
          haystack: 'the quick brown fox',
        ),
        const CrossChatSearchEntry(
          messageId: 'm2',
          conversationId: 'bob',
          isGroup: false,
          haystack: 'lazy dog sleeps',
        ),
      ]);
      final results = index.matches('quick');
      expect(results, hasLength(1));
      expect(results.first.messageId, 'm1');
      expect(results.first.conversationId, 'alice');
    });

    test('matches are case-insensitive via lowercased haystack', () {
      final index = CrossChatSearchIndex(entries: [
        const CrossChatSearchEntry(
          messageId: 'm1',
          conversationId: 'alice',
          isGroup: false,
          haystack: 'meeting at 3pm', // pre-lowercased like the builder does
        ),
      ]);
      // The query is uppercase; index calls `.trim().toLowerCase()` on it.
      expect(index.matches('MEETING'), hasLength(1));
    });

    test('results are sorted most-recent-first by sortMs', () {
      final index = CrossChatSearchIndex(entries: [
        const CrossChatSearchEntry(
          messageId: 'old',
          conversationId: 'alice',
          isGroup: false,
          haystack: 'pizza tonight?',
          sortMs: 100,
        ),
        const CrossChatSearchEntry(
          messageId: 'new',
          conversationId: 'bob',
          isGroup: false,
          haystack: 'pizza? maybe',
          sortMs: 200,
        ),
        const CrossChatSearchEntry(
          messageId: 'middle',
          conversationId: 'carol',
          isGroup: false,
          haystack: 'cold pizza for breakfast',
          sortMs: 150,
        ),
      ]);
      final results = index.matches('pizza');
      expect(results.map((e) => e.messageId).toList(),
          <String>['new', 'middle', 'old']);
    });

    test('LRU cache returns the same instance for repeated queries', () {
      final index = CrossChatSearchIndex(entries: [
        const CrossChatSearchEntry(
          messageId: 'm1',
          conversationId: 'alice',
          isGroup: false,
          haystack: 'pizza',
        ),
      ]);
      final first = index.matches('pizza');
      final second = index.matches('pizza');
      expect(identical(first, second), isTrue,
          reason: 'cache hit should not re-allocate the result list');
    });
  });

  group('buildCrossChatSearchEntriesFromDirects', () {
    test('aggregates direct messages with isGroup=false', () {
      final directs = {
        'alice': [
          _msg('m_alice_1',
              at: DateTime.utc(2026, 5, 14, 10, 0), text: 'meet tomorrow'),
        ],
        'bob': [
          _msg('m_bob_1',
              at: DateTime.utc(2026, 5, 14, 11, 0), text: 'meet at 5'),
        ],
      };
      final entries = buildCrossChatSearchEntriesFromDirects(
        directMessagesByPeer: directs,
        recalledMessageIdsByPeer: const {},
        decodeMessage: (m) => _decoded(
            m.id == 'm_alice_1' ? 'meet tomorrow' : 'meet at 5'),
        previewText: (m, d) => d.text,
      );
      expect(entries, hasLength(2));
      for (final e in entries) {
        expect(e.isGroup, isFalse);
      }
      final alice = entries.firstWhere((e) => e.messageId == 'm_alice_1');
      expect(alice.conversationId, 'alice');
    });

    test('skips messages in the recalled set', () {
      final directs = {
        'alice': [
          _msg('keeper', at: DateTime.utc(2026, 5, 14), text: 'hello world'),
          _msg('recalled',
              at: DateTime.utc(2026, 5, 14), text: 'hello secret'),
        ],
      };
      final entries = buildCrossChatSearchEntriesFromDirects(
        directMessagesByPeer: directs,
        recalledMessageIdsByPeer: const {
          'alice': {'recalled'},
        },
        decodeMessage: (m) =>
            _decoded(m.id == 'keeper' ? 'hello world' : 'hello secret'),
        previewText: (m, d) => d.text,
      );
      expect(entries.map((e) => e.messageId).toList(), <String>['keeper']);
    });

    test('truncates long previews with an ellipsis', () {
      final longText = 'pizza ' * 40;
      final directs = {
        'alice': [_msg('long', at: DateTime.utc(2026, 5, 14), text: longText)],
      };
      final entries = buildCrossChatSearchEntriesFromDirects(
        directMessagesByPeer: directs,
        recalledMessageIdsByPeer: const {},
        decodeMessage: (m) => _decoded(longText),
        previewText: (m, d) => d.text,
        previewMaxLength: 60,
      );
      expect(entries.single.previewSnippet, endsWith('…'));
      expect(entries.single.previewSnippet.length, lessThanOrEqualTo(60));
    });

    test('empty haystacks are excluded', () {
      final directs = {
        'alice': [_msg('empty', at: DateTime.utc(2026, 5, 14))],
      };
      final entries = buildCrossChatSearchEntriesFromDirects(
        directMessagesByPeer: directs,
        recalledMessageIdsByPeer: const {},
        decodeMessage: (m) => _decoded(''),
        previewText: (m, d) => '',
      );
      expect(entries, isEmpty);
    });

    test('decode failure on one message does not poison the rest', () {
      var callCount = 0;
      final directs = {
        'alice': [
          _msg('good', at: DateTime.utc(2026, 5, 14), text: 'pizza pie'),
          _msg('bad', at: DateTime.utc(2026, 5, 14), text: 'pizza secret'),
        ],
      };
      final entries = buildCrossChatSearchEntriesFromDirects(
        directMessagesByPeer: directs,
        recalledMessageIdsByPeer: const {},
        decodeMessage: (m) {
          callCount += 1;
          if (m.id == 'bad') throw StateError('corrupt');
          return _decoded('pizza pie');
        },
        previewText: (m, d) => d.text,
      );
      expect(entries.map((e) => e.messageId).toList(), <String>['good']);
      expect(callCount, 2);
    });
  });

  group('buildCrossChatSearchEntriesFromGroups', () {
    test('aggregates group messages with isGroup=true', () {
      // Use a simple record-like Map<String, dynamic> as the group msg
      // payload so the test doesn't depend on chat_models internals.
      final groups = {
        'grp_team': <Map<String, dynamic>>[
          {
            'id': 'm_grp_1',
            'text': 'team meet',
            'created_at': DateTime.utc(2026, 5, 14, 12, 0),
          },
          {
            'id': 'm_grp_2',
            'text': 'lunch tomorrow',
            'created_at': DateTime.utc(2026, 5, 14, 13, 0),
          },
        ],
      };
      final entries = buildCrossChatSearchEntriesFromGroups<Map<String, dynamic>>(
        groupMessagesByGroup: groups,
        recalledMessageIdsByGroup: const {},
        extractId: (m) => m['id'] as String,
        extractText: (m) => m['text'] as String,
        extractCreatedAt: (m) => m['created_at'] as DateTime?,
      );
      expect(entries, hasLength(2));
      for (final e in entries) {
        expect(e.isGroup, isTrue);
        expect(e.conversationId, 'grp_team');
      }
    });

    test('combines text + contactName + mime into the haystack', () {
      final groups = {
        'grp_team': <Map<String, dynamic>>[
          {
            'id': 'm1',
            'text': 'see attached',
            'contact_name': 'Bob Smith',
            'mime': 'image/png',
            'created_at': DateTime.utc(2026, 5, 14),
          },
        ],
      };
      final entries = buildCrossChatSearchEntriesFromGroups<Map<String, dynamic>>(
        groupMessagesByGroup: groups,
        recalledMessageIdsByGroup: const {},
        extractId: (m) => m['id'] as String,
        extractText: (m) => m['text'] as String,
        extractCreatedAt: (m) => m['created_at'] as DateTime?,
        extractContactName: (m) => m['contact_name'] as String?,
        extractMime: (m) => m['mime'] as String?,
      );
      final index = CrossChatSearchIndex(entries: entries);
      expect(index.matches('bob smith'), hasLength(1));
      expect(index.matches('image/png'), hasLength(1));
      expect(index.matches('attached'), hasLength(1));
    });
  });

  group('buildCrossChatSearchIndex composer', () {
    test('combines direct + group entries into a single matchable index', () {
      final direct = const CrossChatSearchEntry(
        messageId: 'd1',
        conversationId: 'alice',
        isGroup: false,
        haystack: 'pizza tonight',
        sortMs: 1000,
      );
      final group = const CrossChatSearchEntry(
        messageId: 'g1',
        conversationId: 'grp_team',
        isGroup: true,
        haystack: 'pizza for the team',
        sortMs: 2000,
      );
      final index = buildCrossChatSearchIndex(
        directEntries: [direct],
        groupEntries: [group],
      );
      final hits = index.matches('pizza');
      expect(hits, hasLength(2));
      // Group entry has the higher sortMs and should come first.
      expect(hits.first.messageId, 'g1');
    });
  });
}
