/// Pure-helper parser for FCM `data:` payloads delivered as
/// `chat_wakeup` push notifications.
///
/// The server-side push enricher (`chat_service::handlers::
/// build_chat_wakeup_alert_data`) currently emits a minimal payload —
/// just `type: "chat_wakeup"` plus opaque fields. To make a *tap* on
/// the notification deep-link straight to the exact message, we need a
/// stable, schema'd contract for the data fields. This file declares
/// that contract on the client side, with a defensive parser that
/// degrades gracefully when the server hasn't yet started populating
/// the new fields.
///
/// Schema (post-P0-13 server rollout):
/// ```jsonc
/// {
///   "type": "chat_wakeup",
///   "chat_kind": "direct" | "group",
///   "peer_id":  "<sender device id>",   // for direct
///   "group_id": "<group id>",           // for group
///   "message_id": "<server uuid>",
///   "sender_name": "...",
///   "preview": "...",
///   "badge": 42,
///   "ts": "2026-05-13T20:30:00Z"
/// }
/// ```
///
/// Parsing is intentionally tolerant: any of these fields may be
/// missing or malformed. The caller (`_handleChatPushTap`) decides
/// whether a parsed payload has enough information to route to a
/// specific thread, or whether to fall back to "just refresh inbox".

enum ChatPushKind { direct, group, unknown }

class ChatPushPayload {
  /// `chat_kind` field. `unknown` when missing or unrecognized.
  final ChatPushKind kind;

  /// `peer_id` (direct) or `group_id` (group). Empty when neither is
  /// present. Callers can route into a thread iff this is non-empty.
  final String chatId;

  /// Server-canonical message id to scroll to. Empty when the server
  /// hasn't enriched yet; the caller then defaults to "scroll to
  /// bottom + just refresh".
  final String messageId;

  /// Optional human-readable sender label (for banner / log).
  final String? senderName;

  /// Optional preview text (for banner / accessibility).
  final String? preview;

  const ChatPushPayload({
    required this.kind,
    required this.chatId,
    required this.messageId,
    this.senderName,
    this.preview,
  });

  /// True iff the payload carries enough to route to a specific thread.
  bool get hasThreadTarget => chatId.isNotEmpty;

  /// True iff the payload carries enough to scroll to a specific msg.
  bool get hasMessageTarget => hasThreadTarget && messageId.isNotEmpty;
}

ChatPushPayload parseChatPushPayload(Map<String, Object?> data) {
  final type = _str(data['type']).trim().toLowerCase();
  if (type != 'chat_wakeup') {
    return const ChatPushPayload(
      kind: ChatPushKind.unknown,
      chatId: '',
      messageId: '',
    );
  }
  final kindRaw = _str(data['chat_kind']).trim().toLowerCase();
  ChatPushKind kind;
  switch (kindRaw) {
    case 'direct':
    case 'dm':
    case '1on1':
      kind = ChatPushKind.direct;
      break;
    case 'group':
    case 'g':
      kind = ChatPushKind.group;
      break;
    default:
      // If kind is missing but a specific id field is present, infer
      // it. This buys forward-compat with a server that ships peer_id
      // / group_id before it ships the kind discriminator.
      if (_str(data['group_id']).isNotEmpty) {
        kind = ChatPushKind.group;
      } else if (_str(data['peer_id']).isNotEmpty) {
        kind = ChatPushKind.direct;
      } else {
        kind = ChatPushKind.unknown;
      }
  }
  String chatId = '';
  if (kind == ChatPushKind.direct) {
    chatId = _str(data['peer_id']).trim();
  } else if (kind == ChatPushKind.group) {
    chatId = _str(data['group_id']).trim();
  }
  final messageId = _str(data['message_id']).trim();
  final senderName = _strOrNull(data['sender_name'] ?? data['from_name']);
  final preview = _strOrNull(data['preview']);
  return ChatPushPayload(
    kind: kind,
    chatId: chatId,
    messageId: messageId,
    senderName: senderName,
    preview: preview,
  );
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
