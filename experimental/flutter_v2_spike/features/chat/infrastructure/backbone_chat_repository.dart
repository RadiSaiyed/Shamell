import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pinenacl/x25519.dart' as x25519;

import '../../../../core/base_url.dart';
import '../../../../core/chat/chat_models.dart' as legacy_chat;
import '../../../../core/chat/outbound_ratchet_bootstrap.dart';
import '../../../../core/chat/ratchet_models.dart';
import '../../../../core/chat/chat_service.dart';
import '../../../../core/device_binding_guard.dart';
import '../../../../core/logout_wipe.dart';
import '../../../../core/v2_auth_strangler.dart';
import '../../../../core/v2_chat_strangler.dart';
import '../domain/chat_message.dart';
import 'chat_repository.dart';

typedef OnBackboneChatAttemptRecorded = Future<void> Function();
typedef BackboneBaseUrlProvider = Future<String> Function();
typedef BackboneChatServiceFactory = ChatService Function(String baseUrl);

@visibleForTesting
bool shamellIsCriticalBackboneSyncFailure(Object error) {
  if (shamellIsCriticalDeviceBindingDriftError(error)) {
    return true;
  }
  if (error is ChatHttpException) {
    return error.statusCode == 401 || error.statusCode == 403;
  }
  final text = error.toString().toLowerCase();
  return text.contains('auth session required') ||
      text.contains('authentication required') ||
      text.contains('unauthorized') ||
      text.contains('forbidden');
}

class BackboneChatRepository implements ChatRepository {
  final OnBackboneChatAttemptRecorded? onChatAttemptRecorded;
  final BackboneBaseUrlProvider? baseUrlProvider;
  final BackboneChatServiceFactory? serviceFactory;

  BackboneChatRepository({
    this.onChatAttemptRecorded,
    this.baseUrlProvider,
    this.serviceFactory,
  });

  @override
  Future<List<ChatMessage>> listMessages() async {
    final ctx = await _resolveContext(requireOutboundPeerKey: false);
    try {
      final merged = await _syncThread(ctx);
      final sessionKey = await _loadSessionKey(
        store: ctx.store,
        peerId: ctx.peer.id,
        baseUrl: ctx.baseUrl,
      );
      return merged
          .map((m) => _toV2Message(m, ctx: ctx, sessionKey: sessionKey))
          .toList();
    } finally {
      ctx.service.close();
    }
  }

  @override
  Future<ChatMessage> sendMessage({
    required String text,
    required String sender,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      throw Exception('Message is empty');
    }

    final ctx = await _resolveContext(requireOutboundPeerKey: true);
    try {
      final outbound = await ChatOutboundRatchetBootstrapper(
        service: ctx.service,
        store: ctx.store,
      ).nextOutboundSendContext(
        me: ctx.me,
        peer: ctx.peer,
      );
      final outboundCtx = ctx.withPeer(outbound.peer);

      final payload = jsonEncode(<String, Object?>{
        'text': cleanText,
        'client_ts': DateTime.now().toUtc().toIso8601String(),
        'sender_fp': ctx.me.fingerprint,
        'surface': 'v2_chat',
      });

      final sent = await ctx.service.sendMessage(
        me: ctx.me,
        peer: outbound.peer,
        plainText: payload,
        sealedSender: true,
        senderHint: ctx.me.fingerprint,
        sessionKey: outbound.sessionKey,
        keyId: outbound.keyId,
        prevKeyId: outbound.prevKeyId,
        senderDhPubB64: outbound.senderDhPubB64,
        metricVariant: V2ChatFlowVariant.v2,
      );

      await _mergeMessages(
        ctx: outboundCtx,
        incoming: <legacy_chat.ChatMessage>[sent],
      );
      if (onChatAttemptRecorded != null) {
        try {
          await onChatAttemptRecorded!.call();
        } catch (_) {}
      }
      return _toV2Message(
        sent,
        ctx: outboundCtx,
        sessionKey: outbound.sessionKey,
        fallbackText: cleanText,
      );
    } finally {
      ctx.service.close();
    }
  }

