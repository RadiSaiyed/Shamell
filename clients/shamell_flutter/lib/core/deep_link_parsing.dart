class OfficialDeepLinkTarget {
  final String accountId;
  final String? itemId;

  const OfficialDeepLinkTarget({
    required this.accountId,
    this.itemId,
  });
}

class MiniProgramDeepLinkTarget {
  final String id;
  final String? resourceId;

  const MiniProgramDeepLinkTarget({
    required this.id,
    this.resourceId,
  });
}

const int _officialDeepLinkIdentifierMaxChars = 64;
final RegExp _officialDeepLinkIdentifierRe =
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');
final RegExp _miniProgramDeepLinkIdentifierRe =
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$');
final RegExp _officialLinkInTextRe = RegExp(
  r'shamell://official/[^\s]+',
  caseSensitive: false,
);
final RegExp _miniProgramLinkInTextRe = RegExp(
  r'(?:shamell://(?:miniapp|mini_program|moduleapp|moduleapps|green_paket|green_packet|redpacket|red_packet|hongbao)/[^\s]+|(?:MINIPROGRAM|MINI_PROGRAM|MINIAPP|APP|MODULEAPP)\|[^\r\n]+)',
  caseSensitive: false,
);

OfficialDeepLinkTarget? parseOfficialDeepLink(Uri uri) {
  if (uri.scheme.toLowerCase() != 'shamell') return null;
  if (uri.host.trim().toLowerCase() != 'official') return null;
  final segs = uri.pathSegments
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
  if (segs.isEmpty || segs.length > 2) return null;
  final accountId = segs.first;
  if (!_isValidOfficialDeepLinkIdentifier(accountId)) return null;
  final itemId = segs.length > 1 ? _nonEmptyOrNull(segs[1]) : null;
  if (itemId != null && !_isValidOfficialDeepLinkIdentifier(itemId)) {
    return null;
  }
  return OfficialDeepLinkTarget(accountId: accountId, itemId: itemId);
}

OfficialDeepLinkTarget? parseOfficialDeepLinkFromText(String text) {
  final match = _officialLinkInTextRe.firstMatch(text);
  if (match == null) return null;
  final raw = match.group(0);
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    return parseOfficialDeepLink(Uri.parse(raw.trim()));
  } catch (_) {
    return null;
  }
}

OfficialDeepLinkTarget? officialTargetFromExplicitOrText({
  String? explicitAccountId,
  String? explicitItemId,
  required String text,
}) {
  final textTarget = parseOfficialDeepLinkFromText(text);
  final accountId = (explicitAccountId ?? '').trim();
  if (accountId.isEmpty) return textTarget;
  if (!_isValidOfficialDeepLinkIdentifier(accountId)) return textTarget;

  final rawItemId = (explicitItemId ?? '').trim();
  String? itemId;
  if (rawItemId.isNotEmpty && _isValidOfficialDeepLinkIdentifier(rawItemId)) {
    itemId = rawItemId;
  } else if (textTarget != null &&
      textTarget.accountId.toLowerCase() == accountId.toLowerCase()) {
    itemId = textTarget.itemId;
  }

  return OfficialDeepLinkTarget(accountId: accountId, itemId: itemId);
}

String stripOfficialDeepLinksFromText(String text) {
  return text
      .replaceAll(_officialLinkInTextRe, '')
      .replaceAll(RegExp(r'\n{2,}'), '\n')
      .trim();
}

void dispatchOfficialDeepLink(
  Uri uri, {
  required bool capabilityEnabled,
  required void Function() onUnavailable,
  required void Function(String accountId) onOpenAccount,
  required void Function(String accountId, String itemId) onOpenItem,
}) {
  final target = parseOfficialDeepLink(uri);
  if (target == null) return;
  if (!capabilityEnabled) {
    onUnavailable();
    return;
  }
  final itemId = target.itemId;
  if (itemId != null) {
    onOpenItem(target.accountId, itemId);
    return;
  }
  onOpenAccount(target.accountId);
}

MiniProgramDeepLinkTarget? parseMiniProgramDeepLink(Uri uri) {
  if (uri.scheme.toLowerCase() != 'shamell') return null;
  final host = uri.host.trim().toLowerCase();
  final segs = uri.pathSegments
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);

  if (_isGreenPaketHost(host)) {
    final resourceId =
        segs.isNotEmpty ? _cleanMiniProgramIdentifier(segs[0]) : null;
    return MiniProgramDeepLinkTarget(
      id: 'green_paket',
      resourceId: resourceId,
    );
  }

  if (host != 'miniapp' &&
      host != 'mini_program' &&
      host != 'moduleapp' &&
      host != 'moduleapps') {
    return null;
  }

  final rawId = uri.queryParameters['id'] ??
      uri.queryParameters['app_id'] ??
      uri.queryParameters['moduleapp'] ??
      uri.queryParameters['mod'] ??
      (segs.isNotEmpty ? segs[0] : null);
  final id = _normalizeMiniProgramId(rawId);
  if (id == null) return null;
  final rawResource = uri.queryParameters['resource_id'] ??
      uri.queryParameters['packet_id'] ??
      uri.queryParameters['green_paket_id'] ??
      (segs.length > 1 ? segs[1] : null);
  return MiniProgramDeepLinkTarget(
    id: id,
    resourceId: _cleanMiniProgramIdentifier(rawResource),
  );
}

