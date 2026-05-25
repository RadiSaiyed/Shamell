import 'dart:math' as math;

import 'chat_models.dart';

/// User-visible send-status for an outgoing chat message.
///
/// The state machine progresses left-to-right; `failed` is a sink state that
/// only `sending` can reach. Incoming messages never carry an
/// `OutgoingSendStatus` — they render with timestamp only.
///
/// ```
///   ┌── failed
///   │
/// sending ──► sent ──► delivered ──► read
/// ```
///
/// * `sending` — optimistic local stub, no server ACK yet. Rendered as a tiny
///   clock glyph next to the timestamp so the user knows the bubble is "in
///   flight" rather than thinking the app silently swallowed their tap.
/// * `sent` — server returned a canonical id but the recipient hasn't yet
///   acked delivery. Single check mark (✓).
/// * `delivered` — recipient device received the ciphertext. Double check
///   (✓✓), neutral colour.
/// * `read` — recipient marked it read (or auto-marked while the thread was
///   focused). Double check, accent colour. WhatsApp uses blue, iMessage
///   uses a "Read 12:34" footer — we render the double-check in
///   `colorScheme.primary` for theme consistency.
/// * `failed` — terminal send failure after the retry loop is exhausted, or
///   a critical pre-flight rejection. Bubble renders an inline retry chip;
///   tap re-enqueues the same encrypted envelope.
enum OutgoingSendStatus {
  sending,
  sent,
  delivered,
  read,
  failed,
}

/// Mutable companion record for an outgoing message while it is still local
/// (i.e. the server-canonical [ChatMessage.id] has not yet replaced the
/// local stub). Keyed by [localId] inside `_ShamellChatPageState`'s
/// `_localSendStates` map.
///
/// We intentionally keep this off [ChatMessage]: `ChatMessage` is an
/// immutable wire-shape that several decoders / persistence layers rely on,
/// and it has zero local-mutability semantics. Pushing send state onto a
/// side-channel keeps the model boundary clean and lets a server-driven
/// inbox-replay merge cleanly without resurrecting stale local state.
class LocalSendState {
  /// Stable id of the optimistic stub; matches [ChatMessage.id] for the
  /// duration the stub is in the message list.
  final String localId;

  /// `recipientId` for direct messages or `groupId` for group sends —
  /// used to scope the state per conversation so a `clear()` for one
  /// peer doesn't wipe pending sends on another peer.
  final String peerId;

  /// First moment `_send()` started preparing the envelope; used by
  /// failure UI to render an age ("Failed 5 s ago — tap to retry") and
  /// by the persistence layer to expire ancient queued sends.
  final DateTime startedAt;

  /// Current status. See [OutgoingSendStatus].
  final OutgoingSendStatus status;

  /// Localizable failure reason for `failed`. Null for non-failed states.
  final String? errorReason;

  /// 0-based attempt counter; bumped by retry presses.
  final int attempt;

  const LocalSendState({
    required this.localId,
    required this.peerId,
    required this.startedAt,
    required this.status,
    this.errorReason,
    this.attempt = 0,
  });

  LocalSendState withStatus(
    OutgoingSendStatus next, {
    String? errorReason,
    int? attempt,
  }) {
    return LocalSendState(
      localId: localId,
      peerId: peerId,
      startedAt: startedAt,
      status: next,
      errorReason: errorReason ?? this.errorReason,
      attempt: attempt ?? this.attempt,
    );
  }

  /// True iff the bubble's footer should show a retry affordance.
  bool get canRetry => status == OutgoingSendStatus.failed;

  /// True iff the user can edit/recall/delete this message — we deny
  /// any action on a stub that hasn't been server-canonicalized.
  bool get isStillLocal =>
      status == OutgoingSendStatus.sending ||
      status == OutgoingSendStatus.failed;
}

/// Stable prefix that marks a [ChatMessage.id] as a local optimistic stub
/// (not yet server-canonicalized). Server messages can never match because
/// chat_service issues UUIDv4 ids, which always contain hyphens at fixed
/// positions but never start with this literal token.
const String localChatMessageIdPrefix = 'local-';

/// True iff [id] is an in-flight optimistic stub. Used by:
/// - `_mergeMessages` to skip seen-id dedup for stubs that will be replaced
/// - The bubble's long-press menu to hide non-applicable actions
/// - The persistence layer to skip writing stubs to disk
bool isLocalChatMessageId(String id) => id.startsWith(localChatMessageIdPrefix);

/// Deterministic-enough id factory for a local stub. The output is:
/// `local-<base36 epoch ms>-<random 6>`. Lexicographic sort within local
/// stubs matches insertion order, which keeps the message list stable
/// when two near-simultaneous taps queue two stubs back-to-back.
String makeLocalChatMessageId([math.Random? rng]) {
  final r = rng ?? math.Random.secure();
  final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final tail = StringBuffer();
  for (var i = 0; i < 6; i++) {
    tail.write(_b36Alphabet[r.nextInt(_b36Alphabet.length)]);
  }
  return '$localChatMessageIdPrefix$ts-$tail';
}

const String _b36Alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';

/// Derives the user-visible status for an outgoing message.
///
/// Priority order:
///   1. If a [LocalSendState] is present, it wins. A local stub may have
///      `sending` or `failed`; once the server ACK lands the caller drops
///      the local state, and we fall through to the server-side fields.
///   2. `m.readAt != null` → `read`. This implies delivered, so the
///      delivered check is redundant.
///   3. `m.deliveredAt != null` → `delivered`.
///   4. Default → `sent`.
///
/// Incoming messages should never be passed to this — callers gate on
/// `m.isIncomingFor(meId)` first.
OutgoingSendStatus chatMessageOutgoingStatus({
  required ChatMessage message,
  LocalSendState? localState,
}) {
  if (localState != null) return localState.status;
  if (message.readAt != null) return OutgoingSendStatus.read;
  if (message.deliveredAt != null) return OutgoingSendStatus.delivered;
  return OutgoingSendStatus.sent;
}

/// Days-since-midnight helper used by the date-header label.
///
/// We compare against the *local* calendar day, not 24-h windows: a
/// message sent at 23:59 yesterday should label as "Yesterday", not
/// "Today" just because <24 h have elapsed.
int chatCalendarDaysBetween(DateTime a, DateTime b) {
  final ad = DateTime(a.year, a.month, a.day);
  final bd = DateTime(b.year, b.month, b.day);
  return bd.difference(ad).inDays;
}

/// Builds the relative date label for the thread day-separator.
///
/// * Today    → `"Today"` / `"اليوم"`
/// * Yesterday→ `"Yesterday"` / `"أمس"`
/// * Last 7 d → locale-specific weekday name from [weekdayFormatter]
/// * Else     → locale-specific short date from [shortDateFormatter]
///
/// Both formatters are injected so the function stays test-pure
/// (no BuildContext / MaterialLocalizations dependency in unit tests).
String chatMessageDateHeaderLabel(
  DateTime messageTs, {
  required DateTime now,
  required bool isArabic,
  required String Function(DateTime) shortDateFormatter,
  required String Function(DateTime) weekdayFormatter,
}) {
  final localMsg = messageTs.toLocal();
  final localNow = now.toLocal();
  final delta = chatCalendarDaysBetween(localMsg, localNow);
  if (delta == 0) return isArabic ? 'اليوم' : 'Today';
  if (delta == 1) return isArabic ? 'أمس' : 'Yesterday';
  if (delta > 1 && delta < 7) return weekdayFormatter(localMsg);
  return shortDateFormatter(localMsg);
}
