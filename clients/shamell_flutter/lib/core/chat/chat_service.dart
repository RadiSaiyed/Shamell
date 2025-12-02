import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:pinenacl/x25519.dart' as x25519;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'chat_models.dart';

class ChatService {
  ChatService(String baseUrl)
      : _base =
            baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  final String _base;
  WebSocketChannel? _ws;

  Future<ChatContact> registerDevice(ChatIdentity me) async {
    final body = jsonEncode({
      'device_id': me.id,
      'public_key_b64': me.publicKeyB64,
      'name': me.displayName,
    });
    final r = await http.post(_uri('/chat/devices/register'),
        headers: await _headers(json: true), body: body);
    if (r.statusCode >= 400) {
      throw Exception('register failed: ${r.statusCode}');
    }
    final j = jsonDecode(r.body) as Map<String, Object?>;
    return ChatContact(
      id: (j['device_id'] ?? '') as String,
      publicKeyB64: (j['public_key_b64'] ?? '') as String,
      fingerprint: fingerprintForKey((j['public_key_b64'] ?? '') as String),
      name: j['name'] as String?,
      verified: false,
    );
  }

  Future<ChatContact> resolveDevice(String id) async {
    final r = await http.get(_uri('/chat/devices/${Uri.encodeComponent(id)}'),
        headers: await _headers());
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
    final enc = _encryptMessage(me, peer, plainText,
        sealed: sealedSender, sessionKey: sessionKey);
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
      if (expireAfterSeconds != null) 'expire_after_seconds': expireAfterSeconds,
    });
    final r = await http.post(_uri('/chat/messages/send'),
        headers: await _headers(json: true), body: body);
    if (r.statusCode >= 400) {
      throw Exception('send failed: ${r.statusCode}');
    }
    final parsed = ChatMessage.fromJson(
        jsonDecode(r.body) as Map<String, Object?>);
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
    final qp = <String, String>{
      'device_id': deviceId,
      'limit': '$limit',
    };
    if (sinceIso != null && sinceIso.isNotEmpty) {
      qp['since_iso'] = sinceIso;
    }
    qp.putIfAbsent('sealed_view', () => '1');
    final r = await http.get(
        _uri('/chat/messages/inbox', qp),
        headers: await _headers());
    if (r.statusCode >= 400) {
      throw Exception('inbox failed: ${r.statusCode}');
    }
    final arr = jsonDecode(r.body) as List;
    return arr
        .map((m) => ChatMessage.fromJson(m as Map<String, Object?>))
        .toList();
  }

  Future<void> markRead(String id) async {
    await http.post(_uri('/chat/messages/$id/read'),
        headers: await _headers(json: true), body: jsonEncode({'read': true}));
  }

  Future<void> setBlock({
    required String deviceId,
    required String peerId,
    required bool blocked,
    bool hidden = false,
  }) async {
    await http.post(
      _uri('/chat/devices/${Uri.encodeComponent(deviceId)}/block'),
      headers: await _headers(json: true),
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
    await setBlock(deviceId: deviceId, peerId: peerId, blocked: false, hidden: hidden);
  }

  Future<void> registerPushToken({
    required String deviceId,
    required String token,
    String? platform,
  }) async {
    try {
      await http.post(
        _uri('/chat/devices/${Uri.encodeComponent(deviceId)}/push_token'),
        headers: await _headers(json: true),
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

  Stream<List<ChatMessage>> streamInbox({
    required String deviceId,
  }) {
    _ws?.sink.close();
    final u = Uri.parse(_base);
    final wsUri = Uri(
      scheme: u.scheme == 'https' ? 'wss' : 'ws',
      host: u.host,
      port: u.hasPort ? u.port : null,
      path: '/ws/chat/inbox',
      queryParameters: {'device_id': deviceId, 'sealed_view': '1'},
    );
    _ws = WebSocketChannel.connect(wsUri);
    return _ws!.stream.map((payload) {
      try {
        final j = jsonDecode(payload);
        if (j is Map && j['type'] == 'inbox' && j['messages'] is List) {
          final msgs = (j['messages'] as List)
              .map((m) =>
                  ChatMessage.fromJson(m as Map<String, Object?>))
              .toList();
          return msgs;
        }
      } catch (_) {}
      return <ChatMessage>[];
    });
  }

  void close() {
    _ws?.sink.close();
    _ws = null;
  }

  // Helpers
  (String, String) _encryptMessage(
      ChatIdentity me, ChatContact peer, String plain,
      {bool sealed = false, Uint8List? sessionKey}) {
    final rnd = Random.secure();
    final nonce =
        Uint8List.fromList(List<int>.generate(24, (_) => rnd.nextInt(256)));
    if (sealed && sessionKey != null) {
      final box = x25519.SecretBox(sessionKey);
      final cipher = box.encrypt(Uint8List.fromList(utf8.encode(plain)),
          nonce: nonce);
      return (base64Encode(cipher.nonce.asTypedList),
          base64Encode(cipher.cipherText.asTypedList));
    }
    final sk = x25519.PrivateKey(base64Decode(me.privateKeyB64));
    final pkPeer = x25519.PublicKey(base64Decode(peer.publicKeyB64));
    final box = x25519.Box(myPrivateKey: sk, theirPublicKey: pkPeer)
        .encrypt(Uint8List.fromList(utf8.encode(plain)), nonce: nonce);
    return (base64Encode(box.nonce.asTypedList),
        base64Encode(box.cipherText.asTypedList));
  }

  Future<Map<String, String>> _headers({bool json = false}) async {
    final h = <String, String>{};
    if (json) h['content-type'] = 'application/json';
    final sp = await SharedPreferences.getInstance();
    final cookie = sp.getString('sa_cookie');
    if (cookie != null && cookie.isNotEmpty) {
      h['sa_cookie'] = cookie;
    }
    return h;
  }

  Uri _uri(String path, [Map<String, String>? qp]) {
    final base = _base;
    final prefix = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
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

  Future<ChatIdentity?> loadIdentity() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_idKey);
    if (raw == null) return null;
    try {
      return ChatIdentity.fromMap(
          (jsonDecode(raw) as Map<String, Object?>));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveIdentity(ChatIdentity id) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_idKey, jsonEncode(id.toMap()));
  }

  Future<ChatContact?> loadPeer() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_peerKey);
    if (raw == null) return null;
    try {
      return ChatContact.fromMap(
          (jsonDecode(raw) as Map<String, Object?>));
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
        _contactsKey, jsonEncode(contacts.map((c) => c.toMap()).toList()));
  }

  Future<void> saveMessages(String peerId, List<ChatMessage> msgs) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('chat.msgs.$peerId',
        jsonEncode(msgs.map((m) => m.toMap()).toList()));
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

  Future<void> setNotifyPreview(bool enabled) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_notifyPreviewKey, enabled);
  }

  Future<bool> loadNotifyPreview() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_notifyPreviewKey) ?? false;
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
    final sec = _sec();
    final raw = await sec.read(key: _sessionKeyMap);
    if (raw == null || raw.isEmpty) return {};
    final map = (jsonDecode(raw) as Map<String, Object?>);
    return map.map((k, v) => MapEntry(k, v.toString()));
  }

  Future<void> saveSessionKey(String peerId, String keyB64) async {
    final map = await loadSessionKeys();
    map[peerId] = keyB64;
    final sec = _sec();
    await sec.write(key: _sessionKeyMap, value: jsonEncode(map));
  }

  Future<Map<String, Map<String, Object>>> loadChains() async {
    final sec = _sec();
    final raw = await sec.read(key: _chainMap);
    if (raw == null || raw.isEmpty) return {};
    final decoded = (jsonDecode(raw) as Map<String, Object?>);
    return decoded.map((k, v) =>
        MapEntry(k, (v as Map<String, Object?>).map((k2, v2) => MapEntry(k2, v2 ?? ''))));
  }

  Future<void> saveChain(String peerId, Map<String, Object> state) async {
    final map = await loadChains();
    map[peerId] = state;
    final sec = _sec();
    await sec.write(key: _chainMap, value: jsonEncode(map));
  }

  Future<Map<String, Object>> loadRatchet(String peerId) async {
    final sec = _sec();
    final raw = await sec.read(key: '$_ratchetMap.$peerId');
    if (raw == null || raw.isEmpty) return {};
    return jsonDecode(raw) as Map<String, Object>;
  }

  Future<void> saveRatchet(String peerId, Map<String, Object> state) async {
    final sec = _sec();
    await sec.write(key: '$_ratchetMap.$peerId', value: jsonEncode(state));
  }

  Future<void> deleteRatchet(String peerId) async {
    final sec = _sec();
    await sec.delete(key: '$_ratchetMap.$peerId');
  }

  static const _notifyPreviewKey = 'chat.notify.preview';
  static const _sessionKeyMap = 'chat.session.keys';
  static const _chainMap = 'chat.session.chain';
  static const _ratchetMap = 'chat.ratchet';

  FlutterSecureStorage _sec() => const FlutterSecureStorage(
        aOptions: AndroidOptions(
          encryptedSharedPreferences: true,
          resetOnError: true,
          // prefer hardware-backed when available
          sharedPreferencesName: 'chat_secure_store',
        ),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock,
        ),
        mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock),
      );
}
