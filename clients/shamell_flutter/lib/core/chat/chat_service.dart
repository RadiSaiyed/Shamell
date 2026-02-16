import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:pinenacl/ed25519.dart' as ed25519;
import 'package:pinenacl/x25519.dart' as x25519;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'chat_models.dart';
import 'package:shamell_flutter/core/device_id.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';

@visibleForTesting
const bool shamellDesktopSecureStorageDefault = bool.fromEnvironment(
  'ENABLE_DESKTOP_SECURE_STORAGE',
  defaultValue: true,
);

@visibleForTesting
const String shamellChatProtocolSendVersion = 'v2_libsignal';

@visibleForTesting
const bool shamellLibsignalKeyApiDebugDefault = bool.fromEnvironment(
  'ENABLE_LIBSIGNAL_KEY_API',
  defaultValue: true,
);

@visibleForTesting
const bool shamellLibsignalKeyApiReleaseDefault = bool.fromEnvironment(
  'ENABLE_LIBSIGNAL_KEY_API_IN_RELEASE',
  defaultValue: false,
);

@visibleForTesting
const bool shamellLibsignalV2OnlyDebugDefault = bool.fromEnvironment(
  'CHAT_PROTOCOL_V2_ONLY',
  defaultValue: true,
);

@visibleForTesting
const bool shamellLibsignalV2OnlyReleaseDefault = bool.fromEnvironment(
  'CHAT_PROTOCOL_V2_ONLY_IN_RELEASE',
  defaultValue: true,
);

@visibleForTesting
const int shamellLibsignalPrekeyBatchDefault = int.fromEnvironment(
  'LIBSIGNAL_PREKEY_BATCH_SIZE',
  defaultValue: 64,
);

enum OfficialNotificationMode {
  full, // show message preview
  summary, // generic text only, no preview
  muted, // no local notification
}

/// Minimal typed HTTP error for chat calls.
///
/// Best practice: keep raw bodies out of exception strings to avoid leaking
/// server internals into UI logs/crash reports. Callers may still inspect
/// `statusCode`/`body` for safe error mapping.
class ChatHttpException implements Exception {
  final String op;
  final int statusCode;
  final String? body;

  const ChatHttpException({
    required this.op,
    required this.statusCode,
    this.body,
  });

  @override
  String toString() => 'ChatHttpException($op, HTTP $statusCode)';
}

@visibleForTesting
ChatGroupMessage shamellDecryptOrBlockGroupMessage(
    ChatGroupMessage m, Uint8List key) {
  final kind = (m.kind ?? '').toLowerCase();
  if (kind == 'system') return m;

  // Fail closed: group chat must never render unsealed user content.
  if (kind != 'sealed') {
    return ChatGroupMessage(
      id: m.id,
      groupId: m.groupId,
      senderId: m.senderId,
      text: 'Blocked insecure group message',
      kind: 'system',
      createdAt: m.createdAt,
      expireAt: m.expireAt,
    );
  }
  if (m.nonceB64 == null ||
      m.boxB64 == null ||
      m.nonceB64!.isEmpty ||
      m.boxB64!.isEmpty) {
    // Keep the message but clear any server-provided plaintext fields.
    return ChatGroupMessage(
      id: m.id,
      groupId: m.groupId,
      senderId: m.senderId,
      text: '',
      kind: 'sealed',
      nonceB64: m.nonceB64,
      boxB64: m.boxB64,
      createdAt: m.createdAt,
      expireAt: m.expireAt,
    );
  }
  try {
    final nonce = base64Decode(m.nonceB64!);
    final boxBytes = base64Decode(m.boxB64!);
    final plain = x25519.SecretBox(
      key,
    ).decrypt(x25519.ByteList(boxBytes), nonce: nonce);
    final raw = utf8.decode(plain);
    final j = jsonDecode(raw);
    if (j is Map) {
      final text = (j['text'] ?? '').toString();
      final kindRaw = (j['kind'] ?? '').toString().trim();
      final attB64 = (j['attachment_b64'] ?? '').toString();
      final attMime = (j['attachment_mime'] ?? '').toString();
      final voiceSecs = j['voice_secs'] is num
          ? (j['voice_secs'] as num).toInt()
          : int.tryParse((j['voice_secs'] ?? '').toString());
      double? lat;
      double? lon;
      final latRaw = j['lat'];
      final lonRaw = j['lon'];
      if (latRaw is num) {
        lat = latRaw.toDouble();
      } else if (latRaw is String && latRaw.isNotEmpty) {
        lat = double.tryParse(latRaw);
      }
      if (lonRaw is num) {
        lon = lonRaw.toDouble();
      } else if (lonRaw is String && lonRaw.isNotEmpty) {
        lon = double.tryParse(lonRaw);
      }
      final contactIdRaw = j['contact_id'] ?? j['contactId'];
      final contactId = (contactIdRaw ?? '').toString().trim();
      final contactNameRaw = j['contact_name'] ?? j['contactName'];
      final contactName = (contactNameRaw ?? '').toString().trim();
      return ChatGroupMessage(
        id: m.id,
        groupId: m.groupId,
        senderId: m.senderId,
        text: text,
        kind: kindRaw.isEmpty ? null : kindRaw,
        nonceB64: m.nonceB64,
        boxB64: m.boxB64,
        attachmentB64: attB64.isEmpty ? null : attB64,
        attachmentMime: attMime.isEmpty ? null : attMime,
        voiceSecs: voiceSecs,
        lat: lat,
        lon: lon,
        contactId: contactId.isEmpty ? null : contactId,
        contactName: contactName.isEmpty ? null : contactName,
        createdAt: m.createdAt,
        expireAt: m.expireAt,
      );
    }
  } catch (_) {}
  // Decryption failed: keep only the ciphertext envelope to avoid showing any
  // accidental plaintext fields.
  return ChatGroupMessage(
    id: m.id,
    groupId: m.groupId,
    senderId: m.senderId,
    text: '',
    kind: 'sealed',
    nonceB64: m.nonceB64,
    boxB64: m.boxB64,
    createdAt: m.createdAt,
    expireAt: m.expireAt,
  );
}

@visibleForTesting
bool shamellAcceptDirectInboxEnvelope(Map<String, Object?> map) {
  // Fail closed: direct-chat envelopes must remain on the strict v2 sealed path.
  final protocol = (map['protocol_version'] ?? '').toString().trim();
  if (protocol != shamellChatProtocolSendVersion) return false;
  final sealedRaw = map['sealed_sender'];
  final sealed = sealedRaw is bool
      ? sealedRaw
      : sealedRaw != null &&
          sealedRaw.toString().trim().toLowerCase() == 'true';
  if (!sealed) return false;
  final nonceB64 = (map['nonce_b64'] ?? '').toString().trim();
  final boxB64 = (map['box_b64'] ?? '').toString().trim();
  if (nonceB64.isEmpty || boxB64.isEmpty) return false;
  return true;
}

@visibleForTesting
bool shamellAcceptPeerKeyBundle(ChatKeyBundle bundle) {
  // Fail closed: peer bundle must advertise strict v2-only semantics.
  if (bundle.deviceId.trim().isEmpty) return false;
  if (bundle.protocolFloor.trim() != shamellChatProtocolSendVersion) {
    return false;
  }
  if (!bundle.supportsV2 || !bundle.v2Only) return false;
  if (bundle.identityKeyB64.trim().isEmpty) return false;
  if (bundle.identitySigningPubkeyB64 == null ||
      bundle.identitySigningPubkeyB64!.trim().isEmpty) {
    return false;
  }
  if (bundle.signedPrekeyId <= 0) return false;
  if (bundle.signedPrekeyB64.trim().isEmpty) return false;
  if (bundle.signedPrekeySigB64.trim().isEmpty) return false;
  return true;
}

class ChatService {
  ChatService(String baseUrl, {http.Client? httpClient})
      : _base = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _http = httpClient ?? http.Client();

  final String _base;
  final http.Client _http;
  WebSocketChannel? _ws;
  WebSocketChannel? _wsGroups;

  List<ChatMessage> _parseDirectInboxMessages(List raw) {
    final out = <ChatMessage>[];
    for (final item in raw) {
      Map<String, Object?>? messageMap;
      if (item is Map<String, Object?>) {
        messageMap = item;
      } else if (item is Map) {
        messageMap = item.cast<String, Object?>();
      }
      if (messageMap == null) continue;
      if (!shamellAcceptDirectInboxEnvelope(messageMap)) {
        continue;
      }
      try {
        out.add(ChatMessage.fromJson(messageMap));
      } catch (_) {}
    }
    return out;
  }

  bool _isLocalhostHost(String host) {
    final h = host.trim().toLowerCase();
    return h == 'localhost' || h == '127.0.0.1' || h == '::1';
  }

  void _assertSecureTransportBase() {
    // Best practice: never send auth tokens over plaintext transports.
    // Allow only localhost dev on http/ws.
    final u = Uri.tryParse(_base);
    if (u == null) {
      throw StateError('Invalid chat base URL');
    }
    final scheme = u.scheme.toLowerCase();
    final host = u.host.toLowerCase();
    if (scheme == 'https') return;
    if (scheme == 'http' && _isLocalhostHost(host)) return;
    throw StateError('Insecure chat base URL: HTTPS is required');
  }

