import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../main.dart' show LoginPage;
import '../../core/account_snapshot_store.dart';
import '../../core/app_activity.dart';
import '../../core/app_sounds.dart';
import '../../core/payment_event_bus.dart';
import '../../core/payment_event_stream.dart';
import '../../core/device_binding_reauth.dart';
import '../../core/format.dart' show fmtCents;
import '../../core/history_page.dart';
import '../../core/design_tokens.dart';
import '../../core/perf.dart';
import '../../core/l10n.dart';
import '../../core/ui_kit.dart';
import '../../core/safe_set_state.dart';
import '../../core/capabilities.dart';
import 'payments_bills.dart';
import 'payments_attestation.dart';
import 'payments_card_style.dart';
import 'currency_symbol_store.dart';
import 'payments_idempotency.dart';
import 'payments_receive_pay.dart';
import 'payments_advanced.dart';
import 'payments_exchange.dart';
import 'supported_currencies.dart';
import 'payments_receipt.dart';
import 'payments_send.dart' show GroupPayPage;
import 'payments_requests.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import 'package:shamell_flutter/core/http_error.dart';
import 'package:shamell_flutter/core/base_url.dart';
import 'package:shamell_flutter/core/device_id.dart';

class _PaymentsOverviewReauthTriggered implements Exception {
  const _PaymentsOverviewReauthTriggered();
}

class PaymentOverviewTab extends StatefulWidget {
  final String baseUrl;
  final String walletId;
  final String deviceId;
  final String? initialSection;
  final http.Client? client;
  final VoidCallback? onCriticalSessionFailure;
  const PaymentOverviewTab(
      {super.key,
      required this.baseUrl,
      required this.walletId,
      required this.deviceId,
      this.initialSection,
      this.client,
      this.onCriticalSessionFailure});
  @override
  State<PaymentOverviewTab> createState() => _PaymentOverviewTabState();
}

