import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pinenacl/x25519.dart' as x25519;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'chat_models.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';

enum OfficialNotificationMode {
  full, // show message preview
  summary, // generic text only, no preview
  muted, // no local notification
}

class ChatService {
  ChatService(String baseUrl)
      : _base = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl;

  final String _base;
  WebSocketChannel? _ws;
  WebSocketChannel? _wsGroups;

  Future<ChatContact> registerDevice(ChatIdentity me) async {
    final body = jsonEncode({
      'device_id': me.id,
      'public_key_b64': me.publicKeyB64,
      'name': me.displayName,
    });
    final r = await http.post(
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
    return ChatContact(
      id: (j['device_id'] ?? '') as String,
      publicKeyB64: (j['public_key_b64'] ?? '') as String,
      fingerprint: fingerprintForKey((j['public_key_b64'] ?? '') as String),
      name: j['name'] as String?,
      verified: false,
    );
  }

  Future<ChatContact> resolveDevice(String id) async {
    final r = await http.get(
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

  Future<ChatMessage> sendMessage({
    required ChatIdentity me,
    required ChatContact peer,
    required String plainText,
    int? expireAfterSeconds,
    bool sealedSender = false,
    String? senderHint,
    Uint8List? sessionKey,
    int? keyId,
    int? prevKeyId,
    String? senderDhPubB64,
  }) async {
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
      'sender_pubkey_b64': me.publicKeyB64,
      if (senderDhPubB64 != null) 'sender_dh_pub_b64': senderDhPubB64,
      'nonce_b64': enc.$1,
      'box_b64': enc.$2,
      'sealed_sender': sealedSender,
      if (sealedSender && senderHint != null) 'sender_hint': senderHint,
      if (sealedSender && senderHint != null) 'sender_fingerprint': senderHint,
      if (keyId != null) 'key_id': keyId.toString(),
      if (prevKeyId != null) 'prev_key_id': prevKeyId.toString(),
      if (expireAfterSeconds != null)
        'expire_after_seconds': expireAfterSeconds,
    });
    final r = await http.post(
      _uri('/chat/messages/send'),
      headers: await _headers(json: true, chatDeviceId: me.id),
      body: body,
    );
    if (r.statusCode >= 400) {
      throw Exception('send failed: ${r.statusCode}');
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
    qp.putIfAbsent('sealed_view', () => '1');
    final r = await http.get(
      _uri('/chat/messages/inbox', qp),
      headers: await _headers(chatDeviceId: deviceId),
    );
    if (r.statusCode >= 400) {
      throw Exception('inbox failed: ${r.statusCode}');
    }
    final arr = jsonDecode(r.body) as List;
    return arr
        .map((m) => ChatMessage.fromJson(m as Map<String, Object?>))
        .toList();
  }

  Future<void> markRead(String id, {String? deviceId}) async {
    await http.post(
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
    await http.post(
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
    await http.post(
      _uri('/chat/devices/${Uri.encodeComponent(deviceId)}/prefs'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode(body),
    );
  }

  Future<List<ChatContactPrefs>> fetchPrefs({required String deviceId}) async {
    final r = await http.get(
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
    await http.post(
      _uri('/chat/devices/${Uri.encodeComponent(deviceId)}/group_prefs'),
      headers: await _headers(json: true, chatDeviceId: deviceId),
      body: jsonEncode(body),
    );
  }

  Future<List<ChatGroupPrefs>> fetchGroupPrefs({
    required String deviceId,
  }) async {
    final r = await http.get(
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
      await http.post(
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
        final u = Uri.parse(_base);
        final wsUri = Uri(
          scheme: u.scheme == 'https' ? 'wss' : 'ws',
          host: u.host,
          port: u.hasPort ? u.port : null,
          path: '/ws/chat/inbox',
          queryParameters: {'device_id': deviceId, 'sealed_view': '1'},
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
          fallbackUri: _chatWsUriWithFallback(wsUri, auth.deviceId, auth.token),
        );
        _ws = channel;
        late final StreamSubscription sub;
        sub = channel.stream.listen(
          (payload) {
            try {
              final j = jsonDecode(payload);
              if (j is Map && j['type'] == 'inbox' && j['messages'] is List) {
                final msgs = (j['messages'] as List)
                    .map((m) => ChatMessage.fromJson(m as Map<String, Object?>))
                    .toList();
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
          fallbackUri: _chatWsUriWithFallback(wsUri, auth.deviceId, auth.token),
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
    final r = await http.post(
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
    final r = await http.get(
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
    final r = await http.post(
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
      if (expireAfterSeconds != null)
        'expire_after_seconds': expireAfterSeconds,
    };

    try {
      final keyB64 = await ChatLocalStore().loadGroupKey(groupId);
      if (keyB64 != null && keyB64.isNotEmpty) {
        final keyBytes = base64Decode(keyB64);
        if (keyBytes.length == 32) {
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
        }
      }
    } catch (_) {}

    if (!bodyMap.containsKey('box_b64')) {
      if (text.isNotEmpty) bodyMap['text'] = text;
      if (kind != null && kind.isNotEmpty) bodyMap['kind'] = kind;
      if (attachmentB64 != null && attachmentB64.isNotEmpty) {
        bodyMap['attachment_b64'] = attachmentB64;
      }
      if (attachmentMime != null && attachmentMime.isNotEmpty) {
        bodyMap['attachment_mime'] = attachmentMime;
      }
      if (voiceSecs != null) bodyMap['voice_secs'] = voiceSecs;
    }

    final body = jsonEncode(bodyMap);
    final r = await http.post(
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
    final r = await http.get(
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
    final r = await http.get(
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
    final r = await http.post(
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
    final r = await http.post(
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
    final r = await http.post(
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
    final r = await http.get(
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
    final r = await http.post(
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
  ChatGroupMessage _maybeDecryptGroupMessage(
    ChatGroupMessage m,
    Uint8List key,
  ) {
    if (m.kind != 'sealed' ||
        m.nonceB64 == null ||
        m.boxB64 == null ||
        m.nonceB64!.isEmpty ||
        m.boxB64!.isEmpty) {
      return m;
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
    return m;
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

  bool _allowInsecureWsTokenQueryFallback() {
    if (kReleaseMode) {
      return const bool.fromEnvironment(
        'ALLOW_INSECURE_WS_TOKEN_QUERY_FALLBACK_IN_RELEASE',
        defaultValue: false,
      );
    }
    return const bool.fromEnvironment(
      'ALLOW_INSECURE_WS_TOKEN_QUERY_FALLBACK',
      defaultValue: false,
    );
  }

  Uri _chatWsUriWithFallback(Uri wsUri, String? deviceId, String? token) {
    final qp = <String, String>{...wsUri.queryParameters};
    final did = (deviceId ?? '').trim();
    final tok = (token ?? '').trim();
    if (did.isNotEmpty) {
      qp['chat_device_id'] = did;
    }
    if (tok.isNotEmpty && _allowInsecureWsTokenQueryFallback()) {
      qp['chat_device_token'] = tok;
    }
    return wsUri.replace(queryParameters: qp);
  }

  WebSocketChannel _connectWebSocket(
    Uri wsUri, {
    required Map<String, String> headers,
    Uri? fallbackUri,
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
    return WebSocketChannel.connect(fallbackUri ?? wsUri);
  }

  Future<Map<String, String>> _headers({
    bool json = false,
    String? chatDeviceId,
    String? chatDeviceToken,
  }) async {
    final h = <String, String>{};
    if (json) h['content-type'] = 'application/json';
    final cookie = await getSessionCookie();
    if (cookie != null && cookie.isNotEmpty) {
      h['sa_cookie'] = cookie;
    }
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
  static const _secureFallbackPrefix = 'chat.sec.fallback.';
  static const int _voicePlayedMax = 200;

  Future<ChatIdentity?> loadIdentity() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_idKey);
    if (raw == null) return null;
    try {
      return ChatIdentity.fromMap((jsonDecode(raw) as Map<String, Object?>));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveIdentity(ChatIdentity id) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_idKey, jsonEncode(id.toMap()));
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

  Future<void> deleteDeviceAuthToken(String deviceId) async {
    final did = deviceId.trim();
    if (did.isEmpty) return;
    await _secureDelete('$_deviceTokenPrefix$did');
  }

  Future<ChatContact?> loadPeer() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_peerKey);
    if (raw == null) return null;
    try {
      return ChatContact.fromMap((jsonDecode(raw) as Map<String, Object?>));
    } catch (_) {
      return null;
    }
  }

  Future<void> savePeer(ChatContact c) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_peerKey, jsonEncode(c.toMap()));
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
      final arr = (jsonDecode(raw) as List)
          .map((m) => ChatContact.fromMap(m as Map<String, Object?>))
          .whereType<ChatContact>()
          .toList();
      return arr;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveContacts(List<ChatContact> contacts) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _contactsKey,
      jsonEncode(contacts.map((c) => c.toMap()).toList()),
    );
  }

  Future<Map<String, String>> loadDrafts() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_draftsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final out = <String, String>{};
        decoded.forEach((k, v) {
          final id = (k ?? '').toString().trim();
          final text = (v ?? '').toString();
          if (id.isNotEmpty && text.trim().isNotEmpty) {
            out[id] = text;
          }
        });
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
    await sp.setString(_draftsKey, jsonEncode(cleaned));
  }

  Future<void> saveMessages(String peerId, List<ChatMessage> msgs) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      'chat.msgs.$peerId',
      jsonEncode(msgs.map((m) => m.toMap()).toList()),
    );
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
      final arr = (jsonDecode(raw) as List)
          .map((m) => ChatMessage.fromMap(m as Map<String, Object?>))
          .toList();
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
    await sp.setString(
      'chat.grp.msgs.$groupId',
      jsonEncode(
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
      ),
    );
  }

  Future<List<ChatGroupMessage>> loadGroupMessages(String groupId) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('chat.grp.msgs.$groupId');
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

  bool _allowLegacySecureFallback() {
    if (kReleaseMode) {
      return const bool.fromEnvironment(
        'ALLOW_LEGACY_CHAT_SECURE_FALLBACK_IN_RELEASE',
        defaultValue: false,
      );
    }
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_CHAT_SECURE_FALLBACK',
      defaultValue: true,
    );
  }

  bool _useSecureStore() {
    if (kIsWeb) return true;
    final isDesktop = defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
    if (!isDesktop) return true;
    if (kReleaseMode) {
      return const bool.fromEnvironment(
        'ENABLE_DESKTOP_SECURE_STORAGE',
        defaultValue: true,
      );
    }
    return const bool.fromEnvironment(
      'ENABLE_DESKTOP_SECURE_STORAGE',
      defaultValue: false,
    );
  }

  String _legacySecureKey(String key) => '$_secureFallbackPrefix$key';

  Future<String?> _secureRead(String key) async {
    if (_useSecureStore()) {
      try {
        return await _sec().read(key: key);
      } catch (_) {}
    }
    if (!_allowLegacySecureFallback()) return null;
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.getString(_legacySecureKey(key));
    } catch (_) {
      return null;
    }
  }

  Future<void> _secureWrite(String key, String value) async {
    if (_useSecureStore()) {
      try {
        await _sec().write(key: key, value: value);
        if (_allowLegacySecureFallback()) {
          try {
            final sp = await SharedPreferences.getInstance();
            await sp.remove(_legacySecureKey(key));
          } catch (_) {}
        }
        return;
      } catch (_) {}
    }
    if (!_allowLegacySecureFallback()) return;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_legacySecureKey(key), value);
    } catch (_) {}
  }

  Future<void> _secureDelete(String key) async {
    if (_useSecureStore()) {
      try {
        await _sec().delete(key: key);
      } catch (_) {}
    }
    if (!_allowLegacySecureFallback()) return;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_legacySecureKey(key));
    } catch (_) {}
  }

  FlutterSecureStorage _sec() => const FlutterSecureStorage(
        aOptions: AndroidOptions(
          encryptedSharedPreferences: true,
          resetOnError: true,
          // prefer hardware-backed when available
          sharedPreferencesName: 'chat_secure_store',
        ),
        iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
        mOptions:
            MacOsOptions(accessibility: KeychainAccessibility.first_unlock),
      );
}

class ChatCallStore {
  static const _key = 'chat.calllog';

  Future<List<ChatCallLogEntry>> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final arr = (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((m) => ChatCallLogEntry.fromMap(m.cast<String, Object?>()))
          .toList();
      return arr;
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<ChatCallLogEntry> list) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, jsonEncode(list.map((e) => e.toMap()).toList()));
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
