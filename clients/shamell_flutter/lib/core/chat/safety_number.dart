import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

const int shamellSafetyNumberDefaultIterations = 5200;

class _IdentityRef {
  final String id;
  final Uint8List key;
  const _IdentityRef(this.id, this.key);
}

Uint8List _sha512(Uint8List data) {
  final d = crypto.sha512.convert(data).bytes;
  return Uint8List.fromList(d);
}

Uint8List _iterateHash({
  required Uint8List data,
  required Uint8List key,
  required int count,
}) {
  // First round: sha512(data || key)
  var combined = Uint8List(data.length + key.length);
  combined.setAll(0, data);
  combined.setAll(data.length, key);
  var result = _sha512(combined);

  // Subsequent rounds: sha512(prev || key)
  for (var i = 1; i < count; i++) {
    combined = Uint8List(result.length + key.length);
    combined.setAll(0, result);
    combined.setAll(result.length, key);
    result = _sha512(combined);
  }
  return result;
}

String _encodedChunk(Uint8List hash, int offset) {
  final chunk = (hash[offset] << 32) +
      (hash[offset + 1] << 24) +
      (hash[offset + 2] << 16) +
      (hash[offset + 3] << 8) +
      hash[offset + 4];
  final v = chunk % 100000;
  return v.toString().padLeft(5, '0');
}

String _displayStringFor({
  required String identifier,
  required Uint8List identityKey,
  required int iterations,
}) {
  const version = 0; // u16 little-endian
  final idBytes = utf8.encode(identifier);
  final bytes = Uint8List(2 + identityKey.length + idBytes.length);
  bytes[0] = version & 0xff;
  bytes[1] = (version >> 8) & 0xff;
  bytes.setAll(2, identityKey);
  bytes.setAll(2 + identityKey.length, idBytes);

  final out = _iterateHash(data: bytes, key: identityKey, count: iterations);
  return _encodedChunk(out, 0) +
      _encodedChunk(out, 5) +
      _encodedChunk(out, 10) +
      _encodedChunk(out, 15) +
      _encodedChunk(out, 20) +
      _encodedChunk(out, 25);
}

bool _bytesLe(Uint8List a, Uint8List b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    final ai = a[i];
    final bi = b[i];
    if (ai < bi) return true;
    if (ai > bi) return false;
  }
  return a.length <= b.length;
}

(_IdentityRef, _IdentityRef) _canonicalPair(
  String aId,
  Uint8List aKey,
  String bId,
  Uint8List bKey,
) {
  final c = aId.compareTo(bId);
  if (c < 0) return (_IdentityRef(aId, aKey), _IdentityRef(bId, bKey));
  if (c > 0) return (_IdentityRef(bId, bKey), _IdentityRef(aId, aKey));
  return _bytesLe(aKey, bKey)
      ? (_IdentityRef(aId, aKey), _IdentityRef(bId, bKey))
      : (_IdentityRef(bId, bKey), _IdentityRef(aId, aKey));
}

/// Computes a deterministic, symmetric, Signal-style "safety number" for two identities.
///
/// Output:
/// - 60 digits (two 30-digit halves), always numeric.
/// - Symmetric: (A,B) == (B,A).
String shamellSafetyNumber({
  required String localIdentifier,
  required Uint8List localIdentityKey,
  required String remoteIdentifier,
  required Uint8List remoteIdentityKey,
  int iterations = shamellSafetyNumberDefaultIterations,
}) {
  final aId = localIdentifier.trim();
  final bId = remoteIdentifier.trim();
  if (aId.isEmpty || bId.isEmpty) {
    throw ArgumentError('empty identifier');
  }
  if (iterations <= 0) {
    throw ArgumentError('iterations must be > 0');
  }
  if (localIdentityKey.isEmpty || remoteIdentityKey.isEmpty) {
    throw ArgumentError('empty identity key');
  }

  final (a, b) = _canonicalPair(aId, localIdentityKey, bId, remoteIdentityKey);
  final aFp = _displayStringFor(
    identifier: a.id,
    identityKey: a.key,
    iterations: iterations,
  );
  final bFp = _displayStringFor(
    identifier: b.id,
    identityKey: b.key,
    iterations: iterations,
  );
  return '$aFp$bFp';
}

