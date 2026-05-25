import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../base64_bytes_cache.dart';
import 'chat_models.dart';

typedef GroupMessageDisplayName = String Function(
  String id, {
  String? fallback,
});

enum GroupMessageTextSegmentKind { text, mention, mentionHighlight }

class GroupMessageTextSegment {
  final String text;
  final GroupMessageTextSegmentKind kind;

  const GroupMessageTextSegment({
    required this.text,
    this.kind = GroupMessageTextSegmentKind.text,
  });
}

class GroupMessageTextPresentation {
  final String plainText;
  final List<GroupMessageTextSegment> segments;
  final bool mentionsCurrentUser;
  final bool mentionsAll;

  const GroupMessageTextPresentation({
    required this.plainText,
    this.segments = const <GroupMessageTextSegment>[],
    this.mentionsCurrentUser = false,
    this.mentionsAll = false,
  });

  bool get hasStyledSegments => segments
      .any((segment) => segment.kind != GroupMessageTextSegmentKind.text);
}

class GroupMessagePresentation {
  final String timestampLabel;
  final String kind;
  final String mime;
  final bool isMe;
  final bool hasAttachment;
  final bool isSystem;
  final bool isImage;
  final bool isVoice;
  final bool isLocation;
  final bool isContact;
  final GroupMessageTextPresentation body;
  final GroupMessageTextPresentation rawText;
  final GroupMessageTextPresentation mentionPreview;
  final Uint8List? attachmentBytes;
  final int voiceSecs;
  final double? lat;
  final double? lon;
  final String contactId;
  final String contactDisplayName;
  final String contactInitial;
  final String senderDisplayName;

  const GroupMessagePresentation({
    required this.timestampLabel,
    required this.kind,
    required this.mime,
    required this.isMe,
    required this.hasAttachment,
    required this.isSystem,
    required this.isImage,
    required this.isVoice,
    required this.isLocation,
    required this.isContact,
    required this.body,
    required this.rawText,
    required this.mentionPreview,
    required this.attachmentBytes,
    required this.voiceSecs,
    required this.lat,
    required this.lon,
    required this.contactId,
    required this.contactDisplayName,
    required this.contactInitial,
    required this.senderDisplayName,
  });
}

final RegExp _groupMessageMentionReg = RegExp(r'@([A-Za-z0-9_-]{2,})');
final RegExp _groupMessageMentionWsReg = RegExp(r'\s');
const String _groupMessageArabicAllToken = '@الكل';

GroupMessageTextPresentation buildGroupMessageTextPresentation({
  required String text,
  required GroupMessageDisplayName displayName,
  required String currentUserId,
  required bool isArabic,
}) {
  if (text.isEmpty || !text.contains('@')) {
    return GroupMessageTextPresentation(plainText: text);
  }

  final matches = <({int start, int end, String rawId})>[];
  for (final match in _groupMessageMentionReg.allMatches(text)) {
    if (match.start > 0 &&
        !_groupMessageMentionWsReg.hasMatch(text[match.start - 1])) {
      continue;
    }
    final rawId = (match.group(1) ?? '').trim();
    if (rawId.isEmpty) continue;
    matches.add((start: match.start, end: match.end, rawId: rawId));
  }

  var idx = text.indexOf(_groupMessageArabicAllToken);
  while (idx != -1) {
    if (idx == 0 || _groupMessageMentionWsReg.hasMatch(text[idx - 1])) {
      matches.add((
        start: idx,
        end: idx + _groupMessageArabicAllToken.length,
        rawId: 'all',
      ));
    }
    idx = text.indexOf(
      _groupMessageArabicAllToken,
      idx + _groupMessageArabicAllToken.length,
    );
  }

  matches.sort((a, b) => a.start.compareTo(b.start));
  if (matches.isEmpty) {
    return GroupMessageTextPresentation(plainText: text);
  }

  final meIdLower = currentUserId.trim().toLowerCase();
  final plainTextBuffer = StringBuffer();
  final segments = <GroupMessageTextSegment>[];
  var mentionsCurrentUser = false;
  var mentionsAll = false;
  var last = 0;
  for (final match in matches) {
    if (match.start > last) {
      final chunk = text.substring(last, match.start);
      plainTextBuffer.write(chunk);
      segments.add(GroupMessageTextSegment(text: chunk));
    }
    final raw = match.rawId.trim();
    final rawLower = raw.toLowerCase();
    final mentionText = rawLower == 'all'
        ? (isArabic ? '@الكل' : '@all')
        : '@${displayName(raw, fallback: raw)}';
    if (rawLower == 'all') {
      mentionsAll = true;
    }
    if (rawLower == 'all' || (meIdLower.isNotEmpty && rawLower == meIdLower)) {
      mentionsCurrentUser = true;
    }
    plainTextBuffer.write(mentionText);
    segments.add(
      GroupMessageTextSegment(
        text: mentionText,
        kind:
            rawLower == 'all' || (meIdLower.isNotEmpty && rawLower == meIdLower)
                ? GroupMessageTextSegmentKind.mentionHighlight
                : GroupMessageTextSegmentKind.mention,
      ),
    );
    last = match.end;
  }
  if (last < text.length) {
    final chunk = text.substring(last);
    plainTextBuffer.write(chunk);
    segments.add(GroupMessageTextSegment(text: chunk));
  }

  return GroupMessageTextPresentation(
    plainText: plainTextBuffer.toString(),
    segments: segments,
    mentionsCurrentUser: mentionsCurrentUser,
    mentionsAll: mentionsAll,
  );
}

