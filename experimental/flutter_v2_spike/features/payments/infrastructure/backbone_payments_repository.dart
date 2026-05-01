import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../../core/base_url.dart';
import '../../../../core/device_binding_guard.dart';
import '../../../../core/device_id.dart';
import '../../../../core/logout_wipe.dart';
import '../../../../core/payments/payments_attestation.dart';
import '../../../../core/payments/payments_idempotency.dart';
import '../../../../core/session_cookie_store.dart';
import '../../../../core/v2_auth_strangler.dart';
import '../../../core/disposable.dart';
import '../domain/payment_transfer.dart';
import 'payments_repository.dart';

typedef BackbonePaymentsBaseUrlProvider = Future<String> Function();

@visibleForTesting
bool shamellIsCriticalBackbonePaymentsFailure(Object error) {
  if (shamellIsCriticalAccountSessionError(error)) {
    return true;
  }
  final text = error.toString().toLowerCase();
  return text.contains('auth session required') ||
      text.contains('authentication required') ||
      text.contains('authenticated session required') ||
      text.contains('unauthorized') ||
      text.contains('forbidden') ||
      text.contains('http 401') ||
      text.contains('http 403');
}

@visibleForTesting
String shamellBackbonePaymentsLocalhostClientIp(String baseUrl) {
  final uri = parseApiBaseUrl(baseUrl.trim());
  if (uri == null) return '';
  if (isLocalhostHost(uri.host)) {
    return '127.0.0.1';
  }
  return '';
}

class BackbonePaymentsRepository implements PaymentsRepository, V2Disposable {
  final BackbonePaymentsBaseUrlProvider? baseUrlProvider;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Duration _requestTimeout;
  bool _disposed = false;

