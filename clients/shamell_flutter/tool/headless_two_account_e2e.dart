import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:pinenacl/x25519.dart' as x25519;

class E2eError implements Exception {
  final String message;
  E2eError(this.message);
  @override
  String toString() => message;
}

class AccountCtx {
  final String label;
  final String accountDeviceId;
  late String sessionCookie;
  late String shamellId;
  late String walletId;
  late String chatDeviceId;
  late String chatAuthToken;
  late String chatPublicKeyB64;
  AccountCtx({required this.label, required this.accountDeviceId});
}

class CallSignalPair {
  final WebSocket a;
  final WebSocket b;
  CallSignalPair({required this.a, required this.b});
}

String _nowIso() => DateTime.now().toUtc().toIso8601String();

String _randId({int len = 16}) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final r = Random.secure();
  return List.generate(len, (_) => chars[r.nextInt(chars.length)]).join();
}

String _randBase64(int bytes) {
  final r = Random.secure();
  final out = Uint8List(bytes);
  for (var i = 0; i < out.length; i++) {
    out[i] = r.nextInt(256);
  }
  return base64Encode(out);
}

bool _hasLeadingZeroBits(List<int> bytes, int bits) {
  if (bits <= 0) return true;
  final full = bits ~/ 8;
  final rem = bits % 8;
  if (full > bytes.length) return false;
  for (var i = 0; i < full; i++) {
    if (bytes[i] != 0) return false;
  }
  if (rem == 0) return true;
  if (full >= bytes.length) return false;
  return (bytes[full] >> (8 - rem)) == 0;
}

String? _solvePow({
  required String nonce,
  required String deviceId,
  required int difficultyBits,
  int maxMillis = 20000,
  int maxIters = 50000000,
}) {
  final sw = Stopwatch()..start();
  final prefix = '$nonce:$deviceId:';
  for (var i = 0; i < maxIters; i++) {
    if (sw.elapsedMilliseconds > maxMillis) return null;
    final digest = crypto.sha256.convert(utf8.encode('$prefix$i')).bytes;
    if (_hasLeadingZeroBits(digest, difficultyBits)) {
      return i.toString();
    }
  }
  return null;
}

String _base(String raw) {
  final t = raw.trim();
  return t.endsWith('/') ? t.substring(0, t.length - 1) : t;
}

String _cookieFromSetCookie(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    throw E2eError('Missing set-cookie header');
  }
  final chunks = raw.split(',');
  for (final chunk in chunks) {
    final part = chunk.trim();
    final eq = part.indexOf('=');
    final semi = part.indexOf(';');
    if (eq <= 0 || semi <= eq) continue;
    final name = part.substring(0, eq).trim();
    final value = part.substring(eq + 1, semi).trim();
    final lower = part.toLowerCase();
    final maxAgeZero = lower.contains('max-age=0');
    if (value.isEmpty || maxAgeZero) continue;
    return '$name=$value';
  }
  throw E2eError('Could not parse active session cookie');
}

Map<String, String> _jsonHeaders({String? cookie}) {
  return <String, String>{
    'content-type': 'application/json',
    if (cookie != null && cookie.isNotEmpty) 'cookie': cookie,
  };
}

Map<String, String> _chatHeaders({
  required AccountCtx ctx,
  bool json = false,
}) {
  return <String, String>{
    if (json) 'content-type': 'application/json',
    'cookie': ctx.sessionCookie,
    'x-chat-device-id': ctx.chatDeviceId,
    'x-chat-device-token': ctx.chatAuthToken,
  };
}

