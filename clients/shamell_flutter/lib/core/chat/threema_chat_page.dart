import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:local_auth/local_auth.dart';
import 'package:pinenacl/x25519.dart' as x25519;
import '../design_tokens.dart';
import '../notification_service.dart';
import '../l10n.dart';
import '../../main.dart' show AppBG;
import 'chat_models.dart';
import 'chat_service.dart';
import 'ratchet_models.dart';

class ThreemaChatPage extends StatefulWidget {
  final String baseUrl;
  const ThreemaChatPage({super.key, required this.baseUrl});

  @override
  State<ThreemaChatPage> createState() => _ThreemaChatPageState();
}

class _ThreemaChatPageState extends State<ThreemaChatPage> {
  late final ChatService _service;
  final _store = ChatLocalStore();
  ChatIdentity? _me;
  ChatContact? _peer;
  List<ChatContact> _contacts = [];
  final _peerIdCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  List<ChatMessage> _messages = [];
  final Map<String, List<ChatMessage>> _cache = {};
  Map<String, int> _unread = {};
  String? _activePeerId;
  Uint8List? _attachedBytes;
  String? _attachedMime;
  String? _attachedName;
  bool _loading = false;
  bool _wsUp = false;
  StreamSubscription<List<ChatMessage>>? _wsSub;
  StreamSubscription<RemoteMessage>? _pushSub;
  bool _notifyPreview = false;
  bool _disappearing = false;
  Duration _disappearAfter = const Duration(minutes: 30);
  bool _showHidden = false;
  bool _showBlocked = false;
  String? _error;
  String? _backupText;
  final Map<String, Uint8List> _sessionKeys = {};
  final Map<String, Uint8List> _sessionKeysByFp = {};
  final Map<String, _ChainState> _chains = {};
  final Map<String, RatchetState> _ratchets = {};
  _SafetyNumber? _safetyNumber;
  String? _ratchetWarning;
  bool _sessionVerified = false;
  final Set<String> _seenMessageIds = {};
  bool _promptedForKeyChange = false;
  String? _sessionHash;
  int _tabIndex = 1; // 0=Contacts,1=Chats,2=Profile,3=Settings
  bool _selectionMode = false;

  @override
  void initState() {
    super.initState();
    _service = ChatService(widget.baseUrl);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final me = await _store.loadIdentity();
    final peer = await _store.loadPeer();
    final contacts = await _store.loadContacts();
    final unread = await _store.loadUnread();
    final active = await _store.loadActivePeer();
    final notifyPreview = await _store.loadNotifyPreview();
    final sessionKeys = await _store.loadSessionKeys();
    final chainStates = await _store.loadChains();
    final mergedContacts = List<ChatContact>.from(contacts);
    if (peer != null && mergedContacts.where((c) => c.id == peer.id).isEmpty) {
      mergedContacts.add(peer);
    }
    // load ratchets after we know which peers we have locally
    for (final c in mergedContacts) {
      final raw = await _store.loadRatchet(c.id);
      final st = raw.isNotEmpty ? RatchetState.fromJson(raw as Map<String, Object?>) : null;
      if (st != null) {
        _ratchets[c.id] = st;
      }
    }
    String? activeId = active ?? peer?.id;
    if (activeId == null && mergedContacts.isNotEmpty) {
      activeId = mergedContacts.first.id;
    }
    ChatContact? activePeer;
    if (activeId != null) {
      for (final c in mergedContacts) {
        if (c.id == activeId) {
          activePeer = c;
          break;
        }
      }
    }
    activePeer ??= mergedContacts.isNotEmpty ? mergedContacts.first : null;
    final cachedMsgs = activePeer != null
        ? await _store.loadMessages(activePeer.id)
        : <ChatMessage>[];
    setState(() {
      _me = me;
      _peer = activePeer;
      _contacts = mergedContacts;
      _activePeerId = activePeer?.id;
      if (activePeer != null) {
        _cache[activePeer.id] = cachedMsgs;
        _messages = cachedMsgs;
      }
      _unread = unread;
      _notifyPreview = notifyPreview;
      _disappearing = activePeer?.disappearing ?? false;
      _disappearAfter = activePeer?.disappearAfter ?? const Duration(minutes: 30);
      _showHidden = false;
      _peerIdCtrl.text = activePeer?.id ?? '';
      _displayNameCtrl.text = me?.displayName ?? '';
      sessionKeys.forEach((k, v) {
        try {
          final key = base64Decode(v);
          _sessionKeys[k] = key;
        } catch (_) {}
      });
      chainStates.forEach((pid, state) {
        try {
          final ck = base64Decode(state['ck']?.toString() ?? '');
          final ctr = int.tryParse(state['ctr']?.toString() ?? '0') ?? 0;
          _chains[pid] = _ChainState(chainKey: ck, counter: ctr);
        } catch (_) {}
      });
      _safetyNumber = _computeSafety();
      _sessionVerified = activePeer?.verified ?? false;
      _sessionHash = _computeSessionHash();
    });
    if (me != null) {
      await _ensurePushToken();
      await _pullInbox();
      _listenWs();
      _listenPush();
    }
  }

  Future<void> _generateIdentity() async {
    final sk = x25519.PrivateKey.generate();
    final pk = sk.publicKey;
    final me = ChatIdentity(
      id: generateShortId(),
      publicKeyB64: base64Encode(pk.asTypedList),
      privateKeyB64: base64Encode(sk.asTypedList),
      fingerprint: fingerprintForKey(base64Encode(pk.asTypedList)),
      displayName:
          _displayNameCtrl.text.trim().isEmpty ? null : _displayNameCtrl.text.trim(),
    );
    await _store.saveIdentity(me);
    setState(() {
      _me = me;
      _error = null;
    });
  }