class _PaymentOverviewTabState extends State<PaymentOverviewTab>
    with SafeSetStateMixin<PaymentOverviewTab>, WidgetsBindingObserver {
  static const Duration _paymentsOverviewRequestTimeout = Duration(seconds: 15);
  bool _loading = true;
  int? _balanceCents;
  int? _cashBalanceCents;
  int _promoCreditCents = 0;
  int _refundCreditCents = 0;
  int _corporateCreditCents = 0;
  bool _walletBucketsLoaded = false;
  String _curSym = 'SYP';
  List<Map<String, dynamic>> _recent = [];
  String _out = '';
  int? _savingsCents;
  bool _handledInitialSection = false;
  List<Map<String, String>> _linkedCards = const <Map<String, String>>[];
  bool _paymentsBillsEnabled = false;
  bool _paymentsCashVouchersEnabled = false;
  bool _paymentsSavingsEnabled = false;
  StreamSubscription<PaymentEvent>? _paymentEventSub;
  Future<void>? _pendingRefreshFromEvent;

  @override
  void initState() {
    super.initState();
    _init();
    _paymentEventSub =
        PaymentEventBus.instance.stream.listen(_onPaymentEvent);
    _maybeStartRealtimeStream();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant PaymentOverviewTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.walletId != widget.walletId ||
        oldWidget.baseUrl != widget.baseUrl) {
      // The parent shell typically resolves the wallet id asynchronously and
      // rebuilds us once it lands; pick up the realtime stream then.
      _maybeStartRealtimeStream();
    }
  }

  void _maybeStartRealtimeStream() {
    if (widget.walletId.isEmpty || widget.baseUrl.isEmpty) return;
    unawaited(PaymentEventStream.instance.start(
      baseUrl: widget.baseUrl,
      walletId: widget.walletId,
      deviceId: widget.deviceId,
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _paymentEventSub?.cancel();
    _paymentEventSub = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted) {
      // Force-refresh on resume so users see authoritative balance after the
      // OS suspended us, and kick the realtime stream off any stale socket.
      PaymentEventStream.instance.reconnectNow();
      unawaited(_loadSnapshot());
    }
  }

  void _onPaymentEvent(PaymentEvent event) {
    if (!mounted) return;
    if (widget.walletId.isEmpty) return;
    if (event.walletId != null &&
        event.walletId!.isNotEmpty &&
        event.walletId != widget.walletId) {
      // Event addresses a different wallet (e.g. a secondary one); ignore.
      return;
    }
    if (event.kind == PaymentEventKind.unknown) return;
    // Coalesce rapid bursts so we never have two refreshes inflight.
    final pending = _pendingRefreshFromEvent;
    if (pending != null) return;
    _pendingRefreshFromEvent = _loadSnapshot().whenComplete(() {
      _pendingRefreshFromEvent = null;
    });
  }

  bool _isPaymentsOverviewReauthTriggered(Object error) =>
      error is _PaymentsOverviewReauthTriggered;

  Future<bool> _forceReauthOnCriticalHttpFailure({
    required int statusCode,
    String? rawBody,
  }) async {
    final forced = await shamellForceReauthIfCriticalAccountSessionHttpFailure(
      context,
      statusCode: statusCode,
      rawBody: rawBody,
      loginPageBuilder: (_) => const LoginPage(),
    );
    if (forced) {
      widget.onCriticalSessionFailure?.call();
    }
    return forced;
  }

  Future<bool> _forceReauthOnCriticalDeviceBindingDrift(Object error) async {
    final forced = await shamellForceReauthIfCriticalDeviceBindingDrift(
      context,
      error: error,
      loginPageBuilder: (_) => const LoginPage(),
    );
    if (forced) {
      widget.onCriticalSessionFailure?.call();
    }
    return forced;
  }

  Future<String> _effectiveDeviceId() async {
    final stable = (await loadStableDeviceId(
              baseUrlOverride: widget.baseUrl,
            ) ??
            '')
        .trim();
    if (stable.isNotEmpty) {
      return stable;
    }
    return widget.deviceId.trim();
  }

  Uri? _apiUri({
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
    return L10n.of(context).isArabic
        ? 'عنوان الخادم غير صالح.'
        : 'Invalid server URL.';
  }

  String _paymentsCashUnavailableMessage() {
    return L10n.of(context).isArabic
        ? 'ميزة السحب النقدي غير متاحة على هذا الخادم.'
        : 'Cash-out is unavailable on this server.';
  }

  String _paymentsSavingsUnavailableMessage() {
    return L10n.of(context).isArabic
        ? 'ميزة الادخار غير متاحة على هذا الخادم.'
        : 'Savings are unavailable on this server.';
  }

  Future<void> _init() async {
    setState(() => _loading = true);
    try {
      _out = '';
      _cashBalanceCents = null;
      _promoCreditCents = 0;
      _refundCreditCents = 0;
      _corporateCreditCents = 0;
      _walletBucketsLoaded = false;
      await _loadPrefs();
      if (widget.walletId.isNotEmpty) {
        await _loadCachedSnapshot();
      }
      // Linked cards are secondary UI; do not block the first wallet paint on
      // a slower secure-store roundtrip.
      unawaited(_loadLinkedCards());
      if (widget.walletId.isNotEmpty) {
        await _loadSnapshot();
      }
      if (!_handledInitialSection) {
        _handledInitialSection = true;
        await _maybeOpenInitialSection();
      }
    } catch (e) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      _out = sanitizeExceptionForUi(
        error: e,
        isArabic: L10n.of(context).isArabic,
      );
      Perf.action('payments_overview_error');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _maybeOpenInitialSection() async {
    final section = (widget.initialSection ?? '').trim().toLowerCase();
    if (section.isEmpty) return;
    if (!mounted) return;
    // No initial-section deep links supported.
  }

  Future<void> _loadSnapshot() async {
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    try {
      final uri = _apiUri(
        pathSegments: <String>['wallets', widget.walletId, 'snapshot'],
        queryParameters: const <String, String>{'limit': '25'},
      );
      if (uri == null) {
        _out = _invalidServerUrlMessage();
        return;
      }
      final r = await httpClient
          .get(uri, headers: await _hdrPO(widget.baseUrl))
          .timeout(_paymentsOverviewRequestTimeout);
      if (r.statusCode == 200) {
        Perf.action('payments_overview_snapshot_ok');
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        await _applySnapshot(j, persist: true, rawBody: r.body);
        await _loadWalletBuckets(httpClient);
      } else {
        if (await _forceReauthOnCriticalHttpFailure(
          statusCode: r.statusCode,
          rawBody: r.body,
        )) {
          return;
        }
        _out = sanitizeHttpError(
          statusCode: r.statusCode,
          rawBody: r.body,
          isArabic: L10n.of(context).isArabic,
        );
        Perf.action('payments_overview_snapshot_fail');
      }
      // Savings overview (best-effort) only when the backend advertises support.
      if (_paymentsSavingsEnabled) {
        try {
          if (widget.walletId.isNotEmpty) {
            final suri = _apiUri(
              pathSegments: <String>['payments', 'savings', 'overview'],
              queryParameters: <String, String>{'wallet_id': widget.walletId},
            );
            if (suri == null) {
              _out = _invalidServerUrlMessage();
              return;
            }
            final sr = await httpClient
                .get(suri, headers: await _hdrPO(widget.baseUrl))
                .timeout(_paymentsOverviewRequestTimeout);
            if (sr.statusCode == 200) {
              final sj = jsonDecode(sr.body) as Map<String, dynamic>;
              final sb = sj['savings_balance_cents'];
              if (sb is int) {
                _savingsCents = sb;
              } else if (sb is num) {
                _savingsCents = sb.toInt();
              }
            } else if (await _forceReauthOnCriticalHttpFailure(
              statusCode: sr.statusCode,
              rawBody: sr.body,
            )) {
              return;
            }
          }
        } catch (_) {}
      }
    } catch (e) {
      if (await _forceReauthOnCriticalDeviceBindingDrift(e)) {
        return;
      }
      _out = sanitizeExceptionForUi(
        error: e,
        isArabic: L10n.of(context).isArabic,
      );
      Perf.action('payments_overview_snapshot_error');
    } finally {
      if (closeClient) {
        httpClient.close();
      }
    }
  }

  Future<void> _loadCachedSnapshot() async {
    try {
      final raw = await loadCachedWalletSnapshotRaw(
        widget.walletId,
        baseUrlOverride: widget.baseUrl,
      );
      if (raw == null || raw.isEmpty) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      await _applySnapshot(j, persist: false);
      if (mounted) {
        // Sobald Cache-Daten da sind, keinen Spinner mehr anzeigen.
        setState(() => _loading = false);
      }
    } catch (_) {}
  }

  Future<void> _loadWalletBuckets(http.Client httpClient) async {
    if (widget.walletId.isEmpty) return;
    try {
      final uri = _apiUri(
        pathSegments: <String>['wallets', widget.walletId, 'buckets'],
      );
      if (uri == null) return;
      final r = await httpClient
          .get(uri, headers: await _hdrPO(widget.baseUrl))
          .timeout(_paymentsOverviewRequestTimeout);
      if (r.statusCode != 200) {
        if (await _forceReauthOnCriticalHttpFailure(
          statusCode: r.statusCode,
          rawBody: r.body,
        )) {
          throw const _PaymentsOverviewReauthTriggered();
        }
        return;
      }
      final j = jsonDecode(r.body);
      if (j is! Map<String, dynamic>) return;
      final cash = j['cash_balance_cents'];
      final promo = j['promo_credit_cents'];
      final refund = j['refund_credit_cents'];
      final corporate = j['corporate_credit_cents'];
      if (cash is num) _cashBalanceCents = cash.toInt();
      _promoCreditCents = promo is num ? promo.toInt() : 0;
      _refundCreditCents = refund is num ? refund.toInt() : 0;
      _corporateCreditCents = corporate is num ? corporate.toInt() : 0;
      _walletBucketsLoaded = true;
    } on _PaymentsOverviewReauthTriggered {
      rethrow;
    } catch (e) {
      if (await _forceReauthOnCriticalDeviceBindingDrift(e)) {
        throw const _PaymentsOverviewReauthTriggered();
      }
    }
  }

  Future<void> _applySnapshot(
    Map<String, dynamic> j, {
    required bool persist,
    String? rawBody,
  }) async {
    try {
      final w = j['wallet'];
      if (w is Map<String, dynamic>) {
        _balanceCents = (w['balance_cents'] ?? 0) as int;
        final cur = (w['currency'] ?? '').toString();
        if (cur.isNotEmpty) {
          _curSym = cur;
          unawaited(
            saveStoredCurrencySymbol(cur, baseUrl: widget.baseUrl),
          );
        }
      }
      final arr = j['txns'];
      if (arr is List) {
        _recent = arr.whereType<Map<String, dynamic>>().toList();
      }
      if (persist && rawBody != null) {
        await saveCachedWalletSnapshotRaw(
          widget.walletId,
          rawBody,
          baseUrlOverride: widget.baseUrl,
        );
      }
    } catch (_) {}
  }

  Future<void> _loadPrefs() async {
    try {
      final cs = await loadStoredCurrencySymbol(baseUrl: widget.baseUrl);
      if (cs != null && cs.isNotEmpty) _curSym = cs;
    } catch (_) {}
    try {
      final caps = await ShamellCapabilities.loadForBaseUrl(widget.baseUrl);
      _paymentsBillsEnabled = caps.paymentsBills;
      _paymentsCashVouchersEnabled = caps.paymentsCashVouchers;
      _paymentsSavingsEnabled = caps.paymentsSavings;
    } catch (_) {}
    if (!_paymentsSavingsEnabled) {
      _savingsCents = null;
    }
  }

  Future<void> _loadLinkedCards() async {
    try {
      final raw = await loadCachedWalletLinkedCardsRawList(
        baseUrlOverride: widget.baseUrl,
      );
      final list = <Map<String, String>>[];
      for (final s in raw) {
        try {
          final m = jsonDecode(s) as Map<String, dynamic>;
          final label = (m['label'] ?? '').toString();
          final last4 = (m['last4'] ?? '').toString();
          final brand = (m['brand'] ?? '').toString();
          if (label.isEmpty && last4.isEmpty) continue;
          list.add(<String, String>{
            'label': label,
            'last4': last4,
            'brand': brand,
          });
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _linkedCards = list;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveLinkedCards() async {
    try {
      final list = _linkedCards
          .map((m) => jsonEncode(<String, String>{
                'label': m['label'] ?? '',
                'last4': m['last4'] ?? '',
                'brand': m['brand'] ?? '',
              }))
          .toList();
      await saveCachedWalletLinkedCardsRawList(
        list,
        baseUrlOverride: widget.baseUrl,
      );
    } catch (_) {}
  }

  Future<void> _refresh() async {
    await _init();
  }

  Map<String, dynamic>? _computeRecentSummary() {
    try {
      if (_recent.isEmpty || widget.walletId.isEmpty) return null;
      int inC = 0, outC = 0;
      int inCnt = 0, outCnt = 0;
      for (final t in _recent) {
        final row = t;
        final cents = (row['amount_cents'] ?? 0) as int;
        final from = (row['from_wallet_id'] ?? '').toString();
        final isOut = from == widget.walletId;
        if (isOut) {
          outC += cents;
          outCnt++;
        } else {
          inC += cents;
          inCnt++;
        }
      }
      return {
        'inC': inC,
        'outC': outC,
        'inCnt': inCnt,
        'outCnt': outCnt,
      };
    } catch (_) {
      return null;
    }
  }

  void _goToTab(BuildContext context, int index) {
    final ctrl = DefaultTabController.of(context);
    ctrl.animateTo(index);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final summary = _computeRecentSummary();
    final pagePadding = shamellPaymentPagePadding(context);
    final children = <Widget>[
      ShamellPaymentCardSurface(
        child: Padding(
          padding: const EdgeInsets.all(0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.isArabic ? 'محفظتك' : 'Wallet & balance',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              _walletHero(),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (summary != null)
        ShamellPaymentCardSurface(
          tone: ShamellPaymentCardTone.soft,
          child: Padding(
            padding: const EdgeInsets.all(0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.isArabic ? 'ملخص المدفوعات' : 'Payments summary',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _summaryChip(
                      context,
                      label: l.isArabic ? 'خارج المحفظة' : 'Sent',
                      value:
                          '${fmtCents((summary['outC'] ?? 0) as int)} $_curSym · ${(summary['outCnt'] ?? 0)}',
                    ),
                    _summaryChip(
                      context,
                      label: l.isArabic ? 'إلى المحفظة' : 'Received',
                      value:
                          '${fmtCents((summary['inC'] ?? 0) as int)} $_curSym · ${(summary['inCnt'] ?? 0)}',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: widget.walletId.isEmpty
                        ? null
                        : () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => HistoryPage(
                                  baseUrl: widget.baseUrl,
                                  walletId: widget.walletId,
                                ),
                              ),
                            );
                          },
                    child: Text(
                      l.isArabic
                          ? 'عرض كل الحركات بالتفصيل'
                          : 'Open full payments history',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.primary.withValues(alpha: .85),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      if (summary != null) const SizedBox(height: 12),
      ShamellPaymentCardSurface(
        child: Padding(
          padding: const EdgeInsets.all(0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.isArabic ? 'إجراءات سريعة' : 'Quick actions',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              _quickActions(context),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      ShamellPaymentCardSurface(
        child: Padding(
          padding: const EdgeInsets.all(0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _paymentsCashVouchersEnabled
                    ? (l.isArabic
                        ? 'تمويل المحفظة والسحب'
                        : 'Wallet funding & cash‑out')
                    : (l.isArabic ? 'تمويل المحفظة' : 'Wallet funding'),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                _paymentsCashVouchersEnabled
                    ? (l.isArabic
                        ? 'شحن الرصيد أو إنشاء رمز سحب نقدي، مشابه لتجربة SyrChat Pay.'
                        : 'Top up your balance or create a cash‑out code, similar to SyrChat Pay.')
                    : (l.isArabic
                        ? 'شحن رصيدك باستخدام مسار الدفع المدعوم حالياً.'
                        : 'Top up your balance using the currently supported payment path.'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: .70),
                ),
              ),
              const SizedBox(height: 12),
              _fundingActionTile(
                icon: Icons.add_card_outlined,
                title: l.isArabic ? 'شحن المحفظة' : 'Top up wallet',
                subtitle: l.isArabic
                    ? 'إضافة رصيد إلى محفظة SyrChat Pay.'
                    : 'Add balance to your SyrChat Pay wallet.',
                onTap: widget.walletId.isEmpty
                    ? () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              l.isArabic
                                  ? 'يرجى إعداد المحفظة أولاً.'
                                  : 'Please set up your wallet first.',
                            ),
                          ),
                        );
                      }
                    : _openTopupSheet,
              ),
              if (_paymentsCashVouchersEnabled)
                _fundingActionTile(
                  icon: Icons.payments_outlined,
                  title: l.isArabic ? 'سحب نقدي (رمز)' : 'Cash out (code)',
                  subtitle: l.isArabic
                      ? 'إنشاء رمز لسحب مبلغ نقدي.'
                      : 'Create a code for a cash withdrawal.',
                  onTap: () {
                    if (widget.walletId.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            l.isArabic
                                ? 'يرجى إعداد المحفظة أولاً.'
                                : 'Please set up your wallet first.',
                          ),
                        ),
                      );
                      return;
                    }
                    _openCashoutSheet();
                  },
                ),
              const SizedBox(height: 12),
              if (_linkedCards.isNotEmpty) ...[
                Text(
                  l.isArabic
                      ? 'بطاقات مرتبطة (محفوظة محلياً)'
                      : 'Linked cards (stored locally)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withValues(alpha: .80),
                  ),
                ),
                const SizedBox(height: 4),
                Column(
                  children: _linkedCards.map((c) {
                    final label = (c['label'] ?? '').trim();
                    final last4 = (c['last4'] ?? '').trim();
                    final brand = (c['brand'] ?? '').trim();
                    final title = label.isNotEmpty
                        ? label
                        : (brand.isNotEmpty ? brand : 'Card');
                    final subtitle = last4.isNotEmpty
                        ? (l.isArabic
                            ? 'آخر ٤ أرقام: $last4'
                            : 'Last 4 digits: $last4')
                        : (brand.isNotEmpty ? brand : '');
                    return ShamellPaymentListTileCard(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Tokens.colorPayments.withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.credit_card_outlined,
                          size: 20,
                          color: Tokens.colorPayments,
                        ),
                      ),
                      title: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: subtitle.isEmpty
                          ? null
                          : Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .70),
                              ),
                            ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () {
                          setState(() {
                            _linkedCards =
                                List<Map<String, String>>.from(_linkedCards)
                                  ..remove(c);
                          });
                          // ignore: discarded_futures
                          _saveLinkedCards();
                        },
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 4),
              ],
              _fundingActionTile(
                icon: Icons.credit_card_outlined,
                title: l.isArabic
                    ? 'إدارة البطاقات المرتبطة'
                    : 'Manage linked cards',
                subtitle: l.isArabic
                    ? 'إضافة أو حذف البطاقات المحفوظة محلياً.'
                    : 'Add or remove locally stored cards.',
                onTap: _openManageCardsSheet,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (_paymentsSavingsEnabled)
        ShamellPaymentCardSurface(
          tone: ShamellPaymentCardTone.soft,
          child: Padding(
            padding: const EdgeInsets.all(0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.isArabic ? 'الادخار' : 'Savings',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                _savingsSection(context),
              ],
            ),
          ),
        ),
      ShamellPaymentSection(
        title: l.isArabic ? 'النشاط الأخير' : 'Recent activity',
        subtitle: l.isArabic
            ? 'أحدث الحركات على محفظتك.'
            : 'Latest payments on your wallet.',
        trailing: TextButton(
          onPressed: widget.walletId.isEmpty
              ? null
              : () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => HistoryPage(
                        baseUrl: widget.baseUrl,
                        walletId: widget.walletId,
                      ),
                    ),
                  );
                },
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: Text(l.viewAll),
        ),
        children: [
          ShamellPaymentListTileCard(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            leading: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Tokens.colorPayments.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.receipt_long_outlined,
                size: 18,
                color: Tokens.colorPayments,
              ),
            ),
            title: Text(
              l.isArabic ? 'سجل الفواتير' : 'Bill history',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              l.isArabic
                  ? 'فواتير ومدفوعات خدماتك في قائمة واحدة.'
                  : 'Bills and service payments in one clean list.',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .66),
              ),
            ),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: widget.walletId.isEmpty
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => HistoryPage(
                          baseUrl: widget.baseUrl,
                          walletId: widget.walletId,
                          initialKind: 'bill',
                        ),
                      ),
                    );
                  },
          ),
          const SizedBox(height: 8),
          if (_loading && _balanceCents == null && _recent.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
            )
          else if (widget.walletId.isEmpty)
            _overviewEmptyMessage(
              l.isArabic ? 'لم يتم تعيين المحفظة بعد' : 'Wallet not set yet',
            )
          else if (_recent.isEmpty)
            _overviewEmptyMessage(
              l.isArabic ? 'لا توجد مدفوعات حديثة' : 'No recent payments yet.',
            )
          else
            _recentList(),
          if (_out.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _overviewEmptyMessage(
                _out,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
        ],
      ),
    ];
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: pagePadding,
        children: children,
      ),
    );
  }

  Widget _summaryChip(BuildContext context,
      {required String label, required String value}) {
    return ShamellPaymentMetricChip(
      label: label,
      value: value,
    );
  }

  Widget _fundingActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ShamellPaymentListTileCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Tokens.colorPayments.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 19, color: Tokens.colorPayments),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: .66),
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }

  Widget _walletHero() {
    final bal = _cashBalanceCents ?? _balanceCents;
    final sav = _savingsCents;
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isAr = l.isArabic;
    final isDark = theme.brightness == Brightness.dark;
    final walletLabel = l.homeWallet;
    final walletIdLabel = widget.walletId.isEmpty ? l.notSet : widget.walletId;
    final balanceLabel = isAr ? 'الرصيد النقدي' : 'Cash balance';
    final savingsLabel = isAr ? 'الادخار' : 'Savings';
    final promoLabel = isAr ? 'رصيد ترويجي' : 'Promo credit';
    final refundLabel = isAr ? 'رصيد استرجاع' : 'Refund credit';
    final corporateLabel = isAr ? 'رصيد شركات' : 'Corporate credit';
    final fgPrimary = isDark ? Colors.white : Colors.black87;
    final fgSecondary =
        (isDark ? Colors.white : Colors.black87).withValues(alpha: .70);

    return ShamellPaymentCardSurface(
      tone: ShamellPaymentCardTone.hero,
      padding:
          shamellPaymentCardPadding(context, tone: ShamellPaymentCardTone.hero),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white.withValues(alpha: isDark ? .10 : .62),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: isDark ? .12 : .65),
                  ),
                ),
                child: Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 26,
                  color: Tokens.colorPayments.withValues(alpha: .96),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      walletLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        letterSpacing: .2,
                        color: fgSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      walletIdLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: fgPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 7,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      balanceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
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
                              ? (_loading ? '…' : '—')
                              : '${fmtCents(bal)} $_curSym',
                          maxLines: 1,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 24,
                            color: fgPrimary,
                          ),
                        ),
                      ),
                    ),
                    if (_paymentsSavingsEnabled && sav != null && sav > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        savingsLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 11,
                          color: fgSecondary,
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            '${fmtCents(sav)} $_curSym',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: fgPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (_walletBucketsLoaded) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (_promoCreditCents > 0)
                  _summaryChip(
                    context,
                    label: promoLabel,
                    value: '${fmtCents(_promoCreditCents)} $_curSym',
                  ),
                if (_refundCreditCents > 0)
                  _summaryChip(
                    context,
                    label: refundLabel,
                    value: '${fmtCents(_refundCreditCents)} $_curSym',
                  ),
                if (_corporateCreditCents > 0)
                  _summaryChip(
                    context,
                    label: corporateLabel,
                    value: '${fmtCents(_corporateCreditCents)} $_curSym',
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _quickActions(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final compact = shamellPaymentIsCompact(context);
    final itemWidth = compact ? 72.0 : 80.0;
    final iconSize = compact ? 40.0 : 44.0;

    Widget item({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
    }) {
      return SizedBox(
        width: itemWidth,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(
                  color: Tokens.colorPayments.withValues(alpha: .08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: Tokens.colorPayments.withValues(alpha: .95),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: compact ? 10.5 : 11,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Wrap(
      spacing: compact ? 10 : 16,
      runSpacing: compact ? 10 : 12,
      children: [
        item(
          icon: Icons.qr_code_2,
          label: l.isArabic ? 'الدفع والاستلام' : 'Pay & receive',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ReceivePayPage(
                  baseUrl: widget.baseUrl,
                  fromWalletId: widget.walletId,
                  walletCurrency: _curSym,
                ),
              ),
            );
          },
        ),
        item(
          icon: Icons.arrow_upward_rounded,
          label: l.isArabic ? 'تحويل' : 'Transfer',
          onTap: () => _goToTab(context, 2),
        ),
        // Exchange tile hidden when only a single currency is
        // supported app-wide (Syria-only deployment). Re-enable by
        // restoring entries in `supported_currencies.dart`.
        if (shamellSupportedWalletCurrencies.length > 1)
          item(
            icon: Icons.currency_exchange,
            label: l.isArabic ? 'صرف' : 'Exchange',
            onTap: () {
              if (widget.walletId.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      l.isArabic
                          ? 'يرجى إعداد المحفظة أولاً.'
                          : 'Please set up your wallet first.',
                    ),
                  ),
                );
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PaymentExchangePage(
                    baseUrl: widget.baseUrl,
                    fromWalletId: widget.walletId,
                    walletCurrency: _curSym,
                    client: widget.client,
                  ),
                ),
              );
            },
          ),
        item(
          icon: Icons.tune_outlined,
          label: l.isArabic ? 'ميزات' : 'Features',
          onTap: () {
            if (widget.walletId.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    l.isArabic
                        ? 'يرجى إعداد المحفظة أولاً.'
                        : 'Please set up your wallet first.',
                  ),
                ),
              );
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PaymentsAdvancedPage(
                  baseUrl: widget.baseUrl,
                  walletId: widget.walletId,
                  deviceId: widget.deviceId,
                  currency: _curSym,
                  client: widget.client,
                ),
              ),
            );
          },
        ),
        if (_paymentsBillsEnabled)
          item(
            icon: Icons.receipt_long_outlined,
            label: l.isArabic ? 'الفواتير' : 'Bills',
            onTap: () {
              if (widget.walletId.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      l.isArabic
                          ? 'يرجى إعداد المحفظة أولاً.'
                          : 'Please set up your wallet first.',
                    ),
                  ),
                );
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BillsPage(
                    widget.baseUrl,
                    widget.walletId,
                    widget.deviceId,
                  ),
                ),
              );
            },
          ),
        item(
          icon: Icons.groups_2_outlined,
          label: l.isArabic ? 'تقسيم الفاتورة' : 'Split bill',
          onTap: () {
            if (widget.walletId.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    l.isArabic
                        ? 'يرجى إعداد المحفظة أولاً.'
                        : 'Please set up your wallet first.',
                  ),
                ),
              );
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GroupPayPage(
                  baseUrl: widget.baseUrl,
                  fromWalletId: widget.walletId,
                  deviceId: widget.deviceId,
                  walletCurrency: _curSym,
                ),
              ),
            );
          },
        ),
        item(
          icon: Icons.pending_actions_outlined,
          label: l.isArabic ? 'طلبات الدفع' : 'Payment requests',
          onTap: () {
            if (widget.walletId.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    l.isArabic
                        ? 'يرجى إعداد المحفظة أولاً.'
                        : 'Please set up your wallet first.',
                  ),
                ),
              );
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RequestsPage(
                  baseUrl: widget.baseUrl,
                  walletId: widget.walletId,
                  deviceId: widget.deviceId,
                  walletCurrency: _curSym,
                ),
              ),
            );
          },
        ),
        item(
          icon: Icons.storefront_outlined,
          label: l.isArabic ? 'QR تاجر' : 'Merchant QR',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ReceivePayPage(
                  baseUrl: widget.baseUrl,
                  fromWalletId: widget.walletId,
                  walletCurrency: _curSym,
                ),
              ),
            );
          },
        ),
        item(
          icon: Icons.arrow_downward_rounded,
          label: l.isArabic ? 'استلام' : 'Receive',
          onTap: () => _goToTab(context, 3),
        ),
      ],
    );
  }

  Future<void> _openTopupSheet() async {
    final l = L10n.of(context);
    if (widget.walletId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'الرجاء إعداد المحفظة أولاً'
                : 'Please set up your wallet first',
          ),
        ),
      );
      return;
    }
    final amountCtrl = TextEditingController();
    bool submitting = false;
    String? error;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final bottom = MediaQuery.of(ctx).viewInsets.bottom;
          final walletLabel = widget.walletId.trim().length > 16
              ? '${widget.walletId.trim().substring(0, 8)}…${widget.walletId.trim().substring(widget.walletId.trim().length - 4)}'
              : widget.walletId.trim();
        final balanceCents = _cashBalanceCents ?? _balanceCents;
        return Padding(
          padding:
              EdgeInsets.only(bottom: bottom, left: 12, right: 12, top: 12),
          child: StatefulBuilder(
            builder: (ctx2, setStateSB) {
              final theme = Theme.of(ctx2);
              return SingleChildScrollView(
                child: ShamellPaymentCardSurface(
                  tone: ShamellPaymentCardTone.hero,
                  radius: 28,
                  padding: shamellPaymentCardPadding(
                    ctx2,
                    tone: ShamellPaymentCardTone.hero,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l.isArabic ? 'شحن المحفظة' : 'Top up wallet',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.isArabic
                            ? 'أدخل المبلغ الذي تريد شحنه إلى محفظتك.'
                            : 'Enter the amount you want to add to your wallet balance.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .70),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ShamellPaymentMetricChip(
                            label: l.isArabic ? 'المحفظة' : 'Wallet',
                            value: walletLabel,
                            icon: Icons.account_balance_wallet_outlined,
                          ),
                          if (balanceCents != null)
                            ShamellPaymentMetricChip(
                              label: l.isArabic ? 'الرصيد' : 'Balance',
                              value: '${fmtCents(balanceCents)} $_curSym',
                              icon: Icons.savings_outlined,
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'المبلغ ($_curSym)'
                              : 'Amount ($_curSym)',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [50, 100, 250].map((preset) {
                          return ShamellPaymentPillButton(
                            label: Text('$preset $_curSym'),
                            icon: const Icon(
                              Icons.add_rounded,
                              size: 16,
                            ),
                            onPressed: submitting
                                ? null
                                : () {
                                    amountCtrl.text = preset.toString();
                                    setStateSB(() {
                                      error = null;
                                    });
                                  },
                          );
                        }).toList(growable: false),
                      ),
                      if (error != null && error!.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          error!,
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: ShamellPaymentPillButton(
                              label: Text(l.shamellDialogCancel),
                              icon: const Icon(
                                Icons.close_rounded,
                                size: 16,
                              ),
                              onPressed: submitting
                                  ? null
                                  : () => Navigator.of(ctx2).pop(),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: PrimaryButton(
                              label: submitting
                                  ? (l.isArabic ? 'جارٍ الشحن…' : 'Topping up…')
                                  : (l.isArabic ? 'شحن' : 'Top up'),
                              onPressed: submitting
                                  ? null
                                  : () async {
                                      final raw = amountCtrl.text
                                          .trim()
                                          .replaceAll(',', '.');
                                      final amt = double.tryParse(raw) ?? 0;
                                      if (!amt.isFinite || amt <= 0) {
                                        setStateSB(() {
                                          error = l.payCheckInputs;
                                        });
                                        return;
                                      }
                                      setStateSB(() {
                                        submitting = true;
                                        error = null;
                                      });
                                      try {
                                        await _submitTopup(amt);
                                        if (context.mounted) {
                                          Navigator.of(ctx2).pop();
                                        }
                                      } catch (e) {
                                        if (_isPaymentsOverviewReauthTriggered(
                                            e)) {
                                          return;
                                        }
                                        setStateSB(() {
                                          submitting = false;
                                          error =
                                              sanitizeExceptionForUi(error: e);
                                        });
                                      }
                                    },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
      );
    } finally {
      amountCtrl.dispose();
    }
  }

  Future<void> _submitTopup(double amountMajor) async {
    final l = L10n.of(context);
    final uri = _apiUri(
      pathSegments: <String>['payments', 'wallets', widget.walletId, 'topup'],
    );
    if (uri == null) {
      _out = _invalidServerUrlMessage();
      throw StateError(_invalidServerUrlMessage());
    }
    final amountCents = shamellPaymentAmountMajorToCents(amountMajor);
    final deviceId = await _effectiveDeviceId();
    final payload = <String, Object?>{
      'amount_cents': amountCents,
    };
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    try {
      final attestationHeaders = await (() async {
        try {
          return await shamellBuildPaymentMutationAttestationHeaders(
            baseUrl: widget.baseUrl,
            deviceId: deviceId,
            operation: 'payments_topup',
            resourceId: shamellPaymentTopupAttestationResourceId(
              walletId: widget.walletId,
              amountCents: amountCents,
            ),
            client: httpClient,
          );
        } on PaymentMutationAttestationHttpFailure catch (e) {
          if (await _forceReauthOnCriticalHttpFailure(
            statusCode: e.statusCode,
            rawBody: e.rawBody,
          )) {
            throw const _PaymentsOverviewReauthTriggered();
          }
          throw Exception(sanitizeHttpError(
            statusCode: e.statusCode,
            rawBody: e.rawBody,
            isArabic: l.isArabic,
          ));
        }
      })();
      final headers = await _hdrPO(widget.baseUrl, json: true);
      headers['Idempotency-Key'] = newPaymentsIdempotencyKey('topup');
      if (deviceId.isNotEmpty) {
        headers['X-Device-ID'] = deviceId;
      }
      headers.addAll(attestationHeaders);
      final r = await httpClient
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(_paymentsOverviewRequestTimeout);
      if (r.statusCode >= 200 && r.statusCode < 300) {
        unawaited(ShamellSoundEffects.play(ShamellSoundEffect.moneyReceived));
        shamellRecordAppActivity(
          baseUrl: widget.baseUrl,
          eventType: 'payment_wallet_topup',
          moduleId: 'payments',
          action: 'wallet_topup',
          metadata: <String, Object?>{
            'amount_cents': amountCents,
            'wallet_id': widget.walletId,
          },
          client: httpClient,
        );
        await _loadSnapshot();
        if (mounted) {
          setState(() {});
        }
        final msg =
            l.isArabic ? 'تم شحن المحفظة بنجاح.' : 'Wallet top‑up successful.';
        if (Scaffold.maybeOf(context) != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
        }
        return;
      }
      if (await _forceReauthOnCriticalHttpFailure(
        statusCode: r.statusCode,
        rawBody: r.body,
      )) {
        throw const _PaymentsOverviewReauthTriggered();
      }
      throw Exception(sanitizeHttpError(
        statusCode: r.statusCode,
        rawBody: r.body,
        isArabic: l.isArabic,
      ));
    } catch (e) {
      if (_isPaymentsOverviewReauthTriggered(e)) rethrow;
      if (await _forceReauthOnCriticalDeviceBindingDrift(e)) {
        throw const _PaymentsOverviewReauthTriggered();
      }
      rethrow;
    } finally {
      if (closeClient) {
        httpClient.close();
      }
    }
  }

  Future<void> _openCashoutSheet() async {
    final l = L10n.of(context);
    if (widget.walletId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'الرجاء إعداد المحفظة أولاً'
                : 'Please set up your wallet first',
          ),
        ),
      );
      return;
    }
    final amountCtrl = TextEditingController();
    final secretCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    bool submitting = false;
    String? error;
    try {
      await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        final walletLabel = widget.walletId.trim().length > 16
            ? '${widget.walletId.trim().substring(0, 8)}…${widget.walletId.trim().substring(widget.walletId.trim().length - 4)}'
            : widget.walletId.trim();
        return Padding(
          padding:
              EdgeInsets.only(bottom: bottom, left: 12, right: 12, top: 12),
          child: StatefulBuilder(
            builder: (ctx2, setStateSB) {
              final theme = Theme.of(ctx2);
              return SingleChildScrollView(
                child: ShamellPaymentCardSurface(
                  tone: ShamellPaymentCardTone.hero,
                  radius: 28,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l.isArabic ? 'سحب نقدي برمز' : 'Cash out with code',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.isArabic
                            ? 'أنشئ رمزاً يمكن تسليمه لوكيل أو مستلم مع عبارة سرية للتحقق.'
                            : 'Create a code for an agent or recipient, protected by a secret phrase.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .70),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ShamellPaymentMetricChip(
                            label: l.isArabic ? 'المحفظة' : 'Wallet',
                            value: walletLabel,
                            icon: Icons.account_balance_wallet_outlined,
                          ),
                          if ((_cashBalanceCents ?? _balanceCents) != null)
                            ShamellPaymentMetricChip(
                              label: l.isArabic ? 'الرصيد' : 'Balance',
                              value:
                                  '${fmtCents(_cashBalanceCents ?? _balanceCents ?? 0)} $_curSym',
                              icon: Icons.payments_outlined,
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'المبلغ ($_curSym)'
                              : 'Amount ($_curSym)',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [50, 100, 250].map((preset) {
                          return ShamellPaymentPillButton(
                            label: Text('$preset $_curSym'),
                            icon: const Icon(Icons.add_rounded, size: 16),
                            onPressed: submitting
                                ? null
                                : () {
                                    amountCtrl.text = preset.toString();
                                    setStateSB(() {
                                      error = null;
                                    });
                                  },
                          );
                        }).toList(growable: false),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: secretCtrl,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'كلمة سر للرمز (مطلوبة)'
                              : 'Secret phrase for code (required)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'هاتف المستلم (اختياري)'
                              : 'Recipient phone (optional)',
                        ),
                      ),
                      if (error != null && error!.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          error!,
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: ShamellPaymentPillButton(
                              label: Text(l.shamellDialogCancel),
                              icon: const Icon(Icons.close_rounded, size: 16),
                              onPressed: submitting
                                  ? null
                                  : () => Navigator.of(ctx2).pop(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: PrimaryButton(
                              label: submitting
                                  ? (l.isArabic ? 'جارٍ الإنشاء…' : 'Creating…')
                                  : (l.isArabic ? 'إنشاء رمز' : 'Create code'),
                              onPressed: submitting
                                  ? null
                                  : () async {
                                      final rawAmt = amountCtrl.text
                                          .trim()
                                          .replaceAll(',', '.');
                                      final amt = double.tryParse(rawAmt) ?? 0;
                                      final secret = secretCtrl.text.trim();
                                      if (!amt.isFinite ||
                                          amt <= 0 ||
                                          secret.length < 3) {
                                        setStateSB(() {
                                          error = l.payCheckInputs;
                                        });
                                        return;
                                      }
                                      setStateSB(() {
                                        submitting = true;
                                        error = null;
                                      });
                                      try {
                                        final resp = await _submitCashout(
                                          amountMajor: amt,
                                          secret: secret,
                                          recipientPhone: phoneCtrl.text.trim(),
                                        );
                                        if (resp.isEmpty || !context.mounted) {
                                          return;
                                        }
                                        if (!context.mounted) return;
                                        Navigator.of(ctx2).pop();
                                        final code =
                                            (resp['code'] ?? '').toString();
                                        final amtC =
                                            (resp['amount_cents'] ?? 0) as int;
                                        final cur = (resp['currency'] ?? 'SYP')
                                            .toString();
                                        final formatted = fmtCents(amtC);
                                        final snack = l.isArabic
                                            ? 'رمز السحب: $code · $formatted $cur'
                                            : 'Cash‑out code: $code · $formatted $cur';
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                                SnackBar(content: Text(snack)));
                                      } catch (e) {
                                        if (_isPaymentsOverviewReauthTriggered(
                                            e)) {
                                          return;
                                        }
                                        setStateSB(() {
                                          submitting = false;
                                          error =
                                              sanitizeExceptionForUi(error: e);
                                        });
                                      }
                                    },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
    } finally {
      amountCtrl.dispose();
      secretCtrl.dispose();
      phoneCtrl.dispose();
    }
  }

  Future<Map<String, dynamic>> _submitCashout({
    required double amountMajor,
    required String secret,
    String? recipientPhone,
  }) async {
    final l = L10n.of(context);
    if (!_paymentsCashVouchersEnabled) {
      _out = _paymentsCashUnavailableMessage();
      throw StateError(_paymentsCashUnavailableMessage());
    }
    final uri = _apiUri(
      pathSegments: <String>['payments', 'cash', 'create'],
    );
    if (uri == null) {
      _out = _invalidServerUrlMessage();
      throw StateError(_invalidServerUrlMessage());
    }
    final deviceId = await _effectiveDeviceId();
    final headers = await _hdrPO(widget.baseUrl, json: true);
    headers['Idempotency-Key'] = newPaymentsIdempotencyKey('cash');
    if (deviceId.isNotEmpty) {
      headers['X-Device-ID'] = deviceId;
    }
    final amountCents = shamellPaymentAmountMajorToCents(amountMajor);
    if (amountCents <= 0) {
      throw Exception(l.payCheckInputs);
    }
    final payload = <String, Object?>{
      'from_wallet_id': widget.walletId,
      'amount_cents': amountCents,
      'secret_phrase': secret,
    };
    if (recipientPhone != null && recipientPhone.trim().isNotEmpty) {
      payload['recipient_phone'] = recipientPhone.trim();
    }
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    try {
      final r = await httpClient
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(_paymentsOverviewRequestTimeout);
      if (r.statusCode >= 200 && r.statusCode < 300) {
        try {
          final body = jsonDecode(r.body);
          if (body is Map<String, dynamic>) {
            await _loadSnapshot();
            if (mounted) {
              setState(() {});
            }
            return body;
          }
        } catch (_) {}
        return <String, dynamic>{};
      }
      if (await _forceReauthOnCriticalHttpFailure(
        statusCode: r.statusCode,
        rawBody: r.body,
      )) {
        throw const _PaymentsOverviewReauthTriggered();
      }
      throw Exception(sanitizeHttpError(
        statusCode: r.statusCode,
        rawBody: r.body,
        isArabic: l.isArabic,
      ));
    } catch (e) {
      if (_isPaymentsOverviewReauthTriggered(e)) rethrow;
      if (await _forceReauthOnCriticalDeviceBindingDrift(e)) {
        throw const _PaymentsOverviewReauthTriggered();
      }
      rethrow;
    } finally {
      if (closeClient) {
        httpClient.close();
      }
    }
  }

  Future<void> _openManageCardsSheet() async {
    final l = L10n.of(context);
    String label = '';
    String last4 = '';
    String brand = '';
    String? error;
    // Allocate controllers ONCE outside the builder. The previous code
    // recreated them on every rebuild (every keystroke triggered
    // setStateSB), leaking 3 TextEditingControllers per character typed
    // and orphaning the user's input as the underlying instance changed.
    final labelCtrl = TextEditingController(text: label);
    final last4Ctrl = TextEditingController(text: last4);
    final brandCtrl = TextEditingController(text: brand);
    try {
      await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding:
              EdgeInsets.only(bottom: bottom, left: 12, right: 12, top: 12),
          child: StatefulBuilder(
            builder: (ctx2, setStateSB) {
              final theme = Theme.of(ctx2);
              return ShamellPaymentCardSurface(
                tone: ShamellPaymentCardTone.hero,
                radius: 28,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l.isArabic
                          ? 'إضافة بطاقة مرتبطة (محلياً)'
                          : 'Add linked card (local only)',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.isArabic
                          ? 'هذه البيانات تبقى على هذا الجهاز فقط لتسهيل التعرف على بطاقاتك.'
                          : 'This data stays on this device only, so you can recognise your cards faster.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .70),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ShamellPaymentMetricChip(
                          label: l.isArabic ? 'المحفوظة' : 'Saved',
                          value: _linkedCards.length.toString(),
                          icon: Icons.credit_card_outlined,
                        ),
                        ShamellPaymentMetricChip(
                          label: l.isArabic ? 'النطاق' : 'Scope',
                          value: l.isArabic ? 'محلي فقط' : 'Local only',
                          icon: Icons.phone_android_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: labelCtrl,
                      decoration: InputDecoration(
                        labelText: l.isArabic
                            ? 'اسم البطاقة (مثال: بطاقتي الرئيسية)'
                            : 'Card label (e.g. Main card)',
                      ),
                      onChanged: (v) {
                        label = v;
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: last4Ctrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l.isArabic ? 'آخر ٤ أرقام' : 'Last 4 digits',
                      ),
                      onChanged: (v) {
                        last4 = v;
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: brandCtrl,
                      decoration: InputDecoration(
                        labelText: l.isArabic
                            ? 'النوع (اختياري، مثال: Visa)'
                            : 'Brand (optional, e.g. Visa)',
                      ),
                      onChanged: (v) {
                        brand = v;
                      },
                    ),
                    if (error != null && error!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        error!,
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: ShamellPaymentPillButton(
                            label: Text(l.shamellDialogCancel),
                            icon: const Icon(Icons.close_rounded, size: 16),
                            onPressed: () => Navigator.of(ctx2).pop(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: PrimaryButton(
                            label: l.isArabic ? 'حفظ البطاقة' : 'Save card',
                            onPressed: () {
                              final lbl = label.trim();
                              final l4 = last4.trim();
                              if (lbl.isEmpty && l4.isEmpty) {
                                setStateSB(() {
                                  error = l.payCheckInputs;
                                });
                                return;
                              }
                              final card = <String, String>{
                                'label': lbl,
                                'last4': l4,
                                'brand': brand.trim(),
                              };
                              setState(() {
                                final list = List<Map<String, String>>.from(
                                    _linkedCards);
                                list.insert(0, card);
                                _linkedCards = list;
                              });
                              // ignore: discarded_futures
                              _saveLinkedCards();
                              Navigator.of(ctx2).pop();
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
    } finally {
      labelCtrl.dispose();
      last4Ctrl.dispose();
      brandCtrl.dispose();
    }
  }

  Widget _savingsSection(BuildContext context) {
    final l = L10n.of(context);
    final sav = _savingsCents ?? 0;
    final bal = _balanceCents ?? 0;
    final hasWallet = widget.walletId.isNotEmpty;
    final isLoadingSavings = _loading && _savingsCents == null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        l.isArabic
            ? 'حوّل الأموال بين رصيد المحفظة ورصيد الادخار، كما في المحافظ الفائقة.'
            : 'Move money between your wallet balance and savings, similar to super‑app wallets.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: .70),
            ),
      ),
      const SizedBox(height: 8),
      if (isLoadingSavings)
        const Center(
          child: Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        )
      else ...[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l.isArabic ? 'رصيد الادخار' : 'Savings balance',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              '${fmtCents(sav)} $_curSym',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: PrimaryButton(
                icon: Icons.savings_outlined,
                label: l.isArabic ? 'إلى الادخار' : 'Move to savings',
                expanded: true,
                onPressed: hasWallet
                    ? () => _promptSavingsMove(toSavings: true)
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: Text(
                  l.isArabic ? 'سحب من الادخار' : 'Withdraw to wallet',
                ),
                onPressed: hasWallet && sav > 0
                    ? () => _promptSavingsMove(toSavings: false)
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          l.isArabic
              ? 'المحفظة: ${fmtCents(bal)} $_curSym · الادخار: ${fmtCents(sav)} $_curSym'
              : 'Wallet: ${fmtCents(bal)} $_curSym · Savings: ${fmtCents(sav)} $_curSym',
          style: TextStyle(
            fontSize: 11,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: .60),
          ),
        ),
        const SizedBox(height: 8),
        _savingsRecentList(context),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: widget.walletId.isEmpty
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => HistoryPage(
                          baseUrl: widget.baseUrl,
                          walletId: widget.walletId,
                          initialKind: 'savings',
                        ),
                      ),
                    );
                  },
            child: Text(
              l.isArabic
                  ? 'عرض سجل الادخار بالكامل'
                  : 'View full savings history',
            ),
          ),
        ),
      ],
    ]);
  }

  Future<void> _promptSavingsMove({required bool toSavings}) async {
    final l = L10n.of(context);
    if (widget.walletId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.isArabic
            ? 'الرجاء إعداد المحفظة أولاً'
            : 'Please set up your wallet first'),
      ));
      return;
    }
    final amountCtrl = TextEditingController();
    bool submitting = false;
    String? error;
    try {
      await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding:
              EdgeInsets.only(bottom: bottom, left: 12, right: 12, top: 12),
          child: StatefulBuilder(
            builder: (ctx2, setStateSB) {
              final theme = Theme.of(ctx2);
              final sav = _savingsCents ?? 0;
              final bal = _balanceCents ?? 0;
              final title = toSavings
                  ? (l.isArabic ? 'تحويل إلى الادخار' : 'Move to savings')
                  : (l.isArabic ? 'سحب من الادخار' : 'Withdraw from savings');
              final description = toSavings
                  ? (l.isArabic
                      ? 'سيتم تحويل المبلغ من رصيد المحفظة إلى رصيد الادخار.'
                      : 'Move money from your wallet balance into savings.')
                  : (l.isArabic
                      ? 'سيتم سحب المبلغ من رصيد الادخار إلى رصيد المحفظة.'
                      : 'Withdraw money from savings back to your wallet.');
              return ShamellPaymentCardSurface(
                tone: ShamellPaymentCardTone.hero,
                radius: 28,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .72),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ShamellPaymentMetricChip(
                          label: l.isArabic ? 'المحفظة' : 'Wallet',
                          value: '${fmtCents(bal)} $_curSym',
                          icon: Icons.account_balance_wallet_outlined,
                        ),
                        ShamellPaymentMetricChip(
                          label: l.isArabic ? 'الادخار' : 'Savings',
                          value: '${fmtCents(sav)} $_curSym',
                          icon: Icons.savings_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: amountCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: l.isArabic
                            ? 'المبلغ ($_curSym)'
                            : 'Amount ($_curSym)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [50, 100, 250].map((preset) {
                        return ShamellPaymentPillButton(
                          label: Text('$preset $_curSym'),
                          icon: const Icon(Icons.add_rounded, size: 16),
                          onPressed: submitting
                              ? null
                              : () {
                                  amountCtrl.text = preset.toString();
                                  setStateSB(() {
                                    error = null;
                                  });
                                },
                        );
                      }).toList(growable: false),
                    ),
                    if (error != null && error!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        error!,
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: ShamellPaymentPillButton(
                            label: Text(l.shamellDialogCancel),
                            icon: const Icon(Icons.close_rounded, size: 16),
                            onPressed: submitting
                                ? null
                                : () => Navigator.of(ctx2).pop(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: PrimaryButton(
                            label: submitting
                                ? (l.isArabic ? 'جارٍ التنفيذ…' : 'Processing…')
                                : (toSavings
                                    ? (l.isArabic
                                        ? 'إيداع في الادخار'
                                        : 'Move to savings')
                                    : (l.isArabic
                                        ? 'سحب من الادخار'
                                        : 'Withdraw')),
                            onPressed: submitting
                                ? null
                                : () async {
                                    final raw = amountCtrl.text
                                        .trim()
                                        .replaceAll(',', '.');
                                    final amt = double.tryParse(raw) ?? 0;
                                    if (!amt.isFinite || amt <= 0) {
                                      setStateSB(() {
                                        error = l.payCheckInputs;
                                      });
                                      return;
                                    }
                                    setStateSB(() {
                                      submitting = true;
                                      error = null;
                                    });
                                    try {
                                      await _submitSavingsMove(
                                        toSavings: toSavings,
                                        amountMajor: amt,
                                      );
                                      if (context.mounted) {
                                        Navigator.of(ctx2).pop();
                                      }
                                    } catch (e) {
                                      if (_isPaymentsOverviewReauthTriggered(
                                          e)) {
                                        return;
                                      }
                                      setStateSB(() {
                                        submitting = false;
                                        error =
                                            sanitizeExceptionForUi(error: e);
                                      });
                                    }
                                  },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
    } finally {
      amountCtrl.dispose();
    }
  }

  Future<void> _submitSavingsMove(
      {required bool toSavings, required double amountMajor}) async {
    final l = L10n.of(context);
    if (!amountMajor.isFinite || amountMajor <= 0) {
      throw Exception(l.payCheckInputs);
    }
    if (!_paymentsSavingsEnabled) {
      _out = _paymentsSavingsUnavailableMessage();
      throw StateError(_paymentsSavingsUnavailableMessage());
    }
    final uri = _apiUri(
      pathSegments: <String>[
        'payments',
        'savings',
        toSavings ? 'deposit' : 'withdraw',
      ],
    );
    if (uri == null) {
      _out = _invalidServerUrlMessage();
      throw StateError(_invalidServerUrlMessage());
    }
    final deviceId = await _effectiveDeviceId();
    final headers = await _hdrPO(widget.baseUrl, json: true);
    headers['Idempotency-Key'] =
        newPaymentsIdempotencyKey(toSavings ? 'sav-dep' : 'sav-wd');
    if (deviceId.isNotEmpty) {
      headers['X-Device-ID'] = deviceId;
    }
    final payload = <String, Object?>{
      'wallet_id': widget.walletId,
      'amount': double.parse(amountMajor.toStringAsFixed(2)),
    };
    try {
      final httpClient = widget.client ?? shamellHttpClient();
      final closeClient = widget.client == null;
      try {
        final r = await httpClient
            .post(uri, headers: headers, body: jsonEncode(payload))
            .timeout(_paymentsOverviewRequestTimeout);
        if (r.statusCode >= 200 && r.statusCode < 300) {
          unawaited(ShamellSoundEffects.play(ShamellSoundEffect.success));
          shamellRecordAppActivity(
            baseUrl: widget.baseUrl,
            eventType: toSavings
                ? 'payment_savings_deposit'
                : 'payment_savings_withdraw',
            moduleId: 'payments',
            action: toSavings ? 'savings_deposit' : 'savings_withdraw',
            metadata: <String, Object?>{
              'amount_major': amountMajor,
              'wallet_id': widget.walletId,
            },
            client: httpClient,
          );
          // Refresh wallet + savings overview so the UI stays in sync.
          await _loadSnapshot();
          if (mounted) {
            setState(() {});
          }
          final msg = toSavings
              ? (l.isArabic
                  ? 'تم تحويل المبلغ إلى الادخار'
                  : 'Moved amount to savings')
              : (l.isArabic ? 'تم السحب من الادخار' : 'Withdrawn from savings');
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
          return;
        }
        if (await _forceReauthOnCriticalHttpFailure(
          statusCode: r.statusCode,
          rawBody: r.body,
        )) {
          throw const _PaymentsOverviewReauthTriggered();
        }
        throw Exception(sanitizeHttpError(
          statusCode: r.statusCode,
          rawBody: r.body,
          isArabic: l.isArabic,
        ));
      } finally {
        if (closeClient) {
          httpClient.close();
        }
      }
    } catch (e) {
      if (_isPaymentsOverviewReauthTriggered(e)) rethrow;
      if (await _forceReauthOnCriticalDeviceBindingDrift(e)) {
        throw const _PaymentsOverviewReauthTriggered();
      }
      rethrow;
    }
  }

  @visibleForTesting
  Future<void> debugSubmitTopup(double amountMajor) async {
    try {
      await _submitTopup(amountMajor);
    } on _PaymentsOverviewReauthTriggered {
      return;
    }
  }

  @visibleForTesting
  Future<void> debugSubmitCashout({
    required double amountMajor,
    required String secret,
    String? recipientPhone,
  }) async {
    try {
      await _submitCashout(
        amountMajor: amountMajor,
        secret: secret,
        recipientPhone: recipientPhone,
      );
    } on _PaymentsOverviewReauthTriggered {
      return;
    }
  }

  @visibleForTesting
  Future<void> debugSubmitSavingsMove({
    required bool toSavings,
    required double amountMajor,
  }) async {
    try {
      await _submitSavingsMove(
        toSavings: toSavings,
        amountMajor: amountMajor,
      );
    } on _PaymentsOverviewReauthTriggered {
      return;
    }
  }

  Widget _savingsRecentList(BuildContext context) {
    final l = L10n.of(context);
    final items = _recent
        .where((t) {
          final kind = (t['kind'] ?? '').toString().toLowerCase();
          return kind.startsWith('savings_');
        })
        .take(3)
        .toList();
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.isArabic ? 'أحدث حركات الادخار' : 'Recent savings activity',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 4),
        for (final t in items) _savingsRecentTile(context, t),
      ],
    );
  }

  Widget _savingsRecentTile(BuildContext context, Map<String, dynamic> t) {
    final l = L10n.of(context);
    final kind = (t['kind'] ?? '').toString().toLowerCase();
    final isDep = kind.startsWith('savings_deposit');
    final cents = (t['amount_cents'] ?? 0) as int;
    final amt = fmtCents(cents);
    final sign = isDep ? '-' : '+';
    final ts = (t['created_at'] ?? '').toString();
    final label = isDep
        ? (l.isArabic ? 'إلى الادخار' : 'To savings')
        : (l.isArabic ? 'من الادخار' : 'From savings');
    return ShamellPaymentListTileCard(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Tokens.colorPayments.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.savings_outlined,
          size: 20,
          color: Tokens.colorPayments,
        ),
      ),
      title: Text(
        '$sign$amt $_curSym',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
      subtitle: Text(
        '$label • $ts',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .70),
        ),
      ),
    );
  }

  Widget _recentList() {
    final items = _recent.take(5).toList();
    return Column(children: [
      for (final t in items) _recentTile(t),
    ]);
  }

  Widget _overviewEmptyMessage(String message, {Color? color}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: .22)
            : const Color(0xFFEFF3F8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: isDark ? .34 : .80),
        ),
      ),
      child: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: color ?? theme.colorScheme.onSurface.withValues(alpha: .66),
        ),
      ),
    );
  }

  Widget _recentTile(Map<String, dynamic> t) {
    final cents = (t['amount_cents'] ?? 0) as int;
    final isOut = (t['from_wallet_id'] ?? '').toString() == widget.walletId;
    final sign = isOut ? '-' : '+';
    final who = isOut ? (t['to_wallet_id'] ?? '') : (t['from_wallet_id'] ?? '');
    final amt = fmtCents(cents);
    final kindRaw = (t['kind'] ?? '').toString();
    final kind = kindRaw.toLowerCase();
    final ref = (t['reference'] ?? '').toString();
    final ts = (t['created_at'] ?? '').toString();
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    String mainLabel;
    if (kind.startsWith('transfer')) {
      mainLabel = L10n.of(context).isArabic ? 'تحويل' : 'Transfer';
    } else if (kind.startsWith('topup')) {
      mainLabel = L10n.of(context).isArabic ? 'شحن رصيد' : 'Top‑up';
    } else if (kind.startsWith('cash')) {
      mainLabel = L10n.of(context).isArabic ? 'سحب نقدي' : 'Cash out';
    } else if (kind.startsWith('bill')) {
      mainLabel = L10n.of(context).isArabic ? 'فاتورة' : 'Bill payment';
    } else if (kind.startsWith('savings')) {
      mainLabel = L10n.of(context).isArabic ? 'ادخار' : 'Savings movement';
    } else {
      mainLabel = kindRaw;
    }

    String subtitleText;
    if (ref.isNotEmpty && who.toString().isNotEmpty) {
      subtitleText = '$ts · $who\n$ref';
    } else if (who.toString().isNotEmpty) {
      subtitleText = '$ts · $who';
    } else if (ref.isNotEmpty) {
      subtitleText = '$ts\n$ref';
    } else {
      subtitleText = ts;
    }

    final Color amountColor =
        sign == '+' ? Tokens.colorPayments : onSurface.withValues(alpha: .85);
    final Color iconColor = Tokens.colorPayments;
    final Color iconBg = Tokens.colorPayments.withValues(alpha: .08);
    final IconData iconData =
        sign == '+' ? Icons.call_received_rounded : Icons.call_made_rounded;

    return ShamellPaymentListTileCard(
      onTap: () => showShamellPaymentReceiptSheet(
        context,
        transaction: t,
        walletId: widget.walletId,
        currency: _curSym,
      ),
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(iconData, color: iconColor, size: 20),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              mainLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$sign$amt $_curSym',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: amountColor,
            ),
          ),
        ],
      ),
      subtitle: Text(
        subtitleText,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: onSurface.withValues(alpha: .70),
        ),
      ),
    );
  }
}

Future<Map<String, String>> _hdrPO(String baseUrl, {bool json = false}) async {
  return shamellSessionHeadersForBaseUrl(baseUrl, json: json);
}