  BackbonePaymentsRepository({
    this.baseUrlProvider,
    http.Client? httpClient,
    http.Client Function()? httpClientFactory,
    Duration requestTimeout = const Duration(seconds: 20),
  })  : assert(
          httpClient == null || httpClientFactory == null,
          'Provide either httpClient or httpClientFactory, not both.',
        ),
        _httpClient =
            httpClient ?? (httpClientFactory?.call() ?? shamellHttpClient()),
        _ownsHttpClient = httpClient == null,
        _requestTimeout = requestTimeout;

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }

  @override
  Future<TransferResult> transfer(PaymentTransfer transfer) async {
    String? baseUrl;
    try {
      final fromWalletId = transfer.fromWalletId.trim();
      final toWalletId = transfer.toWalletId.trim();
      if (fromWalletId.isEmpty) {
        throw Exception('Missing source wallet');
      }
      if (toWalletId.isEmpty) {
        throw Exception('Missing destination wallet');
      }
      if (transfer.amountCents <= 0) {
        throw Exception('Amount must be positive');
      }
      final idempotencyKey = transfer.idempotencyKey.trim().isNotEmpty
          ? transfer.idempotencyKey.trim()
          : newPaymentsIdempotencyKey('v2tw');

      baseUrl = await _resolveBaseUrl();
      final transferUri = secureApiChildUri(
        baseUrl: baseUrl,
        pathSegments: const <String>['payments', 'transfer'],
      );
      if (transferUri == null) {
        throw Exception('Invalid API base URL. Configure HTTPS base_url.');
      }
      final headers = await _authHeaders(baseUrl, json: true);
      headers['Idempotency-Key'] = idempotencyKey;
      final deviceId = await getOrCreateStableDeviceId(
        baseUrlOverride: baseUrl,
      );
      headers['X-Device-ID'] = deviceId;
      headers.addAll(
        await shamellBuildPaymentMutationAttestationHeaders(
          baseUrl: baseUrl,
          deviceId: deviceId,
          operation: 'payments_transfer',
          resourceId: shamellPaymentTransferAttestationResourceId(
            fromWalletId: fromWalletId,
            toWalletId: toWalletId,
            amountCents: transfer.amountCents,
          ),
          client: _httpClient,
        ),
      );
      final response = await _httpClient
          .post(
            transferUri,
            headers: headers,
            body: jsonEncode(<String, Object?>{
              'from_wallet_id': fromWalletId,
              'to_wallet_id': toWalletId,
              'amount_cents': transfer.amountCents,
            }),
          )
          .timeout(_requestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _httpError(
          fallback: 'Transfer failed',
          statusCode: response.statusCode,
          body: response.body,
        );
      }

      final newBalance = await _loadWalletBalance(
        baseUrl: baseUrl,
        walletId: fromWalletId,
      );
      return TransferResult(newBalanceCents: newBalance);
    } catch (e) {
      await _rethrowIfCriticalSessionFailure(e, baseUrlOverride: baseUrl);
      rethrow;
    }
  }

  @override
  Future<int> loadBalanceCents({required String walletId}) async {
    String? baseUrl;
    try {
      baseUrl = await _resolveBaseUrl();
      return await _loadWalletBalance(baseUrl: baseUrl, walletId: walletId);
    } catch (e) {
      await _rethrowIfCriticalSessionFailure(e, baseUrlOverride: baseUrl);
      rethrow;
    }
  }

  Future<String> _resolveBaseUrl() async {
    final raw = baseUrlProvider != null
        ? await baseUrlProvider!.call()
        : await V2AuthStranglerStore.resolveBaseUrl();
    final baseUrl = normalizeSecureApiBaseUrl(raw.trim());
    if (baseUrl == null) {
      throw Exception('Invalid API base URL. Configure HTTPS base_url.');
    }
    return baseUrl;
  }

  Future<Map<String, String>> _authHeaders(
    String baseUrl, {
    bool json = false,
  }) async {
    final headers = <String, String>{};
    if (json) {
      headers['content-type'] = 'application/json';
    }

    final localhostIp = shamellBackbonePaymentsLocalhostClientIp(baseUrl);
    if (localhostIp.isNotEmpty) {
      headers['x-shamell-client-ip'] = localhostIp;
    }

    final cookie = await getSessionCookieHeader(baseUrl);
    if (cookie == null || cookie.isEmpty) {
      throw Exception('auth session required');
    }
    headers['cookie'] = cookie;
    return headers;
  }

  Future<int> _loadWalletBalance({
    required String baseUrl,
    required String walletId,
  }) async {
    final normalizedWalletId = walletId.trim();
    if (normalizedWalletId.isEmpty) {
      throw Exception('Missing wallet ID');
    }
    final walletUri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'payments',
        'wallets',
        normalizedWalletId,
      ],
    );
    if (walletUri == null) {
      throw Exception('Invalid API base URL. Configure HTTPS base_url.');
    }
    final response = await _httpClient
        .get(
          walletUri,
          headers: await _authHeaders(baseUrl),
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw _httpError(
        fallback: 'Failed to load wallet',
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid wallet response.');
    }
    final raw = decoded['balance_cents'] ?? decoded['balanceCents'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    final parsed = int.tryParse((raw ?? '').toString());
    if (parsed != null) return parsed;
    throw Exception('Wallet response missing balance_cents.');
  }

  Exception _httpError({
    required String fallback,
    required int statusCode,
    required String body,
  }) {
    final detail = _extractApiDetail(body);
    if (statusCode == 401 || statusCode == 403) {
      if (detail.isNotEmpty) {
        return Exception(detail);
      }
      return Exception('auth session required');
    }
    if (detail.isNotEmpty) {
      return Exception(detail);
    }
    return Exception('$fallback (HTTP $statusCode).');
  }

  Future<void> _rethrowIfCriticalSessionFailure(
    Object error, {
    String? baseUrlOverride,
  }) async {
    if (!shamellIsCriticalBackbonePaymentsFailure(error)) {
      return;
    }
    await wipeLocalAccountData(
      preserveDevicePrefs: true,
      baseUrlOverride: baseUrlOverride,
    );
    throw Exception(
      'This Shamell session is no longer valid on this device. Sign in again.',
    );
  }

  String _extractApiDetail(String rawBody) {
    final text = rawBody.trim();
    if (text.isEmpty) return '';
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        final detail = (decoded['detail'] ?? '').toString().trim();
        if (detail.isNotEmpty) return detail;
        final error = (decoded['error'] ?? '').toString().trim();
        if (error.isNotEmpty) return error;
        final message = (decoded['message'] ?? '').toString().trim();
        if (message.isNotEmpty) return message;
      }
    } catch (_) {}
    return text;
  }
}
