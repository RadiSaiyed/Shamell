import 'dart:async';
import 'dart:convert';
import 'package:shamell_flutter/core/session_cookie_store.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shamell_flutter/core/base_url.dart';
import 'package:shamell_flutter/core/capabilities.dart';
import 'package:shamell_flutter/core/http_error.dart';
import '../../../main.dart' show LoginPage;

import '../../core/app_activity.dart';
import '../../core/app_sounds.dart';
import '../../core/device_binding_reauth.dart';
import '../../core/device_id.dart';
import '../../core/format.dart' show fmtCents;
import '../../core/history_page.dart';
import '../../core/l10n.dart';
import '../../core/shamell_loading_shimmer.dart';
import '../../core/ui_kit.dart';
import '../../core/perf.dart';
import '../../core/design_tokens.dart';
import '../../core/safe_set_state.dart';
import 'payments_idempotency.dart';
import 'payments_local_store.dart';
import 'payments_card_style.dart';

const Duration _paymentsBillsRequestTimeout = Duration(seconds: 15);

class BillsPage extends StatefulWidget {
  final String baseUrl;
  final String walletId;
  final String deviceId;
  final http.Client? client;
  const BillsPage(
    this.baseUrl,
    this.walletId,
    this.deviceId, {
    super.key,
    this.client,
  });

  @override
  State<BillsPage> createState() => _BillsPageState();
}