GroupMessagePresentation buildGroupMessagePresentation({
  required ChatGroupMessage message,
  required bool isArabic,
  required String currentUserId,
  required GroupMessageDisplayName displayName,
  required String previewVoice,
  required String previewImage,
  required String previewUnknown,
  required String encryptedMessageLabel,
  Base64BytesCache? attachmentBytesCache,
}) {
  final kind = (message.kind ?? '').toLowerCase();
  final hasAttachment = (message.attachmentB64 ?? '').trim().isNotEmpty;
  final mime = (message.attachmentMime ?? '').toLowerCase();
  final isImage =
      kind == 'image' || (hasAttachment && mime.startsWith('image/'));
  final isVoice = kind == 'voice';
  final isLocation =
      kind == 'location' && message.lat != null && message.lon != null;
  final contactId = (message.contactId ?? '').trim();
  final isContact = kind == 'contact' && contactId.isNotEmpty;
  final senderDisplayName = displayName(
    message.senderId,
    fallback: message.senderId,
  );
  final rawText = buildGroupMessageTextPresentation(
    text: message.text,
    displayName: displayName,
    currentUserId: currentUserId,
    isArabic: isArabic,
  );
  final attachmentBytes = hasAttachment
      ? attachmentBytesCache != null
          ? attachmentBytesCache.decode(message.attachmentB64)
          : _decodeAttachmentBytes(message.attachmentB64)
      : null;
  final body = () {
    if (kind == 'system') {
      return GroupMessageTextPresentation(
        plainText: _buildSystemGroupMessageLabel(
          message,
          displayName: displayName,
          isArabic: isArabic,
        ),
      );
    }
    final displayText =
        kind == 'sealed' && message.text.isEmpty && !hasAttachment
            ? encryptedMessageLabel
            : message.text;
    return buildGroupMessageTextPresentation(
      text: displayText,
      displayName: displayName,
      currentUserId: currentUserId,
      isArabic: isArabic,
    );
  }();
  final mentionPreview = () {
    if (kind == 'voice') {
      return GroupMessageTextPresentation(plainText: previewVoice);
    }
    if (isImage) {
      if (rawText.plainText.isEmpty) {
        return GroupMessageTextPresentation(plainText: previewImage);
      }
      return _prependGroupMessageTextPresentation(
        prefix: '$previewImage ',
        presentation: rawText,
      );
    }
    if (kind == 'sealed' && message.text.isEmpty && !hasAttachment) {
      return GroupMessageTextPresentation(plainText: encryptedMessageLabel);
    }
    if (rawText.plainText.isNotEmpty) {
      return rawText;
    }
    return GroupMessageTextPresentation(plainText: previewUnknown);
  }();
  final contactDisplayName = () {
    if (!isContact) return '';
    final text = message.text.trim();
    if (text.isNotEmpty) return text;
    final contactName = (message.contactName ?? '').trim();
    if (contactName.isNotEmpty) return contactName;
    return contactId;
  }();
  final contactInitial = contactDisplayName.trim().isNotEmpty
      ? contactDisplayName.trim().substring(0, 1).toUpperCase()
      : '?';

  return GroupMessagePresentation(
    timestampLabel: _formatGroupMessageTimestamp(message.createdAt),
    kind: kind,
    mime: mime,
    isMe: currentUserId.trim().isNotEmpty &&
        message.senderId.trim() == currentUserId.trim(),
    hasAttachment: hasAttachment,
    isSystem: kind == 'system',
    isImage: isImage,
    isVoice: isVoice,
    isLocation: isLocation,
    isContact: isContact,
    body: body,
    rawText: rawText,
    mentionPreview: mentionPreview,
    attachmentBytes: attachmentBytes,
    voiceSecs: message.voiceSecs ?? 0,
    lat: message.lat,
    lon: message.lon,
    contactId: contactId,
    contactDisplayName: contactDisplayName,
    contactInitial: contactInitial,
    senderDisplayName: senderDisplayName,
  );
}