Map<String, String> _paymentHeaders({
  required AccountCtx ctx,
  bool json = false,
  String? idempotencyKey,
  String? merchant,
  String? ref,
}) {
  return <String, String>{
    if (json) 'content-type': 'application/json',
    'cookie': ctx.sessionCookie,
    'x-device-id': ctx.accountDeviceId,
    if (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
      'idempotency-key': idempotencyKey.trim(),
    if (merchant != null && merchant.trim().isNotEmpty)
      'x-merchant': merchant.trim(),
    if (ref != null && ref.trim().isNotEmpty) 'x-ref': ref.trim(),
  };
}

Map<String, dynamic> _decodeMap(String raw, String op) {
  final decoded = jsonDecode(raw);
  if (decoded is Map<String, dynamic>) return decoded;
  if (decoded is Map) {
    final out = <String, dynamic>{};
    decoded.forEach((key, value) => out[key.toString()] = value);
    return out;
  }
  throw E2eError('Invalid $op response: expected object');
}

List<dynamic> _decodeList(String raw, String op) {
  final decoded = jsonDecode(raw);
  if (decoded is List) return decoded;
  throw E2eError('Invalid $op response: expected list');
}

int _parseIntField(dynamic raw, String field, String op) {
  if (raw is num) return raw.toInt();
  final parsed = int.tryParse((raw ?? '').toString().trim());
  if (parsed != null) return parsed;
  throw E2eError('Invalid $op response: missing/invalid $field');
}

Future<http.Response> _req(
  http.Client client, {
  required String method,
  required Uri uri,
  Map<String, String>? headers,
  Object? body,
}) async {
  final req = http.Request(method, uri);
  if (headers != null) req.headers.addAll(headers);
  if (body != null) req.body = body.toString();
  final streamed = await client.send(req).timeout(const Duration(seconds: 30));
  return http.Response.fromStream(streamed);
}

void _expect2xx(http.Response r, String op) {
  if (r.statusCode >= 200 && r.statusCode < 300) return;
  throw E2eError('$op failed: HTTP ${r.statusCode} body=${r.body}');
}

Future<AccountCtx> _createAccount(
  http.Client client, {
  required String baseUrl,
  required String label,
}) async {
  final ctx = AccountCtx(
    label: label,
    accountDeviceId: 'acc${_randId(len: 12)}',
  );
  final base = _base(baseUrl);
  final challengeUri = Uri.parse('$base/auth/account/create/challenge');

  String? challengeToken;
  String? powSolution;
  String? iosDeviceCheckTokenB64;
  String? androidPlayIntegrityToken;

  final challengeResp = await _req(
    client,
    method: 'POST',
    uri: challengeUri,
    headers: _jsonHeaders(),
    body: jsonEncode(<String, Object?>{
      'device_id': ctx.accountDeviceId,
    }),
  );

  if (challengeResp.statusCode == 503) {
    throw E2eError('Account create disabled on server (HTTP 503).');
  }
  if (challengeResp.statusCode != 404) {
    if (challengeResp.statusCode != 200) {
      throw E2eError(
        'Challenge request failed (${ctx.label}): '
        'HTTP ${challengeResp.statusCode} body=${challengeResp.body}',
      );
    }
    final decoded = jsonDecode(challengeResp.body);
    if (decoded is! Map) {
      throw E2eError('Invalid challenge response (${ctx.label})');
    }
    final hwEnabled = decoded['hw_attestation_enabled'] == true;
    final hwRequired = decoded['hw_attestation_required'] == true;
    if (hwEnabled && hwRequired) {
      throw E2eError(
        'Hardware attestation required (${ctx.label}); '
        'headless creation without iOS/Android attestation token is not possible.',
      );
    }
    challengeToken = (decoded['challenge_token'] ?? decoded['token'] ?? '')
        .toString()
        .trim();
    final powEnabled = decoded['enabled'] == true;
    if (powEnabled) {
      final nonce = (decoded['nonce'] ?? '').toString().trim();
      final diffRaw = decoded['difficulty_bits'];
      final diffBits = diffRaw is num
          ? diffRaw.toInt()
          : int.tryParse((diffRaw ?? '').toString()) ?? -1;
      if (nonce.isEmpty || diffBits < 0) {
        throw E2eError('Invalid PoW challenge (${ctx.label})');
      }
      powSolution = _solvePow(
        nonce: nonce,
        deviceId: ctx.accountDeviceId,
        difficultyBits: diffBits,
      );
      if (powSolution == null || powSolution!.isEmpty) {
        throw E2eError('PoW solve failed/timeout (${ctx.label})');
      }
    }
  }

  final createResp = await _req(
    client,
    method: 'POST',
    uri: Uri.parse('$base/auth/account/create'),
    headers: _jsonHeaders(),
    body: jsonEncode(<String, Object?>{
      'device_id': ctx.accountDeviceId,
      if (challengeToken != null && challengeToken.isNotEmpty)
        'challenge_token': challengeToken,
      if (challengeToken != null && challengeToken.isNotEmpty)
        'pow_token': challengeToken,
      if (powSolution != null && powSolution.isNotEmpty)
        'pow_solution': powSolution,
      if (iosDeviceCheckTokenB64 != null)
        'ios_devicecheck_token_b64': iosDeviceCheckTokenB64,
      if (androidPlayIntegrityToken != null)
        'android_play_integrity_token': androidPlayIntegrityToken,
    }),
  );
  _expect2xx(createResp, 'auth/account/create (${ctx.label})');
  ctx.sessionCookie = _cookieFromSetCookie(createResp.headers['set-cookie']);
  try {
    final decoded = jsonDecode(createResp.body);
    if (decoded is Map) {
      ctx.shamellId = (decoded['shamell_id'] ?? '').toString().trim();
    } else {
      ctx.shamellId = '';
    }
  } catch (_) {
    ctx.shamellId = '';
  }
  if (ctx.shamellId.isEmpty) {
    throw E2eError(
        'Missing shamell_id in account-create response (${ctx.label})');
  }
  return ctx;
}

Future<void> _registerAuthDevice(
  http.Client client, {
  required String baseUrl,
  required AccountCtx ctx,
}) async {
  final resp = await _req(
    client,
    method: 'POST',
    uri: Uri.parse('${_base(baseUrl)}/auth/devices/register'),
    headers: _jsonHeaders(cookie: ctx.sessionCookie),
    body: jsonEncode(<String, Object?>{
      'device_id': ctx.accountDeviceId,
      'device_type': 'headless',
      'platform': 'headless',
      'device_name': 'Headless ${ctx.label}',
    }),
  );
  _expect2xx(resp, 'auth/devices/register (${ctx.label})');
}

Future<void> _registerChatDevice(
  http.Client client, {
  required String baseUrl,
  required AccountCtx ctx,
}) async {
  final sk = x25519.PrivateKey.generate();
  final pkB64 = base64Encode(sk.publicKey.asTypedList);
  final chatDeviceId = 'd${_randId(len: 12)}';

  final resp = await _req(
    client,
    method: 'POST',
    uri: Uri.parse('${_base(baseUrl)}/chat/devices/register'),
    headers: _jsonHeaders(cookie: ctx.sessionCookie),
    body: jsonEncode(<String, Object?>{
      'device_id': chatDeviceId,
      'client_device_id': ctx.accountDeviceId,
      'public_key_b64': pkB64,
      'name': 'Headless ${ctx.label}',
    }),
  );
  _expect2xx(resp, 'chat/devices/register (${ctx.label})');
  final decoded = jsonDecode(resp.body);
  if (decoded is! Map) {
    throw E2eError('Invalid chat register response (${ctx.label})');
  }
  final authToken = (decoded['auth_token'] ?? '').toString().trim();
  if (authToken.isEmpty) {
    throw E2eError('Missing chat auth_token (${ctx.label})');
  }

  ctx.chatDeviceId = (decoded['device_id'] ?? chatDeviceId).toString().trim();
  ctx.chatAuthToken = authToken;
  ctx.chatPublicKeyB64 = pkB64;
}

Future<void> _assertHomeSnapshot(
  http.Client client, {
  required String baseUrl,
  required AccountCtx ctx,
}) async {
  final r = await _req(
    client,
    method: 'GET',
    uri: Uri.parse('${_base(baseUrl)}/me/home_snapshot'),
    headers: <String, String>{'cookie': ctx.sessionCookie},
  );
  if (r.statusCode >= 200 && r.statusCode < 300) return;
  // Some deployments can return a transient dependency error from payments.
  if (r.statusCode == 422 &&
      r.body.toLowerCase().contains('payments upstream error')) {
    stderr.writeln(
      'WARN: me/home_snapshot (${ctx.label}) returned 422 due to payments upstream; continuing.',
    );
    return;
  }
  throw E2eError(
    'me/home_snapshot (${ctx.label}) failed: HTTP ${r.statusCode} body=${r.body}',
  );
}

Future<void> _assertAuthDevicesList(
  http.Client client, {
  required String baseUrl,
  required AccountCtx ctx,
}) async {
  final r = await _req(
    client,
    method: 'GET',
    uri: Uri.parse('${_base(baseUrl)}/auth/devices'),
    headers: <String, String>{'cookie': ctx.sessionCookie},
  );
  _expect2xx(r, 'auth/devices list (${ctx.label})');
}

Future<void> _paymentsEnsureUser(
  http.Client client, {
  required String baseUrl,
  required AccountCtx ctx,
}) async {
  final r = await _req(
    client,
    method: 'POST',
    uri: Uri.parse('${_base(baseUrl)}/payments/users'),
    headers: _paymentHeaders(ctx: ctx, json: true),
    body: jsonEncode(<String, Object?>{}),
  );
  _expect2xx(r, 'payments/users (${ctx.label})');
  final decoded = _decodeMap(r.body, 'payments/users');
  final walletId = (decoded['wallet_id'] ?? '').toString().trim();
  if (walletId.isEmpty) {
    throw E2eError(
        'Missing wallet_id in payments/users response (${ctx.label})');
  }
  ctx.walletId = walletId;
}

Future<int> _paymentsGetWalletBalance(
  http.Client client, {
  required String baseUrl,
  required AccountCtx ctx,
}) async {
  final walletId = ctx.walletId.trim();
  if (walletId.isEmpty) {
    throw E2eError('wallet_id not initialized (${ctx.label})');
  }
  final r = await _req(
    client,
    method: 'GET',
    uri: Uri.parse(
      '${_base(baseUrl)}/payments/wallets/${Uri.encodeComponent(walletId)}',
    ),
    headers: _paymentHeaders(ctx: ctx),
  );
  _expect2xx(r, 'payments/wallets/:wallet_id (${ctx.label})');
  final decoded = _decodeMap(r.body, 'payments/wallet');
  final gotWalletId = (decoded['wallet_id'] ?? '').toString().trim();
  if (gotWalletId != walletId) {
    throw E2eError(
      'payments/wallet mismatch (${ctx.label}): got=$gotWalletId expected=$walletId',
    );
  }
  return _parseIntField(
      decoded['balance_cents'], 'balance_cents', 'payments/wallet');
}

Future<int> _paymentsTopup(
  http.Client client, {
  required String baseUrl,
  required AccountCtx ctx,
  required int amountCents,
}) async {
  final idem =
      'top-${ctx.label}-${DateTime.now().millisecondsSinceEpoch}-${_randId(len: 6)}';
  final r = await _req(
    client,
    method: 'POST',
    uri: Uri.parse(
      '${_base(baseUrl)}/payments/wallets/${Uri.encodeComponent(ctx.walletId)}/topup',
    ),
    headers: _paymentHeaders(
      ctx: ctx,
      json: true,
      idempotencyKey: idem,
    ),
    body: jsonEncode(<String, Object?>{
      'amount_cents': amountCents,
    }),
  );
  _expect2xx(r, 'payments/wallets/:wallet_id/topup (${ctx.label})');
  final decoded = _decodeMap(r.body, 'payments/topup');
  return _parseIntField(
      decoded['balance_cents'], 'balance_cents', 'payments/topup');
}

Future<int> _paymentsTransfer(
  http.Client client, {
  required String baseUrl,
  required AccountCtx sender,
  required AccountCtx recipient,
  required int amountCents,
}) async {
  final idem =
      'tx-${sender.label}-${recipient.label}-${DateTime.now().millisecondsSinceEpoch}-${_randId(len: 6)}';
  final r = await _req(
    client,
    method: 'POST',
    uri: Uri.parse('${_base(baseUrl)}/payments/transfer'),
    headers: _paymentHeaders(
      ctx: sender,
      json: true,
      idempotencyKey: idem,
      merchant: 'headless_e2e',
      ref: 'headless-transfer',
    ),
    body: jsonEncode(<String, Object?>{
      'from_wallet_id': sender.walletId,
      'to_wallet_id': recipient.walletId,
      'amount_cents': amountCents,
    }),
  );
  _expect2xx(r, 'payments/transfer (${sender.label}->${recipient.label})');
  final decoded = _decodeMap(r.body, 'payments/transfer');
  final wid = (decoded['wallet_id'] ?? '').toString().trim();
  if (wid.isEmpty) {
    throw E2eError('Missing wallet_id in payments/transfer response');
  }
  return _parseIntField(
      decoded['balance_cents'], 'balance_cents', 'payments/transfer');
}

Future<String> _paymentsFavoriteCreate(
  http.Client client, {
  required String baseUrl,
  required AccountCtx owner,
  required AccountCtx favorite,
}) async {
  final r = await _req(
    client,
    method: 'POST',
    uri: Uri.parse('${_base(baseUrl)}/payments/favorites'),
    headers: _paymentHeaders(ctx: owner, json: true),
    body: jsonEncode(<String, Object?>{
      'owner_wallet_id': owner.walletId,
      'favorite_wallet_id': favorite.walletId,
      'alias': 'fav_${favorite.label.toLowerCase()}',
    }),
  );
  _expect2xx(r, 'payments/favorites create (${owner.label})');
  final decoded = _decodeMap(r.body, 'payments/favorites create');
  final id = (decoded['id'] ?? '').toString().trim();
  if (id.isEmpty) throw E2eError('Missing favorite id');
  return id;
}

Future<void> _paymentsFavoriteListContains(
  http.Client client, {
  required String baseUrl,
  required AccountCtx owner,
  required String favoriteId,
}) async {
  final r = await _req(
    client,
    method: 'GET',
    uri: Uri.parse(
      '${_base(baseUrl)}/payments/favorites?owner_wallet_id=${Uri.encodeComponent(owner.walletId)}',
    ),
    headers: _paymentHeaders(ctx: owner),
  );
  _expect2xx(r, 'payments/favorites list (${owner.label})');
  final list = _decodeList(r.body, 'payments/favorites list');
  final found = list.any(
    (e) => e is Map && (e['id'] ?? '').toString().trim() == favoriteId,
  );
  if (!found) {
    throw E2eError(
        'Favorite id not found in list (${owner.label}): $favoriteId');
  }
}

Future<void> _paymentsFavoriteDelete(
  http.Client client, {
  required String baseUrl,
  required AccountCtx owner,
  required String favoriteId,
}) async {
  final r = await _req(
    client,
    method: 'DELETE',
    uri: Uri.parse(
      '${_base(baseUrl)}/payments/favorites/${Uri.encodeComponent(favoriteId)}',
    ),
    headers: _paymentHeaders(ctx: owner),
  );
  _expect2xx(r, 'payments/favorites delete (${owner.label})');
}

Future<String> _paymentsRequestCreate(
  http.Client client, {
  required String baseUrl,
  required AccountCtx requester,
  required AccountCtx payer,
  required int amountCents,
  required String message,
}) async {
  final r = await _req(
    client,
    method: 'POST',
    uri: Uri.parse('${_base(baseUrl)}/payments/requests'),
    headers: _paymentHeaders(ctx: requester, json: true),
    body: jsonEncode(<String, Object?>{
      'from_wallet_id': requester.walletId,
      'to_wallet_id': payer.walletId,
      'amount_cents': amountCents,
      'message': message,
    }),
  );
  _expect2xx(r, 'payments/requests create (${requester.label})');
  final decoded = _decodeMap(r.body, 'payments/requests create');
  final rid = (decoded['id'] ?? '').toString().trim();
  if (rid.isEmpty) throw E2eError('Missing request id');
  return rid;
}

Future<void> _paymentsRequestListContains(
  http.Client client, {
  required String baseUrl,
  required AccountCtx actor,
  required String kind,
  required String requestId,
}) async {
  final r = await _req(
    client,
    method: 'GET',
    uri: Uri.parse(
      '${_base(baseUrl)}/payments/requests'
      '?wallet_id=${Uri.encodeComponent(actor.walletId)}'
      '&kind=${Uri.encodeComponent(kind)}'
      '&limit=100',
    ),
    headers: _paymentHeaders(ctx: actor),
  );
  _expect2xx(r, 'payments/requests list (${actor.label}/$kind)');
  final list = _decodeList(r.body, 'payments/requests list');
  final found = list.any(
    (e) => e is Map && (e['id'] ?? '').toString().trim() == requestId,
  );
  if (!found) {
    throw E2eError(
      'Request id not found in payments/requests list (${actor.label}/$kind): $requestId',
    );
  }
}

Future<void> _paymentsRequestAccept(
  http.Client client, {
  required String baseUrl,
  required AccountCtx payer,
  required String requestId,
}) async {
  final idem =
      'req-accept-${payer.label}-${DateTime.now().millisecondsSinceEpoch}-${_randId(len: 6)}';
  final r = await _req(
    client,
    method: 'POST',
    uri: Uri.parse(
      '${_base(baseUrl)}/payments/requests/${Uri.encodeComponent(requestId)}/accept',
    ),
    headers: _paymentHeaders(
      ctx: payer,
      json: true,
      idempotencyKey: idem,
    ),
    body: jsonEncode(<String, Object?>{
      'to_wallet_id': payer.walletId,
    }),
  );
  _expect2xx(r, 'payments/requests/:rid/accept (${payer.label})');
  final decoded = _decodeMap(r.body, 'payments/requests accept');
  final walletId = (decoded['wallet_id'] ?? '').toString().trim();
  if (walletId != payer.walletId) {
    throw E2eError(
      'payments request accept wallet mismatch: got=$walletId expected=${payer.walletId}',
    );
  }
}

Future<void> _paymentsRequestCancel(
  http.Client client, {
  required String baseUrl,
  required AccountCtx requester,
  required String requestId,
}) async {
  final r = await _req(
    client,
    method: 'POST',
    uri: Uri.parse(
      '${_base(baseUrl)}/payments/requests/${Uri.encodeComponent(requestId)}/cancel',
    ),
    headers: _paymentHeaders(ctx: requester),
  );
  _expect2xx(r, 'payments/requests/:rid/cancel (${requester.label})');
}

Future<void> _assertBusReadEndpoints(
  http.Client client, {
  required String baseUrl,
  required AccountCtx ctx,
}) async {
  final paths = <String>[
    '/bus/health',
    '/bus/cities?limit=5',
    '/bus/cities_cached?limit=5',
    '/bus/operators?limit=5',
    '/bus/routes',
  ];
  for (final path in paths) {
    final r = await _req(
      client,
      method: 'GET',
      uri: Uri.parse('${_base(baseUrl)}$path'),
      headers: <String, String>{'cookie': ctx.sessionCookie},
    );
    _expect2xx(r, 'bus read endpoint $path (${ctx.label})');
  }
}

Future<String> _createInvite(
  http.Client client, {
  required String baseUrl,
  required AccountCtx issuer,
}) async {
  final r = await _req(
    client,
    method: 'POST',
    uri: Uri.parse('${_base(baseUrl)}/contacts/invites'),
    headers: _chatHeaders(ctx: issuer, json: true),
    body: jsonEncode(<String, Object?>{'max_uses': 1}),
  );
  _expect2xx(r, 'contacts/invites create (${issuer.label})');
  final decoded = jsonDecode(r.body);
  if (decoded is! Map) throw E2eError('Invalid contacts/invites response');
  final token = (decoded['token'] ?? '').toString().trim();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
    throw E2eError('Invalid invite token format');
  }
  return token;
}

