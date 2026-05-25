import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:pinenacl/x25519.dart' as x25519;

class ProbeError implements Exception {
  final String message;
  ProbeError(this.message);
  @override
  String toString() => message;
}

class Ctx {
  final String label;
  final String accountDeviceId;
  late String sessionCookie;
  late String shamellId;
  late String chatDeviceId;
  late String chatAuthToken;
  late String chatPublicKeyB64;
  Ctx({required this.label, required this.accountDeviceId});
}

String? _hostHeaderOverride;

String _base(String raw) {
  final t = raw.trim();
  return t.endsWith('/') ? t.substring(0, t.length - 1) : t;
}

String _randId({int len = 16}) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final r = Random.secure();
  return List.generate(len, (_) => chars[r.nextInt(chars.length)]).join();
}

String _cookieFromSetCookie(String? raw) {
  final sc = (raw ?? '').trim();
  if (sc.isEmpty) {
    throw ProbeError('Missing set-cookie header');
  }
  final match =
      RegExp(r'__host-sa_session=([0-9a-f]{32})', caseSensitive: false)
          .firstMatch(sc);
  if (match != null) {
    return '__Host-sa_session=${match.group(1)!}';
  }
  throw ProbeError('Could not parse active session cookie');
}

Map<String, String> _jsonHeaders({String? cookie}) {
  return <String, String>{
    'content-type': 'application/json',
    if (cookie != null && cookie.isNotEmpty) 'cookie': cookie,
  };
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
  final hostHeader = _hostHeaderOverride;
  if (hostHeader != null && hostHeader.isNotEmpty) {
    req.headers['host'] = hostHeader;
  }
  if (body != null) req.body = body.toString();
  final streamed = await client.send(req).timeout(const Duration(seconds: 30));
  return http.Response.fromStream(streamed);
}

void _expect2xx(http.Response r, String op) {
  if (r.statusCode >= 200 && r.statusCode < 300) return;
  throw ProbeError('$op failed: HTTP ${r.statusCode} body=${r.body}');
}

Future<Ctx> _createAccount(
  http.Client client, {
  required String baseUrl,
  required String label,
}) async {
  final ctx = Ctx(
    label: label,
    accountDeviceId: 'acc${_randId(len: 12)}',
  );
  final base = _base(baseUrl);
  final username = 'probe_${label.toLowerCase()}_${_randId(len: 12)}';
  final password = 'Shamell!${_randId(len: 18)}';

  final signupResp = await _req(
    client,
    method: 'POST',
    uri: Uri.parse('$base/auth/signup'),
    headers: _jsonHeaders(),
    body: jsonEncode(<String, Object?>{
      'username': username,
      'password': password,
      'device_id': ctx.accountDeviceId,
    }),
  );
  _expect2xx(signupResp, 'auth/signup ($label)');
  ctx.sessionCookie = _cookieFromSetCookie(signupResp.headers['set-cookie']);
  final decoded = jsonDecode(signupResp.body);
  if (decoded is! Map) {
    throw ProbeError('invalid auth/signup response ($label)');
  }
  ctx.shamellId = (decoded['shamell_id'] ?? '').toString().trim();
  if (ctx.shamellId.isEmpty) {
    throw ProbeError('missing shamell_id ($label)');
  }
  return ctx;
}

Future<void> _registerAuthDevice(
  http.Client client, {
  required String baseUrl,
  required Ctx ctx,
}) async {
  final r = await _req(
    client,
    method: 'POST',
    uri: Uri.parse('${_base(baseUrl)}/auth/devices/register'),
    headers: _jsonHeaders(cookie: ctx.sessionCookie),
    body: jsonEncode(<String, Object?>{
      'device_id': ctx.accountDeviceId,
      'device_type': 'headless',
      'platform': 'headless',
      'device_name': 'Probe ${ctx.label}',
    }),
  );
  _expect2xx(r, 'auth/devices/register (${ctx.label})');
}

Future<void> _registerChatDevice(
  http.Client client, {
  required String baseUrl,
  required Ctx ctx,
}) async {
  final sk = x25519.PrivateKey.generate();
  final pkB64 = base64Encode(sk.publicKey.asTypedList);
  final chatDeviceId = 'd${_randId(len: 12)}';
  final r = await _req(
    client,
    method: 'POST',
    uri: Uri.parse('${_base(baseUrl)}/chat/devices/register'),
    headers: _jsonHeaders(cookie: ctx.sessionCookie),
    body: jsonEncode(<String, Object?>{
      'device_id': chatDeviceId,
      'client_device_id': ctx.accountDeviceId,
      'public_key_b64': pkB64,
      'name': 'Probe ${ctx.label}',
    }),
  );
  _expect2xx(r, 'chat/devices/register (${ctx.label})');
  final decoded = jsonDecode(r.body);
  if (decoded is! Map) {
    throw ProbeError('invalid chat register response (${ctx.label})');
  }
  ctx.chatDeviceId = (decoded['device_id'] ?? chatDeviceId).toString().trim();
  ctx.chatAuthToken = (decoded['auth_token'] ?? '').toString().trim();
  if (ctx.chatAuthToken.isEmpty) {
    throw ProbeError('missing chat auth_token (${ctx.label})');
  }
  ctx.chatPublicKeyB64 = pkB64;
}

