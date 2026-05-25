import 'dart:convert';

import 'chat_models.dart';

typedef ChatThreadDisplayName = String Function(
  String id, {
  String? fallback,
});

enum ChatGroupThreadPreviewSegmentKind { text, mention, mentionHighlight }

class ChatGroupThreadPreviewSegment {
  final String text;
  final ChatGroupThreadPreviewSegmentKind kind;

  const ChatGroupThreadPreviewSegment({
    required this.text,
    this.kind = ChatGroupThreadPreviewSegmentKind.text,
  });
}

class ChatGroupThreadPreviewData {
  final String plainText;
  final List<ChatGroupThreadPreviewSegment> segments;

  const ChatGroupThreadPreviewData({
    required this.plainText,
    this.segments = const <ChatGroupThreadPreviewSegment>[],
  });

  bool get hasStyledSegments => segments.any(
        (segment) => segment.kind != ChatGroupThreadPreviewSegmentKind.text,
      );
}

final RegExp _chatThreadMentionReg = RegExp(r'@([A-Za-z0-9_-]{2,})');
final RegExp _chatThreadMentionWsReg = RegExp(r'\s');
const String _chatThreadArabicAllToken = '@الكل';

String formatChatThreadTimestamp(
  DateTime? timestamp, {
  required DateTime now,
}) {
  if (timestamp == null) return '';
  final dt = timestamp.toLocal();
  final nowLocal = now.toLocal();
  if (dt.year == nowLocal.year &&
      dt.month == nowLocal.month &&
      dt.day == nowLocal.day) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
  return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

String? buildLatestChatCallPreview({
  required ChatCallLogEntry? latestCall,
  required DateTime? latestMessageAt,
  required bool isArabic,
}) {
  if (latestCall == null) return null;
  final msgTs = latestMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  if (!latestCall.ts.isAfter(msgTs)) return null;
  final isOut = latestCall.direction == 'out';
  final missed = !latestCall.accepted;
  final kindLabel = latestCall.kind == 'video'
      ? (isArabic ? 'فيديو' : 'Video')
      : (isArabic ? 'صوت' : 'Voice');
  String status;
  if (missed) {
    status = isArabic ? 'مكالمة فائتة' : 'Missed call';
  } else if (latestCall.duration.inMinutes > 0) {
    status = '${latestCall.duration.inMinutes}m';
  } else {
    status = '${latestCall.duration.inSeconds.remainder(60)}s';
  }
  return '${isOut ? (isArabic ? 'صادر' : 'Outgoing') : (isArabic ? 'وارد' : 'Incoming')} $kindLabel • $status';
}

List<({int start, int end, String rawId})> _collectThreadPreviewMentionMatches(
  String text,
) {
  final matches = <({int start, int end, String rawId})>[];
  for (final mm in _chatThreadMentionReg.allMatches(text)) {
    if (mm.start > 0 && !_chatThreadMentionWsReg.hasMatch(text[mm.start - 1])) {
      continue;
    }
    final rawId = (mm.group(1) ?? '').trim();
    if (rawId.isEmpty) continue;
    matches.add((start: mm.start, end: mm.end, rawId: rawId));
  }

  var idx = text.indexOf(_chatThreadArabicAllToken);
  while (idx != -1) {
    if (idx == 0 || _chatThreadMentionWsReg.hasMatch(text[idx - 1])) {
      matches.add((
        start: idx,
        end: idx + _chatThreadArabicAllToken.length,
        rawId: 'all',
      ));
    }
    idx = text.indexOf(
        _chatThreadArabicAllToken, idx + _chatThreadArabicAllToken.length);
  }

  matches.sort((a, b) => a.start.compareTo(b.start));
  return matches;
}

List<ChatGroupThreadPreviewSegment> _buildThreadPreviewMentionSegments(
  String text, {
  required ChatThreadDisplayName displayName,
  required String currentUserId,
  required bool isArabic,
}) {
  final matches = _collectThreadPreviewMentionMatches(text);
  if (matches.isEmpty) {
    return const <ChatGroupThreadPreviewSegment>[];
  }
  final segments = <ChatGroupThreadPreviewSegment>[];
  final meIdLower = currentUserId.trim().toLowerCase();
  var last = 0;
  for (final match in matches) {
    if (match.start > last) {
      segments.add(
        ChatGroupThreadPreviewSegment(
          text: text.substring(last, match.start),
        ),
      );
    }
    final raw = match.rawId.trim();
    final rawLower = raw.toLowerCase();
    final kind =
        (rawLower == 'all' || (meIdLower.isNotEmpty && rawLower == meIdLower))
            ? ChatGroupThreadPreviewSegmentKind.mentionHighlight
            : ChatGroupThreadPreviewSegmentKind.mention;
    final mentionText = rawLower == 'all'
        ? (isArabic ? '@الكل' : '@all')
        : '@${displayName(raw, fallback: raw)}';
    segments.add(
      ChatGroupThreadPreviewSegment(
        text: mentionText,
        kind: kind,
      ),
    );
    last = match.end;
  }
  if (last < text.length) {
    segments.add(
      ChatGroupThreadPreviewSegment(text: text.substring(last)),
    );
  }
  return segments;
}

String _buildSystemGroupThreadPreviewText(
  ChatGroupMessage message, {
  required ChatThreadDisplayName displayName,
  required bool isArabic,
}) {
  final raw = message.text.trim();
  if (raw.isEmpty) {
    return isArabic ? 'حدث في المجموعة' : 'Group event';
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      final ev = (decoded['event'] ?? '').toString();
      final actor = (decoded['actor_id'] ?? '').toString();
      if (ev == 'invite') {
        final idsRaw = decoded['member_ids'];
        final ids = <String>[];
        if (idsRaw is List) {
          for (final value in idsRaw) {
            final id = value.toString().trim();
            if (id.isNotEmpty) ids.add(id);
          }
        }
        final who = displayName(actor);
        final joined =
            ids.map((id) => displayName(id, fallback: id)).join(', ');
        return isArabic
            ? 'قام $who بإضافة ${ids.isEmpty ? 'أعضاء' : joined}'
            : '$who invited ${ids.isEmpty ? 'members' : joined}';
      }
      if (ev == 'create') {
        final name = (decoded['name'] ?? '').toString();
        final idsRaw = decoded['member_ids'];
        final ids = <String>[];
        if (idsRaw is List) {
          for (final value in idsRaw) {
            final id = value.toString().trim();
            if (id.isNotEmpty) ids.add(id);
          }
        }
        final who = displayName(actor);
        final joined =
            ids.map((id) => displayName(id, fallback: id)).join(', ');
        if (isArabic) {
          final base =
              name.isNotEmpty ? 'أنشأ $who "$name"' : 'أنشأ $who المجموعة';
          return ids.isEmpty ? base : '$base وأضاف $joined';
        }
        final base =
            name.isNotEmpty ? '$who created "$name"' : '$who created the group';
        return ids.isEmpty ? base : '$base and invited $joined';
      }
      if (ev == 'leave') {
        final who = displayName(actor);
        return isArabic ? 'غادر $who المجموعة' : '$who left the group';
      }
      if (ev == 'role') {
        final target = (decoded['target_id'] ?? '').toString();
        final role = (decoded['role'] ?? '').toString();
        final who = displayName(actor);
        final targetLabel = displayName(
          target,
          fallback: isArabic ? 'عضو' : 'a member',
        );
        if (role == 'admin') {
          return isArabic
              ? 'قام $who بترقية $targetLabel'
              : '$who made $targetLabel admin';
        }
        return isArabic
            ? 'قام $who بإزالة صلاحية المشرف من $targetLabel'
            : '$who removed admin from $targetLabel';
      }
      if (ev == 'rename') {
        final newName = (decoded['new_name'] ?? '').toString();
        final who = displayName(actor);
        if (isArabic) {
          return newName.isNotEmpty
              ? 'قام $who بتغيير اسم المجموعة إلى "$newName"'
              : 'قام $who بتغيير اسم المجموعة';
        }
        return newName.isNotEmpty
            ? '$who changed group name to "$newName"'
            : '$who changed group name';
      }
      if (ev == 'avatar') {
        final action = (decoded['action'] ?? '').toString();
        final who = displayName(actor);
        if (isArabic) {
          return action == 'remove'
              ? 'قام $who بإزالة صورة المجموعة'
              : 'قام $who بتغيير صورة المجموعة';
        }
        return action == 'remove'
            ? '$who removed group photo'
            : '$who changed group photo';
      }
      if (ev == 'key_rotated') {
        final ver = (decoded['version'] ?? '').toString();
        final actorLabel = displayName(
          actor,
          fallback: isArabic ? 'مشرف' : 'An admin',
        );
        return isArabic
            ? 'قام $actorLabel بتدوير مفتاح التشفير${ver.isNotEmpty ? ' (v$ver)' : ''}'
            : '$actorLabel rotated encryption key${ver.isNotEmpty ? ' (v$ver)' : ''}';
      }
    }
  } catch (_) {}
  return raw;
}

