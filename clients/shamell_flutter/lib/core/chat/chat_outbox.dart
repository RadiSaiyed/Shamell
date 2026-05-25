import 'dart:convert';

/// One pending outgoing-message record in the offline outbox.
///
/// The audit (P0-5) called this out as the single largest unsolved
/// chat-UX gap: messages typed while offline either fail immediately
/// with a snackbar or, after the optimistic-send change, sit forever
/// in `sending` state because the retry loop exhausted and there's no
/// persistent queue to flush on reconnect. This class is the persisted
/// record that survives app-restart, account-switch, and network-flap.
///
/// **Storage shape.** The entry stores *plaintext* (`text`,
/// `attachmentB64`, `replyToMessageId`), **not** the encrypted
/// envelope. Reason: the encrypted envelope is bound to a specific
/// ratchet key version, and by the time we re-send (possibly hours
/// later after a key rotation) that key is stale. The send path will
/// re-encrypt from plaintext using the *current* key state, so the
/// outbox entry is forward-compatible with rotations.
///
/// **PII / privacy.** SharedPreferences on Android is per-app sandbox,
/// not user-encrypted at rest by default. For SyrChat we already keep
/// drafts and message text in similar storage. A future hardening
/// pass should wrap this in `flutter_secure_storage` for the
/// keystore-backed flavour, but that's a separate concern from the
/// outbox lifecycle itself.
class ChatOutboxEntry {
  /// Stable id matching the on-screen optimistic stub
  /// (`local-<ts>-<rand>`, see `chat_send_status.dart`).
  final String localId;

  /// `recipientId` for direct messages. Groups are intentionally
  /// out-of-scope for v1 of the outbox — group sends have a
  /// per-conversation key rotation that adds extra resolution logic.
  final String peerId;

  /// Plaintext body the user typed. Empty for attachment-only sends.
  final String text;

  /// Base64-encoded attachment bytes when present; null otherwise.
  final String? attachmentB64;

  /// MIME type for the attachment, when [attachmentB64] is set.
  final String? attachmentMime;

  /// Server id of the message being replied to, if this is a reply.
  final String? replyToMessageId;

  /// Original moment the user tapped Send — used both as the bubble's
  /// `createdAt` (so the optimistic stub renders at the correct
  /// position in the thread on app restart) and as the staleness
  /// signal for auto-expiry of *very* old queued sends.
  final DateTime createdAt;

  /// Number of times we've attempted the send. Bumped on each
  /// flush-attempt failure. Caller decides when to give up — typical
  /// policy is "drop after 8 attempts spanning ~24 h".
  final int attempt;

  /// Last user-visible failure reason, surfaced under the bubble's
  /// retry chip. Null when the entry is still in flight or fresh.
  final String? lastError;

  const ChatOutboxEntry({
    required this.localId,
    required this.peerId,
    required this.text,
    required this.createdAt,
    this.attachmentB64,
    this.attachmentMime,
    this.replyToMessageId,
    this.attempt = 0,
    this.lastError,
  });