  Future<ChatContact> registerDevice(ChatIdentity me) async {
    final clientDeviceId = (await getOrCreateStableDeviceId()).trim();
    final body = jsonEncode({
      'device_id': me.id,
      if (clientDeviceId.isNotEmpty) 'client_device_id': clientDeviceId,
      'public_key_b64': me.publicKeyB64,
      'name': me.displayName,
    });
    final r = await _http.post(
      _uri('/chat/devices/register'),
      headers: await _headers(json: true, chatDeviceId: me.id),
      body: body,
    );
    if (r.statusCode >= 400) {
      throw Exception('register failed: ${r.statusCode}');
    }
    final j = jsonDecode(r.body) as Map<String, Object?>;
    final authToken = (j['auth_token'] ?? '').toString().trim();
    if (authToken.isNotEmpty) {
      await ChatLocalStore().saveDeviceAuthToken(me.id, authToken);
    }
    await _bootstrapLibsignalMaterial(me);
    return ChatContact(
      id: (j['device_id'] ?? '') as String,
      publicKeyB64: (j['public_key_b64'] ?? '') as String,
      fingerprint: fingerprintForKey((j['public_key_b64'] ?? '') as String),
      name: j['name'] as String?,
      verified: false,
    );
  }

  Future<ChatContact> resolveDevice(String id) async {
    final r = await _http.get(
      _uri('/chat/devices/${Uri.encodeComponent(id)}'),
      headers: await _headers(),
    );
    if (r.statusCode >= 400) {
      throw Exception('device not found (${r.statusCode})');
    }
    final j = jsonDecode(r.body) as Map<String, Object?>;
    final pk = (j['public_key_b64'] ?? '') as String;
    return ChatContact(
      id: (j['device_id'] ?? id) as String,
      publicKeyB64: pk,
      fingerprint: fingerprintForKey(pk),
      name: j['name'] as String?,
      verified: false,
    );
  }

  Future<void> _requireSessionCookieForAccountOps() async {
    final cookie = (await getSessionCookieHeader(_base) ?? '').trim();
    if (cookie.isEmpty) {
      throw StateError('Authentication required');
    }
  }

  Future<ChatIdentity> _ensureChatIdentityAndRegistrationForAccountOps() async {
    final store = ChatLocalStore();
    var me = await store.loadIdentity();
    if (me == null ||
        me.id.trim().isEmpty ||
        me.publicKeyB64.trim().isEmpty ||
        me.privateKeyB64.trim().isEmpty) {
      final sk = x25519.PrivateKey.generate();
      final pk = sk.publicKey;
      final pkB64 = base64Encode(pk.asTypedList);
      me = ChatIdentity(
        id: generateShortId(),
        publicKeyB64: pkB64,
        privateKeyB64: base64Encode(sk.asTypedList),
        fingerprint: fingerprintForKey(pkB64),
      );
      await store.saveIdentity(me);
    }

    final tok = (await store.loadDeviceAuthToken(me.id) ?? '').trim();
    if (tok.isEmpty) {
      // This binds the chat device to the authenticated Shamell account in the backend.
      await registerDevice(me);
    } else {
      // Best-effort: ensure key material exists for upgraded clients without re-registering.
      await _bootstrapLibsignalMaterial(me);
    }

    return me;
  }

