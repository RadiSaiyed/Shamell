import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'base_url.dart';
import 'hardware_attestation.dart';
import 'session_cookie_store.dart';

const String shamellBiometricEnrollAttestationChallengeHeader =
    'X-SyrChat-Biometric-Attestation-Challenge';
const String shamellBiometricEnrollAttestationPlayIntegrityHeader =
    'X-SyrChat-Biometric-Play-Integrity';
const String shamellBiometricEnrollAttestationAppleDeviceCheckHeader =
    'X-SyrChat-Biometric-Apple-DeviceCheck';
const Duration _biometricEnrollAttestationChallengeTimeout =
    Duration(seconds: 12);

bool shamellAllowLegacyBiometricEnrollAttestationChallengeFallback({
  bool isReleaseMode = kReleaseMode,
}) =>
    !isReleaseMode;

typedef BiometricEnrollAttestationPlayIntegrityTokenProvider = Future<String?>
    Function({required String nonceB64});
typedef BiometricEnrollAttestationAppleTokenProvider = Future<String?>
    Function();

@visibleForTesting
BiometricEnrollAttestationPlayIntegrityTokenProvider
    shamellBiometricEnrollAttestationPlayIntegrityTokenProvider =
    HardwareAttestation.tryGetPlayIntegrityToken;

@visibleForTesting
BiometricEnrollAttestationAppleTokenProvider
    shamellBiometricEnrollAttestationAppleTokenProvider =
    HardwareAttestation.tryGetAppleDeviceCheckTokenB64;

@visibleForTesting
void resetShamellBiometricEnrollAttestationTestHooks() {
  shamellBiometricEnrollAttestationPlayIntegrityTokenProvider =
      HardwareAttestation.tryGetPlayIntegrityToken;
  shamellBiometricEnrollAttestationAppleTokenProvider =
      HardwareAttestation.tryGetAppleDeviceCheckTokenB64;
}

class BiometricEnrollAttestationHttpFailure implements Exception {
  final int statusCode;
  final String rawBody;

  const BiometricEnrollAttestationHttpFailure({
    required this.statusCode,
    required this.rawBody,
  });

  @override
  String toString() => 'biometric enroll attestation failed: $statusCode';
}

class BiometricEnrollAttestationUnavailable implements Exception {
  final String detail;

  const BiometricEnrollAttestationUnavailable(this.detail);

  @override
  String toString() => detail;
}

Uri? _biometricEnrollAttestationChallengeUri(String baseUrl) {
  return secureApiChildUri(
    baseUrl: baseUrl,
    pathSegments: const <String>['auth', 'biometric', 'enroll', 'challenge'],
  );
}

Future<Map<String, String>> shamellBuildBiometricEnrollAttestationHeaders({
  required String baseUrl,
  required String deviceId,
  required http.Client client,
  bool isReleaseMode = kReleaseMode,
}) async {
  final challengeUri = _biometricEnrollAttestationChallengeUri(baseUrl);
  if (challengeUri == null) {
    throw StateError('Invalid server URL.');
  }

  final challengeHeaders =
      await shamellSessionHeadersForBaseUrl(baseUrl, json: true);
  final response = await client
      .post(
        challengeUri,
        headers: challengeHeaders,
        body: jsonEncode(<String, Object?>{
          'device_id': deviceId.trim(),
        }),
      )
      .timeout(_biometricEnrollAttestationChallengeTimeout);
  if (response.statusCode == 404) {
    if (!shamellAllowLegacyBiometricEnrollAttestationChallengeFallback(
      isReleaseMode: isReleaseMode,
    )) {
      throw const BiometricEnrollAttestationUnavailable(
        'device attestation unavailable',
      );
    }
    return const <String, String>{};
  }
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw BiometricEnrollAttestationHttpFailure(
      statusCode: response.statusCode,
      rawBody: response.body,
    );
  }

  final decoded = jsonDecode(response.body);
  final payload = decoded is Map
      ? Map<String, Object?>.from(decoded.cast<Object?, Object?>())
      : const <String, Object?>{};
  if (payload['enabled'] != true) {
    return const <String, String>{};
  }

  final challengeToken = (payload['challenge_token'] ?? '').toString().trim();
  final nonceB64 =
      (payload['hw_attestation_nonce_b64'] ?? '').toString().trim();
  final providers = <String>[
    if (payload['hw_attestation_providers'] is List)
      for (final entry in payload['hw_attestation_providers'] as List)
        entry.toString().trim(),
  ].where((entry) => entry.isNotEmpty).toSet();

  if (challengeToken.isEmpty || nonceB64.isEmpty || providers.isEmpty) {
    throw const BiometricEnrollAttestationUnavailable(
      'device attestation unavailable',
    );
  }

  String? iosToken;
  String? androidToken;
  if (providers.contains('google_play_integrity')) {
    androidToken =
        await shamellBiometricEnrollAttestationPlayIntegrityTokenProvider(
      nonceB64: nonceB64,
    );
  }
  if (androidToken == null && providers.contains('apple_devicecheck')) {
    iosToken = await shamellBiometricEnrollAttestationAppleTokenProvider();
  }
  if ((iosToken ?? '').trim().isEmpty && (androidToken ?? '').trim().isEmpty) {
    throw const BiometricEnrollAttestationUnavailable(
      'device attestation unavailable',
    );
  }

  return <String, String>{
    shamellBiometricEnrollAttestationChallengeHeader: challengeToken,
    if ((androidToken ?? '').trim().isNotEmpty)
      shamellBiometricEnrollAttestationPlayIntegrityHeader:
          androidToken!.trim(),
    if ((iosToken ?? '').trim().isNotEmpty)
      shamellBiometricEnrollAttestationAppleDeviceCheckHeader: iosToken!.trim(),
  };
}
