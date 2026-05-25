import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/account_identity_store.dart';
import 'money_mutation_guard.dart';
import '../../../main.dart' show LoginPage;
import '../../core/app_activity.dart';
import '../../core/app_sounds.dart';
import '../../core/device_binding_reauth.dart';
import '../../core/design_tokens.dart';
import '../../core/format.dart' show fmtCents;
import '../../core/l10n.dart';
import '../../core/http_error.dart';
import '../../core/safe_clipboard.dart';
import '../../core/safe_set_state.dart';
import 'package:shamell_flutter/core/capabilities.dart';
import 'package:shamell_flutter/core/base_url.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import 'currency_symbol_store.dart';
// WaterButton removed from Payments; no main import required
import 'payments_attestation.dart' show shamellPaymentAmountMajorToCents;
import 'payments_send.dart' show PayActionButton; // reuse button style
import 'payments_card_style.dart';
import 'payments_qr_payload.dart';

const Duration _paymentsReceiveRequestTimeout = Duration(seconds: 15);

String _paymentsMaskSecretValue(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return '';
  if (raw.length <= 4) {
    return '*' * raw.length;
  }
  if (raw.length <= 6) {
    return '${raw[0]}***${raw[raw.length - 1]}';
  }
  return '${raw.substring(0, 2)}***${raw.substring(raw.length - 2)}';
}

String shamellPaymentsMaskSensitivePayloadForDisplay(String payload) {
  final raw = payload.trim();
  if (raw.isEmpty) return raw;
  final uri = Uri.tryParse(raw);
  if (uri != null &&
      uri.scheme.toLowerCase() == 'shamell' &&
      uri.queryParameters.isNotEmpty) {
    final masked = <String, String>{};
    for (final entry in uri.queryParameters.entries) {
      final key = entry.key.trim();
      final lower = key.toLowerCase();
      if (lower == 'wallet_id' ||
          lower == 'to_wallet_id' ||
          lower == 'to_alias' ||
          lower == 'alias' ||
          lower == 'note' ||
          lower == 'ref' ||
          lower == 'reference') {
        masked[key] = _paymentsMaskSecretValue(entry.value);
      } else {
        masked[key] = entry.value;
      }
    }
    final queryStart = raw.indexOf('?');
    final base = queryStart >= 0 ? raw.substring(0, queryStart) : raw;
    final query = masked.entries
        .map((entry) =>
            '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value).replaceAll('%2A', '*')}')
        .join('&');
    return '$base?$query';
  }
  final parts = raw.split('|');
  if (parts.length <= 1) {
    return _paymentsMaskSecretValue(raw);
  }
  final out = <String>[parts.first];
  for (final part in parts.skip(1)) {
    final idx = part.indexOf('=');
    if (idx <= 0 || idx >= part.length - 1) {
      out.add(_paymentsMaskSecretValue(part));
      continue;
    }
    final key = part.substring(0, idx).trim();
    final value = part.substring(idx + 1);
    out.add('$key=${_paymentsMaskSecretValue(value)}');
  }
  return out.join('|');
}

class ShareQrPanel extends StatelessWidget {
  final String payload;
  const ShareQrPanel({super.key, required this.payload});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: shamellPaymentPagePadding(context),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final qrSize = constraints.maxWidth.clamp(160.0, 220.0).toDouble();
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(payload, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              QrImageView(data: payload, size: qrSize),
            ],
          );
        },
      ),
    );
  }
}

class PaymentReceiveTab extends StatefulWidget {
  final String baseUrl;
  final String fromWalletId;
  final http.Client? client;
  final String? walletCurrency;

  /// When true, only show the core pay-code UI (SyrChat-style "Receive" view).
  final bool compact;

  const PaymentReceiveTab({
    super.key,
    required this.baseUrl,
    required this.fromWalletId,
    this.client,
    this.walletCurrency,
    this.compact = false,
  });

  @override
  State<PaymentReceiveTab> createState() => _PaymentReceiveTabState();
}

