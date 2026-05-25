import 'dart:convert';

import 'supported_currencies.dart';

enum ShamellPaymentQrPayloadType { pay, topup }

class ShamellPaymentQrPayload {
  final ShamellPaymentQrPayloadType type;
  final String? walletId;
  final String? alias;
  final int? amountCents;
  final String? currency;
  final String? note;
  final String? label;
  final String? mode;
  final String? expiresAtIso;
  final bool isVersioned;

  const ShamellPaymentQrPayload({
    required this.type,
    this.walletId,
    this.alias,
    this.amountCents,
    this.currency,
    this.note,
    this.label,
    this.mode,
    this.expiresAtIso,
    this.isVersioned = false,
  });

  String get amountMajorText {
    final cents = amountCents;
    if (cents == null || cents <= 0) return '';
    final sign = cents < 0 ? '-' : '';
    final abs = cents.abs();
    final whole = abs ~/ 100;
    final frac = abs % 100;
    return '$sign$whole.${frac.toString().padLeft(2, '0')}';
  }

  DateTime? get expiresAt {
    final raw = (expiresAtIso ?? '').trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  bool get isExpired {
    final deadline = expiresAt;
    if (deadline == null) return false;
    return DateTime.now().toUtc().isAfter(deadline);
  }
}

String buildShamellPaymentQrPayload({
  required ShamellPaymentQrPayloadType type,
  required String walletId,
  required String currency,
  int? amountCents,
  String? note,
  String? label,
  String? mode,
  DateTime? expiresAt,
}) {
  final normalizedCurrency = shamellNormalizeWalletCurrency(currency);
  final query = <String, String>{
    'v': '2',
    'wallet_id': walletId.trim(),
    'currency': normalizedCurrency,
  };
  if (amountCents != null && amountCents > 0) {
    query['amount_cents'] = amountCents.toString();
  }
  final cleanNote = (note ?? '').trim();
  if (cleanNote.isNotEmpty) query['note'] = cleanNote;
  final cleanLabel = (label ?? '').trim();
  if (cleanLabel.isNotEmpty) query['label'] = cleanLabel;
  final cleanMode = (mode ?? '').trim().toLowerCase();
  if (cleanMode.isNotEmpty) query['mode'] = cleanMode;
  if (expiresAt != null)
    query['expires_at'] = expiresAt.toUtc().toIso8601String();
  return Uri(
    scheme: 'shamell',
    host: type == ShamellPaymentQrPayloadType.topup ? 'topup' : 'pay',
    queryParameters: query,
  ).toString();
}

ShamellPaymentQrPayload? parseShamellPaymentQrPayload(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final upper = text.toUpperCase();
  if (upper.startsWith('PAY|') ||
      upper.startsWith('CASH|') ||
      upper.startsWith('TOPUP|')) {
    return _parsePipePayload(text);
  }
  if (text.startsWith('{')) return _parseJsonPayload(text);
  final uri = Uri.tryParse(text);
  if (uri != null && uri.scheme.isNotEmpty) {
    final parsed = _parseUriPayload(uri);
    if (parsed != null) return parsed;
    return null;
  }
  if (text.startsWith('@')) {
    return ShamellPaymentQrPayload(
      type: ShamellPaymentQrPayloadType.pay,
      alias: text,
    );
  }
  return ShamellPaymentQrPayload(
    type: ShamellPaymentQrPayloadType.pay,
    walletId: text,
  );
}

ShamellPaymentQrPayload? _parsePipePayload(String text) {
  final parts = text.split('|');
  if (parts.isEmpty) return null;
  final kind = parts.first.trim().toUpperCase();
  final map = <String, String>{};
  for (final part in parts.skip(1)) {
    final idx = part.indexOf('=');
    if (idx <= 0 || idx >= part.length - 1) continue;
    final key = part.substring(0, idx).trim().toLowerCase();
    final value = part.substring(idx + 1).trim();
    try {
      map[key] = Uri.decodeComponent(value);
    } catch (_) {
      continue;
    }
  }
  final type = kind == 'TOPUP'
      ? ShamellPaymentQrPayloadType.topup
      : ShamellPaymentQrPayloadType.pay;
  return _payloadFromMap(
    map,
    type: type,
    isVersioned: (map['v'] ?? '').trim() == '2',
  );
}

ShamellPaymentQrPayload? _parseJsonPayload(String text) {
  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map) return null;
    final map = <String, String>{};
    for (final entry in decoded.entries) {
      map[entry.key.toString().trim().toLowerCase()] =
          (entry.value ?? '').toString();
    }
    final typeRaw = (map['type'] ?? map['kind'] ?? '').trim().toLowerCase();
    return _payloadFromMap(
      map,
      type: typeRaw == 'topup'
          ? ShamellPaymentQrPayloadType.topup
          : ShamellPaymentQrPayloadType.pay,
      isVersioned: (map['v'] ?? '').trim() == '2',
    );
  } catch (_) {
    return null;
  }
}