Future<String> _createInvite(
  http.Client client, {
  required String baseUrl,
  required Ctx issuer,
}) async {
  final r = await _req(
    client,
    method: 'POST',
    uri: Uri.parse('${_base(baseUrl)}/contacts/invites'),
    headers: <String, String>{
      'cookie': issuer.sessionCookie,
      'x-chat-device-id': issuer.chatDeviceId,
      'x-chat-device-token': issuer.chatAuthToken,
      'content-type': 'application/json',
    },
    body: jsonEncode(<String, Object?>{'max_uses': 1}),
  );
  _expect2xx(r, 'contacts/invites/create (${issuer.label})');
  final decoded = jsonDecode(r.body);
  if (decoded is! Map) throw ProbeError('invalid contacts invite response');
  final token = (decoded['token'] ?? '').toString().trim();
  if (token.isEmpty) throw ProbeError('missing invite token');
  return token;
}

Future<void> _redeemInvite(
  http.Client client, {
  required String baseUrl,
  required Ctx redeemer,
  required String token,
}) async {
  final r = await _req(
    client,
    method: 'POST',
    uri: Uri.parse('${_base(baseUrl)}/contacts/invites/redeem'),
    headers: <String, String>{
      'cookie': redeemer.sessionCookie,
      'x-chat-device-id': redeemer.chatDeviceId,
      'x-chat-device-token': redeemer.chatAuthToken,
      'content-type': 'application/json',
    },
    body: jsonEncode(<String, Object?>{'token': token}),
  );
  _expect2xx(r, 'contacts/invites/redeem (${redeemer.label})');
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

Future<void> _printFirstMessages(
  WebSocket ws,
  String label, {
  int seconds = 5,
}) async {
  final until = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(until)) {
    final remain = until.difference(DateTime.now());
    dynamic msg;
    try {
      msg = await ws.first.timeout(remain);
    } catch (_) {
      break;
    }
    stdout.writeln('[$label] ${msg.toString()}');
  }
}

Future<void> main(List<String> args) async {
  var baseUrl = 'https://api.shamell.online';
  var hostHeader = Platform.environment['SHAMELL_E2E_HOST_HEADER'] ?? '';
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--base-url' && i + 1 < args.length) {
      baseUrl = args[++i];
    } else if (args[i] == '--host-header' && i + 1 < args.length) {
      hostHeader = args[++i];
    }
  }
  _hostHeaderOverride = hostHeader.trim().isEmpty ? null : hostHeader.trim();

  final client = http.Client();
  try {
    final a = await _createAccount(client, baseUrl: baseUrl, label: 'A');
    final b = await _createAccount(client, baseUrl: baseUrl, label: 'B');
    await _registerAuthDevice(client, baseUrl: baseUrl, ctx: a);
    await _registerAuthDevice(client, baseUrl: baseUrl, ctx: b);
    await _registerChatDevice(client, baseUrl: baseUrl, ctx: a);
    await _registerChatDevice(client, baseUrl: baseUrl, ctx: b);
    final tokenA = await _createInvite(client, baseUrl: baseUrl, issuer: a);
    await _redeemInvite(client, baseUrl: baseUrl, redeemer: b, token: tokenA);
    final tokenB = await _createInvite(client, baseUrl: baseUrl, issuer: b);
    await _redeemInvite(client, baseUrl: baseUrl, redeemer: a, token: tokenB);

    stdout.writeln('A: ${a.chatDeviceId}');
    stdout.writeln('B: ${b.chatDeviceId}');

    final wsA = await WebSocket.connect(
      _wsUri(baseUrl, '/ws/call/signaling?device_id=${a.chatDeviceId}')
          .toString(),
      headers: <String, dynamic>{
        'cookie': a.sessionCookie,
        'x-chat-device-id': a.chatDeviceId,
        'x-chat-device-token': a.chatAuthToken,
        if (_hostHeaderOverride != null) 'host': _hostHeaderOverride!,
      },
    );
    final wsB = await WebSocket.connect(
      _wsUri(baseUrl, '/ws/call/signaling?device_id=${b.chatDeviceId}')
          .toString(),
      headers: <String, dynamic>{
        'cookie': b.sessionCookie,
        'x-chat-device-id': b.chatDeviceId,
        'x-chat-device-token': b.chatAuthToken,
        if (_hostHeaderOverride != null) 'host': _hostHeaderOverride!,
      },
    );

    final callId = 'probe-${_randId(len: 8)}';
    wsA.add(jsonEncode(<String, Object?>{
      'type': 'invite',
      'to': b.chatDeviceId,
      'call_id': callId,
      'mode': 'audio',
    }));

    await Future.wait([
      _printFirstMessages(wsA, 'A'),
      _printFirstMessages(wsB, 'B'),
    ]);

    await wsA.close();
    await wsB.close();
  } finally {
    client.close();
  }
}
