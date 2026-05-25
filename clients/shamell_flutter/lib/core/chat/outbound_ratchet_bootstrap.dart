import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:pinenacl/x25519.dart' as x25519;

import 'chat_models.dart';
import 'chat_service.dart';
import 'ratchet_models.dart';

const int _curveKeyBytes = 32;

class ChatSigningKeyPinViolation implements Exception {
  final String reason;
  const ChatSigningKeyPinViolation(this.reason);

  @override
  String toString() => 'ChatSigningKeyPinViolation($reason)';
}

class ChatSessionBootstrapViolation implements Exception {
  final String reason;
  const ChatSessionBootstrapViolation(this.reason);

  @override
  String toString() => 'ChatSessionBootstrapViolation($reason)';
}

class ChatOutboundSendContext {
  final ChatContact peer;
  final Uint8List sessionKey;
  final int keyId;
  final int prevKeyId;
  final String senderDhPubB64;

  const ChatOutboundSendContext({
    required this.peer,
    required this.sessionKey,
    required this.keyId,
    required this.prevKeyId,
    required this.senderDhPubB64,
  });
}

class ChatOutboundRatchetBootstrapper {
  final ChatService service;
  final ChatLocalStore store;

  const ChatOutboundRatchetBootstrapper({
    required this.service,
    required this.store,
  });

  Future<ChatOutboundSendContext> nextOutboundSendContext({
    required ChatIdentity me,
    required ChatContact peer,
  }) async {
    final preparedPeer = await _bootstrapPeerSessionIfNeeded(
      me: me,
      peer: peer,
    );
    final ratchet = await _loadOrCreateRatchet(
      me: me,
      peer: preparedPeer,
    );
    final next = shamellRatchetNextSendKey(ratchet);
    await store.saveRatchet(
      preparedPeer.id,
      ratchet.toJson(),
      baseUrlOverride: service.baseUrl,
    );
    return ChatOutboundSendContext(
      peer: preparedPeer,
      sessionKey: next.$1,
      keyId: next.$2,
      prevKeyId: next.$3,
      senderDhPubB64: next.$4,
    );
  }

  Future<ChatContact> _bootstrapPeerSessionIfNeeded({
    required ChatIdentity me,
    required ChatContact peer,
  }) async {
    final existing = await _loadRatchet(peer.id);
    if (existing != null && _isRatchetBoundToPeer(existing, peer)) return peer;
    if (existing != null) {
      final hydratedPeer = _contactWithRatchetIdentity(peer, existing);
      if (hydratedPeer != null) {
        await _persistPeer(hydratedPeer);
        return hydratedPeer;
      }
      await store.deleteRatchet(peer.id, baseUrlOverride: service.baseUrl);
    }
    if (!service.libsignalKeyApiEnabled) return peer;
    final pinnedSigningKey = (await store.loadPinnedIdentitySigningPubkey(
              peer.id,
              baseUrlOverride: service.baseUrl,
            ) ??
            '')
        .trim();

    try {
      final bundle = await service.fetchKeyBundle(
        targetDeviceId: peer.id,
        requesterDeviceId: me.id,
      );
      final signingKeyB64 = (bundle.identitySigningPubkeyB64 ?? '').trim();
      var hasPinnedSigningKey = pinnedSigningKey.isNotEmpty;
      final sameSigningKey = _sameSigningKeyMaterial(
        signingKeyB64,
        pinnedSigningKey,
      );
      if (hasPinnedSigningKey) {
        if (signingKeyB64.isEmpty || !sameSigningKey) {
          if (!peer.verified) {
            await _clearPeerSessionMaterial(
              peer.id,
            );
            hasPinnedSigningKey = false;
          } else {
            throw const ChatSigningKeyPinViolation(
              'identity signing key changed',
            );
          }
        }
      }
      if (!hasPinnedSigningKey && signingKeyB64.isEmpty) {
        throw const ChatSigningKeyPinViolation('identity signing key missing');
      }
      final identityKeyB64 = bundle.identityKeyB64.trim();
      if (identityKeyB64.isEmpty) {
        throw const ChatSessionBootstrapViolation('identity key missing');
      }
      final bundleFp = fingerprintForKey(identityKeyB64).trim();
      if (bundleFp.isEmpty) {
        throw const ChatSessionBootstrapViolation(
          'identity fingerprint missing',
        );
      }

      final keyChanged =
          identityKeyB64 != peer.publicKeyB64 || bundleFp != peer.fingerprint;
      final updatedPeer = keyChanged
          ? _contactWithUpdatedKey(peer, identityKeyB64, bundleFp)
          : peer;

      if (keyChanged) {
        await store.upsertContact(
          updatedPeer,
          baseUrlOverride: service.baseUrl,
        );
        final activePeer = await store.loadPeer(
          baseUrlOverride: service.baseUrl,
        );
        if (activePeer?.id == updatedPeer.id) {
          await store.savePeer(
            updatedPeer,
            baseUrlOverride: service.baseUrl,
          );
        }
      }

      await store.saveSessionBootstrapMeta(
        updatedPeer.id,
        protocolFloor: bundle.protocolFloor,
        signedPrekeyId: bundle.signedPrekeyId,
        oneTimePrekeyId: bundle.oneTimePrekeyId,
        v2Only: bundle.v2Only,
        identitySigningPubkeyB64: signingKeyB64,
        baseUrlOverride: service.baseUrl,
      );
      return updatedPeer;
    } on ChatSigningKeyPinViolation {
      rethrow;
    } on ChatHttpException {
      rethrow;
    } on ChatSessionBootstrapViolation {
      rethrow;
    } catch (e) {
      throw ChatSessionBootstrapViolation(e.toString());
    }
  }

