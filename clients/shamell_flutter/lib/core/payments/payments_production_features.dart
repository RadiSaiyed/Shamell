import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/base_url.dart';
import '../../core/device_id.dart';
import '../../core/format.dart' show fmtCents;
import '../../core/http_error.dart';
import '../../core/l10n.dart';
import '../../core/session_cookie_store.dart';
import 'payments_card_style.dart';
import 'payments_idempotency.dart';
import 'payments_send.dart' show PayActionButton;

class PaymentsProductionFeaturesPage extends StatefulWidget {
  final String baseUrl;
  final String walletId;
  final String deviceId;
  final String currency;
  final http.Client? client;

  const PaymentsProductionFeaturesPage({
    super.key,
    required this.baseUrl,
    required this.walletId,
    required this.deviceId,
    required this.currency,
    this.client,
  });

  @override
  State<PaymentsProductionFeaturesPage> createState() =>
      _PaymentsProductionFeaturesPageState();
}

class _PaymentsProductionFeaturesPageState
    extends State<PaymentsProductionFeaturesPage> {
  late final http.Client _http;
  late final bool _ownsHttpClient;

  final _linkAmountCtrl = TextEditingController();
  final _linkPurposeCtrl = TextEditingController();
  final _payLinkCtrl = TextEditingController();
  final _aliasCtrl = TextEditingController();
  final _webhookUrlCtrl =
      TextEditingController(text: 'https://example.com/payments');
  final _settlementAmountCtrl = TextEditingController();
  final _settlementDestinationCtrl = TextEditingController();
  final _settlementResolveCtrl = TextEditingController();
  final _disputeTxnCtrl = TextEditingController();
  final _disputeReasonCtrl = TextEditingController();
  final _kycTypeCtrl = TextEditingController(text: 'id');
  final _kycRefCtrl = TextEditingController();
  final _fxFromCtrl = TextEditingController(text: 'USD');
  final _fxToCtrl = TextEditingController(text: 'SYP');
  final _fxRateCtrl = TextEditingController(text: '10000');
  final _offlinePayloadCtrl =
      TextEditingController(text: '{"kind":"transfer"}');
  final _miniIntentCtrl = TextEditingController();
  final _riskRuleCtrl = TextEditingController(text: 'High value transaction');
  final _riskThresholdCtrl = TextEditingController(text: '1000000');

  List<Map<String, dynamic>> _links = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _aliases = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _webhooks = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _settlements = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _disputes = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _kycDocs = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _fxRates = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _offline = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _events = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _riskRules = const <Map<String, dynamic>>[];
  Map<String, dynamic>? _reconciliation;
  Map<String, dynamic>? _riskEvaluation;
  Map<String, dynamic>? _recurringRun;
  String _status = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _http = widget.client ?? shamellHttpClient();
    _ownsHttpClient = widget.client == null;
    _refresh();
  }

  @override
  void dispose() {
    for (final ctrl in [
      _linkAmountCtrl,
      _linkPurposeCtrl,
      _payLinkCtrl,
      _aliasCtrl,
      _webhookUrlCtrl,
      _settlementAmountCtrl,
      _settlementDestinationCtrl,
      _settlementResolveCtrl,
      _disputeTxnCtrl,
      _disputeReasonCtrl,
      _kycTypeCtrl,
      _kycRefCtrl,
      _fxFromCtrl,
      _fxToCtrl,
      _fxRateCtrl,
      _offlinePayloadCtrl,
      _miniIntentCtrl,
      _riskRuleCtrl,
      _riskThresholdCtrl,
    ]) {
      ctrl.dispose();
    }
    if (_ownsHttpClient) _http.close();
    super.dispose();
  }

  Uri? _uri(List<String> path, {Map<String, String>? query}) {
    return secureApiChildUri(
      baseUrl: widget.baseUrl,
      pathSegments: <String>['payments', ...path],
      queryParameters: query,
    );
  }

  int _parseCents(String raw) {
    final value = double.tryParse(raw.trim().replaceAll(',', '.'));
    if (value == null || !value.isFinite || value <= 0) return 0;
    return (value * 100).round();
  }

  Future<Map<String, String>> _headers({bool json = false}) {
    return shamellSessionHeadersForBaseUrl(widget.baseUrl, json: json);
  }

  Future<Map<String, String>> _mutationHeaders(String scope) async {
    final headers = await _headers(json: true);
    final stable = (await getOrCreateStableDeviceId(
      baseUrlOverride: widget.baseUrl,
    ))
        .trim();
    headers['Idempotency-Key'] = newPaymentsIdempotencyKey(scope);
    headers['X-Device-ID'] = stable.isNotEmpty ? stable : widget.deviceId;
    return headers;
  }

  Future<dynamic> _get(List<String> path, {Map<String, String>? query}) async {
    final uri = _uri(path, query: query);
    if (uri == null) throw StateError('Invalid server URL');
    final response = await _http.get(uri, headers: await _headers());
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(response.body);
    }
    return jsonDecode(response.body);
  }

  Future<dynamic> _post(
    List<String> path,
    Map<String, Object?> body, {
    required String scope,
  }) async {
    final uri = _uri(path);
    if (uri == null) throw StateError('Invalid server URL');
    final response = await _http.post(
      uri,
      headers: await _mutationHeaders(scope),
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(response.body);
    }
    return jsonDecode(response.body);
  }

  List<Map<String, dynamic>> _maps(dynamic decoded) {
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    }
    return const <Map<String, dynamic>>[];
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '...';
    });
    try {
      await action();
      if (!mounted) return;
      setState(() => _status = label);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = sanitizeExceptionForUi(
          error: error,
          isArabic: L10n.of(context).isArabic,
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    await _run('Loaded.', _loadAll);
  }

  Future<void> _loadAll() async {
    _links = _maps(await _get(const <String>['payment-links']));
    _aliases = _maps(await _get(const <String>['aliases']));
    _webhooks = _maps(await _get(const <String>['merchant', 'webhooks']));
    _settlements = _maps(await _get(const <String>['merchant', 'settlements']));
    _disputes = _maps(await _get(const <String>['disputes']));
    _kycDocs = _maps(await _get(const <String>['kyc', 'documents']));
    _fxRates = _maps(await _get(const <String>['fx', 'rates']));
    _offline = _maps(await _get(const <String>['offline-payments']));
    _events = _maps(await _get(const <String>['events']));
    try {
      _riskRules = _maps(await _get(const <String>['admin', 'risk', 'rules']));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.isArabic ? 'الدفع المتقدم' : 'Production payments'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _refresh,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: shamellPaymentPagePadding(context),
          children: [
            _paymentLinksCard(),
            _merchantOpsCard(),
            _identityCard(),
            _checkoutAndOfflineCard(),
            _disputesAndFxCard(),
            _adminOpsCard(),
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 12),
              ShamellPaymentCardSurface(
                tone: ShamellPaymentCardTone.soft,
                child: SelectableText(_status),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _title(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }

  Widget _card(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ShamellPaymentCardSurface(
        tone: ShamellPaymentCardTone.soft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _row(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentLinksCard() {
    return _card([
      _title('Payment links', Icons.link_outlined),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _linkAmountCtrl,
              keyboardType: TextInputType.number,
              decoration:
                  InputDecoration(labelText: 'Amount (${widget.currency})'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _linkPurposeCtrl,
              decoration: const InputDecoration(labelText: 'Purpose'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          PayActionButton(
            icon: Icons.add_link_outlined,
            label: 'Create link',
            onTap: () => _run('Payment link created.', () async {
              await _post(
                const <String>['payment-links'],
                <String, Object?>{
                  'amount_cents': _parseCents(_linkAmountCtrl.text),
                  'currency': widget.currency,
                  'purpose': _linkPurposeCtrl.text.trim(),
                },
                scope: 'payment-link-create',
              );
              await _loadAll();
            }),
            radius: 16,
          ),
          PayActionButton(
            icon: Icons.payments_outlined,
            label: 'Pay link',
            onTap: () => _run('Payment link paid.', () async {
              final id = _payLinkCtrl.text.trim();
              await _post(<String>[
                'payment-links',
                id,
                'pay'
              ], const <String, Object?>{}, scope: 'payment-link-pay');
              await _loadAll();
            }),
            radius: 16,
          ),
        ],
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _payLinkCtrl,
        decoration: const InputDecoration(labelText: 'Link ID to pay'),
      ),
      const SizedBox(height: 8),
      for (final link in _links.take(4))
        _row(
          '${link['status']} · ${fmtCents((link['amount_cents'] as num?)?.toInt() ?? 0)} ${link['currency']}',
          '${link['id'] ?? ''}',
        ),
    ]);
  }

  Widget _merchantOpsCard() {
    return _card([
      _title('Merchant checkout, webhooks & settlement', Icons.store_outlined),
      const SizedBox(height: 10),
      TextField(
        controller: _webhookUrlCtrl,
        decoration: const InputDecoration(labelText: 'Webhook URL'),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _settlementAmountCtrl,
              keyboardType: TextInputType.number,
              decoration:
                  InputDecoration(labelText: 'Payout (${widget.currency})'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _settlementDestinationCtrl,
              decoration: const InputDecoration(labelText: 'Destination'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          PayActionButton(
            icon: Icons.webhook_outlined,
            label: 'Add webhook',
            onTap: () => _run('Webhook added.', () async {
              await _post(
                const <String>['merchant', 'webhooks'],
                <String, Object?>{
                  'url': _webhookUrlCtrl.text.trim(),
                  'events': <String>[
                    'payment_intent.paid',
                    'payment_link.paid',
                    'refund.approved',
                  ],
                },
                scope: 'merchant-webhook',
              );
              await _loadAll();
            }),
            radius: 16,
          ),
          PayActionButton(
            icon: Icons.account_balance_outlined,
            label: 'Request payout',
            onTap: () => _run('Settlement requested.', () async {
              await _post(
                const <String>['merchant', 'settlements'],
                <String, Object?>{
                  'amount_cents': _parseCents(_settlementAmountCtrl.text),
                  'destination_ref': _settlementDestinationCtrl.text.trim(),
                },
                scope: 'merchant-settlement',
              );
              await _loadAll();
            }),
            radius: 16,
          ),
        ],
      ),
      const SizedBox(height: 8),
      for (final webhook in _webhooks.take(2))
        _row('${webhook['status']}', '${webhook['url']}'),
      for (final settlement in _settlements.take(3))
        _row(
          '${settlement['status']} · ${fmtCents((settlement['amount_cents'] as num?)?.toInt() ?? 0)} ${settlement['currency']}',
          '${settlement['id']}',
        ),
    ]);
  }

  Widget _identityCard() {
    return _card([
      _title('Wallet aliases & KYC upload', Icons.badge_outlined),
      const SizedBox(height: 10),
      TextField(
        controller: _aliasCtrl,
        decoration: const InputDecoration(labelText: '@alias'),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _kycTypeCtrl,
              decoration: const InputDecoration(labelText: 'Document type'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _kycRefCtrl,
              decoration:
                  const InputDecoration(labelText: 'Document reference'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          PayActionButton(
            icon: Icons.alternate_email,
            label: 'Save alias',
            onTap: () => _run('Alias saved.', () async {
              await _post(
                const <String>['aliases'],
                <String, Object?>{
                  'alias': _aliasCtrl.text.trim(),
                  'alias_type': 'username',
                },
                scope: 'wallet-alias',
              );
              await _loadAll();
            }),
            radius: 16,
          ),
          PayActionButton(
            icon: Icons.upload_file_outlined,
            label: 'Submit KYC',
            onTap: () => _run('KYC document submitted.', () async {
              await _post(
                const <String>['kyc', 'documents'],
                <String, Object?>{
                  'document_type': _kycTypeCtrl.text.trim(),
                  'reference': _kycRefCtrl.text.trim(),
                },
                scope: 'kyc-document',
              );
              await _loadAll();
            }),
            radius: 16,
          ),
        ],
      ),
      const SizedBox(height: 8),
      for (final alias in _aliases.take(3))
        _row('@${alias['alias']}', '${alias['alias_type']}'),
      for (final doc in _kycDocs.take(3))
        _row('${doc['document_type']} · ${doc['status']}',
            '${doc['reference']}'),
    ]);
  }

  Widget _checkoutAndOfflineCard() {
    return _card([
      _title(
          'Checkout, notifications & offline queue', Icons.extension_outlined),
      const SizedBox(height: 10),
      TextField(
        controller: _miniIntentCtrl,
        decoration: const InputDecoration(labelText: 'Mini Payment Intent ID'),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _offlinePayloadCtrl,
        maxLines: 2,
        decoration: const InputDecoration(labelText: 'Offline payload JSON'),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          PayActionButton(
            icon: Icons.check_circle_outline,
            label: 'Confirm intent',
            onTap: () => _run('Payment intent confirmed.', () async {
              final id = _miniIntentCtrl.text.trim();
              await _post(<String>[
                'mini',
                'payment-intents',
                id,
                'confirm'
              ], const <String, Object?>{}, scope: 'mini-intent-confirm');
              await _loadAll();
            }),
            radius: 16,
          ),
          PayActionButton(
            icon: Icons.cloud_upload_outlined,
            label: 'Submit offline',
            onTap: () => _run('Offline payment submitted.', () async {
              final payload = jsonDecode(_offlinePayloadCtrl.text) as Object?;
              await _post(
                const <String>['offline-payments'],
                <String, Object?>{
                  'operation': 'transfer',
                  'payload': payload,
                },
                scope: 'offline-payment',
              );
              await _loadAll();
            }),
            radius: 16,
          ),
        ],
      ),
      const SizedBox(height: 8),
      for (final event in _events.take(3))
        _row('${event['event_type']}', '${event['title']}'),
      for (final item in _offline.take(3))
        _row('${item['operation']} · ${item['status']}', '${item['id']}'),
    ]);
  }

  Widget _disputesAndFxCard() {
    return _card([
      _title('Disputes & FX rates', Icons.gavel_outlined),
      const SizedBox(height: 10),
      TextField(
        controller: _disputeTxnCtrl,
        decoration: const InputDecoration(labelText: 'Transaction ID'),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _disputeReasonCtrl,
        decoration: const InputDecoration(labelText: 'Dispute reason'),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _fxFromCtrl,
              decoration: const InputDecoration(labelText: 'FX from'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _fxToCtrl,
              decoration: const InputDecoration(labelText: 'FX to'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _fxRateCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Rate bps'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          PayActionButton(
            icon: Icons.report_outlined,
            label: 'Open dispute',
            onTap: () => _run('Dispute opened.', () async {
              await _post(
                const <String>['disputes'],
                <String, Object?>{
                  'txn_id': _disputeTxnCtrl.text.trim(),
                  'reason': _disputeReasonCtrl.text.trim(),
                },
                scope: 'payment-dispute',
              );
              await _loadAll();
            }),
            radius: 16,
          ),
          PayActionButton(
            icon: Icons.currency_exchange,
            label: 'Set FX rate',
            onTap: () => _run('FX rate saved.', () async {
              await _post(
                const <String>['admin', 'fx', 'rates'],
                <String, Object?>{
                  'from_currency': _fxFromCtrl.text.trim(),
                  'to_currency': _fxToCtrl.text.trim(),
                  'rate_bps': int.tryParse(_fxRateCtrl.text.trim()) ?? 0,
                  'fee_bps': 50,
                },
                scope: 'fx-rate',
              );
              await _loadAll();
            }),
            radius: 16,
          ),
        ],
      ),
      const SizedBox(height: 8),
      for (final dispute in _disputes.take(3))
        _row('${dispute['status']} · ${dispute['txn_id']}',
            '${dispute['reason']}'),
      for (final rate in _fxRates.take(3))
        _row('${rate['from_currency']} -> ${rate['to_currency']}',
            '${rate['rate_bps']} bps'),
    ]);
  }

  Widget _adminOpsCard() {
    return _card([
      _title('Admin risk, reconciliation & recurring runner',
          Icons.admin_panel_settings_outlined),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _riskRuleCtrl,
              decoration: const InputDecoration(labelText: 'Risk rule'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _riskThresholdCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Threshold cents'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _settlementResolveCtrl,
        decoration:
            const InputDecoration(labelText: 'Settlement ID to approve'),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          PayActionButton(
            icon: Icons.rule_outlined,
            label: 'Add rule',
            onTap: () => _run('Risk rule added.', () async {
              await _post(
                const <String>['admin', 'risk', 'rules'],
                <String, Object?>{
                  'name': _riskRuleCtrl.text.trim(),
                  'rule_type': 'high_value_txn',
                  'threshold_cents':
                      int.tryParse(_riskThresholdCtrl.text.trim()) ?? 0,
                  'action': 'alert',
                },
                scope: 'risk-rule',
              );
              await _loadAll();
            }),
            radius: 16,
          ),
          PayActionButton(
            icon: Icons.security_outlined,
            label: 'Evaluate',
            onTap: () => _run('Risk evaluated.', () async {
              _riskEvaluation = Map<String, dynamic>.from(
                await _post(const <String>[
                  'admin',
                  'risk',
                  'evaluate'
                ], const <String, Object?>{}, scope: 'risk-evaluate') as Map,
              );
            }),
            radius: 16,
          ),
          PayActionButton(
            icon: Icons.balance_outlined,
            label: 'Reconcile',
            onTap: () => _run('Reconciliation loaded.', () async {
              _reconciliation = Map<String, dynamic>.from(
                await _get(const <String>['admin', 'reconciliation']) as Map,
              );
            }),
            radius: 16,
          ),
          PayActionButton(
            icon: Icons.repeat_on_outlined,
            label: 'Run recurring',
            onTap: () => _run('Recurring runner completed.', () async {
              _recurringRun = Map<String, dynamic>.from(
                await _post(const <String>[
                  'admin',
                  'recurring',
                  'run'
                ], const <String, Object?>{}, scope: 'recurring-run') as Map,
              );
            }),
            radius: 16,
          ),
          PayActionButton(
            icon: Icons.verified_outlined,
            label: 'Approve payout',
            onTap: () => _run('Settlement approved.', () async {
              final id = _settlementResolveCtrl.text.trim();
              await _post(<String>[
                'admin',
                'settlements',
                id,
                'resolve'
              ], const <String, Object?>{
                'action': 'approve'
              }, scope: 'settlement-resolve');
              await _loadAll();
            }),
            radius: 16,
          ),
        ],
      ),
      const SizedBox(height: 8),
      for (final rule in _riskRules.take(3))
        _row('${rule['rule_type']} · ${rule['action']}', '${rule['name']}'),
      if (_riskEvaluation != null)
        _row('Risk evaluation', '${_riskEvaluation!['triggered']}'),
      if (_reconciliation != null)
        _row('Reconciliation',
            '${_reconciliation!['mismatch_count']} mismatches'),
      if (_recurringRun != null)
        _row('Recurring run',
            '${_recurringRun!['executed_count']} executed · ${_recurringRun!['failed_count']} failed'),
    ]);
  }
}