Future<String> _redeemInvite(
  http.Client client, {
  required String baseUrl,
  required AccountCtx redeemer,
  required String token,
}) async {
  final r = await _req(
    client,
    method: 'POST',
    uri: Uri.parse('${_base(baseUrl)}/contacts/invites/redeem'),
    headers: _chatHeaders(ctx: redeemer, json: true),
    body: jsonEncode(<String, Object?>{'token': token}),
  );
  _expect2xx(r, 'contacts/invites/redeem (${redeemer.label})');
  final decoded = jsonDecode(r.body);
  if (decoded is! Map) throw E2eError('Invalid contacts/redeem response');
  final deviceId = (decoded['device_id'] ?? '').toString().trim();
  if (deviceId.isEmpty) throw E2eError('Missing device_id in redeem response');
  return deviceId;
}

Future<String> _resolveByShamellId(
  http.Client client, {
  required String baseUrl,
  required AccountCtx actor,
  required String shamellId,
}) async {
  final r = await _req(
    client,
    method: 'POST',
    uri: Uri.parse('${_base(baseUrl)}/contacts/resolve'),
    headers: _chatHeaders(ctx: actor, json: true),
    body: jsonEncode(
        <String, Object?>{'shamell_id': shamellId.trim().toUpperCase()}),
  );
  _expect2xx(r, 'contacts/resolve (${actor.label})');
  final decoded = jsonDecode(r.body);
  if (decoded is! Map) throw E2eError('Invalid contacts/resolve response');
  final deviceId = (decoded['device_id'] ?? '').toString().trim();
  if (deviceId.isEmpty) throw E2eError('Missing device_id in resolve response');
  return deviceId;
}