  Future<void> _persistPeer(ChatContact peer) async {
    await store.upsertContact(
      peer,
      baseUrlOverride: service.baseUrl,
    );
    final activePeer = await store.loadPeer(
      baseUrlOverride: service.baseUrl,
    );
    if (activePeer?.id == peer.id) {
      await store.savePeer(
        peer,
        baseUrlOverride: service.baseUrl,
      );
    }
  }

  ChatContact? _contactWithRatchetIdentity(
    ChatContact peer,
    RatchetState state,
  ) {
    final existingPublicKey = peer.publicKeyB64.trim();
    final existingFingerprint = peer.fingerprint.trim();
    if (existingPublicKey.isNotEmpty || existingFingerprint.isNotEmpty) {
      return null;
    }
    final peerIdentity = state.peerIdentity.trim();
    final peerPublicKeyB64 = state.peerDhPubB64.trim();
    if (peerIdentity.isEmpty ||
        shamellDecodeCurveKeyB64(peerPublicKeyB64) == null) {
      return null;
    }
    return ChatContact(
      id: peer.id,
      publicKeyB64: peerPublicKeyB64,
      fingerprint: peerIdentity,
      name: peer.name,
      verified: peer.verified,
      verifiedAt: peer.verifiedAt,
      starred: peer.starred,
      pinned: peer.pinned,
      disappearing: peer.disappearing,
      disappearAfter: peer.disappearAfter,
      archived: peer.archived,
      hidden: peer.hidden,
      blocked: peer.blocked,
      blockedAt: peer.blockedAt,
      muted: peer.muted,
    );
  }

  Future<RatchetState?> _loadRatchet(String peerId) async {
    final raw = await store.loadRatchet(
      peerId,
      baseUrlOverride: service.baseUrl,
    );
    if (raw.isEmpty) return null;
    final map = <String, Object?>{};
    raw.forEach((k, v) {
      map[k] = v;
    });
    final st = RatchetState.fromJson(map);
    if (st != null && shamellIsValidRatchetState(st)) {
      return st;
    }
    await store.deleteRatchet(peerId, baseUrlOverride: service.baseUrl);
    return null;
  }

  Future<RatchetState> _loadOrCreateRatchet({
    required ChatIdentity me,
    required ChatContact peer,
  }) async {
    final existing = await _loadRatchet(peer.id);
    if (existing != null && _isRatchetBoundToPeer(existing, peer)) {
      return existing;
    }
    if (existing != null) {
      await store.deleteRatchet(peer.id, baseUrlOverride: service.baseUrl);
    }

    final peerPub = shamellDecodeCurveKeyB64(peer.publicKeyB64);
    if (peerPub == null) {
      throw const ChatSessionBootstrapViolation('peer identity key invalid');
    }
    final myIdentityPrivate = shamellDecodeCurveKeyB64(me.privateKeyB64);
    if (myIdentityPrivate == null) {
      throw const ChatSessionBootstrapViolation('identity private key invalid');
    }
    final dh = x25519.PrivateKey(myIdentityPrivate);
    final dhPub =
        shamellDecodeCurveKeyB64(me.publicKeyB64) ?? dh.publicKey.asTypedList;
    final shared = x25519.Box(
      myPrivateKey: dh,
      theirPublicKey: x25519.PublicKey(peerPub),
    ).sharedKey;
    final rk =
        Uint8List.fromList(crypto.sha256.convert(shared.asTypedList).bytes);
    return RatchetState(
      rootKey: rk,
      sendChainKey: rk,
      recvChainKey: rk,
      sendCount: 0,
      recvCount: 0,
      pn: 0,
      skipped: <String, String>{},
      peerIdentity: peer.fingerprint,
      dhPriv: dh.asTypedList,
      dhPub: Uint8List.fromList(dhPub),
      peerDhPub: peerPub,
      peerDhPubB64: base64Encode(peerPub),
    );
  }