  ChatOutboxEntry withAttempt({
    required int attempt,
    String? lastError,
  }) {
    return ChatOutboxEntry(
      localId: localId,
      peerId: peerId,
      text: text,
      attachmentB64: attachmentB64,
      attachmentMime: attachmentMime,
      replyToMessageId: replyToMessageId,
      createdAt: createdAt,
      attempt: attempt,
      lastError: lastError,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'local_id': localId,
        'peer_id': peerId,
        'text': text,
        if (attachmentB64 != null) 'attachment_b64': attachmentB64,
        if (attachmentMime != null) 'attachment_mime': attachmentMime,
        if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
        'created_at': createdAt.toUtc().toIso8601String(),
        'attempt': attempt,
        if (lastError != null) 'last_error': lastError,
      };

  static ChatOutboxEntry? fromJson(Map<String, Object?> map) {
    final localId = _str(map['local_id']);
    final peerId = _str(map['peer_id']);
    if (localId.isEmpty || peerId.isEmpty) return null;
    DateTime? createdAt;
    final rawTs = map['created_at'];
    if (rawTs is String && rawTs.trim().isNotEmpty) {
      createdAt = DateTime.tryParse(rawTs);
    }
    return ChatOutboxEntry(
      localId: localId,
      peerId: peerId,
      text: _str(map['text']),
      attachmentB64: _strOrNull(map['attachment_b64']),
      attachmentMime: _strOrNull(map['attachment_mime']),
      replyToMessageId: _strOrNull(map['reply_to_message_id']),
      createdAt: createdAt ?? DateTime.fromMillisecondsSinceEpoch(0).toUtc(),
      attempt: _int(map['attempt']),
      lastError: _strOrNull(map['last_error']),
    );
  }

  /// True iff the entry's plaintext is empty AND it has no attachment —
  /// such entries should never have been enqueued, but defensive
  /// callers can use this to silently drop them on load.
  bool get isVacuous => text.trim().isEmpty && (attachmentB64 == null);
}

/// Encodes a list of entries to a single JSON string suitable for
/// SharedPreferences. The wrapper object includes a version key so a
/// future schema change can opt-in to a migration path instead of
/// dropping old queue contents on the floor.
String serializeChatOutbox(List<ChatOutboxEntry> entries) {
  return jsonEncode(<String, Object?>{
    'version': 1,
    'entries': entries.map((e) => e.toJson()).toList(),
  });
}

/// Parses a serialized outbox. Robust to:
/// * empty / null input → empty list
/// * non-JSON garbage → empty list (logs are not produced here to
///   keep the helper test-pure; the caller logs)
/// * future versions → empty list (force re-queue rather than risk
///   misinterpreting unknown fields)
/// * partially-malformed entries → those entries are dropped, the
///   rest of the list is returned. This is the right policy because
///   we'd rather lose one corrupt message than the entire queue.
List<ChatOutboxEntry> deserializeChatOutbox(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const <ChatOutboxEntry>[];
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return const <ChatOutboxEntry>[];
  }
  if (decoded is! Map<String, Object?>) return const <ChatOutboxEntry>[];
  final version = decoded['version'];
  if (version is! int || version != 1) return const <ChatOutboxEntry>[];
  final rawList = decoded['entries'];
  if (rawList is! List) return const <ChatOutboxEntry>[];
  final result = <ChatOutboxEntry>[];
  for (final element in rawList) {
    if (element is Map<String, Object?>) {
      final entry = ChatOutboxEntry.fromJson(element);
      if (entry != null && !entry.isVacuous) {
        result.add(entry);
      }
    } else if (element is Map) {
      final entry = ChatOutboxEntry.fromJson(element.cast<String, Object?>());
      if (entry != null && !entry.isVacuous) {
        result.add(entry);
      }
    }
  }
  return result;
}

/// Default retry-backoff schedule for the outbox flush loop. Steps:
/// `0s, 5s, 15s, 30s, 60s, 120s, 300s, 600s` then capped. The pattern
/// is "try again fast a few times, then back off so we don't drain
/// battery on a long outage." Caller uses [chatOutboxBackoffSeconds]
/// to compute the delay for an entry's current `attempt` count.
const List<int> _chatOutboxBackoffScheduleSeconds = <int>[
  0,
  5,
  15,
  30,
  60,
  120,
  300,
  600,
];

int chatOutboxBackoffSeconds(int attempt) {
  if (attempt <= 0) return _chatOutboxBackoffScheduleSeconds.first;
  if (attempt >= _chatOutboxBackoffScheduleSeconds.length) {
    return _chatOutboxBackoffScheduleSeconds.last;
  }
  return _chatOutboxBackoffScheduleSeconds[attempt];
}

/// Decides whether an entry should be permanently dropped from the
/// queue. Returns `true` for:
/// * `attempt >= maxAttempts` (default 8) — we've genuinely given up
/// * `createdAt` more than `maxAgeHours` old (default 24 h) — even if
///   we never got to attempt 8 (e.g. the user closed the app for a
///   day) the message is now stale, sending it would be more
///   confusing than dropping it.
bool chatOutboxShouldDrop(
  ChatOutboxEntry entry, {
  required DateTime now,
  int maxAttempts = 8,
  int maxAgeHours = 24,
}) {
  if (entry.attempt >= maxAttempts) return true;
  final age = now.toUtc().difference(entry.createdAt.toUtc());
  return age.inHours >= maxAgeHours;
}

String _str(Object? v) {
  if (v == null) return '';
  if (v is String) return v;
  return v.toString();
}

String? _strOrNull(Object? v) {
  if (v == null) return null;
  final s = v is String ? v : v.toString();
  final trimmed = s.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int _int(Object? v) {
  if (v is int) return v;
  if (v is String) return int.tryParse(v) ?? 0;
  if (v is num) return v.toInt();
  return 0;
}
