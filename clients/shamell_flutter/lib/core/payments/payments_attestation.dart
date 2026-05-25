import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../base_url.dart';
import '../hardware_attestation.dart';
import '../session_cookie_store.dart';

const String shamellPaymentAttestationChallengeHeader =
    'X-SyrChat-Payment-Attestation-Challenge';
const String shamellPaymentAttestationPlayIntegrityHeader =
    'X-SyrChat-Payment-Play-Integrity';
const String shamellPaymentAttestationAppleDeviceCheckHeader =
    'X-SyrChat-Payment-Apple-DeviceCheck';
const Duration _paymentAttestationChallengeTimeout = Duration(seconds: 12);
const String _maxI64ValueDecimal = '9223372036854775807';
const int _maxJsSafeIntegerValue = 9007199254740991;
const bool _allowLocalhostHttpInReleaseForPayments = bool.fromEnvironment(
  'ALLOW_LOCALHOST_HTTP_IN_RELEASE',
  defaultValue: false,
);
const bool _disablePaymentMutationDeviceAttestation = bool.fromEnvironment(
  'DISABLE_PAYMENT_MUTATION_DEVICE_ATTESTATION',
  defaultValue: false,
);

bool shamellAllowLegacyPaymentMutationAttestationChallengeFallback({
  bool isReleaseMode = kReleaseMode,
}) =>
    !isReleaseMode;

bool shamellAllowLocalhostQaPaymentAuthBypass(
  String baseUrl, {
  bool isReleaseMode = kReleaseMode,
  bool? allowLocalhostHttpInRelease,
}) {
  final uri = parseApiBaseUrl(baseUrl.trim());
  if (uri == null) return false;
  final isLocalhostHttp =
      uri.scheme.trim().toLowerCase() == 'http' && isLocalhostHost(uri.host);
  if (!isLocalhostHttp) return false;
  if (!isReleaseMode) return true;
  final allowLocalhost =
      allowLocalhostHttpInRelease ?? _allowLocalhostHttpInReleaseForPayments;
  return allowLocalhost;
}

typedef PaymentAttestationPlayIntegrityTokenProvider = Future<String?> Function(
    {required String nonceB64});
typedef PaymentAttestationAppleTokenProvider = Future<String?> Function();

@visibleForTesting
PaymentAttestationPlayIntegrityTokenProvider
    shamellPaymentAttestationPlayIntegrityTokenProvider =
    HardwareAttestation.tryGetPlayIntegrityToken;

@visibleForTesting
PaymentAttestationAppleTokenProvider
    shamellPaymentAttestationAppleTokenProvider =
    HardwareAttestation.tryGetAppleDeviceCheckTokenB64;

@visibleForTesting
void resetShamellPaymentAttestationTestHooks() {
  shamellPaymentAttestationPlayIntegrityTokenProvider =
      HardwareAttestation.tryGetPlayIntegrityToken;
  shamellPaymentAttestationAppleTokenProvider =
      HardwareAttestation.tryGetAppleDeviceCheckTokenB64;
}

class PaymentMutationAttestationHttpFailure implements Exception {
  final int statusCode;
  final String rawBody;

  const PaymentMutationAttestationHttpFailure({
    required this.statusCode,
    required this.rawBody,
  });

  @override
  String toString() => 'payment attestation failed: $statusCode';
}

class PaymentMutationAttestationUnavailable implements Exception {
  final String detail;

  const PaymentMutationAttestationUnavailable(this.detail);

  @override
  String toString() => detail;
}

int shamellPaymentAmountMajorToCents(double amountMajor) {
  if (!amountMajor.isFinite || amountMajor < 0) {
    throw const PaymentMutationAttestationUnavailable(
      'device attestation unavailable',
    );
  }
  final fixed = amountMajor.toStringAsFixed(2);
  if (!RegExp(r'^[0-9]+\.[0-9]{2}$').hasMatch(fixed)) {
    throw const PaymentMutationAttestationUnavailable(
      'device attestation unavailable',
    );
  }
  final parts = fixed.split('.');
  if (parts.length != 2) {
    throw const PaymentMutationAttestationUnavailable(
      'device attestation unavailable',
    );
  }
  final whole = int.tryParse(parts[0]);
  final frac = int.tryParse(parts[1]);
  if (whole == null || frac == null) {
    throw const PaymentMutationAttestationUnavailable(
      'device attestation unavailable',
    );
  }
  final wholeCents = whole * 100;
  final cents = wholeCents + frac;
  final maxCents =
      kIsWeb ? _maxJsSafeIntegerValue : int.parse(_maxI64ValueDecimal);
  if (cents < 0 || cents > maxCents) {
    throw const PaymentMutationAttestationUnavailable(
      'device attestation unavailable',
    );
  }
  return cents;
}

String _paymentAttestationComponent(String value) =>
    Uri.encodeQueryComponent(value.trim()).replaceAll('+', '%20');

String shamellPaymentCreateUserAttestationResourceId({
  required String accountId,
}) {
  return 'account_id=${_paymentAttestationComponent(accountId)}';
}

String shamellPaymentTopupAttestationResourceId({
  required String walletId,
  required int amountCents,
}) {
  return 'wallet_id=${_paymentAttestationComponent(walletId)}'
      '&amount_cents=$amountCents';
}

