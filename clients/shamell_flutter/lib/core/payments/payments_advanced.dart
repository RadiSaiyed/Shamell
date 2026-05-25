import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../core/base_url.dart';
import '../../core/device_id.dart';
import '../../core/format.dart' show fmtCents;
import '../../core/http_error.dart';
import '../../core/l10n.dart';
import '../../core/session_cookie_store.dart';
import 'payments_card_style.dart';
import 'payments_idempotency.dart';
import 'payments_production_features.dart';
import 'payments_send.dart' show PayActionButton;

class PaymentsAdvancedPage extends StatefulWidget {
  final String baseUrl;
  final String walletId;
  final String deviceId;
  final String currency;
  final http.Client? client;

  const PaymentsAdvancedPage({
    super.key,
    required this.baseUrl,
    required this.walletId,
    required this.deviceId,
    required this.currency,
    this.client,
  });

  @override
  State<PaymentsAdvancedPage> createState() => _PaymentsAdvancedPageState();
}

class _PaymentsAdvancedPageState extends State<PaymentsAdvancedPage> {
  late final http.Client _http;
  late final bool _ownsHttpClient;

  final _holdAmountCtrl = TextEditingController();
  final _holdReasonCtrl = TextEditingController();
  final _recurringToCtrl = TextEditingController();
  final _recurringAmountCtrl = TextEditingController();
  final _recurringDaysCtrl = TextEditingController(text: '30');
  final _refundTxnCtrl = TextEditingController();
  final _refundAmountCtrl = TextEditingController();
  final _refundReasonCtrl = TextEditingController();
  final _merchantNameCtrl = TextEditingController();
  final _merchantCategoryCtrl = TextEditingController();
  final _miniAmountCtrl = TextEditingController();
  final _miniRefCtrl = TextEditingController();
  final _adminWalletCtrl = TextEditingController();
  final _kycLevelCtrl = TextEditingController(text: '1');

  Map<String, dynamic>? _limits;
  List<Map<String, dynamic>> _statement = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _holds = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _recurring = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _refunds = const <Map<String, dynamic>>[];
  Map<String, dynamic>? _merchant;
  Map<String, dynamic>? _miniIntent;
  Map<String, dynamic>? _risk;
  String _status = '';
  bool _busy = false;
  bool _freezeTarget = true;

  @override
  void initState() {
    super.initState();
    _ownsHttpClient = widget.client == null;
    _http = widget.client ?? shamellHttpClient();
    _adminWalletCtrl.text = widget.walletId;
    _refreshAll();
  }

