import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'base_url.dart';
import 'device_id.dart';
import 'payments/supported_currencies.dart';
import 'session_cookie_store.dart';

class UsernamePasswordAuthResult {
  final String username;
  final String shamellId;
  final String walletId;
  final String walletCurrency;

  const UsernamePasswordAuthResult({
    required this.username,
    required this.shamellId,
    this.walletId = '',
    this.walletCurrency = shamellDefaultWalletCurrency,
  });
}

Future<UsernamePasswordAuthResult> shamellSignUpWithUsernamePassword({
  required String baseUrl,
  required String username,
  required String password,
  String? walletCurrency,
  http.Client? client,
}) async {
  return _submitUsernamePasswordAuth(
    path: '/auth/signup',
    baseUrl: baseUrl,
    username: username,
    password: password,
    walletCurrency: walletCurrency,
    client: client,
  );
}

Future<UsernamePasswordAuthResult> shamellSignInWithUsernamePassword({
  required String baseUrl,
  required String username,
  required String password,
  http.Client? client,
}) async {
  return _submitUsernamePasswordAuth(
    path: '/auth/login',
    baseUrl: baseUrl,
    username: username,
    password: password,
    client: client,
  );
}

Future<UsernamePasswordAuthResult> _submitUsernamePasswordAuth({
  required String path,
  required String baseUrl,
  required String username,
  required String password,
  String? walletCurrency,
  http.Client? client,
}) async {
  final base = normalizeSecureApiBaseUrl(baseUrl.trim());
  if (base == null) {
    throw Exception('Invalid API base URL. Configure HTTPS base_url.');
  }

  final normalizedUsername = username.trim().toLowerCase();
  final deviceId = await getOrCreateStableDeviceId(baseUrlOverride: base);
  final ownedClient = client == null;
  final httpClient = client ?? shamellHttpClient();

  try {
    final requestBody = <String, Object?>{
      'username': normalizedUsername,
      'password': password,
      'device_id': deviceId,
    };
    if (path == '/auth/signup' && walletCurrency != null) {
      requestBody['currency'] = shamellNormalizeWalletCurrency(walletCurrency);
    }

    final response = await httpClient.post(
      Uri.parse('$base$path'),
      headers: await shamellSessionHeadersForBaseUrl(
        base,
        json: true,
        includeSessionCookie: false,
      ),
      body: jsonEncode(requestBody),
    );

    if (response.statusCode != 200) {
      throw Exception(
        _usernamePasswordAuthErrorMessage(
          statusCode: response.statusCode,
          rawBody: response.body,
        ),
      );
    }

    if (!kIsWeb) {
      final token = extractSessionTokenFromSetCookieHeader(
        response.headers['set-cookie'],
      );
      if (token == null || token.isEmpty) {
        throw Exception('Missing session cookie.');
      }
      await setSessionTokenForBaseUrl(base, token);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('Invalid authentication response.');
    }

    final shamellId = (decoded['shamell_id'] ?? '').toString().trim();
    final walletId = (decoded['wallet_id'] ?? '').toString().trim();
    final wallet = decoded['wallet'];
    final responseCurrency = wallet is Map
        ? (wallet['currency'] ?? '').toString()
        : (decoded['currency'] ?? '').toString();
    final responseUsername = (decoded['username'] ?? normalizedUsername)
        .toString()
        .trim()
        .toLowerCase();
    return UsernamePasswordAuthResult(
      username: responseUsername,
      shamellId: shamellId,
      walletId: walletId,
      walletCurrency: shamellNormalizeWalletCurrency(responseCurrency),
    );
  } finally {
    if (ownedClient) {
      httpClient.close();
    }
  }
}

String _usernamePasswordAuthErrorMessage({
  required int statusCode,
  required String rawBody,
}) {
  final detail = _extractUsernamePasswordAuthDetail(rawBody);
  if (detail.isNotEmpty) {
    return detail;
  }
  switch (statusCode) {
    case 400:
      return 'Invalid username or password format.';
    case 401:
      return 'Invalid username or password.';
    case 409:
      return 'Username already taken.';
    default:
      return 'Authentication failed (HTTP $statusCode).';
  }
}

String _extractUsernamePasswordAuthDetail(String rawBody) {
  final body = rawBody.trim();
  if (body.isEmpty) return '';
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      final detail =
          (decoded['detail'] ?? decoded['error'] ?? '').toString().trim();
      if (detail.isNotEmpty) {
        return detail;
      }
    }
  } catch (_) {}
  return body.length > 200 ? body.substring(0, 200).trim() : body;
}
