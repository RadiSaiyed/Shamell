import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../main.dart' show LoginPage;
import '../../core/app_activity.dart';
import '../../core/app_sounds.dart';
import '../../core/device_binding_reauth.dart';
import '../../core/device_id.dart';
import '../../core/l10n.dart';
import 'money_mutation_guard.dart';
import '../../core/http_error.dart';
import '../../core/safe_set_state.dart';
import '../../core/session_cookie_store.dart';
import 'package:shamell_flutter/core/base_url.dart';
import 'payments_attestation.dart';
import 'payments_idempotency.dart';
import 'payments_qr_payload.dart';
import 'payments_send.dart' show PayActionButton; // reuse styled button
import 'payments_card_style.dart';
import 'supported_currencies.dart';
import '../../core/scan_page.dart';

class PaymentScanTab extends StatefulWidget {
  final String baseUrl;
  final String fromWalletId;
  final bool autoScan;
  final http.Client? client;
  final Future<String?> Function(BuildContext context)? scanLauncher;
  final String? walletCurrency;
  const PaymentScanTab(
      {super.key,
      required this.baseUrl,
      required this.fromWalletId,
      this.autoScan = false,
      this.client,
      this.scanLauncher,
      this.walletCurrency});
  @override
  State<PaymentScanTab> createState() => _PaymentScanTabState();
}