MiniProgramDeepLinkTarget? parseMiniProgramDeepLinkFromText(String text) {
  final match = _miniProgramLinkInTextRe.firstMatch(text);
  if (match == null) return null;
  final raw = match.group(0);
  if (raw == null || raw.trim().isEmpty) return null;
  final pipeTarget = parseMiniProgramPipePayload(raw);
  if (pipeTarget != null) return pipeTarget;
  try {
    return parseMiniProgramDeepLink(Uri.parse(raw.trim()));
  } catch (_) {
    return null;
  }
}

MiniProgramDeepLinkTarget? miniProgramTargetFromExplicitOrText({
  String? explicitId,
  required String text,
}) {
  final normalizedExplicitId = _normalizeMiniProgramId(explicitId);
  final textTarget = parseMiniProgramDeepLinkFromText(text);
  if (normalizedExplicitId == null) return textTarget;
  if (textTarget != null && textTarget.id == normalizedExplicitId) {
    return MiniProgramDeepLinkTarget(
      id: normalizedExplicitId,
      resourceId: textTarget.resourceId,
    );
  }
  return MiniProgramDeepLinkTarget(id: normalizedExplicitId);
}

String stripMiniProgramDeepLinksFromText(String text) {
  return text
      .replaceAll(_miniProgramLinkInTextRe, '')
      .replaceAll(RegExp(r'\n{2,}'), '\n')
      .trim();
}

MiniProgramDeepLinkTarget? parseMiniProgramPipePayload(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final sep = text.indexOf('|');
  if (sep <= 0) return null;
  final kind = text.substring(0, sep).trim().toUpperCase();
  if (kind != 'MINIPROGRAM' &&
      kind != 'MINI_PROGRAM' &&
      kind != 'MINIAPP' &&
      kind != 'APP' &&
      kind != 'MODULEAPP') {
    return null;
  }
  final body = text.substring(sep + 1);
  final pairs = _parsePipePairs(body);
  final rawId = pairs['id'] ??
      pairs['app_id'] ??
      pairs['app'] ??
      pairs['moduleapp'] ??
      pairs['module_app'] ??
      pairs['mod'];
  final id = _normalizeMiniProgramId(rawId);
  if (id == null) return null;
  final resourceId = _cleanMiniProgramIdentifier(
    pairs['resource_id'] ??
        pairs['packet_id'] ??
        pairs['green_paket_id'] ??
        pairs['item_id'],
  );
  return MiniProgramDeepLinkTarget(id: id, resourceId: resourceId);
}

String shamellMiniProgramDeepLink(String id) {
  final normalized = _normalizeMiniProgramId(id) ?? 'mini_programs';
  return 'shamell://mini_program/$normalized';
}

String shamellGreenPaketDeepLink(String packetId) {
  final id = _cleanMiniProgramIdentifier(packetId) ?? '';
  return id.isEmpty
      ? 'shamell://mini_program/green_paket'
      : 'shamell://green_paket/$id';
}

String? _nonEmptyOrNull(String? value) {
  final v = (value ?? '').trim();
  return v.isEmpty ? null : v;
}

bool _isValidOfficialDeepLinkIdentifier(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized.length > _officialDeepLinkIdentifierMaxChars) {
    return false;
  }
  return _officialDeepLinkIdentifierRe.hasMatch(normalized);
}

bool _isGreenPaketHost(String host) {
  return host == 'green_paket' ||
      host == 'green_packet' ||
      host == 'redpacket' ||
      host == 'red_packet' ||
      host == 'hongbao';
}

String? _cleanMiniProgramIdentifier(String? raw) {
  final normalized = (raw ?? '').trim();
  if (normalized.isEmpty ||
      !_miniProgramDeepLinkIdentifierRe.hasMatch(normalized)) {
    return null;
  }
  return normalized;
}

String? _normalizeMiniProgramId(String? raw) {
  final normalized = _cleanMiniProgramIdentifier(raw)?.toLowerCase();
  if (normalized == null) return null;
  if (normalized == 'wallet' || normalized == 'pay') return 'payments';
  if (normalized == 'saved' ||
      normalized == 'saved_items' ||
      normalized == 'bookmarks') {
    return 'favorites';
  }
  if (_isGreenPaketHost(normalized)) return 'green_paket';
  if (normalized == 'official' || normalized == 'officials') {
    return 'official_accounts';
  }
  if (normalized == 'nearby') return 'people_nearby';
  if (normalized == 'sticker_store') return 'stickers';
  if (normalized == 'coach' ||
      normalized == 'coach_bus' ||
      normalized == 'coachbus') {
    return 'bus';
  }
  return normalized;
}

Map<String, String> _parsePipePairs(String body) {
  final out = <String, String>{};
  for (final part in body.split('|')) {
    final idx = part.indexOf('=');
    if (idx <= 0) continue;
    final key = part.substring(0, idx).trim().toLowerCase();
    if (key.isEmpty) continue;
    final rawValue = part.substring(idx + 1).trim();
    try {
      out[key] = Uri.decodeComponent(rawValue);
    } catch (_) {
      out[key] = rawValue;
    }
  }
  return out;
}