class GroupMessagePresentationCache {
  GroupMessagePresentationCache({
    this.maxEntries = 256,
    Base64BytesCache? attachmentBytesCache,
  }) : _attachmentBytesCache =
            attachmentBytesCache ?? Base64BytesCache(maxEntries: 256);

  final int maxEntries;
  final Base64BytesCache _attachmentBytesCache;
  final Map<String, _CachedGroupMessagePresentation> _entries =
      <String, _CachedGroupMessagePresentation>{};

  GroupMessagePresentation build(
    ChatGroupMessage message, {
    required bool isArabic,
    required String currentUserId,
    required int displayNamesRevision,
    required GroupMessageDisplayName displayName,
    required String previewVoice,
    required String previewImage,
    required String previewUnknown,
    required String encryptedMessageLabel,
  }) {
    final key = _cacheKeyForMessage(message);
    final cached = _entries.remove(key);
    if (cached != null &&
        cached.matches(
          message,
          isArabic: isArabic,
          currentUserId: currentUserId,
          displayNamesRevision: displayNamesRevision,
          previewVoice: previewVoice,
          previewImage: previewImage,
          previewUnknown: previewUnknown,
          encryptedMessageLabel: encryptedMessageLabel,
        )) {
      _entries[key] = cached;
      return cached.presentation;
    }

    final presentation = buildGroupMessagePresentation(
      message: message,
      isArabic: isArabic,
      currentUserId: currentUserId,
      displayName: displayName,
      previewVoice: previewVoice,
      previewImage: previewImage,
      previewUnknown: previewUnknown,
      encryptedMessageLabel: encryptedMessageLabel,
      attachmentBytesCache: _attachmentBytesCache,
    );
    if (_entries.length >= maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = _CachedGroupMessagePresentation.from(
      message: message,
      isArabic: isArabic,
      currentUserId: currentUserId,
      displayNamesRevision: displayNamesRevision,
      previewVoice: previewVoice,
      previewImage: previewImage,
      previewUnknown: previewUnknown,
      encryptedMessageLabel: encryptedMessageLabel,
      presentation: presentation,
    );
    return presentation;
  }

  void clear() => _entries.clear();

  @visibleForTesting
  int get size => _entries.length;

  static String _cacheKeyForMessage(ChatGroupMessage message) {
    final id = message.id.trim();
    if (id.isNotEmpty) {
      return id;
    }
    final createdAtMicros =
        message.createdAt?.toUtc().microsecondsSinceEpoch ?? 0;
    return [
      message.groupId,
      message.senderId,
      '$createdAtMicros',
      message.text,
    ].join('|');
  }
}

class _CachedGroupMessagePresentation {
  final String senderId;
  final String text;
  final String kind;
  final String attachmentB64;
  final String attachmentMime;
  final int voiceSecs;
  final double? lat;
  final double? lon;
  final String contactId;
  final String contactName;
  final int createdAtMicros;
  final bool isArabic;
  final String currentUserId;
  final int displayNamesRevision;
  final String previewVoice;
  final String previewImage;
  final String previewUnknown;
  final String encryptedMessageLabel;
  final GroupMessagePresentation presentation;

  const _CachedGroupMessagePresentation({
    required this.senderId,
    required this.text,
    required this.kind,
    required this.attachmentB64,
    required this.attachmentMime,
    required this.voiceSecs,
    required this.lat,
    required this.lon,
    required this.contactId,
    required this.contactName,
    required this.createdAtMicros,
    required this.isArabic,
    required this.currentUserId,
    required this.displayNamesRevision,
    required this.previewVoice,
    required this.previewImage,
    required this.previewUnknown,
    required this.encryptedMessageLabel,
    required this.presentation,
  });

  factory _CachedGroupMessagePresentation.from({
    required ChatGroupMessage message,
    required bool isArabic,
    required String currentUserId,
    required int displayNamesRevision,
    required String previewVoice,
    required String previewImage,
    required String previewUnknown,
    required String encryptedMessageLabel,
    required GroupMessagePresentation presentation,
  }) {
    return _CachedGroupMessagePresentation(
      senderId: message.senderId,
      text: message.text,
      kind: (message.kind ?? '').toLowerCase(),
      attachmentB64: (message.attachmentB64 ?? '').trim(),
      attachmentMime: (message.attachmentMime ?? '').toLowerCase(),
      voiceSecs: message.voiceSecs ?? 0,
      lat: message.lat,
      lon: message.lon,
      contactId: (message.contactId ?? '').trim(),
      contactName: (message.contactName ?? '').trim(),
      createdAtMicros: message.createdAt?.toUtc().microsecondsSinceEpoch ?? 0,
      isArabic: isArabic,
      currentUserId: currentUserId,
      displayNamesRevision: displayNamesRevision,
      previewVoice: previewVoice,
      previewImage: previewImage,
      previewUnknown: previewUnknown,
      encryptedMessageLabel: encryptedMessageLabel,
      presentation: presentation,
    );
  }

