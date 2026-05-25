import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/outbound_ratchet_bootstrap.dart';
import 'package:shamell_flutter/core/chat/ratchet_models.dart';

void main() {
  test('decode curve key accepts only 32-byte keys', () {
    final valid = base64Encode(Uint8List.fromList(List<int>.filled(32, 7)));
    final invalid = base64Encode(Uint8List.fromList(List<int>.filled(31, 7)));

    expect(shamellDecodeCurveKeyB64(valid), isNotNull);
    expect(shamellDecodeCurveKeyB64(invalid), isNull);
    expect(shamellDecodeCurveKeyB64('not-base64'), isNull);
  });

  test('ratchet state validation rejects malformed skipped keys', () {
    final valid = _sampleRatchetState();
    expect(shamellIsValidRatchetState(valid), isTrue);

    valid.skipped['peer:1'] = 'not-base64';
    expect(shamellIsValidRatchetState(valid), isFalse);
  });

  test('next send key advances send counter and key ids', () {
    final st = _sampleRatchetState();

    final first = shamellRatchetNextSendKey(st);
    expect(first.$1.length, 32);
    expect(first.$2, 0);
    expect(first.$3, 0);
    expect(base64Decode(first.$4).length, 32);
    expect(st.sendCount, 1);

    final second = shamellRatchetNextSendKey(st);
    expect(second.$1.length, 32);
    expect(second.$2, 1);
    expect(second.$3, 0);
    expect(st.sendCount, 2);
    expect(base64Encode(first.$1), isNot(base64Encode(second.$1)));
  });
}

RatchetState _sampleRatchetState() {
  final root = Uint8List.fromList(List<int>.filled(32, 1));
  final send = Uint8List.fromList(List<int>.filled(32, 2));
  final recv = Uint8List.fromList(List<int>.filled(32, 3));
  final dhPriv = Uint8List.fromList(List<int>.filled(32, 4));
  final dhPub = Uint8List.fromList(List<int>.filled(32, 5));
  final peerDh = Uint8List.fromList(List<int>.filled(32, 6));
  return RatchetState(
    rootKey: root,
    sendChainKey: send,
    recvChainKey: recv,
    sendCount: 0,
    recvCount: 0,
    pn: 0,
    skipped: <String, String>{},
    peerIdentity: 'peer-fp',
    dhPriv: dhPriv,
    dhPub: dhPub,
    peerDhPub: peerDh,
    peerDhPubB64: base64Encode(peerDh),
  );
}