  Future<String> createContactInviteToken({int maxUses = 1}) async {
    await _requireSessionCookieForAccountOps();
    final me = await _ensureChatIdentityAndRegistrationForAccountOps();
    final requested = maxUses.clamp(1, 20);
    final r = await _http.post(
      _uri('/contacts/invites'),
      headers: await _headers(json: true, chatDeviceId: me.id),
      body: jsonEncode(<String, Object?>{'max_uses': requested}),
    );
    if (r.statusCode >= 400) {
      throw Exception('invite create failed: ${r.statusCode}');
    }
    final j = jsonDecode(r.body);
    if (j is! Map) {
      throw Exception('invite create failed');
    }
    final tok = (j['token'] ?? '').toString().trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(tok)) {
      throw Exception('invite create failed');
    }
    return tok;
  }

  Future<String> redeemContactInviteToken(String rawToken) async {
    final tok = rawToken.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(tok)) {
      throw Exception('invalid invite token');
    }
    await _requireSessionCookieForAccountOps();
    final me = await _ensureChatIdentityAndRegistrationForAccountOps();
    final r = await _http.post(
      _uri('/contacts/invites/redeem'),
      headers: await _headers(json: true, chatDeviceId: me.id),
      body: jsonEncode(<String, Object?>{'token': tok}),
    );
    if (r.statusCode >= 400) {
      throw Exception('invite redeem failed: ${r.statusCode}');
    }
    final j = jsonDecode(r.body);
    if (j is! Map) {
      throw Exception('invite redeem failed');
    }
    final did = (j['device_id'] ?? '').toString().trim();
    if (did.isEmpty) {
      throw Exception('invite redeem failed');
    }
    return did;
  }

  /// Fetches a peer key bundle from the server.
  /// Note: this may consume one-time prekeys server-side; call only when establishing a new session.
  Future<ChatKeyBundle> fetchKeyBundle({
    required String targetDeviceId,
    String? requesterDeviceId,
  }) async {
    final did = targetDeviceId.trim();
    if (did.isEmpty) {
      throw ArgumentError.value(targetDeviceId, 'targetDeviceId');
    }
    final r = await _http.get(
      _uri('/chat/keys/bundle/${Uri.encodeComponent(did)}'),
      headers: await _headers(chatDeviceId: requesterDeviceId),
    );
    if (r.statusCode >= 400) {
      throw Exception('key bundle fetch failed: ${r.statusCode}');
    }
    final bundle =
        ChatKeyBundle.fromJson(jsonDecode(r.body) as Map<String, Object?>);
    if (!shamellAcceptPeerKeyBundle(bundle)) {
      throw StateError('insecure key bundle rejected');
    }
    return bundle;
  }

  Future<void> registerLibsignalBundle({
    required ChatIdentity me,
    bool? v2Only,
    int oneTimePrekeyCount = shamellLibsignalPrekeyBatchDefault,
  }) async {
    final signedPrekey = x25519.PrivateKey.generate().publicKey;
    final signedPrekeyB64 = base64Encode(signedPrekey.asTypedList);
    final signedPrekeyId = DateTime.now().millisecondsSinceEpoch;
    final signatureInput = _keyRegisterSignatureInput(
      deviceId: me.id,
      identityKeyB64: me.publicKeyB64,
      signedPrekeyId: signedPrekeyId,
      signedPrekeyB64: signedPrekeyB64,
    );
    final keyRegistrationSignature = _signKeyRegisterInput(
      identityPrivateKeyB64: me.privateKeyB64,
      input: signatureInput,
    );
    final r = await _http.post(
      _uri('/chat/keys/register'),
      headers: await _headers(json: true, chatDeviceId: me.id),
      body: jsonEncode({
        'device_id': me.id,
        'identity_key_b64': me.publicKeyB64,
        'identity_signing_pubkey_b64':
            keyRegistrationSignature.identitySigningPubkeyB64,
        'signed_prekey_id': signedPrekeyId,
        'signed_prekey_b64': signedPrekeyB64,
        'signed_prekey_sig_b64': keyRegistrationSignature.signatureB64,
        'signed_prekey_sig_alg': 'ed25519',
        'v2_only': v2Only ?? _enableLibsignalV2Only(),
      }),
    );
    if (r.statusCode >= 400) {
      throw Exception('keys register failed: ${r.statusCode}');
    }

    final prekeys = _buildOneTimePrekeys(oneTimePrekeyCount);
    if (prekeys.isEmpty) return;
    final upload = await _http.post(
      _uri('/chat/keys/prekeys/upload'),
      headers: await _headers(json: true, chatDeviceId: me.id),
      body: jsonEncode({
        'device_id': me.id,
        'prekeys': prekeys.map((p) => p.toJson()).toList(),
      }),
    );
    if (upload.statusCode >= 400) {
      throw Exception('prekeys upload failed: ${upload.statusCode}');
    }
  }

  Future<ChatMessage> sendMessage({
    required ChatIdentity me,
    required ChatContact peer,
    required String plainText,
    int? expireAfterSeconds,
    bool sealedSender = true,
    String? senderHint,
    Uint8List? sessionKey,
    int? keyId,
    int? prevKeyId,
    String? senderDhPubB64,
  }) async {
    final hint = sealedSender
        ? ((senderHint ?? '').trim().isNotEmpty
            ? senderHint!.trim()
            : me.fingerprint.trim())
        : '';
    final enc = _encryptMessage(
      me,
      peer,
      plainText,
      sealed: sealedSender,
      sessionKey: sessionKey,
    );
    final body = jsonEncode({
      'sender_id': me.id,
      'recipient_id': peer.id,
      'protocol_version': _messageProtocolVersion(),
      'sender_pubkey_b64': me.publicKeyB64,
      if (senderDhPubB64 != null) 'sender_dh_pub_b64': senderDhPubB64,
      'nonce_b64': enc.$1,
      'box_b64': enc.$2,
      'sealed_sender': sealedSender,
      if (sealedSender && hint.isNotEmpty) 'sender_hint': hint,
      if (sealedSender && hint.isNotEmpty) 'sender_fingerprint': hint,
      if (keyId != null) 'key_id': keyId.toString(),
      if (prevKeyId != null) 'prev_key_id': prevKeyId.toString(),
      if (expireAfterSeconds != null)
        'expire_after_seconds': expireAfterSeconds,
    });
    final r = await _http.post(
      _uri('/chat/messages/send'),
      headers: await _headers(json: true, chatDeviceId: me.id),
      body: body,
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw ChatHttpException(
          op: 'send', statusCode: r.statusCode, body: r.body);
    }
    final parsed = ChatMessage.fromJson(
      jsonDecode(r.body) as Map<String, Object?>,
    );
    if (parsed.createdAt != null) return parsed;
    return ChatMessage(
      id: parsed.id,
      senderId: parsed.senderId,
      recipientId: parsed.recipientId,
      senderPubKeyB64: parsed.senderPubKeyB64,
      nonceB64: parsed.nonceB64,
      boxB64: parsed.boxB64,
      createdAt: DateTime.now(),
    );
  }

  Future<List<ChatMessage>> fetchInbox({
    required String deviceId,
    int limit = 50,
    String? sinceIso,
  }) async {
    final qp = <String, String>{'device_id': deviceId, 'limit': '$limit'};
    if (sinceIso != null && sinceIso.isNotEmpty) {
      qp['since_iso'] = sinceIso;
    }
    final r = await _http.get(
      _uri('/chat/messages/inbox', qp),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw Exception('inbox failed: ${r.statusCode}');
    }
    final arr = jsonDecode(r.body) as List;
    return _parseDirectInboxMessages(arr);
  }

  Future<void> markRead(String id, {String? deviceId}) async {
    await _http.post(
      _uri('/chat/messages/$id/read'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode({'read': true}),
    );
  }

  Future<void> setBlock({
    required String deviceId,
    required String peerId,
    required bool blocked,
    bool hidden = false,
  }) async {
    await _http.post(
      _uri('/chat/devices/${Uri.encodeComponent(deviceId)}/block'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode({
        'peer_id': peerId,
        'blocked': blocked,
        'hidden': hidden,
      }),
    );
  }

  Future<void> setHidden({
    required String deviceId,
    required String peerId,
    required bool hidden,
  }) async {
    await setBlock(
      deviceId: deviceId,
      peerId: peerId,
      blocked: false,
      hidden: hidden,
    );
  }

  Future<void> setPrefs({
    required String deviceId,
    required String peerId,
    bool? muted,
    bool? starred,
    bool? pinned,
  }) async {
    final body = <String, Object?>{'peer_id': peerId};
    if (muted != null) body['muted'] = muted;
    if (starred != null) body['starred'] = starred;
    if (pinned != null) body['pinned'] = pinned;
    await _http.post(
      _uri('/chat/devices/${Uri.encodeComponent(deviceId)}/prefs'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode(body),
    );
  }

  Future<List<ChatContactPrefs>> fetchPrefs({required String deviceId}) async {
    final r = await _http.get(
      _uri('/chat/devices/${Uri.encodeComponent(deviceId)}/prefs'),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw Exception('prefs failed: ${r.statusCode}');
    }
    final decoded = jsonDecode(r.body);
    final list = <ChatContactPrefs>[];
    if (decoded is Map && decoded['prefs'] is List) {
      for (final e in decoded['prefs'] as List) {
        if (e is Map<String, Object?>) {
          list.add(ChatContactPrefs.fromJson(e));
        } else if (e is Map) {
          list.add(ChatContactPrefs.fromJson(e.cast<String, Object?>()));
        }
      }
    }
    return list;
  }

  Future<void> setGroupPrefs({
    required String deviceId,
    required String groupId,
    bool? muted,
    bool? pinned,
  }) async {
    final body = <String, Object?>{'group_id': groupId};
    if (muted != null) body['muted'] = muted;
    if (pinned != null) body['pinned'] = pinned;
    await _http.post(
      _uri('/chat/devices/${Uri.encodeComponent(deviceId)}/group_prefs'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode(body),
    );
  }

  Future<List<ChatGroupPrefs>> fetchGroupPrefs({
    required String deviceId,
  }) async {
    final r = await _http.get(
      _uri('/chat/devices/${Uri.encodeComponent(deviceId)}/group_prefs'),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw Exception('group prefs failed: ${r.statusCode}');
    }
    final decoded = jsonDecode(r.body);
    final list = <ChatGroupPrefs>[];
    if (decoded is List) {
      for (final e in decoded) {
        if (e is Map<String, Object?>) {
          list.add(ChatGroupPrefs.fromJson(e));
        } else if (e is Map) {
          list.add(ChatGroupPrefs.fromJson(e.cast<String, Object?>()));
        }
      }
    }
    return list;
  }

  Future<void> registerPushToken({
    required String deviceId,
    required String token,
    String? platform,
  }) async {
    try {
      await _http.post(
        _uri('/chat/devices/${Uri.encodeComponent(deviceId)}/push_token'),
        headers: await _headers(json: true, chatDeviceId: deviceId),
        body: jsonEncode({
          'token': token,
          'platform': platform ?? 'flutter',
          'ts': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    } catch (_) {
      // Endpoint may not exist yet; ignore failures for now.
    }
  }

  Stream<List<ChatMessage>> streamInbox({required String deviceId}) {
    _ws?.sink.close();
    final out = StreamController<List<ChatMessage>>();
    Future<void>(() async {
      try {
        _assertSecureTransportBase();
        final u = Uri.parse(_base);
        final wsUri = Uri(
          scheme: u.scheme == 'https' ? 'wss' : 'ws',
          host: u.host,
          port: u.hasPort ? u.port : null,
          path: '/ws/chat/inbox',
          queryParameters: {'device_id': deviceId},
        );
        final auth = await _chatAuthContext(chatDeviceId: deviceId);
        final headers = <String, String>{};
        if (auth.deviceId != null && auth.deviceId!.isNotEmpty) {
          headers['X-Chat-Device-Id'] = auth.deviceId!;
        }
        if (auth.token != null && auth.token!.isNotEmpty) {
          headers['X-Chat-Device-Token'] = auth.token!;
        }
        final channel = _connectWebSocket(
          wsUri,
          headers: headers,
        );
        _ws = channel;
        late final StreamSubscription sub;
        sub = channel.stream.listen(
          (payload) {
            try {
              final j = jsonDecode(payload);
              if (j is Map && j['type'] == 'inbox' && j['messages'] is List) {
                final msgs = _parseDirectInboxMessages(j['messages'] as List);
                out.add(msgs);
                return;
              }
            } catch (_) {}
            out.add(<ChatMessage>[]);
          },
          onError: out.addError,
          onDone: () async {
            await out.close();
          },
          cancelOnError: false,
        );
        out.onCancel = () async {
          await sub.cancel();
          channel.sink.close();
          if (identical(_ws, channel)) {
            _ws = null;
          }
        };
      } catch (e, st) {
        out.addError(e, st);
        await out.close();
      }
    });
    return out.stream;
  }

  Stream<ChatGroupInboxUpdate> streamGroupInbox({required String deviceId}) {
    _wsGroups?.sink.close();
    final out = StreamController<ChatGroupInboxUpdate>();
    final store = ChatLocalStore();
    Future<void>(() async {
      try {
        _assertSecureTransportBase();
        final u = Uri.parse(_base);
        final wsUri = Uri(
          scheme: u.scheme == 'https' ? 'wss' : 'ws',
          host: u.host,
          port: u.hasPort ? u.port : null,
          path: '/ws/chat/groups',
          queryParameters: {'device_id': deviceId},
        );
        final auth = await _chatAuthContext(chatDeviceId: deviceId);
        final headers = <String, String>{};
        if (auth.deviceId != null && auth.deviceId!.isNotEmpty) {
          headers['X-Chat-Device-Id'] = auth.deviceId!;
        }
        if (auth.token != null && auth.token!.isNotEmpty) {
          headers['X-Chat-Device-Token'] = auth.token!;
        }
        final channel = _connectWebSocket(
          wsUri,
          headers: headers,
        );
        _wsGroups = channel;
        late final StreamSubscription sub;
        sub = channel.stream.listen(
          (payload) async {
            try {
              final j = jsonDecode(payload);
              if (j is Map &&
                  j['type'] == 'group_inbox' &&
                  j['group_id'] is String &&
                  j['messages'] is List) {
                final gid = (j['group_id'] as String).trim();
                var msgs = (j['messages'] as List)
                    .whereType<Map>()
                    .map(
                      (m) =>
                          ChatGroupMessage.fromJson(m.cast<String, Object?>()),
                    )
                    .toList();
                try {
                  final keyB64 = await store.loadGroupKey(gid);
                  if (keyB64 != null && keyB64.isNotEmpty) {
                    final key = base64Decode(keyB64);
                    if (key.length == 32) {
                      msgs = msgs
                          .map((m) => _maybeDecryptGroupMessage(m, key))
                          .toList();
                    }
                  }
                } catch (_) {}
                if (gid.isNotEmpty && msgs.isNotEmpty) {
                  out.add(ChatGroupInboxUpdate(groupId: gid, messages: msgs));
                }
              }
            } catch (_) {}
          },
          onError: out.addError,
          onDone: () async {
            await out.close();
          },
          cancelOnError: false,
        );
        out.onCancel = () async {
          await sub.cancel();
          channel.sink.close();
          if (identical(_wsGroups, channel)) {
            _wsGroups = null;
          }
        };
      } catch (e, st) {
        out.addError(e, st);
        await out.close();
      }
    });
    return out.stream;
  }

  Future<ChatGroup> createGroup({
    required String deviceId,
    required String name,
    List<String> memberIds = const <String>[],
    String? groupId,
  }) async {
    final body = jsonEncode({
      'device_id': deviceId,
      'name': name,
      if (memberIds.isNotEmpty) 'member_ids': memberIds,
      if (groupId != null && groupId.isNotEmpty) 'group_id': groupId,
    });
    final r = await _http.post(
      _uri('/chat/groups/create'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: body,
    );
    if (r.statusCode >= 400) {
      throw Exception('group create failed: ${r.statusCode}');
    }
    return ChatGroup.fromJson(jsonDecode(r.body) as Map<String, Object?>);
  }

  Future<List<ChatGroup>> listGroups({required String deviceId}) async {
    final r = await _http.get(
      _uri('/chat/groups/list', {'device_id': deviceId}),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw Exception('groups list failed: ${r.statusCode}');
    }
    final arr = jsonDecode(r.body) as List;
    return arr
        .whereType<Map>()
        .map((m) => ChatGroup.fromJson(m.cast<String, Object?>()))
        .toList();
  }

  Future<ChatGroup> updateGroup({
    required String groupId,
    required String actorId,
    String? name,
    String? avatarB64,
    String? avatarMime,
  }) async {
    final body = jsonEncode({
      'actor_id': actorId,
      if (name != null) 'name': name,
      if (avatarB64 != null) 'avatar_b64': avatarB64,
      if (avatarMime != null) 'avatar_mime': avatarMime,
    });
    final r = await _http.post(
      _uri('/chat/groups/${Uri.encodeComponent(groupId)}/update'),
      headers: await _headers(json: true, chatDeviceId: actorId),
      body: body,
    );
    if (r.statusCode >= 400) {
      throw Exception('group update failed: ${r.statusCode}');
    }
    return ChatGroup.fromJson(jsonDecode(r.body) as Map<String, Object?>);
  }

  Future<ChatGroupMessage> sendGroupMessage({
    required String groupId,
    required String senderId,
    String text = '',
    String? kind,
    String? attachmentB64,
    String? attachmentMime,
    int? voiceSecs,
    int? expireAfterSeconds,
    double? lat,
    double? lon,
    String? contactId,
    String? contactName,
  }) async {
    final payload = <String, Object?>{
      'text': text,
      if (kind != null && kind.isNotEmpty) 'kind': kind,
      if (attachmentB64 != null && attachmentB64.isNotEmpty)
        'attachment_b64': attachmentB64,
      if (attachmentMime != null && attachmentMime.isNotEmpty)
        'attachment_mime': attachmentMime,
      if (voiceSecs != null) 'voice_secs': voiceSecs,
      if (lat != null) 'lat': lat,
      if (lon != null) 'lon': lon,
      if (contactId != null && contactId.isNotEmpty) 'contact_id': contactId,
      if (contactName != null && contactName.isNotEmpty)
        'contact_name': contactName,
    };

    final bodyMap = <String, Object?>{
      'sender_id': senderId,
      'protocol_version': _messageProtocolVersion(),
      if (expireAfterSeconds != null)
        'expire_after_seconds': expireAfterSeconds,
    };

    final keyB64 = await ChatLocalStore().loadGroupKey(groupId);
    if (keyB64 == null || keyB64.isEmpty) {
      throw StateError('group encryption key missing');
    }
    final keyBytes = base64Decode(keyB64);
    if (keyBytes.length != 32) {
      throw StateError('group encryption key invalid');
    }
    final rnd = Random.secure();
    final nonce = Uint8List.fromList(
      List<int>.generate(24, (_) => rnd.nextInt(256)),
    );
    final box = x25519.SecretBox(Uint8List.fromList(keyBytes)).encrypt(
      Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      nonce: nonce,
    );
    bodyMap['kind'] = 'sealed';
    bodyMap['nonce_b64'] = base64Encode(box.nonce.asTypedList);
    bodyMap['box_b64'] = base64Encode(box.cipherText.asTypedList);

    final body = jsonEncode(bodyMap);
    final r = await _http.post(
      _uri('/chat/groups/${Uri.encodeComponent(groupId)}/messages/send'),
      headers: await _headers(json: true, chatDeviceId: senderId),
      body: body,
    );
    if (r.statusCode >= 400) {
      throw Exception('group send failed: ${r.statusCode}');
    }
    return ChatGroupMessage.fromJson(
      jsonDecode(r.body) as Map<String, Object?>,
    );
  }

  Future<List<ChatGroupMessage>> fetchGroupInbox({
    required String groupId,
    required String deviceId,
    int limit = 50,
    String? sinceIso,
  }) async {
    final qp = <String, String>{'device_id': deviceId, 'limit': '$limit'};
    if (sinceIso != null && sinceIso.isNotEmpty) {
      qp['since_iso'] = sinceIso;
    }
    final r = await _http.get(
      _uri('/chat/groups/${Uri.encodeComponent(groupId)}/messages/inbox', qp),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw Exception('group inbox failed: ${r.statusCode}');
    }
    final arr = jsonDecode(r.body) as List;
    var msgs = arr
        .whereType<Map>()
        .map((m) => ChatGroupMessage.fromJson(m.cast<String, Object?>()))
        .toList();
    try {
      final keyB64 = await ChatLocalStore().loadGroupKey(groupId);
      if (keyB64 != null && keyB64.isNotEmpty) {
        final key = base64Decode(keyB64);
        if (key.length == 32) {
          msgs = msgs.map((m) => _maybeDecryptGroupMessage(m, key)).toList();
        }
      }
    } catch (_) {}
    return msgs;
  }

  Future<List<ChatGroupMember>> listGroupMembers({
    required String groupId,
    required String deviceId,
  }) async {
    final r = await _http.get(
      _uri('/chat/groups/${Uri.encodeComponent(groupId)}/members', {
        'device_id': deviceId,
      }),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw Exception('group members failed: ${r.statusCode}');
    }
    final arr = jsonDecode(r.body) as List;
    return arr
        .whereType<Map>()
        .map((m) => ChatGroupMember.fromJson(m.cast<String, Object?>()))
        .toList();
  }

  Future<ChatGroup> inviteGroupMembers({
    required String groupId,
    required String inviterId,
    required List<String> memberIds,
  }) async {
    final body = jsonEncode({'inviter_id': inviterId, 'member_ids': memberIds});
    final r = await _http.post(
      _uri('/chat/groups/${Uri.encodeComponent(groupId)}/invite'),
      headers: await _headers(json: true, chatDeviceId: inviterId),
      body: body,
    );
    if (r.statusCode >= 400) {
      throw Exception('group invite failed: ${r.statusCode}');
    }
    return ChatGroup.fromJson(jsonDecode(r.body) as Map<String, Object?>);
  }

  Future<void> leaveGroup({
    required String groupId,
    required String deviceId,
  }) async {
    final body = jsonEncode({'device_id': deviceId});
    final r = await _http.post(
      _uri('/chat/groups/${Uri.encodeComponent(groupId)}/leave'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: body,
    );
    if (r.statusCode >= 400) {
      throw Exception('group leave failed: ${r.statusCode}');
    }
  }

  Future<void> setGroupRole({
    required String groupId,
    required String actorId,
    required String targetId,
    required String role,
  }) async {
    final body = jsonEncode({
      'actor_id': actorId,
      'target_id': targetId,
      'role': role,
    });
    final r = await _http.post(
      _uri('/chat/groups/${Uri.encodeComponent(groupId)}/set_role'),
      headers: await _headers(json: true, chatDeviceId: actorId),
      body: body,
    );
    if (r.statusCode >= 400) {
      throw Exception('group set role failed: ${r.statusCode}');
    }
  }

  Future<List<ChatGroupKeyEvent>> listGroupKeyEvents({
    required String groupId,
    required String deviceId,
    int limit = 20,
  }) async {
    final qp = <String, String>{
      'device_id': deviceId,
      'limit': '${limit.clamp(1, 200)}',
    };
    final r = await _http.get(
      _uri('/chat/groups/${Uri.encodeComponent(groupId)}/keys/events', qp),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw Exception('group key events failed: ${r.statusCode}');
    }
    final decoded = jsonDecode(r.body);
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((m) => ChatGroupKeyEvent.fromJson(m.cast<String, Object?>()))
          .toList();
    }
    return const <ChatGroupKeyEvent>[];
  }

  Future<int> rotateGroupKey({
    required String groupId,
    required String actorId,
    String? keyFp,
  }) async {
    final body = jsonEncode({
      'actor_id': actorId,
      if (keyFp != null && keyFp.isNotEmpty) 'key_fp': keyFp,
    });
    final r = await _http.post(
      _uri('/chat/groups/${Uri.encodeComponent(groupId)}/keys/rotate'),
      headers: await _headers(json: true, chatDeviceId: actorId),
      body: body,
    );
    if (r.statusCode >= 400) {
      throw Exception('group key rotate failed: ${r.statusCode}');
    }
    try {
      final j = jsonDecode(r.body) as Map<String, Object?>;
      return (j['version'] as num?)?.toInt() ??
          int.tryParse((j['version'] ?? '').toString()) ??
          0;
    } catch (_) {
      return 0;
    }
  }

  void close() {
    _ws?.sink.close();
    _ws = null;
    _wsGroups?.sink.close();
    _wsGroups = null;
  }

  // Helpers
  Future<void> _bootstrapLibsignalMaterial(ChatIdentity me) async {
    if (!_enableLibsignalKeyApi()) return;
    final store = ChatLocalStore();
    if (await store.isDeviceKeyBootstrapped(me.id)) return;
    await registerLibsignalBundle(me: me);
    await store.markDeviceKeyBootstrapped(me.id);
  }

  bool get libsignalKeyApiEnabled => _enableLibsignalKeyApi();

  bool _enableLibsignalKeyApi() {
    if (kReleaseMode) return shamellLibsignalKeyApiReleaseDefault;
    return shamellLibsignalKeyApiDebugDefault;
  }

  bool _enableLibsignalV2Only() {
    if (kReleaseMode) return shamellLibsignalV2OnlyReleaseDefault;
    return shamellLibsignalV2OnlyDebugDefault;
  }

  String _messageProtocolVersion() {
    // Enforced: no legacy protocol fallback (break old clients rather than downgrading).
    return shamellChatProtocolSendVersion;
  }

  String _keyRegisterSignatureInput({
    required String deviceId,
    required String identityKeyB64,
    required int signedPrekeyId,
    required String signedPrekeyB64,
  }) {
    return 'shamell-key-register-v1\n'
        '${deviceId.trim()}\n'
        '${identityKeyB64.trim()}\n'
        '$signedPrekeyId\n'
        '${signedPrekeyB64.trim()}\n';
  }

  Uint8List _deriveKeyRegisterSigningSeed({
    required String identityPrivateKeyB64,
  }) {
    final keyBytes = base64Decode(identityPrivateKeyB64);
    final context = utf8.encode('shamell-key-register-sign-seed-v1');
    final digest = crypto.sha256.convert(<int>[...context, ...keyBytes]).bytes;
    return Uint8List.fromList(digest);
  }

  ({String signatureB64, String identitySigningPubkeyB64})
      _signKeyRegisterInput({
    required String identityPrivateKeyB64,
    required String input,
  }) {
    final seed = _deriveKeyRegisterSigningSeed(
      identityPrivateKeyB64: identityPrivateKeyB64,
    );
    final signingKey = ed25519.SigningKey(seed: seed);
    final signed = signingKey.sign(Uint8List.fromList(utf8.encode(input)));
    return (
      signatureB64: base64Encode(signed.signature.asTypedList),
      identitySigningPubkeyB64: base64Encode(signingKey.verifyKey.asTypedList),
    );
  }

  List<ChatOneTimePrekey> _buildOneTimePrekeys(int requested) {
    final count = requested.clamp(1, 500);
    final baseKeyId = DateTime.now().microsecondsSinceEpoch;
    return List<ChatOneTimePrekey>.generate(count, (i) {
      final keyId = baseKeyId + i;
      final keyB64 = base64Encode(
        x25519.PrivateKey.generate().publicKey.asTypedList,
      );
      return ChatOneTimePrekey(keyId: keyId, keyB64: keyB64);
    });
  }

  ChatGroupMessage _maybeDecryptGroupMessage(
    ChatGroupMessage m,
    Uint8List key,
  ) {
    return shamellDecryptOrBlockGroupMessage(m, key);
  }

  (String, String) _encryptMessage(
    ChatIdentity me,
    ChatContact peer,
    String plain, {
    bool sealed = false,
    Uint8List? sessionKey,
  }) {
    final rnd = Random.secure();
    final nonce = Uint8List.fromList(
      List<int>.generate(24, (_) => rnd.nextInt(256)),
    );
    if (sealed && sessionKey != null) {
      final box = x25519.SecretBox(sessionKey);
      final cipher = box.encrypt(
        Uint8List.fromList(utf8.encode(plain)),
        nonce: nonce,
      );
      return (
        base64Encode(cipher.nonce.asTypedList),
        base64Encode(cipher.cipherText.asTypedList),
      );
    }
    final sk = x25519.PrivateKey(base64Decode(me.privateKeyB64));
    final pkPeer = x25519.PublicKey(base64Decode(peer.publicKeyB64));
    final box = x25519.Box(
      myPrivateKey: sk,
      theirPublicKey: pkPeer,
    ).encrypt(Uint8List.fromList(utf8.encode(plain)), nonce: nonce);
    return (
      base64Encode(box.nonce.asTypedList),
      base64Encode(box.cipherText.asTypedList),
    );
  }

  Future<({String? deviceId, String? token})> _chatAuthContext({
    String? chatDeviceId,
    String? chatDeviceToken,
  }) async {
    String? did = chatDeviceId?.trim();
    if (did == null || did.isEmpty) {
      final id = await ChatLocalStore().loadIdentity();
      final candidate = id?.id.trim() ?? '';
      if (candidate.isNotEmpty) {
        did = candidate;
      }
    }
    String? tok = chatDeviceToken?.trim();
    if ((tok == null || tok.isEmpty) && did != null && did.isNotEmpty) {
      tok = (await ChatLocalStore().loadDeviceAuthToken(did))?.trim();
    }
    if (did != null && did.isEmpty) did = null;
    if (tok != null && tok.isEmpty) tok = null;
    return (deviceId: did, token: tok);
  }

  WebSocketChannel _connectWebSocket(
    Uri wsUri, {
    required Map<String, String> headers,
  }) {
    if (headers.isNotEmpty) {
      try {
        final dynamic connector = WebSocketChannel.connect;
        final dynamic ch = Function.apply(
          connector,
          <Object?>[wsUri],
          <Symbol, Object?>{#headers: headers},
        );
        if (ch is WebSocketChannel) {
          return ch;
        }
      } catch (_) {}
    }
    // Fail closed: never fall back to putting authentication material into the URL.
    return WebSocketChannel.connect(wsUri);
  }

  Future<Map<String, String>> _headers({
    bool json = false,
    String? chatDeviceId,
    String? chatDeviceToken,
  }) async {
    _assertSecureTransportBase();
    final h = <String, String>{};
    if (json) h['content-type'] = 'application/json';
    final cookie = await getSessionCookieHeader(_base);
    if (cookie != null && cookie.isNotEmpty) h['cookie'] = cookie;
    final auth = await _chatAuthContext(
      chatDeviceId: chatDeviceId,
      chatDeviceToken: chatDeviceToken,
    );
    if (auth.deviceId != null && auth.deviceId!.isNotEmpty) {
      h['X-Chat-Device-Id'] = auth.deviceId!;
    }
    if (auth.token != null && auth.token!.isNotEmpty) {
      h['X-Chat-Device-Token'] = auth.token!;
    }
    return h;
  }

  Uri _uri(String path, [Map<String, String>? qp]) {
    final base = _base;
    final prefix =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final full = '$prefix$path';
    return Uri.parse(full).replace(queryParameters: qp);
  }
}

class ChatLocalStore {
  static const _idKey = 'chat.identity';
  static const _peerKey = 'chat.peer';
  static const _contactsKey = 'chat.contacts';
  static const _unreadKey = 'chat.unread';
  static const _activePeerKey = 'chat.active';
  static const _officialNotifKey = 'official.notif';
  static const _groupSeenKey = 'chat.grp.seen';
  static const _groupNamesKey = 'chat.grp.names';
  static const _voicePlayedPrefix = 'chat.voice.played.';
  static const _groupVoicePlayedPrefix = 'chat.grp.voice.played.';
  static const _draftsKey = 'chat.drafts.v1';
  static const _deviceTokenPrefix = 'chat.device.token.';
  static const _deviceKeyBootstrapPrefix = 'chat.device.keys.bootstrapped.';
  static const int _voicePlayedMax = 200;

  Future<ChatIdentity?> loadIdentity() async {
    String? raw = await _secureRead(_idKey);
    if (raw == null || raw.isEmpty) {
      try {
        final sp = await SharedPreferences.getInstance();
        final legacy = sp.getString(_idKey);
        if (legacy != null && legacy.isNotEmpty) {
          raw = legacy;
          await _secureWrite(_idKey, legacy);
        }
      } catch (_) {}
    }
    if (raw == null || raw.isEmpty) return null;
    try {
      return ChatIdentity.fromMap((jsonDecode(raw) as Map<String, Object?>));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveIdentity(ChatIdentity id) async {
    await _secureWrite(_idKey, jsonEncode(id.toMap()));
  }

  Future<void> saveDeviceAuthToken(String deviceId, String token) async {
    final did = deviceId.trim();
    final tok = token.trim();
    if (did.isEmpty || tok.isEmpty) return;
    await _secureWrite('$_deviceTokenPrefix$did', tok);
  }

  Future<String?> loadDeviceAuthToken(String deviceId) async {
    final did = deviceId.trim();
    if (did.isEmpty) return null;
    final value = await _secureRead('$_deviceTokenPrefix$did');
    final token = (value ?? '').trim();
    if (token.isEmpty) return null;
    return token;
  }

  Future<bool> isDeviceKeyBootstrapped(String deviceId) async {
    final did = deviceId.trim();
    if (did.isEmpty) return false;
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.getBool('$_deviceKeyBootstrapPrefix$did') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> markDeviceKeyBootstrapped(String deviceId) async {
    final did = deviceId.trim();
    if (did.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('$_deviceKeyBootstrapPrefix$did', true);
    } catch (_) {}
  }

  Future<void> clearDeviceKeyBootstrapped(String deviceId) async {
    final did = deviceId.trim();
    if (did.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove('$_deviceKeyBootstrapPrefix$did');
    } catch (_) {}
  }

  Future<void> deleteDeviceAuthToken(String deviceId) async {
    final did = deviceId.trim();
    if (did.isEmpty) return;
    await _secureDelete('$_deviceTokenPrefix$did');
    await clearDeviceKeyBootstrapped(did);
  }

  Future<ChatContact?> loadPeer() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_peerKey);
    if (raw == null) return null;
    final decodedRaw = (await _decryptSensitivePrefsString(raw)) ?? raw;
    try {
      final out =
          ChatContact.fromMap((jsonDecode(decodedRaw) as Map<String, Object?>));
      // Best-effort migration: encrypt legacy plaintext.
      if (decodedRaw == raw) {
        final enc = await _encryptSensitivePrefsString(decodedRaw);
        if (enc != null && enc.isNotEmpty) {
          await sp.setString(_peerKey, enc);
        }
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  Future<void> savePeer(ChatContact c) async {
    final sp = await SharedPreferences.getInstance();
    final raw = jsonEncode(c.toMap());
    final enc = await _encryptSensitivePrefsString(raw);
    if (enc == null || enc.isEmpty) {
      return;
    }
    await sp.setString(_peerKey, enc);
  }

  Future<void> clearPeer() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_peerKey);
  }

  Future<List<ChatContact>> loadContacts() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_contactsKey);
    if (raw == null) return [];
    try {
      final decodedRaw = (await _decryptSensitivePrefsString(raw)) ?? raw;
      final arr = (jsonDecode(decodedRaw) as List)
          .map((m) => ChatContact.fromMap(m as Map<String, Object?>))
          .whereType<ChatContact>()
          .toList();
      // Best-effort migration: encrypt legacy plaintext.
      if (decodedRaw == raw) {
        final enc = await _encryptSensitivePrefsString(decodedRaw);
        if (enc != null && enc.isNotEmpty) {
          await sp.setString(_contactsKey, enc);
        }
      }
      return arr;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveContacts(List<ChatContact> contacts) async {
    final sp = await SharedPreferences.getInstance();
    final raw = jsonEncode(contacts.map((c) => c.toMap()).toList());
    final enc = await _encryptSensitivePrefsString(raw);
    if (enc == null || enc.isEmpty) {
      return;
    }
    await sp.setString(_contactsKey, enc);
  }

  Future<Map<String, String>> loadDrafts() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_draftsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decodedRaw = (await _decryptSensitivePrefsString(raw)) ?? raw;
      final decoded = jsonDecode(decodedRaw);
      if (decoded is Map) {
        final out = <String, String>{};
        decoded.forEach((k, v) {
          final id = (k ?? '').toString().trim();
          final text = (v ?? '').toString();
          if (id.isNotEmpty && text.trim().isNotEmpty) {
            out[id] = text;
          }
        });
        // Best-effort migration: encrypt legacy plaintext.
        if (decodedRaw == raw) {
          final enc = await _encryptSensitivePrefsString(decodedRaw);
          if (enc != null && enc.isNotEmpty) {
            await sp.setString(_draftsKey, enc);
          }
        }
        return out;
      }
    } catch (_) {}
    return {};
  }

  Future<void> saveDrafts(Map<String, String> drafts) async {
    final sp = await SharedPreferences.getInstance();
    if (drafts.isEmpty) {
      await sp.remove(_draftsKey);
      return;
    }
    final cleaned = <String, String>{};
    drafts.forEach((k, v) {
      final id = k.trim();
      if (id.isEmpty) return;
      if (v.trim().isEmpty) return;
      cleaned[id] = v;
    });
    if (cleaned.isEmpty) {
      await sp.remove(_draftsKey);
      return;
    }
    final raw = jsonEncode(cleaned);
    final enc = await _encryptSensitivePrefsString(raw);
    if (enc == null || enc.isEmpty) {
      return;
    }
    await sp.setString(_draftsKey, enc);
  }

  Future<void> saveMessages(String peerId, List<ChatMessage> msgs) async {
    final sp = await SharedPreferences.getInstance();
    final raw = jsonEncode(msgs.map((m) => m.toMap()).toList());
    final enc = await _encryptSensitivePrefsString(raw);
    if (enc == null || enc.isEmpty) {
      return;
    }
    await sp.setString('chat.msgs.$peerId', enc);
  }

  Future<void> deleteMessages(String peerId) async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove('chat.msgs.$peerId');
  }

  Future<List<ChatMessage>> loadMessages(String peerId) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('chat.msgs.$peerId');
    if (raw == null) return [];
    try {
      final decodedRaw = (await _decryptSensitivePrefsString(raw)) ?? raw;
      final arr = (jsonDecode(decodedRaw) as List)
          .map((m) => ChatMessage.fromMap(m as Map<String, Object?>))
          .toList();
      // Best-effort migration: encrypt legacy plaintext.
      if (decodedRaw == raw) {
        await saveMessages(peerId, arr);
      }
      return arr;
    } catch (_) {
      return [];
    }
  }

  Future<Set<String>> loadVoicePlayed(String peerId) async {
    if (peerId.isEmpty) return <String>{};
    final sp = await SharedPreferences.getInstance();
    final list =
        sp.getStringList('$_voicePlayedPrefix$peerId') ?? const <String>[];
    return list.where((id) => id.trim().isNotEmpty).toSet();
  }

  Future<void> markVoicePlayed(String peerId, String messageId) async {
    if (peerId.isEmpty || messageId.isEmpty) return;
    final sp = await SharedPreferences.getInstance();
    final key = '$_voicePlayedPrefix$peerId';
    final current = sp.getStringList(key) ?? const <String>[];
    final next = <String>[
      ...current.where((id) => id.isNotEmpty && id != messageId),
      messageId,
    ];
    if (next.length > _voicePlayedMax) {
      next.removeRange(0, next.length - _voicePlayedMax);
    }
    await sp.setStringList(key, next);
  }

  Future<Set<String>> loadGroupVoicePlayed(String groupId) async {
    if (groupId.isEmpty) return <String>{};
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList('$_groupVoicePlayedPrefix$groupId') ??
        const <String>[];
    return list.where((id) => id.trim().isNotEmpty).toSet();
  }

  Future<void> markGroupVoicePlayed(String groupId, String messageId) async {
    if (groupId.isEmpty || messageId.isEmpty) return;
    final sp = await SharedPreferences.getInstance();
    final key = '$_groupVoicePlayedPrefix$groupId';
    final current = sp.getStringList(key) ?? const <String>[];
    final next = <String>[
      ...current.where((id) => id.isNotEmpty && id != messageId),
      messageId,
    ];
    if (next.length > _voicePlayedMax) {
      next.removeRange(0, next.length - _voicePlayedMax);
    }
    await sp.setStringList(key, next);
  }

  Future<void> saveGroupMessages(
    String groupId,
    List<ChatGroupMessage> msgs,
  ) async {
    final sp = await SharedPreferences.getInstance();
    final raw = jsonEncode(
      msgs
          .map(
            (m) => {
              'id': m.id,
              'group_id': m.groupId,
              'sender_id': m.senderId,
              'text': m.text,
              'kind': m.kind,
              'nonce_b64': m.nonceB64,
              'box_b64': m.boxB64,
              'attachment_b64': m.attachmentB64,
              'attachment_mime': m.attachmentMime,
              'voice_secs': m.voiceSecs,
              'created_at': m.createdAt?.toUtc().toIso8601String(),
              'expire_at': m.expireAt?.toUtc().toIso8601String(),
            },
          )
          .toList(),
    );
    final enc = await _encryptSensitivePrefsString(raw);
    if (enc == null || enc.isEmpty) {
      return;
    }
    await sp.setString('chat.grp.msgs.$groupId', enc);
  }

  Future<List<ChatGroupMessage>> loadGroupMessages(String groupId) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('chat.grp.msgs.$groupId');
    if (raw == null) return [];
    try {
      final decodedRaw = (await _decryptSensitivePrefsString(raw)) ?? raw;
      final arr = (jsonDecode(decodedRaw) as List)
          .whereType<Map>()
          .map((m) => ChatGroupMessage.fromJson(m.cast<String, Object?>()))
          .toList();
      // Best-effort migration: encrypt legacy plaintext.
      if (decodedRaw == raw) {
        await saveGroupMessages(groupId, arr);
      }
      return arr;
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteGroupMessages(String groupId) async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove('chat.grp.msgs.$groupId');
  }

  Future<Map<String, String>> loadGroupSeen() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_groupSeenKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> saveGroupSeen(Map<String, String> seen) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_groupSeenKey, jsonEncode(seen));
  }

  Future<void> setGroupSeen(String groupId, DateTime ts) async {
    final map = await loadGroupSeen();
    map[groupId] = ts.toUtc().toIso8601String();
    await saveGroupSeen(map);
  }

  Future<Map<String, String>> loadGroupNames() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_groupNamesKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<String?> loadGroupName(String groupId) async {
    final gid = groupId.trim();
    if (gid.isEmpty) return null;
    final map = await loadGroupNames();
    final name = (map[gid] ?? '').trim();
    if (name.isEmpty) return null;
    return name;
  }

  Future<void> saveGroupNames(Map<String, String> names) async {
    final sp = await SharedPreferences.getInstance();
    if (names.isEmpty) {
      await sp.remove(_groupNamesKey);
      return;
    }
    await sp.setString(_groupNamesKey, jsonEncode(names));
  }

  Future<void> upsertGroupNames(Iterable<ChatGroup> groups) async {
    final sp = await SharedPreferences.getInstance();
    Map<String, String> names = {};
    try {
      final raw = sp.getString(_groupNamesKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          names = decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      }
    } catch (_) {
      names = {};
    }

    var changed = false;
    for (final g in groups) {
      final gid = g.id.trim();
      final name = g.name.trim();
      if (gid.isEmpty || name.isEmpty) continue;
      if (names[gid] != name) {
        names[gid] = name;
        changed = true;
      }
    }
    if (!changed) return;
    await saveGroupNames(names);
  }

  Future<Map<String, int>> loadUnread() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_unreadKey);
    if (raw == null) return {};
    try {
      final map = (jsonDecode(raw) as Map<String, Object?>);
      return map.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0));
    } catch (_) {
      return {};
    }
  }

  Future<void> saveUnread(Map<String, int> unread) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_unreadKey, jsonEncode(unread));
  }

  Future<void> setActivePeer(String peerId) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_activePeerKey, peerId);
  }

  Future<String?> loadActivePeer() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_activePeerKey);
  }

  Future<Map<String, String>> _loadOfficialNotifRaw() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_officialNotifKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveOfficialNotifRaw(Map<String, String> prefs) async {
    final sp = await SharedPreferences.getInstance();
    if (prefs.isEmpty) {
      await sp.remove(_officialNotifKey);
      return;
    }
    await sp.setString(_officialNotifKey, jsonEncode(prefs));
  }

  Future<OfficialNotificationMode?> loadOfficialNotifMode(String peerId) async {
    if (peerId.isEmpty) return null;
    final map = await _loadOfficialNotifRaw();
    final raw = map[peerId];
    switch (raw) {
      case 'full':
        return OfficialNotificationMode.full;
      case 'summary':
        return OfficialNotificationMode.summary;
      case 'muted':
        return OfficialNotificationMode.muted;
      default:
        return null;
    }
  }

  Future<void> setOfficialNotifMode(
    String peerId,
    OfficialNotificationMode? mode,
  ) async {
    if (peerId.isEmpty) return;
    final map = await _loadOfficialNotifRaw();
    if (mode == null) {
      map.remove(peerId);
    } else {
      final raw = switch (mode) {
        OfficialNotificationMode.full => 'full',
        OfficialNotificationMode.summary => 'summary',
        OfficialNotificationMode.muted => 'muted',
      };
      map[peerId] = raw;
    }
    await _saveOfficialNotifRaw(map);
  }

  Future<void> setNotifyPreview(bool enabled) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_notifyPreviewKey, enabled);
  }

  Future<bool> loadNotifyPreview() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_notifyPreviewKey) ?? false;
  }

  Future<void> setNotifyEnabled(bool enabled) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_notifyEnabledKey, enabled);
  }

  Future<bool> loadNotifyEnabled() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_notifyEnabledKey) ?? true;
  }

  Future<void> setNotifySound(bool enabled) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_notifySoundKey, enabled);
  }

  Future<bool> loadNotifySound() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_notifySoundKey) ?? true;
  }

  Future<void> setNotifyVibrate(bool enabled) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_notifyVibrateKey, enabled);
  }

  Future<bool> loadNotifyVibrate() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_notifyVibrateKey) ?? true;
  }

  Future<void> setNotifyDndEnabled(bool enabled) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_notifyDndKey, enabled);
  }

  Future<bool> loadNotifyDndEnabled() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_notifyDndKey) ?? false;
  }

  Future<void> setNotifyDndSchedule({
    required int startMinutes,
    required int endMinutes,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final start = startMinutes.clamp(0, 24 * 60 - 1).toInt();
    final end = endMinutes.clamp(0, 24 * 60 - 1).toInt();
    await sp.setInt(_notifyDndStartKey, start);
    await sp.setInt(_notifyDndEndKey, end);
  }

  Future<int> loadNotifyDndStartMinutes() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getInt(_notifyDndStartKey) ?? _notifyDndDefaultStart;
  }

  Future<int> loadNotifyDndEndMinutes() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getInt(_notifyDndEndKey) ?? _notifyDndDefaultEnd;
  }

  Future<
      ({
        bool enabled,
        bool preview,
        bool sound,
        bool vibrate,
        bool dnd,
        int dndStart,
        int dndEnd,
      })> loadNotifyConfig() async {
    final sp = await SharedPreferences.getInstance();
    return (
      enabled: sp.getBool(_notifyEnabledKey) ?? true,
      preview: sp.getBool(_notifyPreviewKey) ?? false,
      sound: sp.getBool(_notifySoundKey) ?? true,
      vibrate: sp.getBool(_notifyVibrateKey) ?? true,
      dnd: sp.getBool(_notifyDndKey) ?? false,
      dndStart: sp.getInt(_notifyDndStartKey) ?? _notifyDndDefaultStart,
      dndEnd: sp.getInt(_notifyDndEndKey) ?? _notifyDndDefaultEnd,
    );
  }

  Future<bool> isVerified(String peerId, String fp) async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_verKey(peerId)) == fp;
  }

  Future<void> markVerified(String peerId, String fp) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_verKey(peerId), fp);
  }

  String _verKey(String peerId) => 'chat.ver.${peerId}';

  Future<Map<String, String>> loadSessionKeys() async {
    final raw = await _secureRead(_sessionKeyMap);
    if (raw == null || raw.isEmpty) return {};
    final map = (jsonDecode(raw) as Map<String, Object?>);
    return map.map((k, v) => MapEntry(k, v.toString()));
  }

  Future<String?> loadGroupKey(String groupId) async {
    if (groupId.isEmpty) return null;
    return await _secureRead('$_groupKeyPrefix$groupId');
  }

  Future<void> saveGroupKey(String groupId, String keyB64) async {
    if (groupId.isEmpty || keyB64.isEmpty) return;
    await _secureWrite('$_groupKeyPrefix$groupId', keyB64);
  }

  Future<void> deleteGroupKey(String groupId) async {
    if (groupId.isEmpty) return;
    await _secureDelete('$_groupKeyPrefix$groupId');
  }

  Future<void> saveSessionKey(String peerId, String keyB64) async {
    final map = await loadSessionKeys();
    map[peerId] = keyB64;
    await _secureWrite(_sessionKeyMap, jsonEncode(map));
  }

  Future<void> saveSessionBootstrapMeta(
    String peerId, {
    required String protocolFloor,
    required int signedPrekeyId,
    int? oneTimePrekeyId,
    required bool v2Only,
    String? identitySigningPubkeyB64,
  }) async {
    final pid = peerId.trim();
    if (pid.isEmpty) return;
    final signingKey = (identitySigningPubkeyB64 ?? '').trim();
    await _secureWrite(
      '$_sessionBootstrapPrefix$pid',
      jsonEncode({
        'peer_id': pid,
        'protocol_floor': protocolFloor,
        'signed_prekey_id': signedPrekeyId,
        'one_time_prekey_id': oneTimePrekeyId,
        'v2_only': v2Only,
        if (signingKey.isNotEmpty) 'identity_signing_pubkey_b64': signingKey,
        'bootstrapped_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  Future<Map<String, Object?>> loadSessionBootstrapMeta(String peerId) async {
    final pid = peerId.trim();
    if (pid.isEmpty) return <String, Object?>{};
    final raw = await _secureRead('$_sessionBootstrapPrefix$pid');
    if (raw == null || raw.isEmpty) return <String, Object?>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
    return <String, Object?>{};
  }

  Future<String?> loadPinnedIdentitySigningPubkey(String peerId) async {
    final meta = await loadSessionBootstrapMeta(peerId);
    final raw = (meta['identity_signing_pubkey_b64'] ?? '').toString().trim();
    if (raw.isEmpty) return null;
    return raw;
  }

  Future<void> deleteSessionBootstrapMeta(String peerId) async {
    final pid = peerId.trim();
    if (pid.isEmpty) return;
    await _secureDelete('$_sessionBootstrapPrefix$pid');
  }

  Future<Map<String, Map<String, Object>>> loadChains() async {
    final raw = await _secureRead(_chainMap);
    if (raw == null || raw.isEmpty) return {};
    final decoded = (jsonDecode(raw) as Map<String, Object?>);
    return decoded.map(
      (k, v) => MapEntry(
        k,
        (v as Map<String, Object?>).map((k2, v2) => MapEntry(k2, v2 ?? '')),
      ),
    );
  }

  Future<void> saveChain(String peerId, Map<String, Object> state) async {
    final map = await loadChains();
    map[peerId] = state;
    await _secureWrite(_chainMap, jsonEncode(map));
  }

  Future<Map<String, Object>> loadRatchet(String peerId) async {
    final raw = await _secureRead('$_ratchetMap.$peerId');
    if (raw == null || raw.isEmpty) return {};
    return jsonDecode(raw) as Map<String, Object>;
  }

  Future<void> saveRatchet(String peerId, Map<String, Object> state) async {
    await _secureWrite('$_ratchetMap.$peerId', jsonEncode(state));
  }

  Future<void> deleteRatchet(String peerId) async {
    await _secureDelete('$_ratchetMap.$peerId');
  }

  static const _notifyPreviewKey = 'chat.notify.preview';
  static const _notifyEnabledKey = 'chat.notify.enabled';
  static const _notifySoundKey = 'chat.notify.sound';
  static const _notifyVibrateKey = 'chat.notify.vibrate';
  static const _notifyDndKey = 'chat.notify.dnd';
  static const _notifyDndStartKey = 'chat.notify.dnd_start';
  static const _notifyDndEndKey = 'chat.notify.dnd_end';
  static const int _notifyDndDefaultStart = 22 * 60;
  static const int _notifyDndDefaultEnd = 8 * 60;
  static const _sessionKeyMap = 'chat.session.keys';
  static const _chainMap = 'chat.session.chain';
  static const _ratchetMap = 'chat.ratchet';
  static const _groupKeyPrefix = 'chat.grp.key.';
  static const _sessionBootstrapPrefix = 'chat.session.bootstrap.';

  bool _useSecureStore() {
    // Best practice: do not persist E2EE secrets in browser storage.
    // (flutter_secure_storage_web uses Web Storage, which is not a safe secret store.)
    if (kIsWeb) return false;
    final isDesktop = defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
    if (!isDesktop) return true;
    return shamellDesktopSecureStorageDefault;
  }

  static const _prefsCryptoKeyName = 'chat.local.enc_key.v1';
  static Uint8List? _prefsCryptoKeyCache;

  Future<Uint8List?> _prefsCryptoKey() async {
    if (!_useSecureStore()) return null;
    if (_prefsCryptoKeyCache != null && _prefsCryptoKeyCache!.length == 32) {
      return _prefsCryptoKeyCache;
    }
    try {
      final raw = (await _secureRead(_prefsCryptoKeyName) ?? '').trim();
      if (raw.isNotEmpty) {
        final bytes = base64Decode(raw);
        if (bytes.length == 32) {
          _prefsCryptoKeyCache = bytes;
          return bytes;
        }
      }
    } catch (_) {}
    try {
      final rng = Random.secure();
      final bytes = Uint8List(32);
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = rng.nextInt(256);
      }
      final encoded = base64Encode(bytes);
      await _secureWrite(_prefsCryptoKeyName, encoded);
      final roundTrip = (await _secureRead(_prefsCryptoKeyName) ?? '').trim();
      if (roundTrip == encoded) {
        _prefsCryptoKeyCache = bytes;
        return bytes;
      }
      // Fail closed: if we can't persist the key, don't persist ciphertext we
      // can't decrypt on next app launch.
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> wipeSecrets() async {
    _prefsCryptoKeyCache = null;
    if (!_useSecureStore()) return;
    try {
      final sec = _sec();
      final all = await sec.readAll();
      for (final k in all.keys) {
        if (!k.startsWith('chat.')) continue;
        try {
          await sec.delete(key: k);
        } catch (_) {}
      }
    } catch (_) {
      // Best-effort fallback: delete high-value keys we can name.
      try {
        final sec = _sec();
        await sec.delete(key: _idKey);
        await sec.delete(key: _sessionKeyMap);
        await sec.delete(key: _chainMap);
        await sec.delete(key: _prefsCryptoKeyName);
      } catch (_) {}
    }
  }

  Future<String?> _encryptSensitivePrefsString(String plaintext) async {
    try {
      final key = await _prefsCryptoKey();
      if (key == null || key.length != 32) return null;
      final pt = Uint8List.fromList(utf8.encode(plaintext));
      final enc = x25519.SecretBox(key).encrypt(pt);
      return jsonEncode(<String, Object?>{
        'v': 1,
        'nonce_b64': base64Encode(enc.nonce.asTypedList),
        'box_b64': base64Encode(enc.cipherText.asTypedList),
      });
    } catch (_) {
      return null;
    }
  }

  Future<String?> _decryptSensitivePrefsString(String raw) async {
    final s = raw.trim();
    if (!s.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(s);
      if (decoded is! Map) return null;
      final v = decoded['v'];
      if (v is! num || v.toInt() != 1) return null;
      final nonceB64 = (decoded['nonce_b64'] ?? '').toString().trim();
      final boxB64 = (decoded['box_b64'] ?? '').toString().trim();
      if (nonceB64.isEmpty || boxB64.isEmpty) return null;
      final key = await _prefsCryptoKey();
      if (key == null || key.length != 32) return null;
      final nonce = base64Decode(nonceB64);
      final box = base64Decode(boxB64);
      final plain = x25519.SecretBox(key).decrypt(
        x25519.ByteList(box),
        nonce: nonce,
      );
      return utf8.decode(plain);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _secureRead(String key) async {
    if (_useSecureStore()) {
      try {
        return await _sec().read(key: key);
      } catch (_) {}
    }
    return null;
  }

  Future<void> _secureWrite(String key, String value) async {
    if (_useSecureStore()) {
      try {
        await _sec().write(key: key, value: value);
        return;
      } catch (_) {}
    }
    // Fail closed: if secure storage isn't available, do not persist secrets.
  }

  Future<void> _secureDelete(String key) async {
    if (_useSecureStore()) {
      try {
        await _sec().delete(key: key);
      } catch (_) {}
    }
  }

  FlutterSecureStorage _sec() => const FlutterSecureStorage(
        aOptions: AndroidOptions(
          encryptedSharedPreferences: true,
          resetOnError: true,
          // prefer hardware-backed when available
          sharedPreferencesName: 'chat_secure_store',
        ),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
        mOptions: MacOsOptions(
            accessibility: KeychainAccessibility.first_unlock_this_device),
      );
}

class ChatCallStore {
  static const _key = 'chat.calllog';

  Future<List<ChatCallLogEntry>> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final store = ChatLocalStore();
      final decodedRaw = (await store._decryptSensitivePrefsString(raw)) ?? raw;
      final arr = (jsonDecode(decodedRaw) as List)
          .whereType<Map>()
          .map((m) => ChatCallLogEntry.fromMap(m.cast<String, Object?>()))
          .toList();
      // Best-effort migration: encrypt legacy plaintext.
      if (decodedRaw == raw) {
        await save(arr);
      }
      return arr;
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<ChatCallLogEntry> list) async {
    final sp = await SharedPreferences.getInstance();
    final raw = jsonEncode(list.map((e) => e.toMap()).toList());
    final store = ChatLocalStore();
    final enc = await store._encryptSensitivePrefsString(raw);
    if (enc == null || enc.isEmpty) {
      return;
    }
    await sp.setString(_key, enc);
  }

  Future<void> append(ChatCallLogEntry entry, {int maxEntries = 100}) async {
    final current = await load();
    final updated = <ChatCallLogEntry>[entry, ...current];
    if (updated.length > maxEntries) {
      updated.removeRange(maxEntries, updated.length);
    }
    await save(updated);
  }
}
