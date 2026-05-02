import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart' as crypto;

Uint8List _kdfRoot(Uint8List rk, Uint8List dh) {
  final hmac = crypto.Hmac(crypto.sha256, rk);
  final combined = hmac.convert(dh).bytes;
  final k1 = crypto.sha256.convert([...combined, 0x01]).bytes;
  return Uint8List.fromList(k1);
}

void main() {
  test('kdfRoot produces deterministic length', () {
    final rk = Uint8List.fromList(List<int>.filled(32, 1));
    final dh = Uint8List.fromList(List<int>.filled(32, 2));
    final out = _kdfRoot(rk, dh);
    expect(out.length, 32);
    final out2 = _kdfRoot(rk, dh);
    expect(base64Encode(out), base64Encode(out2));
  });
}
