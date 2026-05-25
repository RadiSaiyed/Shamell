import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/base_url.dart';
import '../../core/device_id.dart';
import '../../core/session_cookie_store.dart';
import 'payments_idempotency.dart';

class ShamellMiniPaymentIntent {
  final String id;
  final String walletId;
  final int amountCents;
  final String currency;
  final String status;
  final String? merchantReference;
  final String? expiresAt;
  final String? paidTxnId;

  const ShamellMiniPaymentIntent({
    required this.id,
    required this.walletId,
    required this.amountCents,
    required this.currency,
    required this.status,
    this.merchantReference,
    this.expiresAt,
    this.paidTxnId,
  });

  factory ShamellMiniPaymentIntent.fromJson(Map<String, dynamic> json) {
    return ShamellMiniPaymentIntent(
      id: (json['id'] ?? '').toString(),
      walletId: (json['wallet_id'] ?? '').toString(),
      amountCents: (json['amount_cents'] is num)
          ? (json['amount_cents'] as num).toInt()
          : int.tryParse((json['amount_cents'] ?? '').toString()) ?? 0,
      currency: (json['currency'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      merchantReference:
          (json['merchant_reference'] ?? '').toString().trim().isEmpty
              ? null
              : (json['merchant_reference'] ?? '').toString(),
      expiresAt: (json['expires_at'] ?? '').toString().trim().isEmpty
          ? null
          : (json['expires_at'] ?? '').toString(),
      paidTxnId: (json['paid_txn_id'] ?? '').toString().trim().isEmpty
          ? null
          : (json['paid_txn_id'] ?? '').toString(),
    );
  }
}

class ShamellMiniProgramPaymentSdk {
  final String baseUrl;
  final http.Client client;

  const ShamellMiniProgramPaymentSdk({
    required this.baseUrl,
    required this.client,
  });

  Uri? _uri(List<String> pathSegments) {
    return secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['payments', 'mini', ...pathSegments],
    );
  }

  Future<Map<String, String>> _mutationHeaders() async {
    final deviceId = await getOrCreateStableDeviceId(baseUrlOverride: baseUrl);
    final headers = await shamellSessionHeadersForBaseUrl(baseUrl, json: true);
    headers['Idempotency-Key'] = newPaymentsIdempotencyKey('mini-payment');
    headers['X-Device-ID'] = deviceId;
    return headers;
  }

  Future<ShamellMiniPaymentIntent> createPaymentIntent({
    required int amountCents,
    required String currency,
    String? merchantReference,
    Map<String, Object?>? metadata,
  }) async {
    final uri = _uri(const <String>['payment-intents']);
    if (uri == null) throw StateError('Invalid server URL');
    final response = await client.post(
      uri,
      headers: await _mutationHeaders(),
      body: jsonEncode(<String, Object?>{
        'amount_cents': amountCents,
        'currency': currency,
        if ((merchantReference ?? '').trim().isNotEmpty)
          'merchant_reference': merchantReference!.trim(),
        if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(response.body);
    }
    return ShamellMiniPaymentIntent.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<ShamellMiniPaymentIntent> getPaymentIntent(String intentId) async {
    final uri = _uri(<String>['payment-intents', intentId.trim()]);
    if (uri == null) throw StateError('Invalid server URL');
    final response = await client.get(
      uri,
      headers: await shamellSessionHeadersForBaseUrl(baseUrl),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(response.body);
    }
    return ShamellMiniPaymentIntent.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<ShamellMiniPaymentIntent> confirmPaymentIntent(String intentId) async {
    final uri = _uri(<String>['payment-intents', intentId.trim(), 'confirm']);
    if (uri == null) throw StateError('Invalid server URL');
    final response = await client.post(
      uri,
      headers: await _mutationHeaders(),
      body: jsonEncode(const <String, Object?>{}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(response.body);
    }
    return ShamellMiniPaymentIntent.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