  Future<_BackboneContext> _resolveContext({
    required bool requireOutboundPeerKey,
  }) async {
    final base = await _resolveBaseUrl();
    final service = serviceFactory?.call(base) ?? ChatService(base);
    final store = ChatLocalStore();
    var resolved = false;
    try {
      try {
        await service.ensureAccountChatReady();
      } catch (e) {
        if (shamellIsCriticalDeviceBindingDriftError(e)) {
          await wipeLocalAccountData(
            preserveDevicePrefs: true,
            baseUrlOverride: base,
          );
          throw Exception(
            'This Shamell session no longer matches this device. Sign in again.',
          );
        }
        rethrow;
      }
      final me = await store.loadIdentity(baseUrlOverride: base);
      if (me == null) {
        throw Exception('Chat identity unavailable');
      }

      final contacts = await store.loadContacts(baseUrlOverride: base);
      var activePeerId =
          (await store.loadActivePeer(baseUrlOverride: base) ?? '').trim();
      legacy_chat.ChatContact? peer;
      if (activePeerId.isNotEmpty) {
        for (final contact in contacts) {
          if (contact.id == activePeerId) {
            peer = contact;
            break;
          }
        }
      }
      if (peer == null && contacts.isNotEmpty) {
        peer = contacts.first;
        activePeerId = peer.id;
        await store.setActivePeer(activePeerId, baseUrlOverride: base);
      }
      if (peer == null || peer.id.trim().isEmpty) {
        throw const NoActiveChatPeerException(
          'No chat contact selected yet.',
        );
      }

      var resolvedPeer = peer;
      if (resolvedPeer.publicKeyB64.trim().isEmpty) {
        try {
          final refreshed = await service.resolveDevice(resolvedPeer.id);
          resolvedPeer = refreshed;
          await store.upsertContact(
            resolvedPeer,
            baseUrlOverride: base,
          );
        } catch (e) {
          if (shamellIsCriticalBackboneSyncFailure(e)) {
            await wipeLocalAccountData(
              preserveDevicePrefs: true,
              baseUrlOverride: base,
            );
            throw Exception(
              'This Shamell session is no longer valid on this device. Sign in again.',
            );
          }
        }
      }
      if (resolvedPeer.publicKeyB64.trim().isEmpty &&
          requireOutboundPeerKey &&
          !await _hasUsableLocalOutboundRatchet(
            store: store,
            peerId: resolvedPeer.id,
            baseUrl: base,
          )) {
        throw Exception('Active chat peer has no public key.');
      }

      resolved = true;
      return _BackboneContext(
        baseUrl: base,
        service: service,
        store: store,
        me: me,
        peer: resolvedPeer,
      );
    } finally {
      if (!resolved) {
        service.close();
      }
    }
  }

  Future<bool> _hasUsableLocalOutboundRatchet({
    required ChatLocalStore store,
    required String peerId,
    required String baseUrl,
  }) async {
    final raw = await store.loadRatchet(
      peerId,
      baseUrlOverride: baseUrl,
    );
    if (raw.isEmpty) return false;
    final map = <String, Object?>{};
    raw.forEach((key, value) {
      map[key] = value;
    });
    final state = RatchetState.fromJson(map);
    return state != null && _isUsableRatchetState(state);
  }

  bool _isUsableRatchetState(RatchetState state) {
    final hasValidKeys = state.rootKey.length == 32 &&
        state.sendChainKey.length == 32 &&
        state.recvChainKey.length == 32 &&
        state.dhPriv.length == 32 &&
        state.dhPub.length == 32 &&
        state.peerDhPub.length == 32;
    if (!hasValidKeys) return false;
    if (state.sendCount < 0 || state.recvCount < 0 || state.pn < 0) {
      return false;
    }
    for (final skipped in state.skipped.values) {
      if (_decodeCurveKeyB64(skipped) == null) {
        return false;
      }
    }
    return true;
  }