Future<String> _sendDirectMessage(
  http.Client client, {
  required String baseUrl,
  required AccountCtx sender,
  required AccountCtx recipient,
  required String senderHint,
}) async {
  final r = await _req(
    client,
    method: 'POST',
    uri: Uri.parse('${_base(baseUrl)}/chat/messages/send'),
    headers: _chatHeaders(ctx: sender, json: true),
    body: jsonEncode(<String, Object?>{
      'sender_id': sender.chatDeviceId,
      'recipient_id': recipient.chatDeviceId,
      'protocol_version': 'v2_libsignal',
      'sender_pubkey_b64': sender.chatPublicKeyB64,
      'nonce_b64': _randBase64(24),
      'box_b64': _randBase64(64),
      'sealed_sender': true,
      'sender_hint': senderHint,
      'sender_fingerprint': senderHint,
    }),
  );
  _expect2xx(r, 'chat/messages/send (${sender.label}->${recipient.label})');
  final decoded = jsonDecode(r.body);
  if (decoded is! Map) throw E2eError('Invalid send response');
  final id = (decoded['id'] ?? '').toString().trim();
  if (id.isEmpty) throw E2eError('Missing message id in send response');
  return id;
}

Future<List<dynamic>> _fetchInbox(
  http.Client client, {
  required String baseUrl,
  required AccountCtx ctx,
}) async {
  final r = await _req(
    client,
    method: 'GET',
    uri: Uri.parse(
        '${_base(baseUrl)}/chat/messages/inbox?device_id=${Uri.encodeComponent(ctx.chatDeviceId)}&limit=50'),
    headers: _chatHeaders(ctx: ctx),
  );
  _expect2xx(r, 'chat/messages/inbox (${ctx.label})');
  final decoded = jsonDecode(r.body);
  if (decoded is! List) throw E2eError('Invalid inbox response (${ctx.label})');
  return decoded;
}

Future<void> _markRead(
  http.Client client, {
  required String baseUrl,
  required AccountCtx ctx,
  required String messageId,
}) async {
  final r = await _req(
    client,
    method: 'POST',
    uri: Uri.parse(
        '${_base(baseUrl)}/chat/messages/${Uri.encodeComponent(messageId)}/read'),
    headers: _chatHeaders(ctx: ctx, json: true),
    body: jsonEncode(<String, Object?>{'read': true}),
  );
  _expect2xx(r, 'chat/messages/read (${ctx.label})');
}

Future<String> _createGroup(
  http.Client client, {
  required String baseUrl,
  required AccountCtx owner,
  required AccountCtx peer,
}) async {
  final r = await _req(
    client,
    method: 'POST',
    uri: Uri.parse('${_base(baseUrl)}/chat/groups/create'),
    headers: _chatHeaders(ctx: owner, json: true),
    body: jsonEncode(<String, Object?>{
      'device_id': owner.chatDeviceId,
      'name': 'Headless-${_randId(len: 6)}',
      'member_ids': <String>[peer.chatDeviceId],
    }),
  );
  _expect2xx(r, 'chat/groups/create');
  final decoded = jsonDecode(r.body);
  if (decoded is! Map) throw E2eError('Invalid group create response');
  final gid = (decoded['group_id'] ?? '').toString().trim();
  if (gid.isEmpty) throw E2eError('Missing group_id in create response');
  return gid;
}

