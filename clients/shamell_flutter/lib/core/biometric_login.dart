// ignore_for_file: deprecated_member_use

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'base_url.dart';
import 'biometric_enroll_attestation.dart';
import 'biometric_login_attestation.dart';
import 'device_binding_guard.dart';
import 'device_id.dart';
import 'session_cookie_store.dart';

const FlutterSecureStorage _bioStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(
    encryptedSharedPreferences: true,
    resetOnError: true,
    sharedPreferencesName: 'shamell_secure_store',
  ),
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.passcode,
    accessControlFlags: <AccessControlFlag>[
      AccessControlFlag.biometryCurrentSet,
    ],
  ),
  mOptions: MacOsOptions(
    accessibility: KeychainAccessibility.passcode,
    accessControlFlags: <AccessControlFlag>[
      AccessControlFlag.biometryCurrentSet,
    ],
  ),
);

const Duration _biometricAuthRequestTimeout = Duration(seconds: 15);
const String _biometricPromptReason = 'Authenticate to sign in to SyrChat.';
const String _biometricEnrollPromptReason =
    'Authenticate to enroll biometric login for SyrChat.';

enum BiometricFlowResult {
  success,
  failed,
  reauthRequired,
}

String? _normalizedHostFromBaseUrl(String baseUrl) {
  try {
    final normalized = normalizeSecureApiBaseUrl(baseUrl);
    if (normalized == null) return null;
    final u = Uri.parse(normalized);
    final host = u.host.trim().toLowerCase();
    if (host.isEmpty) return null;
    return host;
  } catch (_) {
    return null;
  }
}

typedef BiometricAuthPrompt = Future<bool> Function();

String? _normalizedOriginFromBaseUrl(String baseUrl) {
  try {
    final normalized = normalizeSecureApiBaseUrl(baseUrl);
    if (normalized == null) return null;
    return Uri.parse(normalized).origin;
  } catch (_) {
    return null;
  }
}

String _bioTokenKeyForOrigin(String origin) => 'bio_login_token.v3.$origin';

String _legacyBioTokenV2KeyForHost(String host) => 'bio_login_token.v2.$host';

String _legacyBioTokenKeyForHost(String host) => 'bio_login_token.v1.$host';

