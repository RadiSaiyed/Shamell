import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'hardware_attestation_contract.dart';

@visibleForTesting
RuntimeCompromiseState parseRuntimeCompromiseState(Object? raw) {
  final map = raw is Map ? raw : const <Object?, Object?>{};
  final compromised = map['compromised'] == true;
  final signalsRaw = map['signals'];
  final signals = <String>[
    if (signalsRaw is List)
      for (final entry in signalsRaw) entry?.toString().trim() ?? '',
  ].where((entry) => entry.isNotEmpty).toList(growable: false);
  return RuntimeCompromiseState(
    compromised: compromised || signals.isNotEmpty,
    signals: signals,
  );
}

@visibleForTesting
RuntimeCompromiseState runtimeCompromiseCheckUnavailableState() =>
    const RuntimeCompromiseState(
      compromised: true,
      signals: <String>['runtime_compromise_check_unavailable'],
    );

@visibleForTesting
int? parseAndroidSdkInt(Object? raw) {
  final value = switch (raw) {
    int value => value,
    num value => value.toInt(),
    _ => 0,
  };
  return value > 0 ? value : null;
}

class HardwareAttestation {
  static const MethodChannel _ch =
      MethodChannel('shamell/hardware_attestation');

  static Future<bool> isRuntimeIntegrityFailClosed() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return false;
    }
    if (Platform.isAndroid) {
      try {
        final raw = await _ch.invokeMethod<Object?>(
          'runtime_integrity_fail_closed',
        );
        return raw == true;
      } catch (_) {
        return true;
      }
    }
    // iOS currently keeps runtime integrity fail-closed.
    return true;
  }

  static Future<RuntimeCompromiseState> getRuntimeCompromiseState() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return RuntimeCompromiseState.safe;
    }
    final failClosed = await isRuntimeIntegrityFailClosed();
    try {
      final raw = await _ch
          .invokeMapMethod<Object?, Object?>('runtime_compromise_state');
      final state = parseRuntimeCompromiseState(raw);
      if (!failClosed) return RuntimeCompromiseState.safe;
      return state;
    } catch (_) {
      if (!failClosed) return RuntimeCompromiseState.safe;
      return runtimeCompromiseCheckUnavailableState();
    }
  }

  static Future<String?> tryGetAppleDeviceCheckTokenB64() async {
    if (kIsWeb || !Platform.isIOS) return null;
    final runtimeState = await getRuntimeCompromiseState();
    if (runtimeState.compromised) return null;
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
    final runtimeState = await getRuntimeCompromiseState();
    if (runtimeState.compromised) return null;
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

  static Future<int?> tryGetAndroidSdkInt() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final raw = await _ch.invokeMethod<Object?>('android_sdk_int');
      return parseAndroidSdkInt(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> tryGetAndroidSecureId({
    bool? platformIsAndroid,
  }) async {
    if (kIsWeb || !(platformIsAndroid ?? Platform.isAndroid)) return null;
    try {
      final raw = await _ch.invokeMethod<String>('android_secure_id');
      final value = raw?.trim();
      if (value == null || value.isEmpty) return null;
      return value;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> isProbablyAndroidEmulator({
    bool? platformIsAndroid,
  }) async {
    if (kIsWeb || !(platformIsAndroid ?? Platform.isAndroid)) return false;
    try {
      final raw = await _ch.invokeMethod<Object?>('android_is_emulator');
      return raw == true;
    } catch (_) {
      return false;
    }
  }
}
