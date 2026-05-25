import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

const String _pbkdf2Prefix = 'pbkdf2_sha256';
const int _defaultPbkdf2Iterations = 120000;
const int _minPbkdf2Iterations = 10000;
const int _maxPbkdf2Iterations = 600000;
const int _saltLengthBytes = 16;
const int _derivedKeyLengthBytes = 32;

final Random _secureRandom = Random.secure();

String hashLocalPassword(
  String raw, {
  List<int>? salt,
  int iterations = _defaultPbkdf2Iterations,
}) {
  final normalized = raw.trim();
  final effectiveIterations = _normalizePbkdf2Iterations(iterations);
  final saltBytes = Uint8List.fromList(
    salt ??
        List<int>.generate(_saltLengthBytes, (_) => _secureRandom.nextInt(256)),
  );
  final derived = _pbkdf2HmacSha256(
    utf8.encode(normalized),
    saltBytes,
    effectiveIterations,
    _derivedKeyLengthBytes,
  );
  return [
    _pbkdf2Prefix,
    effectiveIterations.toString(),
    base64Url.encode(saltBytes),
    base64Url.encode(derived),
  ].join(r'$');
}

bool verifyLocalPassword(String raw, String stored) {
  final normalizedStored = stored.trim();
  if (normalizedStored.isEmpty) {
    return false;
  }

  final parsed = _parsePbkdf2Hash(normalizedStored);
  if (parsed != null) {
    final derived = _pbkdf2HmacSha256(
      utf8.encode(raw.trim()),
      parsed.salt,
      parsed.iterations,
      parsed.expected.length,
    );
    return _constantTimeEquals(derived, parsed.expected);
  }

  if (!_isLegacySha256Hash(normalizedStored)) {
    return false;
  }

  return _constantTimeEquals(
    utf8.encode(_legacySha256(raw.trim())),
    utf8.encode(normalizedStored.toLowerCase()),
  );
}

String? migrateLegacyPasswordHash(String raw, String stored) {
  final normalizedStored = stored.trim();
  if (_parsePbkdf2Hash(normalizedStored) != null) {
    return normalizedStored;
  }
  if (!_isLegacySha256Hash(normalizedStored)) {
    return null;
  }
  if (_legacySha256(raw.trim()) != normalizedStored.toLowerCase()) {
    return null;
  }
  return hashLocalPassword(raw);
}

bool isSupportedLocalPasswordHash(String stored) {
  final normalizedStored = stored.trim();
  if (normalizedStored.isEmpty) return false;
  if (_parsePbkdf2Hash(normalizedStored) != null) return true;
  return _isLegacySha256Hash(normalizedStored);
}

String _legacySha256(String raw) {
  final bytes = utf8.encode(raw);
  return crypto.sha256.convert(bytes).toString();
}

_ParsedPbkdf2Hash? _parsePbkdf2Hash(String raw) {
  final parts = raw.split(r'$');
  if (parts.length != 4 || parts.first != _pbkdf2Prefix) {
    return null;
  }

  final iterations = int.tryParse(parts[1]);
  if (iterations == null ||
      iterations < _minPbkdf2Iterations ||
      iterations > _maxPbkdf2Iterations) {
    return null;
  }

  try {
    final salt = base64Url.decode(parts[2]);
    final expected = base64Url.decode(parts[3]);
    if (salt.length < 8 || expected.isEmpty) {
      return null;
    }
    return _ParsedPbkdf2Hash(
      iterations: iterations,
      salt: Uint8List.fromList(salt),
      expected: Uint8List.fromList(expected),
    );
  } catch (_) {
    return null;
  }
}

int _normalizePbkdf2Iterations(int iterations) {
  if (iterations < _minPbkdf2Iterations) {
    return _minPbkdf2Iterations;
  }
  if (iterations > _maxPbkdf2Iterations) {
    return _maxPbkdf2Iterations;
  }
  return iterations;
}

bool _isLegacySha256Hash(String value) {
  final normalized = value.trim();
  if (normalized.length != 64) return false;
  final hex = RegExp(r'^[0-9a-fA-F]{64}$');
  return hex.hasMatch(normalized);
}

Uint8List _pbkdf2HmacSha256(
  List<int> password,
  List<int> salt,
  int iterations,
  int length,
) {
  final hmac = crypto.Hmac(crypto.sha256, password);
  const hashLength = 32;
  final blocks = (length / hashLength).ceil();
  final out = BytesBuilder(copy: false);

  for (var blockIndex = 1; blockIndex <= blocks; blockIndex++) {
    final block = BytesBuilder(copy: false)
      ..add(salt)
      ..add(<int>[
        (blockIndex >> 24) & 0xff,
        (blockIndex >> 16) & 0xff,
        (blockIndex >> 8) & 0xff,
        blockIndex & 0xff,
      ]);
    var u = Uint8List.fromList(hmac.convert(block.toBytes()).bytes);
    final t = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    out.add(t);
  }

  final bytes = out.toBytes();
  return Uint8List.sublistView(bytes, 0, length);
}

bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

class _ParsedPbkdf2Hash {
  final int iterations;
  final Uint8List salt;
  final Uint8List expected;

  const _ParsedPbkdf2Hash({
    required this.iterations,
    required this.salt,
    required this.expected,
  });
}