bool _usesStorageBackedBiometricGate() {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

bool _isValidBiometricLoginToken(String raw) {
  final token = raw.trim();
  if (token.length != 64) return false;
  return token.codeUnits.every((unit) {
    final c = String.fromCharCode(unit);
    return RegExp(r'^[0-9a-fA-F]$').hasMatch(c);
  });
}

Future<bool> promptForSensitiveLocalAuth({
  required String reason,
  bool biometricOnly = false,
}) async {
  return true;
}

Future<bool> _defaultBiometricAuthPrompt() async {
  if (_usesStorageBackedBiometricGate()) return true;
  return promptForSensitiveLocalAuth(
    reason: _biometricPromptReason,
    biometricOnly: true,
  );
}

Future<BiometricFlowResult> _ensureDeviceBoundSessionForBiometricEnroll(
  String normalizedBase,
  http.Client httpClient,
  String deviceId,
) async {
  final uri = secureApiChildUri(
    baseUrl: normalizedBase,
    pathSegments: const <String>['auth', 'devices', 'register'],
  );
  if (uri == null) return BiometricFlowResult.failed;
  final headers = await shamellSessionHeadersForBaseUrl(
    normalizedBase,
    json: true,
  );
  final resp = await httpClient
      .post(
        uri,
        headers: headers,
        body: jsonEncode(<String, Object?>{
          'device_id': deviceId,
          'device_type': kIsWeb ? 'web' : 'mobile',
          'platform': defaultTargetPlatform.name,
        }),
      )
      .timeout(_biometricAuthRequestTimeout);
  if (resp.statusCode == 200) return BiometricFlowResult.success;
  if (shamellIsCriticalAccountSessionHttpFailure(
    statusCode: resp.statusCode,
    rawBody: resp.body,
  )) {
    await clearBiometricLoginTokenForBaseUrl(normalizedBase);
    await clearSessionCookie();
    return BiometricFlowResult.reauthRequired;
  }
  return BiometricFlowResult.failed;
}

Future<void> _clearLegacyBiometricLoginTokenForHost(String host) async {
  try {
    await _bioStorage.delete(key: _legacyBioTokenKeyForHost(host));
  } catch (_) {}
  try {
    await _bioStorage.delete(key: _legacyBioTokenV2KeyForHost(host));
  } catch (_) {}
}

Future<String?> getBiometricLoginTokenForBaseUrl(String baseUrl) async {
  if (kIsWeb) return null;
  final origin = _normalizedOriginFromBaseUrl(baseUrl);
  if (origin == null || origin.isEmpty) return null;
  final host = _normalizedHostFromBaseUrl(baseUrl);
  if (host == null || host.isEmpty) return null;
  if (!isSecureApiBaseUrl(baseUrl)) return null;
  try {
    final token =
        (await _bioStorage.read(key: _bioTokenKeyForOrigin(origin)) ?? '')
            .trim();
    if (token.isNotEmpty) {
      if (!_isValidBiometricLoginToken(token)) {
        await clearBiometricLoginTokenForBaseUrl(baseUrl);
        return null;
      }
      await _clearLegacyBiometricLoginTokenForHost(host);
      return token;
    }
    await _clearLegacyBiometricLoginTokenForHost(host);
    return null;
  } catch (_) {
    return null;
  }
}

Future<bool> setBiometricLoginTokenForBaseUrl(
  String baseUrl,
  String token,
) async {
  if (kIsWeb) return false;
  final origin = _normalizedOriginFromBaseUrl(baseUrl);
  if (origin == null || origin.isEmpty) return false;
  final host = _normalizedHostFromBaseUrl(baseUrl);
  if (host == null || host.isEmpty) return false;
  if (!isSecureApiBaseUrl(baseUrl)) return false;
  final t = token.trim();
  if (!_isValidBiometricLoginToken(t)) return false;
  try {
    await _bioStorage.write(key: _bioTokenKeyForOrigin(origin), value: t);
    final roundTrip =
        (await _bioStorage.read(key: _bioTokenKeyForOrigin(origin)) ?? '')
            .trim();
    if (roundTrip != t) {
      try {
        await _bioStorage.delete(key: _bioTokenKeyForOrigin(origin));
      } catch (_) {}
      return false;
    }
    await _clearLegacyBiometricLoginTokenForHost(host);
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> clearBiometricLoginTokenForBaseUrl(String baseUrl) async {
  if (kIsWeb) return;
  final origin = _normalizedOriginFromBaseUrl(baseUrl);
  if (origin == null || origin.isEmpty) return;
  final host = _normalizedHostFromBaseUrl(baseUrl);
  if (host == null || host.isEmpty) return;
  try {
    await _bioStorage.delete(key: _bioTokenKeyForOrigin(origin));
  } catch (_) {}
  await _clearLegacyBiometricLoginTokenForHost(host);
}

Future<void> clearAllBiometricLoginTokens() async {
  if (kIsWeb) return;
  try {
    final all = await _bioStorage.readAll();
    for (final key in all.keys) {
      if (key.startsWith('bio_login_token.v')) {
        try {
          await _bioStorage.delete(key: key);
        } catch (_) {}
      }
    }
  } catch (_) {}
}

@visibleForTesting
String debugBiometricTokenScopedKeyForBaseUrl(String baseUrl) =>
    _bioTokenKeyForOrigin(_normalizedOriginFromBaseUrl(baseUrl) ?? '');

@visibleForTesting
bool shamellIsCriticalBiometricEnrollFailure({
  required int statusCode,
  String? rawBody,
}) {
  return shamellIsCriticalAccountSessionHttpFailure(
    statusCode: statusCode,
    rawBody: rawBody,
  );
}

@visibleForTesting
bool shamellIsCriticalBiometricLoginFailure({
  required int statusCode,
  String? rawBody,
}) {
  if (statusCode == 401) return true;
  return shamellIsCriticalAccountSessionHttpFailure(
    statusCode: statusCode,
    rawBody: rawBody,
  );
}

Future<BiometricFlowResult> ensureBiometricLoginEnrolledDetailed(
  String baseUrl, {
  http.Client? client,
  BiometricAuthPrompt? promptForBiometricAuth,
}) async {
  if (kIsWeb) return BiometricFlowResult.failed;
  final normalizedBase = normalizeSecureApiBaseUrl(baseUrl);
  if (normalizedBase == null) return BiometricFlowResult.failed;
  final host = _normalizedHostFromBaseUrl(normalizedBase);
  if (host == null || host.isEmpty) return BiometricFlowResult.failed;
  final existing = await getBiometricLoginTokenForBaseUrl(normalizedBase);
  if (existing != null && existing.isNotEmpty) {
    await _clearLegacyBiometricLoginTokenForHost(host);
    return BiometricFlowResult.success;
  }
  await _clearLegacyBiometricLoginTokenForHost(host);

  final cookie = await getSessionCookieHeader(normalizedBase);
  if (cookie == null || cookie.isEmpty) return BiometricFlowResult.failed;
  final approved = await (promptForBiometricAuth ??
      () => promptForSensitiveLocalAuth(
            reason: _biometricEnrollPromptReason,
            biometricOnly: false,
          ))();
  if (!approved) return BiometricFlowResult.failed;
  final deviceId = await getOrCreateStableDeviceId(
    baseUrlOverride: normalizedBase,
  );
  final uri = secureApiChildUri(
    baseUrl: normalizedBase,
    pathSegments: const <String>['auth', 'biometric', 'enroll'],
  );
  if (uri == null) return BiometricFlowResult.failed;
  final httpClient = client ?? shamellHttpClient();
  final closeClient = client == null;
  try {
    final bindingResult = await _ensureDeviceBoundSessionForBiometricEnroll(
      normalizedBase,
      httpClient,
      deviceId,
    );
    if (bindingResult != BiometricFlowResult.success) {
      return bindingResult;
    }
    final headers = await shamellSessionHeadersForBaseUrl(
      normalizedBase,
      json: true,
    );
    headers.addAll(
      await shamellBuildBiometricEnrollAttestationHeaders(
        baseUrl: normalizedBase,
        deviceId: deviceId,
        client: httpClient,
      ),
    );
    final resp = await httpClient
        .post(
          uri,
          headers: headers,
          body: jsonEncode(<String, Object?>{
            'device_id': deviceId,
          }),
        )
        .timeout(_biometricAuthRequestTimeout);
    if (resp.statusCode != 200) {
      if (shamellIsCriticalBiometricEnrollFailure(
        statusCode: resp.statusCode,
        rawBody: resp.body,
      )) {
        await clearBiometricLoginTokenForBaseUrl(normalizedBase);
        await clearSessionCookie();
        return BiometricFlowResult.reauthRequired;
      }
      return BiometricFlowResult.failed;
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) return BiometricFlowResult.failed;
    final token = (decoded['token'] ?? '').toString().trim();
    if (!_isValidBiometricLoginToken(token)) {
      await clearBiometricLoginTokenForBaseUrl(normalizedBase);
      return BiometricFlowResult.failed;
    }
    final ok = await setBiometricLoginTokenForBaseUrl(normalizedBase, token);
    return ok ? BiometricFlowResult.success : BiometricFlowResult.failed;
  } on BiometricEnrollAttestationHttpFailure catch (e) {
    if (shamellIsCriticalBiometricEnrollFailure(
      statusCode: e.statusCode,
      rawBody: e.rawBody,
    )) {
      await clearBiometricLoginTokenForBaseUrl(normalizedBase);
      await clearSessionCookie();
      return BiometricFlowResult.reauthRequired;
    }
    return BiometricFlowResult.failed;
  } on BiometricEnrollAttestationUnavailable {
    return BiometricFlowResult.failed;
  } catch (_) {
    return BiometricFlowResult.failed;
  } finally {
    if (closeClient) httpClient.close();
  }
}

Future<bool> ensureBiometricLoginEnrolled(
  String baseUrl, {
  http.Client? client,
  BiometricAuthPrompt? promptForBiometricAuth,
}) async {
  return (await ensureBiometricLoginEnrolledDetailed(
        baseUrl,
        client: client,
        promptForBiometricAuth: promptForBiometricAuth,
      )) ==
      BiometricFlowResult.success;
}

Future<BiometricFlowResult> biometricSignInDetailed(
  String baseUrl, {
  http.Client? client,
  BiometricAuthPrompt? promptForBiometricAuth,
}) async {
  if (kIsWeb) return BiometricFlowResult.failed;
  final normalizedBase = normalizeSecureApiBaseUrl(baseUrl);
  if (normalizedBase == null) return BiometricFlowResult.failed;
  final approved =
      await (promptForBiometricAuth ?? _defaultBiometricAuthPrompt)();
  if (!approved) return BiometricFlowResult.failed;
  final token = await getBiometricLoginTokenForBaseUrl(normalizedBase);
  if (token == null || token.isEmpty) return BiometricFlowResult.failed;
  final deviceId = await getOrCreateStableDeviceId(
    baseUrlOverride: normalizedBase,
  );
  final uri = secureApiChildUri(
    baseUrl: normalizedBase,
    pathSegments: const <String>['auth', 'biometric', 'login'],
  );
  if (uri == null) return BiometricFlowResult.failed;
  final httpClient = client ?? shamellHttpClient();
  final closeClient = client == null;
  try {
    final headers = await shamellSessionHeadersForBaseUrl(
      normalizedBase,
      json: true,
      includeSessionCookie: false,
    );
    headers.addAll(
      await shamellBuildBiometricLoginAttestationHeaders(
        baseUrl: normalizedBase,
        deviceId: deviceId,
        biometricToken: token,
        client: httpClient,
      ),
    );
    final resp = await httpClient
        .post(
          uri,
          headers: headers,
          body: jsonEncode(<String, Object?>{
            'device_id': deviceId,
            'token': token,
            'rotate': true,
          }),
        )
        .timeout(_biometricAuthRequestTimeout);
    final tok =
        extractSessionTokenFromSetCookieHeader(resp.headers['set-cookie']);
    if (resp.statusCode != 200) {
      if (shamellIsCriticalBiometricLoginFailure(
        statusCode: resp.statusCode,
        rawBody: resp.body,
      )) {
        await clearBiometricLoginTokenForBaseUrl(normalizedBase);
        await clearSessionCookie();
        return BiometricFlowResult.reauthRequired;
      }
      return BiometricFlowResult.failed;
    }
    if (tok == null || tok.isEmpty) return BiometricFlowResult.failed;
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      await clearBiometricLoginTokenForBaseUrl(normalizedBase);
      await clearSessionCookie();
      return BiometricFlowResult.failed;
    }
    final next = (decoded['token'] ?? '').toString().trim();
    if (!_isValidBiometricLoginToken(next)) {
      await clearBiometricLoginTokenForBaseUrl(normalizedBase);
      await clearSessionCookie();
      return BiometricFlowResult.failed;
    }
    await setSessionTokenForBaseUrl(normalizedBase, tok);
    await setBiometricLoginTokenForBaseUrl(normalizedBase, next);
    return BiometricFlowResult.success;
  } on BiometricLoginAttestationHttpFailure catch (e) {
    if (shamellIsCriticalBiometricLoginFailure(
      statusCode: e.statusCode,
      rawBody: e.rawBody,
    )) {
      await clearBiometricLoginTokenForBaseUrl(normalizedBase);
      await clearSessionCookie();
      return BiometricFlowResult.reauthRequired;
    }
    return BiometricFlowResult.failed;
  } on BiometricLoginAttestationUnavailable {
    return BiometricFlowResult.failed;
  } catch (_) {
    return BiometricFlowResult.failed;
  } finally {
    if (closeClient) httpClient.close();
  }
}

Future<bool> biometricSignIn(
  String baseUrl, {
  http.Client? client,
  BiometricAuthPrompt? promptForBiometricAuth,
}) async {
  return (await biometricSignInDetailed(
        baseUrl,
        client: client,
        promptForBiometricAuth: promptForBiometricAuth,
      )) ==
      BiometricFlowResult.success;
}
