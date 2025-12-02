import 'dart:convert';
import 'dart:typed_data';

class RatchetState {
  Uint8List rootKey;
  Uint8List sendChainKey;
  Uint8List recvChainKey;
  int sendCount;
  int recvCount;
  int pn; // previous recv count
  Map<String, String> skipped; // key: "$dhPub:$n" -> msgKey b64
  String peerIdentity;
  Uint8List dhPriv;
  Uint8List dhPub;
  Uint8List peerDhPub;
  String peerDhPubB64;
  int maxSkip;

  RatchetState({
    required this.rootKey,
    required this.sendChainKey,
    required this.recvChainKey,
    required this.sendCount,
    required this.recvCount,
    required this.pn,
    required this.skipped,
    required this.peerIdentity,
    required this.dhPriv,
    required this.dhPub,
    required this.peerDhPub,
    required this.peerDhPubB64,
    this.maxSkip = 50,
  });

  Map<String, Object> toJson() => {
        'rk': base64Encode(rootKey),
        'ck_s': base64Encode(sendChainKey),
        'ck_r': base64Encode(recvChainKey),
        'ns': sendCount,
        'nr': recvCount,
        'pn': pn,
        'skipped': skipped,
        'peer': peerIdentity,
        'dh_priv': base64Encode(dhPriv),
        'dh_pub': base64Encode(dhPub),
        'peer_dh': base64Encode(peerDhPub),
        'peer_dh_b64': peerDhPubB64,
        'max_skip': maxSkip,
      };

  static RatchetState? fromJson(Map<String, Object?> map) {
    try {
      return RatchetState(
        rootKey: base64Decode(map['rk'] as String),
        sendChainKey: base64Decode(map['ck_s'] as String),
        recvChainKey: base64Decode(map['ck_r'] as String),
        sendCount: (map['ns'] as num).toInt(),
        recvCount: (map['nr'] as num).toInt(),
        pn: (map['pn'] as num).toInt(),
        skipped: (map['skipped'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())),
        peerIdentity: map['peer'] as String,
        dhPriv: base64Decode(map['dh_priv'] as String),
        dhPub: base64Decode(map['dh_pub'] as String),
        peerDhPub: base64Decode(map['peer_dh'] as String),
        peerDhPubB64: map['peer_dh_b64'] as String? ?? '',
        maxSkip: (map['max_skip'] as num?)?.toInt() ?? 50,
      );
    } catch (_) {
      return null;
    }
  }
}
