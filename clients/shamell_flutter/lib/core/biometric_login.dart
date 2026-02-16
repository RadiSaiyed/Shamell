import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'device_id.dart';
import 'session_cookie_store.dart';

const FlutterSecureStorage _bioStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(
    encryptedSharedPreferences: true,
    resetOnError: true,
    sharedPreferencesName: 'shamell_secure_store',
  ),
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
);

String? _normalizedHostFromBaseUrl(String baseUrl) {
  try {
    final u = Uri.parse(baseUrl.trim());
    final host = u.host.trim().toLowerCase();
    if (host.isEmpty) return null;
    return host;
  } catch (_) {
    return null;
  }
}

bool _isSecureBaseUrl(String baseUrl) {
  final u = Uri.tryParse(baseUrl.trim());
  if (u == null) return false;
  final scheme = u.scheme.trim().toLowerCase();
  final host = u.host.trim().toLowerCase();
  if (host.isEmpty) return false;
  if (scheme == 'https') return true;
  // Allow plaintext only for explicit localhost dev.
  return scheme == 'http' && (host == 'localhost' || host == '127.0.0.1' || host == '::1');
}

String _bioTokenKeyForHost(String host) => 'bio_login_token.v1.$host';

Future<String?> getBiometricLoginTokenForBaseUrl(String baseUrl) async {
  if (kIsWeb) return null;
  final host = _normalizedHostFromBaseUrl(baseUrl);
  if (host == null || host.isEmpty) return null;
  if (!_isSecureBaseUrl(baseUrl)) return null;
  try {
    return (await _bioStorage.read(key: _bioTokenKeyForHost(host)) ?? '').trim();
  } catch (_) {
    return null;
  }
}

Future<void> setBiometricLoginTokenForBaseUrl(String baseUrl, String token) async {
  if (kIsWeb) return;
  final host = _normalizedHostFromBaseUrl(baseUrl);
  if (host == null || host.isEmpty) return;
  if (!_isSecureBaseUrl(baseUrl)) return;
  final t = token.trim();
  if (t.isEmpty) return;
  try {
    await _bioStorage.write(key: _bioTokenKeyForHost(host), value: t);
  } catch (_) {}
}

Future<void> clearBiometricLoginTokenForBaseUrl(String baseUrl) async {
  if (kIsWeb) return;
  final host = _normalizedHostFromBaseUrl(baseUrl);
  if (host == null || host.isEmpty) return;
  try {
    await _bioStorage.delete(key: _bioTokenKeyForHost(host));
  } catch (_) {}
}

Future<bool> ensureBiometricLoginEnrolled(String baseUrl) async {
  if (kIsWeb) return false;
  if (!_isSecureBaseUrl(baseUrl)) return false;
  final existing = await getBiometricLoginTokenForBaseUrl(baseUrl);
  if (existing != null && existing.isNotEmpty) return true;

  final cookie = await getSessionCookieHeader(baseUrl);
  if (cookie == null || cookie.isEmpty) return false;
  final deviceId = await getOrCreateStableDeviceId();
  final uri = Uri.parse('${baseUrl.trim()}/auth/biometric/enroll');
  try {
    final resp = await http.post(
      uri,
      headers: <String, String>{
        'content-type': 'application/json',
        'cookie': cookie,
      },
      body: jsonEncode(<String, Object?>{
        'device_id': deviceId,
      }),
    );
    if (resp.statusCode != 200) return false;
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) return false;
    final token = (decoded['token'] ?? '').toString().trim();
    if (token.isEmpty) return false;
    await setBiometricLoginTokenForBaseUrl(baseUrl, token);
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> biometricSignIn(String baseUrl) async {
  if (kIsWeb) return false;
  if (!_isSecureBaseUrl(baseUrl)) return false;
  final token = await getBiometricLoginTokenForBaseUrl(baseUrl);
  if (token == null || token.isEmpty) return false;
  final deviceId = await getOrCreateStableDeviceId();
  final uri = Uri.parse('${baseUrl.trim()}/auth/biometric/login');
  try {
    final resp = await http.post(
      uri,
      headers: const <String, String>{
        'content-type': 'application/json',
      },
      body: jsonEncode(<String, Object?>{
        'device_id': deviceId,
        'token': token,
        'rotate': true,
      }),
    );
    final tok = extractSessionTokenFromSetCookieHeader(resp.headers['set-cookie']);
    if (resp.statusCode != 200 || tok == null || tok.isEmpty) return false;
    await setSessionTokenForBaseUrl(baseUrl, tok);
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map) {
        final next = (decoded['token'] ?? '').toString().trim();
        if (next.isNotEmpty) {
          await setBiometricLoginTokenForBaseUrl(baseUrl, next);
        }
      }
    } catch (_) {}
    return true;
  } catch (_) {
    return false;
  }
}