class _BillsPageState extends State<BillsPage>
    with SafeSetStateMixin<BillsPage> {
  final _amountCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _billerAccountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _selectedBiller = 'electricity';
  bool _loading = false;
  String _banner = '';
  bool _bannerError = false;
  int? _walletBalance;
  String _curSym = 'SYP';
  List<Map<String, dynamic>> _templates = [];
  List<Map<String, dynamic>> _remoteBillers = [];
  int _modeIndex = 0; // 0 = pay bill, 1 = bill history
  bool _paymentsBillsEnabled = false;
  bool _capabilitiesLoaded = false;

  final _billers = const [
    {
      'code': 'electricity',
      'label_en': 'Electricity',
      'label_ar': 'الكهرباء',
    },
    {
      'code': 'mobile',
      'label_en': 'Mobile top‑up',
      'label_ar': 'شحن الجوال',
    },
    {
      'code': 'internet',
      'label_en': 'Internet',
      'label_ar': 'الإنترنت',
    },
    {
      'code': 'water',
      'label_en': 'Water',
      'label_ar': 'المياه',
    },
  ];

  List<Map<String, dynamic>> _effectiveBillers() {
    if (_remoteBillers.isNotEmpty) return _remoteBillers;
    return _billers;
  }

  IconData _billerIcon(String code) {
    switch (code) {
      case 'electricity':
        return Icons.bolt_outlined;
      case 'mobile':
        return Icons.smartphone_outlined;
      case 'internet':
        return Icons.wifi_outlined;
      case 'water':
        return Icons.water_drop_outlined;
      default:
        return Icons.receipt_long_outlined;
    }
  }

  Map<String, dynamic>? _selectedBillerConfig() {
    try {
      return _effectiveBillers().firstWhere(
        (b) => (b['code'] ?? '') == _selectedBiller,
        orElse: () => {},
      );
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _accountCtrl.dispose();
    _billerAccountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final caps = await ShamellCapabilities.loadForBaseUrl(widget.baseUrl);
      _paymentsBillsEnabled = caps.paymentsBills;
    } catch (_) {
      _paymentsBillsEnabled = false;
    } finally {
      _capabilitiesLoaded = true;
    }
    if (_paymentsBillsEnabled) {
      await _loadWallet();
      await _loadBillers();
      await _loadTemplates();
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<Map<String, String>> _hdr() async {
    final stable = (await loadStableDeviceId(
              baseUrlOverride: widget.baseUrl,
            ) ??
            '')
        .trim();
    final deviceId = stable.isNotEmpty ? stable : widget.deviceId.trim();
    return shamellSessionHeadersForBaseUrl(
      widget.baseUrl,
      json: true,
      extra:
          deviceId.isEmpty ? null : <String, String>{'X-Device-ID': deviceId},
    );
  }

  Uri? _paymentsUri({
    required List<String> pathSegments,
    Map<String, String>? queryParameters,
  }) {
    return secureApiChildUri(
      baseUrl: widget.baseUrl,
      pathSegments: pathSegments,
      queryParameters: queryParameters,
    );
  }

  String _invalidServerUrlMessage() {
    final isArabic = L10n.of(context).isArabic;
    return isArabic ? 'عنوان الخادم غير صالح.' : 'Invalid server URL.';
  }

  Future<void> _loadWallet() async {
    final wid = widget.walletId;
    if (wid.isEmpty) return;
    final uri = _paymentsUri(pathSegments: <String>['wallets', wid]);
    if (uri == null) return;
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    try {
      final r = await httpClient
          .get(uri, headers: await _hdr())
          .timeout(_paymentsBillsRequestTimeout);
      if (!mounted) return;
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final bal = j['balance_cents'];
        final cur = (j['currency'] ?? '').toString();
        setState(() {
          _walletBalance =
              bal is int ? bal : (bal is num ? bal.toInt() : _walletBalance);
          if (cur.isNotEmpty) _curSym = cur;
        });
      } else if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: r.statusCode,
        rawBody: r.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
    } catch (e) {
      if (!mounted) return;
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
    } finally {
      if (closeClient) httpClient.close();
    }
  }

  Future<void> _loadBillers() async {
    final uri =
        _paymentsUri(pathSegments: const <String>['payments', 'billers']);
    if (uri == null) return;
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    try {
      final r = await httpClient
          .get(uri, headers: await _hdr())
          .timeout(_paymentsBillsRequestTimeout);
      if (!mounted) return;
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is List) {
          final list = <Map<String, dynamic>>[];
          for (final e in body) {
            if (e is Map<String, dynamic>) list.add(e);
          }
          if (mounted && list.isNotEmpty) {
            setState(() {
              _remoteBillers = list;
              // Ensure selected biller exists; otherwise pick first.
              if (!_remoteBillers.any((b) =>
                  (b['code'] ?? '') == _selectedBiller &&
                  (b['code'] ?? '').toString().isNotEmpty)) {
                final first = _remoteBillers.first;
                final c = (first['code'] ?? '').toString();
                if (c.isNotEmpty) {
                  _selectedBiller = c;
                }
              }
              // If server configured a wallet for the selected biller,
              // pre-fill the biller wallet field so endusers do not have
              // to look it up manually.
              final cfg = _selectedBillerConfig();
              final wid = (cfg?['wallet_id'] ?? '').toString().trim();
              if (wid.isNotEmpty) {
                _billerAccountCtrl.text = wid;
              }
            });
          }
        }
      } else if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: r.statusCode,
        rawBody: r.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
    } catch (e) {
      if (!mounted) return;
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
    } finally {
      if (closeClient) httpClient.close();
    }
  }

  Future<void> _loadTemplates() async {
    try {
      final arr = await loadBillTemplateEntries(
        baseUrlOverride: widget.baseUrl,
      );
      final list = <Map<String, dynamic>>[];
      for (final s in arr) {
        try {
          final m = jsonDecode(s);
          if (m is Map<String, dynamic> &&
              (m['biller_code'] ?? '').toString().isNotEmpty) {
            list.add(m);
          }
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _templates = list;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveTemplates() async {
    try {
      final list = _templates.map((m) => jsonEncode(m)).toList(growable: false);
      await saveBillTemplateEntries(
        list,
        baseUrlOverride: widget.baseUrl,
      );
    } catch (_) {}
  }

  List<Map<String, dynamic>> _templatesForSelected() {
    return _templates
        .where((t) => (t['biller_code'] ?? '') == _selectedBiller)
        .toList();
  }

  Future<void> _saveCurrentAsTemplate() async {
    final l = L10n.of(context);
    final acct = _accountCtrl.text.trim();
    final billerWallet = _billerAccountCtrl.text.trim();
    if (acct.isEmpty || billerWallet.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.payCheckInputs),
      ));
      return;
    }
    final labelCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: ShamellPaymentCardSurface(
            tone: ShamellPaymentCardTone.hero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.isArabic ? 'حفظ كقالب فاتورة' : 'Save as bill template',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: labelCtrl,
                  decoration: InputDecoration(
                    labelText: l.isArabic ? 'اسم القالب' : 'Template name',
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ShamellPaymentPillButton(
                        label: Text(l.shamellDialogCancel),
                        icon: const Icon(Icons.close_rounded, size: 16),
                        onPressed: () => Navigator.of(ctx).pop(false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PrimaryButton(
                        label: l.shamellDialogOk,
                        onPressed: () => Navigator.of(ctx).pop(true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (ok != true) return;
    final label = labelCtrl.text.trim();
    if (label.isEmpty) return;
    final tpl = <String, dynamic>{
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'biller_code': _selectedBiller,
      'label': label,
      'account': acct,
      'biller_wallet': billerWallet,
      'note': _noteCtrl.text.trim(),
    };
    setState(() {
      _templates.removeWhere((t) =>
          (t['biller_code'] ?? '') == _selectedBiller &&
          (t['label'] ?? '') == label);
      _templates.insert(0, tpl);
      while (_templates.length > 16) {
        _templates.removeLast();
      }
    });
    await _saveTemplates();
  }

  void _applyTemplate(Map<String, dynamic> tpl) {
    final acct = (tpl['account'] ?? '').toString();
    final bw = (tpl['biller_wallet'] ?? '').toString();
    final note = (tpl['note'] ?? '').toString();
    setState(() {
      _accountCtrl.text = acct;
      // Only apply the biller wallet from the template when the
      // currently selected biller does not have a fixed wallet
      // configured server-side. This keeps operator-configured
      // biller wallets authoritative, while still allowing custom
      // wallets for manual billers.
      final cfg = _selectedBillerConfig() ?? {};
      final fixedWallet = (cfg['wallet_id'] ?? '').toString().trim();
      final hasPreset = fixedWallet.isNotEmpty;
      if (!hasPreset || _billerAccountCtrl.text.trim().isEmpty) {
        _billerAccountCtrl.text = bw;
      }
      if (note.isNotEmpty) {
        _noteCtrl.text = note;
      }
    });
  }

  Future<void> _payBill() async {
    final l = L10n.of(context);
    final wid = widget.walletId;
    if (wid.isEmpty) {
      setState(() {
        _bannerError = true;
        _banner = l.isArabic
            ? 'الرجاء إعداد المحفظة أولاً'
            : 'Please set up your wallet first';
      });
      return;
    }
    final amtStr = _amountCtrl.text.trim().replaceAll(',', '.');
    final amtMajor = double.tryParse(amtStr) ?? 0;
    final acct = _accountCtrl.text.trim();
    final billerWallet = _billerAccountCtrl.text.trim();
    if (amtMajor <= 0 || billerWallet.isEmpty) {
      setState(() {
        _bannerError = true;
        _banner = l.payCheckInputs;
      });
      return;
    }
    final note = _noteCtrl.text.trim();
    final code = _selectedBiller;
    final uri =
        _paymentsUri(pathSegments: const <String>['payments', 'bills', 'pay']);
    if (uri == null) {
      setState(() {
        _bannerError = true;
        _banner = _invalidServerUrlMessage();
      });
      return;
    }
    final ikey = newPaymentsIdempotencyKey('bill');
    final payload = <String, Object?>{
      'from_wallet_id': wid,
      'to_wallet_id': billerWallet,
      'biller_code': code,
      'amount': double.parse(amtMajor.toStringAsFixed(2)),
      if (acct.isNotEmpty) 'reference': acct,
      if (note.isNotEmpty) 'note': note,
    };
    setState(() {
      _loading = true;
      _banner = '';
    });
    final t0 = DateTime.now().millisecondsSinceEpoch;
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    try {
      final headers = await _hdr();
      headers['Idempotency-Key'] = ikey;
      final resp = await httpClient
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(_paymentsBillsRequestTimeout);
      if (!mounted) return;
      final dt = DateTime.now().millisecondsSinceEpoch - t0;
      Perf.sample('bills_pay_ms', dt);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        unawaited(ShamellSoundEffects.play(ShamellSoundEffect.paymentSent));
        shamellRecordAppActivity(
          baseUrl: widget.baseUrl,
          eventType: 'payment_bill_paid',
          moduleId: 'payments',
          action: 'bill_paid',
          metadata: <String, Object?>{
            'amount_major': amtMajor,
            'biller_code': code,
          },
          client: httpClient,
        );
        await _loadWallet();
        setState(() {
          _bannerError = false;
          _banner =
              l.isArabic ? 'تم دفع الفاتورة بنجاح' : 'Bill paid successfully';
        });
      } else {
        if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
          context,
          statusCode: resp.statusCode,
          rawBody: resp.body,
          loginPageBuilder: (_) => const LoginPage(),
        )) {
          return;
        }
        final msg = sanitizeHttpError(
          statusCode: resp.statusCode,
          rawBody: resp.body,
          isArabic: l.isArabic,
        );
        setState(() {
          _bannerError = true;
          _banner = msg;
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      setState(() {
        _bannerError = true;
        _banner = sanitizeExceptionForUi(error: e, isArabic: l.isArabic);
      });
    } finally {
      if (closeClient) httpClient.close();
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .98)
        : (Colors.grey[100] ?? Colors.white);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.isArabic ? 'الفواتير' : 'Bills'),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      backgroundColor: bgColor,
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l = L10n.of(context);
    if (!_capabilitiesLoaded) {
      return const ShamellSkeletonList(itemCount: 5);
    }
    if (!_paymentsBillsEnabled) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ShamellPaymentCardSurface(
              tone: ShamellPaymentCardTone.hero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 40,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: .70),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l.isArabic
                        ? 'الفواتير غير متاحة على هذا الخادم.'
                        : 'Bills are unavailable on this server.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l.isArabic
                        ? 'تم إخفاء هذا التدفق لأن واجهات الفوترة غير مفعلة في الواجهة الخلفية الحالية.'
                        : 'This flow is hidden because bill-payment APIs are not enabled on the current backend.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: .72),
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: ShamellPaymentCardSurface(
            tone: ShamellPaymentCardTone.soft,
            padding: const EdgeInsets.all(6),
            child: _buildModeSwitcher(context),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: AnimatedSwitcher(
            duration: Tokens.motionBase,
            child: _modeIndex == 0
                ? _buildBillForm(context)
                : _buildBillHistory(context),
          ),
        ),
      ],
    );
  }

  Widget _buildModeSwitcher(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color cardBg = theme.cardColor;
    final Color borderColor =
        theme.dividerColor.withValues(alpha: isDark ? .35 : .25);
    final Color accent = Tokens.colorPayments;
    final labels = [
      l.isArabic ? 'دفع فاتورة' : 'Pay bills',
      l.isArabic ? 'سجل الفواتير' : 'Bill history',
    ];
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: List.generate(labels.length, (index) {
          final bool selected = _modeIndex == index;
          final Color bg = selected
              ? (isDark
                  ? accent.withValues(alpha: .22)
                  : accent.withValues(alpha: .10))
              : Colors.transparent;
          final Color fg = selected
              ? accent
              : theme.colorScheme.onSurface.withValues(alpha: .80);
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (_modeIndex == index) return;
                setState(() {
                  _modeIndex = index;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  labels[index],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: fg,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildBillForm(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final billers = _effectiveBillers();
    final walletLabel = widget.walletId.isEmpty
        ? (l.isArabic ? 'غير مُعدّة' : 'Not set')
        : widget.walletId.length > 16
            ? '${widget.walletId.substring(0, 8)}…${widget.walletId.substring(widget.walletId.length - 4)}'
            : widget.walletId;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_banner.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ShamellPaymentCardSurface(
              tone: ShamellPaymentCardTone.soft,
              accent: _bannerError
                  ? Theme.of(context).colorScheme.error
                  : Tokens.colorPayments,
              child: Text(
                _banner,
                style: TextStyle(
                  color: _bannerError
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: .80),
                  height: 1.35,
                ),
              ),
            ),
          ),
        ShamellPaymentCardSurface(
          tone: ShamellPaymentCardTone.hero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.isArabic ? 'محفظتك' : 'Your wallet',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ShamellPaymentMetricChip(
                    label: l.isArabic ? 'المحفظة' : 'Wallet',
                    value: walletLabel,
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                  ShamellPaymentMetricChip(
                    label: l.isArabic ? 'الرصيد' : 'Balance',
                    value: _walletBalance == null
                        ? '…'
                        : '${fmtCents(_walletBalance!)} $_curSym',
                    icon: Icons.payments_outlined,
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
              Text(
                l.isArabic ? 'نوع الفاتورة' : 'Bill type',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: billers.map((b) {
                  final code = (b['code'] ?? '').toString();
                  if (code.isEmpty) return const SizedBox.shrink();
                  final isSelected = code == _selectedBiller;
                  final label = l.isArabic
                      ? (b['label_ar'] ?? b['label_en'] ?? '').toString()
                      : (b['label_en'] ?? b['label_ar'] ?? '').toString();
                  return SizedBox(
                    width: 96,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        if (_selectedBiller == code) return;
                        setState(() {
                          _selectedBiller = code;
                          final biller = _selectedBillerConfig() ?? {};
                          final wid =
                              (biller['wallet_id'] ?? '').toString().trim();
                          if (wid.isNotEmpty) {
                            _billerAccountCtrl.text = wid;
                          }
                        });
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Tokens.colorPayments.withValues(alpha: .16)
                                  : theme.colorScheme.surface
                                      .withValues(alpha: .90),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: isSelected
                                    ? Tokens.colorPayments
                                        .withValues(alpha: .90)
                                    : theme.dividerColor.withValues(alpha: .25),
                              ),
                            ),
                            child: Icon(
                              _billerIcon(code),
                              size: 22,
                              color: isSelected
                                  ? Tokens.colorPayments
                                  : theme.colorScheme.onSurface
                                      .withValues(alpha: .80),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(growable: false),
              ),
              const SizedBox(height: 10),
              Builder(builder: (ctx) {
                final cfg = _selectedBillerConfig() ?? {};
                final label = l.isArabic
                    ? (cfg['label_ar'] ?? cfg['label_en'] ?? '').toString()
                    : (cfg['label_en'] ?? cfg['label_ar'] ?? '').toString();
                final wid = (cfg['wallet_id'] ?? '').toString().trim();
                if (label.isEmpty && wid.isEmpty) {
                  return const SizedBox.shrink();
                }
                final text = wid.isEmpty
                    ? (l.isArabic ? 'الدفع إلى: $label' : 'Paying to: $label')
                    : (l.isArabic
                        ? 'الدفع إلى $label · المحفظة: $wid'
                        : 'Paying to $label · wallet: $wid');
                return Text(
                  text,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: .70),
                      ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ShamellPaymentCardSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.isArabic ? 'تفاصيل الفاتورة' : 'Bill details',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Builder(builder: (ctx) {
                final tpls = _templatesForSelected();
                if (tpls.isEmpty) return const SizedBox(height: 12);
                return Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: tpls.map((t) {
                      final label = (t['label'] ?? '').toString();
                      return ShamellPaymentPillButton(
                        label: Text(
                          label.isEmpty ? 'Template' : label,
                          overflow: TextOverflow.ellipsis,
                        ),
                        icon: const Icon(Icons.bookmark_outline, size: 16),
                        onPressed: () => _applyTemplate(t),
                      );
                    }).toList(growable: false),
                  ),
                );
              }),
              const SizedBox(height: 12),
              TextField(
                controller: _accountCtrl,
                decoration: InputDecoration(
                  labelText: l.isArabic
                      ? 'رقم الحساب أو الهاتف'
                      : 'Account / phone reference',
                ),
              ),
              const SizedBox(height: 8),
              Builder(builder: (ctx) {
                final cfg = _selectedBillerConfig() ?? {};
                final fixedWallet = (cfg['wallet_id'] ?? '').toString().trim();
                final hasPreset = fixedWallet.isNotEmpty;
                final helper = hasPreset
                    ? (l.isArabic
                        ? 'محفظة مزود الخدمة مُعدّة مسبقاً؛ لا يمكن تعديلها.'
                        : 'Provider wallet is preconfigured and cannot be edited.')
                    : (l.isArabic
                        ? 'المحفظة التي تستلم المدفوعات (مزود الكهرباء أو الاتصالات).'
                        : 'Wallet that receives the payment (utility or telco).');
                return TextField(
                  controller: _billerAccountCtrl,
                  readOnly: hasPreset,
                  enabled: !hasPreset,
                  decoration: InputDecoration(
                    labelText:
                        l.isArabic ? 'محفظة مزود الخدمة' : 'Biller wallet ID',
                    helperText: helper,
                  ),
                );
              }),
              const SizedBox(height: 8),
              TextField(
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: l.isArabic ? 'المبلغ' : 'Amount ($_curSym)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _noteCtrl,
                decoration: InputDecoration(
                  labelText:
                      l.isArabic ? 'ملاحظة (اختياري)' : 'Note (optional)',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ShamellPaymentPillButton(
                      label: Text(
                        l.isArabic ? 'حفظ كقالب' : 'Save as template',
                      ),
                      icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                      onPressed: _loading ? null : _saveCurrentAsTemplate,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PrimaryButton(
                      icon: Icons.receipt_long_outlined,
                      label: _loading
                          ? (l.isArabic ? 'جارٍ الدفع…' : 'Paying…')
                          : (l.isArabic ? 'دفع الفاتورة' : 'Pay bill'),
                      onPressed: _loading ? null : _payBill,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBillHistory(BuildContext context) {
    final l = L10n.of(context);
    if (widget.walletId.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l.isArabic
                ? 'يرجى إعداد المحفظة لعرض سجل الفواتير.'
                : 'Please set up your wallet first to view bill history.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: .75),
                ),
          ),
        ),
      );
    }
    return HistoryPage(
      baseUrl: widget.baseUrl,
      walletId: widget.walletId,
      initialKind: 'bill',
    );
  }
}