Future<void> _assertGroupsList(
  http.Client client, {
  required String baseUrl,
  required AccountCtx ctx,
}) async {
  final r = await _req(
    client,
    method: 'GET',
    uri: Uri.parse(
        '${_base(baseUrl)}/chat/groups/list?device_id=${Uri.encodeComponent(ctx.chatDeviceId)}'),
    headers: _chatHeaders(ctx: ctx),
  );
  _expect2xx(r, 'chat/groups/list (${ctx.label})');
}

Future<void> _sendGroupMessage(
  http.Client client, {
  required String baseUrl,
  required String groupId,
  required AccountCtx sender,
}) async {
  final r = await _req(
    client,
    method: 'POST',
    uri: Uri.parse(
        '${_base(baseUrl)}/chat/groups/${Uri.encodeComponent(groupId)}/messages/send'),
    headers: _chatHeaders(ctx: sender, json: true),
    body: jsonEncode(<String, Object?>{
      'sender_id': sender.chatDeviceId,
      'protocol_version': 'v2_libsignal',
      'nonce_b64': _randBase64(24),
      'box_b64': _randBase64(64),
    }),
  );
  _expect2xx(r, 'chat/groups/messages/send');
}

Future<void> _assertGroupInbox(
  http.Client client, {
  required String baseUrl,
  required String groupId,
  required AccountCtx ctx,
}) async {
  final r = await _req(
    client,
    method: 'GET',
    uri: Uri.parse(
      '${_base(baseUrl)}/chat/groups/${Uri.encodeComponent(groupId)}/messages/inbox'
      '?device_id=${Uri.encodeComponent(ctx.chatDeviceId)}&limit=50',
    ),
    headers: _chatHeaders(ctx: ctx),
  );
  _expect2xx(r, 'chat/groups/messages/inbox (${ctx.label})');
}

Future<void> _assertGroupMembers(
  http.Client client, {
  required String baseUrl,
  required String groupId,
  required AccountCtx ctx,
}) async {
  final r = await _req(
    client,
    method: 'GET',
    uri: Uri.parse(
      '${_base(baseUrl)}/chat/groups/${Uri.encodeComponent(groupId)}/members'
      '?device_id=${Uri.encodeComponent(ctx.chatDeviceId)}',
    ),
    headers: _chatHeaders(ctx: ctx),
  );
  _expect2xx(r, 'chat/groups/members (${ctx.label})');
}

Future<void> _chatGetDevice(
  http.Client client, {
  required String baseUrl,
  required AccountCtx ctx,
  required String deviceId,
}) async {
  final r = await _req(
    client,
    method: 'GET',
    uri: Uri.parse(
        '${_base(baseUrl)}/chat/devices/${Uri.encodeComponent(deviceId)}'),
    headers: _chatHeaders(ctx: ctx),
  );
  _expect2xx(r, 'chat/devices/:device_id get (${ctx.label})');
  final decoded = _decodeMap(r.body, 'chat get device');
  final got = (decoded['device_id'] ?? '').toString().trim();
  if (got != deviceId) {
    throw E2eError('chat get device mismatch: got=$got expected=$deviceId');
  }
}

Future<void> _chatPushToken(
  http.Client client, {
  required String baseUrl,
  required AccountCtx ctx,
}) async {
  final r = await _req(
    client,
    method: 'POST',
    uri: Uri.parse(
      '${_base(baseUrl)}/chat/devices/${Uri.encodeComponent(ctx.chatDeviceId)}/push_token',
    ),
    headers: _chatHeaders(ctx: ctx, json: true),
    body: jsonEncode(<String, Object?>{
      'token': 'push_${ctx.label.toLowerCase()}_${_randId(len: 20)}',
      'platform': 'headless',
    }),
  );
  _expect2xx(r, 'chat push token (${ctx.label})');
}

Future<void> _chatSetHidden(
  http.Client client, {
  required String baseUrl,
  required AccountCtx actor,
  required AccountCtx peer,
  required bool hidden,
}) async {
  final r = await _req(
    client,
    method: 'POST',
    uri: Uri.parse(
      '${_base(baseUrl)}/chat/devices/${Uri.encodeComponent(actor.chatDeviceId)}/block',
    ),
    headers: _chatHeaders(ctx: actor, json: true),
    body: jsonEncode(<String, Object?>{
      'peer_id': peer.chatDeviceId,
      'blocked': false,
      'hidden': hidden,
    }),
  );
  _expect2xx(r, 'chat hidden set (${actor.label})');
}

Future<void> _chatAssertHiddenContains(
  http.Client client, {
  required String baseUrl,
  required AccountCtx actor,
  required String peerDeviceId,
  required bool expected,
}) async {
  final r = await _req(
    client,
    method: 'GET',
    uri: Uri.parse(
      '${_base(baseUrl)}/chat/devices/${Uri.encodeComponent(actor.chatDeviceId)}/hidden',
    ),
    headers: _chatHeaders(ctx: actor),
  );
  _expect2xx(r, 'chat hidden list (${actor.label})');
  final decoded = _decodeMap(r.body, 'chat hidden list');
  final hiddenRaw = decoded['hidden'];
  final hidden = hiddenRaw is List
      ? hiddenRaw.map((e) => e.toString().trim()).toList()
      : const <String>[];
  final contains = hidden.contains(peerDeviceId);
  if (contains != expected) {
    throw E2eError(
      'chat hidden list mismatch (${actor.label}): contains=$contains expected=$expected',
    );
  }
}

Future<void> _chatSetPrefs(
  http.Client client, {
  required String baseUrl,
  required AccountCtx actor,
  required AccountCtx peer,
  required bool muted,
  required bool starred,
  required bool pinned,
}) async {
  final r = await _req(
    client,
    method: 'POST',
    uri: Uri.parse(
      '${_base(baseUrl)}/chat/devices/${Uri.encodeComponent(actor.chatDeviceId)}/prefs',
    ),
    headers: _chatHeaders(ctx: actor, json: true),
    body: jsonEncode(<String, Object?>{
      'peer_id': peer.chatDeviceId,
      'muted': muted,
      'starred': starred,
      'pinned': pinned,
    }),
  );
  _expect2xx(r, 'chat prefs set (${actor.label})');
}

Future<void> _chatAssertPrefs(
  http.Client client, {
  required String baseUrl,
  required AccountCtx actor,
  required AccountCtx peer,
  required bool muted,
  required bool starred,
  required bool pinned,
}) async {
  final r = await _req(
    client,
    method: 'GET',
    uri: Uri.parse(
      '${_base(baseUrl)}/chat/devices/${Uri.encodeComponent(actor.chatDeviceId)}/prefs',
    ),
    headers: _chatHeaders(ctx: actor),
  );
  _expect2xx(r, 'chat prefs list (${actor.label})');
  final decoded = _decodeMap(r.body, 'chat prefs list');
  final prefs = decoded['prefs'];
  if (prefs is! List) {
    throw E2eError('Invalid chat prefs list response: missing prefs list');
  }
  Map<String, dynamic>? target;
  for (final e in prefs) {
    if (e is Map &&
        (e['peer_id'] ?? '').toString().trim() == peer.chatDeviceId) {
      target = <String, dynamic>{};
      e.forEach((key, value) => target![key.toString()] = value);
      break;
    }
  }
  if (target == null) {
    throw E2eError(
        'chat prefs list does not contain peer ${peer.chatDeviceId}');
  }
  final gotMuted = target['muted'] == true;
  final gotStarred = target['starred'] == true;
  final gotPinned = target['pinned'] == true;
  if (gotMuted != muted || gotStarred != starred || gotPinned != pinned) {
    throw E2eError(
      'chat prefs mismatch: muted=$gotMuted/$muted starred=$gotStarred/$starred pinned=$gotPinned/$pinned',
    );
  }
}

