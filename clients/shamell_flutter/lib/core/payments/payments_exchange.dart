import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/app_activity.dart';
import '../../core/base_url.dart';
import '../../core/device_id.dart';
import '../../core/format.dart' show fmtCents;
import '../../core/http_error.dart';
import '../../core/l10n.dart';
import '../../core/session_cookie_store.dart';
import 'payments_card_style.dart';
import 'payments_idempotency.dart';
import 'payments_send.dart' show PayActionButton;
import 'supported_currencies.dart';

class PaymentExchangePage extends StatefulWidget {
  final String baseUrl;
  final String fromWalletId;
  final String walletCurrency;
  final http.Client? client;

  const PaymentExchangePage({
    super.key,
    required this.baseUrl,
    required this.fromWalletId,
    required this.walletCurrency,
    this.client,
  });

  @override
  State<PaymentExchangePage> createState() => _PaymentExchangePageState();
}

class _PaymentExchangePageState extends State<PaymentExchangePage> {
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _rateCtrl = TextEditingController(text: '1.00');
  final TextEditingController _feeBpsCtrl = TextEditingController(text: '50');
  final TextEditingController _targetWalletCtrl = TextEditingController();

  late final http.Client _http;
  late final bool _ownsHttpClient;
  late String _fromCurrency;
  late String _toCurrency;
  Map<String, dynamic>? _quote;
  String _quotePayload = '';
  String _status = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _http = widget.client ?? shamellHttpClient();
    _ownsHttpClient = widget.client == null;
    _fromCurrency = shamellNormalizeWalletCurrency(widget.walletCurrency);
    _toCurrency = shamellSupportedWalletCurrencies
        .map((currency) => currency.code)
        .firstWhere(
          (code) => code != _fromCurrency,
          orElse: () => shamellDefaultWalletCurrency,
        );
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _rateCtrl.dispose();
    _feeBpsCtrl.dispose();
    _targetWalletCtrl.dispose();
    if (_ownsHttpClient) _http.close();
    super.dispose();
  }

  Uri? _apiUri(List<String> pathSegments) {
    return secureApiChildUri(
      baseUrl: widget.baseUrl,
      pathSegments: <String>['payments', ...pathSegments],
    );
  }

  Future<Map<String, String>> _mutationHeaders(String scope) async {
    final headers = await shamellSessionHeadersForBaseUrl(
      widget.baseUrl,
      json: true,
    );
    final deviceId = (await getOrCreateStableDeviceId(
      baseUrlOverride: widget.baseUrl,
    ))
        .trim();
    headers['Idempotency-Key'] = newPaymentsIdempotencyKey(scope);
    headers['X-Device-ID'] = deviceId;
    return headers;
  }

  int _parseMajorToCents(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    final major = double.tryParse(normalized);
    if (major == null || !major.isFinite || major <= 0) return 0;
    return (major * 100).round();
  }

  double _parseRate() {
    final value = double.tryParse(_rateCtrl.text.trim().replaceAll(',', '.'));
    if (value == null || !value.isFinite || value <= 0) return 0;
    return value;
  }

  int _parseRateBps() {
    return (_parseRate() * 10000).round();
  }

  int _parseFeeBps() {
    final value = int.tryParse(_feeBpsCtrl.text.trim()) ?? 0;
    return value.clamp(0, 2000).toInt();
  }

  int _quoteTargetCents() {
    final sourceCents = _parseMajorToCents(_amountCtrl.text);
    final rate = _parseRate();
    if (sourceCents <= 0 || rate <= 0) return 0;
    final feeFactor = (10000 - _parseFeeBps()) / 10000.0;
    return ((sourceCents * rate) * feeFactor).round();
  }

  String _quotePayloadFor(Map<String, dynamic> quote) {
    return Uri(
      scheme: 'shamell',
      host: 'exchange',
      queryParameters: <String, String>{
        'v': '2',
        'quote_id': (quote['id'] ?? '').toString(),
        'from_wallet_id': (quote['from_wallet_id'] ?? '').toString(),
        'to_wallet_id': (quote['to_wallet_id'] ?? '').toString(),
        'from_currency': (quote['from_currency'] ?? '').toString(),
        'to_currency': (quote['to_currency'] ?? '').toString(),
        'amount_cents': (quote['amount_cents'] ?? '').toString(),
        'expected_amount_cents':
            (quote['expected_amount_cents'] ?? '').toString(),
        'rate_bps': (quote['rate_bps'] ?? '').toString(),
        'fee_bps': (quote['fee_bps'] ?? '').toString(),
        'status': (quote['status'] ?? '').toString(),
        'expires_at': (quote['expires_at'] ?? '').toString(),
      },
    ).toString();
  }

  Future<Map<String, dynamic>> _post(
    List<String> path,
    Map<String, Object?> body, {
    required String scope,
  }) async {
    final uri = _apiUri(path);
    if (uri == null) throw StateError('Invalid server URL');
    final response = await _http.post(
      uri,
      headers: await _mutationHeaders(scope),
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(response.body);
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<void> _run(String success, Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '...';
    });
    try {
      await action();
      if (!mounted) return;
      setState(() => _status = success);
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

  Future<void> _createQuote() async {
    final l = L10n.of(context);
    final sourceCents = _parseMajorToCents(_amountCtrl.text);
    final targetCents = _quoteTargetCents();
    final rateBps = _parseRateBps();
    final targetWalletId = _targetWalletCtrl.text.trim();
    if (sourceCents <= 0 || targetCents <= 0 || rateBps <= 0) {
      setState(() {
        _status = l.isArabic
            ? 'أدخل مبلغاً وسعر صرف صالحين.'
            : 'Enter a valid amount and exchange rate.';
        _quotePayload = '';
      });
      return;
    }
    if (targetWalletId.isEmpty || targetWalletId == widget.fromWalletId) {
      setState(() {
        _status = l.isArabic
            ? 'أدخل محفظة هدف مختلفة.'
            : 'Enter a different target wallet.';
        _quotePayload = '';
      });
      return;
    }
    await _run(l.isArabic ? 'تم إنشاء عرض الصرف.' : 'Exchange quote created.',
        () async {
      final quote = await _post(
        const <String>['exchange', 'quotes'],
        <String, Object?>{
          'to_wallet_id': targetWalletId,
          'amount_cents': sourceCents,
          'expected_amount_cents': targetCents,
          'rate_bps': rateBps,
          'fee_bps': _parseFeeBps(),
          'expires_in_secs': 300,
        },
        scope: 'exchange-quote',
      );
      shamellRecordAppActivity(
        baseUrl: widget.baseUrl,
        eventType: 'payment_exchange_quote_created',
        moduleId: 'payments',
        action: 'exchange_quote_created',
        metadata: <String, Object?>{
          'quote_id': quote['id'],
          'from_currency': quote['from_currency'],
          'to_currency': quote['to_currency'] ?? _toCurrency,
          'amount_cents': sourceCents,
          'expected_amount_cents': targetCents,
          'fee_bps': _parseFeeBps(),
        },
        client: widget.client,
      );
      _quote = quote;
      _quotePayload = _quotePayloadFor(quote);
    });
  }

  Future<void> _executeQuote() async {
    final quoteId = (_quote?['id'] ?? '').toString().trim();
    if (quoteId.isEmpty) return;
    final l = L10n.of(context);
    await _run(l.isArabic ? 'تم تنفيذ الصرف.' : 'Exchange executed.', () async {
      final quote = await _post(
        <String>['exchange', 'quotes', quoteId, 'execute'],
        const <String, Object?>{},
        scope: 'exchange-execute',
      );
      shamellRecordAppActivity(
        baseUrl: widget.baseUrl,
        eventType: 'payment_exchange_quote_executed',
        moduleId: 'payments',
        action: 'exchange_quote_executed',
        metadata: <String, Object?>{
          'quote_id': quote['id'],
          'debit_txn_id': quote['debit_txn_id'],
          'credit_txn_id': quote['credit_txn_id'],
        },
        client: widget.client,
      );
      _quote = quote;
      _quotePayload = _quotePayloadFor(quote);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final sourceCents = _parseMajorToCents(_amountCtrl.text);
    final targetCents = _quoteTargetCents();
    final quote = _quote;
    final currencies = shamellSupportedWalletCurrencies
        .map((currency) => currency.code)
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.isArabic ? 'الصرف' : 'Exchange'),
      ),
      body: SafeArea(
        child: ListView(
          padding: shamellPaymentPagePadding(context),
          children: [
            ShamellPaymentCardSurface(
              tone: ShamellPaymentCardTone.hero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.isArabic
                        ? 'صرف متعدد العملات'
                        : 'Multi-currency exchange',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.fromWalletId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .70),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ShamellPaymentMetricChip(
                        label: l.isArabic ? 'من' : 'From',
                        value: quote?['from_currency']?.toString() ??
                            _fromCurrency,
                        icon: Icons.account_balance_wallet_outlined,
                      ),
                      ShamellPaymentMetricChip(
                        label: l.isArabic ? 'إلى' : 'To',
                        value: quote?['to_currency']?.toString() ?? _toCurrency,
                        icon: Icons.currency_exchange,
                      ),
                      ShamellPaymentMetricChip(
                        label: l.isArabic ? 'الصافي' : 'Net',
                        value: targetCents > 0
                            ? '${fmtCents(targetCents)} $_toCurrency'
                            : '-',
                        icon: Icons.trending_up_rounded,
                      ),
                      if (quote != null)
                        ShamellPaymentMetricChip(
                          label: 'Status',
                          value: (quote['status'] ?? '').toString(),
                          icon: Icons.verified_outlined,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ShamellPaymentCardSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _targetWalletCtrl,
                    decoration: InputDecoration(
                      labelText: l.isArabic ? 'محفظة الهدف' : 'Target wallet',
                    ),
                    onChanged: (_) {
                      setState(() {
                        _quote = null;
                        _quotePayload = '';
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _toCurrency,
                    decoration: InputDecoration(
                      labelText: l.isArabic ? 'عملة الوجهة' : 'Target currency',
                    ),
                    items: currencies
                        .where((currency) => currency != _fromCurrency)
                        .map(
                          (currency) => DropdownMenuItem<String>(
                            value: currency,
                            child: Text(currency),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _toCurrency = value;
                        _quote = null;
                        _quotePayload = '';
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _amountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: l.isArabic
                          ? 'المبلغ ($_fromCurrency)'
                          : 'Amount ($_fromCurrency)',
                    ),
                    onChanged: (_) {
                      setState(() {
                        _quote = null;
                        _quotePayload = '';
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _rateCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: l.isArabic
                          ? 'سعر الصرف ($_toCurrency لكل $_fromCurrency)'
                          : 'Rate ($_toCurrency per $_fromCurrency)',
                    ),
                    onChanged: (_) {
                      setState(() {
                        _quote = null;
                        _quotePayload = '';
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _feeBpsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l.isArabic ? 'الرسوم bps' : 'Fee bps',
                    ),
                    onChanged: (_) {
                      setState(() {
                        _quote = null;
                        _quotePayload = '';
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  if (sourceCents > 0)
                    Text(
                      '${fmtCents(sourceCents)} $_fromCurrency -> ${fmtCents(targetCents)} $_toCurrency',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      PayActionButton(
                        icon: Icons.price_check_outlined,
                        label: l.isArabic ? 'إنشاء عرض' : 'Create quote',
                        onTap: _busy ? () {} : _createQuote,
                        radius: 16,
                      ),
                      if (quote != null && quote['status'] == 'quoted')
                        PayActionButton(
                          icon: Icons.done_all_outlined,
                          label: l.isArabic ? 'تنفيذ' : 'Execute',
                          onTap: _busy ? () {} : _executeQuote,
                          radius: 16,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 12),
              ShamellPaymentCardSurface(
                tone: ShamellPaymentCardTone.soft,
                child: Text(_status),
              ),
            ],
            if (_quotePayload.isNotEmpty) ...[
              const SizedBox(height: 12),
              ShamellPaymentCardSurface(
                tone: ShamellPaymentCardTone.soft,
                child: Column(
                  children: [
                    SelectableText(
                      _quotePayload,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    QrImageView(data: _quotePayload, size: 220),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _quotePayload));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l.isArabic
                                ? 'تم نسخ عرض الصرف.'
                                : 'Exchange quote copied.'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy),
                      label: Text(l.isArabic ? 'نسخ' : 'Copy'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
