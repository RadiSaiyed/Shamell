import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/local_password_hash.dart';

void main() {
  test('pbkdf2 password hashes verify with the original password', () {
    final stored = hashLocalPassword(
      'correct horse battery staple',
      salt: List<int>.generate(16, (i) => i),
      iterations: 10000,
    );

    expect(
      verifyLocalPassword('correct horse battery staple', stored),
      isTrue,
    );
    expect(verifyLocalPassword('wrong password', stored), isFalse);
  });

  test('same password with different salts produces different hashes', () {
    final a = hashLocalPassword(
      'pass1234',
      salt: List<int>.filled(16, 1),
      iterations: 10000,
    );
    final b = hashLocalPassword(
      'pass1234',
      salt: List<int>.filled(16, 2),
      iterations: 10000,
    );

    expect(a, isNot(b));
  });

  test('legacy sha256 hashes remain verifiable and can be migrated', () {
    final legacy = crypto.sha256.convert('legacy-pass'.codeUnits).toString();

    expect(verifyLocalPassword('legacy-pass', legacy), isTrue);
    final migrated = migrateLegacyPasswordHash('legacy-pass', legacy);
    expect(migrated, isNotNull);
    expect(migrated, isNot(legacy));
    expect(verifyLocalPassword('legacy-pass', migrated!), isTrue);
    expect(verifyLocalPassword('wrong-pass', migrated), isFalse);
  });

  test('malformed stored hashes are rejected', () {
    expect(verifyLocalPassword('pass1234', 'pbkdf2_sha256\$oops'), isFalse);
    expect(verifyLocalPassword('pass1234', ''), isFalse);
  });

  test('pbkdf2 iteration bounds are enforced on verify', () {
    final valid = hashLocalPassword(
      'pass1234',
      salt: List<int>.generate(16, (i) => i),
      iterations: 10000,
    );
    final parts = valid.split(r'$');
    final outOfPolicy = '${parts[0]}\$9999999\$${parts[2]}\$${parts[3]}';

    expect(verifyLocalPassword('pass1234', outOfPolicy), isFalse);
    expect(isSupportedLocalPasswordHash(outOfPolicy), isFalse);
  });

  test('hashLocalPassword clamps caller-provided iteration count', () {
    final low = hashLocalPassword(
      'pass1234',
      salt: List<int>.filled(16, 3),
      iterations: 1,
    );
    final high = hashLocalPassword(
      'pass1234',
      salt: List<int>.filled(16, 4),
      iterations: 9999999,
    );

    expect(low.split(r'$')[1], '10000');
    expect(high.split(r'$')[1], '600000');
  });
}