  Future<void> _register() async {
    if (_me == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _service.registerDevice(_me!);
      await _pullInbox();
      _listenWs();
      await _ensurePushToken();
      _sessionVerified = false;
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolvePeer({String? presetId}) async {
    final id = (presetId ?? _peerIdCtrl.text).trim();
    if (id.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
          final peer = await _service.resolveDevice(id);
          final verified = await _store.isVerified(peer.id, peer.fingerprint);
          final c = peer.copyWith(verified: verified);
          await _store.savePeer(c);
          final updatedContacts = _upsertContact(c);
          await _store.saveContacts(updatedContacts);
          await _store.setActivePeer(c.id);
          final cached = await _store.loadMessages(c.id);
          _cache[c.id] = cached;
          setState(() {
            _peer = c;
            _activePeerId = c.id;
            _contacts = updatedContacts;
            _messages = cached;
            _unread[c.id] = 0;
            _peerIdCtrl.text = c.id;
            _safetyNumber = _computeSafety();
            _ratchetWarning = null;
          });
          await _store.saveUnread(_unread);
          await _pullInbox();
        } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markVerified() async {
    final p = _peer;
    if (p == null) return;
    await _store.markVerified(p.id, p.fingerprint);
    final updated = p.copyWith(verified: true);
    final contacts = _upsertContact(updated);
    await _store.saveContacts(contacts);
    setState(() {
      _peer = updated;
      _contacts = contacts;
      _disappearing = updated.disappearing;
      _disappearAfter = updated.disappearAfter ?? _disappearAfter;
      _safetyNumber = _computeSafety();
      _sessionVerified = true;
    });
  }

  Future<void> _send() async {
    if (_me == null || _peer == null) return;
    final text = _msgCtrl.text.trim();
    if (text.isEmpty && _attachedBytes == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _ratchetWarning = null;
    });
    try {
      _sessionHash ??= _computeSessionHash();
      final payload = <String, Object?>{
        "text": text,
        "client_ts": DateTime.now().toIso8601String(),
        "sender_fp": _me?.fingerprint ?? '',
        "session_hash": _sessionHash,
      };
    if (_attachedBytes != null) {
      payload["attachment_b64"] = base64Encode(_attachedBytes!);
      payload["attachment_mime"] = _attachedMime ?? "image/jpeg";
    }
    final ratchet = _ensureRatchet(_peer!);
    final mk = _ratchetNextSend(ratchet);
    final sessionKey = mk.$1;
    final keyId = mk.$2;
    final prevKeyId = mk.$3;
    final dhPubB64 = mk.$4;
      final msg = await _service.sendMessage(
          me: _me!,
          peer: _peer!,
          plainText: jsonEncode(payload),
          expireAfterSeconds:
              _disappearing ? _disappearAfter.inSeconds : null,
          sealedSender: true,
          senderHint: _me?.fingerprint,
          sessionKey: sessionKey,
          keyId: keyId,
          prevKeyId: prevKeyId,
          senderDhPubB64: dhPubB64);
      _msgCtrl.clear();
      _attachedBytes = null;
      _attachedMime = null;
      _attachedName = null;
      _mergeMessages([msg]);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pullInbox() async {
    if (_me == null) return;
    try {
      final msgs = await _service.fetchInbox(deviceId: _me!.id, limit: 80);
      _mergeMessages(msgs);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  void _listenWs() {
    _wsSub?.cancel();
    _service.close();
    final me = _me;
    if (me == null) return;
    _wsSub = _service.streamInbox(deviceId: me.id).listen((msgs) {
      if (msgs.isNotEmpty) {
        _mergeMessages(msgs);
      }
      if (mounted) setState(() => _wsUp = true);
    }, onError: (_) {
      if (mounted) setState(() => _wsUp = false);
    }, onDone: () {
      if (mounted) setState(() => _wsUp = false);
    });
  }

  void _listenPush() {
    _pushSub?.cancel();
    _pushSub = FirebaseMessaging.onMessage.listen((msg) {
      try {
        final data = msg.data;
        if (data['type'] == 'chat' &&
            (data['device_id'] == _me?.id || data['deviceId'] == _me?.id)) {
          _pullInbox();
          _showLocalNotification();
        }
      } catch (_) {}
    });
  }

  Future<void> _pickAttachment() async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(
          source: ImageSource.gallery, maxWidth: 1600, imageQuality: 82);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      setState(() {
        _attachedBytes = bytes;
        final ext = (x.name.split('.').last).toLowerCase();
        _attachedMime = ext == 'png' ? 'image/png' : 'image/jpeg';
        _attachedName = x.name;
      });
    } catch (e) {
      final l = L10n.of(context);
      setState(() => _error = '${l.mirsaalAttachFailed}: $e');
    }
  }

  Future<void> _showLocalNotification() async {
    try {
      final latest =
          _latestCachedMessage() ?? (_messages.isNotEmpty ? _messages.last : null);
      final l = L10n.of(context);
      final title = l.mirsaalNewMessageTitle;
      String body = l.mirsaalNewMessageBody;
      if (_notifyPreview && latest != null) {
        body = _previewText(latest);
      }
      await NotificationService.showSimple(title: title, body: body);
    } catch (_) {}
  }

  Future<void> _ensurePushToken() async {
    final me = _me;
    if (me == null) return;
    try {
      final perm = await FirebaseMessaging.instance.requestPermission();
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;
      final tok = await FirebaseMessaging.instance.getToken();
      if (tok == null || tok.isEmpty) return;
      final platform = switch (defaultTargetPlatform) {
        TargetPlatform.android => 'android',
        TargetPlatform.iOS => 'ios',
        TargetPlatform.macOS => 'macos',
        TargetPlatform.windows => 'windows',
        TargetPlatform.linux => 'linux',
        _ => 'flutter',
      };
      await _service.registerPushToken(
          deviceId: me.id, token: tok, platform: platform);
    } catch (_) {
      // Soft-fail; push registration is best-effort for now.
    }
  }

  Future<void> _switchPeer(ChatContact c) async {
    final cached = _cache[c.id] ?? await _store.loadMessages(c.id);
    _cache[c.id] = cached;
    _pruneExpired(c.id);
    setState(() {
      _peer = c;
      _activePeerId = c.id;
      _peerIdCtrl.text = c.id;
      _messages = cached;
      _unread[c.id] = 0;
      _disappearing = c.disappearing;
      _disappearAfter = c.disappearAfter ?? _disappearAfter;
      _safetyNumber = _computeSafety();
    });
    await _store.setActivePeer(c.id);
    await _store.saveUnread(_unread);
    await _markThreadRead(c.id);
    await _pullInbox();
  }

  void _mergeMessages(List<ChatMessage> msgs) {
    final meId = _me?.id;
    if (meId == null) return;
    final updatedUnread = Map<String, int>.from(_unread);
    var contactsChanged = false;
    for (final m in msgs) {
      if (_seenMessageIds.contains(m.id)) {
        continue; // replay protection
      }
      _seenMessageIds.add(m.id);
      final peerId = _peerIdForMessage(m, meId);
      final isIncoming = m.senderId != meId;
      final contact = _contacts.firstWhere(
          (c) => c.id == peerId,
          orElse: () => _peer ?? ChatContact(id: peerId, publicKeyB64: '', fingerprint: ''));
      if (contact.blocked) {
        // Skip storing blocked contacts; mark read to clear server backlog
        if (isIncoming) {
          unawaited(_service.markRead(m.id));
        }
        continue;
      }
      var list = _cache[peerId] ?? <ChatMessage>[];
      final map = {for (final msg in list) msg.id: msg};
      map[m.id] = m;
      list = map.values.toList()
        ..sort((a, b) {
          final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return ad.compareTo(bd);
        });
      if (list.length > 200) {
        list = list.sublist(list.length - 200);
      }
      _cache[peerId] = list;
      unawaited(_store.saveMessages(peerId, list));
      contactsChanged = _ensureContact(peerId, m.senderPubKeyB64) || contactsChanged;
      _pruneExpired(peerId);
      if (peerId == _activePeerId) {
        _messages = _cache[peerId] ?? list;
        updatedUnread[peerId] = 0;
        if (isIncoming) {
          unawaited(_service.markRead(m.id));
        }
      } else if (isIncoming) {
        updatedUnread[peerId] = (updatedUnread[peerId] ?? 0) + 1;
      }
    }
    setState(() {
      _unread = updatedUnread;
      if (_activePeerId != null) {
        _messages = _cache[_activePeerId!] ?? _messages;
      }
      if (contactsChanged) {
        _contacts = List<ChatContact>.from(_contacts);
      }
    });
    unawaited(_store.saveUnread(_unread));
  }

  String _decrypt(ChatMessage m) {
    final me = _me;
    if (me == null) return '<no identity>';
    // Try sealed-session secretbox first
    if (m.sealedSender) {
      final key = _sessionKeyForMessage(m);
      if (key != null) {
        try {
          final box = x25519.SecretBox(key);
          final cipher = x25519.ByteList(base64Decode(m.boxB64));
          final nonce = base64Decode(m.nonceB64);
          final plain =
              box.decrypt(cipher, nonce: nonce);
          return utf8.decode(plain);
        } catch (_) {}
      }
    }
    try {
      final sk = x25519.PrivateKey(base64Decode(me.privateKeyB64));
      final senderPkB64 = m.senderPubKeyB64.isNotEmpty
          ? m.senderPubKeyB64
          : _peer?.publicKeyB64 ?? '';
      if (senderPkB64.isEmpty) throw Exception('missing sender pk');
      final pkSender = x25519.PublicKey(base64Decode(senderPkB64));
      final cipher = base64Decode(m.boxB64);
      final nonce = base64Decode(m.nonceB64);
      final plain = x25519.Box(myPrivateKey: sk, theirPublicKey: pkSender)
          .decrypt(x25519.ByteList(cipher), nonce: Uint8List.fromList(nonce));
      return utf8.decode(plain);
    } catch (_) {
      try {
        return utf8.decode(base64Decode(m.boxB64));
      } catch (_) {
        return '<encrypted>';
      }
    }
  }

  bool _isIncoming(ChatMessage m) => _me != null && m.senderId != _me!.id;

  String _peerIdForMessage(ChatMessage m, String myId) {
    if (m.senderId.isNotEmpty) {
      return m.senderId == myId ? m.recipientId : m.senderId;
    }
    if (m.senderHint != null && m.senderHint!.isNotEmpty) {
      final found = _contacts
          .firstWhere((c) => c.fingerprint == m.senderHint, orElse: () => _peer ?? ChatContact(id: '', publicKeyB64: '', fingerprint: ''));
      if (found.id.isNotEmpty) return found.id;
    }
    return _peer?.id ?? m.recipientId;
  }

  bool _ensureContact(String peerId, String pubKeyB64) {
    if (peerId.isEmpty) return false;
    final exists = _contacts.any((c) => c.id == peerId);
    if (exists) return false;
    final c = ChatContact(
      id: peerId,
      publicKeyB64: pubKeyB64,
      fingerprint: fingerprintForKey(pubKeyB64),
      verified: false,
    );
    _contacts = [..._contacts, c];
    unawaited(_store.saveContacts(_contacts));
    return true;
  }

  List<ChatContact> _upsertContact(ChatContact c) {
    final idx = _contacts.indexWhere((x) => x.id == c.id);
    if (idx == -1) {
      _contacts = [..._contacts, c];
      return _contacts;
    }
    final copy = List<ChatContact>.from(_contacts);
    copy[idx] = c;
    _contacts = copy;
    return copy;
  }

  Future<void> _markThreadRead(String peerId) async {
    final meId = _me?.id;
    if (meId == null) return;
    final msgs = _cache[peerId] ?? await _store.loadMessages(peerId);
    for (final m in msgs) {
      if (m.senderId != meId) {
        unawaited(_service.markRead(m.id));
      }
    }
  }

  List<ChatContact> _sortedContacts() {
    final entries = _contacts.map((c) {
      final last = _cache[c.id] != null && _cache[c.id]!.isNotEmpty
          ? _cache[c.id]!.last
          : null;
      final ts = last?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return (c, ts);
    }).toList();
    entries.sort((a, b) => b.$2.compareTo(a.$2));
    return entries.map((e) => e.$1).toList();
  }

  void _pruneExpired(String peerId) {
    final meId = _me?.id;
    if (meId == null) return;
    final contact = _contacts.firstWhere((c) => c.id == peerId,
        orElse: () => _peer ?? ChatContact(id: peerId, publicKeyB64: '', fingerprint: ''));
    if (!contact.disappearing || contact.disappearAfter == null) return;
    final cutoff = DateTime.now().subtract(contact.disappearAfter!);
    final list = _cache[peerId] ?? [];
    final kept = list.where((m) {
      final ts = m.createdAt ?? m.deliveredAt ?? m.readAt ?? contact.verifiedAt;
      if (ts == null) return true;
      return ts.isAfter(cutoff);
    }).toList();
    if (kept.length != list.length) {
      _cache[peerId] = kept;
      if (peerId == _activePeerId) {
        _messages = kept;
      }
      unawaited(_store.saveMessages(peerId, kept));
    }
  }

  _DecodedPayload _decodeMessage(ChatMessage m) {
    final raw = _decrypt(m);
    try {
      final j = jsonDecode(raw);
      if (j is Map) {
        final text = (j['text'] ?? '').toString();
        Uint8List? att;
        String? mime;
        if (j['attachment_b64'] is String && (j['attachment_b64'] as String).isNotEmpty) {
          try {
            att = base64Decode(j['attachment_b64'] as String);
            mime = (j['attachment_mime'] ?? 'image/jpeg').toString();
          } catch (_) {}
        }
        final clientTs = j['client_ts'] as String?;
        DateTime? ts;
        if (clientTs != null && clientTs.isNotEmpty) {
          try {
            ts = DateTime.parse(clientTs);
          } catch (_) {}
        }
        final senderFp = (j['sender_fp'] ?? '').toString();
        final sessionHash = (j['session_hash'] ?? '').toString();
        if (senderFp.isNotEmpty) {
          // map sender hint for sealed sender
          _sessionKeysByFp[senderFp] = _sessionKeysByFp[senderFp] ?? _sessionKeys[_activePeerId ?? ''] ?? Uint8List(0);
          if (_peer != null && _peer!.fingerprint != senderFp) {
            final l = L10n.of(context);
            _ratchetWarning = l.mirsaalSessionChangedBody;
          }
        }
        if (_sessionHash != null && sessionHash.isNotEmpty && sessionHash != _sessionHash) {
          _ratchetWarning = 'Session hash mismatch. Verify or reset.';
          _sessionVerified = false;
        }
        return _DecodedPayload(text: text, attachment: att, mime: mime, clientTs: ts);
      }
    } catch (_) {}
    return _DecodedPayload(text: raw, attachment: null, mime: null);
  }

  String _previewText(ChatMessage m) {
    final d = _decodeMessage(m);
    if (d.text.isNotEmpty) return d.text;
    final l = L10n.of(context);
    if (d.attachment != null) return l.mirsaalPreviewImage;
    return l.mirsaalPreviewUnknown;
  }

  String _expirationLabel(ChatMessage m) {
    Duration? ttl = m.expireAt != null && m.createdAt != null
        ? m.expireAt!.difference(m.createdAt!)
        : (_disappearing ? _disappearAfter : null);
    if (ttl == null || ttl.inSeconds <= 0) return '';
    final created = m.createdAt ?? DateTime.now();
    final expires = m.expireAt ?? created.add(ttl);
    final remaining = expires.difference(DateTime.now());
    if (remaining.isNegative) return 'expired';
    final mins = remaining.inMinutes;
    if (mins >= 1) return '~${mins}m';
    return '<1m';
  }

  Future<void> _openImage(Uint8List data, String? mime) async {
    await showDialog(
        context: context,
        builder: (_) {
          return Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: InteractiveViewer(
              child: Image.memory(data, fit: BoxFit.contain),
            ),
          );
        });
  }

  Future<void> _shareAttachment(Uint8List data, String? mime) async {
    try {
      final ext = (mime == 'image/png') ? 'png' : 'jpg';
      final file = XFile.fromData(data, mimeType: mime ?? 'image/jpeg', name: 'chat.$ext');
      await Share.shareXFiles([file], text: 'Encrypted chat image');
    } catch (e) {
      setState(() => _error = 'Share failed: $e');
    }
  }

  Future<void> _backupIdentity() async {
    final me = _me;
    if (me == null) return;
    final pass = await _promptPassphrase(confirm: true);
    if (pass == null || pass.isEmpty) return;
    try {
      final salt = _randomBytes(16);
      final key = _pbkdf2(pass, salt, 60000, 32);
      final box = x25519.SecretBox(key);
      final payload = jsonEncode(me.toMap());
      final nonce = _randomBytes(24);
      final cipher = box.encrypt(Uint8List.fromList(utf8.encode(payload)), nonce: nonce);
      final backup = 'CHATBACKUP|v1|salt=${base64Encode(salt)}|nonce=${base64Encode(nonce)}|cipher=${base64Encode(cipher.cipherText)}';
      setState(() => _backupText = backup);
      await Clipboard.setData(ClipboardData(text: backup));
      if (mounted) {
        final l = L10n.of(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.mirsaalBackupCreated)));
      }
    } catch (e) {
      final l = L10n.of(context);
      setState(() => _error = '${l.mirsaalBackupFailed}: $e');
    }
  }

  Future<void> _restoreIdentity() async {
    try {
      final backup = await _promptBackup();
      if (backup == null || backup.isEmpty) return;
      final pass = await _promptPassphrase(confirm: false);
      if (pass == null || pass.isEmpty) return;
      final parts = backup.split('|');
      if (parts.length < 5 || !backup.startsWith('CHATBACKUP|v1|')) {
        final l = L10n.of(context);
        setState(() => _error = l.mirsaalBackupInvalidFormat);
        return;
      }
      String? saltB64;
      String? nonceB64;
      String? cipherB64;
      for (final p in parts.skip(2)) {
        final kv = p.split('=');
        if (kv.length == 2) {
          if (kv[0] == 'salt') saltB64 = kv[1];
          if (kv[0] == 'nonce') nonceB64 = kv[1];
          if (kv[0] == 'cipher') cipherB64 = kv[1];
        }
      }
      if (saltB64 == null || nonceB64 == null || cipherB64 == null) {
        final l = L10n.of(context);
        setState(() => _error = l.mirsaalBackupMissingFields);
        return;
      }
      final salt = base64Decode(saltB64);
      final nonce = base64Decode(nonceB64);
      final cipher = x25519.ByteList(base64Decode(cipherB64));
      final key = _pbkdf2(pass, salt, 60000, 32);
      final box = x25519.SecretBox(key);
      final plain = box.decrypt(cipher, nonce: nonce);
      final map = jsonDecode(utf8.decode(plain));
      final restored = ChatIdentity.fromMap((map as Map<String, Object?>));
      if (restored == null) {
        final l = L10n.of(context);
        setState(() => _error = l.mirsaalBackupCorrupt);
        return;
      }
      await _store.saveIdentity(restored);
      setState(() {
        _me = restored;
        _backupText = backup;
      });
      await _register();
      await _pullInbox();
      _listenWs();
    } catch (e) {
      final l = L10n.of(context);
      setState(() => _error = '${l.mirsaalRestoreFailed}: $e');
    }
  }

  Future<String?> _promptPassphrase({required bool confirm}) async {
    final ctrl1 = TextEditingController();
    final ctrl2 = TextEditingController();
    final l = L10n.of(context);
    return await showDialog<String>(
        context: context,
        builder: (_) {
          return AlertDialog(
            title: Text(confirm
                ? l.mirsaalBackupPassphraseTitleSet
                : l.mirsaalBackupPassphraseTitleEnter),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl1,
                  obscureText: true,
                  decoration:
                      InputDecoration(labelText: l.mirsaalBackupPassphraseLabel),
                ),
                if (confirm)
                  TextField(
                    controller: ctrl2,
                    obscureText: true,
                    decoration:
                        InputDecoration(labelText: l.mirsaalBackupPassphraseConfirm),
                  ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: Text(l.mirsaalDialogCancel)),
              TextButton(
                  onPressed: () {
                    if (confirm && ctrl1.text != ctrl2.text) {
                      Navigator.of(context).pop(null);
                      return;
                    }
                    Navigator.of(context).pop(ctrl1.text);
                  },
                  child: Text(l.mirsaalDialogOk)),
            ],
          );
        });
  }

  Future<String?> _promptBackup() async {
    final ctrl = TextEditingController(text: _backupText);
    final l = L10n.of(context);
    return await showDialog<String>(
        context: context,
        builder: (_) {
          return AlertDialog(
            title: Text(l.mirsaalBackupDialogTitle),
            content: TextField(
              controller: ctrl,
              maxLines: 3,
              decoration: InputDecoration(labelText: l.mirsaalBackupDialogLabel),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: Text(l.mirsaalDialogCancel)),
              TextButton(
                  onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
                  child: Text(l.mirsaalRestoreBackupButton)),
            ],
          );
        });
  }

  Uint8List _randomBytes(int len) {
    final rnd = Random.secure();
    return Uint8List.fromList(List<int>.generate(len, (_) => rnd.nextInt(256)));
  }

  Uint8List _pbkdf2(String pass, Uint8List salt, int iterations, int length) {
    final passBytes = utf8.encode(pass);
    final hmac = crypto.Hmac(crypto.sha256, passBytes);
    final digestLen = hmac.convert(<int>[]).bytes.length;
    final blockCount = (length / digestLen).ceil();
    final out = BytesBuilder();
    for (var block = 1; block <= blockCount; block++) {
      var u = hmac.convert([...salt, ..._int32(block)]).bytes;
      var t = List<int>.from(u);
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      out.add(t);
    }
    final bytes = out.toBytes();
    return Uint8List.fromList(bytes.sublist(0, length));
  }

  List<int> _int32(int i) => [
        (i >> 24) & 0xff,
        (i >> 16) & 0xff,
        (i >> 8) & 0xff,
        i & 0xff,
      ];

  String _fmtDuration(Duration d) {
    if (d.inDays >= 1) return '${d.inDays}d';
    if (d.inHours >= 1) return '${d.inHours}h';
    if (d.inMinutes >= 1) return '${d.inMinutes}m';
    return '${d.inSeconds}s';
  }

  RatchetState _ensureRatchet(ChatContact peer) {
    final pid = peer.id;
    final existing = _ratchets[pid];
    if (existing != null) return existing;
    final dh = x25519.PrivateKey.generate();
    final dhPub = dh.publicKey;
    final shared = x25519.Box(
            myPrivateKey: dh, theirPublicKey: x25519.PublicKey(base64Decode(peer.publicKeyB64)))
        .sharedKey;
    final rk = Uint8List.fromList(crypto.sha256.convert(shared.asTypedList).bytes);
    final st = RatchetState(
      rootKey: rk,
      sendChainKey: rk,
      recvChainKey: rk,
      sendCount: 0,
      recvCount: 0,
      pn: 0,
      skipped: {},
      peerIdentity: peer.fingerprint,
      dhPriv: dh.asTypedList,
      dhPub: dhPub.asTypedList,
      peerDhPub: base64Decode(peer.publicKeyB64),
      peerDhPubB64: peer.publicKeyB64,
    );
    _ratchets[pid] = st;
    _store.saveRatchet(pid, st.toJson());
    return st;
  }

  (Uint8List, int, int, String) _ratchetNextSend(RatchetState st) {
    final mk = _kdfChain(st.sendChainKey, st.sendCount);
    st.sendChainKey = mk.$2;
    final keyId = st.sendCount;
    final prev = st.sendCount - 1;
    st.sendCount += 1;
    _store.saveRatchet(_peer?.id ?? st.peerIdentity, st.toJson());
    return (mk.$1, keyId, prev >= 0 ? prev : 0, base64Encode(st.dhPub));
  }

  Uint8List? _sessionKeyForMessage(ChatMessage m) {
    final targetCtr = m.keyId ?? 0;
    final fp = m.senderHint ?? _peer?.fingerprint ?? '';
    final peer = _contacts.firstWhere(
        (x) => x.fingerprint == fp,
        orElse: () => _peer ?? ChatContact(id: '', publicKeyB64: '', fingerprint: fp));
    final st = _ensureRatchet(peer);
    // detect identity/key mismatch
    if (fp.isNotEmpty && peer.fingerprint != fp) {
      final l = L10n.of(context);
      _ratchetWarning = l.mirsaalRatchetKeyMismatch;
      _sessionVerified = false;
      setState(() {});
      if (!_promptedForKeyChange) {
        _promptedForKeyChange = true;
        _showKeyChangePrompt();
      }
      return null;
    }
    if (m.senderDhPubB64 != null && m.senderDhPubB64!.isNotEmpty) {
      if (st.peerDhPubB64 != m.senderDhPubB64) {
        _dhRatchet(st, base64Decode(m.senderDhPubB64!), peerId: peer.id);
        st.peerDhPubB64 = m.senderDhPubB64!;
      }
    }
    // out-of-order guard
    if (targetCtr < st.recvCount &&
        !st.skipped.containsKey('${m.senderDhPubB64 ?? ''}:$targetCtr')) {
      final l = L10n.of(context);
      _ratchetWarning = l.mirsaalRatchetWindowWarning;
      setState(() {});
      return null;
    }
    // explicit window: allow up to +50 ahead
    if (targetCtr - st.recvCount > st.maxSkip) {
      final l = L10n.of(context);
      _ratchetWarning = l.mirsaalRatchetAheadWarning;
      setState(() {});
      return null;
    }
    // skipped cache lookup
    final skipKey = '${m.senderDhPubB64 ?? ''}:$targetCtr';
    if (st.skipped.containsKey(skipKey)) {
      final mk = st.skipped.remove(skipKey);
      _store.saveRatchet(peer.id, st.toJson());
      return mk != null ? base64Decode(mk) : null;
    }
    // advance recv chain
    var counter = st.recvCount;
    while (counter <= targetCtr) {
      final derived = _kdfChain(st.recvChainKey, counter);
      st.recvChainKey = derived.$2;
      if (counter == targetCtr) {
        st.recvCount = counter + 1;
        _store.saveRatchet(peer.id, st.toJson());
        _ratchetWarning = null;
        return derived.$1;
      } else {
        if (st.skipped.length >= st.maxSkip) {
          final firstKey = st.skipped.keys.first;
          st.skipped.remove(firstKey);
        }
        st.skipped['${m.senderDhPubB64 ?? ''}:$counter'] =
            base64Encode(derived.$1);
        counter += 1;
      }
    }
    _store.saveRatchet(peer.id, st.toJson());
    return null;
  }

  void _dhRatchet(RatchetState st, Uint8List newPeerDh, {required String peerId}) {
    st.pn = st.recvCount;
    st.recvCount = 0;
    st.peerDhPub = newPeerDh;
    st.skipped.clear();
    // derive new root + recv chain
    final dhShared = x25519.Box(
            myPrivateKey: x25519.PrivateKey(st.dhPriv),
            theirPublicKey: x25519.PublicKey(newPeerDh))
        .sharedKey;
    final newRoot = _kdfRoot(st.rootKey, dhShared.asTypedList);
    st.rootKey = newRoot.$1;
    st.recvChainKey = newRoot.$2;
    // rotate our DH
    final newDh = x25519.PrivateKey.generate();
    st.dhPriv = newDh.asTypedList;
    st.dhPub = newDh.publicKey.asTypedList;
    final dhShared2 = x25519.Box(
            myPrivateKey: newDh, theirPublicKey: x25519.PublicKey(newPeerDh))
        .sharedKey;
    final sendRoot = _kdfRoot(st.rootKey, dhShared2.asTypedList);
    st.rootKey = sendRoot.$1;
    st.sendChainKey = sendRoot.$2;
    st.sendCount = 0;
    _store.saveRatchet(peerId, st.toJson());
    _ratchetWarning = null;
    setState(() {});
  }

  (Uint8List, Uint8List) _kdfRoot(Uint8List rk, Uint8List dh) {
    final hmac = crypto.Hmac(crypto.sha256, rk);
    final combined = hmac.convert(dh).bytes;
    final k1 = crypto.sha256.convert([...combined, 0x01]).bytes;
    final k2 = crypto.sha256.convert([...combined, 0x02]).bytes;
    return (Uint8List.fromList(k1), Uint8List.fromList(k2));
  }

  (Uint8List, Uint8List) _kdfChain(Uint8List ck, int n) {
    final hmac = crypto.Hmac(crypto.sha256, ck);
    final mk = hmac.convert(utf8.encode('msg-$n')).bytes;
    final next = hmac.convert(utf8.encode('ck-$n')).bytes;
    return (Uint8List.fromList(mk), Uint8List.fromList(next));
  }

  void _showKeyChangePrompt() {
    if (!mounted) return;
    final l = L10n.of(context);
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              title: Text(l.mirsaalSessionChangedTitle),
              content: Text(l.mirsaalSessionChangedBody),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l.mirsaalLater)),
                TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _resetSession();
                    },
                    child: Text(l.mirsaalResetSessionLabel)),
              ],
            ));
  }

  _SafetyNumber? _computeSafety() {
    if (_me == null || _peer == null) return null;
    final a = _me!.fingerprint;
    final b = _peer!.fingerprint;
    final combined = (a.compareTo(b) <= 0) ? '$a$b' : '$b$a';
    final hash = crypto.sha256.convert(utf8.encode(combined)).bytes;
    final hex = hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final chunks = <String>[];
    for (var i = 0; i < hex.length; i += 10) {
      chunks.add(hex.substring(i, (i + 10).clamp(0, hex.length)));
    }
    return _SafetyNumber(chunks.join(' '), hex);
  }

  String? _computeSessionHash() {
    if (_me == null || _peer == null) return null;
    final a = _me!.fingerprint;
    final b = _peer!.fingerprint;
    final combined = (a.compareTo(b) <= 0) ? '$a$b' : '$b$a';
    return crypto.sha256.convert(utf8.encode('sess|$combined')).toString();
  }

  Future<void> _resetSession() async {
    final pid = _peer?.id;
    if (pid == null) return;
    _ratchets.remove(pid);
    _chains.remove(pid);
    _sessionKeys.remove(pid);
    _sessionKeysByFp.remove(_peer?.fingerprint ?? '');
    _cache[pid] = [];
    await _store.deleteRatchet(pid);
    await _store.saveSessionKey(pid, '');
    await _store.saveChain(pid, {});
    setState(() {
      _messages = [];
      _safetyNumber = _computeSafety();
      _sessionVerified = false;
      _sessionHash = _computeSessionHash();
      _ratchetWarning = null;
      _promptedForKeyChange = false;
    });
  }

  Future<bool> _authenticate() async {
    try {
      final auth = LocalAuthentication();
      final can = await auth.canCheckBiometrics || await auth.isDeviceSupported();
      if (!can) return true;
      final l = L10n.of(context);
      return await auth.authenticate(
          localizedReason: l.mirsaalUnlockHiddenReason,
          options: const AuthenticationOptions(biometricOnly: false));
    } catch (_) {
      return false;
    }
  }

  bool _hasHiddenContacts() => _contacts.any((c) => c.hidden);

  ChatMessage? _latestCachedMessage() {
    ChatMessage? latest;
    DateTime latestTs = DateTime.fromMillisecondsSinceEpoch(0);
    for (final entry in _cache.entries) {
      final list = entry.value;
      if (list.isEmpty) continue;
      final cand = list.last;
      final ts = cand.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (ts.isAfter(latestTs)) {
        latest = cand;
        latestTs = ts;
      }
      _seenMessageIds.add(cand.id);
    }
    return latest;
  }

  Color _trustColor(ChatContact p) {
    if (p.verified) return Tokens.colorPayments; // green when verified
    return Tokens.accent.withValues(alpha: 0.8);
  }

  Widget _ratchetBanner() {
    if (_ratchetWarning == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: .4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(_ratchetWarning!, style: const TextStyle(color: Colors.red))),
          TextButton(onPressed: _resetSession, child: const Text('Reset'))
        ],
      ),
    );
  }

  Future<void> _scanQr() async {
    final l = L10n.of(context);
    final code = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) {
          return SizedBox(
            height: 420,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Text(l.mirsaalScanContactQrTitle),
                Expanded(
                  child: MobileScanner(
                    fit: BoxFit.cover,
                    onDetect: (barcodes) {
                      if (barcodes.barcodes.isEmpty) return;
                      Navigator.of(ctx).pop(barcodes.barcodes.first.rawValue);
                    },
                  ),
                ),
              ],
            ),
          );
        });
    if (code == null) return;
    try {
      final data = jsonDecode(code);
      if (data is Map && data['id'] is String && data['pub'] is String) {
        final id = data['id'] as String;
        _peerIdCtrl.text = id;
        await _resolvePeer(presetId: id);
        return;
      }
    } catch (_) {}
    // fallback: treat as plain id
    _peerIdCtrl.text = code;
    await _resolvePeer(presetId: code);
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _pushSub?.cancel();
    _service.close();
    _peerIdCtrl.dispose();
    _msgCtrl.dispose();
    _displayNameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    final peer = _peer;
     final l = L10n.of(context);
    Widget body;
    switch (_tabIndex) {
      case 0:
        body = _buildContactsTab(me, peer);
        break;
      case 1:
        body = _buildChatsTab(me, peer);
        break;
      case 2:
        body = _buildProfileTab(me);
        break;
      case 3:
        body = _buildChannelTab();
        break;
      case 4:
      default:
        body = _buildSettingsTab();
        break;
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mirsaal'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_safetyNumber != null && _sessionVerified)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Tooltip(
                message: 'Session verified',
                child: Icon(Icons.verified_user, color: Tokens.colorPayments),
              ),
            ),
          if (_wsUp)
            const Padding(
              padding: EdgeInsets.only(right: 12.0),
              child: Icon(Icons.wifi_tethering, color: Colors.lightGreenAccent),
            )
          else
            IconButton(
                tooltip: 'Reconnect',
                onPressed: _listenWs,
                icon: const Icon(Icons.wifi_off))
        ],
      ),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const AppBG(),
          SafeArea(child: body),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (value) {
          setState(() {
            _tabIndex = value;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white70,
        backgroundColor: Colors.black.withValues(alpha: 0.15),
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.contacts_outlined),
            label: l.mirsaalTabContacts,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.chat_bubble_outline),
            label: l.mirsaalTabChats,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person_outline),
            label: l.mirsaalTabProfile,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.campaign_outlined),
            label: l.mirsaalTabChannel,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings_outlined),
            label: l.mirsaalTabSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildContactsTab(ChatIdentity? me, ChatContact? peer) {
    final l = L10n.of(context);
    return RefreshIndicator(
      onRefresh: () async => _pullInbox(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Icon(Icons.contacts_outlined, size: 22),
              const SizedBox(width: 8),
              Text(
                l.mirsaalTabContacts,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Builder(builder: (context) {
            final sorted = _sortedContacts();
            final visible = sorted
                .where((c) => (!c.hidden || _showHidden) && (!c.blocked || _showBlocked))
                .toList();
            if (visible.isEmpty) {
              // Demo contacts when there are no real contacts yet.
              final demo = [
                'Lea · Wallet & Taxi',
                'Omar · Food & Stays',
                'Ranya · Mirsaal Ops',
              ];
              return Column(
                children: demo
                    .map((name) => ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.person_outline),
                          ),
                          title: Text(name),
                          subtitle: const Text('Demo contact'),
                        ))
                    .toList(),
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: visible.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final c = visible[i];
                final isActive = c.id == _activePeerId;
                final unread = _unread[c.id] ?? 0;
                return ListTile(
                  onTap: () => _switchPeer(c),
                  selected: isActive,
                  leading: CircleAvatar(
                    backgroundColor:
                        c.verified ? Tokens.colorPayments.withValues(alpha: .2) : Tokens.accent.withValues(alpha: .15),
                    child: Text(
                      (c.name != null && c.name!.isNotEmpty
                              ? c.name!.substring(0, 1)
                              : c.id.substring(0, 1))
                          .toUpperCase(),
                    ),
                  ),
                  title: Text(c.name ?? c.id, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    c.fingerprint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: unread > 0
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Tokens.accent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('$unread', style: const TextStyle(color: Colors.white)),
                        )
                      : null,
                );
              },
            );
          }),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }

  Widget _buildChatsTab(ChatIdentity? me, ChatContact? peer) {
    final l = L10n.of(context);
    return RefreshIndicator(
      onRefresh: () async => _pullInbox(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              // Left: circular menu button with three dots
              InkWell(
                onTap: _showChatsMenu,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: .08),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: .30)),
                  ),
                  child: const Icon(Icons.more_horiz, size: 18),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l.homeChat,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 16),
                ),
              ),
              IconButton(
                tooltip: 'New chat',
                onPressed: _startNewChat,
                icon: const Icon(Icons.chat_outlined),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _conversationsCard(),
          const SizedBox(height: 12),
          _chatCard(me, peer),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }

  Widget _buildProfileTab(ChatIdentity? me) {
    final l = L10n.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _identityCard(me),
        const SizedBox(height: 16),
        ListTile(
          leading: const Icon(Icons.qr_code_2_outlined),
          title: Text(l.mirsaalProfileShowQr),
        ),
        ListTile(
          leading: const Icon(Icons.share_outlined),
          title: Text(l.mirsaalProfileShareId),
        ),
        ListTile(
          leading: const Icon(Icons.shield_outlined),
          title: Text(l.mirsaalProfileSafe),
        ),
        ListTile(
          leading: const Icon(Icons.file_upload_outlined),
          title: Text(l.mirsaalProfileExportId),
        ),
        ListTile(
          leading: const Icon(Icons.key_outlined),
          title: Text(l.mirsaalProfileRevocationPass),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.phone_iphone_outlined),
          title: Text(l.mirsaalProfileLinkedPhone),
        ),
        ListTile(
          leading: const Icon(Icons.alternate_email_outlined),
          title: Text(l.mirsaalProfileLinkedEmail),
        ),
        ListTile(
          leading: const Icon(Icons.vpn_key_outlined),
          title: Text(l.mirsaalProfilePublicKey),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.delete_forever_outlined, color: Colors.redAccent),
          title: Text(
            l.mirsaalProfileDeleteId,
            style: const TextStyle(color: Colors.redAccent),
          ),
        ),
      ],
    );
  }

  Widget _buildChannelTab() {
    final l = L10n.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          l.mirsaalTabChannel,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        const Text(
          'Channel feed will show broadcast messages and announcements here.',
        ),
      ],
    );
  }

  Widget _buildSettingsTab() {
    final l = L10n.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Icon(Icons.settings_outlined, size: 22),
            const SizedBox(width: 8),
            Text(
              l.mirsaalTabSettings,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ListTile(
          leading: const Icon(Icons.lock_outline),
          title: Text(l.mirsaalSettingsPrivacy),
        ),
        ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: Text(l.mirsaalSettingsAppearance),
        ),
        ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: Text(l.mirsaalSettingsNotifications),
        ),
        ListTile(
          leading: const Icon(Icons.chat_bubble_outline),
          title: Text(l.mirsaalSettingsChat),
        ),
        ListTile(
          leading: const Icon(Icons.perm_media_outlined),
          title: Text(l.mirsaalSettingsMedia),
        ),
        ListTile(
          leading: const Icon(Icons.storage_outlined),
          title: Text(l.mirsaalSettingsStorage),
        ),
        ListTile(
          leading: const Icon(Icons.lock_clock_outlined),
          title: Text(l.mirsaalSettingsPasscode),
        ),
        ListTile(
          leading: const Icon(Icons.call_outlined),
          title: Text(l.mirsaalSettingsCalls),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.star_border),
          title: Text(l.mirsaalSettingsRate),
        ),
        ListTile(
          leading: const Icon(Icons.group_add_outlined),
          title: Text(l.mirsaalSettingsInviteFriends),
        ),
        ListTile(
          leading: const Icon(Icons.support_agent_outlined),
          title: Text(l.mirsaalSettingsSupport),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: Text(l.mirsaalSettingsPrivacyPolicy),
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: Text(l.mirsaalSettingsTerms),
        ),
        ListTile(
          leading: const Icon(Icons.article_outlined),
          title: Text(l.mirsaalSettingsLicense),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.tune_outlined),
          title: Text(l.mirsaalSettingsAdvanced),
        ),
      ],
    );
  }

  Future<void> _markAllChatsRead() async {
    if (_unread.isEmpty) return;
    setState(() {
      _unread = {for (final e in _unread.entries) e.key: 0};
    });
    unawaited(_store.saveUnread(_unread));
  }

  void _showChatsMenu() {
    final l = L10n.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: Text(l.mirsaalChatsMarkAllRead),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _markAllChatsRead();
                },
              ),
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: Text(l.mirsaalChatsSelection),
                onTap: () {
                  Navigator.of(ctx).pop();
                  setState(() {
                    _selectionMode = !_selectionMode;
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _startNewChat() {
    // Reuse QR-based contact flow to initiate a new chat.
    _scanQr();
  }

  Widget _identityCard(ChatIdentity? me) {
    final l = L10n.of(context);
    return _block(
        title: l.mirsaalIdentityTitle,
        trailing: _loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              me?.id ?? l.mirsaalIdentityNotCreated,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              me != null
                  ? '${l.chatMyFingerprint} ${me.fingerprint}'
                  : l.mirsaalIdentityHint,
              style: TextStyle(
                  color: Theme.of(context).textTheme.bodySmall?.color ??
                      Colors.grey),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: TextField(
                  controller: _displayNameCtrl,
                  decoration: InputDecoration(
                      labelText: l.mirsaalDisplayNameOptional),
                )),
                const SizedBox(width: 8),
                FilledButton.icon(
                    onPressed: _generateIdentity,
                    icon: const Icon(Icons.bolt),
                    label: Text(l.mirsaalGenerate))
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: FilledButton.tonal(
                        onPressed: me == null ? null : _register,
                        child: Text(l.mirsaalRegisterWithRelay)),
                ),
                const SizedBox(width: 8),
                Expanded(
                    child: FilledButton.tonal(
                        onPressed: me == null
                            ? null
                            : () => _showQr(me),
                        child: Text(l.mirsaalShowQrButton))),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: FilledButton.tonal(
                        onPressed: me == null
                            ? null
                            : () async {
                                await Clipboard.setData(ClipboardData(text: me.id));
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(l.mirsaalIdCopiedSnack)));
                                }
                              },
                        child: Text(l.mirsaalCopyIdButton))),
                const SizedBox(width: 8),
                Expanded(
                    child: FilledButton.tonal(
                        onPressed: me == null
                            ? null
                            : () async {
                                await Share.share('My chat ID: ${me.id}\nFP: ${me.fingerprint}');
                              },
                        child: Text(l.mirsaalShareIdButton))),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: FilledButton.tonal(
                        onPressed: me == null ? null : _backupIdentity,
                        child: Text(l.mirsaalBackupPassphraseButton))),
                const SizedBox(width: 8),
                Expanded(
                    child: FilledButton.tonal(
                        onPressed: _restoreIdentity,
                        child: Text(l.mirsaalRestoreBackupButton))),
              ],
            ),
            if (_backupText != null && _backupText!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6.0),
                child: SelectableText(
                  _backupText!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey),
                ),
              )
          ],
        ));
  }

  Widget _conversationsCard() {
    final l = L10n.of(context);
    return _block(
        title: l.mirsaalTabChats,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
                tooltip: l.mirsaalSyncInbox,
                onPressed: _pullInbox,
                icon: const Icon(Icons.refresh)),
      IconButton(
          tooltip: _notifyPreview
              ? l.mirsaalMessagePreviewsDisable
              : l.mirsaalMessagePreviewsEnable,
          onPressed: () async {
            final next = !_notifyPreview;
            setState(() => _notifyPreview = next);
            await _store.setNotifyPreview(next);
          },
          icon: Icon(
              _notifyPreview ? Icons.visibility : Icons.visibility_off)),
      if (_ratchetWarning != null)
        const Padding(
          padding: EdgeInsets.only(left: 4.0),
          child: Icon(Icons.warning_amber, color: Colors.red),
        ),
            IconButton(
                tooltip:
                    _showBlocked ? l.mirsaalHideLockedChats : l.mirsaalShowLockedChats,
                onPressed: () {
                  setState(() {
                    _showBlocked = !_showBlocked;
                  });
                },
                icon: Icon(
                    _showBlocked ? Icons.block_flipped : Icons.block_outlined)),
          ],
        ),
        child: Column(
          children: [
            if (_contacts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: Text(l.mirsaalNoContactsHint),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (ctx, i) {
                  final sorted = _sortedContacts();
                  final visible = sorted
                      .where((c) => (!c.hidden || _showHidden) && (!c.blocked || _showBlocked))
                      .toList();
                  final c = visible[i];
                  final isActive = c.id == _activePeerId;
                  final unread = _unread[c.id] ?? 0;
                  final thread = _cache[c.id];
                  final last = thread != null && thread.isNotEmpty ? thread.last : null;
                  final preview =
                      last != null ? _previewText(last) : l.mirsaalNoMessagesYet;
                  final ts = last?.createdAt != null
                      ? last!.createdAt!.toLocal().toString().substring(0, 16)
                      : '';
                  return ListTile(
                    onTap: () => _switchPeer(c),
                    selected: isActive,
                    leading: CircleAvatar(
                      backgroundColor:
                          c.verified ? Tokens.colorPayments.withValues(alpha: .2) : Tokens.accent.withValues(alpha: .15),
                      child: Text(c.name != null && c.name!.isNotEmpty
                          ? c.name!.substring(0, 1).toUpperCase()
                          : c.id.substring(0, 1)),
                    ),
                    title: Row(
                      children: [
                        Expanded(child: Text(c.name ?? c.id, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        if (c.verified)
                          const Padding(
                            padding: EdgeInsets.only(left: 4.0),
                            child: Icon(Icons.verified, size: 18, color: Tokens.colorPayments),
                          ),
                        if (c.hidden)
                          const Padding(
                            padding: EdgeInsets.only(left: 4.0),
                            child: Icon(Icons.lock, size: 16, color: Colors.grey),
                          ),
                      ],
                    ),
                    subtitle: Text('${c.fingerprint} · $preview',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: unread > 0
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Tokens.accent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text('$unread', style: const TextStyle(color: Colors.white)),
                          )
                        : Text(ts, style: const TextStyle(fontSize: 12)),
                  );
                },
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemCount: _sortedContacts()
                    .where((c) => (!c.hidden || _showHidden) && (!c.blocked || _showBlocked))
                    .length,
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                      onPressed: _scanQr, child: Text(l.mirsaalScanQr)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonal(
                      onPressed: _pullInbox, child: Text(l.mirsaalSyncInbox)),
                ),
                if (_hasHiddenContacts()) ...[
                  const SizedBox(width: 8),
                  IconButton(
                      tooltip: _showHidden
                          ? l.mirsaalHideLockedChats
                          : l.mirsaalShowLockedChats,
                      onPressed: () async {
                        if (_showHidden) {
                          setState(() => _showHidden = false);
                          return;
                        }
                        final ok = await _authenticate();
                        if (ok) setState(() => _showHidden = true);
                      },
                      icon: Icon(_showHidden ? Icons.lock_open : Icons.lock)),
                ]
              ],
            )
          ],
        ));
  }

  Widget _contactCard(ChatContact? peer) {
    final verified = peer?.verified ?? false;
    final l = L10n.of(context);
    return _block(
        title: l.chatPeer,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _peerIdCtrl,
              decoration: InputDecoration(
                  labelText: l.mirsaalPeerIdLabel,
                  suffixIcon: IconButton(
                      onPressed: _scanQr, icon: const Icon(Icons.qr_code_scanner))),
            ),
            const SizedBox(height: 8),
              Row(children: [
              Expanded(
                  child: FilledButton(
                      onPressed: _resolvePeer, child: Text(l.mirsaalResolve))),
              const SizedBox(width: 8),
              Expanded(
                  child: FilledButton.tonal(
                      onPressed: verified ? null : _markVerified,
                      child: Text(
                          verified ? l.mirsaalVerifiedLabel : l.mirsaalMarkVerifiedLabel))),
            ]),
            const SizedBox(height: 8),
            if (peer != null) Row(
              children: [
                Expanded(
                    child: FilledButton.tonal(
                        onPressed: () async {
                          final next = !_disappearing;
                          setState(() {
                            _disappearing = next;
                          });
                          final updated = peer.copyWith(
                              disappearing: next,
                              disappearAfter: _disappearAfter);
                          final contacts = _upsertContact(updated);
                          await _store.saveContacts(contacts);
                          setState(() {
                            _peer = updated;
                            _contacts = contacts;
                          });
                        },
                        child: Text(_disappearing
                            ? l.mirsaalDisableDisappear
                            : l.mirsaalEnableDisappear))),
                const SizedBox(width: 8),
                Expanded(
                    child: DropdownButtonFormField<Duration>(
                  initialValue: _disappearAfter,
                  decoration:
                      InputDecoration(labelText: l.mirsaalDisappearAfter),
                  items: const [
                    Duration(minutes: 5),
                    Duration(minutes: 30),
                    Duration(hours: 1),
                    Duration(hours: 6),
                    Duration(days: 1),
                  ]
                      .map((d) => DropdownMenuItem(
                            value: d,
                            child: Text(_fmtDuration(d)),
                          ))
                      .toList(),
                  onChanged: (v) async {
                    if (v == null) return;
                    setState(() => _disappearAfter = v);
                    final updated = peer.copyWith(
                        disappearAfter: v, disappearing: _disappearing);
                    final contacts = _upsertContact(updated);
                    await _store.saveContacts(contacts);
                    setState(() {
                      _peer = updated;
                      _contacts = contacts;
                    });
                  },
                )),
              ],
            ),
            const SizedBox(height: 8),
            if (peer != null)
              Row(
                children: [
                  Expanded(
                      child: FilledButton.tonal(
                          onPressed: () async {
                            final updated = peer.copyWith(hidden: !peer.hidden);
                            final contacts = _upsertContact(updated);
                            try {
                              await _service.setHidden(
                                  deviceId: _me?.id ?? '',
                                  peerId: peer.id,
                                  hidden: updated.hidden);
                            } catch (_) {}
                            await _store.saveContacts(contacts);
                            setState(() {
                              _peer = updated;
                              _contacts = contacts;
                              if (updated.hidden && !_showHidden) {
                                _activePeerId = null;
                                _peer = null;
                                _messages = [];
                              }
                            });
                          },
                          child: Text(peer.hidden
                              ? l.mirsaalUnhideChat
                              : l.mirsaalHideChat))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: FilledButton.tonal(
                          onPressed: () async {
                            final updated = peer.copyWith(blocked: !peer.blocked, blockedAt: DateTime.now());
                            final contacts = _upsertContact(updated);
                            try {
                              await _service.setBlock(
                                  deviceId: _me?.id ?? '',
                                  peerId: peer.id,
                                  blocked: updated.blocked,
                                  hidden: updated.hidden);
                            } catch (_) {}
                            await _store.saveContacts(contacts);
                            setState(() {
                              _peer = updated;
                              _contacts = contacts;
                              if (updated.blocked && _activePeerId == peer.id) {
                                _messages = [];
                              }
                            });
                          },
                          child: Text(peer.blocked
                              ? l.mirsaalUnblock
                              : l.mirsaalBlock))),
                ],
              ),
            if (peer != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.verified, color: _trustColor(peer)),
                  const SizedBox(width: 6),
                  Text(
                    peer.verified
                        ? l.mirsaalTrustedFingerprint
                        : l.mirsaalUnverifiedContact,
                    style: TextStyle(
                        color: _trustColor(peer),
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('${l.mirsaalPeerFingerprintLabel} ${peer.fingerprint}'),
              const SizedBox(height: 4),
              Text('${l.mirsaalYourFingerprintLabel} ${_me?.fingerprint ?? ''}'),
              const SizedBox(height: 8),
              if (_safetyNumber != null)
                Row(
                  children: [
                    Expanded(
                        child: Text('${l.mirsaalSafetyLabel} ${_safetyNumber!.formatted}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.grey[600]))),
                    IconButton(
                        tooltip: l.mirsaalResetSessionLabel,
                        onPressed: _resetSession,
                        icon: const Icon(Icons.refresh)),
                  ],
                ),
            ]
          ],
        ));
  }

  Widget _chatCard(ChatIdentity? me, ChatContact? peer) {
    final l = L10n.of(context);
    return _block(
        title: l.mirsaalMessagesTitle,
        child: Column(
          children: [
            if (_ratchetWarning != null) _ratchetBanner(),
            if (_messages.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Text(peer == null
                    ? l.mirsaalAddContactFirst
                    : l.mirsaalNoMessagesYet),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (ctx, i) => _bubble(_messages[i], me),
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemCount: _messages.length,
              ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                    tooltip: l.mirsaalAttachImage,
                    onPressed:
                        (_loading || me == null || peer == null) ? null : _pickAttachment,
                    icon: const Icon(Icons.attach_file)),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    maxLines: 4,
                    minLines: 1,
                    decoration: InputDecoration(
                        labelText: l.mirsaalTypeMessage),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                    onPressed: (_loading || me == null || peer == null || (peer?.blocked ?? false))
                        ? null
                        : _send,
                    child: const Icon(Icons.send)),
              ],
            ),
            if (_attachedBytes != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        _attachedBytes!,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(
                      _attachedName ?? l.mirsaalImageAttached,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )),
                    IconButton(
                        tooltip: l.mirsaalRemoveAttachment,
                        onPressed: () {
                          setState(() {
                            _attachedBytes = null;
                            _attachedMime = null;
                            _attachedName = null;
                          });
                        },
                        icon: const Icon(Icons.close))
                  ],
                ),
              )
          ],
        ));
  }

  Widget _bubble(ChatMessage m, ChatIdentity? me) {
    final incoming = _isIncoming(m);
    final decoded = _decodeMessage(m);
    final text = decoded.text.isNotEmpty
        ? decoded.text
        : (decoded.attachment != null ? '[Image]' : '');
    final ts = m.createdAt != null
        ? m.createdAt!.toLocal().toString().substring(0, 16)
        : '';
    final status = incoming
        ? ''
        : m.readAt != null
            ? '✓✓ read'
            : m.deliveredAt != null
                ? '✓✓ delivered'
                : '✓ sent';
    final expTs = _expirationLabel(m);
    final incomingColor = Theme.of(context)
        .colorScheme
        .surfaceContainerHighest
        .withValues(alpha: .35);
    final outgoingColor = Tokens.accent.withValues(alpha: .18);
    return Align(
      alignment: incoming ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: incoming ? incomingColor : outgoingColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment:
              incoming ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            if (m.sealedSender && incoming && _ratchetWarning != null)
              Text(
                _ratchetWarning!,
                style: const TextStyle(color: Colors.red, fontSize: 11),
              ),
            Text(text),
            if (decoded.attachment != null) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: GestureDetector(
                  onTap: () => _openImage(decoded.attachment!, decoded.mime),
                  onLongPress: () => _shareAttachment(decoded.attachment!, decoded.mime),
                  child: Image.memory(
                    decoded.attachment!,
                    width: 220,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!incoming && status.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: Text(
                      status,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                  ),
                if (expTs.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: Text(
                      expTs,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.redAccent, fontSize: 11),
                    ),
                  ),
                Text(
                  ts,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _block({required String title, Widget? trailing, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: .2)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, 6))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              if (trailing != null) trailing
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  void _showQr(ChatIdentity me) {
    final payload = jsonEncode(
        {'id': me.id, 'pub': me.publicKeyB64, 'fp': me.fingerprint, 'name': me.displayName});
    showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (_) {
          return Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Share your ID',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                QrImageView(
                  data: payload,
                  version: QrVersions.auto,
                  size: 220,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square),
                  dataModuleStyle:
                      const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square),
                ),
                const SizedBox(height: 12),
                SelectableText(me.id),
                const SizedBox(height: 6),
                SelectableText('Fingerprint: ${me.fingerprint}'),
              ],
            ),
          );
        });
  }
}

class _DecodedPayload {
  final String text;
  final Uint8List? attachment;
  final String? mime;
  final DateTime? clientTs;
  const _DecodedPayload(
      {required this.text, required this.attachment, required this.mime, this.clientTs});
}

class _ChainState {
  Uint8List chainKey;
  int counter;
  _ChainState({required this.chainKey, required this.counter});
}

class _SafetyNumber {
  final String formatted;
  final String raw;
  const _SafetyNumber(this.formatted, this.raw);
}