String shamellPaymentTransferAttestationResourceId({
  required String fromWalletId,
  required int amountCents,
  String? toWalletId,
  String? toAlias,
}) {
  final wallet = (toWalletId ?? '').trim();
  final alias = (toAlias ?? '').trim();
  if ((wallet.isEmpty && alias.isEmpty) ||
      (wallet.isNotEmpty && alias.isNotEmpty)) {
    throw const PaymentMutationAttestationUnavailable(
      'device attestation unavailable',
    );
  }
  final prefix = 'from_wallet_id=${_paymentAttestationComponent(fromWalletId)}';
  if (wallet.isNotEmpty) {
    return '$prefix&to_wallet_id=${_paymentAttestationComponent(wallet)}'
        '&amount_cents=$amountCents';
  }
  return '$prefix&to_alias=${_paymentAttestationComponent(alias)}'
      '&amount_cents=$amountCents';
}

String shamellPaymentRequestAcceptAttestationResourceId({
  required String requestId,
  required String toWalletId,
}) {
  return 'rid=${_paymentAttestationComponent(requestId)}'
      '&to_wallet_id=${_paymentAttestationComponent(toWalletId)}';
}

String shamellPaymentRequestCreateAttestationResourceId({
  required String fromWalletId,
  required int amountCents,
  String? toWalletId,
  String? toAlias,
}) {
  final wallet = (toWalletId ?? '').trim();
  final alias = (toAlias ?? '').trim();
  if ((wallet.isEmpty && alias.isEmpty) ||
      (wallet.isNotEmpty && alias.isNotEmpty)) {
    throw const PaymentMutationAttestationUnavailable(
      'device attestation unavailable',
    );
  }
  final prefix = 'from_wallet_id=${_paymentAttestationComponent(fromWalletId)}';
  if (wallet.isNotEmpty) {
    return '$prefix&to_wallet_id=${_paymentAttestationComponent(wallet)}'
        '&amount_cents=$amountCents';
  }
  return '$prefix&to_alias=${_paymentAttestationComponent(alias)}'
      '&amount_cents=$amountCents';
}

String shamellPaymentRequestCancelAttestationResourceId({
  required String requestId,
  required String fromWalletId,
}) {
  return 'rid=${_paymentAttestationComponent(requestId)}'
      '&from_wallet_id=${_paymentAttestationComponent(fromWalletId)}';
}

String shamellPaymentFavoriteCreateAttestationResourceId({
  required String ownerWalletId,
  required String favoriteWalletId,
  String? alias,
}) {
  final normalizedAlias = (alias ?? '').trim();
  var resourceId =
      'owner_wallet_id=${_paymentAttestationComponent(ownerWalletId)}'
      '&favorite_wallet_id=${_paymentAttestationComponent(favoriteWalletId)}';
  if (normalizedAlias.isNotEmpty) {
    resourceId += '&alias=${_paymentAttestationComponent(normalizedAlias)}';
  }
  return resourceId;
}

String shamellPaymentFavoriteDeleteAttestationResourceId({
  required String favoriteId,
  required String ownerWalletId,
}) {
  return 'fid=${_paymentAttestationComponent(favoriteId)}'
      '&owner_wallet_id=${_paymentAttestationComponent(ownerWalletId)}';
}

Uri? _paymentAttestationChallengeUri(String baseUrl) {
  return secureApiChildUri(
    baseUrl: baseUrl,
    pathSegments: const <String>['auth', 'payment_attestation', 'challenge'],
  );
}

Future<Map<String, String>> shamellBuildPaymentMutationAttestationHeaders({
  required String baseUrl,
  required String deviceId,
  required String operation,
  required String resourceId,
  required http.Client client,
  bool isReleaseMode = kReleaseMode,
  bool? allowLocalhostHttpInRelease,
  bool? disableDeviceAttestation,
}) async {
  if (disableDeviceAttestation ?? _disablePaymentMutationDeviceAttestation) {
    return const <String, String>{};
  }
  if (shamellAllowLocalhostQaPaymentAuthBypass(
    baseUrl,
    isReleaseMode: isReleaseMode,
    allowLocalhostHttpInRelease: allowLocalhostHttpInRelease,
  )) {
    return const <String, String>{};
  }
  final challengeUri = _paymentAttestationChallengeUri(baseUrl);
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
          'operation': operation,
          'resource_id': resourceId,
        }),
      )
      .timeout(_paymentAttestationChallengeTimeout);
  if (response.statusCode == 404) {
    if (!shamellAllowLegacyPaymentMutationAttestationChallengeFallback(
      isReleaseMode: isReleaseMode,
    )) {
      throw const PaymentMutationAttestationUnavailable(
        'device attestation unavailable',
      );
    }
    return const <String, String>{};
  }
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw PaymentMutationAttestationHttpFailure(
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
    throw const PaymentMutationAttestationUnavailable(
      'device attestation unavailable',
    );
  }

  String? iosToken;
  String? androidToken;
  if (providers.contains('google_play_integrity')) {
    androidToken = await shamellPaymentAttestationPlayIntegrityTokenProvider(
      nonceB64: nonceB64,
    );
  }
  if (androidToken == null && providers.contains('apple_devicecheck')) {
    iosToken = await shamellPaymentAttestationAppleTokenProvider();
  }
  if ((iosToken ?? '').trim().isEmpty && (androidToken ?? '').trim().isEmpty) {
    throw const PaymentMutationAttestationUnavailable(
      'device attestation unavailable',
    );
  }

  return <String, String>{
    shamellPaymentAttestationChallengeHeader: challengeToken,
    if ((androidToken ?? '').trim().isNotEmpty)
      shamellPaymentAttestationPlayIntegrityHeader: androidToken!.trim(),
    if ((iosToken ?? '').trim().isNotEmpty)
      shamellPaymentAttestationAppleDeviceCheckHeader: iosToken!.trim(),
  };
}