ChatGroupThreadPreviewData buildChatGroupThreadPreviewData({
  required ChatGroupMessage? message,
  required ChatThreadDisplayName displayName,
  required bool isArabic,
  required String currentUserId,
  required String noMessagesYet,
  required String previewVoice,
  required String previewImage,
  required String encryptedMessageLabel,
}) {
  if (message == null) {
    return ChatGroupThreadPreviewData(plainText: noMessagesYet);
  }
  final kind = (message.kind ?? '').toLowerCase();
  if (kind == 'system') {
    return ChatGroupThreadPreviewData(
      plainText: _buildSystemGroupThreadPreviewText(
        message,
        displayName: displayName,
        isArabic: isArabic,
      ),
    );
  }
  if (kind == 'sealed') {
    return ChatGroupThreadPreviewData(plainText: encryptedMessageLabel);
  }
  if (kind == 'voice') {
    return ChatGroupThreadPreviewData(plainText: previewVoice);
  }

  final mime = (message.attachmentMime ?? '').toLowerCase();
  final isImage = kind == 'image' || mime.startsWith('image/');
  final rawText = isImage ? message.text.trim() : message.text;
  final senderLabel = displayName(message.senderId, fallback: '');
  final mentionSegments = rawText.contains('@')
      ? _buildThreadPreviewMentionSegments(
          rawText,
          displayName: displayName,
          currentUserId: currentUserId,
          isArabic: isArabic,
        )
      : const <ChatGroupThreadPreviewSegment>[];
  final hasRichPreview = mentionSegments.isNotEmpty;

  String plainBody;
  if (isImage) {
    if (hasRichPreview) {
      plainBody = [
        previewImage,
        if (rawText.isNotEmpty)
          mentionSegments.map((segment) => segment.text).join(),
      ].join(rawText.isNotEmpty ? ' ' : '');
    } else {
      plainBody = rawText.isNotEmpty ? '$previewImage $rawText' : previewImage;
    }
  } else if (rawText.isNotEmpty) {
    plainBody = hasRichPreview
        ? mentionSegments.map((segment) => segment.text).join()
        : rawText;
  } else {
    plainBody = noMessagesYet;
  }
  final plainText = senderLabel.isNotEmpty && plainBody.isNotEmpty
      ? '$senderLabel: $plainBody'
      : plainBody;
  if (!hasRichPreview) {
    return ChatGroupThreadPreviewData(plainText: plainText);
  }

  final segments = <ChatGroupThreadPreviewSegment>[];
  if (senderLabel.isNotEmpty) {
    segments.add(ChatGroupThreadPreviewSegment(text: '$senderLabel: '));
  }
  if (isImage) {
    segments.add(ChatGroupThreadPreviewSegment(text: previewImage));
    if (rawText.isNotEmpty) {
      segments.add(const ChatGroupThreadPreviewSegment(text: ' '));
    }
  }
  segments.addAll(mentionSegments);
  return ChatGroupThreadPreviewData(
    plainText: plainText,
    segments: segments,
  );
}
