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
import '../ephemeral_voice_file.dart';
import '../favorites_store.dart';
import '../base_url.dart';
import '../device_binding_guard.dart';
import '../shamell_user_id.dart';
import 'chat_models.dart';
import 'package:shamell_flutter/core/device_id.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import 'package:shamell_flutter/core/v2_chat_strangler.dart';

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

@visibleForTesting
const Duration shamellLibsignalPrekeyStatusCheckMinInterval = Duration(
  minutes: 10,
);

@visibleForTesting
const int shamellDirectMessageCiphertextMaxB64Len = 1000000;
final RegExp _inviteTokenRegex = RegExp(r'^[0-9a-f]{64}$');
final RegExp _shamellUserIdRegex = RegExp(r'^[A-HJ-NP-Z2-9]{8}$');

String _normalizeInviteTokenOrThrow(String rawToken) {
  final tok = rawToken.trim().toLowerCase();
  if (!_inviteTokenRegex.hasMatch(tok)) {
    throw Exception('invalid invite token');
  }
  return tok;
}

String _normalizeShamellUserIdOrThrow(String rawShamellId) {
  final normalized = rawShamellId.trim().toUpperCase();
  if (!_shamellUserIdRegex.hasMatch(normalized)) {
    throw Exception('invalid shamell id');
  }
  return normalized;
}

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

int _compareTimestampIdCursor(
  DateTime? leftTs,
  String leftId,
  DateTime? rightTs,
  String rightId,
) {
  final left = leftTs ?? DateTime.fromMillisecondsSinceEpoch(0);
  final right = rightTs ?? DateTime.fromMillisecondsSinceEpoch(0);
  final byTime = left.compareTo(right);
  if (byTime != 0) return byTime;
  return leftId.compareTo(rightId);
}

ChatGroupMessage? _latestGroupCursorMessage(
    Iterable<ChatGroupMessage> messages) {
  ChatGroupMessage? latest;
  for (final message in messages) {
    if (message.id.trim().isEmpty || message.createdAt == null) {
      continue;
    }
    if (latest == null ||
        _compareTimestampIdCursor(
              latest.createdAt,
              latest.id,
              message.createdAt,
              message.id,
            ) <
            0) {
      latest = message;
    }
  }
  return latest;
}

ChatGroupMessage? _oldestGroupCursorMessage(
    Iterable<ChatGroupMessage> messages) {
  ChatGroupMessage? oldest;
  for (final message in messages) {
    if (message.id.trim().isEmpty || message.createdAt == null) {
      continue;
    }
    if (oldest == null ||
        _compareTimestampIdCursor(
              oldest.createdAt,
              oldest.id,
              message.createdAt,
              message.id,
            ) >
            0) {
      oldest = message;
    }
  }
  return oldest;
}

ChatMessage? _latestDirectCursorMessage(Iterable<ChatMessage> messages) {
  ChatMessage? latest;
  for (final message in messages) {
    if (message.id.trim().isEmpty || message.createdAt == null) {
      continue;
    }
    if (latest == null ||
        _compareTimestampIdCursor(
              latest.createdAt,
              latest.id,
              message.createdAt,
              message.id,
            ) <
            0) {
      latest = message;
    }
  }
  return latest;
}

class _ChatGroupListCursor {
  final String createdAt;
  final String id;

  const _ChatGroupListCursor({
    required this.createdAt,
    required this.id,
  });
}

_ChatGroupListCursor? _oldestGroupListCursor(Iterable<ChatGroup> groups) {
  ChatGroup? oldest;
  for (final group in groups) {
    if (group.id.trim().isEmpty || group.createdAt == null) {
      continue;
    }
    if (oldest == null ||
        _compareTimestampIdCursor(
              oldest.createdAt,
              oldest.id,
              group.createdAt,
              group.id,
            ) >
            0) {
      oldest = group;
    }
  }
  if (oldest == null || oldest.createdAt == null) {
    return null;
  }
  return _ChatGroupListCursor(
    createdAt: oldest.createdAt!.toUtc().toIso8601String(),
    id: oldest.id,
  );
}

int _compareGroupListCursorDesc(ChatGroup left, ChatGroup right) {
  return _compareTimestampIdCursor(
    right.createdAt,
    right.id,
    left.createdAt,
    left.id,
  );
}

class _ChatGroupMembersCursor {
  final String joinedAt;
  final String deviceId;

  const _ChatGroupMembersCursor({
    required this.joinedAt,
    required this.deviceId,
  });
}

_ChatGroupMembersCursor? _latestGroupMembersCursor(
  Iterable<ChatGroupMember> members,
) {
  ChatGroupMember? latest;
  for (final member in members) {
    if (member.deviceId.trim().isEmpty || member.joinedAt == null) {
      continue;
    }
    if (latest == null ||
        _compareTimestampIdCursor(
              latest.joinedAt,
              latest.deviceId,
              member.joinedAt,
              member.deviceId,
            ) <
            0) {
      latest = member;
    }
  }
  if (latest == null || latest.joinedAt == null) {
    return null;
  }
  return _ChatGroupMembersCursor(
    joinedAt: latest.joinedAt!.toUtc().toIso8601String(),
    deviceId: latest.deviceId,
  );
}

int _compareGroupMemberCursorAsc(ChatGroupMember left, ChatGroupMember right) {
  return _compareTimestampIdCursor(
    left.joinedAt,
    left.deviceId,
    right.joinedAt,
    right.deviceId,
  );
}

int? _oldestGroupKeyEventVersion(Iterable<ChatGroupKeyEvent> events) {
  int? oldest;
  for (final event in events) {
    final version = event.version;
    if (version <= 0) continue;
    if (oldest == null || version < oldest) {
      oldest = version;
    }
  }
  return oldest;
}

int _compareGroupKeyEventDesc(ChatGroupKeyEvent left, ChatGroupKeyEvent right) {
  return right.version.compareTo(left.version);
}

@immutable
class ChatDirectSendEnvelope {
  final String senderId;
  final String recipientId;
  final String protocolVersion;
  final String senderPubkeyB64;
  final String? senderDhPubB64;
  final String nonceB64;
  final String boxB64;
  final bool sealedSender;
  final String? senderHint;
  final String? senderFingerprint;
  final String? keyId;
  final String? prevKeyId;
  final int? expireAfterSeconds;

  const ChatDirectSendEnvelope({
    required this.senderId,
    required this.recipientId,
    required this.protocolVersion,
    required this.senderPubkeyB64,
    required this.nonceB64,
    required this.boxB64,
    required this.sealedSender,
    this.senderDhPubB64,
    this.senderHint,
    this.senderFingerprint,
    this.keyId,
    this.prevKeyId,
    this.expireAfterSeconds,
  });

  bool matchesActors({
    required ChatIdentity me,
    required ChatContact peer,
  }) {
    return senderId == me.id &&
        recipientId == peer.id &&
        senderPubkeyB64 == me.publicKeyB64;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'sender_id': senderId,
        'recipient_id': recipientId,
        'protocol_version': protocolVersion,
        'sender_pubkey_b64': senderPubkeyB64,
        if (senderDhPubB64 != null) 'sender_dh_pub_b64': senderDhPubB64,
        'nonce_b64': nonceB64,
        'box_b64': boxB64,
        'sealed_sender': sealedSender,
        if (sealedSender && (senderHint ?? '').trim().isNotEmpty)
          'sender_hint': senderHint!.trim(),
        if (sealedSender && (senderFingerprint ?? '').trim().isNotEmpty)
          'sender_fingerprint': senderFingerprint!.trim(),
        if (keyId != null) 'key_id': keyId,
        if (prevKeyId != null) 'prev_key_id': prevKeyId,
        if (expireAfterSeconds != null)
          'expire_after_seconds': expireAfterSeconds,
      };
}