  bool matches(
    ChatGroupMessage message, {
    required bool isArabic,
    required String currentUserId,
    required int displayNamesRevision,
    required String previewVoice,
    required String previewImage,
    required String previewUnknown,
    required String encryptedMessageLabel,
  }) {
    return senderId == message.senderId &&
        text == message.text &&
        kind == (message.kind ?? '').toLowerCase() &&
        attachmentB64 == (message.attachmentB64 ?? '').trim() &&
        attachmentMime == (message.attachmentMime ?? '').toLowerCase() &&
        voiceSecs == (message.voiceSecs ?? 0) &&
        lat == message.lat &&
        lon == message.lon &&
        contactId == (message.contactId ?? '').trim() &&
        contactName == (message.contactName ?? '').trim() &&
        createdAtMicros ==
            (message.createdAt?.toUtc().microsecondsSinceEpoch ?? 0) &&
        this.isArabic == isArabic &&
        this.currentUserId == currentUserId &&
        this.displayNamesRevision == displayNamesRevision &&
        this.previewVoice == previewVoice &&
        this.previewImage == previewImage &&
        this.previewUnknown == previewUnknown &&
        this.encryptedMessageLabel == encryptedMessageLabel;
  }
}

GroupMessageTextPresentation _prependGroupMessageTextPresentation({
  required String prefix,
  required GroupMessageTextPresentation presentation,
}) {
  if (prefix.isEmpty) return presentation;
  if (presentation.segments.isEmpty) {
    return GroupMessageTextPresentation(
      plainText: '$prefix${presentation.plainText}',
      mentionsCurrentUser: presentation.mentionsCurrentUser,
      mentionsAll: presentation.mentionsAll,
    );
  }
  return GroupMessageTextPresentation(
    plainText: '$prefix${presentation.plainText}',
    segments: <GroupMessageTextSegment>[
      GroupMessageTextSegment(text: prefix),
      ...presentation.segments,
    ],
    mentionsCurrentUser: presentation.mentionsCurrentUser,
    mentionsAll: presentation.mentionsAll,
  );
}

Uint8List? _decodeAttachmentBytes(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return null;
  try {
    return base64Decode(value);
  } catch (_) {
    return null;
  }
}

String _formatGroupMessageTimestamp(DateTime? timestamp) {
  if (timestamp == null) return '';
  final dt = timestamp.toLocal();
  return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

String _buildSystemGroupMessageLabel(
  ChatGroupMessage message, {
  required GroupMessageDisplayName displayName,
  required bool isArabic,
}) {
  final raw = message.text.trim();
  if (raw.isEmpty) {
    return isArabic ? 'حدث في المجموعة' : 'Group event';
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      final event = (decoded['event'] ?? '').toString();
      final actor = (decoded['actor_id'] ?? '').toString();
      if (event == 'invite') {
        final idsRaw = decoded['member_ids'];
        final ids = <String>[];
        if (idsRaw is List) {
          for (final value in idsRaw) {
            final id = value.toString().trim();
            if (id.isNotEmpty) ids.add(id);
          }
        }
        final who = displayName(actor);
        final added = ids.map((id) => displayName(id, fallback: id)).join(', ');
        if (isArabic) {
          return ids.isEmpty
              ? 'قام $who بإضافة أعضاء'
              : 'قام $who بإضافة $added';
        }
        return ids.isEmpty ? '$who invited members' : '$who invited $added';
      }
      if (event == 'create') {
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
        final invited =
            ids.map((id) => displayName(id, fallback: id)).join(', ');
        if (isArabic) {
          final base = name.isNotEmpty
              ? 'أنشأ $who المجموعة "$name"'
              : 'أنشأ $who المجموعة';
          return ids.isEmpty ? base : '$base وأضاف $invited';
        }
        final base =
            name.isNotEmpty ? '$who created "$name"' : '$who created the group';
        return ids.isEmpty ? base : '$base and invited $invited';
      }
      if (event == 'leave') {
        final who = displayName(actor);
        return isArabic ? 'غادر $who المجموعة' : '$who left the group';
      }
      if (event == 'role') {
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
      if (event == 'rename') {
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
      if (event == 'avatar') {
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
      if (event == 'key_rotated') {
        final version = (decoded['version'] ?? '').toString();
        final actorLabel = displayName(
          actor,
          fallback: isArabic ? 'مشرف' : 'An admin',
        );
        return isArabic
            ? 'قام $actorLabel بتدوير مفتاح التشفير${version.isNotEmpty ? ' (v$version)' : ''}'
            : '$actorLabel rotated encryption key${version.isNotEmpty ? ' (v$version)' : ''}';
      }
    }
  } catch (_) {}
  return raw;
}