Future<void> _chatGroupUpdate(
  http.Client client, {
  required String baseUrl,
  required String groupId,
  required AccountCtx actor,
}) async {
  final r = await _req(
    client,
    method: 'POST',
    uri: Uri.parse(
      '${_base(baseUrl)}/chat/groups/${Uri.encodeComponent(groupId)}/update',
    ),
    headers: _chatHeaders(ctx: actor, json: true),
    body: jsonEncode(<String, Object?>{
      'actor_id': actor.chatDeviceId,
      'name': 'HeadlessUpd-${_randId(len: 5)}',
    }),
  );
  _expect2xx(r, 'chat/groups/update');
}

Future<void> _chatGroupSetRole(
  http.Client client, {
  required String baseUrl,
  required String groupId,
  required AccountCtx actorAdmin,
  required AccountCtx target,
  required String role,
}) async {
  final r = await _req(
    client,
    method: 'POST',
    uri: Uri.parse(
      '${_base(baseUrl)}/chat/groups/${Uri.encodeComponent(groupId)}/set_role',
    ),
    headers: _chatHeaders(ctx: actorAdmin, json: true),
    body: jsonEncode(<String, Object?>{
      'actor_id': actorAdmin.chatDeviceId,
      'target_id': target.chatDeviceId,
      'role': role,
    }),
  );
  _expect2xx(r, 'chat/groups/set_role');
}

Future<int> _chatGroupRotateKey(
  http.Client client, {
  required String baseUrl,
  required String groupId,
  required AccountCtx actorAdmin,
}) async {
  final r = await _req(
    client,
    method: 'POST',
    uri: Uri.parse(
      '${_base(baseUrl)}/chat/groups/${Uri.encodeComponent(groupId)}/keys/rotate',
    ),
    headers: _chatHeaders(ctx: actorAdmin, json: true),
    body: jsonEncode(<String, Object?>{
      'actor_id': actorAdmin.chatDeviceId,
      'key_fp': _randId(len: 12),
    }),
  );
  _expect2xx(r, 'chat/groups/keys/rotate');
  final decoded = _decodeMap(r.body, 'chat group rotate key');
  return _parseIntField(decoded['version'], 'version', 'chat group rotate key');
}

Future<void> _chatAssertGroupKeyEventVersion(
  http.Client client, {
  required String baseUrl,
  required String groupId,
  required AccountCtx ctx,
  required int version,
}) async {
  for (var attempt = 0; attempt < 6; attempt++) {
    final r = await _req(
      client,
      method: 'GET',
      uri: Uri.parse(
        '${_base(baseUrl)}/chat/groups/${Uri.encodeComponent(groupId)}/keys/events'
        '?device_id=${Uri.encodeComponent(ctx.chatDeviceId)}&limit=50',
      ),
      headers: _chatHeaders(ctx: ctx),
    );
    _expect2xx(r, 'chat/groups/keys/events (${ctx.label})');
    final list = _decodeList(r.body, 'chat group key events');
    var found = false;
    for (final e in list) {
      if (e is! Map) continue;
      final vRaw = e['version'];
      final v = vRaw is num
          ? vRaw.toInt()
          : int.tryParse((vRaw ?? '').toString().trim());
      if (v == version) {
        found = true;
        break;
      }
    }
    if (found) return;
    if (attempt < 5) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
  }
  throw E2eError('Group key event version not found: $version');
}

Future<void> _chatSetGroupPrefs(
  http.Client client, {
  required String baseUrl,
  required String groupId,
  required AccountCtx ctx,
  required bool muted,
  required bool pinned,
}) async {
  final r = await _req(
    client,
    method: 'POST',
    uri: Uri.parse(
      '${_base(baseUrl)}/chat/devices/${Uri.encodeComponent(ctx.chatDeviceId)}/group_prefs',
    ),
    headers: _chatHeaders(ctx: ctx, json: true),
    body: jsonEncode(<String, Object?>{
      'group_id': groupId,
      'muted': muted,
      'pinned': pinned,
    }),
  );
  _expect2xx(r, 'chat group prefs set (${ctx.label})');
}

Future<void> _chatAssertGroupPrefs(
  http.Client client, {
  required String baseUrl,
  required String groupId,
  required AccountCtx ctx,
  required bool muted,
  required bool pinned,
}) async {
  final r = await _req(
    client,
    method: 'GET',
    uri: Uri.parse(
      '${_base(baseUrl)}/chat/devices/${Uri.encodeComponent(ctx.chatDeviceId)}/group_prefs',
    ),
    headers: _chatHeaders(ctx: ctx),
  );
  _expect2xx(r, 'chat group prefs list (${ctx.label})');
  final list = _decodeList(r.body, 'chat group prefs list');
  Map<String, dynamic>? target;
  for (final e in list) {
    if (e is Map && (e['group_id'] ?? '').toString().trim() == groupId) {
      target = <String, dynamic>{};
      e.forEach((key, value) => target![key.toString()] = value);
      break;
    }
  }
  if (target == null) {
    throw E2eError('chat group prefs missing group_id=$groupId');
  }
  final gotMuted = target['muted'] == true;
  final gotPinned = target['pinned'] == true;
  if (gotMuted != muted || gotPinned != pinned) {
    throw E2eError(
      'chat group prefs mismatch: muted=$gotMuted/$muted pinned=$gotPinned/$pinned',
    );
  }
}

Uri _wsUri(String baseUrl, String pathAndQuery) {
  final b = Uri.parse(_base(baseUrl));
  final scheme = b.scheme == 'https' ? 'wss' : 'ws';
  return Uri(
    scheme: scheme,
    userInfo: b.userInfo,
    host: b.host,
    port: b.hasPort ? b.port : null,
    path: pathAndQuery.split('?').first,
    query: pathAndQuery.contains('?') ? pathAndQuery.split('?').last : null,
  );
}

Future<CallSignalPair> _connectCallSignals({
  required String baseUrl,
  required AccountCtx a,
  required AccountCtx b,
}) async {
  final wsA = await WebSocket.connect(
    _wsUri(baseUrl,
            '/ws/call/signaling?device_id=${Uri.encodeComponent(a.chatDeviceId)}')
        .toString(),
    headers: <String, dynamic>{'cookie': a.sessionCookie},
  );
  final wsB = await WebSocket.connect(
    _wsUri(baseUrl,
            '/ws/call/signaling?device_id=${Uri.encodeComponent(b.chatDeviceId)}')
        .toString(),
    headers: <String, dynamic>{'cookie': b.sessionCookie},
  );
  return CallSignalPair(a: wsA, b: wsB);
}