  bool _isRatchetBoundToPeer(RatchetState st, ChatContact peer) {
    final storedPeerIdentity = st.peerIdentity.trim();
    final currentPeerFingerprint = peer.fingerprint.trim();
    if (storedPeerIdentity.isEmpty || currentPeerFingerprint.isEmpty) {
      return false;
    }
    return storedPeerIdentity == currentPeerFingerprint;
  }

  Future<void> _clearPeerSessionMaterial(String peerId) async {
    final pid = peerId.trim();
    if (pid.isEmpty) return;
    await store.deleteRatchet(pid, baseUrlOverride: service.baseUrl);
    await store.saveSessionKey(
      pid,
      '',
      baseUrlOverride: service.baseUrl,
    );
    await store.saveChain(
      pid,
      <String, Object>{},
      baseUrlOverride: service.baseUrl,
    );
    await store.deleteSessionBootstrapMeta(
      pid,
      baseUrlOverride: service.baseUrl,
    );
  }

  ChatContact _contactWithUpdatedKey(
    ChatContact base,
    String publicKeyB64,
    String fingerprint,
  ) {
    return ChatContact(
      id: base.id,
      publicKeyB64: publicKeyB64,
      fingerprint: fingerprint,
      name: base.name,
      verified: false,
      verifiedAt: null,
      starred: base.starred,
      pinned: base.pinned,
      disappearing: base.disappearing,
      disappearAfter: base.disappearAfter,
      archived: base.archived,
      hidden: base.hidden,
      blocked: base.blocked,
      blockedAt: base.blockedAt,
      muted: base.muted,
    );
  }

  bool _sameSigningKeyMaterial(String leftB64, String rightB64) {
    if (leftB64.isEmpty || rightB64.isEmpty) return false;
    try {
      final left = base64Decode(leftB64);
      final right = base64Decode(rightB64);
      if (left.length != right.length) return false;
      var diff = 0;
      for (var i = 0; i < left.length; i++) {
        diff |= left[i] ^ right[i];
      }
      return diff == 0;
    } catch (_) {
      return false;
    }
  }
}

bool shamellHasTrustedLocalPeerBootstrapState({
  required ChatContact peer,
  required String? pinnedIdentitySigningPubkeyB64,
}) {
  final publicKeyB64 = peer.publicKeyB64.trim();
  final fingerprint = peer.fingerprint.trim();
  final pinnedKey = (pinnedIdentitySigningPubkeyB64 ?? '').trim();
  if (publicKeyB64.isEmpty || fingerprint.isEmpty || pinnedKey.isEmpty) {
    return false;
  }
  if (shamellDecodeCurveKeyB64(publicKeyB64) == null ||
      shamellDecodeCurveKeyB64(pinnedKey) == null) {
    return false;
  }
  return fingerprintForKey(publicKeyB64).trim() == fingerprint;
}

@visibleForTesting
Uint8List? shamellDecodeCurveKeyB64(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return null;
  try {
    final decoded = base64Decode(value);
    if (decoded.length != _curveKeyBytes) return null;
    return decoded;
  } catch (_) {
    return null;
  }
}

@visibleForTesting
bool shamellIsValidRatchetState(RatchetState st) {
  final hasValidKeys = st.rootKey.length == _curveKeyBytes &&
      st.sendChainKey.length == _curveKeyBytes &&
      st.recvChainKey.length == _curveKeyBytes &&
      st.dhPriv.length == _curveKeyBytes &&
      st.dhPub.length == _curveKeyBytes &&
      st.peerDhPub.length == _curveKeyBytes;
  if (!hasValidKeys) return false;
  if (st.sendCount < 0 || st.recvCount < 0 || st.pn < 0) {
    return false;
  }
  for (final skipped in st.skipped.values) {
    if (shamellDecodeCurveKeyB64(skipped) == null) {
      return false;
    }
  }
  return true;
}

@visibleForTesting
(Uint8List, Uint8List) shamellRatchetKdfChain(Uint8List ck, int n) {
  final hmac = crypto.Hmac(crypto.sha256, ck);
  final mk = hmac.convert(utf8.encode('msg-$n')).bytes;
  final next = hmac.convert(utf8.encode('ck-$n')).bytes;
  return (Uint8List.fromList(mk), Uint8List.fromList(next));
}

@visibleForTesting
(Uint8List, int, int, String) shamellRatchetNextSendKey(RatchetState st) {
  final mk = shamellRatchetKdfChain(st.sendChainKey, st.sendCount);
  st.sendChainKey = mk.$2;
  final keyId = st.sendCount;
  final prev = st.sendCount - 1;
  st.sendCount += 1;
  return (mk.$1, keyId, prev >= 0 ? prev : 0, base64Encode(st.dhPub));
}