  @override
  void dispose() {
    for (final ctrl in [
      _holdAmountCtrl,
      _holdReasonCtrl,
      _recurringToCtrl,
      _recurringAmountCtrl,
      _recurringDaysCtrl,
      _refundTxnCtrl,
      _refundAmountCtrl,
      _refundReasonCtrl,
      _merchantNameCtrl,
      _merchantCategoryCtrl,
      _miniAmountCtrl,
      _miniRefCtrl,
      _adminWalletCtrl,
      _kycLevelCtrl,
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
    final deviceId = (await getOrCreateStableDeviceId(
      baseUrlOverride: widget.baseUrl,
    ))
        .trim();
    headers['Idempotency-Key'] = newPaymentsIdempotencyKey(scope);
    headers['X-Device-ID'] = deviceId.isNotEmpty ? deviceId : widget.deviceId;
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

  Future<void> _refreshAll() async {
    await _run('Loaded.', _loadAllData);
  }

  Future<void> _loadAllData() async {
    _limits = Map<String, dynamic>.from(
      await _get(<String>['wallets', widget.walletId, 'limits']) as Map,
    );
    _statement = _maps(await _get(
      <String>['wallets', widget.walletId, 'statement'],
      query: const <String, String>{'limit': '100'},
    ).then((value) => value is Map ? value['txns'] : value));
    _holds = _maps(await _get(<String>['wallets', widget.walletId, 'holds']));
    _recurring = _maps(await _get(
      const <String>['recurring'],
      query: <String, String>{'wallet_id': widget.walletId},
    ));
    _refunds = _maps(await _get(
      const <String>['refunds'],
      query: <String, String>{'wallet_id': widget.walletId},
    ));
    try {
      final merchant = await _get(const <String>['merchant', 'profile']) as Map;
      _merchant = Map<String, dynamic>.from(merchant);
      _merchantNameCtrl.text = (_merchant?['merchant_name'] ?? '').toString();
      _merchantCategoryCtrl.text = (_merchant?['category'] ?? '').toString();
    } catch (_) {}
  }

  String _csvForStatement() {
    final rows = <List<String>>[
      const <String>[
        'id',
        'created_at',
        'kind',
        'from_wallet_id',
        'to_wallet_id',
        'amount_cents',
        'fee_cents',
        'meta',
      ],
      for (final txn in _statement)
        [
          '${txn['id'] ?? ''}',
          '${txn['created_at'] ?? ''}',
          '${txn['kind'] ?? ''}',
          '${txn['from_wallet_id'] ?? ''}',
          '${txn['to_wallet_id'] ?? ''}',
          '${txn['amount_cents'] ?? ''}',
          '${txn['fee_cents'] ?? ''}',
          '${txn['meta'] ?? ''}',
        ],
    ];
    String cell(String raw) => '"${raw.replaceAll('"', '""')}"';
    return rows.map((row) => row.map(cell).join(',')).join('\n');
  }

  Future<void> _copyStatementCsv() async {
    await Clipboard.setData(ClipboardData(text: _csvForStatement()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(L10n.of(context).copiedLabel)),
    );
  }

  Future<void> _copyStatementUrl(String format) async {
    final uri = _uri(
      <String>['wallets', widget.walletId, 'statement'],
      query: <String, String>{'limit': '100', 'format': format},
    );
    if (uri == null) return;
    await Clipboard.setData(ClipboardData(text: uri.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(L10n.of(context).copiedLabel)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.isArabic ? 'ميزات الدفع' : 'Payment features'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _refreshAll,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          )
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: shamellPaymentPagePadding(context),
          children: [
            _limitsCard(),
            _productionCard(),
            _statementCard(),
            _holdsCard(),
            _recurringCard(),
            _refundCard(),
            _merchantCard(),
            _miniIntentCard(),
            _adminCard(),
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

  Widget _sectionTitle(String text, IconData icon) {
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

  Widget _limitsCard() {
    final limits = _limits;
    return _card(
      children: [
        _sectionTitle(
            'KYC, limits & availability', Icons.verified_user_outlined),
        const SizedBox(height: 10),
        if (limits == null)
          const Text('No limits loaded.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip('KYC', '${limits['kyc_status']} / ${limits['kyc_level']}'),
              _chip(
                'Available',
                '${fmtCents((limits['available_balance_cents'] as num?)?.toInt() ?? 0)} ${limits['currency']}',
              ),
              _chip(
                  'Held',
                  fmtCents(
                      (limits['active_hold_cents'] as num?)?.toInt() ?? 0)),
              _chip('Frozen', '${limits['frozen'] == true}'),
            ],
          ),
      ],
    );
  }

  Widget _productionCard() {
    return _card(
      children: [
        _sectionTitle('Production payment suite', Icons.rocket_launch_outlined),
        const SizedBox(height: 10),
        Text(
          'Payment links, merchant checkout, webhooks, settlement, risk rules, disputes, KYC upload, FX rates, offline queue and audit timeline.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        PayActionButton(
          icon: Icons.open_in_new_outlined,
          label: 'Open production features',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PaymentsProductionFeaturesPage(
                  baseUrl: widget.baseUrl,
                  walletId: widget.walletId,
                  deviceId: widget.deviceId,
                  currency: widget.currency,
                  client: widget.client,
                ),
              ),
            );
          },
          radius: 16,
        ),
      ],
    );
  }

  Widget _statementCard() {
    return _card(
      children: [
        _sectionTitle(
            'Statements & receipts export', Icons.file_download_outlined),
        const SizedBox(height: 10),
        Text('${_statement.length} transactions loaded.'),
        const SizedBox(height: 8),
        PayActionButton(
          icon: Icons.copy,
          label: 'Copy CSV statement',
          onTap: _copyStatementCsv,
          radius: 16,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PayActionButton(
              icon: Icons.table_chart_outlined,
              label: 'Copy CSV link',
              onTap: () => _copyStatementUrl('csv'),
              radius: 16,
            ),
            PayActionButton(
              icon: Icons.picture_as_pdf_outlined,
              label: 'Copy PDF link',
              onTap: () => _copyStatementUrl('pdf'),
              radius: 16,
            ),
          ],
        ),
      ],
    );
  }

  Widget _holdsCard() {
    return _card(
      children: [
        _sectionTitle('Wallet holds', Icons.lock_clock_outlined),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _holdAmountCtrl,
                keyboardType: TextInputType.number,
                decoration:
                    InputDecoration(labelText: 'Amount (${widget.currency})'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _holdReasonCtrl,
                decoration: const InputDecoration(labelText: 'Reason'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        PayActionButton(
          icon: Icons.add,
          label: 'Create hold',
          onTap: () => _run('Hold created.', () async {
            await _post(
              <String>['wallets', widget.walletId, 'holds'],
              <String, Object?>{
                'amount_cents': _parseCents(_holdAmountCtrl.text),
                'reason': _holdReasonCtrl.text.trim(),
              },
              scope: 'wallet-hold',
            );
            await _loadAllData();
          }),
          radius: 16,
        ),
        const SizedBox(height: 8),
        for (final hold in _holds.take(4))
          _miniRow(
            '${hold['status']} · ${fmtCents((hold['amount_cents'] as num?)?.toInt() ?? 0)} ${hold['currency']}',
            '${hold['reason'] ?? ''}',
          ),
      ],
    );
  }

  Widget _recurringCard() {
    return _card(
      children: [
        _sectionTitle('Recurring payments', Icons.repeat_rounded),
        const SizedBox(height: 10),
        TextField(
          controller: _recurringToCtrl,
          decoration: const InputDecoration(labelText: 'Target wallet'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _recurringAmountCtrl,
                keyboardType: TextInputType.number,
                decoration:
                    InputDecoration(labelText: 'Amount (${widget.currency})'),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 110,
              child: TextField(
                controller: _recurringDaysCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Days'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        PayActionButton(
          icon: Icons.playlist_add,
          label: 'Create recurring payment',
          onTap: () => _run('Recurring payment created.', () async {
            await _post(
              const <String>['recurring'],
              <String, Object?>{
                'to_wallet_id': _recurringToCtrl.text.trim(),
                'amount_cents': _parseCents(_recurringAmountCtrl.text),
                'interval_days': int.tryParse(_recurringDaysCtrl.text) ?? 30,
              },
              scope: 'recurring-payment',
            );
            await _loadAllData();
          }),
          radius: 16,
        ),
        const SizedBox(height: 8),
        for (final item in _recurring.take(4))
          _miniRow(
            '${item['status']} · ${fmtCents((item['amount_cents'] as num?)?.toInt() ?? 0)} ${item['currency']}',
            'Next: ${item['next_run_at'] ?? '-'}',
          ),
      ],
    );
  }

  Widget _refundCard() {
    return _card(
      children: [
        _sectionTitle('Refunds & disputes', Icons.undo_rounded),
        const SizedBox(height: 10),
        TextField(
          controller: _refundTxnCtrl,
          decoration:
              const InputDecoration(labelText: 'Original transaction ID'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _refundAmountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Amount optional'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _refundReasonCtrl,
                decoration: const InputDecoration(labelText: 'Reason'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        PayActionButton(
          icon: Icons.report_problem_outlined,
          label: 'Request refund',
          onTap: () => _run('Refund requested.', () async {
            final amount = _parseCents(_refundAmountCtrl.text);
            await _post(
              const <String>['refunds'],
              <String, Object?>{
                'original_txn_id': _refundTxnCtrl.text.trim(),
                if (amount > 0) 'amount_cents': amount,
                'reason': _refundReasonCtrl.text.trim(),
              },
              scope: 'refund-request',
            );
            await _loadAllData();
          }),
          radius: 16,
        ),
        const SizedBox(height: 8),
        for (final refund in _refunds.take(4))
          _miniRow(
            '${refund['status']} · ${fmtCents((refund['amount_cents'] as num?)?.toInt() ?? 0)} ${refund['currency']}',
            '${refund['original_txn_id'] ?? ''}',
          ),
      ],
    );
  }

  Widget _merchantCard() {
    return _card(
      children: [
        _sectionTitle('Merchant dashboard', Icons.storefront_outlined),
        const SizedBox(height: 10),
        TextField(
          controller: _merchantNameCtrl,
          decoration: const InputDecoration(labelText: 'Merchant name'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _merchantCategoryCtrl,
          decoration: const InputDecoration(labelText: 'Category'),
        ),
        const SizedBox(height: 8),
        PayActionButton(
          icon: Icons.save_outlined,
          label: 'Save merchant profile',
          onTap: () => _run('Merchant profile saved.', () async {
            _merchant = Map<String, dynamic>.from(
              await _post(
                const <String>['merchant', 'profile'],
                <String, Object?>{
                  'merchant_name': _merchantNameCtrl.text.trim(),
                  'category': _merchantCategoryCtrl.text.trim(),
                },
                scope: 'merchant-profile',
              ) as Map,
            );
          }),
          radius: 16,
        ),
        if (_merchant != null) ...[
          const SizedBox(height: 8),
          _miniRow('${_merchant!['merchant_name']}', '${_merchant!['status']}'),
        ],
      ],
    );
  }

  Widget _miniIntentCard() {
    return _card(
      children: [
        _sectionTitle('Mini Program Payment SDK', Icons.extension_outlined),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _miniAmountCtrl,
                keyboardType: TextInputType.number,
                decoration:
                    InputDecoration(labelText: 'Amount (${widget.currency})'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _miniRefCtrl,
                decoration: const InputDecoration(labelText: 'Reference'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        PayActionButton(
          icon: Icons.api_outlined,
          label: 'Create payment intent',
          onTap: () => _run('Payment intent created.', () async {
            _miniIntent = Map<String, dynamic>.from(
              await _post(
                const <String>['mini', 'payment-intents'],
                <String, Object?>{
                  'amount_cents': _parseCents(_miniAmountCtrl.text),
                  'currency': widget.currency,
                  'merchant_reference': _miniRefCtrl.text.trim(),
                  'metadata': <String, Object?>{'source': 'advanced_page'},
                },
                scope: 'mini-payment-intent',
              ) as Map,
            );
          }),
          radius: 16,
        ),
        if (_miniIntent != null) ...[
          const SizedBox(height: 8),
          _miniRow('${_miniIntent!['id']}', '${_miniIntent!['status']}'),
        ],
      ],
    );
  }

  Widget _adminCard() {
    return _card(
      children: [
        _sectionTitle(
            'Admin: KYC, freeze & risk', Icons.admin_panel_settings_outlined),
        const SizedBox(height: 10),
        TextField(
          controller: _adminWalletCtrl,
          decoration: const InputDecoration(labelText: 'Target wallet'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _freezeTarget,
                title: const Text('Freeze target'),
                onChanged: (value) => setState(() => _freezeTarget = value),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 96,
              child: TextField(
                controller: _kycLevelCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'KYC'),
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PayActionButton(
              icon: Icons.block_outlined,
              label: 'Apply freeze',
              onTap: () => _run('Wallet control updated.', () async {
                await _post(
                  const <String>['admin', 'wallet-controls'],
                  <String, Object?>{
                    'wallet_id': _adminWalletCtrl.text.trim(),
                    'frozen': _freezeTarget,
                    'reason': 'advanced_page',
                  },
                  scope: 'admin-wallet-control',
                );
                await _loadAllData();
              }),
              radius: 16,
            ),
            PayActionButton(
              icon: Icons.verified_outlined,
              label: 'Update KYC',
              onTap: () => _run('KYC updated.', () async {
                await _post(
                  const <String>['admin', 'kyc'],
                  <String, Object?>{
                    'wallet_id': _adminWalletCtrl.text.trim(),
                    'kyc_level': int.tryParse(_kycLevelCtrl.text) ?? 1,
                  },
                  scope: 'admin-kyc',
                );
                await _loadAllData();
              }),
              radius: 16,
            ),
            PayActionButton(
              icon: Icons.shield_outlined,
              label: 'Load risk',
              onTap: () => _run('Risk loaded.', () async {
                _risk = Map<String, dynamic>.from(
                  await _get(const <String>['admin', 'risk', 'metrics']) as Map,
                );
              }),
              radius: 16,
            ),
          ],
        ),
        if (_risk != null) ...[
          const SizedBox(height: 8),
          _miniRow(
            'Risk',
            '24h txns: ${_risk!['txn_24h_count']} · alerts: ${(_risk!['alerts'] as List?)?.join(', ') ?? '-'}',
          ),
        ],
      ],
    );
  }

  Widget _card({required List<Widget> children}) {
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

  Widget _chip(String label, String value) {
    return ShamellPaymentMetricChip(
      label: label,
      value: value,
      icon: Icons.check_circle_outline,
    );
  }

  Widget _miniRow(String title, String subtitle) {
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
}
