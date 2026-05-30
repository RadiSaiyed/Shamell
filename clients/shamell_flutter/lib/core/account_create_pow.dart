import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';

@visibleForTesting
bool shamellHasLeadingZeroBits(List<int> bytes, int bits) {
  if (bits <= 0) return true;
  final full = bits ~/ 8;
  final rem = bits % 8;
  if (full > bytes.length) return false;
  for (var i = 0; i < full; i++) {
    if (bytes[i] != 0) return false;
  }
  if (rem == 0) return true;
  if (full >= bytes.length) return false;
  // Require the most-significant `rem` bits of the next byte to be zero.
  return (bytes[full] >> (8 - rem)) == 0;
}

/// Compute callback used for account-create PoW attestation.
///
/// Message schema:
/// - nonce: string
/// - device_id: string
/// - difficulty_bits: int (0..30)
/// - max_millis: int (optional)
/// - max_iters: int (optional)
String? shamellSolveAccountCreatePow(Map<String, Object?> message) {
  final nonce = (message['nonce'] ?? '').toString().trim();
  final deviceId = (message['device_id'] ?? '').toString().trim();
  final difficulty = int.tryParse((message['difficulty_bits'] ?? '').toString()) ?? -1;
  final maxMillis = int.tryParse((message['max_millis'] ?? '').toString()) ?? 15000;
  final maxIters = int.tryParse((message['max_iters'] ?? '').toString()) ?? 50000000;
  if (nonce.isEmpty || deviceId.isEmpty) return null;
  if (difficulty < 0 || difficulty > 30) return null;

  final prefix = '$nonce:$deviceId:';
  final sw = Stopwatch()..start();
  for (var i = 0; i < maxIters; i++) {
    if (sw.elapsedMilliseconds > maxMillis) return null;
    final digest = crypto.sha256.convert(utf8.encode('$prefix$i')).bytes;
    if (shamellHasLeadingZeroBits(digest, difficulty)) {
      return i.toString();
    }
  }
  return null;
}

