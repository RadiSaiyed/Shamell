import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class HardwareAttestation {
  static const MethodChannel _ch =
      MethodChannel('shamell/hardware_attestation');

  static Future<String?> tryGetAppleDeviceCheckTokenB64() async {
    if (kIsWeb || !Platform.isIOS) return null;
    try {
      final tok = await _ch.invokeMethod<String>('devicecheck_token');
      final v = tok?.trim();
      if (v == null || v.isEmpty) return null;
      return v;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> tryGetPlayIntegrityToken({
    required String nonceB64,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return null;
    final n = nonceB64.trim();
    if (n.isEmpty) return null;
    try {
      final tok = await _ch.invokeMethod<String>('play_integrity_token', {
        'nonce_b64': n,
      });
      final v = tok?.trim();
      if (v == null || v.isEmpty) return null;
      return v;
    } catch (_) {
      return null;
    }
  }
}