class _PaymentScanTabState extends State<PaymentScanTab>
    with SafeSetStateMixin<PaymentScanTab>, MoneyMutationGuardMixin<PaymentScanTab> {
  static const Duration _paymentsScanRequestTimeout = Duration(seconds: 15);
  late final http.Client _http;
  late final bool _ownsHttpClient;
  final toCtrl = TextEditingController();
  final aliasCtrl = TextEditingController();
  final amtCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  String out = '';
  bool _scanned = false;
  bool _showAmountPrompt = false;
  String _targetLabel = '';
  String _qrCurrency = '';

  @override
  void initState() {
    super.initState();
    _ownsHttpClient = widget.client == null;
    _http = widget.client ?? shamellHttpClient();
  }

  @override
  void dispose() {
    if (_ownsHttpClient) {
      _http.close();
    }
    toCtrl.dispose();
    aliasCtrl.dispose();
    amtCtrl.dispose();
    noteCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, String>> _hdr({bool json = false}) async {
    return shamellSessionHeadersForBaseUrl(widget.baseUrl, json: json);
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
    return L10n.of(context).isArabic
        ? 'عنوان الخادم غير صالح.'
        : 'Invalid server URL.';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.autoScan && !_scanned) {
      _scanned = true;
      Future.microtask(_scan);
    }
  }

  Future<void> _scan() async {
    try {
      final raw = await (widget.scanLauncher?.call(context) ??
          Navigator.push<String?>(
              context, MaterialPageRoute(builder: (_) => const ScanPage())));
      if (!mounted) return;
      if (raw == null) return;
      final p = _parse(raw.toString());
      // Audit-fix (C-P1-11): all QR-validation error messages route
      // through L10n so RTL users see Arabic copy instead of the
      // English-only fallbacks that used to leak through here.
      final l = L10n.of(context);
      if ((p['type'] ?? '') == 'topup') {
        setState(() {
          _showAmountPrompt = false;
          out = l.isArabic
              ? 'رمز QR غير صالح: هذا رمز شحن، وليس رمز دفع.'
              : 'Invalid QR: this is a top-up code, not a payment code.';
        });
        return;
      }
      final expiresAtRaw = (p['expires_at'] ?? '').trim();
      final expiresAt = expiresAtRaw.isEmpty
          ? null
          : DateTime.tryParse(expiresAtRaw)?.toUtc();
      if (expiresAt != null && DateTime.now().toUtc().isAfter(expiresAt)) {
        setState(() {
          _showAmountPrompt = false;
          out = l.isArabic
              ? 'انتهت صلاحية رمز الدفع.'
              : 'This payment QR has expired.';
        });
        return;
      }
      final scannedCurrency = (p['currency'] ?? '').trim().toUpperCase();
      if (scannedCurrency.isNotEmpty &&
          !shamellIsSupportedWalletCurrency(scannedCurrency)) {
        setState(() {
          _qrCurrency = scannedCurrency;
          _showAmountPrompt = false;
          out = l.isArabic
              ? 'عملة رمز QR غير مدعومة: $scannedCurrency.'
              : 'Unsupported QR currency: $scannedCurrency.';
        });
        return;
      }
      final walletCurrency = (widget.walletCurrency ?? '').trim().toUpperCase();
      if (scannedCurrency.isNotEmpty &&
          walletCurrency.isNotEmpty &&
          scannedCurrency != walletCurrency) {
        setState(() {
          _qrCurrency = scannedCurrency;
          _showAmountPrompt = false;
          out = l.isArabic
              ? 'عدم تطابق العملة: رمز QR بـ $scannedCurrency، والمحفظة المفتوحة بـ $walletCurrency.'
              : 'Currency mismatch: this QR is $scannedCurrency, but the open wallet is $walletCurrency.';
        });
        return;
      }
      toCtrl.text = p['to_wallet_id'] ?? '';
      aliasCtrl.text = p['to_alias'] ?? '';
      if ((p['amount'] ?? '').toString().isNotEmpty) {
        amtCtrl.text = p['amount']!;
      }
      if ((p['note'] ?? '').toString().isNotEmpty) {
        noteCtrl.text = p['note']!;
      }
      setState(() {
        _qrCurrency = scannedCurrency;
        _targetLabel = (p['label'] ?? '').toString();
      });
      setState(() {
        // Reset any previous amount prompt; _confirmAndPay will re-enable it if needed.
        _showAmountPrompt = false;
      });
      await _confirmAndPay();
    } catch (e) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sanitizeExceptionForUi(
              error: e,
              isArabic: L10n.of(context).isArabic,
            ),
          ),
        ),
      );
    }
  }

  Map<String, String> _parse(String raw) {
    final parsed = parseShamellPaymentQrPayload(raw);
    if (parsed != null) {
      return {
        'type':
            parsed.type == ShamellPaymentQrPayloadType.topup ? 'topup' : 'pay',
        'to_wallet_id': parsed.walletId ?? '',
        'to_alias': parsed.alias ?? '',
        'amount': _amountInputText(parsed.amountCents),
        'note': parsed.note ?? '',
        'label': parsed.label ?? '',
        'mode': parsed.mode ?? '',
        'expires_at': parsed.expiresAtIso ?? '',
        'currency': parsed.currency ?? '',
      };
    }
    String toWallet = '',
        toAlias = '',
        amount = '',
        note = '',
        label = '',
        mode = '',
        expiresAt = '';
    try {
      // Custom PAY| format: PAY|wallet=...|amount=...|ref=...
      if (raw.startsWith('PAY|') || raw.startsWith('CASH|')) {
        final parts = raw.split('|');
        for (final p in parts.skip(1)) {
          final kv = p.split('=');
          if (kv.length != 2) continue;
          final k = kv[0].trim();
          String v;
          try {
            v = Uri.decodeComponent(kv[1].trim());
          } catch (_) {
            continue;
          }
          switch (k) {
            case 'wallet':
              toWallet = v;
              break;
            case 'to_wallet_id':
              toWallet = v;
              break;
            case 'alias':
              toAlias = v;
              break;
            case 'to_alias':
              toAlias = v;
              break;
            case 'amount':
              amount = v;
              break; // SYP major units string
            case 'ref':
              note = v;
              break;
            case 'note':
              note = v;
              break;
            case 'label':
            case 'merchant':
            case 'name':
              label = v;
              break;
            case 'mode':
            case 'qr_mode':
              mode = v;
              break;
            case 'expires_at':
            case 'expires':
            case 'expiry':
              expiresAt = v;
              break;
          }
        }
      } else if (raw.trim().startsWith('{')) {
        final j = jsonDecode(raw);
        toWallet = (j['to_wallet_id'] ?? '').toString();
        toAlias = (j['to_alias'] ?? j['alias'] ?? '').toString();
        amount = (j['amount'] ?? j['amount_syp'] ?? '').toString();
        note = (j['note'] ?? j['reference'] ?? '').toString();
        label =
            (j['merchant_name'] ?? j['label'] ?? j['name'] ?? '').toString();
        mode = (j['mode'] ?? j['qr_mode'] ?? '').toString();
        expiresAt =
            (j['expires_at'] ?? j['expires'] ?? j['expiry'] ?? '').toString();
      } else {
        final uri = Uri.tryParse(raw);
        if (uri != null && uri.scheme.isNotEmpty) {
          final q = uri.queryParameters;
          toWallet = (q['to_wallet_id'] ?? '').toString();
          toAlias = (q['to_alias'] ?? q['alias'] ?? '').toString();
          amount = (q['amount'] ?? q['amt'] ?? '').toString();
          note = (q['note'] ?? q['ref'] ?? '').toString();
          label =
              (q['merchant_name'] ?? q['label'] ?? q['name'] ?? '').toString();
          mode = (q['mode'] ?? q['qr_mode'] ?? '').toString();
          expiresAt =
              (q['expires_at'] ?? q['expires'] ?? q['expiry'] ?? '').toString();
          if (toWallet.isEmpty && toAlias.isEmpty) {
            final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
            if (segs.isNotEmpty) toWallet = segs.last;
          }
        } else {
          if (raw.trim().startsWith('@')) {
            toAlias = raw.trim();
          } else {
            toWallet = raw.trim();
          }
        }
      }
    } catch (_) {}
    return {
      'type': 'pay',
      'to_wallet_id': toWallet,
      'to_alias': toAlias,
      'amount': amount,
      'note': note,
      'label': label,
      'mode': mode,
      'expires_at': expiresAt,
      'currency': '',
    };
  }

  String _amountInputText(int? cents) {
    if (cents == null || cents <= 0) return '';
    if (cents % 100 == 0) return (cents ~/ 100).toString();
    return '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
  }

  String get _effectiveCurrency {
    final qrCurrency = _qrCurrency.trim().toUpperCase();
    if (qrCurrency.isNotEmpty) return qrCurrency;
    final walletCurrency = (widget.walletCurrency ?? '').trim().toUpperCase();
    if (walletCurrency.isNotEmpty) return walletCurrency;
    return 'SYP';
  }

  /// Entry point for the QR-scan Pay action. Routed through
  /// [guardMoneyMutation] so a double-tap on the confirm dialog cannot
  /// fire two `/transfer` POSTs with two distinct idempotency keys
  /// (which would mint two real transfers; the server idempotency
  /// layer dedupes the same key on retry, not two different keys
  /// generated by two distinct invocations).
  Future<void> _pay() async {
    await guardMoneyMutation<void>(_payUnguarded);
  }

  /// The actual scan-pay pipeline. Never call directly — go through
  /// [_pay] so the guard is always engaged.
  Future<void> _payUnguarded() async {
    final toWallet = toCtrl.text.trim();
    final toAlias = aliasCtrl.text.trim();
    final amt = amtCtrl.text.trim();
    final note = noteCtrl.text.trim();
    final l = L10n.of(context);
    if (amt.isEmpty || (toWallet.isEmpty && toAlias.isEmpty)) {
      setState(() => out = l.isArabic
          ? 'أدخل الجهة المستلمة والمبلغ'
          : 'Enter target and amount');
      return;
    }
    final amountMajor = double.tryParse(amt.replaceAll(',', '.'));
    if (amountMajor == null || !amountMajor.isFinite || amountMajor <= 0) {
      setState(() =>
          out = l.isArabic ? 'أدخل مبلغًا صالحًا.' : 'Enter a valid amount.');
      return;
    }
    final fromWalletId = widget.fromWalletId.trim();
    if (fromWalletId.isEmpty) {
      setState(
          () => out = l.isArabic ? 'المحفظة غير صالحة.' : 'Wallet is invalid.');
      return;
    }
    setState(() {
      out = '...';
    });
    final uri = _paymentsUri(pathSegments: <String>['transfer']);
    if (uri == null) {
      setState(() => out = _invalidServerUrlMessage());
      return;
    }
    final amountCents = shamellPaymentAmountMajorToCents(amountMajor);
    final idempotencyKey = newPaymentsIdempotencyKey('payments-scan-transfer');
    final targetWalletId = toWallet.isNotEmpty ? toWallet : '';
    final targetAlias = targetWalletId.isEmpty ? toAlias : '';

    final deviceId = (await getOrCreateStableDeviceId(
      baseUrlOverride: widget.baseUrl,
    ))
        .trim();
    if (deviceId.isEmpty) {
      setState(() {
        out = sanitizeExceptionForUi(
          error: const PaymentMutationAttestationUnavailable(
            'device attestation unavailable',
          ),
          isArabic: l.isArabic,
        );
      });
      return;
    }

    final attestationHeaders = await (() async {
      try {
        return await shamellBuildPaymentMutationAttestationHeaders(
          baseUrl: widget.baseUrl,
          deviceId: deviceId,
          operation: 'payments_transfer',
          resourceId: shamellPaymentTransferAttestationResourceId(
            fromWalletId: fromWalletId,
            amountCents: amountCents,
            toWalletId: targetWalletId,
            toAlias: targetAlias,
          ),
          client: _http,
        );
      } on PaymentMutationAttestationHttpFailure catch (e) {
        if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
          context,
          statusCode: e.statusCode,
          rawBody: e.rawBody,
          loginPageBuilder: (_) => const LoginPage(),
        )) {
          return null;
        }
        setState(() {
          out = sanitizeHttpError(
            statusCode: e.statusCode,
            rawBody: e.rawBody,
            isArabic: l.isArabic,
          );
        });
        return null;
      } catch (e) {
        if (await shamellForceReauthIfCriticalDeviceBindingDrift(
          context,
          error: e,
          loginPageBuilder: (_) => const LoginPage(),
        )) {
          return null;
        }
        setState(() {
          out = sanitizeExceptionForUi(
            error: e,
            isArabic: l.isArabic,
          );
        });
        return null;
      }
    })();
    if (attestationHeaders == null) {
      return;
    }

    try {
      final body = <String, dynamic>{
        'from_wallet_id': fromWalletId,
        'amount_cents': amountCents,
      };
      if (targetWalletId.isNotEmpty) {
        body['to_wallet_id'] = targetWalletId;
      } else {
        body['to_alias'] = targetAlias;
      }
      if (note.isNotEmpty) body['reference'] = note;

      final headers = await _hdr(json: true)
        ..addAll(<String, String>{
          'Idempotency-Key': idempotencyKey,
          'X-Device-ID': deviceId,
        })
        ..addAll(attestationHeaders);
      final r = await _http
          .post(
            uri,
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(_paymentsScanRequestTimeout);
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: r.statusCode,
        rawBody: r.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      if (r.statusCode >= 200 && r.statusCode < 300) {
        unawaited(ShamellSoundEffects.play(ShamellSoundEffect.paymentSent));
        shamellRecordAppActivity(
          baseUrl: widget.baseUrl,
          eventType: 'payment_scan_transfer_sent',
          moduleId: 'payments',
          action: 'scan_transfer_sent',
          metadata: <String, Object?>{
            'amount_cents': amountCents,
            'currency': _effectiveCurrency,
            'target_type': targetWalletId.isNotEmpty ? 'wallet' : 'alias',
          },
          client: _http,
        );
        setState(() {
          out = l.isArabic ? 'تم إرسال الدفع.' : 'Payment sent.';
        });
      } else {
        setState(() {
          out = sanitizeHttpError(
            statusCode: r.statusCode,
            rawBody: r.body,
            isArabic: l.isArabic,
          );
        });
      }
    } catch (e) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      setState(() {
        out = sanitizeExceptionForUi(
          error: e,
          isArabic: l.isArabic,
        );
      });
    }
  }

  Future<void> _confirmAndPay() async {
    final toWallet = toCtrl.text.trim();
    final toAlias = aliasCtrl.text.trim();
    final amt = amtCtrl.text.trim();
    final l = L10n.of(context);
    if (toWallet.isEmpty && toAlias.isEmpty) {
      setState(() {
        _showAmountPrompt = false;
        out = l.isArabic
            ? 'رمز QR غير صالح: لا يوجد مستلم للدفع.'
            : 'Invalid QR: missing payment target';
      });
      return;
    }
    final myWallet = widget.fromWalletId.trim();
    if (myWallet.isNotEmpty && toWallet.isNotEmpty && myWallet == toWallet) {
      setState(() {
        _showAmountPrompt = false;
        out = l.isArabic
            ? 'لا يمكن الدفع لرمز سرتشات باي الخاص بك.'
            : 'You cannot pay your own SyrChat pay code.';
      });
      return;
    }
    if (amt.isEmpty) {
      setState(() {
        _showAmountPrompt = true;
        out = '';
      });
      return;
    }
    final target = toAlias.isNotEmpty ? toAlias : toWallet;
    // `l` already declared at the top of this method.
    // Audit-fix (C-P1-4): the confirm copy was English-only; in an
    // RTL-first product that was effectively a broken dialog for a
    // significant slice of users. Strings now route through L10n.
    //
    // Audit-fix (C-P1-3): for amounts above the configurable
    // large-amount threshold (defaults to 100 of the wallet currency)
    // we red-tint the body + insert an explicit "Above your typical
    // payment" caveat so accidental swipes / mis-tapped amounts get
    // a second look from the user before the money moves.
    final amtMajor = double.tryParse(amt) ?? 0.0;
    final largeAmountThreshold = _shamellPaymentLargeAmountThreshold;
    final isLargeAmount = amtMajor >= largeAmountThreshold;
    final theme = Theme.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            l.isArabic ? 'تأكيد الدفع' : 'Confirm payment',
            style: TextStyle(
              color: isLargeAmount ? theme.colorScheme.error : null,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.isArabic
                    ? 'دفع $amt $_effectiveCurrency إلى $target الآن؟'
                    : 'Pay $amt $_effectiveCurrency to $target now?',
              ),
              if (isLargeAmount) ...[
                const SizedBox(height: 10),
                Text(
                  l.isArabic
                      ? 'مبلغ كبير — تحقق من الجهة المستلمة قبل التأكيد.'
                      : 'Large amount — double-check the recipient before confirming.',
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.shamellDialogCancel),
            ),
            FilledButton(
              style: isLargeAmount
                  ? FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                    )
                  : null,
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.isArabic ? 'ادفع' : 'Pay'),
            ),
          ],
        );
      },
    );
    if (ok == true) {
      await _pay();
    }
  }

  /// Threshold (in major currency units, e.g. dollars not cents) at
  /// which the confirm dialog upgrades to the red "Large amount"
  /// treatment. Conservative default — typical retail flows are well
  /// below this, while still catching accidental amount-typing slips
  /// on the QR scan path.
  static const double _shamellPaymentLargeAmountThreshold = 100.0;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final targetAlias = aliasCtrl.text.trim();
    final targetWallet = toCtrl.text.trim();
    final target = targetAlias.isNotEmpty ? targetAlias : targetWallet;
    final hasTarget = target.isNotEmpty;
    final content = ListView(
      padding: shamellPaymentPagePadding(context),
      children: [
        ShamellPaymentCardSurface(
          tone: ShamellPaymentCardTone.section,
          padding: shamellPaymentCardPadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.isArabic ? 'مسح ودفع' : 'Scan & pay',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                l.isArabic
                    ? 'امسح رمز الدفع أو أدخل الكود يدوياً لإرسال دفعة سريعة.'
                    : 'Scan a payment code or enter it manually to send money fast.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      height: 1.35,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: .72),
                    ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: PayActionButton(
                  label: l.isArabic ? 'مسح رمز QR للدفع' : 'Scan QR to pay',
                  onTap: _scan,
                  icon: Icons.qr_code_scanner,
                  radius: 16,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (hasTarget)
          ShamellPaymentCardSurface(
            tone: ShamellPaymentCardTone.soft,
            padding: shamellPaymentCardPadding(
              context,
              tone: ShamellPaymentCardTone.soft,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.isArabic ? 'الدفع إلى' : 'Paying to',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  target,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_targetLabel.isNotEmpty && _targetLabel != target) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.storefront_outlined, size: 16),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          l.isArabic
                              ? 'التاجر: $_targetLabel'
                              : 'Merchant: $_targetLabel',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: .75),
                                  ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (targetWallet.isNotEmpty && targetAlias.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      targetWallet,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: .70),
                      ),
                    ),
                  ),
                if (noteCtrl.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ShamellPaymentMetricChip(
                    icon: Icons.sticky_note_2_outlined,
                    label: l.isArabic ? 'ملاحظة' : 'Note',
                    value: noteCtrl.text.trim(),
                  ),
                ],
              ],
            ),
          ),
        if (hasTarget) const SizedBox(height: 12),
        if (_showAmountPrompt) ...[
          ShamellPaymentCardSurface(
            tone: ShamellPaymentCardTone.soft,
            padding: shamellPaymentCardPadding(
              context,
              tone: ShamellPaymentCardTone.soft,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.isArabic
                      ? 'أدخل المبلغ لهذا الدفع'
                      : 'Enter amount for this payment',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: amtCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Amount ($_effectiveCurrency)',
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  // Gate on the money-mutation guard so double-taps
                  // (or rebuild-driven re-entry while the in-flight
                  // /transfer is still pending) can't mint a second
                  // transfer with a fresh idempotency key.
                  child: PayActionButton(
                    label: l.isArabic ? 'تأكيد الدفع' : 'Confirm payment',
                    onTap: isMoneyMutationInFlight ? null : _confirmAndPay,
                    icon: Icons.arrow_forward_rounded,
                    radius: 16,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (out.isNotEmpty)
          ShamellPaymentCardSurface(
            tone: ShamellPaymentCardTone.soft,
            padding: shamellPaymentCardPadding(
              context,
              tone: ShamellPaymentCardTone.soft,
            ),
            child: SelectableText(out),
          ),
      ],
    );

    return content;
  }
}