ShamellPaymentQrPayload? _parseUriPayload(Uri uri) {
  final scheme = uri.scheme.trim().toLowerCase();
  final host = uri.host.trim().toLowerCase();
  if (scheme != 'shamell') {
    if (uri.queryParameters.keys.any((key) => const <String>{
          'wallet_id',
          'to_wallet_id',
          'wallet',
          'to_alias',
          'alias',
          'amount',
          'amount_cents',
        }.contains(key.toLowerCase()))) {
      return _payloadFromMap(
        uri.queryParameters,
        type: ShamellPaymentQrPayloadType.pay,
        isVersioned: false,
      );
    }
    return null;
  }
  final pathSegments = uri.pathSegments
      .map((segment) => segment.trim().toLowerCase())
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  final firstPath = pathSegments.isEmpty ? '' : pathSegments.first;
  final typeRaw = (uri.queryParameters['type'] ?? '').trim().toLowerCase();
  final isTopup = host == 'topup' || firstPath == 'topup' || typeRaw == 'topup';
  final isPay = host == 'pay' ||
      host == 'payment' ||
      firstPath == 'pay' ||
      firstPath == 'payment' ||
      typeRaw == 'pay' ||
      typeRaw == 'transfer';
  if (!isTopup && !isPay) return null;
  final payload = _payloadFromMap(
    uri.queryParameters,
    type: isTopup
        ? ShamellPaymentQrPayloadType.topup
        : ShamellPaymentQrPayloadType.pay,
    isVersioned: (uri.queryParameters['v'] ?? '').trim() == '2',
  );
  if (payload == null) return null;
  if ((payload.walletId ?? '').isNotEmpty || (payload.alias ?? '').isNotEmpty) {
    return payload;
  }
  final candidateSegments = uri.pathSegments
      .where((segment) => segment.trim().isNotEmpty)
      .toList(growable: false);
  if (candidateSegments.length <= 1) return payload;
  return ShamellPaymentQrPayload(
    type: payload.type,
    walletId: candidateSegments.last.trim(),
    alias: payload.alias,
    amountCents: payload.amountCents,
    currency: payload.currency,
    note: payload.note,
    label: payload.label,
    mode: payload.mode,
    expiresAtIso: payload.expiresAtIso,
    isVersioned: payload.isVersioned,
  );
}

ShamellPaymentQrPayload? _payloadFromMap(
  Map<String, String> map, {
  required ShamellPaymentQrPayloadType type,
  required bool isVersioned,
}) {
  final wallet = _firstNonEmpty(map, const <String>[
    'wallet_id',
    'to_wallet_id',
    'wallet',
    'to',
  ]);
  final alias = _firstNonEmpty(map, const <String>['to_alias', 'alias']);
  final amountCents = _parseAmountCents(map);
  final currencyRaw = _firstNonEmpty(map, const <String>['currency', 'cur']);
  final currency =
      currencyRaw == null ? null : _normalizeQrCurrency(currencyRaw);
  return ShamellPaymentQrPayload(
    type: type,
    walletId: wallet,
    alias: alias,
    amountCents: amountCents,
    currency: currency,
    note: _firstNonEmpty(map, const <String>['note', 'ref', 'reference']),
    label: _firstNonEmpty(
      map,
      const <String>['label', 'merchant', 'merchant_name', 'name'],
    ),
    mode: _firstNonEmpty(map, const <String>['mode', 'qr_mode']),
    expiresAtIso: _firstNonEmpty(
      map,
      const <String>['expires_at', 'expires', 'expiry'],
    ),
    isVersioned: isVersioned,
  );
}

String _normalizeQrCurrency(String raw) {
  final normalized = raw.trim().toUpperCase();
  if (normalized.isEmpty) return shamellDefaultWalletCurrency;
  if (shamellIsSupportedWalletCurrency(normalized)) return normalized;
  return normalized;
}

String? _firstNonEmpty(Map<String, String> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key]?.trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

int? _parseAmountCents(Map<String, String> map) {
  final direct = _firstNonEmpty(map, const <String>['amount_cents', 'cents']);
  if (direct != null) {
    final cents = int.tryParse(direct);
    if (cents != null && cents > 0) return cents;
  }
  final major = _firstNonEmpty(map, const <String>['amount', 'amt']);
  if (major == null) return null;
  return _parseMajorAmountToCents(major);
}

int? _parseMajorAmountToCents(String raw) {
  final normalized = raw.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(normalized)) return null;
  final parts = normalized.split('.');
  final whole = int.tryParse(parts.first);
  if (whole == null) return null;
  final frac = parts.length > 1 ? parts[1].padRight(2, '0') : '00';
  final fracCents = int.tryParse(frac.substring(0, 2));
  if (fracCents == null) return null;
  final cents = whole * 100 + fracCents;
  return cents > 0 ? cents : null;
}