@visibleForTesting
ChatGroupMessage shamellDecryptOrBlockGroupMessage(
    ChatGroupMessage m, Uint8List key) {
  final kind = (m.kind ?? '').toLowerCase();
  if (kind == 'system') return m;
  if (key.length != 32) {
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
  ChatService(
    String baseUrl, {
    http.Client? httpClient,
    @visibleForTesting bool ownsHttpClient = false,
  })  : _base = _normalizeBase(baseUrl),
        _http = httpClient ?? shamellHttpClient(),
        _ownsHttpClient = ownsHttpClient || httpClient == null;

  static const Duration _chatRequestTimeout = Duration(seconds: 15);

  static String _normalizeBase(String raw) {
    final normalized = normalizeSecureApiBaseUrl(raw);
    if (normalized == null) {
      return '';
    }
    return normalized;
  }

  final String _base;
  final http.Client _http;
  final bool _ownsHttpClient;
  WebSocketChannel? _ws;
  WebSocketChannel? _wsGroups;
  WebSocketChannel? _wsTyping;
  bool _closed = false;
  static final Map<String, Future<ChatIdentity>>
      _accountChatReadyInFlightByBase = <String, Future<ChatIdentity>>{};

  String get baseUrl => _base;

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
    // Allow http only on localhost (always) and private-LAN hosts in non-release
    // builds — required for on-device debug builds talking to a dev BFF on the
    // local network. Release builds always require HTTPS.
    final u = Uri.tryParse(_base);
    if (u == null) {
      throw StateError('Invalid chat base URL');
    }
    final scheme = u.scheme.toLowerCase();
    final host = u.host.toLowerCase();
    if (scheme == 'https') return;
    if (scheme == 'http' && _isLocalhostHost(host)) return;
    if (scheme == 'http' && !kReleaseMode && isLocalNetworkHost(host)) return;
    throw StateError('Insecure chat base URL: HTTPS is required');
  }

  Future<http.Response> _get(
    Uri uri, {
    Map<String, String>? headers,
  }) =>
      _http.get(uri, headers: headers).timeout(_chatRequestTimeout);

  Future<http.Response> _post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) =>
      _http
          .post(
            uri,
            headers: headers,
            body: body,
            encoding: encoding,
          )
          .timeout(_chatRequestTimeout);

  Future<http.Response> _delete(
    Uri uri, {
    Map<String, String>? headers,
  }) =>
      _http.delete(uri, headers: headers).timeout(_chatRequestTimeout);

  Future<ChatContact> registerDevice(ChatIdentity me) async {
    final clientDeviceId =
        (await getOrCreateStableDeviceId(baseUrlOverride: _base)).trim();
    final body = jsonEncode({
      'device_id': me.id,
      if (clientDeviceId.isNotEmpty) 'client_device_id': clientDeviceId,
      'public_key_b64': me.publicKeyB64,
      'name': me.displayName,
    });
    final r = await _post(
      _uri('/chat/devices/register'),
      headers: await _headers(json: true, chatDeviceId: me.id),
      body: body,
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'registerDevice',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final j = jsonDecode(r.body) as Map<String, Object?>;
    final authToken = (j['auth_token'] ?? '').toString().trim();
    if (authToken.isNotEmpty) {
      await ChatLocalStore().saveDeviceAuthToken(
        me.id,
        authToken,
        baseUrlOverride: _base,
      );
    }
    final currentShamellUserId =
        (await loadShamellUserId(baseUrlOverride: _base) ?? '')
            .trim()
            .toUpperCase();
    if (_shamellUserIdRegex.hasMatch(currentShamellUserId)) {
      await ChatLocalStore().saveRegisteredAccountShamellUserId(
        me.id,
        currentShamellUserId,
        baseUrlOverride: _base,
      );
    }
    await _ensureLibsignalMaterialForRegisteredDevice(me);
    return ChatContact(
      id: (j['device_id'] ?? '') as String,
      publicKeyB64: (j['public_key_b64'] ?? '') as String,
      fingerprint: fingerprintForKey((j['public_key_b64'] ?? '') as String),
      name: j['name'] as String?,
      verified: false,
    );
  }

  Future<ChatContact> resolveDevice(String id) async {
    final r = await _get(
      _uri('/chat/devices/${Uri.encodeComponent(id)}'),
      headers: await _headers(),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'resolveDevice',
        statusCode: r.statusCode,
        body: r.body,
      );
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

  Future<void> _refreshSessionForAccountOps() async {
    final cookie = (await getSessionCookieHeader(_base) ?? '').trim();
    if (cookie.isEmpty) {
      throw Exception('auth session required');
    }
  }

  Future<void> _repairSessionForAccountOps() async {
    await clearSessionCookie();
    throw Exception('auth session required');
  }

  Future<void> _failClosedIfCriticalAccountSessionError(Object error) async {
    if (!shamellIsCriticalAccountSessionError(error)) return;
    await clearSessionCookie();
    throw Exception('auth session required');
  }

  Future<void> _failClosedIfCriticalAccountSessionHttpFailure(
    http.Response response,
  ) async {
    if (!shamellIsCriticalAccountSessionHttpFailure(
      statusCode: response.statusCode,
      rawBody: response.body,
    )) {
      return;
    }
    await clearSessionCookie();
    throw Exception('auth session required');
  }

  Future<void> _requireSessionCookieForAccountOps() async {
    await _refreshSessionForAccountOps();
    final cookie = (await getSessionCookieHeader(_base) ?? '').trim();
    if (cookie.isEmpty) throw StateError('Authentication required');
  }

  Future<http.Response> _postAccountJsonWithRetry({
    required String path,
    required String chatDeviceId,
    required Map<String, Object?> body,
  }) async {
    Future<http.Response> send(String did) async => _post(
          _uri(path),
          headers: await _headers(json: true, chatDeviceId: did),
          body: jsonEncode(body),
        );

    var did = chatDeviceId;
    var repairedAuth = false;
    var repairedRegistration = false;
    const maxAttempts = 3;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final r = await send(did);
        if (r.statusCode == 403 &&
            _isChatDeviceOwnershipFailureResponse(r.body) &&
            !repairedRegistration) {
          repairedRegistration = true;
          final me = await _ensureChatIdentityAndRegistrationForAccountOps(
            forceRegister: true,
          );
          did = me.id;
          continue;
        }
        if (_shouldRepairAccountAuthResponse(r) && !repairedAuth) {
          repairedAuth = true;
          await _repairSessionForAccountOps();
          final me = await _ensureChatIdentityAndRegistrationForAccountOps(
            forceRegister: true,
          );
          did = me.id;
          continue;
        }
        if (r.statusCode == 409 &&
            _isChatDeviceNotRegisteredResponse(r.body) &&
            !repairedRegistration) {
          repairedRegistration = true;
          final me = await _ensureChatIdentityAndRegistrationForAccountOps(
            forceRegister: true,
          );
          did = me.id;
          continue;
        }
        await _failClosedIfCriticalAccountSessionHttpFailure(r);
        if (_isRetryableAccountHttpStatus(r.statusCode) &&
            attempt < maxAttempts - 1) {
          await _backoffDelay(attempt);
          continue;
        }
        return r;
      } catch (e) {
        if (!_isRetryableAccountException(e) || attempt >= maxAttempts - 1) {
          rethrow;
        }
        await _backoffDelay(attempt);
      }
    }

    return send(did);
  }

  String _extractHttpDetail(String? rawBody) {
    final text = (rawBody ?? '').trim();
    if (text.isEmpty) return '';
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        final detail = (decoded['detail'] ?? '').toString().trim();
        if (detail.isNotEmpty) return detail;
      }
    } catch (_) {}
    return text;
  }

  bool _isChatDeviceNotRegisteredResponse(String? rawBody) {
    final d = _extractHttpDetail(rawBody).toLowerCase();
    return d.contains('chat device not registered');
  }

  bool _isChatDeviceOwnershipFailureResponse(String? rawBody) {
    final d = _extractHttpDetail(rawBody).toLowerCase();
    return d.contains('device not registered for authenticated user') ||
        d.contains('chat device not registered') ||
        d.contains('chat device_id required');
  }

  bool _shouldRepairAccountAuthResponse(http.Response response) {
    return shamellIsCriticalAccountSessionHttpFailure(
      statusCode: response.statusCode,
      rawBody: response.body,
    );
  }

  bool _isRetryableAccountHttpStatus(int statusCode) {
    return statusCode == 408 ||
        statusCode == 425 ||
        statusCode == 429 ||
        statusCode >= 500;
  }

  bool _isRetryableAccountException(Object error) {
    if (error is ChatHttpException) {
      return _isRetryableAccountHttpStatus(error.statusCode);
    }
    final raw = error.toString().toLowerCase();
    return raw.contains('socket') ||
        raw.contains('network') ||
        raw.contains('connection') ||
        raw.contains('timeout');
  }

  Future<void> _backoffDelay(int attempt) async {
    final capped = attempt.clamp(0, 4);
    final base = 250 * (1 << capped);
    final jitter = Random.secure().nextInt(220);
    await Future<void>.delayed(Duration(milliseconds: base + jitter));
  }

  bool _isMissingLibsignalKeyApiFailure(Object e) {
    if (e is ChatHttpException) {
      return e.statusCode == 404 &&
          (e.op == 'keysBootstrap' ||
              e.op == 'prekeysStatus' ||
              e.op == 'keysRegister' ||
              e.op == 'prekeysUpload');
    }
    final text = e.toString().toLowerCase();
    return text.contains('keys bootstrap failed: 404') ||
        text.contains('prekeys status failed: 404') ||
        text.contains('keys register failed: 404') ||
        text.contains('prekeys upload failed: 404');
  }

  bool _shouldFallbackToFullChatDeviceRegistration(Object e) {
    if (e is! ChatHttpException) return false;
    final detail = _extractHttpDetail(e.body).toLowerCase();
    if (shamellIsCriticalAccountSessionHttpFailure(
      statusCode: e.statusCode,
      rawBody: e.body,
    )) {
      return true;
    }
    return detail.contains('unknown chat device auth') ||
        detail.contains('invalid chat device token') ||
        detail.contains('chat device auth required') ||
        detail.contains('device auth mismatch') ||
        _isChatDeviceOwnershipFailureResponse(e.body) ||
        (e.statusCode == 409 && _isChatDeviceNotRegisteredResponse(e.body));
  }

  bool _isAuthFailure(Object e) {
    if (e is ChatHttpException) {
      return e.statusCode == 401 || e.statusCode == 403;
    }
    final text = e.toString().toLowerCase();
    return text.contains('authentication required') ||
        text.contains('unauthorized') ||
        text.contains('forbidden') ||
        text.contains('failed: 401') ||
        text.contains('failed: 403');
  }

  bool _isDeviceIdInUseFailure(Object e) {
    if (e is ChatHttpException) {
      if (e.statusCode != 400 && e.statusCode != 403 && e.statusCode != 409) {
        return false;
      }
      final detail = _extractHttpDetail(e.body).toLowerCase();
      return detail.contains('device id already in use') ||
          detail.contains('device_id already in use');
    }
    final text = e.toString().toLowerCase();
    return text.contains('device id already in use') ||
        text.contains('device_id already in use');
  }

  Future<ChatIdentity> _createAndPersistFreshIdentity(
    ChatLocalStore store, {
    String? baseUrlOverride,
  }) async {
    final sk = x25519.PrivateKey.generate();
    final pk = sk.publicKey;
    final pkB64 = base64Encode(pk.asTypedList);
    final me = ChatIdentity(
      id: generateShortId(),
      publicKeyB64: pkB64,
      privateKeyB64: base64Encode(sk.asTypedList),
      fingerprint: fingerprintForKey(pkB64),
    );
    await store.saveIdentity(me, baseUrlOverride: baseUrlOverride);
    return me;
  }

  Future<ChatIdentity> _ensureChatIdentityAndRegistrationForAccountOps({
    bool forceRegister = false,
  }) async {
    final existing = _accountChatReadyInFlightByBase[_base];
    if (existing != null) {
      final settled = await existing;
      if (!forceRegister) {
        return settled;
      }
    }

    final future = _ensureChatIdentityAndRegistrationForAccountOpsCore(
      forceRegister: forceRegister,
    );
    _accountChatReadyInFlightByBase[_base] = future;
    try {
      return await future;
    } finally {
      if (identical(_accountChatReadyInFlightByBase[_base], future)) {
        _accountChatReadyInFlightByBase.remove(_base);
      }
    }
  }

  Future<ChatIdentity> _ensureChatIdentityAndRegistrationForAccountOpsCore({
    bool forceRegister = false,
  }) async {
    final store = ChatLocalStore();
    final loaded = await store.loadIdentity(baseUrlOverride: _base);
    var me = (loaded == null ||
            loaded.id.trim().isEmpty ||
            loaded.publicKeyB64.trim().isEmpty ||
            loaded.privateKeyB64.trim().isEmpty)
        ? await _createAndPersistFreshIdentity(
            store,
            baseUrlOverride: _base,
          )
        : loaded;

    final token = (await store.loadDeviceAuthToken(
              me.id,
              baseUrlOverride: _base,
            ) ??
            '')
        .trim();
    final keyBootstrapped = await store.isDeviceKeyBootstrapped(
      me.id,
      baseUrlOverride: _base,
    );
    final currentShamellUserId =
        (await loadShamellUserId(baseUrlOverride: _base) ?? '')
            .trim()
            .toUpperCase();
    final registeredShamellUserId =
        (await store.loadRegisteredAccountShamellUserId(
                  me.id,
                  baseUrlOverride: _base,
                ) ??
                '')
            .trim()
            .toUpperCase();
    final hasRegisteredAccountDrift =
        _shamellUserIdRegex.hasMatch(currentShamellUserId) &&
            _shamellUserIdRegex.hasMatch(registeredShamellUserId) &&
            currentShamellUserId != registeredShamellUserId;
    var needsFullDeviceRegistration =
        forceRegister || hasRegisteredAccountDrift;

    if (hasRegisteredAccountDrift) {
      await store.deleteDeviceAuthToken(me.id, baseUrlOverride: _base);
      await store.deletePushTokenBindingFingerprint(
        me.id,
        baseUrlOverride: _base,
      );
      me = await _createAndPersistFreshIdentity(
        store,
        baseUrlOverride: _base,
      );
    }

    if (token.isNotEmpty && keyBootstrapped && !needsFullDeviceRegistration) {
      // Existing chat-device registration and key bootstrap are both present;
      // keep account ops cheap while opportunistically topping up depleted
      // one-time prekeys so new peers do not start failing with bundle_unavailable.
      try {
        await _maybeRefillOneTimePrekeys(me, store: store);
      } catch (e) {
        if (!_shouldFallbackToFullChatDeviceRegistration(e)) {
          await _failClosedIfCriticalAccountSessionError(e);
          rethrow;
        }
        needsFullDeviceRegistration = true;
      }
      if (!needsFullDeviceRegistration) {
        return me;
      }
    }

    if (token.isNotEmpty && !needsFullDeviceRegistration) {
      try {
        await _ensureLibsignalMaterialForRegisteredDevice(
          me,
          store: store,
        );
        return me;
      } catch (e) {
        if (!_shouldFallbackToFullChatDeviceRegistration(e)) {
          await _failClosedIfCriticalAccountSessionError(e);
          rethrow;
        }
        needsFullDeviceRegistration = true;
      }
    }

    // Register (or re-register) this chat device for account-scoped operations.
    var didForceSessionRefresh = false;
    var didRotateIdentity = false;
    while (true) {
      try {
        await registerDevice(me);
        break;
      } catch (e) {
        if (_isDeviceIdInUseFailure(e) && !didRotateIdentity) {
          // Treat ownership/conflict responses before generic 401/403 handling.
          // Otherwise a recoverable device-id clash can incorrectly trigger an
          // account bootstrap refresh before we rotate to a fresh local identity.
          didRotateIdentity = true;
          me = await _createAndPersistFreshIdentity(
            store,
            baseUrlOverride: _base,
          );
          continue;
        }
        if (_isAuthFailure(e) && !didForceSessionRefresh) {
          // Recover from stale/invalid local session cookie by forcing a fresh
          // account session and rotating the local chat identity once.
          // Otherwise the client can keep retrying a device_id that belongs to
          // a previous account session and never converge.
          didForceSessionRefresh = true;
          await _repairSessionForAccountOps();
          me = await _createAndPersistFreshIdentity(
            store,
            baseUrlOverride: _base,
          );
          continue;
        }
        await _failClosedIfCriticalAccountSessionError(e);
        rethrow;
      }
    }

    return me;
  }

  Future<void> ensureAccountChatReady() async {
    await _requireSessionCookieForAccountOps();
    await _ensureChatIdentityAndRegistrationForAccountOps();
  }

  Future<String> resolveContactByShamellId(String shamellId) async {
    final normalized = _normalizeShamellUserIdOrThrow(shamellId);
    await _requireSessionCookieForAccountOps();
    final me = await _ensureChatIdentityAndRegistrationForAccountOps();
    final r = await _postAccountJsonWithRetry(
      path: '/contacts/resolve_by_shamell_id',
      chatDeviceId: me.id,
      body: <String, Object?>{'shamell_id': normalized},
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'resolveContactByShamellId',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final j = jsonDecode(r.body);
    if (j is! Map) {
      throw Exception('contact resolve failed');
    }
    final did = (j['device_id'] ?? '').toString().trim();
    if (did.isEmpty) {
      throw Exception('contact resolve failed');
    }
    return did;
  }

  /// Resolves a contact by SyrChat ID with account/chat bootstrap retries.
  Future<String> resolveContactByShamellIdEnsured(
    String shamellId, {
    int attempts = 2,
  }) async {
    final normalized = _normalizeShamellUserIdOrThrow(shamellId);
    Object? lastError;
    final tries = attempts.clamp(1, 5);
    for (var attempt = 0; attempt < tries; attempt++) {
      try {
        await ensureAccountChatReady();
        return await resolveContactByShamellId(normalized);
      } catch (e) {
        lastError = e;
        final retryable = _isRetryableAccountException(e);
        if (!retryable || attempt >= tries - 1) {
          rethrow;
        }
        await _backoffDelay(attempt);
      }
    }
    throw lastError ?? StateError('contact resolve failed');
  }

  Future<String> createContactInviteToken({int maxUses = 1}) async {
    await _requireSessionCookieForAccountOps();
    final me = await _ensureChatIdentityAndRegistrationForAccountOps();
    final requested = maxUses.clamp(1, 20);
    final r = await _postAccountJsonWithRetry(
      path: '/contacts/invites',
      chatDeviceId: me.id,
      body: <String, Object?>{'max_uses': requested},
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'createInvite',
        statusCode: r.statusCode,
        body: r.body,
      );
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

  /// Creates an invite token with built-in account/chat bootstrap retries.
  ///
  /// This is used by UI entry points to avoid duplicating the same
  /// "ensure session + ensure chat device + create token" flow.
  Future<String> createContactInviteTokenEnsured({
    int maxUses = 1,
    int attempts = 2,
  }) async {
    Object? lastError;
    final tries = attempts.clamp(1, 5);
    for (var attempt = 0; attempt < tries; attempt++) {
      try {
        await ensureAccountChatReady();
        return await createContactInviteToken(maxUses: maxUses);
      } catch (e) {
        lastError = e;
        final retryable = _isRetryableAccountException(e);
        if (!retryable || attempt >= tries - 1) {
          rethrow;
        }
        await _backoffDelay(attempt);
      }
    }
    throw lastError ?? StateError('invite create failed');
  }

  Future<String> redeemContactInviteToken(String rawToken) async {
    final tok = _normalizeInviteTokenOrThrow(rawToken);
    await _requireSessionCookieForAccountOps();
    final me = await _ensureChatIdentityAndRegistrationForAccountOps();
    final r = await _postAccountJsonWithRetry(
      path: '/contacts/invites/redeem',
      chatDeviceId: me.id,
      body: <String, Object?>{'token': tok},
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'redeemInvite',
        statusCode: r.statusCode,
        body: r.body,
      );
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

  /// Redeems an invite token with built-in account/chat bootstrap retries.
  Future<String> redeemContactInviteTokenEnsured(
    String rawToken, {
    int attempts = 2,
  }) async {
    final normalizedToken = _normalizeInviteTokenOrThrow(rawToken);
    Object? lastError;
    final tries = attempts.clamp(1, 5);
    for (var attempt = 0; attempt < tries; attempt++) {
      try {
        await ensureAccountChatReady();
        return await redeemContactInviteToken(normalizedToken);
      } catch (e) {
        lastError = e;
        final retryable = _isRetryableAccountException(e);
        if (!retryable || attempt >= tries - 1) {
          rethrow;
        }
        await _backoffDelay(attempt);
      }
    }
    throw lastError ?? StateError('invite redeem failed');
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
    final r = await _get(
      _uri('/chat/keys/bundle/${Uri.encodeComponent(did)}'),
      headers: await _headers(chatDeviceId: requesterDeviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'fetchKeyBundle',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final bundle =
        ChatKeyBundle.fromJson(jsonDecode(r.body) as Map<String, Object?>);
    if (!shamellAcceptPeerKeyBundle(bundle)) {
      throw StateError('insecure key bundle rejected');
    }
    return bundle;
  }

  Future<ChatPrekeyStatus> fetchPrekeyStatus({
    required String deviceId,
  }) async {
    final did = deviceId.trim();
    if (did.isEmpty) {
      throw ArgumentError.value(deviceId, 'deviceId');
    }
    final r = await _get(
      _uri('/chat/keys/prekeys/status/${Uri.encodeComponent(did)}'),
      headers: await _headers(chatDeviceId: did),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'prekeysStatus',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    return ChatPrekeyStatus.fromJson(
      jsonDecode(r.body) as Map<String, Object?>,
    );
  }

  Future<void> uploadOneTimePrekeys({
    required ChatIdentity me,
    int count = shamellLibsignalPrekeyBatchDefault,
  }) async {
    final prekeys = _buildOneTimePrekeys(count);
    if (prekeys.isEmpty) return;
    final upload = await _post(
      _uri('/chat/keys/prekeys/upload'),
      headers: await _headers(json: true, chatDeviceId: me.id),
      body: jsonEncode({
        'device_id': me.id,
        'prekeys': prekeys.map((p) => p.toJson()).toList(),
      }),
    );
    if (upload.statusCode >= 400) {
      throw ChatHttpException(
        op: 'prekeysUpload',
        statusCode: upload.statusCode,
        body: upload.body,
      );
    }
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
    final registerBody = <String, Object?>{
      'device_id': me.id,
      'identity_key_b64': me.publicKeyB64,
      'identity_signing_pubkey_b64':
          keyRegistrationSignature.identitySigningPubkeyB64,
      'signed_prekey_id': signedPrekeyId,
      'signed_prekey_b64': signedPrekeyB64,
      'signed_prekey_sig_b64': keyRegistrationSignature.signatureB64,
      'signed_prekey_sig_alg': 'ed25519',
      'v2_only': v2Only ?? _enableLibsignalV2Only(),
    };
    final prekeys = _buildOneTimePrekeys(oneTimePrekeyCount);
    if (prekeys.isNotEmpty) {
      final bootstrap = await _post(
        _uri('/chat/keys/bootstrap'),
        headers: await _headers(json: true, chatDeviceId: me.id),
        body: jsonEncode(<String, Object?>{
          ...registerBody,
          'prekeys': prekeys.map((p) => p.toJson()).toList(),
        }),
      );
      if (bootstrap.statusCode < 400) {
        return;
      }
      if (bootstrap.statusCode != 404) {
        throw ChatHttpException(
          op: 'keysBootstrap',
          statusCode: bootstrap.statusCode,
          body: bootstrap.body,
        );
      }
    }
    final r = await _post(
      _uri('/chat/keys/register'),
      headers: await _headers(json: true, chatDeviceId: me.id),
      body: jsonEncode(registerBody),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'keysRegister',
        statusCode: r.statusCode,
        body: r.body,
      );
    }

    if (prekeys.isEmpty) return;
    await uploadOneTimePrekeys(me: me, count: prekeys.length);
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
    ChatDirectSendEnvelope? preparedEnvelope,
    V2ChatFlowVariant metricVariant = V2ChatFlowVariant.legacy,
  }) async {
    final stopwatch = Stopwatch()..start();
    var ok = false;
    try {
      final envelope = preparedEnvelope ??
          prepareDirectSendEnvelope(
            me: me,
            peer: peer,
            plainText: plainText,
            expireAfterSeconds: expireAfterSeconds,
            sealedSender: sealedSender,
            senderHint: senderHint,
            sessionKey: sessionKey,
            keyId: keyId,
            prevKeyId: prevKeyId,
            senderDhPubB64: senderDhPubB64,
          );
      if (!envelope.matchesActors(me: me, peer: peer)) {
        throw StateError('prepared direct envelope actor mismatch');
      }
      final body = jsonEncode(envelope.toJson());
      final r = await _post(
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
      ok = true;
      if (parsed.createdAt != null) {
        return parsed;
      }
      return ChatMessage(
        id: parsed.id,
        senderId: parsed.senderId,
        recipientId: parsed.recipientId,
        senderPubKeyB64: parsed.senderPubKeyB64,
        nonceB64: parsed.nonceB64,
        boxB64: parsed.boxB64,
        createdAt: DateTime.now(),
      );
    } finally {
      stopwatch.stop();
      await V2ChatStranglerStore.recordSendAttempt(
        variant: metricVariant,
        elapsedMs: stopwatch.elapsedMilliseconds,
        success: ok,
        baseUrlOverride: baseUrl,
      );
    }
  }

  Future<ChatMessage> editMessage({
    required ChatIdentity me,
    required ChatContact peer,
    required String messageId,
    required String plainText,
    Uint8List? sessionKey,
    int? keyId,
    int? prevKeyId,
    String? senderDhPubB64,
    ChatDirectSendEnvelope? preparedEnvelope,
  }) async {
    final normalizedMessageId = messageId.trim();
    if (normalizedMessageId.isEmpty) {
      throw ArgumentError.value(messageId, 'messageId', 'required');
    }
    final envelope = preparedEnvelope ??
        prepareDirectSendEnvelope(
          me: me,
          peer: peer,
          plainText: plainText,
          sealedSender: true,
          senderHint: me.fingerprint,
          sessionKey: sessionKey,
          keyId: keyId,
          prevKeyId: prevKeyId,
          senderDhPubB64: senderDhPubB64,
        );
    if (!envelope.matchesActors(me: me, peer: peer)) {
      throw StateError('prepared direct envelope actor mismatch');
    }
    final r = await _post(
      _uri('/chat/messages/${Uri.encodeComponent(normalizedMessageId)}/edit'),
      headers: await _headers(json: true, chatDeviceId: me.id),
      body: jsonEncode({
        'device_id': me.id,
        'protocol_version': envelope.protocolVersion,
        if ((envelope.senderDhPubB64 ?? '').trim().isNotEmpty)
          'sender_dh_pub_b64': envelope.senderDhPubB64,
        'nonce_b64': envelope.nonceB64,
        'box_b64': envelope.boxB64,
        if ((envelope.keyId ?? '').trim().isNotEmpty) 'key_id': envelope.keyId,
        if ((envelope.prevKeyId ?? '').trim().isNotEmpty)
          'prev_key_id': envelope.prevKeyId,
      }),
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw ChatHttpException(
        op: 'editMessage',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    return ChatMessage.fromJson(jsonDecode(r.body) as Map<String, Object?>);
  }

  ChatDirectSendEnvelope prepareDirectSendEnvelope({
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
  }) {
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
    if (enc.$2.length > shamellDirectMessageCiphertextMaxB64Len) {
      throw StateError('direct message too large');
    }
    return ChatDirectSendEnvelope(
      senderId: me.id,
      recipientId: peer.id,
      protocolVersion: _messageProtocolVersion(),
      senderPubkeyB64: me.publicKeyB64,
      senderDhPubB64: senderDhPubB64,
      nonceB64: enc.$1,
      boxB64: enc.$2,
      sealedSender: sealedSender,
      senderHint: sealedSender && hint.isNotEmpty ? hint : null,
      senderFingerprint: sealedSender && hint.isNotEmpty ? hint : null,
      keyId: keyId?.toString(),
      prevKeyId: prevKeyId?.toString(),
      expireAfterSeconds: expireAfterSeconds,
    );
  }

  Future<List<ChatMessage>> fetchInbox({
    required String deviceId,
    int limit = 50,
    String? sinceIso,
    String? sinceId,
    String? beforeCreatedAt,
    String? beforeId,
  }) async {
    final normalizedSinceIso = sinceIso?.trim() ?? '';
    final normalizedSinceId = sinceId?.trim() ?? '';
    final normalizedBeforeCreatedAt = beforeCreatedAt?.trim() ?? '';
    final normalizedBeforeId = beforeId?.trim() ?? '';
    if (normalizedSinceIso.isNotEmpty &&
        (normalizedBeforeCreatedAt.isNotEmpty ||
            normalizedBeforeId.isNotEmpty)) {
      throw ArgumentError(
        'before_created_at/before_id cannot be combined with since_iso/since_id',
      );
    }
    if ((normalizedBeforeCreatedAt.isEmpty) != (normalizedBeforeId.isEmpty)) {
      throw ArgumentError(
        'before_created_at and before_id are required together',
      );
    }
    final qp = <String, String>{'device_id': deviceId, 'limit': '$limit'};
    if (normalizedSinceIso.isNotEmpty) {
      qp['since_iso'] = normalizedSinceIso;
    }
    if (normalizedSinceId.isNotEmpty) {
      qp['since_id'] = normalizedSinceId;
    }
    if (normalizedBeforeCreatedAt.isNotEmpty) {
      qp['before_created_at'] = normalizedBeforeCreatedAt;
      qp['before_id'] = normalizedBeforeId;
    }
    final r = await _get(
      _uri('/chat/messages/inbox', qp),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'fetchInbox',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final arr = jsonDecode(r.body) as List;
    return _parseDirectInboxMessages(arr);
  }

  Future<List<ChatMessage>> fetchInboxPaged({
    required String deviceId,
    String? sinceIso,
    String? sinceId,
    int batchSize = 200,
    int maxPages = 25,
    int? retainLatestCount,
  }) async {
    final normalizedBatchSize = batchSize.clamp(1, 200);
    final normalizedMaxPages = maxPages < 1 ? 1 : maxPages;
    var cursorIso = sinceIso?.trim();
    var cursorId = sinceId?.trim();
    final incremental = (cursorIso ?? '').isNotEmpty;
    String? beforeCreatedAt;
    String? beforeId;
    final collected = <ChatMessage>[];
    final seenIds = <String>{};

    for (var page = 0; page < normalizedMaxPages; page++) {
      final items = await fetchInbox(
        deviceId: deviceId,
        limit: normalizedBatchSize,
        sinceIso: incremental ? cursorIso : null,
        sinceId: incremental ? cursorId : null,
        beforeCreatedAt: incremental ? null : beforeCreatedAt,
        beforeId: incremental ? null : beforeId,
      );
      if (items.isEmpty) {
        break;
      }
      for (final item in items) {
        if (item.id.trim().isEmpty || !seenIds.add(item.id)) {
          continue;
        }
        collected.add(item);
      }
      if (!incremental) {
        final oldest = _oldestDirectCursorMessage(items);
        if (oldest == null) {
          break;
        }
        if (items.length < normalizedBatchSize) {
          break;
        }
        final nextBeforeCreatedAt = oldest.createdAt?.toUtc().toIso8601String();
        final nextBeforeId = oldest.id.trim();
        if ((nextBeforeCreatedAt ?? '').isEmpty || nextBeforeId.isEmpty) {
          break;
        }
        if (beforeCreatedAt == nextBeforeCreatedAt &&
            beforeId == nextBeforeId) {
          break;
        }
        beforeCreatedAt = nextBeforeCreatedAt;
        beforeId = nextBeforeId;
        continue;
      }
      final latest = _latestDirectCursorMessage(items);
      if (latest == null) {
        break;
      }
      final nextCursorIso = latest.createdAt!.toUtc().toIso8601String();
      final nextCursorId = latest.id;
      if (nextCursorIso == cursorIso && nextCursorId == cursorId) {
        break;
      }
      cursorIso = nextCursorIso;
      cursorId = nextCursorId;
      if (items.length < normalizedBatchSize) {
        break;
      }
    }

    collected.sort((a, b) {
      return _compareTimestampIdCursor(
        a.createdAt,
        a.id,
        b.createdAt,
        b.id,
      );
    });
    if (retainLatestCount != null &&
        retainLatestCount > 0 &&
        collected.length > retainLatestCount) {
      return collected.sublist(collected.length - retainLatestCount);
    }
    return collected;
  }

  Future<List<ChatMessage>> fetchThreadHistory({
    required String deviceId,
    required String peerId,
    int limit = 200,
    String? beforeCreatedAt,
    String? beforeId,
  }) async {
    final normalizedBeforeCreatedAt = beforeCreatedAt?.trim() ?? '';
    final normalizedBeforeId = beforeId?.trim() ?? '';
    if ((normalizedBeforeCreatedAt.isEmpty) != (normalizedBeforeId.isEmpty)) {
      throw ArgumentError(
        'before_created_at and before_id are required together',
      );
    }
    final qp = <String, String>{
      'device_id': deviceId,
      'peer_id': peerId,
      'limit': '$limit',
    };
    if (normalizedBeforeCreatedAt.isNotEmpty) {
      qp['before_created_at'] = normalizedBeforeCreatedAt;
      qp['before_id'] = normalizedBeforeId;
    }
    final r = await _get(
      _uri('/chat/messages/thread', qp),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'fetchThreadHistory',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final arr = jsonDecode(r.body) as List;
    final messages = _parseDirectInboxMessages(arr);
    messages.sort((a, b) {
      return _compareTimestampIdCursor(
        a.createdAt,
        a.id,
        b.createdAt,
        b.id,
      );
    });
    return messages;
  }

  ChatMessage? _oldestDirectCursorMessage(List<ChatMessage> messages) {
    ChatMessage? oldest;
    for (final message in messages) {
      if (message.id.trim().isEmpty || message.createdAt == null) {
        continue;
      }
      if (oldest == null ||
          _compareTimestampIdCursor(
                message.createdAt,
                message.id,
                oldest.createdAt,
                oldest.id,
              ) <
              0) {
        oldest = message;
      }
    }
    return oldest;
  }

  Future<void> markRead(String id, {String? deviceId}) async {
    await _post(
      _uri('/chat/messages/$id/read'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode({'read': true}),
    );
  }

  Future<void> setMessageReaction({
    required String deviceId,
    required String messageId,
    String? emoji,
  }) async {
    final remove = (emoji ?? '').trim().isEmpty;
    final r = await _post(
      _uri('/chat/messages/${Uri.encodeComponent(messageId)}/reactions'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode({
        'device_id': deviceId,
        if (!remove) 'emoji': emoji!.trim(),
        if (remove) 'remove': true,
      }),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'setMessageReaction',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
  }

  Future<Map<String, String>> fetchMessageReactions({
    required String deviceId,
    required String messageId,
  }) async {
    final r = await _get(
      _uri(
        '/chat/messages/${Uri.encodeComponent(messageId)}/reactions',
        {'device_id': deviceId},
      ),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'fetchMessageReactions',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final arr = jsonDecode(r.body) as List;
    final out = <String, String>{};
    for (final item in arr.whereType<Map>()) {
      final actor = (item['actor_device_id'] ?? '').toString().trim();
      final reaction = (item['emoji'] ?? '').toString().trim();
      if (actor.isNotEmpty && reaction.isNotEmpty) {
        out[actor] = reaction;
      }
    }
    return out;
  }

  /// Cycle 4: set or unset a reaction on a group message. The
  /// `emoji` arg is the new emoji choice — passing an empty string
  /// is interpreted as "remove the current reaction" (server's
  /// `remove: true` semantics). Toggle pattern handled by the chat
  /// page: tap a chip you already placed → call with empty emoji.
  Future<void> setGroupMessageReaction({
    required String deviceId,
    required String groupId,
    required String messageId,
    String? emoji,
  }) async {
    final remove = (emoji ?? '').trim().isEmpty;
    final r = await _post(
      _uri(
        '/chat/groups/${Uri.encodeComponent(groupId)}/messages/${Uri.encodeComponent(messageId)}/reactions',
      ),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode({
        'device_id': deviceId,
        if (!remove) 'emoji': emoji!.trim(),
        if (remove) 'remove': true,
      }),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'setGroupMessageReaction',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
  }

  /// Cycle 5 wave 1: list every prior revision of a direct message.
  /// Each entry carries the encrypted ciphertext + key material so
  /// the client can decrypt and show the prior body under "View edit
  /// history".
  Future<List<Map<String, Object?>>> listMessageEditHistory({
    required String deviceId,
    required String messageId,
  }) async {
    final r = await _get(
      _uri(
        '/chat/messages/${Uri.encodeComponent(messageId)}/edit_history',
        {'device_id': deviceId},
      ),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'listMessageEditHistory',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final raw = jsonDecode(r.body);
    if (raw is! List) return const <Map<String, Object?>>[];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, Object?>.from(m))
        .toList(growable: false);
  }

  /// Cycle 5 wave 1: send a typing-state signal to a peer. The
  /// recipient's chat header receives the event via Redis pubsub and
  /// renders a "typing…" indicator. `kind` is either `started` or
  /// `stopped` — the client debounces these to ~3s minimum on its
  /// composer so we never spam the server.
  Future<void> postTypingSignal({
    required String deviceId,
    required String peerId,
    required String kind,
  }) async {
    final r = await _post(
      _uri('/chat/messages/typing'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode({
        'device_id': deviceId,
        'peer_id': peerId,
        'kind': kind,
      }),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'postTypingSignal',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
  }

  /// Cycle 5 wave 2: group analog of [postTypingSignal]. Fan-out to
  /// every group member happens server-side; client just emits one
  /// HTTP call per state transition.
  Future<void> postGroupTypingSignal({
    required String deviceId,
    required String groupId,
    required String kind,
  }) async {
    final r = await _post(
      _uri('/chat/groups/${Uri.encodeComponent(groupId)}/typing'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode({
        'device_id': deviceId,
        'kind': kind,
      }),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'postGroupTypingSignal',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
  }

  /// Cycle 5 wave 3: cheap aggregate stats for a 1:1 conversation,
  /// used by the chat-list tile to render unread/pinned badges
  /// without fetching the full inbox. Returns null on any failure —
  /// callers should treat null as "show the stale tile until next
  /// refresh" rather than as an error worth surfacing.
  Future<Map<String, Object?>?> fetchConversationStats({
    required String deviceId,
    required String peerId,
  }) async {
    try {
      final r = await _get(
        _uri('/chat/conversation_stats', {
          'device_id': deviceId,
          'peer_id': peerId,
        }),
        headers: await _headers(chatDeviceId: deviceId),
      );
      if (r.statusCode >= 400) return null;
      final raw = jsonDecode(r.body);
      if (raw is! Map) return null;
      return Map<String, Object?>.from(raw);
    } catch (_) {
      return null;
    }
  }

  /// Cycle 5 wave 4: group analog of [fetchConversationStats].
  Future<Map<String, Object?>?> fetchGroupConversationStats({
    required String deviceId,
    required String groupId,
  }) async {
    try {
      final r = await _get(
        _uri(
          '/chat/groups/${Uri.encodeComponent(groupId)}/conversation_stats',
          {'device_id': deviceId},
        ),
        headers: await _headers(chatDeviceId: deviceId),
      );
      if (r.statusCode >= 400) return null;
      final raw = jsonDecode(r.body);
      if (raw is! Map) return null;
      return Map<String, Object?>.from(raw);
    } catch (_) {
      return null;
    }
  }

  /// Cycle 7: snooze a 1:1 conversation for `seconds`. Pass
  /// `seconds: 0` to clear. Server caps at 30 days. Optional `reason`
  /// is a short tag like "in meeting" that renders in the chat-list
  /// tile while the snooze is active.
  Future<void> setConversationSnooze({
    required String deviceId,
    required String peerId,
    required int seconds,
    String? reason,
  }) async {
    final body = <String, Object?>{
      'device_id': deviceId,
      'peer_id': peerId,
      'seconds': seconds,
    };
    if (reason != null && reason.trim().isNotEmpty) {
      body['reason'] = reason.trim();
    }
    final r = await _post(
      _uri('/chat/messages/snooze'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode(body),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'setConversationSnooze',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
  }

  /// Cycle 7: snooze a group conversation. Same shape as the direct
  /// variant minus `peer_id` (the group_id is in the URL path).
  Future<void> setGroupConversationSnooze({
    required String deviceId,
    required String groupId,
    required int seconds,
    String? reason,
  }) async {
    final body = <String, Object?>{
      'device_id': deviceId,
      'seconds': seconds,
    };
    if (reason != null && reason.trim().isNotEmpty) {
      body['reason'] = reason.trim();
    }
    final r = await _post(
      _uri('/chat/groups/${Uri.encodeComponent(groupId)}/snooze'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode(body),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'setGroupConversationSnooze',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
  }

  /// Cycle 7: list every currently-active snooze for the caller.
  /// Used by the chat list to render snooze badges on tiles without
  /// extra per-tile lookups.
  Future<List<Map<String, Object?>>> listConversationSnoozes({
    required String deviceId,
  }) async {
    final r = await _get(
      _uri('/chat/messages/snoozes', {'device_id': deviceId}),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'listConversationSnoozes',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final raw = jsonDecode(r.body);
    if (raw is! List) return const <Map<String, Object?>>[];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, Object?>.from(m))
        .toList(growable: false);
  }

  /// Cycle 8: upsert a saved reply template (canned response). Server
  /// enforces `slug` 1-32, `label` 1-64, `body` 1-2048, max 32
  /// replies per device.
  Future<void> setSavedReply({
    required String deviceId,
    required String slug,
    required String label,
    required String body,
  }) async {
    final r = await _post(
      _uri('/chat/messages/saved_replies'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode({
        'device_id': deviceId,
        'slug': slug,
        'label': label,
        'body': body,
      }),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'setSavedReply',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
  }

  /// Cycle 8: delete a saved reply by slug.
  Future<void> deleteSavedReply({
    required String deviceId,
    required String slug,
  }) async {
    final r = await _delete(
      _uri('/chat/messages/saved_replies/${Uri.encodeComponent(slug)}',
          {'device_id': deviceId}),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'deleteSavedReply',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
  }

  /// Cycle 8: list the caller's saved replies, alphabetised by label.
  Future<List<Map<String, Object?>>> listSavedReplies({
    required String deviceId,
  }) async {
    final r = await _get(
      _uri('/chat/messages/saved_replies', {'device_id': deviceId}),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'listSavedReplies',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final raw = jsonDecode(r.body);
    if (raw is! List) return const <Map<String, Object?>>[];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, Object?>.from(m))
        .toList(growable: false);
  }

  // ────────────────── Cycle 8 — scheduled messages ──────────────────

  /// Cycle 10: schedule a message for future delivery, holding the
  /// FULL ratchet envelope on the server so the delivery worker
  /// (`spawn_scheduled_message_delivery_worker` in chat_service Rust)
  /// can INSERT directly into `chat_messages` at the scheduled time.
  /// The caller pre-encrypts via [prepareDirectSendEnvelope] and
  /// hands the envelope here together with the recipient and the
  /// `scheduledFor` UTC timestamp.
  ///
  /// Cycle 8/9 v1 took a single opaque `payload` argument; that
  /// shape is gone (migration 0042 dropped the matching column).
  ///
  /// Returns the server-assigned id + canonical RFC-3339 scheduled
  /// timestamp. Throws [ChatHttpException] on validation / per-
  /// device-cap failures (400 / 409).
  Future<Map<String, Object?>> scheduleMessage({
    required String deviceId,
    String? peerId,
    String? groupId,
    required ChatDirectSendEnvelope envelope,
    required DateTime scheduledFor,
  }) async {
    final body = <String, Object?>{
      'device_id': deviceId,
      if (peerId != null && peerId.isNotEmpty) 'peer_id': peerId,
      if (groupId != null && groupId.isNotEmpty) 'group_id': groupId,
      'protocol_version': envelope.protocolVersion,
      'sender_pubkey_b64': envelope.senderPubkeyB64,
      if (envelope.senderDhPubB64 != null)
        'sender_dh_pub_b64': envelope.senderDhPubB64,
      'nonce_b64': envelope.nonceB64,
      'box_b64': envelope.boxB64,
      'sealed_sender': envelope.sealedSender,
      if (envelope.senderHint != null) 'sender_hint': envelope.senderHint,
      if (envelope.keyId != null) 'key_id': envelope.keyId,
      if (envelope.prevKeyId != null) 'prev_key_id': envelope.prevKeyId,
      if (envelope.expireAfterSeconds != null)
        'expire_after_seconds': envelope.expireAfterSeconds,
      'scheduled_for': scheduledFor.toUtc().toIso8601String(),
    };
    final r = await _post(
      _uri('/chat/messages/scheduled'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode(body),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'scheduleMessage',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final raw = jsonDecode(r.body);
    if (raw is! Map) return const <String, Object?>{};
    return Map<String, Object?>.from(raw);
  }

  /// Cycle 8: list the caller's scheduled messages. By default
  /// returns only pending rows (not yet sent / not cancelled). Pass
  /// `dueOnly: true` for the client's dequeue tick — the server
  /// filters to rows whose `scheduledFor <= NOW()`. Pass
  /// `includeTerminal: true` for the audit view that also surfaces
  /// already-sent and cancelled rows.
  Future<List<Map<String, Object?>>> listScheduledMessages({
    required String deviceId,
    bool includeTerminal = false,
    bool dueOnly = false,
  }) async {
    final query = <String, String>{'device_id': deviceId};
    if (includeTerminal) query['include_terminal'] = 'true';
    if (dueOnly) query['due_only'] = 'true';
    final r = await _get(
      _uri('/chat/messages/scheduled', query),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'listScheduledMessages',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final raw = jsonDecode(r.body);
    if (raw is! List) return const <Map<String, Object?>>[];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, Object?>.from(m))
        .toList(growable: false);
  }

  /// Cycle 8: cancel a pending scheduled message. Idempotent — a
  /// double-cancel returns 200 if the row exists. 404 only if the id
  /// doesn't exist for the caller.
  Future<void> cancelScheduledMessage({
    required String deviceId,
    required String id,
  }) async {
    final r = await _delete(
      _uri('/chat/messages/scheduled/${Uri.encodeComponent(id)}',
          {'device_id': deviceId}),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'cancelScheduledMessage',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
  }

  // ────────────────────── Cycle 14 — polls ──────────────────────

  /// Cycle 14: attach a poll to an already-sent chat message. The
  /// caller posts the regular chat message first (the message body
  /// is the opaque poll-pointer envelope), captures the new message
  /// id, then calls this with the same id + the server-visible
  /// question + options. The server enforces the per-poll caps
  /// (2..=10 options, question ≤ 500 chars).
  Future<Map<String, Object?>> createPoll({
    required String deviceId,
    required String messageId,
    required String question,
    required List<String> options,
    bool multiSelect = false,
    bool anonymous = false,
    DateTime? closesAt,
  }) async {
    final body = <String, Object?>{
      'device_id': deviceId,
      'message_id': messageId,
      'question': question,
      'options': options,
      'multi_select': multiSelect,
      'anonymous': anonymous,
      if (closesAt != null) 'closes_at': closesAt.toUtc().toIso8601String(),
    };
    final r = await _post(
      _uri('/chat/messages/${Uri.encodeComponent(messageId)}/poll'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode(body),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'createPoll',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final raw = jsonDecode(r.body);
    if (raw is! Map) return const <String, Object?>{};
    return Map<String, Object?>.from(raw);
  }

  /// Cycle 14: cast / change / clear votes for a poll. Empty
  /// `optionIdxs` clears any prior votes. Idempotent — re-sending
  /// the same list is a no-op server-side.
  Future<Map<String, Object?>> votePoll({
    required String deviceId,
    required String pollId,
    required List<int> optionIdxs,
  }) async {
    final r = await _post(
      _uri('/chat/polls/${Uri.encodeComponent(pollId)}/vote'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode(<String, Object?>{
        'device_id': deviceId,
        'option_idxs': optionIdxs,
      }),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'votePoll',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final raw = jsonDecode(r.body);
    if (raw is! Map) return const <String, Object?>{};
    return Map<String, Object?>.from(raw);
  }

  /// Cycle 15: fetch a poll by the anchor chat-message id. Returns
  /// the same shape as `getPoll`; throws `ChatHttpException` with
  /// `statusCode == 404` when the message has no attached poll
  /// (callers use that 404 as the "this is not a poll" signal in
  /// the bubble dispatcher's lazy detection).
  Future<Map<String, Object?>> getPollByMessage({
    required String deviceId,
    required String messageId,
  }) async {
    final r = await _get(
      _uri('/chat/messages/${Uri.encodeComponent(messageId)}/poll',
          {'device_id': deviceId}),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'getPollByMessage',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final raw = jsonDecode(r.body);
    if (raw is! Map) return const <String, Object?>{};
    return Map<String, Object?>.from(raw);
  }

  /// Cycle 14: fetch the poll header + tally + the caller's current
  /// votes. Returns the same shape the bubble widget renders.
  Future<Map<String, Object?>> getPoll({
    required String deviceId,
    required String pollId,
  }) async {
    final r = await _get(
      _uri('/chat/polls/${Uri.encodeComponent(pollId)}',
          {'device_id': deviceId}),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'getPoll',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final raw = jsonDecode(r.body);
    if (raw is! Map) return const <String, Object?>{};
    return Map<String, Object?>.from(raw);
  }

  // ────────────────────── Cycle 29 — stories ──────────────────────

  /// Cycle 29: post a 24h ephemeral story. v1 stores plaintext
  /// text + base64 attachment server-side. Returns the new story id.
  Future<Map<String, Object?>> createStory({
    required String deviceId,
    String kind = 'text',
    String? text,
    String? attachmentB64,
    String? attachmentMime,
  }) async {
    final body = <String, Object?>{
      'device_id': deviceId,
      'kind': kind,
      if (text != null && text.trim().isNotEmpty) 'text': text,
      if (attachmentB64 != null && attachmentB64.isNotEmpty)
        'attachment_b64': attachmentB64,
      if (attachmentMime != null && attachmentMime.isNotEmpty)
        'attachment_mime': attachmentMime,
    };
    final r = await _post(
      _uri('/chat/stories'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode(body),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'createStory',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final raw = jsonDecode(r.body);
    if (raw is! Map) return const <String, Object?>{};
    return Map<String, Object?>.from(raw);
  }

  /// Cycle 29: list visible stories (live = not deleted, not yet
  /// expired). The server returns up to 256 rows; the chat list's
  /// "status" strip filters to the latest from each author.
  Future<List<Map<String, Object?>>> listStories({
    required String deviceId,
  }) async {
    final r = await _get(
      _uri('/chat/stories', {'device_id': deviceId}),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'listStories',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final raw = jsonDecode(r.body);
    if (raw is! List) return const <Map<String, Object?>>[];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, Object?>.from(m))
        .toList(growable: false);
  }

  /// Cycle 29: record that this device has viewed a story.
  /// Idempotent — re-posting is a no-op.
  Future<void> markStoryViewed({
    required String deviceId,
    required String storyId,
  }) async {
    final r = await _post(
      _uri('/chat/stories/${Uri.encodeComponent(storyId)}/view'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode(<String, Object?>{'device_id': deviceId}),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'markStoryViewed',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
  }

  /// Cycle 29: delete one of the caller's own stories. Soft-delete
  /// (server stamps `deleted_at`); rows still exist for audit + the
  /// retention sweep prunes them later.
  Future<void> deleteStory({
    required String deviceId,
    required String storyId,
  }) async {
    final r = await _delete(
      _uri('/chat/stories/${Uri.encodeComponent(storyId)}',
          {'device_id': deviceId}),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'deleteStory',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
  }

  /// Cycle 33: react to a story with a single emoji. Upserts; sending
  /// a different emoji replaces the prior one.
  Future<void> reactToStory({
    required String deviceId,
    required String storyId,
    required String emoji,
  }) async {
    final r = await _post(
      _uri('/chat/stories/${Uri.encodeComponent(storyId)}/react'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode(<String, Object?>{
        'device_id': deviceId,
        'emoji': emoji,
      }),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'reactToStory',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
  }

  /// Cycle 33: clear the caller's reaction on a story (idempotent).
  Future<void> clearStoryReaction({
    required String deviceId,
    required String storyId,
  }) async {
    final r = await _delete(
      _uri('/chat/stories/${Uri.encodeComponent(storyId)}/react',
          {'device_id': deviceId}),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'clearStoryReaction',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
  }

  /// Cycle 55: fetch the caller's own profile. Returns an empty map
  /// when the caller has never set a profile (server returns 200 with
  /// just `{device_id}`).
  Future<Map<String, Object?>> getMyProfile({
    required String deviceId,
  }) async {
    final r = await _get(
      _uri('/chat/profile', {'device_id': deviceId}),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'getMyProfile',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final decoded = jsonDecode(r.body);
    if (decoded is! Map) return const <String, Object?>{};
    return decoded.cast<String, Object?>();
  }

  /// Cycle 55: upsert the caller's profile. Pass `null` for any field
  /// to leave it untouched. Set `clearAvatar` / `clearStatus` to drop
  /// the avatar or the status fields respectively.
  ///
  /// Cycle 58 added `statusEmoji` / `statusText` / `clearStatus`.
  Future<void> setMyProfile({
    required String deviceId,
    String? displayName,
    String? avatarB64,
    String? avatarMime,
    bool clearAvatar = false,
    String? statusEmoji,
    String? statusText,
    bool clearStatus = false,
  }) async {
    final body = <String, Object?>{'device_id': deviceId};
    if (displayName != null) body['display_name'] = displayName;
    if (avatarB64 != null) body['avatar_b64'] = avatarB64;
    if (avatarMime != null) body['avatar_mime'] = avatarMime;
    if (clearAvatar) body['clear_avatar'] = true;
    if (statusEmoji != null) body['status_emoji'] = statusEmoji;
    if (statusText != null) body['status_text'] = statusText;
    if (clearStatus) body['clear_status'] = true;
    final r = await _post(
      _uri('/chat/profile'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode(body),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'setMyProfile',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
  }

  /// Cycle 63: set / clear the per-conversation notification preview
  /// pref. Pass `previewMode: 'default'` to clear the override.
  Future<void> setConversationNotificationPref({
    required String deviceId,
    String? peerId,
    String? groupId,
    required String previewMode,
  }) async {
    final body = <String, Object?>{
      'device_id': deviceId,
      'preview_mode': previewMode,
    };
    if (peerId != null && peerId.isNotEmpty) body['peer_id'] = peerId;
    if (groupId != null && groupId.isNotEmpty) body['group_id'] = groupId;
    final r = await _post(
      _uri('/chat/notifications/prefs'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode(body),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'setConversationNotificationPref',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
  }

  /// Cycle 63: list the caller's per-conversation notification prefs.
  Future<List<Map<String, Object?>>> listConversationNotificationPrefs({
    required String deviceId,
  }) async {
    final r = await _get(
      _uri('/chat/notifications/prefs', {'device_id': deviceId}),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'listConversationNotificationPrefs',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final decoded = jsonDecode(r.body);
    if (decoded is! List) return const <Map<String, Object?>>[];
    return decoded
        .whereType<Map<Object?, Object?>>()
        .map((m) => m.cast<String, Object?>())
        .toList(growable: false);
  }

  /// Cycle 55: batch-fetch peer profiles.
  Future<List<Map<String, Object?>>> listPeerProfiles({
    required String deviceId,
    required List<String> peerIds,
  }) async {
    final r = await _post(
      _uri('/chat/profiles/list'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode(<String, Object?>{
        'device_id': deviceId,
        'peer_ids': peerIds,
      }),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'listPeerProfiles',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final decoded = jsonDecode(r.body);
    if (decoded is! List) return const <Map<String, Object?>>[];
    return decoded
        .whereType<Map<Object?, Object?>>()
        .map((m) => m.cast<String, Object?>())
        .toList(growable: false);
  }

  /// Cycle 37: heartbeat the caller's presence. Idempotent.
  Future<void> presenceHeartbeat({required String deviceId}) async {
    final r = await _post(
      _uri('/chat/presence/heartbeat'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode(<String, Object?>{'device_id': deviceId}),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'presenceHeartbeat',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
  }

  /// Cycle 37: batch-fetch last-seen-at for a set of peer device-ids.
  Future<List<Map<String, Object?>>> listPeerPresence({
    required String deviceId,
    required List<String> peerIds,
  }) async {
    final r = await _post(
      _uri('/chat/presence/list'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode(<String, Object?>{
        'device_id': deviceId,
        'peer_ids': peerIds,
      }),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'listPeerPresence',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final decoded = jsonDecode(r.body);
    if (decoded is! List) return const <Map<String, Object?>>[];
    return decoded
        .whereType<Map<Object?, Object?>>()
        .map((m) => m.cast<String, Object?>())
        .toList(growable: false);
  }

  /// Cycle 34: list who viewed one of the caller's own stories.
  /// Server returns 403 if the caller is not the story author.
  Future<List<Map<String, Object?>>> listStoryViews({
    required String deviceId,
    required String storyId,
  }) async {
    final r = await _get(
      _uri('/chat/stories/${Uri.encodeComponent(storyId)}/views',
          {'device_id': deviceId}),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'listStoryViews',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final decoded = jsonDecode(r.body);
    if (decoded is! List) return const <Map<String, Object?>>[];
    return decoded
        .whereType<Map<Object?, Object?>>()
        .map((m) => m.cast<String, Object?>())
        .toList(growable: false);
  }

  /// Cycle 33: list who reacted to one of the caller's own stories.
  /// Server returns 403 if the caller is not the story author.
  Future<List<Map<String, Object?>>> listStoryReactions({
    required String deviceId,
    required String storyId,
  }) async {
    final r = await _get(
      _uri('/chat/stories/${Uri.encodeComponent(storyId)}/reactions',
          {'device_id': deviceId}),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'listStoryReactions',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final decoded = jsonDecode(r.body);
    if (decoded is! List) return const <Map<String, Object?>>[];
    return decoded
        .whereType<Map<Object?, Object?>>()
        .map((m) => m.cast<String, Object?>())
        .toList(growable: false);
  }

  /// Cycle 14: close a poll. Only the creator can close; idempotent
  /// for already-closed polls.
  Future<void> closePoll({
    required String deviceId,
    required String pollId,
  }) async {
    final r = await _delete(
      _uri('/chat/polls/${Uri.encodeComponent(pollId)}',
          {'device_id': deviceId}),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'closePoll',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
  }

  /// Cycle 8: confirm a scheduled message was delivered through the
  /// regular send path. The client calls this after running the
  /// drained-due payload through `send_message` so the audit row
  /// transitions from pending to terminal. `deliveredMsgId` is
  /// stored as the back-pointer to the resulting `chat_messages`
  /// row when provided.
  Future<void> markScheduledMessageSent({
    required String deviceId,
    required String id,
    String? deliveredMsgId,
  }) async {
    final body = <String, Object?>{
      'device_id': deviceId,
      if (deliveredMsgId != null && deliveredMsgId.isNotEmpty)
        'delivered_msg_id': deliveredMsgId,
    };
    final r = await _post(
      _uri('/chat/messages/scheduled/${Uri.encodeComponent(id)}/sent'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode(body),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'markScheduledMessageSent',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
  }

  /// Cycle 6: set / update / remove a personal message bookmark.
  /// `bookmarked: true` saves (with optional `note`); `false` clears.
  /// `kind` is `'direct'` or `'group'` so the server picks the right
  /// ownership check.
  Future<void> setMessageBookmark({
    required String deviceId,
    required String messageId,
    required bool bookmarked,
    String? note,
    String kind = 'direct',
  }) async {
    final body = <String, Object?>{
      'device_id': deviceId,
      'bookmarked': bookmarked,
    };
    if (bookmarked) {
      body['kind'] = kind;
      final trimmed = (note ?? '').trim();
      if (trimmed.isNotEmpty) body['note'] = trimmed;
    }
    final r = await _post(
      _uri('/chat/messages/${Uri.encodeComponent(messageId)}/bookmark'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode(body),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'setMessageBookmark',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
  }

  /// Cycle 6: list the caller's bookmarks, newest-first. Optional
  /// `kind` filter restricts to direct or group only.
  Future<List<Map<String, Object?>>> listMessageBookmarks({
    required String deviceId,
    String? kind,
    int limit = 50,
  }) async {
    final q = <String, String>{
      'device_id': deviceId,
      'limit': limit.toString(),
    };
    if (kind != null && kind.trim().isNotEmpty) {
      q['kind'] = kind.trim();
    }
    final r = await _get(
      _uri('/chat/messages/bookmarks', q),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'listMessageBookmarks',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final raw = jsonDecode(r.body);
    if (raw is! List) return const <Map<String, Object?>>[];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, Object?>.from(m))
        .toList(growable: false);
  }

  /// Cycle 5 wave 4: pin / unpin a group message in the caller's
  /// personal pin list. Server enforces a per-device cap; a 409 on
  /// pin means "too many pinned" and the UI should surface a nudge
  /// to unpin one first.
  Future<void> setGroupMessagePin({
    required String deviceId,
    required String groupId,
    required String messageId,
    required bool pinned,
  }) async {
    final r = await _post(
      _uri(
        '/chat/groups/${Uri.encodeComponent(groupId)}/messages/${Uri.encodeComponent(messageId)}/pin',
      ),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode({
        'device_id': deviceId,
        'pinned': pinned,
      }),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'setGroupMessagePin',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
  }

  /// Cycle 5 wave 4: list my pinned group messages, optionally
  /// filtered to one group. Returns `(group_id, message_id, pinned_at)`
  /// triples ordered most-recent-first.
  Future<List<Map<String, Object?>>> listGroupMessagePins({
    required String deviceId,
    String? groupId,
  }) async {
    final q = <String, String>{'device_id': deviceId};
    if (groupId != null && groupId.trim().isNotEmpty) {
      q['group_id'] = groupId.trim();
    }
    final r = await _get(
      _uri('/chat/groups/message_pins', q),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'listGroupMessagePins',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final raw = jsonDecode(r.body);
    if (raw is! List) return const <Map<String, Object?>>[];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, Object?>.from(m))
        .toList(growable: false);
  }

  Future<void> setMessagePin({
    required String deviceId,
    required String messageId,
    required bool pinned,
  }) async {
    final r = await _post(
      _uri('/chat/messages/${Uri.encodeComponent(messageId)}/pin'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode({
        'device_id': deviceId,
        'pinned': pinned,
      }),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'setMessagePin',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
  }

  Future<Map<String, Set<String>>> fetchPinnedMessages({
    required String deviceId,
    String? peerId,
    int limit = 200,
  }) async {
    final qp = <String, String>{
      'device_id': deviceId,
      'limit': '$limit',
      if ((peerId ?? '').trim().isNotEmpty) 'peer_id': peerId!.trim(),
    };
    final r = await _get(
      _uri('/chat/messages/pins', qp),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'fetchPinnedMessages',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final arr = jsonDecode(r.body) as List;
    final out = <String, Set<String>>{};
    for (final item in arr.whereType<Map>()) {
      final peer = (item['peer_id'] ?? '').toString().trim();
      final message = (item['message_id'] ?? '').toString().trim();
      if (peer.isEmpty || message.isEmpty) continue;
      out.putIfAbsent(peer, () => <String>{}).add(message);
    }
    return out;
  }

  Future<void> reportMessage({
    required String deviceId,
    required String messageId,
    String reason = 'abuse',
    String? note,
  }) async {
    final r = await _post(
      _uri('/chat/messages/${Uri.encodeComponent(messageId)}/report'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode({
        'device_id': deviceId,
        'reason': reason,
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      }),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'reportMessage',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
  }

  Future<void> deleteMessage({
    required String deviceId,
    required String messageId,
    bool deleteForEveryone = false,
    String? reason,
  }) async {
    final r = await _post(
      _uri('/chat/messages/${Uri.encodeComponent(messageId)}/delete'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode({
        'device_id': deviceId,
        'delete_for_everyone': deleteForEveryone,
        if ((reason ?? '').trim().isNotEmpty) 'reason': reason!.trim(),
      }),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'deleteMessage',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
  }

  Future<List<ChatConversationEvent>> fetchConversationEvents({
    required String deviceId,
    int afterEventId = 0,
    int limit = 100,
  }) async {
    final r = await _get(
      _uri('/chat/events', {
        'device_id': deviceId,
        'after_event_id': '$afterEventId',
        'limit': '$limit',
      }),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'fetchConversationEvents',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final arr = jsonDecode(r.body) as List;
    return arr
        .whereType<Map>()
        .map((m) => ChatConversationEvent.fromJson(m.cast<String, Object?>()))
        .where((event) => event.eventId > 0)
        .toList(growable: false);
  }

  Future<void> saveCallLog({
    required String deviceId,
    required ChatCallLogEntry entry,
  }) async {
    final r = await _post(
      _uri('/chat/calls/logs'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode({
        'device_id': deviceId,
        'call_id': entry.id,
        'peer_id': entry.peerId,
        'direction': entry.direction,
        'kind': entry.kind == 'audio' ? 'voice' : entry.kind,
        'accepted': entry.accepted,
        'duration_seconds': entry.duration.inSeconds,
        'started_at': entry.ts.toUtc().toIso8601String(),
      }),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'saveCallLog',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
  }

  Future<List<ChatCallLogEntry>> fetchCallLogs({
    required String deviceId,
    String? peerId,
    int limit = 100,
  }) async {
    final qp = <String, String>{
      'device_id': deviceId,
      'limit': '$limit',
      if ((peerId ?? '').trim().isNotEmpty) 'peer_id': peerId!.trim(),
    };
    final r = await _get(
      _uri('/chat/calls/logs', qp),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'fetchCallLogs',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final arr = jsonDecode(r.body) as List;
    return arr
        .whereType<Map>()
        .map((m) => ChatCallLogEntry.fromMap(m.cast<String, Object?>()))
        .toList();
  }

  Future<void> saveVoiceTranscript({
    required String deviceId,
    required String messageId,
    required String transcript,
    String? language,
    double? confidence,
  }) async {
    final r = await _post(
      _uri('/chat/voice/transcripts'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode({
        'device_id': deviceId,
        'message_id': messageId,
        'transcript': transcript,
        if ((language ?? '').trim().isNotEmpty) 'language': language!.trim(),
        if (confidence != null) 'confidence': confidence,
      }),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'saveVoiceTranscript',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
  }

  Future<String?> fetchVoiceTranscript({
    required String deviceId,
    required String messageId,
  }) async {
    final r = await _get(
      _uri('/chat/voice/transcripts', {
        'device_id': deviceId,
        'message_id': messageId,
      }),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode == 404) return null;
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'fetchVoiceTranscript',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final j = jsonDecode(r.body) as Map<String, Object?>;
    return (j['transcript'] ?? '').toString();
  }

  Future<ChatVoiceTranscriptJob> requestVoiceTranscriptJob({
    required String deviceId,
    required String messageId,
    String? language,
  }) async {
    final r = await _post(
      _uri('/chat/voice/transcript_jobs'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode({
        'device_id': deviceId,
        'message_id': messageId,
        if ((language ?? '').trim().isNotEmpty) 'language': language!.trim(),
      }),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'requestVoiceTranscriptJob',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    return ChatVoiceTranscriptJob.fromJson(
      jsonDecode(r.body) as Map<String, Object?>,
    );
  }

  Future<List<ChatVoiceTranscriptJob>> fetchVoiceTranscriptJobs({
    required String deviceId,
    String? status,
    int limit = 100,
  }) async {
    final qp = <String, String>{
      'device_id': deviceId,
      'limit': '$limit',
      if ((status ?? '').trim().isNotEmpty) 'status': status!.trim(),
    };
    final r = await _get(
      _uri('/chat/voice/transcript_jobs', qp),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'fetchVoiceTranscriptJobs',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final arr = jsonDecode(r.body) as List;
    return arr
        .whereType<Map>()
        .map((m) => ChatVoiceTranscriptJob.fromJson(m.cast<String, Object?>()))
        .toList(growable: false);
  }

  Future<void> setBlock({
    required String deviceId,
    required String peerId,
    required bool blocked,
    bool hidden = false,
  }) async {
    final r = await _post(
      _uri('/chat/devices/${Uri.encodeComponent(deviceId)}/block'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode({
        'peer_id': peerId,
        'blocked': blocked,
        'hidden': hidden,
      }),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'block update',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
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
    final r = await _post(
      _uri('/chat/devices/${Uri.encodeComponent(deviceId)}/prefs'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode(body),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'prefs update',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
  }

  Future<List<ChatContactPrefs>> fetchPrefs({
    required String deviceId,
    int limit = 200,
    String? afterPeerId,
  }) async {
    final qp = <String, String>{'limit': '$limit'};
    final normalizedAfterPeerId = afterPeerId?.trim() ?? '';
    if (normalizedAfterPeerId.isNotEmpty) {
      qp['after_peer_id'] = normalizedAfterPeerId;
    }
    final r = await _get(
      _uri('/chat/devices/${Uri.encodeComponent(deviceId)}/prefs', qp),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'prefs',
        statusCode: r.statusCode,
        body: r.body,
      );
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

  Future<List<ChatContactPrefs>> fetchPrefsPaged({
    required String deviceId,
    int batchSize = 200,
    int maxPages = 25,
  }) async {
    final normalizedBatchSize = batchSize.clamp(1, 200);
    final normalizedMaxPages = maxPages < 1 ? 1 : maxPages;
    String? afterPeerId;
    final merged = <String, ChatContactPrefs>{};

    for (var page = 0; page < normalizedMaxPages; page++) {
      final items = await fetchPrefs(
        deviceId: deviceId,
        limit: normalizedBatchSize,
        afterPeerId: afterPeerId,
      );
      String? nextAfterPeerId;
      for (final item in items) {
        final peerId = item.peerId.trim();
        if (peerId.isEmpty) continue;
        merged[peerId] = item;
        if (nextAfterPeerId == null || peerId.compareTo(nextAfterPeerId) > 0) {
          nextAfterPeerId = peerId;
        }
      }
      if (items.length < normalizedBatchSize || nextAfterPeerId == null) {
        break;
      }
      if (nextAfterPeerId == afterPeerId) {
        break;
      }
      afterPeerId = nextAfterPeerId;
    }

    final prefs = merged.values.toList()
      ..sort((left, right) => left.peerId.compareTo(right.peerId));
    return prefs;
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
    final r = await _post(
      _uri('/chat/devices/${Uri.encodeComponent(deviceId)}/group_prefs'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode(body),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'group prefs update',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
  }

  Future<List<ChatGroupPrefs>> fetchGroupPrefs({
    required String deviceId,
    int limit = 200,
    String? afterGroupId,
  }) async {
    final qp = <String, String>{'limit': '$limit'};
    final normalizedAfterGroupId = afterGroupId?.trim() ?? '';
    if (normalizedAfterGroupId.isNotEmpty) {
      qp['after_group_id'] = normalizedAfterGroupId;
    }
    final r = await _get(
      _uri('/chat/devices/${Uri.encodeComponent(deviceId)}/group_prefs', qp),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'group prefs',
        statusCode: r.statusCode,
        body: r.body,
      );
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

  Future<List<ChatGroupPrefs>> fetchGroupPrefsPaged({
    required String deviceId,
    int batchSize = 200,
    int maxPages = 25,
  }) async {
    final normalizedBatchSize = batchSize.clamp(1, 200);
    final normalizedMaxPages = maxPages < 1 ? 1 : maxPages;
    String? afterGroupId;
    final merged = <String, ChatGroupPrefs>{};

    for (var page = 0; page < normalizedMaxPages; page++) {
      final items = await fetchGroupPrefs(
        deviceId: deviceId,
        limit: normalizedBatchSize,
        afterGroupId: afterGroupId,
      );
      String? nextAfterGroupId;
      for (final item in items) {
        final groupId = item.groupId.trim();
        if (groupId.isEmpty) continue;
        merged[groupId] = item;
        if (nextAfterGroupId == null ||
            groupId.compareTo(nextAfterGroupId) > 0) {
          nextAfterGroupId = groupId;
        }
      }
      if (items.length < normalizedBatchSize || nextAfterGroupId == null) {
        break;
      }
      if (nextAfterGroupId == afterGroupId) {
        break;
      }
      afterGroupId = nextAfterGroupId;
    }

    final prefs = merged.values.toList()
      ..sort((left, right) => left.groupId.compareTo(right.groupId));
    return prefs;
  }

  Future<ChatGroupPrefs?> fetchGroupPrefForGroup({
    required String deviceId,
    required String groupId,
    int batchSize = 200,
    int maxPages = 25,
  }) async {
    final normalizedGroupId = groupId.trim();
    if (normalizedGroupId.isEmpty) {
      return null;
    }
    final normalizedBatchSize = batchSize.clamp(1, 200);
    final normalizedMaxPages = maxPages < 1 ? 1 : maxPages;
    String? afterGroupId;

    for (var page = 0; page < normalizedMaxPages; page++) {
      final items = await fetchGroupPrefs(
        deviceId: deviceId,
        limit: normalizedBatchSize,
        afterGroupId: afterGroupId,
      );
      String? nextAfterGroupId;
      var passedTarget = false;
      for (final item in items) {
        final currentGroupId = item.groupId.trim();
        if (currentGroupId.isEmpty) continue;
        if (currentGroupId == normalizedGroupId) {
          return item;
        }
        if (currentGroupId.compareTo(normalizedGroupId) > 0) {
          passedTarget = true;
          break;
        }
        if (nextAfterGroupId == null ||
            currentGroupId.compareTo(nextAfterGroupId) > 0) {
          nextAfterGroupId = currentGroupId;
        }
      }
      if (passedTarget ||
          items.length < normalizedBatchSize ||
          nextAfterGroupId == null) {
        break;
      }
      if (nextAfterGroupId == afterGroupId) {
        break;
      }
      afterGroupId = nextAfterGroupId;
    }

    return null;
  }

  Future<void> registerPushToken({
    required String deviceId,
    required String token,
    String? platform,
  }) async {
    await _post(
      _uri('/chat/devices/${Uri.encodeComponent(deviceId)}/push_token'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode({
        'token': token,
        'platform': platform ?? 'flutter',
        'ts': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  Future<void> unregisterPushToken({
    required String deviceId,
  }) async {
    await _delete(
      _uri('/chat/devices/${Uri.encodeComponent(deviceId)}/push_token'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
    );
  }

  Stream<List<ChatMessage>> streamInbox({required String deviceId}) {
    _ws?.sink.close();
    final out = StreamController<List<ChatMessage>>();
    Future<void>(() async {
      try {
        _assertSecureTransportBase();
        final wsUri = _wsUri('/ws/chat/inbox', deviceId: deviceId);
        final headers = await shamellChatWebSocketHeadersForBaseUrl(
          _base,
          deviceId: deviceId,
        );
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
        final wsUri = _wsUri('/ws/chat/groups', deviceId: deviceId);
        final headers = await shamellChatWebSocketHeadersForBaseUrl(
          _base,
          deviceId: deviceId,
        );
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
                  final keyB64 = await store.loadGroupKey(
                    gid,
                    baseUrlOverride: _base,
                  );
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

  Stream<ChatTypingSignal> streamTypingSignals({required String deviceId}) {
    _wsTyping?.sink.close();
    final out = StreamController<ChatTypingSignal>();
    Future<void>(() async {
      try {
        _assertSecureTransportBase();
        final wsUri = _wsUri('/ws/chat/typing', deviceId: deviceId);
        final headers = await shamellChatWebSocketHeadersForBaseUrl(
          _base,
          deviceId: deviceId,
        );
        final channel = _connectWebSocket(
          wsUri,
          headers: headers,
        );
        _wsTyping = channel;
        late final StreamSubscription sub;
        sub = channel.stream.listen(
          (payload) {
            try {
              final decoded = jsonDecode(payload);
              Map<String, Object?>? map;
              if (decoded is Map<String, Object?>) {
                map = decoded;
              } else if (decoded is Map) {
                map = decoded.cast<String, Object?>();
              }
              final signal =
                  map == null ? null : ChatTypingSignal.fromJson(map);
              if (signal != null) {
                out.add(signal);
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
          if (identical(_wsTyping, channel)) {
            _wsTyping = null;
          }
        };
      } catch (e, st) {
        out.addError(e, st);
        await out.close();
      }
    });
    return out.stream;
  }

  Future<void> sendTypingSignal({
    required String deviceId,
    required bool isTyping,
    String? peerId,
    String? groupId,
  }) async {
    final channel = _wsTyping;
    if (channel == null) return;
    final trimmedPeerId = (peerId ?? '').trim();
    final trimmedGroupId = (groupId ?? '').trim();
    final isGroup = trimmedGroupId.isNotEmpty;
    if (!isGroup && trimmedPeerId.isEmpty) return;
    if (deviceId.trim().isEmpty) return;
    final payload = <String, Object?>{
      'type': 'typing',
      'scope': isGroup ? 'group' : 'direct',
      'is_typing': isTyping,
      if (isGroup) 'group_id': trimmedGroupId,
      if (!isGroup) 'peer_id': trimmedPeerId,
    };
    try {
      channel.sink.add(jsonEncode(payload));
    } catch (_) {}
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
    final r = await _post(
      _uri('/chat/groups/create'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: body,
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'group create',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    return ChatGroup.fromJson(jsonDecode(r.body) as Map<String, Object?>);
  }

  Future<List<ChatGroup>> listGroups({required String deviceId}) async {
    return listGroupsPaged(deviceId: deviceId, batchSize: 200, maxPages: 25);
  }

  Future<List<ChatGroup>> listGroupsPage({
    required String deviceId,
    int limit = 200,
    String? beforeCreatedAt,
    String? beforeId,
  }) async {
    final normalizedBeforeCreatedAt = beforeCreatedAt?.trim();
    final normalizedBeforeId = beforeId?.trim();
    final hasBeforeCreatedAt = normalizedBeforeCreatedAt != null &&
        normalizedBeforeCreatedAt.isNotEmpty;
    final hasBeforeId =
        normalizedBeforeId != null && normalizedBeforeId.isNotEmpty;
    if (hasBeforeCreatedAt != hasBeforeId) {
      throw ArgumentError('beforeCreatedAt and beforeId required together');
    }
    final qp = <String, String>{
      'device_id': deviceId,
      'limit': '${limit.clamp(1, 200)}',
    };
    if (hasBeforeCreatedAt && hasBeforeId) {
      qp['before_created_at'] = normalizedBeforeCreatedAt!;
      qp['before_id'] = normalizedBeforeId!;
    }
    final r = await _get(
      _uri('/chat/groups/list', qp),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'groups list',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final arr = jsonDecode(r.body) as List;
    return arr
        .whereType<Map>()
        .map((m) => ChatGroup.fromJson(m.cast<String, Object?>()))
        .toList();
  }

  Future<List<ChatGroup>> listGroupsPaged({
    required String deviceId,
    int batchSize = 200,
    int maxPages = 25,
  }) async {
    final merged = <String, ChatGroup>{};
    String? beforeCreatedAt;
    String? beforeId;
    final normalizedBatchSize = batchSize.clamp(1, 200);
    for (var pageIndex = 0; pageIndex < maxPages; pageIndex++) {
      final page = await listGroupsPage(
        deviceId: deviceId,
        limit: normalizedBatchSize,
        beforeCreatedAt: beforeCreatedAt,
        beforeId: beforeId,
      );
      for (final group in page) {
        final groupId = group.id.trim();
        if (groupId.isEmpty) continue;
        merged.putIfAbsent(groupId, () => group);
      }
      final cursor = _oldestGroupListCursor(page);
      if (page.length < normalizedBatchSize || cursor == null) {
        break;
      }
      if (cursor.createdAt == beforeCreatedAt && cursor.id == beforeId) {
        break;
      }
      beforeCreatedAt = cursor.createdAt;
      beforeId = cursor.id;
    }
    final groups = merged.values.toList()..sort(_compareGroupListCursorDesc);
    return groups;
  }

  Future<ChatGroup?> fetchGroupById({
    required String deviceId,
    required String groupId,
    int batchSize = 200,
    int? maxPages,
  }) async {
    final normalizedGroupId = groupId.trim();
    if (normalizedGroupId.isEmpty) {
      return null;
    }
    final normalizedBatchSize = batchSize.clamp(1, 200);
    final normalizedMaxPages =
        (maxPages == null || maxPages < 1) ? null : maxPages;
    final seenCursors = <String>{};
    String? beforeCreatedAt;
    String? beforeId;
    var pageIndex = 0;

    while (normalizedMaxPages == null || pageIndex < normalizedMaxPages) {
      pageIndex += 1;
      final page = await listGroupsPage(
        deviceId: deviceId,
        limit: normalizedBatchSize,
        beforeCreatedAt: beforeCreatedAt,
        beforeId: beforeId,
      );
      for (final group in page) {
        if (group.id.trim() == normalizedGroupId) {
          return group;
        }
      }
      if (page.length < normalizedBatchSize) {
        break;
      }
      final cursor = _oldestGroupListCursor(page);
      if (cursor == null) {
        break;
      }
      final cursorKey = '${cursor.createdAt}\n${cursor.id}';
      if (!seenCursors.add(cursorKey)) {
        break;
      }
      beforeCreatedAt = cursor.createdAt;
      beforeId = cursor.id;
    }

    return null;
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
    final r = await _post(
      _uri('/chat/groups/${Uri.encodeComponent(groupId)}/update'),
      headers: await _headers(json: true, chatDeviceId: actorId),
      body: body,
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'group update',
        statusCode: r.statusCode,
        body: r.body,
      );
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

    final keyB64 = await ChatLocalStore().loadGroupKey(
      groupId,
      baseUrlOverride: _base,
    );
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
    final r = await _post(
      _uri('/chat/groups/${Uri.encodeComponent(groupId)}/messages/send'),
      headers: await _headers(json: true, chatDeviceId: senderId),
      body: body,
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'group send',
        statusCode: r.statusCode,
        body: r.body,
      );
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
    String? sinceId,
    String? beforeCreatedAt,
    String? beforeId,
  }) async {
    final normalizedSinceIso = sinceIso?.trim() ?? '';
    final normalizedSinceId = sinceId?.trim() ?? '';
    final normalizedBeforeCreatedAt = beforeCreatedAt?.trim() ?? '';
    final normalizedBeforeId = beforeId?.trim() ?? '';
    if (normalizedSinceIso.isNotEmpty &&
        (normalizedBeforeCreatedAt.isNotEmpty ||
            normalizedBeforeId.isNotEmpty)) {
      throw ArgumentError(
        'before_created_at/before_id cannot be combined with since_iso/since_id',
      );
    }
    if ((normalizedBeforeCreatedAt.isEmpty) != (normalizedBeforeId.isEmpty)) {
      throw ArgumentError(
        'before_created_at and before_id are required together',
      );
    }
    final qp = <String, String>{'device_id': deviceId, 'limit': '$limit'};
    if (normalizedSinceIso.isNotEmpty) {
      qp['since_iso'] = normalizedSinceIso;
    }
    if (normalizedSinceId.isNotEmpty) {
      qp['since_id'] = normalizedSinceId;
    }
    if (normalizedBeforeCreatedAt.isNotEmpty) {
      qp['before_created_at'] = normalizedBeforeCreatedAt;
      qp['before_id'] = normalizedBeforeId;
    }
    final r = await _get(
      _uri('/chat/groups/${Uri.encodeComponent(groupId)}/messages/inbox', qp),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'group inbox',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final arr = jsonDecode(r.body) as List;
    var msgs = arr
        .whereType<Map>()
        .map((m) => ChatGroupMessage.fromJson(m.cast<String, Object?>()))
        .toList();
    try {
      final keyB64 = await ChatLocalStore().loadGroupKey(
        groupId,
        baseUrlOverride: _base,
      );
      if (keyB64 != null && keyB64.isNotEmpty) {
        final key = base64Decode(keyB64);
        if (key.length == 32) {
          msgs = msgs.map((m) => _maybeDecryptGroupMessage(m, key)).toList();
        }
      }
    } catch (_) {}
    return msgs;
  }

  Future<List<ChatGroupMessage>> fetchGroupInboxPaged({
    required String groupId,
    required String deviceId,
    String? sinceIso,
    String? sinceId,
    int batchSize = 200,
    int maxPages = 25,
    int? retainLatestCount,
  }) async {
    final normalizedBatchSize = batchSize.clamp(1, 200);
    final normalizedMaxPages = maxPages < 1 ? 1 : maxPages;
    var cursorIso = sinceIso?.trim();
    var cursorId = sinceId?.trim();
    final incremental = (cursorIso ?? '').isNotEmpty;
    String? beforeCreatedAt;
    String? beforeId;
    final collected = <ChatGroupMessage>[];
    final seenIds = <String>{};

    for (var page = 0; page < normalizedMaxPages; page++) {
      final items = await fetchGroupInbox(
        groupId: groupId,
        deviceId: deviceId,
        limit: normalizedBatchSize,
        sinceIso: incremental ? cursorIso : null,
        sinceId: incremental ? cursorId : null,
        beforeCreatedAt: incremental ? null : beforeCreatedAt,
        beforeId: incremental ? null : beforeId,
      );
      if (items.isEmpty) {
        break;
      }
      for (final item in items) {
        if (item.id.trim().isEmpty || !seenIds.add(item.id)) {
          continue;
        }
        collected.add(item);
      }
      if (!incremental) {
        final oldest = _oldestGroupCursorMessage(items);
        if (oldest == null) {
          break;
        }
        if (items.length < normalizedBatchSize) {
          break;
        }
        final nextBeforeCreatedAt = oldest.createdAt?.toUtc().toIso8601String();
        final nextBeforeId = oldest.id.trim();
        if ((nextBeforeCreatedAt ?? '').isEmpty || nextBeforeId.isEmpty) {
          break;
        }
        if (beforeCreatedAt == nextBeforeCreatedAt &&
            beforeId == nextBeforeId) {
          break;
        }
        beforeCreatedAt = nextBeforeCreatedAt;
        beforeId = nextBeforeId;
        continue;
      }
      final latest = _latestGroupCursorMessage(items);
      if (latest == null) {
        break;
      }
      final nextCursorIso = latest.createdAt!.toUtc().toIso8601String();
      final nextCursorId = latest.id;
      if (nextCursorIso == cursorIso && nextCursorId == cursorId) {
        break;
      }
      cursorIso = nextCursorIso;
      cursorId = nextCursorId;
      if (items.length < normalizedBatchSize) {
        break;
      }
    }

    collected.sort((a, b) {
      return _compareTimestampIdCursor(
        a.createdAt,
        a.id,
        b.createdAt,
        b.id,
      );
    });
    if (retainLatestCount != null &&
        retainLatestCount > 0 &&
        collected.length > retainLatestCount) {
      return collected.sublist(collected.length - retainLatestCount);
    }
    return collected;
  }

  Future<List<ChatGroupMember>> listGroupMembers({
    required String groupId,
    required String deviceId,
  }) async {
    return listGroupMembersPaged(groupId: groupId, deviceId: deviceId);
  }

  Future<List<ChatGroupMember>> listGroupMembersPage({
    required String groupId,
    required String deviceId,
    int limit = 200,
    String? afterJoinedAt,
    String? afterDeviceId,
  }) async {
    final normalizedAfterJoinedAt = afterJoinedAt?.trim();
    final normalizedAfterDeviceId = afterDeviceId?.trim();
    final hasAfterJoinedAt =
        normalizedAfterJoinedAt != null && normalizedAfterJoinedAt.isNotEmpty;
    final hasAfterDeviceId =
        normalizedAfterDeviceId != null && normalizedAfterDeviceId.isNotEmpty;
    if (hasAfterJoinedAt != hasAfterDeviceId) {
      throw ArgumentError('afterJoinedAt and afterDeviceId required together');
    }
    final qp = <String, String>{
      'device_id': deviceId,
      'limit': '${limit.clamp(1, 200)}',
    };
    if (hasAfterJoinedAt && hasAfterDeviceId) {
      qp['after_joined_at'] = normalizedAfterJoinedAt!;
      qp['after_device_id'] = normalizedAfterDeviceId!;
    }
    final r = await _get(
      _uri('/chat/groups/${Uri.encodeComponent(groupId)}/members', qp),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'group members',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    final arr = jsonDecode(r.body) as List;
    return arr
        .whereType<Map>()
        .map((m) => ChatGroupMember.fromJson(m.cast<String, Object?>()))
        .toList();
  }

  Future<List<ChatGroupMember>> listGroupMembersPaged({
    required String groupId,
    required String deviceId,
    int batchSize = 200,
    int maxPages = 25,
  }) async {
    final normalizedBatchSize = batchSize.clamp(1, 200);
    final normalizedMaxPages = maxPages < 1 ? 1 : maxPages;
    String? afterJoinedAt;
    String? afterDeviceId;
    final merged = <String, ChatGroupMember>{};

    for (var page = 0; page < normalizedMaxPages; page++) {
      final items = await listGroupMembersPage(
        groupId: groupId,
        deviceId: deviceId,
        limit: normalizedBatchSize,
        afterJoinedAt: afterJoinedAt,
        afterDeviceId: afterDeviceId,
      );
      for (final item in items) {
        final memberDeviceId = item.deviceId.trim();
        if (memberDeviceId.isEmpty) continue;
        merged[memberDeviceId] = item;
      }
      final cursor = _latestGroupMembersCursor(items);
      if (items.length < normalizedBatchSize || cursor == null) {
        break;
      }
      if (cursor.joinedAt == afterJoinedAt &&
          cursor.deviceId == afterDeviceId) {
        break;
      }
      afterJoinedAt = cursor.joinedAt;
      afterDeviceId = cursor.deviceId;
    }

    final members = merged.values.toList()..sort(_compareGroupMemberCursorAsc);
    return members;
  }

  Future<ChatGroup> inviteGroupMembers({
    required String groupId,
    required String inviterId,
    required List<String> memberIds,
  }) async {
    final body = jsonEncode({'inviter_id': inviterId, 'member_ids': memberIds});
    final r = await _post(
      _uri('/chat/groups/${Uri.encodeComponent(groupId)}/invite'),
      headers: await _headers(json: true, chatDeviceId: inviterId),
      body: body,
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'group invite',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
    return ChatGroup.fromJson(jsonDecode(r.body) as Map<String, Object?>);
  }

  Future<void> leaveGroup({
    required String groupId,
    required String deviceId,
  }) async {
    final body = jsonEncode({'device_id': deviceId});
    final r = await _post(
      _uri('/chat/groups/${Uri.encodeComponent(groupId)}/leave'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: body,
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'group leave',
        statusCode: r.statusCode,
        body: r.body,
      );
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
    final r = await _post(
      _uri('/chat/groups/${Uri.encodeComponent(groupId)}/set_role'),
      headers: await _headers(json: true, chatDeviceId: actorId),
      body: body,
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'group set role',
        statusCode: r.statusCode,
        body: r.body,
      );
    }
  }

  Future<List<ChatGroupKeyEvent>> listGroupKeyEvents({
    required String groupId,
    required String deviceId,
    int limit = 20,
  }) async {
    return listGroupKeyEventsPaged(
      groupId: groupId,
      deviceId: deviceId,
      batchSize: limit,
    );
  }

  Future<List<ChatGroupKeyEvent>> listGroupKeyEventsPage({
    required String groupId,
    required String deviceId,
    int limit = 20,
    int? beforeVersion,
  }) async {
    final normalizedBeforeVersion = beforeVersion;
    if (normalizedBeforeVersion != null && normalizedBeforeVersion <= 0) {
      throw ArgumentError('beforeVersion must be positive');
    }
    final qp = <String, String>{
      'device_id': deviceId,
      'limit': '${limit.clamp(1, 200)}',
    };
    if (normalizedBeforeVersion != null) {
      qp['before_version'] = '$normalizedBeforeVersion';
    }
    final r = await _get(
      _uri('/chat/groups/${Uri.encodeComponent(groupId)}/keys/events', qp),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'group key events',
        statusCode: r.statusCode,
        body: r.body,
      );
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

  Future<List<ChatGroupKeyEvent>> listGroupKeyEventsPaged({
    required String groupId,
    required String deviceId,
    int batchSize = 50,
    int maxPages = 20,
  }) async {
    final normalizedBatchSize = batchSize.clamp(1, 200);
    final normalizedMaxPages = maxPages < 1 ? 1 : maxPages;
    int? beforeVersion;
    final merged = <int, ChatGroupKeyEvent>{};

    for (var page = 0; page < normalizedMaxPages; page++) {
      final items = await listGroupKeyEventsPage(
        groupId: groupId,
        deviceId: deviceId,
        limit: normalizedBatchSize,
        beforeVersion: beforeVersion,
      );
      for (final item in items) {
        if (item.version <= 0) continue;
        merged[item.version] = item;
      }
      final cursor = _oldestGroupKeyEventVersion(items);
      if (items.length < normalizedBatchSize || cursor == null) {
        break;
      }
      if (cursor == beforeVersion) {
        break;
      }
      beforeVersion = cursor;
    }

    final events = merged.values.toList()..sort(_compareGroupKeyEventDesc);
    return events;
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
    final r = await _post(
      _uri('/chat/groups/${Uri.encodeComponent(groupId)}/keys/rotate'),
      headers: await _headers(json: true, chatDeviceId: actorId),
      body: body,
    );
    if (r.statusCode >= 400) {
      throw ChatHttpException(
        op: 'group key rotate',
        statusCode: r.statusCode,
        body: r.body,
      );
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
    if (_closed) return;
    _closed = true;
    closeLiveSockets();
    if (_ownsHttpClient) {
      _http.close();
    }
  }

  void closeLiveSockets() {
    _ws?.sink.close();
    _ws = null;
    _wsGroups?.sink.close();
    _wsGroups = null;
    _wsTyping?.sink.close();
    _wsTyping = null;
  }

  Future<void> _ensureLibsignalMaterialForRegisteredDevice(
    ChatIdentity me, {
    ChatLocalStore? store,
  }) async {
    final resolvedStore = store ?? ChatLocalStore();
    if (!_enableLibsignalKeyApi()) {
      await resolvedStore.markDeviceKeyBootstrapped(
        me.id,
        baseUrlOverride: _base,
      );
      return;
    }
    try {
      await registerLibsignalBundle(me: me);
      await resolvedStore.markDeviceKeyBootstrapped(
        me.id,
        baseUrlOverride: _base,
      );
      await resolvedStore.markDevicePrekeyStatusCheckedNow(
        me.id,
        baseUrlOverride: _base,
      );
    } catch (e) {
      if (_isMissingLibsignalKeyApiFailure(e)) {
        await resolvedStore.markDeviceKeyBootstrapped(
          me.id,
          baseUrlOverride: _base,
        );
        await resolvedStore.markDevicePrekeyStatusCheckedNow(
          me.id,
          baseUrlOverride: _base,
        );
        return;
      }
      rethrow;
    }
  }

  Future<void> _maybeRefillOneTimePrekeys(
    ChatIdentity me, {
    ChatLocalStore? store,
  }) async {
    if (!_enableLibsignalKeyApi()) return;
    final resolvedStore = store ?? ChatLocalStore();
    if (await resolvedStore.isDevicePrekeyStatusCheckFresh(
      me.id,
      minInterval: shamellLibsignalPrekeyStatusCheckMinInterval,
      baseUrlOverride: _base,
    )) {
      return;
    }
    try {
      final status = await fetchPrekeyStatus(deviceId: me.id);
      await resolvedStore.markDevicePrekeyStatusCheckedNow(
        me.id,
        baseUrlOverride: _base,
      );
      final uploadCount = status.recommendedUpload.clamp(0, 500);
      if (uploadCount <= 0) {
        return;
      }
      await uploadOneTimePrekeys(me: me, count: uploadCount);
      await resolvedStore.markDevicePrekeyStatusCheckedNow(
        me.id,
        baseUrlOverride: _base,
      );
    } catch (e) {
      if (_isMissingLibsignalKeyApiFailure(e)) {
        await resolvedStore.markDevicePrekeyStatusCheckedNow(
          me.id,
          baseUrlOverride: _base,
        );
        return;
      }
      if (_shouldFallbackToFullChatDeviceRegistration(e)) {
        rethrow;
      }
      await resolvedStore.markDevicePrekeyStatusCheckedNow(
        me.id,
        baseUrlOverride: _base,
      );
    }
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
      if (sessionKey.length != 32) {
        throw StateError('session key invalid');
      }
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
    final skRaw = base64Decode(me.privateKeyB64);
    if (skRaw.length != 32) {
      throw StateError('identity private key invalid');
    }
    final pkRaw = base64Decode(peer.publicKeyB64);
    if (pkRaw.length != 32) {
      throw StateError('peer identity key invalid');
    }
    final sk = x25519.PrivateKey(skRaw);
    final pkPeer = x25519.PublicKey(pkRaw);
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
      final id = await ChatLocalStore().loadIdentity(baseUrlOverride: _base);
      final candidate = id?.id.trim() ?? '';
      if (candidate.isNotEmpty) {
        did = candidate;
      }
    }
    String? tok = chatDeviceToken?.trim();
    if ((tok == null || tok.isEmpty) && did != null && did.isNotEmpty) {
      tok = (await ChatLocalStore().loadDeviceAuthToken(
        did,
        baseUrlOverride: _base,
      ))
          ?.trim();
    }
    if (did != null && did.isEmpty) did = null;
    if (tok != null && tok.isEmpty) tok = null;
    return (deviceId: did, token: tok);
  }

  WebSocketChannel _connectWebSocket(
    Uri wsUri, {
    required Map<String, String> headers,
  }) {
    // Fail closed: authenticated chat sockets must not silently retry without
    // the session/device headers that authorize the upgrade.
    return shamellConnectWebSocket(
      wsUri,
      headers: headers,
      failWithoutHeadersOnIo: true,
    );
  }

  Future<Map<String, String>> _headers({
    bool json = false,
    String? chatDeviceId,
    String? chatDeviceToken,
  }) async {
    _assertSecureTransportBase();
    final h = await shamellSessionHeadersForBaseUrl(_base, json: json);
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
    if (base.isEmpty) {
      throw StateError('Invalid chat base URL');
    }
    final prefix =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final full = '$prefix$path';
    return Uri.parse(full).replace(queryParameters: qp);
  }

  Uri _wsUri(String path, {required String deviceId}) {
    final baseUri = Uri.parse(_base);
    final scheme = baseUri.scheme == 'https' ? 'wss' : 'ws';
    final queryParameters = <String, String>{'device_id': deviceId};
    final shouldIncludePort = baseUri.hasPort && baseUri.port > 0;
    if (shouldIncludePort) {
      return Uri(
        scheme: scheme,
        host: baseUri.host,
        port: baseUri.port,
        path: path,
        queryParameters: queryParameters,
      );
    }
    return Uri(
      scheme: scheme,
      host: baseUri.host,
      path: path,
      queryParameters: queryParameters,
    );
  }
}

@visibleForTesting
Future<Map<String, String>> shamellChatWebSocketHeadersForBaseUrl(
  String baseUrl, {
  required String deviceId,
}) async {
  final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
  final token = (await ChatLocalStore().loadDeviceAuthToken(
        deviceId,
        baseUrlOverride: baseUrl,
      )) ??
      '';
  if (token.trim().isNotEmpty) {
    headers['X-Chat-Device-Id'] = deviceId;
    headers['X-Chat-Device-Token'] = token.trim();
  }
  return headers;
}

class ChatLocalStore {
  static const _idKey = 'chat.identity';
  static const _idScopedKeyPrefix = 'chat.identity.v2.';
  static const _peerKey = 'chat.peer';
  static const _peerScopedKeyPrefix = 'chat.peer.v2.';
  static const _contactsKey = 'chat.contacts';
  static const _contactsScopedKeyPrefix = 'chat.contacts.v2.';
  static const _unreadKey = 'chat.unread';
  static const _unreadScopedKeyPrefix = 'chat.unread.v2.';
  static const _unreadPrefix = 'chat.unread.';
  static const _unreadEntityScopedKeyPrefix = 'chat.unread.v3.';
  static const _activePeerKey = 'chat.active';
  static const _activePeerScopedKeyPrefix = 'chat.active.v2.';
  static const _chatWallpaperThemeKey = 'chat.wallpaper_theme';
  static const _chatWallpaperThemeScopedKeyPrefix = 'chat.wallpaper_theme.v2.';
  static const _officialNotifKey = 'official.notif';
  static const _officialNotifScopedKeyPrefix = 'official.notif.v2.';
  static const _serviceNotificationsUnreadKey =
      'official_template_messages.has_unread';
  static const _serviceNotificationsUnreadScopedKeyPrefix =
      'official_template_messages.has_unread.v2.';
  static const _hideServiceNotificationsThreadKey =
      'chat.hide_service_notifications_thread';
  static const _hideServiceNotificationsThreadScopedKeyPrefix =
      'chat.hide_service_notifications_thread.v2.';
  static const _directInboxCursorKey = 'chat.direct_inbox.cursor';
  static const _directInboxCursorScopedKeyPrefix =
      'chat.direct_inbox.cursor.v2.';
  static const _groupSeenKey = 'chat.grp.seen';
  static const _groupSeenScopedKeyPrefix = 'chat.grp.seen.v2.';
  static const _groupSeenPrefix = 'chat.grp.seen.';
  static const _groupSeenEntityScopedKeyPrefix = 'chat.grp.seen.v3.';
  static const _groupNamesKey = 'chat.grp.names';
  static const _groupNamesScopedKeyPrefix = 'chat.grp.names.v2.';
  static const _pinnedMessagesKey = 'chat.pinned_messages';
  static const _pinnedMessagesScopedKeyPrefix = 'chat.pinned_messages.v2.';
  static const _recalledMessagesKey = 'chat.recalled_messages';
  static const _recalledMessagesScopedKeyPrefix = 'chat.recalled_messages.v2.';
  static const _pinnedChatsKey = 'chat.pinned_chats';
  static const _pinnedChatsScopedKeyPrefix = 'chat.pinned_chats.v2.';
  static const _archivedGroupsKey = 'chat.archived_groups';
  static const _archivedGroupsScopedKeyPrefix = 'chat.archived_groups.v2.';
  static const _groupMessageReactionsPrefix = 'chat.group_message_reactions.';
  static const _groupMessageReactionsScopedKeyPrefix =
      'chat.group_message_reactions.v2.';
  static const _messagesScopedKeyPrefix = 'chat.msgs.v2.';
  static const _groupMessagesScopedKeyPrefix = 'chat.grp.msgs.v2.';
  static const _groupNoticePrefix = 'chat.group_notice.';
  static const _groupNoticeScopedKeyPrefix = 'chat.group_notice.v2.';
  static const _officialAutoreplyShownPrefix = 'official.autoreply.shown.';
  static const _officialAutoreplyShownScopedKeyPrefix =
      'official.autoreply.shown.v2.';
  static const _officialAutofollowPrefix = 'official.autofollow.';
  static const _officialAutofollowScopedKeyPrefix = 'official.autofollow.v2.';
  static const _officialAutochatPrefix = 'official.autochat.';
  static const _officialAutochatScopedKeyPrefix = 'official.autochat.v2.';
  static const _voicePlayedPrefix = 'chat.voice.played.';
  static const _voicePlayedScopedKeyPrefix = 'chat.voice.played.v2.';
  static const _groupVoicePlayedPrefix = 'chat.grp.voice.played.';
  static const _groupVoicePlayedScopedKeyPrefix = 'chat.grp.voice.played.v2.';
  static const _verifiedFingerprintScopedKeyPrefix = 'chat.ver.v2.';
  static const _draftsKey = 'chat.drafts.v1';
  static const _draftsScopedKeyPrefix = 'chat.drafts.v2.';
  static const _deviceTokenPrefix = 'chat.device.token.';
  static const _deviceTokenScopedKeyPrefix = 'chat.device.token.v2.';
  static const _deviceRegisteredShamellUserIdPrefix =
      'chat.device.account_shamell_user_id.';
  static const _deviceRegisteredShamellUserIdScopedKeyPrefix =
      'chat.device.account_shamell_user_id.v2.';
  static const _pushTokenBindingFingerprintPrefix =
      'chat.push.binding.fingerprint.';
  static const _pushTokenBindingFingerprintScopedKeyPrefix =
      'chat.push.binding.fingerprint.v2.';
  static const _deviceKeyBootstrapPrefix = 'chat.device.keys.bootstrapped.';
  static const _deviceKeyBootstrapScopedKeyPrefix =
      'chat.device.keys.bootstrapped.v2.';
  static const _devicePrekeyStatusCheckedPrefix =
      'chat.device.prekeys.checked.';
  static const _devicePrekeyStatusCheckedScopedKeyPrefix =
      'chat.device.prekeys.checked.v2.';
  static const _legacySecretFallbackPrefix = 'chat.sec.fallback.';
  static const _chatScopedUnknownScope = 'unknown';
  static const _chatScopedBaseUrlPrefKey = 'base_url';
  static const int _voicePlayedMax = 200;

  Future<ChatIdentity?> loadIdentity({String? baseUrlOverride}) async {
    String? raw = await _loadScopedSecureString(
      legacyKey: _idKey,
      scopedKeyPrefix: _idScopedKeyPrefix,
      baseUrlOverride: baseUrlOverride,
    );
    if (raw == null || raw.isEmpty) {
      try {
        final sp = await SharedPreferences.getInstance();
        final legacy = (sp.getString(_idKey) ?? '').trim();
        if (legacy.isNotEmpty) {
          await sp.remove(_idKey);
          if (_isUnknownChatScopedStateScope(
            _currentChatScopedStateScope(
              sp,
              baseUrlOverride: baseUrlOverride,
            ),
          )) {
            await _saveScopedSecureString(
              legacyKey: _idKey,
              scopedKeyPrefix: _idScopedKeyPrefix,
              value: legacy,
              baseUrlOverride: baseUrlOverride,
            );
            raw = legacy;
          }
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

  Future<void> saveIdentity(
    ChatIdentity id, {
    String? baseUrlOverride,
  }) async {
    await _saveScopedSecureString(
      legacyKey: _idKey,
      scopedKeyPrefix: _idScopedKeyPrefix,
      value: jsonEncode(id.toMap()),
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> saveDeviceAuthToken(
    String deviceId,
    String token, {
    String? baseUrlOverride,
  }) async {
    final did = deviceId.trim();
    final tok = token.trim();
    if (did.isEmpty || tok.isEmpty) return;
    await _saveScopedSecureEntityString(
      legacyKeyPrefix: _deviceTokenPrefix,
      scopedKeyPrefix: _deviceTokenScopedKeyPrefix,
      entityId: did,
      value: tok,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<String?> loadDeviceAuthToken(
    String deviceId, {
    String? baseUrlOverride,
  }) async {
    final did = deviceId.trim();
    if (did.isEmpty) return null;
    final value = await _loadScopedSecureEntityString(
      legacyKeyPrefix: _deviceTokenPrefix,
      scopedKeyPrefix: _deviceTokenScopedKeyPrefix,
      entityId: did,
      baseUrlOverride: baseUrlOverride,
    );
    final token = (value ?? '').trim();
    if (token.isEmpty) return null;
    return token;
  }

  Future<void> saveRegisteredAccountShamellUserId(
    String deviceId,
    String shamellUserId, {
    String? baseUrlOverride,
  }) async {
    final did = deviceId.trim();
    final normalized = shamellUserId.trim().toUpperCase();
    if (did.isEmpty || normalized.isEmpty) return;
    await _saveScopedSensitiveEntityPlainString(
      legacyKeyPrefix: _deviceRegisteredShamellUserIdPrefix,
      scopedKeyPrefix: _deviceRegisteredShamellUserIdScopedKeyPrefix,
      entityId: did,
      value: normalized,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<String?> loadRegisteredAccountShamellUserId(
    String deviceId, {
    String? baseUrlOverride,
  }) async {
    final did = deviceId.trim();
    if (did.isEmpty) return null;
    final raw = (await _loadScopedSensitiveEntityPlainString(
              legacyKeyPrefix: _deviceRegisteredShamellUserIdPrefix,
              scopedKeyPrefix: _deviceRegisteredShamellUserIdScopedKeyPrefix,
              entityId: did,
              baseUrlOverride: baseUrlOverride,
            ) ??
            '')
        .trim()
        .toUpperCase();
    if (raw.isEmpty) return null;
    return raw;
  }

  Future<void> savePushTokenBindingFingerprint(
    String deviceId,
    String fingerprint, {
    String? baseUrlOverride,
  }) async {
    final did = deviceId.trim();
    final normalizedFingerprint = fingerprint.trim();
    if (did.isEmpty || normalizedFingerprint.isEmpty) return;
    await _saveScopedSecureEntityString(
      legacyKeyPrefix: _pushTokenBindingFingerprintPrefix,
      scopedKeyPrefix: _pushTokenBindingFingerprintScopedKeyPrefix,
      entityId: did,
      value: normalizedFingerprint,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<String?> loadPushTokenBindingFingerprint(
    String deviceId, {
    String? baseUrlOverride,
  }) async {
    final did = deviceId.trim();
    if (did.isEmpty) return null;
    final value = await _loadScopedSecureEntityString(
      legacyKeyPrefix: _pushTokenBindingFingerprintPrefix,
      scopedKeyPrefix: _pushTokenBindingFingerprintScopedKeyPrefix,
      entityId: did,
      baseUrlOverride: baseUrlOverride,
    );
    final fingerprint = (value ?? '').trim();
    if (fingerprint.isEmpty) return null;
    return fingerprint;
  }

  Future<void> deletePushTokenBindingFingerprint(
    String deviceId, {
    String? baseUrlOverride,
  }) async {
    final did = deviceId.trim();
    if (did.isEmpty) return;
    await _deleteScopedSecureEntityString(
      legacyKeyPrefix: _pushTokenBindingFingerprintPrefix,
      scopedKeyPrefix: _pushTokenBindingFingerprintScopedKeyPrefix,
      entityId: did,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<bool> isDeviceKeyBootstrapped(
    String deviceId, {
    String? baseUrlOverride,
  }) async {
    final did = deviceId.trim();
    if (did.isEmpty) return false;
    try {
      return await _loadScopedSensitiveEntityBoolFlag(
        legacyKeyPrefix: _deviceKeyBootstrapPrefix,
        scopedKeyPrefix: _deviceKeyBootstrapScopedKeyPrefix,
        entityId: did,
        baseUrlOverride: baseUrlOverride,
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> markDeviceKeyBootstrapped(
    String deviceId, {
    String? baseUrlOverride,
  }) async {
    final did = deviceId.trim();
    if (did.isEmpty) return;
    try {
      await _saveScopedSensitiveEntityBoolFlag(
        legacyKeyPrefix: _deviceKeyBootstrapPrefix,
        scopedKeyPrefix: _deviceKeyBootstrapScopedKeyPrefix,
        entityId: did,
        value: true,
        baseUrlOverride: baseUrlOverride,
      );
    } catch (_) {}
  }

  Future<void> clearDeviceKeyBootstrapped(
    String deviceId, {
    String? baseUrlOverride,
  }) async {
    final did = deviceId.trim();
    if (did.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(
        _scopedChatEntityStateKey(
          _deviceKeyBootstrapScopedKeyPrefix,
          _currentChatScopedStateScope(
            sp,
            baseUrlOverride: baseUrlOverride,
          ),
          did,
        ),
      );
      await sp.remove('$_deviceKeyBootstrapPrefix$did');
    } catch (_) {}
  }

  Future<bool> isDevicePrekeyStatusCheckFresh(
    String deviceId, {
    required Duration minInterval,
    String? baseUrlOverride,
  }) async {
    final did = deviceId.trim();
    if (did.isEmpty) return false;
    final raw = (await _loadScopedSensitiveEntityPlainString(
              legacyKeyPrefix: _devicePrekeyStatusCheckedPrefix,
              scopedKeyPrefix: _devicePrekeyStatusCheckedScopedKeyPrefix,
              entityId: did,
              baseUrlOverride: baseUrlOverride,
            ) ??
            '')
        .trim();
    final checkedAtMillis = int.tryParse(raw);
    if (checkedAtMillis == null || checkedAtMillis <= 0) {
      return false;
    }
    final ageMillis =
        DateTime.now().toUtc().millisecondsSinceEpoch - checkedAtMillis;
    return ageMillis >= 0 && ageMillis < minInterval.inMilliseconds;
  }

  Future<void> markDevicePrekeyStatusCheckedNow(
    String deviceId, {
    String? baseUrlOverride,
  }) async {
    final did = deviceId.trim();
    if (did.isEmpty) return;
    try {
      await _saveScopedSensitiveEntityPlainString(
        legacyKeyPrefix: _devicePrekeyStatusCheckedPrefix,
        scopedKeyPrefix: _devicePrekeyStatusCheckedScopedKeyPrefix,
        entityId: did,
        value: DateTime.now().toUtc().millisecondsSinceEpoch.toString(),
        baseUrlOverride: baseUrlOverride,
      );
    } catch (_) {}
  }

  Future<void> deleteDeviceAuthToken(
    String deviceId, {
    String? baseUrlOverride,
  }) async {
    final did = deviceId.trim();
    if (did.isEmpty) return;
    await _deleteScopedSecureEntityString(
      legacyKeyPrefix: _deviceTokenPrefix,
      scopedKeyPrefix: _deviceTokenScopedKeyPrefix,
      entityId: did,
      baseUrlOverride: baseUrlOverride,
    );
    await clearDeviceKeyBootstrapped(
      did,
      baseUrlOverride: baseUrlOverride,
    );
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(
        _scopedChatEntityStateKey(
          _devicePrekeyStatusCheckedScopedKeyPrefix,
          _currentChatScopedStateScope(
            sp,
            baseUrlOverride: baseUrlOverride,
          ),
          did,
        ),
      );
      await sp.remove('$_devicePrekeyStatusCheckedPrefix$did');
    } catch (_) {}
  }

  Future<ChatContact?> loadPeer({String? baseUrlOverride}) async {
    final raw = await _loadScopedSensitivePlainString(
      legacyKey: _peerKey,
      scopedKeyPrefix: _peerScopedKeyPrefix,
      baseUrlOverride: baseUrlOverride,
    );
    if (raw == null) return null;
    try {
      return ChatContact.fromMap((jsonDecode(raw) as Map<String, Object?>));
    } catch (_) {
      return null;
    }
  }

  Future<void> savePeer(ChatContact c, {String? baseUrlOverride}) async {
    await _saveScopedSensitivePlainString(
      legacyKey: _peerKey,
      scopedKeyPrefix: _peerScopedKeyPrefix,
      value: jsonEncode(c.toMap()),
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> clearPeer({String? baseUrlOverride}) async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(
      _scopedChatStateKey(
        _peerScopedKeyPrefix,
        _currentChatScopedStateScope(
          sp,
          baseUrlOverride: baseUrlOverride,
        ),
      ),
    );
    await sp.remove(_peerKey);
  }

  Future<List<ChatContact>> loadContacts({String? baseUrlOverride}) async {
    final raw = await _loadScopedSensitivePlainString(
      legacyKey: _contactsKey,
      scopedKeyPrefix: _contactsScopedKeyPrefix,
      baseUrlOverride: baseUrlOverride,
    );
    if (raw == null) return [];
    try {
      final arr = (jsonDecode(raw) as List)
          .map((m) => ChatContact.fromMap(m as Map<String, Object?>))
          .whereType<ChatContact>()
          .toList();
      return arr;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveContacts(
    List<ChatContact> contacts, {
    String? baseUrlOverride,
  }) async {
    await _saveScopedSensitivePlainString(
      legacyKey: _contactsKey,
      scopedKeyPrefix: _contactsScopedKeyPrefix,
      value: jsonEncode(contacts.map((c) => c.toMap()).toList()),
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> saveContactsForPeers(
    Iterable<ChatContact> contacts, {
    String? baseUrlOverride,
  }) async {
    final normalizedContacts = <String, ChatContact>{};
    for (final contact in contacts) {
      final contactId = contact.id.trim();
      if (contactId.isEmpty) continue;
      normalizedContacts[contactId] = contact;
    }
    if (normalizedContacts.isEmpty) return;
    final current = await loadContacts(baseUrlOverride: baseUrlOverride);
    final updated = List<ChatContact>.from(current);
    for (final entry in normalizedContacts.entries) {
      final idx = updated.indexWhere((contact) => contact.id == entry.key);
      if (idx == -1) {
        updated.add(entry.value);
      } else {
        updated[idx] = entry.value;
      }
    }
    await saveContacts(updated, baseUrlOverride: baseUrlOverride);
  }

  Future<void> removeContactsForPeers(
    Iterable<String> peerIds, {
    String? baseUrlOverride,
  }) async {
    final normalizedPeerIds = <String>{};
    for (final peerId in peerIds) {
      final normalizedPeerId = peerId.trim();
      if (normalizedPeerId.isEmpty) continue;
      normalizedPeerIds.add(normalizedPeerId);
    }
    if (normalizedPeerIds.isEmpty) return;
    final current = await loadContacts(baseUrlOverride: baseUrlOverride);
    final updated = current
        .where((contact) => !normalizedPeerIds.contains(contact.id))
        .toList(growable: false);
    await saveContacts(updated, baseUrlOverride: baseUrlOverride);
  }

  Future<({String sinceIso, String sinceId})?> loadDirectInboxCursor({
    String? baseUrlOverride,
  }) async {
    final raw = await _loadScopedSensitivePlainString(
      legacyKey: _directInboxCursorKey,
      scopedKeyPrefix: _directInboxCursorScopedKeyPrefix,
      baseUrlOverride: baseUrlOverride,
    );
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final sinceIso = (decoded['since_iso'] ?? '').toString().trim();
      final sinceId = (decoded['since_id'] ?? '').toString().trim();
      if (sinceIso.isEmpty) {
        return null;
      }
      return (sinceIso: sinceIso, sinceId: sinceId);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDirectInboxCursor(
    String sinceIso, {
    String sinceId = '',
    String? baseUrlOverride,
  }) async {
    final normalizedSinceIso = sinceIso.trim();
    if (normalizedSinceIso.isEmpty) return;
    await _saveScopedSensitivePlainString(
      legacyKey: _directInboxCursorKey,
      scopedKeyPrefix: _directInboxCursorScopedKeyPrefix,
      value: jsonEncode(<String, String>{
        'since_iso': normalizedSinceIso,
        'since_id': sinceId.trim(),
      }),
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> saveLatestDirectInboxCursor(
    Iterable<ChatMessage> messages, {
    String? baseUrlOverride,
  }) async {
    final latest = _latestDirectCursorMessage(messages);
    final createdAt = latest?.createdAt;
    if (latest == null || createdAt == null) {
      return;
    }
    await saveDirectInboxCursor(
      createdAt.toUtc().toIso8601String(),
      sinceId: latest.id,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> clearDirectInboxCursor({String? baseUrlOverride}) async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(
      _scopedChatStateKey(
        _directInboxCursorScopedKeyPrefix,
        _currentChatScopedStateScope(
          sp,
          baseUrlOverride: baseUrlOverride,
        ),
      ),
    );
    await sp.remove(_directInboxCursorKey);
  }

  Future<void> upsertContact(
    ChatContact incoming, {
    String? baseUrlOverride,
  }) async {
    final pid = incoming.id.trim();
    if (pid.isEmpty) return;

    final contacts = await loadContacts(baseUrlOverride: baseUrlOverride);
    final idx = contacts.indexWhere((c) => c.id == pid);
    if (idx == -1) {
      await saveContacts(
        <ChatContact>[...contacts, incoming],
        baseUrlOverride: baseUrlOverride,
      );
      return;
    }

    final existing = contacts[idx];
    final merged = ChatContact(
      id: existing.id,
      publicKeyB64: incoming.publicKeyB64.trim().isNotEmpty
          ? incoming.publicKeyB64
          : existing.publicKeyB64,
      fingerprint: incoming.fingerprint.trim().isNotEmpty
          ? incoming.fingerprint
          : existing.fingerprint,
      name: (incoming.name ?? '').trim().isNotEmpty
          ? incoming.name
          : existing.name,
      verified: existing.verified,
      verifiedAt: existing.verifiedAt,
      starred: existing.starred,
      pinned: existing.pinned,
      disappearing: existing.disappearing,
      disappearAfter: existing.disappearAfter,
      archived: existing.archived,
      hidden: existing.hidden,
      blocked: existing.blocked,
      blockedAt: existing.blockedAt,
      muted: existing.muted,
    );
    final updated = List<ChatContact>.from(contacts);
    updated[idx] = merged;
    await saveContacts(updated, baseUrlOverride: baseUrlOverride);
  }

  Future<Map<String, String>> loadDrafts({String? baseUrlOverride}) async {
    return _loadScopedSensitiveStringMap(
      legacyKey: _draftsKey,
      scopedKeyPrefix: _draftsScopedKeyPrefix,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> saveDrafts(
    Map<String, String> drafts, {
    String? baseUrlOverride,
  }) async {
    final cleaned = <String, String>{};
    drafts.forEach((k, v) {
      final id = k.trim();
      if (id.isEmpty) return;
      if (v.trim().isEmpty) return;
      cleaned[id] = v;
    });
    await _saveScopedSensitiveStringMap(
      legacyKey: _draftsKey,
      scopedKeyPrefix: _draftsScopedKeyPrefix,
      values: cleaned,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<Map<String, Set<String>>> loadPinnedMessages({
    String? baseUrlOverride,
  }) async {
    return _loadScopedPinnedMessages(
      legacyKey: _pinnedMessagesKey,
      scopedKeyPrefix: _pinnedMessagesScopedKeyPrefix,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> savePinnedMessages(
    Map<String, Set<String>> values, {
    String? baseUrlOverride,
  }) async {
    await _saveScopedPinnedMessages(
      legacyKey: _pinnedMessagesKey,
      scopedKeyPrefix: _pinnedMessagesScopedKeyPrefix,
      values: values,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> savePinnedMessageForPeer(
    String peerId,
    String messageId,
    bool pinned, {
    String? baseUrlOverride,
  }) async {
    final normalizedPeerId = peerId.trim();
    final normalizedMessageId = messageId.trim();
    if (normalizedPeerId.isEmpty || normalizedMessageId.isEmpty) return;
    final pinnedMessages = Map<String, Set<String>>.from(
      await loadPinnedMessages(baseUrlOverride: baseUrlOverride),
    );
    final current = Set<String>.from(
      pinnedMessages[normalizedPeerId] ?? const <String>{},
    );
    final changed = pinned
        ? current.add(normalizedMessageId)
        : current.remove(normalizedMessageId);
    if (!changed) return;
    if (current.isEmpty) {
      pinnedMessages.remove(normalizedPeerId);
    } else {
      pinnedMessages[normalizedPeerId] = current;
    }
    await savePinnedMessages(
      pinnedMessages,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> removePinnedMessageFromAllPeers(
    String messageId, {
    String? baseUrlOverride,
  }) async {
    final normalizedMessageId = messageId.trim();
    if (normalizedMessageId.isEmpty) return;
    final pinnedMessages = Map<String, Set<String>>.from(
      await loadPinnedMessages(baseUrlOverride: baseUrlOverride),
    );
    var changed = false;
    final peerIds = List<String>.from(pinnedMessages.keys);
    for (final peerId in peerIds) {
      final ids = Set<String>.from(
        pinnedMessages[peerId] ?? const <String>{},
      );
      if (!ids.remove(normalizedMessageId)) continue;
      changed = true;
      if (ids.isEmpty) {
        pinnedMessages.remove(peerId);
      } else {
        pinnedMessages[peerId] = ids;
      }
    }
    if (!changed) return;
    await savePinnedMessages(
      pinnedMessages,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<Set<String>> loadRecalledMessageIds({String? baseUrlOverride}) async {
    return _loadScopedSensitiveStringSet(
      legacyKey: _recalledMessagesKey,
      scopedKeyPrefix: _recalledMessagesScopedKeyPrefix,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> saveRecalledMessageIds(
    Set<String> values, {
    String? baseUrlOverride,
  }) async {
    await _saveScopedSensitiveStringList(
      legacyKey: _recalledMessagesKey,
      scopedKeyPrefix: _recalledMessagesScopedKeyPrefix,
      values: values,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> saveRecalledMessageState(
    String messageId,
    bool recalled, {
    String? baseUrlOverride,
  }) async {
    final normalizedMessageId = messageId.trim();
    if (normalizedMessageId.isEmpty) return;
    final recalledMessageIds = Set<String>.from(
      await loadRecalledMessageIds(baseUrlOverride: baseUrlOverride),
    );
    final changed = recalled
        ? recalledMessageIds.add(normalizedMessageId)
        : recalledMessageIds.remove(normalizedMessageId);
    if (!changed) return;
    await saveRecalledMessageIds(
      recalledMessageIds,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<List<String>> loadPinnedChatOrder({String? baseUrlOverride}) async {
    return _loadScopedSensitiveStringList(
      legacyKey: _pinnedChatsKey,
      scopedKeyPrefix: _pinnedChatsScopedKeyPrefix,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> savePinnedChatOrder(
    List<String> values, {
    String? baseUrlOverride,
  }) async {
    await _saveScopedSensitiveStringList(
      legacyKey: _pinnedChatsKey,
      scopedKeyPrefix: _pinnedChatsScopedKeyPrefix,
      values: values,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> savePinnedChatOrderState(
    String chatKey,
    bool pinned, {
    String? baseUrlOverride,
  }) async {
    final normalizedChatKey = chatKey.trim();
    if (normalizedChatKey.isEmpty) return;
    final current = List<String>.from(
      await loadPinnedChatOrder(baseUrlOverride: baseUrlOverride),
    );
    final next = List<String>.from(current)
      ..removeWhere((id) => id == normalizedChatKey);
    if (pinned) {
      next.insert(0, normalizedChatKey);
    }
    if (listEquals(current, next)) return;
    await savePinnedChatOrder(
      next,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<List<String>> reconcilePinnedChatOrder(
    Iterable<String> pinnedChatKeys, {
    String? baseUrlOverride,
  }) async {
    final normalizedPinnedChatKeys = pinnedChatKeys
        .map((chatKey) => chatKey.trim())
        .where((chatKey) => chatKey.isNotEmpty)
        .toList(growable: false);
    final current = List<String>.from(
      await loadPinnedChatOrder(baseUrlOverride: baseUrlOverride),
    );
    final next = current
        .where((chatKey) => normalizedPinnedChatKeys.contains(chatKey))
        .toList();
    for (final chatKey in normalizedPinnedChatKeys) {
      if (!next.contains(chatKey)) {
        next.add(chatKey);
      }
    }
    if (listEquals(current, next)) {
      return current;
    }
    await savePinnedChatOrder(
      next,
      baseUrlOverride: baseUrlOverride,
    );
    return next;
  }

  Future<Set<String>> loadArchivedGroups({String? baseUrlOverride}) async {
    return _loadScopedSensitiveStringSet(
      legacyKey: _archivedGroupsKey,
      scopedKeyPrefix: _archivedGroupsScopedKeyPrefix,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> saveArchivedGroups(
    Set<String> values, {
    String? baseUrlOverride,
  }) async {
    await _saveScopedSensitiveStringList(
      legacyKey: _archivedGroupsKey,
      scopedKeyPrefix: _archivedGroupsScopedKeyPrefix,
      values: values,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> saveArchivedGroupState(
    String groupId,
    bool archived, {
    String? baseUrlOverride,
  }) async {
    final normalizedGroupId = groupId.trim();
    if (normalizedGroupId.isEmpty) return;
    final archivedGroups = Set<String>.from(
      await loadArchivedGroups(baseUrlOverride: baseUrlOverride),
    );
    final changed = archived
        ? archivedGroups.add(normalizedGroupId)
        : archivedGroups.remove(normalizedGroupId);
    if (!changed) return;
    await saveArchivedGroups(
      archivedGroups,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<Map<String, String>> loadGroupMessageReactions(
    String groupId, {
    String? baseUrlOverride,
  }) async {
    final normalizedGroupId = groupId.trim();
    if (normalizedGroupId.isEmpty) return <String, String>{};
    return _loadScopedSensitiveEntityStringMap(
      legacyKeyPrefix: _groupMessageReactionsPrefix,
      scopedKeyPrefix: _groupMessageReactionsScopedKeyPrefix,
      entityId: normalizedGroupId,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> saveGroupMessageReactions(
    String groupId,
    Map<String, String> values, {
    String? baseUrlOverride,
  }) async {
    final normalizedGroupId = groupId.trim();
    if (normalizedGroupId.isEmpty) return;
    await _saveScopedSensitiveEntityStringMap(
      legacyKeyPrefix: _groupMessageReactionsPrefix,
      scopedKeyPrefix: _groupMessageReactionsScopedKeyPrefix,
      entityId: normalizedGroupId,
      values: values,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> saveMessages(
    String peerId,
    List<ChatMessage> msgs, {
    String? baseUrlOverride,
  }) async {
    final raw = jsonEncode(msgs.map((m) => m.toMap()).toList());
    await _saveScopedSensitiveEntityPlainString(
      legacyKeyPrefix: 'chat.msgs.',
      scopedKeyPrefix: _messagesScopedKeyPrefix,
      entityId: peerId,
      value: raw,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> deleteMessages(
    String peerId, {
    String? baseUrlOverride,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final pid = peerId.trim();
    if (pid.isEmpty) return;
    await sp.remove(
      _scopedChatEntityStateKey(
        _messagesScopedKeyPrefix,
        _currentChatScopedStateScope(
          sp,
          baseUrlOverride: baseUrlOverride,
        ),
        pid,
      ),
    );
    await sp.remove('chat.msgs.$pid');
  }

  Future<List<ChatMessage>> loadMessages(
    String peerId, {
    String? baseUrlOverride,
  }) async {
    final raw = await _loadScopedSensitiveEntityPlainString(
      legacyKeyPrefix: 'chat.msgs.',
      scopedKeyPrefix: _messagesScopedKeyPrefix,
      entityId: peerId,
      baseUrlOverride: baseUrlOverride,
    );
    if (raw == null) return [];
    try {
      final arr = (jsonDecode(raw) as List)
          .map((m) => ChatMessage.fromMap(m as Map<String, Object?>))
          .toList();
      return arr;
    } catch (_) {
      return [];
    }
  }

  Future<Set<String>> loadVoicePlayed(
    String peerId, {
    String? baseUrlOverride,
  }) async {
    final pid = peerId.trim();
    if (pid.isEmpty) return <String>{};
    return _loadScopedSensitiveEntityStringSet(
      legacyKeyPrefix: _voicePlayedPrefix,
      scopedKeyPrefix: _voicePlayedScopedKeyPrefix,
      entityId: pid,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> markVoicePlayed(
    String peerId,
    String messageId, {
    String? baseUrlOverride,
  }) async {
    final pid = peerId.trim();
    final mid = messageId.trim();
    if (pid.isEmpty || mid.isEmpty) return;
    final current = await _loadScopedSensitiveEntityStringList(
      legacyKeyPrefix: _voicePlayedPrefix,
      scopedKeyPrefix: _voicePlayedScopedKeyPrefix,
      entityId: pid,
      baseUrlOverride: baseUrlOverride,
    );
    final next = <String>[
      ...current.where((id) => id.isNotEmpty && id != mid),
      mid,
    ];
    if (next.length > _voicePlayedMax) {
      next.removeRange(0, next.length - _voicePlayedMax);
    }
    await _saveScopedSensitiveEntityStringList(
      legacyKeyPrefix: _voicePlayedPrefix,
      scopedKeyPrefix: _voicePlayedScopedKeyPrefix,
      entityId: pid,
      values: next,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<Set<String>> loadGroupVoicePlayed(
    String groupId, {
    String? baseUrlOverride,
  }) async {
    final gid = groupId.trim();
    if (gid.isEmpty) return <String>{};
    return _loadScopedSensitiveEntityStringSet(
      legacyKeyPrefix: _groupVoicePlayedPrefix,
      scopedKeyPrefix: _groupVoicePlayedScopedKeyPrefix,
      entityId: gid,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> markGroupVoicePlayed(
    String groupId,
    String messageId, {
    String? baseUrlOverride,
  }) async {
    final gid = groupId.trim();
    final mid = messageId.trim();
    if (gid.isEmpty || mid.isEmpty) return;
    final current = await _loadScopedSensitiveEntityStringList(
      legacyKeyPrefix: _groupVoicePlayedPrefix,
      scopedKeyPrefix: _groupVoicePlayedScopedKeyPrefix,
      entityId: gid,
      baseUrlOverride: baseUrlOverride,
    );
    final next = <String>[
      ...current.where((id) => id.isNotEmpty && id != mid),
      mid,
    ];
    if (next.length > _voicePlayedMax) {
      next.removeRange(0, next.length - _voicePlayedMax);
    }
    await _saveScopedSensitiveEntityStringList(
      legacyKeyPrefix: _groupVoicePlayedPrefix,
      scopedKeyPrefix: _groupVoicePlayedScopedKeyPrefix,
      entityId: gid,
      values: next,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> saveGroupMessages(
    String groupId,
    List<ChatGroupMessage> msgs, {
    String? baseUrlOverride,
  }) async {
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
    await _saveScopedSensitiveEntityPlainString(
      legacyKeyPrefix: 'chat.grp.msgs.',
      scopedKeyPrefix: _groupMessagesScopedKeyPrefix,
      entityId: groupId,
      value: raw,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<List<ChatGroupMessage>> loadGroupMessages(
    String groupId, {
    String? baseUrlOverride,
  }) async {
    final raw = await _loadScopedSensitiveEntityPlainString(
      legacyKeyPrefix: 'chat.grp.msgs.',
      scopedKeyPrefix: _groupMessagesScopedKeyPrefix,
      entityId: groupId,
      baseUrlOverride: baseUrlOverride,
    );
    if (raw == null) return [];
    try {
      final arr = (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((m) => ChatGroupMessage.fromJson(m.cast<String, Object?>()))
          .toList();
      return arr;
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteGroupMessages(
    String groupId, {
    String? baseUrlOverride,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final gid = groupId.trim();
    if (gid.isEmpty) return;
    await sp.remove(
      _scopedChatEntityStateKey(
        _groupMessagesScopedKeyPrefix,
        _currentChatScopedStateScope(
          sp,
          baseUrlOverride: baseUrlOverride,
        ),
        gid,
      ),
    );
    await sp.remove('chat.grp.msgs.$gid');
  }

  Future<Map<String, String>> loadGroupSeen({String? baseUrlOverride}) async {
    final entityMap =
        await _loadGroupSeenEntityMap(baseUrlOverride: baseUrlOverride);
    if (entityMap.isNotEmpty) {
      return entityMap;
    }
    final legacyMap =
        await _loadLegacyGroupSeenMap(baseUrlOverride: baseUrlOverride);
    if (legacyMap.isEmpty) {
      return <String, String>{};
    }
    await _saveGroupSeenEntityMap(
      legacyMap,
      baseUrlOverride: baseUrlOverride,
    );
    await _clearLegacyGroupSeenStorage(baseUrlOverride: baseUrlOverride);
    return legacyMap;
  }

  Future<String?> loadGroupSeenForGroup(
    String groupId, {
    String? baseUrlOverride,
  }) async {
    final normalizedGroupId = groupId.trim();
    if (normalizedGroupId.isEmpty) return null;
    final seenIso = (await _loadScopedSensitiveEntityPlainString(
              legacyKeyPrefix: _groupSeenPrefix,
              scopedKeyPrefix: _groupSeenEntityScopedKeyPrefix,
              entityId: normalizedGroupId,
              baseUrlOverride: baseUrlOverride,
            ) ??
            '')
        .trim();
    if (seenIso.isNotEmpty) {
      return seenIso;
    }
    final legacyMap =
        await _loadLegacyGroupSeenMap(baseUrlOverride: baseUrlOverride);
    final legacySeenIso = (legacyMap[normalizedGroupId] ?? '').trim();
    if (legacySeenIso.isEmpty) {
      return null;
    }
    await _saveGroupSeenEntityMap(
      legacyMap,
      baseUrlOverride: baseUrlOverride,
    );
    await _clearLegacyGroupSeenStorage(baseUrlOverride: baseUrlOverride);
    return legacySeenIso;
  }

  Future<Map<String, String>> loadGroupSeenForGroups(
    Iterable<String> groupIds, {
    String? baseUrlOverride,
  }) async {
    final normalizedGroupIds = <String>{};
    for (final groupId in groupIds) {
      final normalizedGroupId = groupId.trim();
      if (normalizedGroupId.isEmpty) continue;
      normalizedGroupIds.add(normalizedGroupId);
    }
    if (normalizedGroupIds.isEmpty) {
      return <String, String>{};
    }
    final out = <String, String>{};
    for (final groupId in normalizedGroupIds) {
      final seenIso = await loadGroupSeenForGroup(
        groupId,
        baseUrlOverride: baseUrlOverride,
      );
      if (seenIso == null || seenIso.isEmpty) continue;
      out[groupId] = seenIso;
    }
    return out;
  }

  Future<void> saveGroupSeen(
    Map<String, String> seen, {
    String? baseUrlOverride,
  }) async {
    await _saveGroupSeenEntityMap(
      seen,
      baseUrlOverride: baseUrlOverride,
    );
    await _clearLegacyGroupSeenStorage(baseUrlOverride: baseUrlOverride);
  }

  Future<void> saveGroupSeenForGroup(
    String groupId,
    DateTime ts, {
    String? baseUrlOverride,
  }) async {
    final normalizedGroupId = groupId.trim();
    if (normalizedGroupId.isEmpty) return;
    final nextTs = ts.toUtc().toIso8601String();
    final legacyMap =
        await _loadLegacyGroupSeenMap(baseUrlOverride: baseUrlOverride);
    if (legacyMap.isNotEmpty) {
      await _saveGroupSeenEntityMap(
        legacyMap,
        baseUrlOverride: baseUrlOverride,
      );
      await _clearLegacyGroupSeenStorage(baseUrlOverride: baseUrlOverride);
    }
    final currentTs = (await _loadScopedSensitiveEntityPlainString(
              legacyKeyPrefix: _groupSeenPrefix,
              scopedKeyPrefix: _groupSeenEntityScopedKeyPrefix,
              entityId: normalizedGroupId,
              baseUrlOverride: baseUrlOverride,
            ) ??
            '')
        .trim();
    if (currentTs == nextTs) return;
    await _saveScopedSensitiveEntityPlainString(
      legacyKeyPrefix: _groupSeenPrefix,
      scopedKeyPrefix: _groupSeenEntityScopedKeyPrefix,
      entityId: normalizedGroupId,
      value: nextTs,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> setGroupSeen(
    String groupId,
    DateTime ts, {
    String? baseUrlOverride,
  }) async {
    await saveGroupSeenForGroup(
      groupId,
      ts,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<Map<String, String>> loadGroupNames({String? baseUrlOverride}) async {
    return _loadScopedSensitiveStringMap(
      legacyKey: _groupNamesKey,
      scopedKeyPrefix: _groupNamesScopedKeyPrefix,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<String?> loadGroupName(
    String groupId, {
    String? baseUrlOverride,
  }) async {
    final gid = groupId.trim();
    if (gid.isEmpty) return null;
    final map = await loadGroupNames(baseUrlOverride: baseUrlOverride);
    final name = (map[gid] ?? '').trim();
    if (name.isEmpty) return null;
    return name;
  }

  Future<void> saveGroupNames(
    Map<String, String> names, {
    String? baseUrlOverride,
  }) async {
    await _saveScopedSensitiveStringMap(
      legacyKey: _groupNamesKey,
      scopedKeyPrefix: _groupNamesScopedKeyPrefix,
      values: names,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> upsertGroupNames(
    Iterable<ChatGroup> groups, {
    String? baseUrlOverride,
  }) async {
    final names = await loadGroupNames(baseUrlOverride: baseUrlOverride);

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
    await saveGroupNames(names, baseUrlOverride: baseUrlOverride);
  }

  Future<String?> loadGroupNotice(
    String groupId, {
    String? baseUrlOverride,
  }) async {
    final gid = groupId.trim();
    if (gid.isEmpty) return null;
    return _loadScopedSensitiveEntityPlainString(
      legacyKeyPrefix: _groupNoticePrefix,
      scopedKeyPrefix: _groupNoticeScopedKeyPrefix,
      entityId: gid,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> saveGroupNotice(
    String groupId,
    String notice, {
    String? baseUrlOverride,
  }) async {
    final gid = groupId.trim();
    if (gid.isEmpty) return;
    await _saveScopedSensitiveEntityPlainString(
      legacyKeyPrefix: _groupNoticePrefix,
      scopedKeyPrefix: _groupNoticeScopedKeyPrefix,
      entityId: gid,
      value: notice,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<Map<String, String>> loadChatThemes({
    String? baseUrlOverride,
  }) async {
    return _loadScopedSensitiveStringMap(
      legacyKey: _chatWallpaperThemeKey,
      scopedKeyPrefix: _chatWallpaperThemeScopedKeyPrefix,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> saveChatThemes(
    Map<String, String> themes, {
    String? baseUrlOverride,
  }) async {
    await _saveScopedSensitiveStringMap(
      legacyKey: _chatWallpaperThemeKey,
      scopedKeyPrefix: _chatWallpaperThemeScopedKeyPrefix,
      values: themes,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> saveChatThemeForPeer(
    String peerId,
    String themeKey, {
    String? baseUrlOverride,
  }) async {
    final normalizedPeerId = peerId.trim();
    if (normalizedPeerId.isEmpty) return;
    final normalizedThemeKey = themeKey.trim();
    final themes = Map<String, String>.from(
      await loadChatThemes(baseUrlOverride: baseUrlOverride),
    );
    if (normalizedThemeKey.isEmpty || normalizedThemeKey == 'default') {
      themes.remove(normalizedPeerId);
    } else {
      themes[normalizedPeerId] = normalizedThemeKey;
    }
    await saveChatThemes(
      themes,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<String?> loadChatThemeForGroup(
    String groupId, {
    String? baseUrlOverride,
  }) async {
    final normalizedGroupId = groupId.trim();
    if (normalizedGroupId.isEmpty) return null;
    final themes = await loadChatThemes(baseUrlOverride: baseUrlOverride);
    final theme = (themes['grp:$normalizedGroupId'] ?? '').trim();
    return theme.isEmpty ? null : theme;
  }

  Future<void> saveChatThemeForGroup(
    String groupId,
    String themeKey, {
    String? baseUrlOverride,
  }) async {
    final normalizedGroupId = groupId.trim();
    if (normalizedGroupId.isEmpty) return;
    final normalizedThemeKey = themeKey.trim();
    final themes = Map<String, String>.from(
      await loadChatThemes(baseUrlOverride: baseUrlOverride),
    );
    final groupThemeKey = 'grp:$normalizedGroupId';
    if (normalizedThemeKey.isEmpty || normalizedThemeKey == 'default') {
      themes.remove(groupThemeKey);
    } else {
      themes[groupThemeKey] = normalizedThemeKey;
    }
    await saveChatThemes(
      themes,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<Map<String, int>> loadUnread({String? baseUrlOverride}) async {
    final entityMap = await _loadUnreadEntityMap(
      baseUrlOverride: baseUrlOverride,
    );
    if (entityMap.isNotEmpty) {
      return entityMap;
    }
    final legacyMap = await _loadLegacyUnreadMap(
      baseUrlOverride: baseUrlOverride,
    );
    if (legacyMap.isEmpty) {
      return <String, int>{};
    }
    await _saveUnreadEntityMap(
      legacyMap,
      baseUrlOverride: baseUrlOverride,
    );
    await _clearLegacyUnreadStorage(baseUrlOverride: baseUrlOverride);
    return legacyMap;
  }

  Future<int> loadUnreadCountForGroup(
    String groupId, {
    String? baseUrlOverride,
  }) async {
    final normalizedGroupId = groupId.trim();
    if (normalizedGroupId.isEmpty) return 0;
    final groupUnreadKey = 'grp:$normalizedGroupId';
    final unreadRaw = (await _loadScopedSensitiveEntityPlainString(
              legacyKeyPrefix: _unreadPrefix,
              scopedKeyPrefix: _unreadEntityScopedKeyPrefix,
              entityId: groupUnreadKey,
              baseUrlOverride: baseUrlOverride,
            ) ??
            '')
        .trim();
    final unreadCount = int.tryParse(unreadRaw) ?? 0;
    if (unreadCount > 0) {
      return unreadCount;
    }
    final legacyMap = await _loadLegacyUnreadMap(
      baseUrlOverride: baseUrlOverride,
    );
    final legacyCount = legacyMap[groupUnreadKey] ?? 0;
    if (legacyCount <= 0) {
      return 0;
    }
    await _saveUnreadEntityMap(
      legacyMap,
      baseUrlOverride: baseUrlOverride,
    );
    await _clearLegacyUnreadStorage(baseUrlOverride: baseUrlOverride);
    return legacyCount;
  }

  Future<int> loadUnreadCountForPeer(
    String peerId, {
    String? baseUrlOverride,
  }) async {
    final normalizedPeerId = peerId.trim();
    if (normalizedPeerId.isEmpty) return 0;
    final unreadRaw = (await _loadScopedSensitiveEntityPlainString(
              legacyKeyPrefix: _unreadPrefix,
              scopedKeyPrefix: _unreadEntityScopedKeyPrefix,
              entityId: normalizedPeerId,
              baseUrlOverride: baseUrlOverride,
            ) ??
            '')
        .trim();
    final unreadCount = int.tryParse(unreadRaw) ?? 0;
    if (unreadCount > 0) {
      return unreadCount;
    }
    final legacyMap = await _loadLegacyUnreadMap(
      baseUrlOverride: baseUrlOverride,
    );
    final legacyCount = legacyMap[normalizedPeerId] ?? 0;
    if (legacyCount <= 0) {
      return 0;
    }
    await _saveUnreadEntityMap(
      legacyMap,
      baseUrlOverride: baseUrlOverride,
    );
    await _clearLegacyUnreadStorage(baseUrlOverride: baseUrlOverride);
    return legacyCount;
  }

  Future<void> saveUnread(
    Map<String, int> unread, {
    String? baseUrlOverride,
  }) async {
    final cleaned = <String, int>{};
    unread.forEach((peerId, count) {
      final normalizedPeerId = peerId.trim();
      if (normalizedPeerId.isEmpty || count <= 0) return;
      cleaned[normalizedPeerId] = count;
    });
    await _saveUnreadEntityMap(
      cleaned,
      baseUrlOverride: baseUrlOverride,
    );
    await _clearLegacyUnreadStorage(baseUrlOverride: baseUrlOverride);
  }

  Future<void> saveUnreadCountForGroup(
    String groupId,
    int unreadCount, {
    String? baseUrlOverride,
  }) async {
    final normalizedGroupId = groupId.trim();
    if (normalizedGroupId.isEmpty) return;
    final groupUnreadKey = 'grp:$normalizedGroupId';
    await _migrateLegacyUnreadStorage(baseUrlOverride: baseUrlOverride);
    await _saveUnreadCountForKey(
      groupUnreadKey,
      unreadCount,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> saveUnreadCountForPeer(
    String peerId,
    int unreadCount, {
    String? baseUrlOverride,
  }) async {
    final normalizedPeerId = peerId.trim();
    if (normalizedPeerId.isEmpty) return;
    await _migrateLegacyUnreadStorage(baseUrlOverride: baseUrlOverride);
    await _saveUnreadCountForKey(
      normalizedPeerId,
      unreadCount,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> saveUnreadCountsForKeys(
    Map<String, int> unread,
    Iterable<String> unreadKeys, {
    String? baseUrlOverride,
  }) async {
    final normalizedUnreadKeys = unreadKeys
        .map((unreadKey) => unreadKey.trim())
        .where((unreadKey) => unreadKey.isNotEmpty)
        .toSet();
    if (normalizedUnreadKeys.isEmpty) return;
    await _migrateLegacyUnreadStorage(baseUrlOverride: baseUrlOverride);
    for (final unreadKey in normalizedUnreadKeys) {
      await _saveUnreadCountForKey(
        unreadKey,
        unread[unreadKey] ?? 0,
        baseUrlOverride: baseUrlOverride,
      );
    }
  }

  Future<void> setActivePeer(
    String peerId, {
    String? baseUrlOverride,
  }) async {
    await _saveScopedSensitivePlainString(
      legacyKey: _activePeerKey,
      scopedKeyPrefix: _activePeerScopedKeyPrefix,
      value: peerId,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> _migrateLegacyUnreadStorage({
    String? baseUrlOverride,
  }) async {
    final legacyMap = await _loadLegacyUnreadMap(
      baseUrlOverride: baseUrlOverride,
    );
    if (legacyMap.isEmpty) return;
    await _saveUnreadEntityMap(
      legacyMap,
      baseUrlOverride: baseUrlOverride,
    );
    await _clearLegacyUnreadStorage(baseUrlOverride: baseUrlOverride);
  }

  Future<void> _saveUnreadCountForKey(
    String unreadKey,
    int unreadCount, {
    String? baseUrlOverride,
  }) async {
    final normalizedUnreadKey = unreadKey.trim();
    if (normalizedUnreadKey.isEmpty) return;
    if (unreadCount <= 0) {
      final sp = await SharedPreferences.getInstance();
      final scopedKey = _scopedChatEntityStateKey(
        _unreadEntityScopedKeyPrefix,
        _currentChatScopedStateScope(
          sp,
          baseUrlOverride: baseUrlOverride,
        ),
        normalizedUnreadKey,
      );
      await _removeSensitivePrefKey(scopedKey);
      await _removeSensitivePrefKey('$_unreadPrefix$normalizedUnreadKey');
      return;
    }
    final currentRaw = (await _loadScopedSensitiveEntityPlainString(
              legacyKeyPrefix: _unreadPrefix,
              scopedKeyPrefix: _unreadEntityScopedKeyPrefix,
              entityId: normalizedUnreadKey,
              baseUrlOverride: baseUrlOverride,
            ) ??
            '')
        .trim();
    final currentUnreadCount = int.tryParse(currentRaw) ?? 0;
    if (currentUnreadCount == unreadCount) return;
    await _saveScopedSensitiveEntityPlainString(
      legacyKeyPrefix: _unreadPrefix,
      scopedKeyPrefix: _unreadEntityScopedKeyPrefix,
      entityId: normalizedUnreadKey,
      value: unreadCount.toString(),
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<String?> loadActivePeer({String? baseUrlOverride}) async {
    return _loadScopedSensitivePlainString(
      legacyKey: _activePeerKey,
      scopedKeyPrefix: _activePeerScopedKeyPrefix,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<Map<String, String>> _loadOfficialNotifRaw({
    String? baseUrlOverride,
  }) async {
    return _loadScopedSensitiveStringMap(
      legacyKey: _officialNotifKey,
      scopedKeyPrefix: _officialNotifScopedKeyPrefix,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> _saveOfficialNotifRaw(
    Map<String, String> prefs, {
    String? baseUrlOverride,
  }) async {
    await _saveScopedSensitiveStringMap(
      legacyKey: _officialNotifKey,
      scopedKeyPrefix: _officialNotifScopedKeyPrefix,
      values: prefs,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<OfficialNotificationMode?> loadOfficialNotifMode(
    String peerId, {
    String? baseUrlOverride,
  }) async {
    if (peerId.isEmpty) return null;
    final map = await _loadOfficialNotifRaw(baseUrlOverride: baseUrlOverride);
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
    OfficialNotificationMode? mode, {
    String? baseUrlOverride,
  }) async {
    if (peerId.isEmpty) return;
    final map = await _loadOfficialNotifRaw(baseUrlOverride: baseUrlOverride);
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
    await _saveOfficialNotifRaw(map, baseUrlOverride: baseUrlOverride);
  }

  Future<bool> loadServiceNotificationsHasUnread({
    String? baseUrlOverride,
  }) async {
    return _loadScopedSensitiveBoolFlag(
      legacyKey: _serviceNotificationsUnreadKey,
      scopedKeyPrefix: _serviceNotificationsUnreadScopedKeyPrefix,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> saveServiceNotificationsHasUnread(
    bool hasUnread, {
    String? baseUrlOverride,
  }) async {
    await _saveScopedSensitiveBoolFlag(
      legacyKey: _serviceNotificationsUnreadKey,
      scopedKeyPrefix: _serviceNotificationsUnreadScopedKeyPrefix,
      value: hasUnread,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<bool> loadHideServiceNotificationsThread({
    String? baseUrlOverride,
  }) async {
    return _loadScopedSensitiveBoolFlag(
      legacyKey: _hideServiceNotificationsThreadKey,
      scopedKeyPrefix: _hideServiceNotificationsThreadScopedKeyPrefix,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> saveHideServiceNotificationsThread(
    bool hide, {
    String? baseUrlOverride,
  }) async {
    await _saveScopedSensitiveBoolFlag(
      legacyKey: _hideServiceNotificationsThreadKey,
      scopedKeyPrefix: _hideServiceNotificationsThreadScopedKeyPrefix,
      value: hide,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<bool> hasOfficialAutoreplyShown(
    String peerId, {
    String? baseUrlOverride,
  }) async {
    final pid = peerId.trim();
    if (pid.isEmpty) return false;
    return _loadScopedSensitiveEntityBoolFlag(
      legacyKeyPrefix: _officialAutoreplyShownPrefix,
      scopedKeyPrefix: _officialAutoreplyShownScopedKeyPrefix,
      entityId: pid,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> markOfficialAutoreplyShown(
    String peerId, {
    String? baseUrlOverride,
  }) async {
    final pid = peerId.trim();
    if (pid.isEmpty) return;
    await _saveScopedSensitiveEntityBoolFlag(
      legacyKeyPrefix: _officialAutoreplyShownPrefix,
      scopedKeyPrefix: _officialAutoreplyShownScopedKeyPrefix,
      entityId: pid,
      value: true,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> clearOfficialAutoreplyShown(
    String peerId, {
    String? baseUrlOverride,
  }) async {
    final pid = peerId.trim();
    if (pid.isEmpty) return;
    await _saveScopedSensitiveEntityBoolFlag(
      legacyKeyPrefix: _officialAutoreplyShownPrefix,
      scopedKeyPrefix: _officialAutoreplyShownScopedKeyPrefix,
      entityId: pid,
      value: false,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<bool> hasOfficialAutofollowed(
    String officialId, {
    String? baseUrlOverride,
  }) async {
    final oid = officialId.trim();
    if (oid.isEmpty) return false;
    return _loadScopedSensitiveEntityBoolFlag(
      legacyKeyPrefix: _officialAutofollowPrefix,
      scopedKeyPrefix: _officialAutofollowScopedKeyPrefix,
      entityId: oid,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> markOfficialAutofollowed(
    String officialId, {
    String? baseUrlOverride,
  }) async {
    final oid = officialId.trim();
    if (oid.isEmpty) return;
    await _saveScopedSensitiveEntityBoolFlag(
      legacyKeyPrefix: _officialAutofollowPrefix,
      scopedKeyPrefix: _officialAutofollowScopedKeyPrefix,
      entityId: oid,
      value: true,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> clearOfficialAutofollowed(
    String officialId, {
    String? baseUrlOverride,
  }) async {
    final oid = officialId.trim();
    if (oid.isEmpty) return;
    await _saveScopedSensitiveEntityBoolFlag(
      legacyKeyPrefix: _officialAutofollowPrefix,
      scopedKeyPrefix: _officialAutofollowScopedKeyPrefix,
      entityId: oid,
      value: false,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<bool> hasOfficialAutochat(
    String peerId, {
    String? baseUrlOverride,
  }) async {
    final pid = peerId.trim();
    if (pid.isEmpty) return false;
    return _loadScopedSensitiveEntityBoolFlag(
      legacyKeyPrefix: _officialAutochatPrefix,
      scopedKeyPrefix: _officialAutochatScopedKeyPrefix,
      entityId: pid,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> markOfficialAutochat(
    String peerId, {
    String? baseUrlOverride,
  }) async {
    final pid = peerId.trim();
    if (pid.isEmpty) return;
    await _saveScopedSensitiveEntityBoolFlag(
      legacyKeyPrefix: _officialAutochatPrefix,
      scopedKeyPrefix: _officialAutochatScopedKeyPrefix,
      entityId: pid,
      value: true,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> clearOfficialAutochat(
    String peerId, {
    String? baseUrlOverride,
  }) async {
    final pid = peerId.trim();
    if (pid.isEmpty) return;
    await _saveScopedSensitiveEntityBoolFlag(
      legacyKeyPrefix: _officialAutochatPrefix,
      scopedKeyPrefix: _officialAutochatScopedKeyPrefix,
      entityId: pid,
      value: false,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> setNotifyPreview(
    bool enabled, {
    String? baseUrlOverride,
  }) async {
    await _saveScopedDeviceBoolPreference(
      legacySecureKey: _notifyPreviewSecureKey,
      scopedSecureKeyPrefix: _notifyPreviewScopedSecureKeyPrefix,
      legacyPrefKey: _notifyPreviewKey,
      scopedPrefKeyPrefix: _notifyPreviewScopedKeyPrefix,
      value: enabled,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<bool> loadNotifyPreview({String? baseUrlOverride}) async {
    return _loadScopedDeviceBoolPreference(
      legacySecureKey: _notifyPreviewSecureKey,
      scopedSecureKeyPrefix: _notifyPreviewScopedSecureKeyPrefix,
      legacyPrefKey: _notifyPreviewKey,
      scopedPrefKeyPrefix: _notifyPreviewScopedKeyPrefix,
      defaultValue: false,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> setNotifyEnabled(
    bool enabled, {
    String? baseUrlOverride,
  }) async {
    await _saveScopedDeviceBoolPreference(
      legacySecureKey: _notifyEnabledSecureKey,
      scopedSecureKeyPrefix: _notifyEnabledScopedSecureKeyPrefix,
      legacyPrefKey: _notifyEnabledKey,
      scopedPrefKeyPrefix: _notifyEnabledScopedKeyPrefix,
      value: enabled,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<bool> loadNotifyEnabled({String? baseUrlOverride}) async {
    return _loadScopedDeviceBoolPreference(
      legacySecureKey: _notifyEnabledSecureKey,
      scopedSecureKeyPrefix: _notifyEnabledScopedSecureKeyPrefix,
      legacyPrefKey: _notifyEnabledKey,
      scopedPrefKeyPrefix: _notifyEnabledScopedKeyPrefix,
      defaultValue: true,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> setNotifySound(
    bool enabled, {
    String? baseUrlOverride,
  }) async {
    await _saveScopedDeviceBoolPreference(
      legacySecureKey: _notifySoundSecureKey,
      scopedSecureKeyPrefix: _notifySoundScopedSecureKeyPrefix,
      legacyPrefKey: _notifySoundKey,
      scopedPrefKeyPrefix: _notifySoundScopedKeyPrefix,
      value: enabled,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<bool> loadNotifySound({String? baseUrlOverride}) async {
    return _loadScopedDeviceBoolPreference(
      legacySecureKey: _notifySoundSecureKey,
      scopedSecureKeyPrefix: _notifySoundScopedSecureKeyPrefix,
      legacyPrefKey: _notifySoundKey,
      scopedPrefKeyPrefix: _notifySoundScopedKeyPrefix,
      defaultValue: true,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> setNotifyVibrate(
    bool enabled, {
    String? baseUrlOverride,
  }) async {
    await _saveScopedDeviceBoolPreference(
      legacySecureKey: _notifyVibrateSecureKey,
      scopedSecureKeyPrefix: _notifyVibrateScopedSecureKeyPrefix,
      legacyPrefKey: _notifyVibrateKey,
      scopedPrefKeyPrefix: _notifyVibrateScopedKeyPrefix,
      value: enabled,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<bool> loadNotifyVibrate({String? baseUrlOverride}) async {
    return _loadScopedDeviceBoolPreference(
      legacySecureKey: _notifyVibrateSecureKey,
      scopedSecureKeyPrefix: _notifyVibrateScopedSecureKeyPrefix,
      legacyPrefKey: _notifyVibrateKey,
      scopedPrefKeyPrefix: _notifyVibrateScopedKeyPrefix,
      defaultValue: true,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> setNotifyDndEnabled(
    bool enabled, {
    String? baseUrlOverride,
  }) async {
    await _saveScopedDeviceBoolPreference(
      legacySecureKey: _notifyDndSecureKey,
      scopedSecureKeyPrefix: _notifyDndScopedSecureKeyPrefix,
      legacyPrefKey: _notifyDndKey,
      scopedPrefKeyPrefix: _notifyDndScopedKeyPrefix,
      value: enabled,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<bool> loadNotifyDndEnabled({String? baseUrlOverride}) async {
    return _loadScopedDeviceBoolPreference(
      legacySecureKey: _notifyDndSecureKey,
      scopedSecureKeyPrefix: _notifyDndScopedSecureKeyPrefix,
      legacyPrefKey: _notifyDndKey,
      scopedPrefKeyPrefix: _notifyDndScopedKeyPrefix,
      defaultValue: false,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> setNotifyDndSchedule({
    required int startMinutes,
    required int endMinutes,
    String? baseUrlOverride,
  }) async {
    final start = startMinutes.clamp(0, 24 * 60 - 1).toInt();
    final end = endMinutes.clamp(0, 24 * 60 - 1).toInt();
    await _saveScopedDeviceIntPreference(
      legacySecureKey: _notifyDndStartSecureKey,
      scopedSecureKeyPrefix: _notifyDndStartScopedSecureKeyPrefix,
      legacyPrefKey: _notifyDndStartKey,
      scopedPrefKeyPrefix: _notifyDndStartScopedKeyPrefix,
      value: start,
      min: 0,
      max: 24 * 60 - 1,
      baseUrlOverride: baseUrlOverride,
    );
    await _saveScopedDeviceIntPreference(
      legacySecureKey: _notifyDndEndSecureKey,
      scopedSecureKeyPrefix: _notifyDndEndScopedSecureKeyPrefix,
      legacyPrefKey: _notifyDndEndKey,
      scopedPrefKeyPrefix: _notifyDndEndScopedKeyPrefix,
      value: end,
      min: 0,
      max: 24 * 60 - 1,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<int> loadNotifyDndStartMinutes({String? baseUrlOverride}) async {
    return _loadScopedDeviceIntPreference(
      legacySecureKey: _notifyDndStartSecureKey,
      scopedSecureKeyPrefix: _notifyDndStartScopedSecureKeyPrefix,
      legacyPrefKey: _notifyDndStartKey,
      scopedPrefKeyPrefix: _notifyDndStartScopedKeyPrefix,
      defaultValue: _notifyDndDefaultStart,
      min: 0,
      max: 24 * 60 - 1,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<int> loadNotifyDndEndMinutes({String? baseUrlOverride}) async {
    return _loadScopedDeviceIntPreference(
      legacySecureKey: _notifyDndEndSecureKey,
      scopedSecureKeyPrefix: _notifyDndEndScopedSecureKeyPrefix,
      legacyPrefKey: _notifyDndEndKey,
      scopedPrefKeyPrefix: _notifyDndEndScopedKeyPrefix,
      defaultValue: _notifyDndDefaultEnd,
      min: 0,
      max: 24 * 60 - 1,
      baseUrlOverride: baseUrlOverride,
    );
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
      })> loadNotifyConfig({
    String? baseUrlOverride,
  }) async {
    return (
      enabled: await loadNotifyEnabled(baseUrlOverride: baseUrlOverride),
      preview: await loadNotifyPreview(baseUrlOverride: baseUrlOverride),
      sound: await loadNotifySound(baseUrlOverride: baseUrlOverride),
      vibrate: await loadNotifyVibrate(baseUrlOverride: baseUrlOverride),
      dnd: await loadNotifyDndEnabled(baseUrlOverride: baseUrlOverride),
      dndStart:
          await loadNotifyDndStartMinutes(baseUrlOverride: baseUrlOverride),
      dndEnd: await loadNotifyDndEndMinutes(baseUrlOverride: baseUrlOverride),
    );
  }

  Future<void> clearNotifyPreferences({
    String? preserveBaseUrlOverride,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final preservedPrefKeys = preserveBaseUrlOverride == null
        ? const <String>{}
        : shamellCurrentScopedNotifyPreferencePrefKeys(
            sp: sp,
            baseUrlOverride: preserveBaseUrlOverride,
          );
    final preservedSecureKeys = preserveBaseUrlOverride == null
        ? const <String>{}
        : _currentScopedNotifyPreferenceSecureKeys(
            sp: sp,
            baseUrlOverride: preserveBaseUrlOverride,
          );
    final legacyPrefKeys = <String>{
      _notifyPreviewKey,
      _notifyEnabledKey,
      _notifySoundKey,
      _notifyVibrateKey,
      _notifyDndKey,
      _notifyDndStartKey,
      _notifyDndEndKey,
    };
    final scopedPrefPrefixes = <String>{
      _notifyPreviewScopedKeyPrefix,
      _notifyEnabledScopedKeyPrefix,
      _notifySoundScopedKeyPrefix,
      _notifyVibrateScopedKeyPrefix,
      _notifyDndScopedKeyPrefix,
      _notifyDndStartScopedKeyPrefix,
      _notifyDndEndScopedKeyPrefix,
    };
    final secureKeys = <String>{
      _notifyPreviewSecureKey,
      _notifyEnabledSecureKey,
      _notifySoundSecureKey,
      _notifyVibrateSecureKey,
      _notifyDndSecureKey,
      _notifyDndStartSecureKey,
      _notifyDndEndSecureKey,
    };
    final scopedSecurePrefixes = <String>{
      _notifyPreviewScopedSecureKeyPrefix,
      _notifyEnabledScopedSecureKeyPrefix,
      _notifySoundScopedSecureKeyPrefix,
      _notifyVibrateScopedSecureKeyPrefix,
      _notifyDndScopedSecureKeyPrefix,
      _notifyDndStartScopedSecureKeyPrefix,
      _notifyDndEndScopedSecureKeyPrefix,
    };

    for (final key in sp.getKeys()) {
      if (legacyPrefKeys.contains(key) ||
          scopedPrefPrefixes.any(key.startsWith)) {
        if (preservedPrefKeys.contains(key)) {
          continue;
        }
        try {
          await sp.remove(key);
        } catch (_) {}
      }
    }

    if (!_useSecureStore()) return;
    try {
      final sec = _sec();
      final all = await sec.readAll();
      for (final key in all.keys) {
        if (secureKeys.contains(key) ||
            scopedSecurePrefixes.any(key.startsWith)) {
          if (preservedSecureKeys.contains(key)) {
            continue;
          }
          try {
            await sec.delete(key: key);
          } catch (_) {}
        }
      }
    } catch (_) {
      try {
        final sec = _sec();
        for (final key in secureKeys) {
          try {
            await sec.delete(key: key);
          } catch (_) {}
        }
      } catch (_) {}
    }
  }

  Future<bool> isVerified(
    String peerId,
    String fp, {
    String? baseUrlOverride,
  }) async {
    final pid = peerId.trim();
    if (pid.isEmpty) return false;
    final stored = await _loadScopedSensitiveEntityPlainString(
      legacyKeyPrefix: 'chat.ver.',
      scopedKeyPrefix: _verifiedFingerprintScopedKeyPrefix,
      entityId: pid,
      baseUrlOverride: baseUrlOverride,
    );
    return stored == fp;
  }

  Future<void> markVerified(
    String peerId,
    String fp, {
    String? baseUrlOverride,
  }) async {
    final pid = peerId.trim();
    if (pid.isEmpty) return;
    await _saveScopedSensitiveEntityPlainString(
      legacyKeyPrefix: 'chat.ver.',
      scopedKeyPrefix: _verifiedFingerprintScopedKeyPrefix,
      entityId: pid,
      value: fp,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<Map<String, String>> loadSessionKeys({
    String? baseUrlOverride,
  }) async {
    final raw = await _loadScopedSecureString(
      legacyKey: _sessionKeyMap,
      scopedKeyPrefix: _sessionKeyMapScopedKeyPrefix,
      baseUrlOverride: baseUrlOverride,
    );
    if (raw == null || raw.isEmpty) return {};
    final map = (jsonDecode(raw) as Map<String, Object?>);
    return map.map((k, v) => MapEntry(k, v.toString()));
  }

  Future<String?> loadGroupKey(
    String groupId, {
    String? baseUrlOverride,
  }) async {
    if (groupId.isEmpty) return null;
    return await _loadScopedSecureEntityString(
      legacyKeyPrefix: _groupKeyPrefix,
      scopedKeyPrefix: _groupKeyScopedKeyPrefix,
      entityId: groupId,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> saveGroupKey(
    String groupId,
    String keyB64, {
    String? baseUrlOverride,
  }) async {
    if (groupId.isEmpty || keyB64.isEmpty) return;
    await _saveScopedSecureEntityString(
      legacyKeyPrefix: _groupKeyPrefix,
      scopedKeyPrefix: _groupKeyScopedKeyPrefix,
      entityId: groupId,
      value: keyB64,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> deleteGroupKey(
    String groupId, {
    String? baseUrlOverride,
  }) async {
    if (groupId.isEmpty) return;
    await _deleteScopedSecureEntityString(
      legacyKeyPrefix: _groupKeyPrefix,
      scopedKeyPrefix: _groupKeyScopedKeyPrefix,
      entityId: groupId,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> saveSessionKey(
    String peerId,
    String keyB64, {
    String? baseUrlOverride,
  }) async {
    final map = await loadSessionKeys(baseUrlOverride: baseUrlOverride);
    map[peerId] = keyB64;
    await _saveScopedSecureString(
      legacyKey: _sessionKeyMap,
      scopedKeyPrefix: _sessionKeyMapScopedKeyPrefix,
      value: jsonEncode(map),
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> saveSessionBootstrapMeta(
    String peerId, {
    required String protocolFloor,
    required int signedPrekeyId,
    int? oneTimePrekeyId,
    required bool v2Only,
    String? identitySigningPubkeyB64,
    String? baseUrlOverride,
  }) async {
    final pid = peerId.trim();
    if (pid.isEmpty) return;
    final signingKey = (identitySigningPubkeyB64 ?? '').trim();
    await _saveScopedSecureEntityString(
      legacyKeyPrefix: _sessionBootstrapPrefix,
      scopedKeyPrefix: _sessionBootstrapScopedKeyPrefix,
      entityId: pid,
      value: jsonEncode({
        'peer_id': pid,
        'protocol_floor': protocolFloor,
        'signed_prekey_id': signedPrekeyId,
        'one_time_prekey_id': oneTimePrekeyId,
        'v2_only': v2Only,
        if (signingKey.isNotEmpty) 'identity_signing_pubkey_b64': signingKey,
        'bootstrapped_at': DateTime.now().toUtc().toIso8601String(),
      }),
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<Map<String, Object?>> loadSessionBootstrapMeta(
    String peerId, {
    String? baseUrlOverride,
  }) async {
    final pid = peerId.trim();
    if (pid.isEmpty) return <String, Object?>{};
    final raw = await _loadScopedSecureEntityString(
      legacyKeyPrefix: _sessionBootstrapPrefix,
      scopedKeyPrefix: _sessionBootstrapScopedKeyPrefix,
      entityId: pid,
      baseUrlOverride: baseUrlOverride,
    );
    if (raw == null || raw.isEmpty) return <String, Object?>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
    return <String, Object?>{};
  }

  Future<String?> loadPinnedIdentitySigningPubkey(
    String peerId, {
    String? baseUrlOverride,
  }) async {
    final meta = await loadSessionBootstrapMeta(
      peerId,
      baseUrlOverride: baseUrlOverride,
    );
    final raw = (meta['identity_signing_pubkey_b64'] ?? '').toString().trim();
    if (raw.isEmpty) return null;
    return raw;
  }

  Future<void> deleteSessionBootstrapMeta(
    String peerId, {
    String? baseUrlOverride,
  }) async {
    final pid = peerId.trim();
    if (pid.isEmpty) return;
    await _deleteScopedSecureEntityString(
      legacyKeyPrefix: _sessionBootstrapPrefix,
      scopedKeyPrefix: _sessionBootstrapScopedKeyPrefix,
      entityId: pid,
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<Map<String, Map<String, Object>>> loadChains({
    String? baseUrlOverride,
  }) async {
    final raw = await _loadScopedSecureString(
      legacyKey: _chainMap,
      scopedKeyPrefix: _chainMapScopedKeyPrefix,
      baseUrlOverride: baseUrlOverride,
    );
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, Map<String, Object>>{};
      decoded.forEach((k, v) {
        if (v is! Map) return;
        final inner = <String, Object>{};
        v.forEach((k2, v2) {
          inner[k2.toString()] = v2 ?? '';
        });
        out[k.toString()] = inner;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> saveChain(
    String peerId,
    Map<String, Object> state, {
    String? baseUrlOverride,
  }) async {
    final map = await loadChains(baseUrlOverride: baseUrlOverride);
    map[peerId] = state;
    await _saveScopedSecureString(
      legacyKey: _chainMap,
      scopedKeyPrefix: _chainMapScopedKeyPrefix,
      value: jsonEncode(map),
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<Map<String, Object>> loadRatchet(
    String peerId, {
    String? baseUrlOverride,
  }) async {
    final raw = await _loadScopedSecureEntityString(
      legacyKeyPrefix: '$_ratchetMap.',
      scopedKeyPrefix: _ratchetScopedKeyPrefix,
      entityId: peerId,
      baseUrlOverride: baseUrlOverride,
    );
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, Object>{};
      decoded.forEach((k, v) {
        out[k.toString()] = v ?? '';
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> saveRatchet(
    String peerId,
    Map<String, Object> state, {
    String? baseUrlOverride,
  }) async {
    await _saveScopedSecureEntityString(
      legacyKeyPrefix: '$_ratchetMap.',
      scopedKeyPrefix: _ratchetScopedKeyPrefix,
      entityId: peerId,
      value: jsonEncode(state),
      baseUrlOverride: baseUrlOverride,
    );
  }

  Future<void> deleteRatchet(
    String peerId, {
    String? baseUrlOverride,
  }) async {
    await _deleteScopedSecureEntityString(
      legacyKeyPrefix: '$_ratchetMap.',
      scopedKeyPrefix: _ratchetScopedKeyPrefix,
      entityId: peerId,
      baseUrlOverride: baseUrlOverride,
    );
  }

  static const _notifyPreviewKey = 'chat.notify.preview';
  static const _notifyEnabledKey = 'chat.notify.enabled';
  static const _notifySoundKey = 'chat.notify.sound';
  static const _notifyVibrateKey = 'chat.notify.vibrate';
  static const _notifyDndKey = 'chat.notify.dnd';
  static const _notifyDndStartKey = 'chat.notify.dnd_start';
  static const _notifyDndEndKey = 'chat.notify.dnd_end';
  static const _notifyPreviewSecureKey = 'notify.preview.v1';
  static const _notifyEnabledSecureKey = 'notify.enabled.v1';
  static const _notifySoundSecureKey = 'notify.sound.v1';
  static const _notifyVibrateSecureKey = 'notify.vibrate.v1';
  static const _notifyDndSecureKey = 'notify.dnd.v1';
  static const _notifyDndStartSecureKey = 'notify.dnd_start.v1';
  static const _notifyDndEndSecureKey = 'notify.dnd_end.v1';
  static const _notifyPreviewScopedKeyPrefix = 'chat.notify.preview.v2.';
  static const _notifyEnabledScopedKeyPrefix = 'chat.notify.enabled.v2.';
  static const _notifySoundScopedKeyPrefix = 'chat.notify.sound.v2.';
  static const _notifyVibrateScopedKeyPrefix = 'chat.notify.vibrate.v2.';
  static const _notifyDndScopedKeyPrefix = 'chat.notify.dnd.v2.';
  static const _notifyDndStartScopedKeyPrefix = 'chat.notify.dnd_start.v2.';
  static const _notifyDndEndScopedKeyPrefix = 'chat.notify.dnd_end.v2.';
  static const _notifyPreviewScopedSecureKeyPrefix = 'notify.preview.v2.';
  static const _notifyEnabledScopedSecureKeyPrefix = 'notify.enabled.v2.';
  static const _notifySoundScopedSecureKeyPrefix = 'notify.sound.v2.';
  static const _notifyVibrateScopedSecureKeyPrefix = 'notify.vibrate.v2.';
  static const _notifyDndScopedSecureKeyPrefix = 'notify.dnd.v2.';
  static const _notifyDndStartScopedSecureKeyPrefix = 'notify.dnd_start.v2.';
  static const _notifyDndEndScopedSecureKeyPrefix = 'notify.dnd_end.v2.';
  static const int _notifyDndDefaultStart = 22 * 60;
  static const int _notifyDndDefaultEnd = 8 * 60;
  static const _sessionKeyMap = 'chat.session.keys';
  static const _sessionKeyMapScopedKeyPrefix = 'chat.session.keys.v2.';
  static const _chainMap = 'chat.session.chain';
  static const _chainMapScopedKeyPrefix = 'chat.session.chain.v2.';
  static const _ratchetMap = 'chat.ratchet';
  static const _ratchetScopedKeyPrefix = 'chat.ratchet.v2.';
  static const _groupKeyPrefix = 'chat.grp.key.';
  static const _groupKeyScopedKeyPrefix = 'chat.grp.key.v2.';
  static const _sessionBootstrapPrefix = 'chat.session.bootstrap.';
  static const _sessionBootstrapScopedKeyPrefix = 'chat.session.bootstrap.v2.';

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

  bool _allowLegacySecretFallback() {
    if (kIsWeb) return false;
    final isDesktop = defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
    if (!isDesktop) return false;
    if (kReleaseMode) {
      return const bool.fromEnvironment(
        'ALLOW_LEGACY_CHAT_SECRET_FALLBACK_IN_RELEASE',
        defaultValue: false,
      );
    }
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_CHAT_SECRET_FALLBACK',
      defaultValue: true,
    );
  }

  String _legacySecretFallbackKey(String key) =>
      '$_legacySecretFallbackPrefix$key';

  static const _prefsCryptoKeyName = 'device.local.enc_key.v1';
  static const _prefsCryptoLegacyKeyName = 'chat.local.enc_key.v1';
  static Uint8List? _prefsCryptoKeyCache;

  Future<Uint8List?> _prefsCryptoKey() async {
    if (!_useSecureStore()) return null;
    if (_prefsCryptoKeyCache != null && _prefsCryptoKeyCache!.length == 32) {
      return _prefsCryptoKeyCache;
    }
    Future<Uint8List?> loadPersistedKey(String keyName) async {
      try {
        final raw = (await _secureRead(keyName) ?? '').trim();
        if (raw.isEmpty) return null;
        final bytes = base64Decode(raw);
        if (bytes.length != 32) return null;
        return bytes;
      } catch (_) {
        return null;
      }
    }

    Future<bool> persistCurrentKey(Uint8List bytes) async {
      try {
        final encoded = base64Encode(bytes);
        await _secureWrite(_prefsCryptoKeyName, encoded);
        final roundTrip = (await _secureRead(_prefsCryptoKeyName) ?? '').trim();
        if (roundTrip != encoded) {
          return false;
        }
        try {
          await _sec().delete(key: _prefsCryptoLegacyKeyName);
        } catch (_) {}
        return true;
      } catch (_) {
        return false;
      }
    }

    try {
      final current = await loadPersistedKey(_prefsCryptoKeyName);
      if (current != null) {
        _prefsCryptoKeyCache = current;
        return current;
      }
      final legacy = await loadPersistedKey(_prefsCryptoLegacyKeyName);
      if (legacy != null) {
        await persistCurrentKey(legacy);
        _prefsCryptoKeyCache = legacy;
        return legacy;
      }
    } catch (_) {}
    try {
      final rng = Random.secure();
      final bytes = Uint8List(32);
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = rng.nextInt(256);
      }
      if (await persistCurrentKey(bytes)) {
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

  Future<void> wipeSecrets({bool preservePrefsCryptoKey = false}) async {
    _prefsCryptoKeyCache = null;
    if (_useSecureStore()) {
      try {
        final sec = _sec();
        final all = await sec.readAll();
        for (final k in all.keys) {
          if (!k.startsWith('chat.')) continue;
          try {
            await sec.delete(key: k);
          } catch (_) {}
        }
        if (!preservePrefsCryptoKey) {
          try {
            await sec.delete(key: _prefsCryptoKeyName);
          } catch (_) {}
        }
      } catch (_) {
        // Best-effort fallback: delete high-value keys we can name.
        try {
          final sec = _sec();
          await sec.delete(key: _idKey);
          await sec.delete(key: _sessionKeyMap);
          await sec.delete(key: _chainMap);
          await sec.delete(key: _prefsCryptoLegacyKeyName);
          if (!preservePrefsCryptoKey) {
            await sec.delete(key: _prefsCryptoKeyName);
          }
        } catch (_) {}
      }
    }
    if (_allowLegacySecretFallback()) {
      try {
        final sp = await SharedPreferences.getInstance();
        final toRemove = sp
            .getKeys()
            .where((k) => k.startsWith(_legacySecretFallbackPrefix))
            .toList(growable: false);
        for (final key in toRemove) {
          try {
            await sp.remove(key);
          } catch (_) {}
        }
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

  Future<List<String>> _loadSensitiveStringList(String key) async {
    final sp = await SharedPreferences.getInstance();
    String? raw;
    try {
      raw = sp.getString(key);
    } catch (_) {
      raw = null;
    }
    if (raw != null && raw.isNotEmpty) {
      try {
        final decodedRaw = (await _decryptSensitivePrefsString(raw)) ?? raw;
        final values = _normalizeStringList(jsonDecode(decodedRaw) as List);
        if (decodedRaw == raw) {
          await _saveSensitiveStringList(key, values);
        }
        return values;
      } catch (_) {
        return <String>[];
      }
    }

    List<String>? legacy;
    try {
      legacy = sp.getStringList(key);
    } catch (_) {
      legacy = null;
    }
    if (legacy == null || legacy.isEmpty) return <String>[];
    final values = _normalizeStringList(legacy);
    await _saveSensitiveStringList(key, values);
    return values;
  }

  Future<List<String>> _loadScopedSensitiveStringList({
    required String legacyKey,
    required String scopedKeyPrefix,
    String? baseUrlOverride,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final scope = _currentChatScopedStateScope(
      sp,
      baseUrlOverride: baseUrlOverride,
    );
    final scopedKey = _scopedChatStateKey(scopedKeyPrefix, scope);

    final scoped = await _loadSensitiveStringList(scopedKey);
    if (scoped.isNotEmpty) {
      await _removeSensitivePrefKey(legacyKey);
      return scoped;
    }

    final legacy = await _loadSensitiveStringList(legacyKey);
    if (legacy.isEmpty) return <String>[];

    await _removeSensitivePrefKey(legacyKey);
    if (_isUnknownChatScopedStateScope(scope)) {
      await _saveSensitiveStringList(scopedKey, legacy);
      return legacy;
    }
    return <String>[];
  }

  Future<Set<String>> _loadScopedSensitiveStringSet({
    required String legacyKey,
    required String scopedKeyPrefix,
    String? baseUrlOverride,
  }) async {
    return _loadScopedSensitiveStringList(
      legacyKey: legacyKey,
      scopedKeyPrefix: scopedKeyPrefix,
      baseUrlOverride: baseUrlOverride,
    ).then((values) => values.toSet());
  }

  Future<String?> _loadSensitivePlainString(String key) async {
    final sp = await SharedPreferences.getInstance();
    final raw = (sp.getString(key) ?? '').trim();
    if (raw.isEmpty) return null;
    try {
      final decodedRaw =
          ((await _decryptSensitivePrefsString(raw)) ?? raw).trim();
      if (decodedRaw.isEmpty) {
        await sp.remove(key);
        return null;
      }
      if (decodedRaw == raw) {
        await _saveSensitivePlainString(key, decodedRaw);
      }
      return decodedRaw;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _loadScopedSensitivePlainString({
    required String legacyKey,
    required String scopedKeyPrefix,
    String? baseUrlOverride,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final scope = _currentChatScopedStateScope(
      sp,
      baseUrlOverride: baseUrlOverride,
    );
    final scopedKey = _scopedChatStateKey(scopedKeyPrefix, scope);

    final scoped = await _loadSensitivePlainString(scopedKey);
    if (scoped != null && scoped.isNotEmpty) {
      await _removeSensitivePrefKey(legacyKey);
      return scoped;
    }

    final legacy = await _loadSensitivePlainString(legacyKey);
    if (legacy == null || legacy.isEmpty) return null;

    await _removeSensitivePrefKey(legacyKey);
    if (_isUnknownChatScopedStateScope(scope)) {
      await _saveSensitivePlainString(scopedKey, legacy);
      return legacy;
    }
    return null;
  }

  Future<bool?> _readSensitiveBoolFlagRaw(String key) async {
    final sp = await SharedPreferences.getInstance();
    try {
      final raw = (sp.getString(key) ?? '').trim();
      if (raw.isNotEmpty) {
        final decodedRaw =
            ((await _decryptSensitivePrefsString(raw)) ?? raw).trim();
        final value = _parseSensitiveBool(decodedRaw);
        if (value != null) {
          return value;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, String>> _loadScopedSensitiveStringMap({
    required String legacyKey,
    required String scopedKeyPrefix,
    String? baseUrlOverride,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final scope = _currentChatScopedStateScope(
      sp,
      baseUrlOverride: baseUrlOverride,
    );
    final scopedKey = _scopedChatStateKey(scopedKeyPrefix, scope);

    final scoped = await _loadSensitiveStringMap(scopedKey);
    if (scoped.isNotEmpty) {
      await _removeSensitivePrefKey(legacyKey);
      return scoped;
    }

    final legacy = await _loadSensitiveStringMap(legacyKey);
    if (legacy.isEmpty) return <String, String>{};

    await _removeSensitivePrefKey(legacyKey);
    if (_isUnknownChatScopedStateScope(scope)) {
      await _saveSensitiveStringMap(scopedKey, legacy);
      return legacy;
    }
    return <String, String>{};
  }

  Future<void> _saveScopedSensitiveStringMap({
    required String legacyKey,
    required String scopedKeyPrefix,
    required Map<String, String> values,
    String? baseUrlOverride,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final scopedKey = _scopedChatStateKey(
      scopedKeyPrefix,
      _currentChatScopedStateScope(
        sp,
        baseUrlOverride: baseUrlOverride,
      ),
    );
    await _saveSensitiveStringMap(scopedKey, values);
    await _removeSensitivePrefKey(legacyKey);
  }

  Future<Map<String, String>> _loadScopedSensitiveEntityStringMap({
    required String legacyKeyPrefix,
    required String scopedKeyPrefix,
    required String entityId,
    String? baseUrlOverride,
  }) async {
    final normalizedEntityId = entityId.trim();
    if (normalizedEntityId.isEmpty) return <String, String>{};
    final legacyKey = '$legacyKeyPrefix$normalizedEntityId';
    final sp = await SharedPreferences.getInstance();
    final scope = _currentChatScopedStateScope(
      sp,
      baseUrlOverride: baseUrlOverride,
    );
    final scopedKey = _scopedChatEntityStateKey(
      scopedKeyPrefix,
      scope,
      normalizedEntityId,
    );

    final scoped = await _loadSensitiveStringMap(scopedKey);
    if (scoped.isNotEmpty) {
      await _removeSensitivePrefKey(legacyKey);
      return scoped;
    }

    final legacy = await _loadSensitiveStringMap(legacyKey);
    if (legacy.isEmpty) return <String, String>{};

    await _removeSensitivePrefKey(legacyKey);
    if (_isUnknownChatScopedStateScope(scope)) {
      await _saveSensitiveStringMap(scopedKey, legacy);
      return legacy;
    }
    return <String, String>{};
  }

  Future<void> _saveScopedSensitiveEntityStringMap({
    required String legacyKeyPrefix,
    required String scopedKeyPrefix,
    required String entityId,
    required Map<String, String> values,
    String? baseUrlOverride,
  }) async {
    final normalizedEntityId = entityId.trim();
    if (normalizedEntityId.isEmpty) return;
    final legacyKey = '$legacyKeyPrefix$normalizedEntityId';
    final sp = await SharedPreferences.getInstance();
    final scopedKey = _scopedChatEntityStateKey(
      scopedKeyPrefix,
      _currentChatScopedStateScope(
        sp,
        baseUrlOverride: baseUrlOverride,
      ),
      normalizedEntityId,
    );
    await _saveSensitiveStringMap(scopedKey, values);
    await _removeSensitivePrefKey(legacyKey);
  }

  Future<void> _saveScopedSensitiveStringList({
    required String legacyKey,
    required String scopedKeyPrefix,
    required Iterable<String> values,
    String? baseUrlOverride,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final scopedKey = _scopedChatStateKey(
      scopedKeyPrefix,
      _currentChatScopedStateScope(
        sp,
        baseUrlOverride: baseUrlOverride,
      ),
    );
    await _saveSensitiveStringList(scopedKey, values);
    await _removeSensitivePrefKey(legacyKey);
  }

  Future<bool> _loadScopedSensitiveBoolFlag({
    required String legacyKey,
    required String scopedKeyPrefix,
    String? baseUrlOverride,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final scope = _currentChatScopedStateScope(
      sp,
      baseUrlOverride: baseUrlOverride,
    );
    final scopedKey = _scopedChatStateKey(scopedKeyPrefix, scope);

    final scoped = await _readSensitiveBoolFlagRaw(scopedKey);
    if (scoped != null) {
      await _removeSensitivePrefKey(legacyKey);
      return scoped;
    }

    bool? legacy;
    try {
      legacy = sp.getBool(legacyKey);
    } catch (_) {
      legacy = null;
    }
    legacy ??= await _readSensitiveBoolFlagRaw(legacyKey);
    if (legacy == null) return false;

    await _removeSensitivePrefKey(legacyKey);
    if (_isUnknownChatScopedStateScope(scope)) {
      await _saveSensitiveBoolFlag(scopedKey, legacy);
      return legacy;
    }
    return false;
  }

  Future<void> _saveScopedSensitiveBoolFlag({
    required String legacyKey,
    required String scopedKeyPrefix,
    required bool value,
    String? baseUrlOverride,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final scopedKey = _scopedChatStateKey(
      scopedKeyPrefix,
      _currentChatScopedStateScope(
        sp,
        baseUrlOverride: baseUrlOverride,
      ),
    );
    await _saveSensitiveBoolFlag(scopedKey, value);
    await _removeSensitivePrefKey(legacyKey);
  }

  Future<void> _saveScopedSensitivePlainString({
    required String legacyKey,
    required String scopedKeyPrefix,
    required String value,
    String? baseUrlOverride,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final scopedKey = _scopedChatStateKey(
      scopedKeyPrefix,
      _currentChatScopedStateScope(
        sp,
        baseUrlOverride: baseUrlOverride,
      ),
    );
    await _saveSensitivePlainString(scopedKey, value);
    await _removeSensitivePrefKey(legacyKey);
  }

  Future<String?> _loadScopedSecureString({
    required String legacyKey,
    required String scopedKeyPrefix,
    String? baseUrlOverride,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final scope = _currentChatScopedStateScope(
      sp,
      baseUrlOverride: baseUrlOverride,
    );
    final scopedKey = _scopedChatStateKey(scopedKeyPrefix, scope);

    final scoped = (await _secureRead(scopedKey) ?? '').trim();
    if (scoped.isNotEmpty) {
      await _secureDelete(legacyKey);
      return scoped;
    }

    final legacy = (await _secureRead(legacyKey) ?? '').trim();
    if (legacy.isEmpty) return null;

    await _secureDelete(legacyKey);
    if (_isUnknownChatScopedStateScope(scope)) {
      await _secureWrite(scopedKey, legacy);
      return legacy;
    }
    return null;
  }

  Future<void> _saveScopedSecureString({
    required String legacyKey,
    required String scopedKeyPrefix,
    required String value,
    String? baseUrlOverride,
  }) async {
    final normalized = value.trim();
    final sp = await SharedPreferences.getInstance();
    final scopedKey = _scopedChatStateKey(
      scopedKeyPrefix,
      _currentChatScopedStateScope(
        sp,
        baseUrlOverride: baseUrlOverride,
      ),
    );
    if (normalized.isEmpty) {
      await _secureDelete(scopedKey);
      await _secureDelete(legacyKey);
      return;
    }
    await _secureWrite(scopedKey, normalized);
    await _secureDelete(legacyKey);
  }

  Future<String?> _loadScopedSecureEntityString({
    required String legacyKeyPrefix,
    required String scopedKeyPrefix,
    required String entityId,
    String? baseUrlOverride,
  }) async {
    final normalizedEntityId = entityId.trim();
    if (normalizedEntityId.isEmpty) return null;
    final legacyKey = '$legacyKeyPrefix$normalizedEntityId';
    final sp = await SharedPreferences.getInstance();
    final scope = _currentChatScopedStateScope(
      sp,
      baseUrlOverride: baseUrlOverride,
    );
    final scopedKey = _scopedChatEntityStateKey(
      scopedKeyPrefix,
      scope,
      normalizedEntityId,
    );

    final scoped = (await _secureRead(scopedKey) ?? '').trim();
    if (scoped.isNotEmpty) {
      await _secureDelete(legacyKey);
      return scoped;
    }

    final legacy = (await _secureRead(legacyKey) ?? '').trim();
    if (legacy.isEmpty) return null;

    await _secureDelete(legacyKey);
    if (_isUnknownChatScopedStateScope(scope)) {
      await _secureWrite(scopedKey, legacy);
      return legacy;
    }
    return null;
  }

  Future<void> _saveScopedSecureEntityString({
    required String legacyKeyPrefix,
    required String scopedKeyPrefix,
    required String entityId,
    required String value,
    String? baseUrlOverride,
  }) async {
    final normalizedEntityId = entityId.trim();
    final normalizedValue = value.trim();
    if (normalizedEntityId.isEmpty) return;
    final legacyKey = '$legacyKeyPrefix$normalizedEntityId';
    final sp = await SharedPreferences.getInstance();
    final scopedKey = _scopedChatEntityStateKey(
      scopedKeyPrefix,
      _currentChatScopedStateScope(
        sp,
        baseUrlOverride: baseUrlOverride,
      ),
      normalizedEntityId,
    );
    if (normalizedValue.isEmpty) {
      await _secureDelete(scopedKey);
      await _secureDelete(legacyKey);
      return;
    }
    await _secureWrite(scopedKey, normalizedValue);
    await _secureDelete(legacyKey);
  }

  Future<void> _deleteScopedSecureEntityString({
    required String legacyKeyPrefix,
    required String scopedKeyPrefix,
    required String entityId,
    String? baseUrlOverride,
  }) async {
    final normalizedEntityId = entityId.trim();
    if (normalizedEntityId.isEmpty) return;
    final legacyKey = '$legacyKeyPrefix$normalizedEntityId';
    final sp = await SharedPreferences.getInstance();
    await _secureDelete(
      _scopedChatEntityStateKey(
        scopedKeyPrefix,
        _currentChatScopedStateScope(
          sp,
          baseUrlOverride: baseUrlOverride,
        ),
        normalizedEntityId,
      ),
    );
    await _secureDelete(legacyKey);
  }

  Future<Map<String, Set<String>>> _loadPinnedMessagesForKey(String key) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(key);
    if (raw == null || raw.isEmpty) return <String, Set<String>>{};
    try {
      final decodedRaw = (await _decryptSensitivePrefsString(raw)) ?? raw;
      final decoded = jsonDecode(decodedRaw);
      if (decoded is! Map) return <String, Set<String>>{};
      final out = <String, Set<String>>{};
      decoded.forEach((k, v) {
        final peerId = (k ?? '').toString().trim();
        if (peerId.isEmpty || v is! List) return;
        final ids = <String>{
          for (final entry in v)
            if ((entry ?? '').toString().trim().isNotEmpty)
              (entry ?? '').toString().trim(),
        };
        if (ids.isNotEmpty) {
          out[peerId] = ids;
        }
      });
      if (decodedRaw == raw) {
        await _savePinnedMessagesForKey(key, out);
      }
      return out;
    } catch (_) {
      return <String, Set<String>>{};
    }
  }

  Future<Map<String, Set<String>>> _loadScopedPinnedMessages({
    required String legacyKey,
    required String scopedKeyPrefix,
    String? baseUrlOverride,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final scope = _currentChatScopedStateScope(
      sp,
      baseUrlOverride: baseUrlOverride,
    );
    final scopedKey = _scopedChatStateKey(scopedKeyPrefix, scope);

    final scoped = await _loadPinnedMessagesForKey(scopedKey);
    if (scoped.isNotEmpty) {
      await _removeSensitivePrefKey(legacyKey);
      return scoped;
    }

    final legacy = await _loadPinnedMessagesForKey(legacyKey);
    if (legacy.isEmpty) return <String, Set<String>>{};

    await _removeSensitivePrefKey(legacyKey);
    if (_isUnknownChatScopedStateScope(scope)) {
      await _savePinnedMessagesForKey(scopedKey, legacy);
      return legacy;
    }
    return <String, Set<String>>{};
  }

  Future<void> _savePinnedMessagesForKey(
    String key,
    Map<String, Set<String>> values,
  ) async {
    final sp = await SharedPreferences.getInstance();
    final cleaned = <String, List<String>>{};
    values.forEach((peerId, ids) {
      final normalizedPeerId = peerId.trim();
      if (normalizedPeerId.isEmpty) return;
      final normalizedIds = ids
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
      if (normalizedIds.isEmpty) return;
      cleaned[normalizedPeerId] = normalizedIds;
    });
    if (cleaned.isEmpty) {
      await sp.remove(key);
      return;
    }
    final enc = await _encryptSensitivePrefsString(jsonEncode(cleaned));
    if (enc == null || enc.isEmpty) {
      return;
    }
    await sp.remove(key);
    await sp.setString(key, enc);
  }

  Future<void> _saveScopedPinnedMessages({
    required String legacyKey,
    required String scopedKeyPrefix,
    required Map<String, Set<String>> values,
    String? baseUrlOverride,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final scopedKey = _scopedChatStateKey(
      scopedKeyPrefix,
      _currentChatScopedStateScope(
        sp,
        baseUrlOverride: baseUrlOverride,
      ),
    );
    await _savePinnedMessagesForKey(scopedKey, values);
    await _removeSensitivePrefKey(legacyKey);
  }

  Future<bool> _loadScopedSensitiveEntityBoolFlag({
    required String legacyKeyPrefix,
    required String scopedKeyPrefix,
    required String entityId,
    String? baseUrlOverride,
  }) async {
    final normalizedEntityId = entityId.trim();
    if (normalizedEntityId.isEmpty) return false;
    final legacyKey = '$legacyKeyPrefix$normalizedEntityId';
    final sp = await SharedPreferences.getInstance();
    final scope = _currentChatScopedStateScope(
      sp,
      baseUrlOverride: baseUrlOverride,
    );
    final scopedKey = _scopedChatEntityStateKey(
      scopedKeyPrefix,
      scope,
      normalizedEntityId,
    );

    final scoped = await _readSensitiveBoolFlagRaw(scopedKey);
    if (scoped != null) {
      await _removeSensitivePrefKey(legacyKey);
      return scoped;
    }

    bool? legacy;
    try {
      legacy = sp.getBool(legacyKey);
    } catch (_) {
      legacy = null;
    }
    legacy ??= await _readSensitiveBoolFlagRaw(legacyKey);
    if (legacy == null) return false;

    await _removeSensitivePrefKey(legacyKey);
    if (_isUnknownChatScopedStateScope(scope)) {
      await _saveSensitiveBoolFlag(scopedKey, legacy);
      return legacy;
    }
    return false;
  }

  Future<void> _saveScopedSensitiveEntityBoolFlag({
    required String legacyKeyPrefix,
    required String scopedKeyPrefix,
    required String entityId,
    required bool value,
    String? baseUrlOverride,
  }) async {
    final normalizedEntityId = entityId.trim();
    if (normalizedEntityId.isEmpty) return;
    final legacyKey = '$legacyKeyPrefix$normalizedEntityId';
    final sp = await SharedPreferences.getInstance();
    final scopedKey = _scopedChatEntityStateKey(
      scopedKeyPrefix,
      _currentChatScopedStateScope(
        sp,
        baseUrlOverride: baseUrlOverride,
      ),
      normalizedEntityId,
    );
    await _saveSensitiveBoolFlag(scopedKey, value);
    await _removeSensitivePrefKey(legacyKey);
  }

  Future<List<String>> _loadScopedSensitiveEntityStringList({
    required String legacyKeyPrefix,
    required String scopedKeyPrefix,
    required String entityId,
    String? baseUrlOverride,
  }) async {
    final normalizedEntityId = entityId.trim();
    if (normalizedEntityId.isEmpty) return <String>[];
    final legacyKey = '$legacyKeyPrefix$normalizedEntityId';
    final sp = await SharedPreferences.getInstance();
    final scope = _currentChatScopedStateScope(
      sp,
      baseUrlOverride: baseUrlOverride,
    );
    final scopedKey = _scopedChatEntityStateKey(
      scopedKeyPrefix,
      scope,
      normalizedEntityId,
    );

    final scoped = await _loadSensitiveStringList(scopedKey);
    if (scoped.isNotEmpty) {
      await _removeSensitivePrefKey(legacyKey);
      return scoped;
    }

    final legacy = await _loadSensitiveStringList(legacyKey);
    if (legacy.isEmpty) return <String>[];

    await _removeSensitivePrefKey(legacyKey);
    if (_isUnknownChatScopedStateScope(scope)) {
      await _saveSensitiveStringList(scopedKey, legacy);
      return legacy;
    }
    return <String>[];
  }

  Future<Set<String>> _loadScopedSensitiveEntityStringSet({
    required String legacyKeyPrefix,
    required String scopedKeyPrefix,
    required String entityId,
    String? baseUrlOverride,
  }) async {
    return _loadScopedSensitiveEntityStringList(
      legacyKeyPrefix: legacyKeyPrefix,
      scopedKeyPrefix: scopedKeyPrefix,
      entityId: entityId,
      baseUrlOverride: baseUrlOverride,
    ).then((values) => values.toSet());
  }

  Future<void> _saveScopedSensitiveEntityStringList({
    required String legacyKeyPrefix,
    required String scopedKeyPrefix,
    required String entityId,
    required Iterable<String> values,
    String? baseUrlOverride,
  }) async {
    final normalizedEntityId = entityId.trim();
    if (normalizedEntityId.isEmpty) return;
    final legacyKey = '$legacyKeyPrefix$normalizedEntityId';
    final sp = await SharedPreferences.getInstance();
    final scopedKey = _scopedChatEntityStateKey(
      scopedKeyPrefix,
      _currentChatScopedStateScope(
        sp,
        baseUrlOverride: baseUrlOverride,
      ),
      normalizedEntityId,
    );
    await _saveSensitiveStringList(scopedKey, values);
    await _removeSensitivePrefKey(legacyKey);
  }

  Future<String?> _loadScopedSensitiveEntityPlainString({
    required String legacyKeyPrefix,
    required String scopedKeyPrefix,
    required String entityId,
    String? baseUrlOverride,
  }) async {
    final normalizedEntityId = entityId.trim();
    if (normalizedEntityId.isEmpty) return null;
    final legacyKey = '$legacyKeyPrefix$normalizedEntityId';
    final sp = await SharedPreferences.getInstance();
    final scope = _currentChatScopedStateScope(
      sp,
      baseUrlOverride: baseUrlOverride,
    );
    final scopedKey = _scopedChatEntityStateKey(
      scopedKeyPrefix,
      scope,
      normalizedEntityId,
    );

    final scoped = await _loadSensitivePlainString(scopedKey);
    if (scoped != null && scoped.isNotEmpty) {
      await _removeSensitivePrefKey(legacyKey);
      return scoped;
    }

    final legacy = await _loadSensitivePlainString(legacyKey);
    if (legacy == null || legacy.isEmpty) return null;

    await _removeSensitivePrefKey(legacyKey);
    if (_isUnknownChatScopedStateScope(scope)) {
      await _saveSensitivePlainString(scopedKey, legacy);
      return legacy;
    }
    return null;
  }

  Future<void> _saveScopedSensitiveEntityPlainString({
    required String legacyKeyPrefix,
    required String scopedKeyPrefix,
    required String entityId,
    required String value,
    String? baseUrlOverride,
  }) async {
    final normalizedEntityId = entityId.trim();
    if (normalizedEntityId.isEmpty) return;
    final legacyKey = '$legacyKeyPrefix$normalizedEntityId';
    final sp = await SharedPreferences.getInstance();
    final scopedKey = _scopedChatEntityStateKey(
      scopedKeyPrefix,
      _currentChatScopedStateScope(
        sp,
        baseUrlOverride: baseUrlOverride,
      ),
      normalizedEntityId,
    );
    await _saveSensitivePlainString(scopedKey, value);
    await _removeSensitivePrefKey(legacyKey);
  }

  Future<Map<String, String>> _loadGroupSeenEntityMap({
    String? baseUrlOverride,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final scope = _currentChatScopedStateScope(
      sp,
      baseUrlOverride: baseUrlOverride,
    );
    final prefix =
        '${_scopedChatStateKey(_groupSeenEntityScopedKeyPrefix, scope)}.';
    final out = <String, String>{};
    final keys = sp.getKeys().where((key) => key.startsWith(prefix)).toList()
      ..sort();
    for (final key in keys) {
      final groupId = key.substring(prefix.length).trim();
      if (groupId.isEmpty) continue;
      final seenIso = (await _loadSensitivePlainString(key) ?? '').trim();
      if (seenIso.isEmpty) {
        await _removeSensitivePrefKey(key);
        continue;
      }
      out[groupId] = seenIso;
    }
    return out;
  }

  Future<Map<String, String>> _loadLegacyGroupSeenMap({
    String? baseUrlOverride,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final scope = _currentChatScopedStateScope(
      sp,
      baseUrlOverride: baseUrlOverride,
    );
    final scopedKey = _scopedChatStateKey(_groupSeenScopedKeyPrefix, scope);
    final scoped = await _loadSensitiveStringMap(scopedKey);
    if (scoped.isNotEmpty) {
      await _removeSensitivePrefKey(_groupSeenKey);
      return scoped;
    }
    final legacy = await _loadSensitiveStringMap(_groupSeenKey);
    if (legacy.isEmpty) {
      return <String, String>{};
    }
    await _removeSensitivePrefKey(_groupSeenKey);
    if (_isUnknownChatScopedStateScope(scope)) {
      return legacy;
    }
    return <String, String>{};
  }

  Future<void> _saveGroupSeenEntityMap(
    Map<String, String> seen, {
    String? baseUrlOverride,
  }) async {
    final normalized = <String, String>{};
    seen.forEach((groupId, seenIso) {
      final normalizedGroupId = groupId.trim();
      final normalizedSeenIso = seenIso.trim();
      if (normalizedGroupId.isEmpty || normalizedSeenIso.isEmpty) return;
      normalized[normalizedGroupId] = normalizedSeenIso;
    });
    final sp = await SharedPreferences.getInstance();
    final scope = _currentChatScopedStateScope(
      sp,
      baseUrlOverride: baseUrlOverride,
    );
    final prefix =
        '${_scopedChatStateKey(_groupSeenEntityScopedKeyPrefix, scope)}.';
    for (final key in sp.getKeys().where((key) => key.startsWith(prefix))) {
      final groupId = key.substring(prefix.length).trim();
      if (!normalized.containsKey(groupId)) {
        await _removeSensitivePrefKey(key);
      }
    }
    for (final entry in normalized.entries) {
      await _saveScopedSensitiveEntityPlainString(
        legacyKeyPrefix: _groupSeenPrefix,
        scopedKeyPrefix: _groupSeenEntityScopedKeyPrefix,
        entityId: entry.key,
        value: entry.value,
        baseUrlOverride: baseUrlOverride,
      );
    }
  }

  Future<void> _clearLegacyGroupSeenStorage({
    String? baseUrlOverride,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final scope = _currentChatScopedStateScope(
      sp,
      baseUrlOverride: baseUrlOverride,
    );
    await _removeSensitivePrefKey(
      _scopedChatStateKey(_groupSeenScopedKeyPrefix, scope),
    );
    await _removeSensitivePrefKey(_groupSeenKey);
  }

  Future<Map<String, int>> _loadUnreadEntityMap({
    String? baseUrlOverride,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final scope = _currentChatScopedStateScope(
      sp,
      baseUrlOverride: baseUrlOverride,
    );
    final prefix =
        '${_scopedChatStateKey(_unreadEntityScopedKeyPrefix, scope)}.';
    final out = <String, int>{};
    final keys = sp.getKeys().where((key) => key.startsWith(prefix)).toList()
      ..sort();
    for (final key in keys) {
      final unreadKey = key.substring(prefix.length).trim();
      if (unreadKey.isEmpty) continue;
      final unreadRaw = (await _loadSensitivePlainString(key) ?? '').trim();
      final unreadCount = int.tryParse(unreadRaw) ?? 0;
      if (unreadCount <= 0) {
        await _removeSensitivePrefKey(key);
        continue;
      }
      out[unreadKey] = unreadCount;
    }
    return out;
  }

  Future<Map<String, int>> _loadLegacyUnreadMap({
    String? baseUrlOverride,
  }) async {
    final raw = await _loadScopedSensitiveStringMap(
      legacyKey: _unreadKey,
      scopedKeyPrefix: _unreadScopedKeyPrefix,
      baseUrlOverride: baseUrlOverride,
    );
    final out = <String, int>{};
    raw.forEach((k, v) {
      final next = int.tryParse(v.trim()) ?? 0;
      if (next > 0) {
        out[k] = next;
      }
    });
    return out;
  }

  Future<void> _saveUnreadEntityMap(
    Map<String, int> unread, {
    String? baseUrlOverride,
  }) async {
    final normalized = <String, String>{};
    unread.forEach((unreadKey, count) {
      final normalizedUnreadKey = unreadKey.trim();
      if (normalizedUnreadKey.isEmpty || count <= 0) return;
      normalized[normalizedUnreadKey] = count.toString();
    });
    final sp = await SharedPreferences.getInstance();
    final scope = _currentChatScopedStateScope(
      sp,
      baseUrlOverride: baseUrlOverride,
    );
    final prefix =
        '${_scopedChatStateKey(_unreadEntityScopedKeyPrefix, scope)}.';
    for (final key in sp.getKeys().where((key) => key.startsWith(prefix))) {
      final unreadKey = key.substring(prefix.length).trim();
      if (!normalized.containsKey(unreadKey)) {
        await _removeSensitivePrefKey(key);
      }
    }
    for (final entry in normalized.entries) {
      await _saveScopedSensitiveEntityPlainString(
        legacyKeyPrefix: _unreadPrefix,
        scopedKeyPrefix: _unreadEntityScopedKeyPrefix,
        entityId: entry.key,
        value: entry.value,
        baseUrlOverride: baseUrlOverride,
      );
    }
  }

  Future<void> _clearLegacyUnreadStorage({
    String? baseUrlOverride,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final scope = _currentChatScopedStateScope(
      sp,
      baseUrlOverride: baseUrlOverride,
    );
    await _removeSensitivePrefKey(
      _scopedChatStateKey(_unreadScopedKeyPrefix, scope),
    );
    await _removeSensitivePrefKey(_unreadKey);
  }

  Future<Map<String, String>> _loadSensitiveStringMap(String key) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(key);
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      final decodedRaw = (await _decryptSensitivePrefsString(raw)) ?? raw;
      final decoded = jsonDecode(decodedRaw);
      if (decoded is! Map) return <String, String>{};
      final out = <String, String>{};
      decoded.forEach((k, v) {
        final normalizedKey = (k ?? '').toString().trim();
        final normalizedValue = (v ?? '').toString().trim();
        if (normalizedKey.isEmpty || normalizedValue.isEmpty) return;
        out[normalizedKey] = normalizedValue;
      });
      if (decodedRaw == raw) {
        await _saveSensitiveStringMap(key, out);
      }
      return out;
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> _saveSensitiveStringList(
      String key, Iterable<String> values) async {
    final sp = await SharedPreferences.getInstance();
    final cleaned = _normalizeStringList(values);
    if (cleaned.isEmpty) {
      await sp.remove(key);
      return;
    }
    final enc = await _encryptSensitivePrefsString(jsonEncode(cleaned));
    if (enc == null || enc.isEmpty) {
      return;
    }
    await sp.remove(key);
    await sp.setString(key, enc);
  }

  Future<void> _saveSensitivePlainString(String key, String value) async {
    final sp = await SharedPreferences.getInstance();
    final normalized = value.trim();
    if (normalized.isEmpty) {
      await sp.remove(key);
      return;
    }
    final enc = await _encryptSensitivePrefsString(normalized);
    if (enc == null || enc.isEmpty) {
      return;
    }
    await sp.remove(key);
    await sp.setString(key, enc);
  }

  Future<void> _saveSensitiveBoolFlag(String key, bool value) async {
    if (!value) {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(key);
      return;
    }
    await _saveSensitivePlainString(key, '1');
  }

  Future<void> _saveSensitiveStringMap(
      String key, Map<String, String> values) async {
    final sp = await SharedPreferences.getInstance();
    final cleaned = <String, String>{};
    values.forEach((mapKey, mapValue) {
      final normalizedKey = mapKey.trim();
      final normalizedValue = mapValue.trim();
      if (normalizedKey.isEmpty || normalizedValue.isEmpty) return;
      cleaned[normalizedKey] = normalizedValue;
    });
    if (cleaned.isEmpty) {
      await sp.remove(key);
      return;
    }
    final enc = await _encryptSensitivePrefsString(jsonEncode(cleaned));
    if (enc == null || enc.isEmpty) {
      return;
    }
    await sp.remove(key);
    await sp.setString(key, enc);
  }

  String _currentChatScopedStateScope(
    SharedPreferences prefs, {
    String? baseUrlOverride,
  }) {
    final rawBase =
        (baseUrlOverride ?? prefs.getString(_chatScopedBaseUrlPrefKey) ?? '')
            .trim();
    return normalizeSecureApiBaseUrl(rawBase) ?? _chatScopedUnknownScope;
  }

  bool _isUnknownChatScopedStateScope(String scope) {
    return scope == _chatScopedUnknownScope;
  }

  String _scopedChatStateKey(String prefix, String scope) {
    final suffix = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
    return '$prefix$suffix';
  }

  String _scopedChatEntityStateKey(
      String prefix, String scope, String entityId) {
    final suffix = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
    return '$prefix$suffix.$entityId';
  }

  Future<void> _removeSensitivePrefKey(String key) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(key);
    } catch (_) {}
  }

  Future<bool> _loadScopedDeviceBoolPreference({
    required String legacySecureKey,
    required String scopedSecureKeyPrefix,
    required String legacyPrefKey,
    required String scopedPrefKeyPrefix,
    required bool defaultValue,
    String? baseUrlOverride,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final scope = _currentChatScopedStateScope(
      sp,
      baseUrlOverride: baseUrlOverride,
    );
    final scopedSecureKey = _scopedChatStateKey(scopedSecureKeyPrefix, scope);
    final scopedPrefKey = _scopedChatStateKey(scopedPrefKeyPrefix, scope);
    if (_useSecureStore()) {
      final secure = await _readDevicePreferenceBool(scopedSecureKey);
      if (secure != null) {
        await _secureDelete(legacySecureKey);
        await _removeLegacyDevicePreferenceKey(legacyPrefKey);
        await _removeLegacyDevicePreferenceKey(scopedPrefKey);
        return secure;
      }

      bool? sharedScoped;
      try {
        sharedScoped = sp.getBool(scopedPrefKey);
      } catch (_) {
        sharedScoped = null;
      }
      if (sharedScoped != null) {
        final wrote =
            await _writeDevicePreferenceBool(scopedSecureKey, sharedScoped);
        await _removeLegacyDevicePreferenceKey(scopedPrefKey);
        if (!wrote) {
          await _secureDelete(scopedSecureKey);
        }
        return sharedScoped;
      }

      final secureLegacy = await _readDevicePreferenceBool(legacySecureKey);
      if (secureLegacy != null) {
        await _secureDelete(legacySecureKey);
        await _removeLegacyDevicePreferenceKey(legacyPrefKey);
        if (_isUnknownChatScopedStateScope(scope)) {
          final wrote =
              await _writeDevicePreferenceBool(scopedSecureKey, secureLegacy);
          if (!wrote) {
            await _secureDelete(scopedSecureKey);
          }
          return secureLegacy;
        }
        return defaultValue;
      }

      bool? legacy;
      try {
        legacy = sp.getBool(legacyPrefKey);
      } catch (_) {
        legacy = null;
      }
      if (legacy == null) return defaultValue;
      await _removeLegacyDevicePreferenceKey(legacyPrefKey);
      if (_isUnknownChatScopedStateScope(scope)) {
        final wrote = await _writeDevicePreferenceBool(scopedSecureKey, legacy);
        if (!wrote) {
          await _secureDelete(scopedSecureKey);
        }
        return legacy;
      }
      return defaultValue;
    }

    bool? scoped;
    try {
      scoped = sp.getBool(scopedPrefKey);
    } catch (_) {
      scoped = null;
    }
    if (scoped != null) {
      await _secureDelete(legacySecureKey);
      await _removeLegacyDevicePreferenceKey(legacyPrefKey);
      return scoped;
    }

    final secureLegacy = await _readDevicePreferenceBool(legacySecureKey);
    if (secureLegacy != null) {
      await _secureDelete(legacySecureKey);
      await _removeLegacyDevicePreferenceKey(legacyPrefKey);
      if (_isUnknownChatScopedStateScope(scope)) {
        try {
          await sp.setBool(scopedPrefKey, secureLegacy);
        } catch (_) {}
        return secureLegacy;
      }
      return defaultValue;
    }

    bool? legacy;
    try {
      legacy = sp.getBool(legacyPrefKey);
    } catch (_) {
      legacy = null;
    }
    if (legacy == null) return defaultValue;
    await _removeLegacyDevicePreferenceKey(legacyPrefKey);
    if (_isUnknownChatScopedStateScope(scope)) {
      try {
        await sp.setBool(scopedPrefKey, legacy);
      } catch (_) {}
      return legacy;
    }
    return defaultValue;
  }

  Future<void> _saveScopedDeviceBoolPreference({
    required String legacySecureKey,
    required String scopedSecureKeyPrefix,
    required String legacyPrefKey,
    required String scopedPrefKeyPrefix,
    required bool value,
    String? baseUrlOverride,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final scope = _currentChatScopedStateScope(
      sp,
      baseUrlOverride: baseUrlOverride,
    );
    final scopedSecureKey = _scopedChatStateKey(scopedSecureKeyPrefix, scope);
    final scopedPrefKey = _scopedChatStateKey(scopedPrefKeyPrefix, scope);
    if (_useSecureStore()) {
      final wrote = await _writeDevicePreferenceBool(scopedSecureKey, value);
      await _secureDelete(legacySecureKey);
      await _removeLegacyDevicePreferenceKey(legacyPrefKey);
      await _removeLegacyDevicePreferenceKey(scopedPrefKey);
      if (!wrote) {
        await _secureDelete(scopedSecureKey);
      }
      return;
    }

    await _secureDelete(legacySecureKey);
    await _removeLegacyDevicePreferenceKey(legacyPrefKey);
    try {
      await sp.setBool(scopedPrefKey, value);
    } catch (_) {}
  }

  Future<int> _loadScopedDeviceIntPreference({
    required String legacySecureKey,
    required String scopedSecureKeyPrefix,
    required String legacyPrefKey,
    required String scopedPrefKeyPrefix,
    required int defaultValue,
    required int min,
    required int max,
    String? baseUrlOverride,
  }) async {
    final safeDefault = defaultValue.clamp(min, max).toInt();
    final sp = await SharedPreferences.getInstance();
    final scope = _currentChatScopedStateScope(
      sp,
      baseUrlOverride: baseUrlOverride,
    );
    final scopedSecureKey = _scopedChatStateKey(scopedSecureKeyPrefix, scope);
    final scopedPrefKey = _scopedChatStateKey(scopedPrefKeyPrefix, scope);
    if (_useSecureStore()) {
      final secure = await _readDevicePreferenceInt(
        scopedSecureKey,
        min: min,
        max: max,
      );
      if (secure != null) {
        await _secureDelete(legacySecureKey);
        await _removeLegacyDevicePreferenceKey(legacyPrefKey);
        await _removeLegacyDevicePreferenceKey(scopedPrefKey);
        return secure;
      }

      int? sharedScoped;
      try {
        sharedScoped = sp.getInt(scopedPrefKey);
      } catch (_) {
        sharedScoped = null;
      }
      if (sharedScoped != null) {
        final normalized = sharedScoped.clamp(min, max).toInt();
        final wrote =
            await _writeDevicePreferenceInt(scopedSecureKey, normalized);
        await _removeLegacyDevicePreferenceKey(scopedPrefKey);
        if (!wrote) {
          await _secureDelete(scopedSecureKey);
        }
        return normalized;
      }

      final secureLegacy = await _readDevicePreferenceInt(
        legacySecureKey,
        min: min,
        max: max,
      );
      if (secureLegacy != null) {
        await _secureDelete(legacySecureKey);
        await _removeLegacyDevicePreferenceKey(legacyPrefKey);
        if (_isUnknownChatScopedStateScope(scope)) {
          final wrote =
              await _writeDevicePreferenceInt(scopedSecureKey, secureLegacy);
          if (!wrote) {
            await _secureDelete(scopedSecureKey);
          }
          return secureLegacy;
        }
        return safeDefault;
      }

      int? legacy;
      try {
        legacy = sp.getInt(legacyPrefKey);
      } catch (_) {
        legacy = null;
      }
      if (legacy == null) return safeDefault;
      final normalized = legacy.clamp(min, max).toInt();
      await _removeLegacyDevicePreferenceKey(legacyPrefKey);
      if (_isUnknownChatScopedStateScope(scope)) {
        final wrote =
            await _writeDevicePreferenceInt(scopedSecureKey, normalized);
        if (!wrote) {
          await _secureDelete(scopedSecureKey);
        }
        return normalized;
      }
      return safeDefault;
    }

    int? scoped;
    try {
      scoped = sp.getInt(scopedPrefKey);
    } catch (_) {
      scoped = null;
    }
    if (scoped != null) {
      await _secureDelete(legacySecureKey);
      await _removeLegacyDevicePreferenceKey(legacyPrefKey);
      return scoped.clamp(min, max).toInt();
    }

    final secureLegacy = await _readDevicePreferenceInt(
      legacySecureKey,
      min: min,
      max: max,
    );
    if (secureLegacy != null) {
      await _secureDelete(legacySecureKey);
      await _removeLegacyDevicePreferenceKey(legacyPrefKey);
      if (_isUnknownChatScopedStateScope(scope)) {
        try {
          await sp.setInt(scopedPrefKey, secureLegacy);
        } catch (_) {}
        return secureLegacy;
      }
      return safeDefault;
    }

    int? legacy;
    try {
      legacy = sp.getInt(legacyPrefKey);
    } catch (_) {
      legacy = null;
    }
    if (legacy == null) return safeDefault;
    final normalized = legacy.clamp(min, max).toInt();
    await _removeLegacyDevicePreferenceKey(legacyPrefKey);
    if (_isUnknownChatScopedStateScope(scope)) {
      try {
        await sp.setInt(scopedPrefKey, normalized);
      } catch (_) {}
      return normalized;
    }
    return safeDefault;
  }

  Future<void> _saveScopedDeviceIntPreference({
    required String legacySecureKey,
    required String scopedSecureKeyPrefix,
    required String legacyPrefKey,
    required String scopedPrefKeyPrefix,
    required int value,
    required int min,
    required int max,
    String? baseUrlOverride,
  }) async {
    final normalized = value.clamp(min, max).toInt();
    final sp = await SharedPreferences.getInstance();
    final scope = _currentChatScopedStateScope(
      sp,
      baseUrlOverride: baseUrlOverride,
    );
    final scopedSecureKey = _scopedChatStateKey(scopedSecureKeyPrefix, scope);
    final scopedPrefKey = _scopedChatStateKey(scopedPrefKeyPrefix, scope);
    if (_useSecureStore()) {
      final wrote =
          await _writeDevicePreferenceInt(scopedSecureKey, normalized);
      await _secureDelete(legacySecureKey);
      await _removeLegacyDevicePreferenceKey(legacyPrefKey);
      await _removeLegacyDevicePreferenceKey(scopedPrefKey);
      if (!wrote) {
        await _secureDelete(scopedSecureKey);
      }
      return;
    }

    await _secureDelete(legacySecureKey);
    await _removeLegacyDevicePreferenceKey(legacyPrefKey);
    try {
      await sp.setInt(scopedPrefKey, normalized);
    } catch (_) {}
  }

  Future<bool?> _readDevicePreferenceBool(String secureKey) async {
    try {
      final raw =
          (await _sec().read(key: secureKey) ?? '').trim().toLowerCase();
      if (raw.isEmpty) return null;
      if (raw == '1' || raw == 'true') return true;
      if (raw == '0' || raw == 'false') return false;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<int?> _readDevicePreferenceInt(
    String secureKey, {
    required int min,
    required int max,
  }) async {
    try {
      final raw = (await _sec().read(key: secureKey) ?? '').trim();
      if (raw.isEmpty) return null;
      final parsed = int.tryParse(raw);
      if (parsed == null) return null;
      return parsed.clamp(min, max).toInt();
    } catch (_) {
      return null;
    }
  }

  Future<bool> _writeDevicePreferenceBool(String secureKey, bool value) async {
    try {
      final encoded = value ? '1' : '0';
      await _sec().write(key: secureKey, value: encoded);
      final roundTrip = (await _sec().read(key: secureKey) ?? '').trim();
      return roundTrip == encoded;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _writeDevicePreferenceInt(String secureKey, int value) async {
    try {
      final encoded = value.toString();
      await _sec().write(key: secureKey, value: encoded);
      final roundTrip = (await _sec().read(key: secureKey) ?? '').trim();
      return roundTrip == encoded;
    } catch (_) {
      return false;
    }
  }

  Future<void> _removeLegacyDevicePreferenceKey(String legacyKey) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(legacyKey);
    } catch (_) {}
  }

  List<String> _normalizeStringList(Iterable<dynamic> values) {
    final out = <String>[];
    for (final value in values) {
      final normalized = (value ?? '').toString().trim();
      if (normalized.isEmpty || out.contains(normalized)) continue;
      out.add(normalized);
    }
    return out;
  }

  bool? _parseSensitiveBool(String raw) {
    switch (raw.trim().toLowerCase()) {
      case '1':
      case 'true':
      case 'yes':
        return true;
      case '0':
      case 'false':
      case 'no':
        return false;
      default:
        return null;
    }
  }

  Future<String?> _secureRead(String key) async {
    if (_useSecureStore()) {
      try {
        final value = await _sec().read(key: key);
        final normalized = (value ?? '').trim();
        if (normalized.isNotEmpty) {
          if (_allowLegacySecretFallback()) {
            try {
              final sp = await SharedPreferences.getInstance();
              await sp.remove(_legacySecretFallbackKey(key));
            } catch (_) {}
          }
          return value;
        }
      } catch (_) {}
    }
    if (_allowLegacySecretFallback()) {
      try {
        final sp = await SharedPreferences.getInstance();
        final legacy =
            (sp.getString(_legacySecretFallbackKey(key)) ?? '').trim();
        if (legacy.isEmpty) return null;
        if (_useSecureStore()) {
          try {
            await _sec().write(key: key, value: legacy);
            final roundTrip = (await _sec().read(key: key) ?? '').trim();
            if (roundTrip == legacy) {
              await sp.remove(_legacySecretFallbackKey(key));
              return legacy;
            }
          } catch (_) {}
        }
        return legacy;
      } catch (_) {}
    }
    return null;
  }

  Future<void> _secureWrite(String key, String value) async {
    if (_useSecureStore()) {
      try {
        await _sec().write(key: key, value: value);
        final roundTrip = (await _sec().read(key: key) ?? '').trim();
        if (roundTrip == value.trim()) {
          if (_allowLegacySecretFallback()) {
            try {
              final sp = await SharedPreferences.getInstance();
              await sp.remove(_legacySecretFallbackKey(key));
            } catch (_) {}
          }
          return;
        }
      } catch (_) {}
    }
    // Desktop debug fallback: keep local QA usable when duplicated/sideloaded
    // app bundles cannot round-trip FlutterSecureStorage state.
    if (_allowLegacySecretFallback()) {
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.setString(_legacySecretFallbackKey(key), value);
      } catch (_) {}
    }
  }

  Future<void> _secureDelete(String key) async {
    if (_useSecureStore()) {
      try {
        await _sec().delete(key: key);
      } catch (_) {}
    }
    if (_allowLegacySecretFallback()) {
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.remove(_legacySecretFallbackKey(key));
      } catch (_) {}
    }
  }

  FlutterSecureStorage _sec() => const FlutterSecureStorage(
        aOptions: AndroidOptions(
          resetOnError: true,
          // prefer hardware-backed when available
          sharedPreferencesName: 'chat_secure_store',
        ),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.unlocked_this_device,
        ),
        mOptions: MacOsOptions(
            accessibility: KeychainAccessibility.unlocked_this_device),
      );
}

bool shamellIsChatCallLogPrefKey(String key) {
  final normalized = key.trim();
  if (normalized.isEmpty) return false;
  return normalized == 'chat.calllog' ||
      normalized.startsWith('chat.calllog.v2.');
}

Set<String> shamellCurrentScopedNotifyPreferencePrefKeys({
  required SharedPreferences sp,
  String? baseUrlOverride,
}) {
  final store = ChatLocalStore();
  final scope = store._currentChatScopedStateScope(
    sp,
    baseUrlOverride: baseUrlOverride,
  );
  return <String>{
    store._scopedChatStateKey(
        ChatLocalStore._notifyPreviewScopedKeyPrefix, scope),
    store._scopedChatStateKey(
        ChatLocalStore._notifyEnabledScopedKeyPrefix, scope),
    store._scopedChatStateKey(
        ChatLocalStore._notifySoundScopedKeyPrefix, scope),
    store._scopedChatStateKey(
        ChatLocalStore._notifyVibrateScopedKeyPrefix, scope),
    store._scopedChatStateKey(ChatLocalStore._notifyDndScopedKeyPrefix, scope),
    store._scopedChatStateKey(
        ChatLocalStore._notifyDndStartScopedKeyPrefix, scope),
    store._scopedChatStateKey(
        ChatLocalStore._notifyDndEndScopedKeyPrefix, scope),
  };
}

String shamellCurrentScopedChatThemesPrefKey({
  required SharedPreferences sp,
  String? baseUrlOverride,
}) {
  final store = ChatLocalStore();
  final scope = store._currentChatScopedStateScope(
    sp,
    baseUrlOverride: baseUrlOverride,
  );
  return store._scopedChatStateKey(
    ChatLocalStore._chatWallpaperThemeScopedKeyPrefix,
    scope,
  );
}

String shamellCurrentScopedHideServiceNotificationsThreadPrefKey({
  required SharedPreferences sp,
  String? baseUrlOverride,
}) {
  final store = ChatLocalStore();
  final scope = store._currentChatScopedStateScope(
    sp,
    baseUrlOverride: baseUrlOverride,
  );
  return store._scopedChatStateKey(
    ChatLocalStore._hideServiceNotificationsThreadScopedKeyPrefix,
    scope,
  );
}

Set<String> shamellCurrentScopedChatWorkspacePrefKeys({
  required SharedPreferences sp,
  String? baseUrlOverride,
}) {
  final store = ChatLocalStore();
  final scope = store._currentChatScopedStateScope(
    sp,
    baseUrlOverride: baseUrlOverride,
  );
  return <String>{
    store._scopedChatStateKey(
      ChatLocalStore._pinnedMessagesScopedKeyPrefix,
      scope,
    ),
    store._scopedChatStateKey(
      ChatLocalStore._recalledMessagesScopedKeyPrefix,
      scope,
    ),
    store._scopedChatStateKey(
        ChatLocalStore._pinnedChatsScopedKeyPrefix, scope),
    store._scopedChatStateKey(
      ChatLocalStore._archivedGroupsScopedKeyPrefix,
      scope,
    ),
  };
}

Set<String> _currentScopedNotifyPreferenceSecureKeys({
  required SharedPreferences sp,
  String? baseUrlOverride,
}) {
  final store = ChatLocalStore();
  final scope = store._currentChatScopedStateScope(
    sp,
    baseUrlOverride: baseUrlOverride,
  );
  return <String>{
    store._scopedChatStateKey(
      ChatLocalStore._notifyPreviewScopedSecureKeyPrefix,
      scope,
    ),
    store._scopedChatStateKey(
      ChatLocalStore._notifyEnabledScopedSecureKeyPrefix,
      scope,
    ),
    store._scopedChatStateKey(
      ChatLocalStore._notifySoundScopedSecureKeyPrefix,
      scope,
    ),
    store._scopedChatStateKey(
      ChatLocalStore._notifyVibrateScopedSecureKeyPrefix,
      scope,
    ),
    store._scopedChatStateKey(
      ChatLocalStore._notifyDndScopedSecureKeyPrefix,
      scope,
    ),
    store._scopedChatStateKey(
      ChatLocalStore._notifyDndStartScopedSecureKeyPrefix,
      scope,
    ),
    store._scopedChatStateKey(
      ChatLocalStore._notifyDndEndScopedSecureKeyPrefix,
      scope,
    ),
  };
}

class ShamellLocalChatHistoryStorageSnapshot {
  const ShamellLocalChatHistoryStorageSnapshot({
    required this.chatBytes,
    required this.groupBytes,
    required this.pinnedBytes,
    required this.chatThreads,
    required this.groupThreads,
  });

  final int chatBytes;
  final int groupBytes;
  final int pinnedBytes;
  final int chatThreads;
  final int groupThreads;
}

int _shamellStorageBytesForString(String? value) {
  if (value == null || value.isEmpty) return 0;
  return utf8.encode(value).length;
}

bool _matchesLegacyChatPrefPrefix({
  required String key,
  required String legacyPrefix,
  required String scopedPrefix,
}) {
  return key.startsWith(legacyPrefix) && !key.startsWith(scopedPrefix);
}

Future<ShamellLocalChatHistoryStorageSnapshot>
    shamellLoadLocalChatHistoryStorageSnapshot({
  required String baseUrl,
  SharedPreferences? sp,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final store = ChatLocalStore();
  final scope = store._currentChatScopedStateScope(
    prefs,
    baseUrlOverride: baseUrl,
  );
  final directMessagesPrefix =
      '${store._scopedChatStateKey(ChatLocalStore._messagesScopedKeyPrefix, scope)}.';
  final groupMessagesPrefix =
      '${store._scopedChatStateKey(ChatLocalStore._groupMessagesScopedKeyPrefix, scope)}.';
  final pinnedMessagesKey = store._scopedChatStateKey(
    ChatLocalStore._pinnedMessagesScopedKeyPrefix,
    scope,
  );
  final callLogKey =
      store._scopedChatStateKey(ChatCallStore._scopedKeyPrefix, scope);

  var chatBytes = 0;
  var groupBytes = 0;
  var pinnedBytes = 0;
  var chatThreads = 0;
  var groupThreads = 0;

  for (final key in prefs.getKeys()) {
    if (key.startsWith(directMessagesPrefix)) {
      chatThreads++;
      chatBytes += _shamellStorageBytesForString(prefs.getString(key));
      continue;
    }
    if (key.startsWith(groupMessagesPrefix)) {
      groupThreads++;
      groupBytes += _shamellStorageBytesForString(prefs.getString(key));
      continue;
    }
    if (key == callLogKey) {
      chatBytes += _shamellStorageBytesForString(prefs.getString(key));
      continue;
    }
    if (key == pinnedMessagesKey) {
      pinnedBytes += _shamellStorageBytesForString(prefs.getString(key));
    }
  }

  return ShamellLocalChatHistoryStorageSnapshot(
    chatBytes: chatBytes,
    groupBytes: groupBytes,
    pinnedBytes: pinnedBytes,
    chatThreads: chatThreads,
    groupThreads: groupThreads,
  );
}

Set<String> shamellChatHistoryPrefKeysToClear(
  Iterable<String> keys, {
  String? baseUrlOverride,
}) {
  final normalizedOverride = normalizeSecureApiBaseUrl(
    (baseUrlOverride ?? '').trim(),
  );
  if (normalizedOverride == null || normalizedOverride.isEmpty) {
    return <String>{
      ...keys.where(
        (key) =>
            key.startsWith('chat.msgs.') ||
            key.startsWith('chat.msgs.v2.') ||
            key.startsWith('chat.grp.msgs.') ||
            key.startsWith('chat.grp.msgs.v2.') ||
            key.startsWith('chat.group_message_reactions.') ||
            key.startsWith('chat.active.v2.') ||
            key.startsWith('chat.drafts.v2.') ||
            key.startsWith('chat.pinned_messages.v2.') ||
            key.startsWith('chat.recalled_messages.v2.') ||
            key.startsWith('chat.pinned_chats.v2.') ||
            key.startsWith('chat.archived_groups.v2.') ||
            key.startsWith('chat.voice.played.') ||
            key.startsWith('chat.grp.voice.played.') ||
            key.startsWith('chat.unread.v2.') ||
            key.startsWith('chat.unread.v3.') ||
            key.startsWith('chat.grp.seen.v2.') ||
            key.startsWith('chat.grp.seen.v3.') ||
            key.startsWith('chat.grp.names.v2.') ||
            key.startsWith('official.notif.v2.') ||
            shamellIsChatCallLogPrefKey(key),
      ),
      'chat.unread',
      'chat.active',
      'chat.grp.seen',
      'chat.grp.names',
      'official.notif',
      'chat.pinned_messages',
      'chat.recalled_messages',
      'chat.pinned_chats',
      'chat.archived_groups',
      'chat.drafts.v1',
      'chat.calllog',
    };
  }

  final store = ChatLocalStore();
  final directMessagesPrefix =
      '${store._scopedChatStateKey(ChatLocalStore._messagesScopedKeyPrefix, normalizedOverride)}.';
  final groupMessagesPrefix =
      '${store._scopedChatStateKey(ChatLocalStore._groupMessagesScopedKeyPrefix, normalizedOverride)}.';
  final groupReactionsPrefix =
      '${store._scopedChatStateKey(ChatLocalStore._groupMessageReactionsScopedKeyPrefix, normalizedOverride)}.';
  final voicePlayedPrefix =
      '${store._scopedChatStateKey(ChatLocalStore._voicePlayedScopedKeyPrefix, normalizedOverride)}.';
  final groupVoicePlayedPrefix =
      '${store._scopedChatStateKey(ChatLocalStore._groupVoicePlayedScopedKeyPrefix, normalizedOverride)}.';
  final unreadPrefix =
      '${store._scopedChatStateKey(ChatLocalStore._unreadEntityScopedKeyPrefix, normalizedOverride)}.';
  final groupSeenPrefix =
      '${store._scopedChatStateKey(ChatLocalStore._groupSeenEntityScopedKeyPrefix, normalizedOverride)}.';
  final exactScopedKeys = <String>{
    store._scopedChatStateKey(
        ChatLocalStore._activePeerScopedKeyPrefix, normalizedOverride),
    store._scopedChatStateKey(
        ChatLocalStore._draftsScopedKeyPrefix, normalizedOverride),
    store._scopedChatStateKey(
        ChatLocalStore._pinnedMessagesScopedKeyPrefix, normalizedOverride),
    store._scopedChatStateKey(
        ChatLocalStore._recalledMessagesScopedKeyPrefix, normalizedOverride),
    store._scopedChatStateKey(
        ChatLocalStore._pinnedChatsScopedKeyPrefix, normalizedOverride),
    store._scopedChatStateKey(
        ChatLocalStore._archivedGroupsScopedKeyPrefix, normalizedOverride),
    store._scopedChatStateKey(
        ChatLocalStore._unreadScopedKeyPrefix, normalizedOverride),
    store._scopedChatStateKey(
        ChatLocalStore._groupSeenScopedKeyPrefix, normalizedOverride),
    store._scopedChatStateKey(
        ChatLocalStore._groupNamesScopedKeyPrefix, normalizedOverride),
    store._scopedChatStateKey(
      ChatLocalStore._officialNotifScopedKeyPrefix,
      normalizedOverride,
    ),
    store._scopedChatStateKey(
        ChatCallStore._scopedKeyPrefix, normalizedOverride),
  };

  return <String>{
    ...keys.where(
      (key) =>
          key.startsWith(directMessagesPrefix) ||
          key.startsWith(groupMessagesPrefix) ||
          key.startsWith(groupReactionsPrefix) ||
          key.startsWith(voicePlayedPrefix) ||
          key.startsWith(groupVoicePlayedPrefix) ||
          key.startsWith(unreadPrefix) ||
          key.startsWith(groupSeenPrefix) ||
          exactScopedKeys.contains(key) ||
          _matchesLegacyChatPrefPrefix(
            key: key,
            legacyPrefix: 'chat.msgs.',
            scopedPrefix: ChatLocalStore._messagesScopedKeyPrefix,
          ) ||
          _matchesLegacyChatPrefPrefix(
            key: key,
            legacyPrefix: 'chat.grp.msgs.',
            scopedPrefix: ChatLocalStore._groupMessagesScopedKeyPrefix,
          ) ||
          _matchesLegacyChatPrefPrefix(
            key: key,
            legacyPrefix: ChatLocalStore._groupMessageReactionsPrefix,
            scopedPrefix: ChatLocalStore._groupMessageReactionsScopedKeyPrefix,
          ) ||
          _matchesLegacyChatPrefPrefix(
            key: key,
            legacyPrefix: ChatLocalStore._voicePlayedPrefix,
            scopedPrefix: ChatLocalStore._voicePlayedScopedKeyPrefix,
          ) ||
          _matchesLegacyChatPrefPrefix(
            key: key,
            legacyPrefix: ChatLocalStore._groupVoicePlayedPrefix,
            scopedPrefix: ChatLocalStore._groupVoicePlayedScopedKeyPrefix,
          ) ||
          _matchesLegacyChatPrefPrefix(
            key: key,
            legacyPrefix: ChatLocalStore._unreadPrefix,
            scopedPrefix: ChatLocalStore._unreadEntityScopedKeyPrefix,
          ) ||
          _matchesLegacyChatPrefPrefix(
            key: key,
            legacyPrefix: ChatLocalStore._groupSeenPrefix,
            scopedPrefix: ChatLocalStore._groupSeenEntityScopedKeyPrefix,
          ),
    ),
    'chat.unread',
    'chat.active',
    'chat.grp.seen',
    'chat.grp.names',
    'official.notif',
    'chat.pinned_messages',
    'chat.recalled_messages',
    'chat.pinned_chats',
    'chat.archived_groups',
    'chat.drafts.v1',
    'chat.calllog',
  };
}

Future<void> shamellClearLocalChatHistory({
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final toRemove = shamellChatHistoryPrefKeysToClear(
    prefs.getKeys(),
    baseUrlOverride: baseUrlOverride,
  );
  for (final key in toRemove) {
    await prefs.remove(key);
  }
  await purgeEphemeralVoiceFiles();
  await clearFavoriteItems(baseUrlOverride: baseUrlOverride);
}

class ChatCallStore {
  static const _key = 'chat.calllog';
  static const _scopedKeyPrefix = 'chat.calllog.v2.';

  Future<List<ChatCallLogEntry>> load({String? baseUrlOverride}) async {
    final sp = await SharedPreferences.getInstance();
    final store = ChatLocalStore();
    final scope = store._currentChatScopedStateScope(
      sp,
      baseUrlOverride: baseUrlOverride,
    );
    final scopedKey = store._scopedChatStateKey(_scopedKeyPrefix, scope);

    final scopedRaw = (sp.getString(scopedKey) ?? '').trim();
    if (scopedRaw.isNotEmpty) {
      await sp.remove(_key);
      try {
        final decodedRaw =
            (await store._decryptSensitivePrefsString(scopedRaw)) ?? scopedRaw;
        final arr = (jsonDecode(decodedRaw) as List)
            .whereType<Map>()
            .map((m) => ChatCallLogEntry.fromMap(m.cast<String, Object?>()))
            .toList();
        if (decodedRaw == scopedRaw) {
          await save(arr, baseUrlOverride: baseUrlOverride);
        }
        return arr;
      } catch (_) {
        return [];
      }
    }

    final raw = sp.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decodedRaw = (await store._decryptSensitivePrefsString(raw)) ?? raw;
      final arr = (jsonDecode(decodedRaw) as List)
          .whereType<Map>()
          .map((m) => ChatCallLogEntry.fromMap(m.cast<String, Object?>()))
          .toList();
      await sp.remove(_key);
      if (store._isUnknownChatScopedStateScope(scope)) {
        await save(arr, baseUrlOverride: baseUrlOverride);
        return arr;
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> save(
    List<ChatCallLogEntry> list, {
    String? baseUrlOverride,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final store = ChatLocalStore();
    final scopedKey = store._scopedChatStateKey(
      _scopedKeyPrefix,
      store._currentChatScopedStateScope(
        sp,
        baseUrlOverride: baseUrlOverride,
      ),
    );
    final raw = jsonEncode(list.map((e) => e.toMap()).toList());
    final enc = await store._encryptSensitivePrefsString(raw);
    if (enc == null || enc.isEmpty) {
      return;
    }
    await sp.remove(_key);
    await sp.remove(scopedKey);
    await sp.setString(scopedKey, enc);
  }

  Future<void> append(
    ChatCallLogEntry entry, {
    int maxEntries = 100,
    String? baseUrlOverride,
  }) async {
    final current = await load(baseUrlOverride: baseUrlOverride);
    final updated = <ChatCallLogEntry>[entry, ...current];
    if (updated.length > maxEntries) {
      updated.removeRange(maxEntries, updated.length);
    }
    await save(updated, baseUrlOverride: baseUrlOverride);
  }
}
