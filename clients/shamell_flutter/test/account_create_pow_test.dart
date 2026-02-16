import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/account_create_pow.dart';

void main() {
  test('shamellSolveAccountCreatePow finds a solution for low difficulty', () {
    const nonce = 'abcd1234';
    const deviceId = 'dev_1234';
    final sol = shamellSolveAccountCreatePow(<String, Object?>{
      'nonce': nonce,
      'device_id': deviceId,
      'difficulty_bits': 4,
      'max_millis': 5000,
      'max_iters': 500000,
    });
    expect(sol, isNotNull);
    final digest = crypto.sha256.convert(utf8.encode('$nonce:$deviceId:${sol!}')).bytes;
    expect(shamellHasLeadingZeroBits(digest, 4), isTrue);
  });

  test('shamellSolveAccountCreatePow rejects invalid inputs', () {
    expect(
      shamellSolveAccountCreatePow(<String, Object?>{
        'nonce': '',
        'device_id': 'dev',
        'difficulty_bits': 0,
      }),
      isNull,
    );
    expect(
      shamellSolveAccountCreatePow(<String, Object?>{
        'nonce': 'n',
        'device_id': '',
        'difficulty_bits': 0,
      }),
      isNull,
    );
    expect(
      shamellSolveAccountCreatePow(<String, Object?>{
        'nonce': 'n',
        'device_id': 'dev',
        'difficulty_bits': 31,
      }),
      isNull,
    );
  });
}