Future<Map<String, dynamic>> _waitWsJson(WebSocket ws,
    {Duration timeout = const Duration(seconds: 8)}) async {
  final msg = await ws.first.timeout(timeout);
  if (msg is! String) throw E2eError('WS payload is not text');
  final decoded = jsonDecode(msg);
  if (decoded is! Map<String, dynamic>) {
    throw E2eError('WS payload is not JSON object');
  }
  return decoded;
}

Future<void> _assertCallSignalingRoundtrip({
  required String baseUrl,
  required AccountCtx a,
  required AccountCtx b,
}) async {
  final pair = await _connectCallSignals(baseUrl: baseUrl, a: a, b: b);
  try {
    final callId = 'headless-${_randId(len: 10)}';
    pair.a.add(jsonEncode(<String, Object?>{
      'type': 'offer',
      'to': b.chatDeviceId,
      'call_id': callId,
      'sdp': 'offer-${_nowIso()}',
    }));
    final gotOnB = await _waitWsJson(pair.b);
    if ((gotOnB['from'] ?? '').toString().trim() != a.chatDeviceId) {
      throw E2eError('Call signaling A->B failed: wrong "from" field');
    }
    if ((gotOnB['type'] ?? '').toString().trim() != 'offer') {
      throw E2eError('Call signaling A->B failed: wrong "type"');
    }

    pair.b.add(jsonEncode(<String, Object?>{
      'type': 'answer',
      'to': a.chatDeviceId,
      'call_id': callId,
      'sdp': 'answer-${_nowIso()}',
    }));
    final gotOnA = await _waitWsJson(pair.a);
    if ((gotOnA['from'] ?? '').toString().trim() != b.chatDeviceId) {
      throw E2eError('Call signaling B->A failed: wrong "from" field');
    }
    if ((gotOnA['type'] ?? '').toString().trim() != 'answer') {
      throw E2eError('Call signaling B->A failed: wrong "type"');
    }
  } finally {
    await pair.a.close();
    await pair.b.close();
  }
}

Future<void> _logout(
  http.Client client, {
  required String baseUrl,
  required AccountCtx ctx,
}) async {
  final r = await _req(
    client,
    method: 'POST',
    uri: Uri.parse('${_base(baseUrl)}/auth/logout'),
    headers: <String, String>{'cookie': ctx.sessionCookie},
  );
  _expect2xx(r, 'auth/logout (${ctx.label})');
}

void _printStep(String msg) {
  stdout.writeln('[${_nowIso()}] $msg');
}

Future<void> _runCheck(
  List<String> failures,
  String label,
  Future<void> Function() action,
) async {
  try {
    await action();
    _printStep('PASS: $label');
  } catch (e) {
    final line = '$label -> $e';
    failures.add(line);
    stderr.writeln('CHECK_FAIL: $line');
  }
}

