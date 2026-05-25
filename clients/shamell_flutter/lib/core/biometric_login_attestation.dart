import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'base_url.dart';
import 'hardware_attestation.dart';
import 'session_cookie_store.dart';

const String shamellBiometricLoginAttestationChallengeHeader =
    'X-SyrChat-Biometric-Login-Attestation-Challenge';
const String shamellBiometricLoginAttestationPlayIntegrityHeader =
    'X-SyrChat-Biometric-Login-Play-Integrity';
const String shamellBiometricLoginAttestationAppleDeviceCheckHeader =
    'X-SyrChat-Biometric-Login-Apple-DeviceCheck';
const Duration _biometricLoginAttestationChallengeTimeout =
    Duration(seconds: 12);

bool shamellAllowLegacyBiometricLoginAttestationChallengeFallback({
  bool isReleaseMode = kReleaseMode,
}) =>
    !isReleaseMode;

typedef BiometricLoginAttestationPlayIntegrityTokenProvider = Future<String?>
    Function({required String nonceB64});
typedef BiometricLoginAttestationAppleTokenProvider = Future<String?>
    Function();

@visibleForTesting
BiometricLoginAttestationPlayIntegrityTokenProvider
    shamellBiometricLoginAttestationPlayIntegrityTokenProvider =
    HardwareAttestation.tryGetPlayIntegrityToken;

@visibleForTesting
BiometricLoginAttestationAppleTokenProvider
    shamellBiometricLoginAttestationAppleTokenProvider =
    HardwareAttestation.tryGetAppleDeviceCheckTokenB64;

@visibleForTesting
void resetShamellBiometricLoginAttestationTestHooks() {
  shamellBiometricLoginAttestationPlayIntegrityTokenProvider =
      HardwareAttestation.tryGetPlayIntegrityToken;
  shamellBiometricLoginAttestationAppleTokenProvider =
      HardwareAttestation.tryGetAppleDeviceCheckTokenB64;
}

class BiometricLoginAttestationHttpFailure implements Exception {
  final int statusCode;
  final String rawBody;

  const BiometricLoginAttestationHttpFailure({
    required this.statusCode,
    required this.rawBody,
  });

  @override
  String toString() => 'biometric login attestation failed: $statusCode';
}

class BiometricLoginAttestationUnavailable implements Exception {
  final String detail;

  const BiometricLoginAttestationUnavailable(this.detail);

  @override
  String toString() => detail;
}

Uri? _biometricLoginAttestationChallengeUri(String baseUrl) {
  return secureApiChildUri(
    baseUrl: baseUrl,
    pathSegments: const <String>['auth', 'biometric', 'login', 'challenge'],
  );
}

Future<Map<String, String>> shamellBuildBiometricLoginAttestationHeaders({
  required String baseUrl,
  required String deviceId,
  required String biometricToken,
  required http.Client client,
  bool isReleaseMode = kReleaseMode,
}) async {
  final challengeUri = _biometricLoginAttestationChallengeUri(baseUrl);
  if (challengeUri == null) {
    throw StateError('Invalid server URL.');
  }

  final challengeHeaders = await shamellSessionHeadersForBaseUrl(
    baseUrl,
    json: true,
    includeSessionCookie: false,
  );
  final response = await client
      .post(
        challengeUri,
        headers: challengeHeaders,
        body: jsonEncode(<String, Object?>{
          'device_id': deviceId.trim(),
          'token': biometricToken.trim(),
        }),
      )
      .timeout(_biometricLoginAttestationChallengeTimeout);
  if (response.statusCode == 404) {
    if (!shamellAllowLegacyBiometricLoginAttestationChallengeFallback(
      isReleaseMode: isReleaseMode,
    )) {
      throw const BiometricLoginAttestationUnavailable(
        'device attestation unavailable',
      );
    }
    return const <String, String>{};
  }
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw BiometricLoginAttestationHttpFailure(
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
    throw const BiometricLoginAttestationUnavailable(
      'device attestation unavailable',
    );
  }

  String? iosToken;
  String? androidToken;
  if (providers.contains('google_play_integrity')) {
    androidToken =
        await shamellBiometricLoginAttestationPlayIntegrityTokenProvider(
      nonceB64: nonceB64,
    );
  }
  if (androidToken == null && providers.contains('apple_devicecheck')) {
    iosToken = await shamellBiometricLoginAttestationAppleTokenProvider();
  }
  if ((iosToken ?? '').trim().isEmpty && (androidToken ?? '').trim().isEmpty) {
    throw const BiometricLoginAttestationUnavailable(
      'device attestation unavailable',
    );
  }

  return <String, String>{
    shamellBiometricLoginAttestationChallengeHeader: challengeToken,
    if ((androidToken ?? '').trim().isNotEmpty)
      shamellBiometricLoginAttestationPlayIntegrityHeader: androidToken!.trim(),
    if ((iosToken ?? '').trim().isNotEmpty)
      shamellBiometricLoginAttestationAppleDeviceCheckHeader: iosToken!.trim(),
  };
}