class _PaymentReceiveTabState extends State<PaymentReceiveTab>
    with
        SafeSetStateMixin<PaymentReceiveTab>,
        MoneyMutationGuardMixin<PaymentReceiveTab> {
  String myWallet = '';
  String _curSym = 'SYP';
  int? _balanceCents;
  bool _loadingWallet = false;
  final amtCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  final merchantLabelCtrl = TextEditingController();
  final merchantExpiryCtrl = TextEditingController(text: '15');
  String qrPayload = '';
  bool _qrPayloadVisible = false;
  bool _merchantQrMode = false;
  final sonicAmtCtrl = TextEditingController(text: '10.00');
  final sonicTokenCtrl = TextEditingController();
  String sonicOut = '';
  String sonicPayload = '';
  bool _sonicPayloadVisible = false;
  final cashCodeCtrl = TextEditingController();
  final cashSecretCtrl = TextEditingController();
  String cashOut = '';
  bool _paymentsSonicEnabled = false;
  bool _paymentsCashVouchersEnabled = false;

  @override
  void initState() {
    super.initState();
    final walletCurrency = (widget.walletCurrency ?? '').trim();
    if (walletCurrency.isNotEmpty) _curSym = walletCurrency;
    _init();
  }

  @override
  void dispose() {
    // Proactively clear potentially sensitive text before disposing controllers.
    amtCtrl.clear();
    noteCtrl.clear();
    merchantLabelCtrl.clear();
    merchantExpiryCtrl.clear();
    sonicAmtCtrl.clear();
    sonicTokenCtrl.clear();
    cashCodeCtrl.clear();
    cashSecretCtrl.clear();
    amtCtrl.dispose();
    noteCtrl.dispose();
    merchantLabelCtrl.dispose();
    merchantExpiryCtrl.dispose();
    sonicAmtCtrl.dispose();
    sonicTokenCtrl.dispose();
    cashCodeCtrl.dispose();
    cashSecretCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final sp = await SharedPreferences.getInstance();
    myWallet =
        await loadStoredWalletId(sp: sp, baseUrlOverride: widget.baseUrl) ??
            widget.fromWalletId;
    final caps =
        await ShamellCapabilities.loadForBaseUrl(widget.baseUrl, sp: sp);
    _paymentsSonicEnabled = caps.paymentsSonic;
    _paymentsCashVouchersEnabled = caps.paymentsCashVouchers;
    final cs = await loadStoredCurrencySymbol(
      baseUrl: widget.baseUrl,
      sp: sp,
    );
    if ((widget.walletCurrency ?? '').trim().isEmpty &&
        cs != null &&
        cs.isNotEmpty) {
      _curSym = cs;
    }
    setState(() {});
    await _loadWallet();
  }

  Future<void> _loadWallet() async {
    if (myWallet.isEmpty) return;
    final uri = _paymentsUri(pathSegments: <String>['wallets', myWallet]);
    if (uri == null) return;
    setState(() => _loadingWallet = true);
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    try {
      final r = await httpClient
          .get(uri, headers: await _hdrPRC(widget.baseUrl))
          .timeout(_paymentsReceiveRequestTimeout);
      if (!mounted) return;
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body);
        _balanceCents = (j['balance_cents'] ?? 0) as int;
        final cur = (j['currency'] ?? '').toString().trim();
        if (cur.isNotEmpty) {
          _curSym = cur;
          unawaited(
            saveStoredCurrencySymbol(cur, baseUrl: widget.baseUrl),
          );
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
      if (mounted) setState(() => _loadingWallet = false);
    }
  }

  double _parseMajor(String s) {
    try {
      final t = s.trim().replaceAll(',', '.');
      return double.parse(t);
    } catch (_) {
      return 0;
    }
  }

  void _makeMyQR() {
    final a = _parseMajor(amtCtrl.text.trim());
    if (myWallet.isEmpty) {
      setState(() => qrPayload = '');
      return;
    }
    final note = noteCtrl.text.trim();
    final amountCents =
        a.isFinite && a > 0 ? shamellPaymentAmountMajorToCents(a) : null;
    final expiryMinutes = (int.tryParse(merchantExpiryCtrl.text.trim()) ?? 15)
        .clamp(1, 1440)
        .toInt();
    final p = buildShamellPaymentQrPayload(
      type: ShamellPaymentQrPayloadType.pay,
      walletId: myWallet,
      currency: _curSym,
      amountCents: amountCents,
      note: note,
      label: _merchantQrMode ? merchantLabelCtrl.text.trim() : null,
      mode: _merchantQrMode ? 'merchant' : null,
      expiresAt: _merchantQrMode
          ? DateTime.now().add(Duration(minutes: expiryMinutes))
          : null,
    );
    setState(() {
      qrPayload = p;
      _qrPayloadVisible = false;
    });
  }

  Uri? _paymentsUri({
    required List<String> pathSegments,
    Map<String, String>? queryParameters,
  }) {
    return secureApiChildUri(
      baseUrl: widget.baseUrl,
      pathSegments: <String>['payments', ...pathSegments],
      queryParameters: queryParameters,
    );
  }

  String _invalidServerUrlMessage() {
    final isArabic = L10n.of(context).isArabic;
    return isArabic ? 'عنوان الخادم غير صالح.' : 'Invalid server URL.';
  }

  String _offlineReplayUnsafeMessage() {
    final isArabic = L10n.of(context).isArabic;
    return isArabic
        ? 'تم تعطيل إعادة المحاولة دون اتصال لهذا الإجراء. تحقق من النتيجة ثم أعد المحاولة عند عودة الاتصال.'
        : 'Offline replay is disabled for this action. Check the result, then retry when online.';
  }

  Future<bool> _requireSensitiveReveal() async {
    return true;
  }

  Future<void> _toggleQrPayloadVisibility() async {
    if (_qrPayloadVisible) {
      if (mounted) {
        setState(() => _qrPayloadVisible = false);
      }
      return;
    }
    final approved = await _requireSensitiveReveal();
    if (approved && mounted) {
      setState(() => _qrPayloadVisible = true);
    }
  }

  Future<void> _copyQrPayloadSensitive() async {
    if (qrPayload.trim().isEmpty) return;
    final approved = _qrPayloadVisible || await _requireSensitiveReveal();
    if (!approved || !mounted) return;
    await shamellCopyToClipboard(qrPayload, sensitive: true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).copiedLabel)),
      );
    }
  }

  Future<void> _showQrPayloadFullscreen() async {
    if (qrPayload.trim().isEmpty) return;
    final approved = _qrPayloadVisible || await _requireSensitiveReveal();
    if (!approved || !mounted) return;
    if (!_qrPayloadVisible) {
      setState(() => _qrPayloadVisible = true);
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => ShareQrPanel(payload: qrPayload),
    );
  }

  Future<void> _toggleSonicPayloadVisibility() async {
    if (_sonicPayloadVisible) {
      if (mounted) {
        setState(() => _sonicPayloadVisible = false);
      }
      return;
    }
    final approved = await _requireSensitiveReveal();
    if (approved && mounted) {
      setState(() => _sonicPayloadVisible = true);
    }
  }

  Future<void> _copySonicPayloadSensitive() async {
    if (sonicPayload.trim().isEmpty) return;
    final approved = _sonicPayloadVisible || await _requireSensitiveReveal();
    if (!approved || !mounted) return;
    await shamellCopyToClipboard(sonicPayload, sensitive: true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).copiedLabel)),
      );
    }
  }

  /// Public entry point for redeeming a cash-out code. Routed through
  /// [guardMoneyMutation] so double-tapping the Redeem button can't
  /// fire two POSTs, and tracks success/failure so the secret phrase
  /// is **only wiped on success** — previously it was cleared
  /// unconditionally in a `finally` block, which forced the user to
  /// re-type the secret after any transient failure (a recurring
  /// support complaint, and a real risk on flows that lock the code
  /// after N failed attempts).
  Future<void> _redeemCashCode() async {
    await guardMoneyMutation<void>(_redeemCashCodeUnguarded);
  }

  Future<void> _redeemCashCodeUnguarded() async {
    final l = L10n.of(context);
    setState(() {
      cashOut = '...';
    });
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    // Latched on a successful 2xx so the `finally` block clears the
    // secret only on success — failures leave the field intact for
    // immediate retry.
    bool redeemSucceeded = false;
    try {
      final code = cashCodeCtrl.text.trim();
      final secret = cashSecretCtrl.text.trim();
      if (code.isEmpty || secret.isEmpty) {
        setState(() {
          cashOut = l.payCheckInputs;
        });
        return;
      }
      final uri = _paymentsUri(pathSegments: <String>['cash', 'redeem']);
      if (uri == null) {
        setState(() {
          cashOut = _invalidServerUrlMessage();
        });
        return;
      }
      final headers = await _hdrPRC(widget.baseUrl, json: true);
      final body = jsonEncode(<String, Object?>{
        'code': code,
        'secret_phrase': secret,
      });
      final r = await httpClient
          .post(uri, headers: headers, body: body)
          .timeout(_paymentsReceiveRequestTimeout);
      if (!mounted) return;
      if (r.statusCode < 200 || r.statusCode >= 300) {
        if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
          context,
          statusCode: r.statusCode,
          rawBody: r.body,
          loginPageBuilder: (_) => const LoginPage(),
        )) {
          return;
        }
      }
      final ok = r.statusCode >= 200 && r.statusCode < 300;
      redeemSucceeded = ok;
      setState(() {
        cashOut = ok
            ? (l.isArabic ? 'تم استبدال الرمز.' : 'Redeemed.')
            : sanitizeHttpError(
                statusCode: r.statusCode,
                rawBody: r.body,
                isArabic: l.isArabic,
              );
      });
      if (ok) {
        unawaited(ShamellSoundEffects.play(ShamellSoundEffect.moneyReceived));
        shamellRecordAppActivity(
          baseUrl: widget.baseUrl,
          eventType: 'payment_cash_code_redeemed',
          moduleId: 'payments',
          action: 'cash_code_redeemed',
          client: httpClient,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic
                  ? 'تم استبدال رمز السحب النقدي.'
                  : 'Cash‑out code redeemed.',
            ),
          ),
        );
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
        cashOut = sanitizeExceptionForUi(error: e, isArabic: l.isArabic);
      });
    } finally {
      // Only clear the secret on success — see method-level comment.
      if (redeemSucceeded) {
        cashSecretCtrl.clear();
      }
      if (closeClient) httpClient.close();
    }
  }

  Future<void> _sonicIssue() async {
    setState(() => sonicOut = '...');
    final uri = _paymentsUri(pathSegments: <String>['sonic', 'issue']);
    if (uri == null) {
      setState(() => sonicOut = _invalidServerUrlMessage());
      return;
    }
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    try {
      final v =
          double.tryParse(sonicAmtCtrl.text.trim().replaceAll(',', '.')) ?? 0;
      final body = jsonEncode({
        'from_wallet_id': myWallet,
        'amount': double.parse(v.toStringAsFixed(2))
      });
      final headers = await _hdrPRC(widget.baseUrl, json: true);
      final r = await httpClient
          .post(uri, headers: headers, body: body)
          .timeout(_paymentsReceiveRequestTimeout);
      if (!mounted) return;
      if (r.statusCode < 200 || r.statusCode >= 300) {
        if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
          context,
          statusCode: r.statusCode,
          rawBody: r.body,
          loginPageBuilder: (_) => const LoginPage(),
        )) {
          return;
        }
      }
      sonicOut = r.statusCode >= 200 && r.statusCode < 300
          ? (L10n.of(context).isArabic ? 'تم إصدار توكن.' : 'Issued token.')
          : sanitizeHttpError(
              statusCode: r.statusCode,
              rawBody: r.body,
              isArabic: L10n.of(context).isArabic,
            );
      try {
        final j = jsonDecode(r.body);
        final tok = j['token'] ?? '';
        sonicPayload = tok is String && tok.startsWith('SONIC|')
            ? tok
            : 'SONIC|token=' + tok.toString();
        _sonicPayloadVisible = false;
      } catch (_) {}
      if (r.statusCode >= 500) {
        sonicOut = _offlineReplayUnsafeMessage();
      }
    } catch (e) {
      if (mounted &&
          await shamellForceReauthIfCriticalDeviceBindingDrift(
            context,
            error: e,
            loginPageBuilder: (_) => const LoginPage(),
          )) {
        return;
      }
      sonicOut = _offlineReplayUnsafeMessage();
    } finally {
      if (closeClient) httpClient.close();
    }
    if (mounted) setState(() {});
  }

  Future<void> _sonicRedeem() async {
    setState(() => sonicOut = '...');
    final uri = _paymentsUri(pathSegments: <String>['sonic', 'redeem']);
    if (uri == null) {
      setState(() => sonicOut = _invalidServerUrlMessage());
      return;
    }
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    try {
      final token = sonicPayload.startsWith('SONIC|')
          ? (() {
              final m = <String, String>{};
              for (final p in sonicPayload.split('|').skip(1)) {
                final kv = p.split('=');
                if (kv.length == 2) m[kv[0]] = kv[1];
              }
              return m['token'] ?? sonicPayload;
            }())
          : sonicTokenCtrl.text.trim();
      final headers = await _hdrPRC(widget.baseUrl, json: true);
      final body = jsonEncode({'token': token});
      final r = await httpClient
          .post(uri, headers: headers, body: body)
          .timeout(_paymentsReceiveRequestTimeout);
      if (!mounted) return;
      if (r.statusCode < 200 || r.statusCode >= 300) {
        if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
          context,
          statusCode: r.statusCode,
          rawBody: r.body,
          loginPageBuilder: (_) => const LoginPage(),
        )) {
          return;
        }
      }
      sonicOut = r.statusCode >= 200 && r.statusCode < 300
          ? (L10n.of(context).isArabic ? 'تم الاستبدال.' : 'Redeemed.')
          : sanitizeHttpError(
              statusCode: r.statusCode,
              rawBody: r.body,
              isArabic: L10n.of(context).isArabic,
            );
      if (r.statusCode >= 500) {
        sonicOut = _offlineReplayUnsafeMessage();
      }
      if (r.statusCode >= 200 && r.statusCode < 300) {
        unawaited(ShamellSoundEffects.play(ShamellSoundEffect.moneyReceived));
        shamellRecordAppActivity(
          baseUrl: widget.baseUrl,
          eventType: 'payment_sonic_redeemed',
          moduleId: 'payments',
          action: 'sonic_redeemed',
          client: httpClient,
        );
        sonicTokenCtrl.clear();
      }
    } catch (e) {
      if (mounted &&
          await shamellForceReauthIfCriticalDeviceBindingDrift(
            context,
            error: e,
            loginPageBuilder: (_) => const LoginPage(),
          )) {
        return;
      }
      sonicOut = _offlineReplayUnsafeMessage();
    } finally {
      if (closeClient) httpClient.close();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final children = <Widget>[
      _walletHero(),
      const SizedBox(height: 12),
      ShamellPaymentCardSurface(
        tone: ShamellPaymentCardTone.section,
        padding: shamellPaymentCardPadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.payRequestTitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              '${l.walletLabel}: ${myWallet.isEmpty ? l.walletNotSetShort : myWallet}',
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: .72),
                  ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: <ButtonSegment<bool>>[
                ButtonSegment<bool>(
                  value: false,
                  icon: const Icon(Icons.person_outline),
                  label: Text(l.isArabic ? 'شخصي' : 'Personal'),
                ),
                ButtonSegment<bool>(
                  value: true,
                  icon: const Icon(Icons.storefront_outlined),
                  label: Text(l.isArabic ? 'تاجر' : 'Merchant'),
                ),
              ],
              selected: <bool>{_merchantQrMode},
              onSelectionChanged: (selection) {
                setState(() {
                  _merchantQrMode = selection.first;
                  qrPayload = '';
                });
              },
            ),
            if (_merchantQrMode) ...[
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final merchantField = TextField(
                    controller: merchantLabelCtrl,
                    decoration: InputDecoration(
                      labelText: l.isArabic ? 'اسم التاجر' : 'Merchant name',
                    ),
                  );
                  final expiryField = TextField(
                    controller: merchantExpiryCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText:
                          l.isArabic ? 'ينتهي بعد (دقيقة)' : 'Expires in (min)',
                    ),
                  );
                  if (constraints.maxWidth < 360) {
                    return Column(
                      children: [
                        merchantField,
                        const SizedBox(height: 8),
                        expiryField,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: merchantField),
                      const SizedBox(width: 8),
                      SizedBox(width: 140, child: expiryField),
                    ],
                  );
                },
              ),
            ],
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final amountField = TextField(
                  controller: amtCtrl,
                  keyboardType: TextInputType.number,
                  decoration:
                      InputDecoration(labelText: l.payRequestAmountLabel),
                );
                final noteField = TextField(
                  controller: noteCtrl,
                  decoration: InputDecoration(labelText: l.payRequestNoteLabel),
                );
                if (constraints.maxWidth < 360) {
                  return Column(
                    children: [
                      amountField,
                      const SizedBox(height: 8),
                      noteField,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: amountField),
                    const SizedBox(width: 8),
                    Expanded(child: noteField),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            Builder(
              builder: (_) {
                final a = _parseMajor(amtCtrl.text.trim());
                if (a <= 0) return const SizedBox.shrink();
                return ShamellPaymentMetricChip(
                  label: l.isArabic ? 'المعاينة' : 'Preview',
                  value:
                      '${l.payRequestPreviewPrefix}${a.toStringAsFixed(2)} $_curSym',
                  icon: Icons.visibility_outlined,
                );
              },
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: PayActionButton(
                icon: Icons.qr_code_2,
                label: l.payRequestQrLabel,
                onTap: _makeMyQR,
                radius: 16,
              ),
            ),
            if (qrPayload.isNotEmpty) ...[
              const SizedBox(height: 14),
              ShamellPaymentCardSurface(
                tone: ShamellPaymentCardTone.soft,
                padding: shamellPaymentCardPadding(
                  context,
                  tone: ShamellPaymentCardTone.soft,
                ),
                child: Column(
                  children: [
                    Text(
                      _qrPayloadVisible
                          ? qrPayload
                          : shamellPaymentsMaskSensitivePayloadForDisplay(
                              qrPayload,
                            ),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 12),
                    if (_qrPayloadVisible)
                      QrImageView(data: qrPayload, size: 220),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        ShamellPaymentPillButton(
                          icon: Icon(
                            _qrPayloadVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          label: Text(
                            _qrPayloadVisible
                                ? (l.isArabic ? 'إخفاء الرمز' : 'Hide code')
                                : (l.isArabic ? 'إظهار الرمز' : 'Reveal code'),
                          ),
                          onPressed: _toggleQrPayloadVisibility,
                        ),
                        ShamellPaymentPillButton(
                          icon: const Icon(Icons.copy),
                          label: Text(l.payShareLinkLabel),
                          onPressed: _copyQrPayloadSensitive,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: PayActionButton(
                        icon: Icons.fullscreen,
                        label: l.isArabic
                            ? 'عرض رمز الدفع بملء الشاشة'
                            : 'Show pay code full‑screen',
                        onTap: _showQrPayloadFullscreen,
                        radius: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ];

    if (!widget.compact &&
        (_paymentsSonicEnabled || _paymentsCashVouchersEnabled)) {
      children.addAll([
        if (_paymentsSonicEnabled) ...[
          const Divider(height: 24),
          ExpansionTile(
            title: Text(l.sonicSectionTitle),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: sonicAmtCtrl,
                      decoration:
                          InputDecoration(labelText: l.sonicAmountLabel),
                    ),
                  ),
                  PayActionButton(
                    label: l.sonicIssueLabel,
                    onTap: _sonicIssue,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (sonicPayload.isNotEmpty)
                Center(
                  child: Column(
                    children: [
                      Text(
                        _sonicPayloadVisible
                            ? sonicPayload
                            : shamellPaymentsMaskSensitivePayloadForDisplay(
                                sonicPayload,
                              ),
                      ),
                      const SizedBox(height: 8),
                      if (_sonicPayloadVisible)
                        QrImageView(data: sonicPayload, size: 200),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          PayActionButton(
                            icon: _sonicPayloadVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                            label: _sonicPayloadVisible
                                ? (l.isArabic ? 'إخفاء التوكن' : 'Hide token')
                                : (l.isArabic
                                    ? 'إظهار التوكن'
                                    : 'Reveal token'),
                            onTap: _toggleSonicPayloadVisibility,
                          ),
                          PayActionButton(
                            icon: Icons.copy,
                            label: l.isArabic ? 'نسخ التوكن' : 'Copy token',
                            onTap: _copySonicPayloadSensitive,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: sonicTokenCtrl,
                      decoration: InputDecoration(labelText: l.sonicTokenLabel),
                    ),
                  ),
                  PayActionButton(
                    label: l.sonicRedeemLabel,
                    onTap: _sonicRedeem,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SelectableText(sonicOut.isEmpty ? '' : sonicOut),
            ],
          ),
        ],
        if (_paymentsCashVouchersEnabled) ...[
          const Divider(height: 24),
          ExpansionTile(
            title: Text(
              l.isArabic ? 'استبدال رمز السحب النقدي' : 'Redeem cash‑out code',
            ),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  l.isArabic
                      ? 'أدخل رمز السحب النقدي وكلمة السر للتحويل إلى المحفظة، مشابه لرموز السحب في المحافظ الفائقة.'
                      : 'Enter the cash‑out code and its secret phrase to redeem funds into your wallet, similar to cash‑out codes in super‑app wallets.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: .70),
                      ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  children: [
                    TextField(
                      controller: cashCodeCtrl,
                      decoration: InputDecoration(
                        labelText: l.labelCode,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: cashSecretCtrl,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: l.cashSecretPhraseOpt,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      // Gate the Redeem button on the in-flight guard
                      // so a double-tap can't fire two cash-redeem
                      // POSTs (and burn an attempt on a code that
                      // locks after N failures).
                      child: PayActionButton(
                        icon: Icons.redeem_outlined,
                        label: l.isArabic ? 'استبدال الرمز' : 'Redeem code',
                        onTap: isMoneyMutationInFlight
                            ? null
                            : _redeemCashCode,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (cashOut.isNotEmpty)
                      SelectableText(
                        cashOut,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: .80),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ]);
    }

    return ListView(
      padding: shamellPaymentPagePadding(context),
      children: children,
    );
  }

  Widget _walletHero() {
    final bal = _balanceCents;
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fgPrimary = theme.colorScheme.onSurface;
    final fgSecondary = fgPrimary.withValues(alpha: .72);
    return ShamellPaymentCardSurface(
      tone: ShamellPaymentCardTone.hero,
      padding:
          shamellPaymentCardPadding(context, tone: ShamellPaymentCardTone.hero),
      child: Row(
        children: [
          Builder(
            builder: (context) {
              final compact = shamellPaymentIsCompact(context);
              return Container(
                width: compact ? 46 : 52,
                height: compact ? 46 : 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: isDark ? .10 : .60),
                  borderRadius: BorderRadius.circular(compact ? 14 : 16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: isDark ? .10 : .65),
                  ),
                ),
                child: Icon(
                  Icons.qr_code_rounded,
                  size: compact ? 23 : 26,
                  color: Tokens.colorPayments.withValues(alpha: .96),
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.walletLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: .2,
                    color: fgSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        myWallet.isEmpty ? l.walletNotSetShort : myWallet,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: fgPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip:
                          l.isArabic ? 'نسخ رقم المحفظة' : 'Copy wallet ID',
                      icon: Icon(
                        Icons.copy_rounded,
                        size: 18,
                        color: fgSecondary,
                      ),
                      onPressed: myWallet.isEmpty
                          ? null
                          : () async {
                              try {
                                await shamellCopyToClipboard(
                                  myWallet,
                                  sensitive: true,
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(l.copiedLabel)),
                                );
                              } catch (_) {}
                            },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  l.balanceLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: fgSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      bal == null
                          ? (_loadingWallet ? '…' : '—')
                          : '${fmtCents(bal)} ${_curSym}',
                      maxLines: 1,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                        letterSpacing: -.5,
                        color: fgPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<Map<String, String>> _hdrPRC(String baseUrl, {bool json = false}) async {
  return shamellSessionHeadersForBaseUrl(baseUrl, json: json);
}