Future<void> main(List<String> args) async {
  var baseUrl = const String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'https://api.shamell.online',
  );
  var keepSessions = false;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--base-url' && i + 1 < args.length) {
      baseUrl = args[++i];
    } else if (a == '--keep-sessions') {
      keepSessions = true;
    } else if (a == '-h' || a == '--help') {
      stdout.writeln(
        'Usage: dart run tool/headless_two_account_e2e.dart '
        '[--base-url <url>] [--keep-sessions]',
      );
      return;
    } else {
      throw E2eError('Unknown argument: $a');
    }
  }

  final client = http.Client();
  late AccountCtx a;
  late AccountCtx b;
  final failures = <String>[];
  String walletOrDash(AccountCtx ctx) {
    try {
      return ctx.walletId;
    } catch (_) {
      return '-';
    }
  }

  try {
    _printStep('Base URL: ${_base(baseUrl)}');
    a = await _createAccount(client, baseUrl: baseUrl, label: 'A');
    b = await _createAccount(client, baseUrl: baseUrl, label: 'B');
    _printStep('Created accounts: A=${a.shamellId} B=${b.shamellId}');

    await _registerAuthDevice(client, baseUrl: baseUrl, ctx: a);
    await _registerAuthDevice(client, baseUrl: baseUrl, ctx: b);
    _printStep('Registered auth devices.');

    await _registerChatDevice(client, baseUrl: baseUrl, ctx: a);
    await _registerChatDevice(client, baseUrl: baseUrl, ctx: b);
    _printStep(
        'Registered chat devices: A=${a.chatDeviceId} B=${b.chatDeviceId}');

    await _assertHomeSnapshot(client, baseUrl: baseUrl, ctx: a);
    await _assertHomeSnapshot(client, baseUrl: baseUrl, ctx: b);
    await _assertAuthDevicesList(client, baseUrl: baseUrl, ctx: a);
    await _assertAuthDevicesList(client, baseUrl: baseUrl, ctx: b);
    _printStep('Verified account endpoints (home_snapshot, auth/devices).');

    await _runCheck(failures, 'payments endpoints', () async {
      await _paymentsEnsureUser(client, baseUrl: baseUrl, ctx: a);
      await _paymentsEnsureUser(client, baseUrl: baseUrl, ctx: b);
      await _paymentsGetWalletBalance(client, baseUrl: baseUrl, ctx: a);
      await _paymentsGetWalletBalance(client, baseUrl: baseUrl, ctx: b);
      await _paymentsTopup(client, baseUrl: baseUrl, ctx: a, amountCents: 5000);
      await _paymentsTopup(client, baseUrl: baseUrl, ctx: b, amountCents: 5000);
      await _paymentsTransfer(
        client,
        baseUrl: baseUrl,
        sender: a,
        recipient: b,
        amountCents: 700,
      );
      final favoriteId = await _paymentsFavoriteCreate(
        client,
        baseUrl: baseUrl,
        owner: a,
        favorite: b,
      );
      await _paymentsFavoriteListContains(
        client,
        baseUrl: baseUrl,
        owner: a,
        favoriteId: favoriteId,
      );
      await _paymentsFavoriteDelete(
        client,
        baseUrl: baseUrl,
        owner: a,
        favoriteId: favoriteId,
      );
      final requestId = await _paymentsRequestCreate(
        client,
        baseUrl: baseUrl,
        requester: a,
        payer: b,
        amountCents: 333,
        message: 'headless request accept',
      );
      await _paymentsRequestListContains(
        client,
        baseUrl: baseUrl,
        actor: a,
        kind: 'outgoing',
        requestId: requestId,
      );
      await _paymentsRequestListContains(
        client,
        baseUrl: baseUrl,
        actor: b,
        kind: 'incoming',
        requestId: requestId,
      );
      await _paymentsRequestAccept(
        client,
        baseUrl: baseUrl,
        payer: b,
        requestId: requestId,
      );
      final cancelRid = await _paymentsRequestCreate(
        client,
        baseUrl: baseUrl,
        requester: a,
        payer: b,
        amountCents: 111,
        message: 'headless request cancel',
      );
      await _paymentsRequestCancel(
        client,
        baseUrl: baseUrl,
        requester: a,
        requestId: cancelRid,
      );
      await _paymentsGetWalletBalance(client, baseUrl: baseUrl, ctx: a);
      await _paymentsGetWalletBalance(client, baseUrl: baseUrl, ctx: b);
    });

    await _runCheck(failures, 'bus read endpoints', () async {
      await _assertBusReadEndpoints(client, baseUrl: baseUrl, ctx: a);
    });

    await _runCheck(failures, 'chat device + push token', () async {
      await _chatGetDevice(
        client,
        baseUrl: baseUrl,
        ctx: a,
        deviceId: a.chatDeviceId,
      );
      await _chatGetDevice(
        client,
        baseUrl: baseUrl,
        ctx: b,
        deviceId: b.chatDeviceId,
      );
      await _chatPushToken(client, baseUrl: baseUrl, ctx: a);
      await _chatPushToken(client, baseUrl: baseUrl, ctx: b);
    });

    await _runCheck(failures, 'contacts invite/redeem/resolve', () async {
      final inviteToken =
          await _createInvite(client, baseUrl: baseUrl, issuer: a);
      final redeemedA = await _redeemInvite(
        client,
        baseUrl: baseUrl,
        redeemer: b,
        token: inviteToken,
      );
      final resolvedB = await _resolveByShamellId(
        client,
        baseUrl: baseUrl,
        actor: a,
        shamellId: b.shamellId,
      );
      if (redeemedA != a.chatDeviceId || resolvedB != b.chatDeviceId) {
        throw E2eError(
          'Contact bootstrap mismatch: redeemA=$redeemedA expected=${a.chatDeviceId}, '
          'resolveB=$resolvedB expected=${b.chatDeviceId}',
        );
      }
      final resolvedA = await _resolveByShamellId(
        client,
        baseUrl: baseUrl,
        actor: b,
        shamellId: a.shamellId,
      );
      if (resolvedA != a.chatDeviceId) {
        throw E2eError(
            'Reverse resolve mismatch: $resolvedA != ${a.chatDeviceId}');
      }
    });

    await _runCheck(failures, 'chat hidden + contact prefs', () async {
      await _chatSetHidden(
        client,
        baseUrl: baseUrl,
        actor: a,
        peer: b,
        hidden: true,
      );
      await _chatAssertHiddenContains(
        client,
        baseUrl: baseUrl,
        actor: a,
        peerDeviceId: b.chatDeviceId,
        expected: true,
      );
      await _chatSetHidden(
        client,
        baseUrl: baseUrl,
        actor: a,
        peer: b,
        hidden: false,
      );
      await _chatAssertHiddenContains(
        client,
        baseUrl: baseUrl,
        actor: a,
        peerDeviceId: b.chatDeviceId,
        expected: false,
      );
      await _chatSetPrefs(
        client,
        baseUrl: baseUrl,
        actor: a,
        peer: b,
        muted: true,
        starred: true,
        pinned: true,
      );
      await _chatAssertPrefs(
        client,
        baseUrl: baseUrl,
        actor: a,
        peer: b,
        muted: true,
        starred: true,
        pinned: true,
      );
    });

    await _runCheck(failures, 'direct chat send/inbox/read', () async {
      final sentA = await _sendDirectMessage(
        client,
        baseUrl: baseUrl,
        sender: a,
        recipient: b,
        senderHint: a.chatPublicKeyB64.substring(0, 44),
      );
      final sentB = await _sendDirectMessage(
        client,
        baseUrl: baseUrl,
        sender: b,
        recipient: a,
        senderHint: b.chatPublicKeyB64.substring(0, 44),
      );
      final inboxA = await _fetchInbox(client, baseUrl: baseUrl, ctx: a);
      final inboxB = await _fetchInbox(client, baseUrl: baseUrl, ctx: b);
      if (inboxA.isEmpty || inboxB.isEmpty) {
        throw E2eError('Direct inbox is empty after sends');
      }
      await _markRead(client, baseUrl: baseUrl, ctx: a, messageId: sentB);
      await _markRead(client, baseUrl: baseUrl, ctx: b, messageId: sentA);
    });

    await _runCheck(failures, 'group chat + group management', () async {
      final groupId =
          await _createGroup(client, baseUrl: baseUrl, owner: a, peer: b);
      await _assertGroupsList(client, baseUrl: baseUrl, ctx: a);
      await _assertGroupsList(client, baseUrl: baseUrl, ctx: b);
      await _chatGroupUpdate(
        client,
        baseUrl: baseUrl,
        groupId: groupId,
        actor: a,
      );
      await _chatGroupSetRole(
        client,
        baseUrl: baseUrl,
        groupId: groupId,
        actorAdmin: a,
        target: b,
        role: 'admin',
      );
      await _chatGroupSetRole(
        client,
        baseUrl: baseUrl,
        groupId: groupId,
        actorAdmin: a,
        target: b,
        role: 'member',
      );
      final keyVersion = await _chatGroupRotateKey(
        client,
        baseUrl: baseUrl,
        groupId: groupId,
        actorAdmin: a,
      );
      await _chatAssertGroupKeyEventVersion(
        client,
        baseUrl: baseUrl,
        groupId: groupId,
        ctx: a,
        version: keyVersion,
      );
      await _chatSetGroupPrefs(
        client,
        baseUrl: baseUrl,
        groupId: groupId,
        ctx: a,
        muted: true,
        pinned: true,
      );
      await _chatAssertGroupPrefs(
        client,
        baseUrl: baseUrl,
        groupId: groupId,
        ctx: a,
        muted: true,
        pinned: true,
      );
      await _sendGroupMessage(
        client,
        baseUrl: baseUrl,
        groupId: groupId,
        sender: a,
      );
      await _assertGroupInbox(client,
          baseUrl: baseUrl, groupId: groupId, ctx: b);
      await _assertGroupMembers(client,
          baseUrl: baseUrl, groupId: groupId, ctx: a);
    });

    await _runCheck(failures, 'call signaling roundtrip', () async {
      await _assertCallSignalingRoundtrip(baseUrl: baseUrl, a: a, b: b);
    });

    if (!keepSessions) {
      await _logout(client, baseUrl: baseUrl, ctx: a);
      await _logout(client, baseUrl: baseUrl, ctx: b);
      _printStep('Logged out both headless sessions.');
    } else {
      _printStep('Keeping sessions (requested by --keep-sessions).');
    }

    stdout.writeln('');
    if (failures.isEmpty) {
      stdout.writeln('HEADLESS_E2E_OK');
    } else {
      stdout.writeln('HEADLESS_E2E_PARTIAL');
      stdout.writeln('Failed checks: ${failures.length}');
      for (final f in failures) {
        stdout.writeln('- $f');
      }
      exitCode = 1;
    }
    stdout.writeln('A shamell_id: ${a.shamellId}');
    stdout.writeln('B shamell_id: ${b.shamellId}');
    stdout.writeln('A wallet_id: ${walletOrDash(a)}');
    stdout.writeln('B wallet_id: ${walletOrDash(b)}');
    stdout.writeln('A chat_device_id: ${a.chatDeviceId}');
    stdout.writeln('B chat_device_id: ${b.chatDeviceId}');
  } on TimeoutException catch (e) {
    stderr.writeln('HEADLESS_E2E_FAIL timeout: $e');
    exitCode = 2;
  } on E2eError catch (e) {
    stderr.writeln('HEADLESS_E2E_FAIL: $e');
    exitCode = 1;
  } catch (e, st) {
    stderr.writeln('HEADLESS_E2E_FAIL unexpected: $e');
    stderr.writeln(st);
    exitCode = 1;
  } finally {
    client.close();
  }
}