  Uint8List? _decodeCurveKeyB64(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    try {
      final decoded = base64Decode(value);
      if (decoded.length != 32) return null;
      return Uint8List.fromList(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<String> _resolveBaseUrl() async {
    final raw = baseUrlProvider != null
        ? await baseUrlProvider!()
        : await V2AuthStranglerStore.resolveBaseUrl();
    final baseUrl = normalizeSecureApiBaseUrl(raw.trim());
    if (baseUrl == null) {
      throw Exception('Invalid API base URL. Configure HTTPS base_url.');
    }
    return baseUrl;
  }

  Future<List<legacy_chat.ChatMessage>> _syncThread(
      _BackboneContext ctx) async {
    List<legacy_chat.ChatMessage> cached = await ctx.store.loadMessages(
      ctx.peer.id,
      baseUrlOverride: ctx.baseUrl,
    );
    List<legacy_chat.ChatMessage> inbox = const <legacy_chat.ChatMessage>[];
    try {
      final directCursor = await ctx.store.loadDirectInboxCursor(
        baseUrlOverride: ctx.baseUrl,
      );
      inbox = await ctx.service.fetchInboxPaged(
        deviceId: ctx.me.id,
        sinceIso: directCursor?.sinceIso,
        sinceId: directCursor?.sinceId,
        batchSize: 200,
        maxPages: 25,
      );
    } catch (e) {
      if (shamellIsCriticalBackboneSyncFailure(e)) {
        await wipeLocalAccountData(
          preserveDevicePrefs: true,
          baseUrlOverride: ctx.baseUrl,
        );
        throw Exception(
          'This Shamell session is no longer valid on this device. Sign in again.',
        );
      }
      inbox = const <legacy_chat.ChatMessage>[];
    }
    if (inbox.isNotEmpty) {
      cached = await _mergeMessages(ctx: ctx, incoming: inbox);
      await ctx.store.saveLatestDirectInboxCursor(
        inbox,
        baseUrlOverride: ctx.baseUrl,
      );
    }
    cached.sort((a, b) {
      final left = a.createdAt ??
          a.deliveredAt ??
          a.readAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final right = b.createdAt ??
          b.deliveredAt ??
          b.readAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final byTime = left.compareTo(right);
      if (byTime != 0) return byTime;
      return a.id.compareTo(b.id);
    });
    return cached;
  }

  Future<List<legacy_chat.ChatMessage>> _mergeMessages({
    required _BackboneContext ctx,
    required List<legacy_chat.ChatMessage> incoming,
  }) async {
    final peerId = ctx.peer.id;
    final meId = ctx.me.id;
    final current = await ctx.store.loadMessages(
      peerId,
      baseUrlOverride: ctx.baseUrl,
    );
    final byId = <String, legacy_chat.ChatMessage>{
      for (final m in current) m.id: m,
    };
    final readAcks = <Future<void>>[];
    final readIds = <String>{};
    var changed = false;
    for (final m in incoming) {
      final candidatePeer = _peerIdForMessage(m, ctx.peer, meId);
      if (candidatePeer != peerId) continue;
      if (!byId.containsKey(m.id)) {
        changed = true;
      }
      byId[m.id] = m;
      if (m.isIncomingFor(meId) && readIds.add(m.id)) {
        readAcks.add(
          ctx.service.markRead(m.id, deviceId: meId).catchError((_) {}),
        );
      }
    }
    if (readAcks.isNotEmpty) {
      await Future.wait<void>(readAcks);
    }
    final next = byId.values.toList();
    if (changed) {
      next.sort((a, b) {
        final left = a.createdAt ??
            a.deliveredAt ??
            a.readAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final right = b.createdAt ??
            b.deliveredAt ??
            b.readAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final byTime = left.compareTo(right);
        if (byTime != 0) return byTime;
        return a.id.compareTo(b.id);
      });
      await ctx.store.saveMessages(
        peerId,
        next,
        baseUrlOverride: ctx.baseUrl,
      );
    }
    return next;
  }

  ChatMessage _toV2Message(
    legacy_chat.ChatMessage message, {
    required _BackboneContext ctx,
    required Uint8List? sessionKey,
    String? fallbackText,
  }) {
    final decrypted = _decryptMessage(
      message: message,
      sessionKey: sessionKey,
    );
    final text = fallbackText ?? v2BackboneChatDecodePayloadText(decrypted);
    final sender = message.isOwnFor(ctx.me.id)
        ? 'You'
        : ((ctx.peer.name ?? '').trim().isEmpty
            ? ctx.peer.id
            : ctx.peer.name!.trim());
    final sentAt = message.createdAt ??
        message.deliveredAt ??
        message.readAt ??
        DateTime.now();
    return ChatMessage(
      id: message.id,
      sender: sender,
      text: text,
      sentAt: sentAt,
    );
  }

  Future<Uint8List?> _loadSessionKey({
    required ChatLocalStore store,
    required String peerId,
    required String baseUrl,
  }) async {
    try {
      final keys = await store.loadSessionKeys(baseUrlOverride: baseUrl);
      final raw = (keys[peerId] ?? '').trim();
      if (raw.isEmpty) return null;
      final bytes = base64Decode(raw);
      if (bytes.length != 32) return null;
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  String _decryptMessage({
    required legacy_chat.ChatMessage message,
    required Uint8List? sessionKey,
  }) {
    if (message.trustedLocalPlaintext) {
      try {
        return utf8.decode(base64Decode(message.boxB64));
      } catch (_) {
        return '<encrypted>';
      }
    }
    if (!message.sealedSender ||
        sessionKey == null ||
        sessionKey.length != 32) {
      return '<encrypted>';
    }
    try {
      final box = x25519.SecretBox(sessionKey);
      final cipher = x25519.ByteList(base64Decode(message.boxB64));
      final nonce = base64Decode(message.nonceB64);
      final plain = box.decrypt(cipher, nonce: nonce);
      return utf8.decode(plain);
    } catch (_) {
      return '<encrypted>';
    }
  }

  String _peerIdForMessage(
    legacy_chat.ChatMessage m,
    legacy_chat.ChatContact peer,
    String myId,
  ) {
    final peerId = m.peerIdFor(myId);
    if (peerId.isNotEmpty) {
      return peerId;
    }
    final senderHint = (m.senderHint ?? '').trim();
    if (senderHint.isNotEmpty && senderHint == peer.fingerprint.trim()) {
      return peer.id;
    }
    return '';
  }
}

@visibleForTesting
String v2BackboneChatDecodePayloadText(String raw) {
  if (raw.trim().isEmpty) return '<empty>';
  if (raw == '<encrypted>') return raw;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      final text = (decoded['text'] ?? '').toString().trim();
      if (text.isNotEmpty) return text;
      final kind = (decoded['kind'] ?? '').toString().trim().toLowerCase();
      if (kind == 'voice') return '[voice]';
      if (kind == 'location') return '[location]';
      if (kind == 'contact') return '[contact]';
      if (decoded['attachment_b64'] is String &&
          (decoded['attachment_b64'] as String).trim().isNotEmpty) {
        return '[image]';
      }
      return '<message>';
    }
  } catch (_) {}
  return raw;
}

class _BackboneContext {
  final String baseUrl;
  final ChatService service;
  final ChatLocalStore store;
  final legacy_chat.ChatIdentity me;
  final legacy_chat.ChatContact peer;

  const _BackboneContext({
    required this.baseUrl,
    required this.service,
    required this.store,
    required this.me,
    required this.peer,
  });

  _BackboneContext withPeer(legacy_chat.ChatContact nextPeer) {
    return _BackboneContext(
      baseUrl: baseUrl,
      service: service,
      store: store,
      me: me,
      peer: nextPeer,
    );
  }
}
