import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../main.dart' show LoginPage;
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/app_activity.dart';
import '../../core/app_sounds.dart';
import '../../core/base_url.dart';
import '../../core/device_binding_guard.dart';
import '../../core/device_binding_reauth.dart';
import '../../core/device_id.dart';
import '../../core/l10n.dart';
import '../../core/app_shell_widgets.dart' show AppBG; // reuse bg only
import 'payments_send.dart' show PayActionButton, GroupPayPage;
import '../../core/format.dart' show fmtCents;
import '../../core/design_tokens.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import '../../core/http_error.dart';
import '../../core/safe_set_state.dart';
import 'payments_attestation.dart';
import 'payments_card_style.dart';
import 'payments_idempotency.dart';
import 'payments_qr_payload.dart';
import 'supported_currencies.dart';

const Duration _paymentsRequestsRequestTimeout = Duration(seconds: 15);
const int _paymentsRequestsPageSize = 100;

class _RequestsCursor {
  final String createdAt;
  final String id;

  const _RequestsCursor({
    required this.createdAt,
    required this.id,
  });
}

List<Map<String, dynamic>> _normalizeRequestsPage(dynamic raw) {
  if (raw is! List) return const <Map<String, dynamic>>[];
  return raw
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

_RequestsCursor? _requestsCursorFromItem(Map<String, dynamic>? item) {
  if (item == null) return null;
  final createdAt = (item['created_at'] ?? '').toString().trim();
  final id = (item['id'] ?? '').toString().trim();
  if (createdAt.isEmpty || id.isEmpty) return null;
  return _RequestsCursor(createdAt: createdAt, id: id);
}

List<Map<String, dynamic>> _mergeRequestsPages(
  List<Map<String, dynamic>> existing,
  List<Map<String, dynamic>> incoming,
) {
  if (incoming.isEmpty) return existing;
  final merged = <Map<String, dynamic>>[...existing];
  final seenIds = existing
      .map((item) => (item['id'] ?? '').toString().trim())
      .where((id) => id.isNotEmpty)
      .toSet();
  for (final item in incoming) {
    final id = (item['id'] ?? '').toString().trim();
    if (id.isEmpty || seenIds.add(id)) {
      merged.add(item);
    }
  }
  return merged;
}

DateTime? _requestsCreatedAt(Map<String, dynamic> item) {
  final raw = (item['created_at'] ?? '').toString().trim();
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toUtc();
}

int _compareRequestsDesc(Map<String, dynamic> a, Map<String, dynamic> b) {
  final at = _requestsCreatedAt(a);
  final bt = _requestsCreatedAt(b);
  if (at != null && bt != null) {
    final tsCmp = bt.compareTo(at);
    if (tsCmp != 0) return tsCmp;
  } else if (at != null) {
    return -1;
  } else if (bt != null) {
    return 1;
  }
  final aid = (a['id'] ?? '').toString();
  final bid = (b['id'] ?? '').toString();
  return bid.compareTo(aid);
}

String _normalizeRequestStatus(String raw) {
  final status = raw.trim().toLowerCase();
  if (status == 'cancelled') {
    // Accept both spellings; backend contract uses "canceled".
    return 'canceled';
  }
  return status;
}

class IncomingRequestBanner extends StatelessWidget {
  final Map<String, dynamic> req;
  // Nullable so the parent (PaymentsShell) can disable the "Accept &
  // Pay" button while a money mutation is already in flight. The
  // banner stays visible (so the user sees what's pending) but the
  // button cannot fire a duplicate accept POST.
  final VoidCallback? onAccept;
  final VoidCallback onDismiss;
  const IncomingRequestBanner(
      {super.key,
      required this.req,
      required this.onAccept,
      required this.onDismiss});
  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final rawAmountCents = req['amount_cents'];
    final amountCents = rawAmountCents is num
        ? rawAmountCents.toInt()
        : int.tryParse((rawAmountCents ?? '').toString()) ?? 0;
    final currency = (req['currency'] ?? shamellDefaultWalletCurrency)
        .toString()
        .trim()
        .toUpperCase();
    final amount = '${fmtCents(amountCents)} $currency';
    final fromWallet = (req['from_wallet_id'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ShamellPaymentCardSurface(
        tone: ShamellPaymentCardTone.soft,
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Tokens.colorPayments.withValues(alpha: .12),
            ),
            child: Icon(
              Icons.pending_actions_outlined,
              color: Tokens.colorPayments.withValues(alpha: .95),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.isArabic ? 'طلب دفعة' : 'Payment request',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  l.isArabic
                      ? 'المبلغ: $amount  ·  من: $fromWallet'
                      : 'Amount: $amount  ·  From: $fromWallet',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PayActionButton(
            label: l.isArabic ? 'قبول و دفع' : 'Accept & Pay',
            onTap: onAccept,
            radius: 16,
          ),
          const SizedBox(width: 4),
          IconButton(onPressed: onDismiss, icon: const Icon(Icons.close))
        ]),
      ),
    );
  }
}

class RequestsPage extends StatefulWidget {
  final String baseUrl;
  final String walletId;
  final String deviceId;
  final String? walletCurrency;
  final http.Client? client;
  const RequestsPage(
      {super.key,
      required this.baseUrl,
      required this.walletId,
      required this.deviceId,
      this.walletCurrency,
      this.client});
  @override
  State<RequestsPage> createState() => _RequestsPageState();
}

class _RequestsPageReauthTriggered implements Exception {
  const _RequestsPageReauthTriggered();
}

class _RequestsPageState extends State<RequestsPage>
    with SafeSetStateMixin<RequestsPage> {
  List<Map<String, dynamic>> incoming = [];
  List<Map<String, dynamic>> outgoing = [];
  String out = '';
  bool loading = true;
  bool _loadingIncomingMore = false;
  bool _loadingOutgoingMore = false;
  bool _incomingHasMore = true;
  bool _outgoingHasMore = true;
  String _currencyFilter = '';
  String? _incomingBeforeCreatedAt;
  String? _incomingBeforeId;
  String? _outgoingBeforeCreatedAt;
  String? _outgoingBeforeId;
  bool _reauthTriggered = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Uri? _requestsUri({
    String? id,
    String? action,
    Map<String, String>? queryParameters,
  }) {
    final pathSegments = <String>['payments', 'requests'];
    final trimmedId = (id ?? '').trim();
    if (trimmedId.isNotEmpty) {
      pathSegments.add(trimmedId);
    }
    final trimmedAction = (action ?? '').trim();
    if (trimmedAction.isNotEmpty) {
      pathSegments.add(trimmedAction);
    }
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

  Future<bool> _forceReauthForCriticalSessionFailure({
    required int statusCode,
    required String rawBody,
  }) async {
    if (!shamellIsCriticalAccountSessionHttpFailure(
      statusCode: statusCode,
      rawBody: rawBody,
    )) {
      return false;
    }
    if (_reauthTriggered) {
      return true;
    }
    _reauthTriggered = true;
    if (!mounted) {
      return true;
    }
    final forced = await shamellForceReauthIfCriticalAccountSessionHttpFailure(
      context,
      statusCode: statusCode,
      rawBody: rawBody,
      loginPageBuilder: (_) => const LoginPage(),
    );
    if (!forced) {
      _reauthTriggered = false;
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

  Future<void> _loadAll() async {
    setState(() => loading = true);
    try {
      final results = await Future.wait<List<Map<String, dynamic>>>([
        _fetch('incoming'),
        _fetch('outgoing'),
      ]);
      final i = results[0];
      final o = results[1];
      _applyRequestsPage(kind: 'incoming', page: i, reset: true);
      _applyRequestsPage(kind: 'outgoing', page: o, reset: true);
      out = '';
    } catch (e) {
      if (e is _RequestsPageReauthTriggered) return;
      out = sanitizeExceptionForUi(
        error: e,
        isArabic: L10n.of(context).isArabic,
      );
    }
    setState(() => loading = false);
  }

  void _applyRequestsPage({
    required String kind,
    required List<Map<String, dynamic>> page,
    required bool reset,
  }) {
    final cursor = page.isEmpty ? null : _requestsCursorFromItem(page.last);
    final hasMore = page.length >= _paymentsRequestsPageSize && cursor != null;
    switch (kind) {
      case 'incoming':
        incoming = reset ? page : _mergeRequestsPages(incoming, page);
        _incomingBeforeCreatedAt = cursor?.createdAt;
        _incomingBeforeId = cursor?.id;
        _incomingHasMore = hasMore;
        break;
      case 'outgoing':
        outgoing = reset ? page : _mergeRequestsPages(outgoing, page);
        _outgoingBeforeCreatedAt = cursor?.createdAt;
        _outgoingBeforeId = cursor?.id;
        _outgoingHasMore = hasMore;
        break;
    }
  }

  bool _isIncomingRequest(Map<String, dynamic> req) {
    final from = (req['from_wallet_id'] ?? '').toString();
    final to = (req['to_wallet_id'] ?? '').toString();
    if (to == widget.walletId && from != widget.walletId) return true;
    if (from == widget.walletId && to != widget.walletId) return false;
    return true;
  }

  Future<List<Map<String, dynamic>>> _fetch(
    String kind, {
    String? beforeCreatedAt,
    String? beforeId,
  }) async {
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    final queryParameters = <String, String>{
      'wallet_id': widget.walletId,
      'kind': kind,
      'limit': '100',
    };
    if (beforeCreatedAt != null && beforeId != null) {
      queryParameters['before_created_at'] = beforeCreatedAt;
      queryParameters['before_id'] = beforeId;
    }
    final u = _requestsUri(
      queryParameters: queryParameters,
    );
    if (u == null) {
      throw Exception(_invalidServerUrlMessage());
    }
    try {
      final r = await httpClient
          .get(u, headers: await _hdrPR(widget.baseUrl))
          .timeout(_paymentsRequestsRequestTimeout);
      if (r.statusCode != 200) {
        if (!mounted) throw const _RequestsPageReauthTriggered();
        if (await _forceReauthForCriticalSessionFailure(
          statusCode: r.statusCode,
          rawBody: r.body,
        )) {
          throw const _RequestsPageReauthTriggered();
        }
        throw Exception(
          sanitizeHttpError(
            statusCode: r.statusCode,
            rawBody: r.body,
            isArabic: L10n.of(context).isArabic,
          ),
        );
      }
      return _normalizeRequestsPage(jsonDecode(r.body));
    } finally {
      if (closeClient) {
        httpClient.close();
      }
    }
  }

  bool _hasMoreForKind(String kind) {
    switch (kind) {
      case 'incoming':
        return _incomingHasMore;
      case 'outgoing':
        return _outgoingHasMore;
      case 'pending':
        return _incomingHasMore || _outgoingHasMore;
      default:
        return false;
    }
  }

  bool _loadingMoreForKind(String kind) {
    switch (kind) {
      case 'incoming':
        return _loadingIncomingMore;
      case 'outgoing':
        return _loadingOutgoingMore;
      case 'pending':
        return _loadingIncomingMore || _loadingOutgoingMore;
      default:
        return false;
    }
  }

  Future<void> _loadMore(String kind) async {
    if (loading || _loadingMoreForKind(kind) || !_hasMoreForKind(kind)) return;
    if (kind == 'pending') {
      setState(() {
        _loadingIncomingMore = _incomingHasMore;
        _loadingOutgoingMore = _outgoingHasMore;
      });
      try {
        if (_incomingHasMore) {
          final page = await _fetch(
            'incoming',
            beforeCreatedAt: _incomingBeforeCreatedAt,
            beforeId: _incomingBeforeId,
          );
          _applyRequestsPage(kind: 'incoming', page: page, reset: false);
        }
        if (_outgoingHasMore) {
          final page = await _fetch(
            'outgoing',
            beforeCreatedAt: _outgoingBeforeCreatedAt,
            beforeId: _outgoingBeforeId,
          );
          _applyRequestsPage(kind: 'outgoing', page: page, reset: false);
        }
        out = '';
      } catch (e) {
        if (e is! _RequestsPageReauthTriggered) {
          out = sanitizeExceptionForUi(
            error: e,
            isArabic: L10n.of(context).isArabic,
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _loadingIncomingMore = false;
            _loadingOutgoingMore = false;
          });
        }
      }
      return;
    }

    setState(() {
      if (kind == 'incoming') {
        _loadingIncomingMore = true;
      } else {
        _loadingOutgoingMore = true;
      }
    });
    try {
      final page = await _fetch(
        kind,
        beforeCreatedAt: kind == 'incoming'
            ? _incomingBeforeCreatedAt
            : _outgoingBeforeCreatedAt,
        beforeId: kind == 'incoming' ? _incomingBeforeId : _outgoingBeforeId,
      );
      _applyRequestsPage(kind: kind, page: page, reset: false);
      out = '';
    } catch (e) {
      if (e is! _RequestsPageReauthTriggered) {
        out = sanitizeExceptionForUi(
          error: e,
          isArabic: L10n.of(context).isArabic,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          if (kind == 'incoming') {
            _loadingIncomingMore = false;
          } else {
            _loadingOutgoingMore = false;
          }
        });
      }
    }
  }

  Future<void> _accept(String id) async {
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    final uri = _requestsUri(id: id, action: 'accept');
    if (uri == null) {
      if (!mounted) return;
      setState(() => out = _invalidServerUrlMessage());
      return;
    }
    final deviceId = await _effectiveDeviceId();
    final attestationHeaders = await (() async {
      try {
        return await shamellBuildPaymentMutationAttestationHeaders(
          baseUrl: widget.baseUrl,
          deviceId: deviceId,
          operation: 'payments_requests_accept',
          resourceId: shamellPaymentRequestAcceptAttestationResourceId(
            requestId: id,
            toWalletId: widget.walletId,
          ),
          client: httpClient,
        );
      } on PaymentMutationAttestationHttpFailure catch (e) {
        if (await _forceReauthForCriticalSessionFailure(
          statusCode: e.statusCode,
          rawBody: e.rawBody,
        )) {
          return null;
        }
        if (mounted) {
          setState(() {
            out = sanitizeHttpError(
              statusCode: e.statusCode,
              rawBody: e.rawBody,
              isArabic: L10n.of(context).isArabic,
            );
          });
        }
        return null;
      } catch (e) {
        if (mounted) {
          setState(() {
            out = sanitizeExceptionForUi(
              error: e,
              isArabic: L10n.of(context).isArabic,
            );
          });
        }
        return null;
      }
    })();
    if (attestationHeaders == null) {
      if (closeClient) httpClient.close();
      return;
    }
    try {
      final headers = await _hdrPR(
        widget.baseUrl,
        json: true,
        deviceId: deviceId,
      );
      headers['Idempotency-Key'] =
          newPaymentsIdempotencyKey('payments-request-accept');
      headers.addAll(attestationHeaders);
      final r = await httpClient
          .post(
            uri,
            headers: headers,
            body: jsonEncode(<String, String>{
              'to_wallet_id': widget.walletId,
            }),
          )
          .timeout(_paymentsRequestsRequestTimeout);
      if (!mounted) return;
      if (r.statusCode == 200) {
        unawaited(ShamellSoundEffects.play(ShamellSoundEffect.paymentSent));
        shamellRecordAppActivity(
          baseUrl: widget.baseUrl,
          eventType: 'payment_request_accepted',
          moduleId: 'payments',
          action: 'request_accepted',
          metadata: <String, Object?>{'request_id': id},
          client: httpClient,
        );
        _loadAll();
      } else {
        if (await _forceReauthForCriticalSessionFailure(
          statusCode: r.statusCode,
          rawBody: r.body,
        )) {
          return;
        }
        setState(() {
          out = sanitizeHttpError(
            statusCode: r.statusCode,
            rawBody: r.body,
            isArabic: L10n.of(context).isArabic,
          );
        });
      }
    } finally {
      if (closeClient) httpClient.close();
    }
  }

  Future<void> _cancel(String id) async {
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    final uri = _requestsUri(id: id, action: 'cancel');
    if (uri == null) {
      if (!mounted) return;
      setState(() => out = _invalidServerUrlMessage());
      return;
    }
    final deviceId = await _effectiveDeviceId();
    final attestationHeaders = await (() async {
      try {
        return await shamellBuildPaymentMutationAttestationHeaders(
          baseUrl: widget.baseUrl,
          deviceId: deviceId,
          operation: 'payments_requests_cancel',
          resourceId: shamellPaymentRequestCancelAttestationResourceId(
            requestId: id,
            fromWalletId: widget.walletId,
          ),
          client: httpClient,
        );
      } on PaymentMutationAttestationHttpFailure catch (e) {
        if (await _forceReauthForCriticalSessionFailure(
          statusCode: e.statusCode,
          rawBody: e.rawBody,
        )) {
          return null;
        }
        if (mounted) {
          setState(() {
            out = sanitizeHttpError(
              statusCode: e.statusCode,
              rawBody: e.rawBody,
              isArabic: L10n.of(context).isArabic,
            );
          });
        }
        return null;
      } catch (e) {
        if (mounted) {
          setState(() {
            out = sanitizeExceptionForUi(
              error: e,
              isArabic: L10n.of(context).isArabic,
            );
          });
        }
        return null;
      }
    })();
    if (attestationHeaders == null) {
      if (closeClient) httpClient.close();
      return;
    }
    try {
      final headers = await _hdrPR(
        widget.baseUrl,
        deviceId: deviceId,
      );
      headers['Idempotency-Key'] =
          newPaymentsIdempotencyKey('payments-request-cancel');
      headers.addAll(attestationHeaders);
      final r = await httpClient
          .post(uri, headers: headers)
          .timeout(_paymentsRequestsRequestTimeout);
      if (!mounted) return;
      if (r.statusCode == 200) {
        shamellRecordAppActivity(
          baseUrl: widget.baseUrl,
          eventType: 'payment_request_cancelled',
          moduleId: 'payments',
          action: 'request_cancelled',
          metadata: <String, Object?>{'request_id': id},
          client: httpClient,
        );
        _loadAll();
      } else {
        if (await _forceReauthForCriticalSessionFailure(
          statusCode: r.statusCode,
          rawBody: r.body,
        )) {
          return;
        }
        setState(() {
          out = sanitizeHttpError(
            statusCode: r.statusCode,
            rawBody: r.body,
            isArabic: L10n.of(context).isArabic,
          );
        });
      }
    } finally {
      if (closeClient) httpClient.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = AppBG();
    final l = L10n.of(context);
    final pending = <Map<String, dynamic>>[
      ..._pending(incoming),
      ..._pending(outgoing),
    ]..sort(_compareRequestsDesc);
    final body = loading
        ? const Center(
            child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator()))
        : TabBarView(children: [
            _list(pending, kind: 'pending', pendingOnly: true),
            _list(incoming, kind: 'incoming'),
            _list(outgoing, kind: 'outgoing'),
          ]);
    return DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: Text(l.homeRequests),
            bottom: TabBar(tabs: [
              Tab(text: l.isArabic ? 'قيد الانتظار' : 'Pending'),
              Tab(text: l.isArabic ? 'واردة' : 'Incoming'),
              Tab(text: l.isArabic ? 'صادرة' : 'Outgoing'),
            ]),
            elevation: 0,
          ),
          body: Stack(children: [
            bg,
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: body,
              ),
            ),
          ]),
          bottomNavigationBar: out.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(out,
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: .9))))
              : null,
        ));
  }

  List<Map<String, dynamic>> _pending(List<Map<String, dynamic>> arr) => arr
      .where(
        (e) =>
            _normalizeRequestStatus((e['status'] ?? '').toString()) ==
            'pending',
      )
      .toList();

  String _requestCurrency(Map<String, dynamic> req) {
    final raw = (req['currency'] ?? '').toString().trim();
    if (raw.isNotEmpty) return shamellNormalizeWalletCurrency(raw);
    final walletCurrency = (widget.walletCurrency ?? '').trim();
    return shamellNormalizeWalletCurrency(walletCurrency);
  }

  List<String> _requestCurrencyOptions(List<Map<String, dynamic>> arr) {
    final set = <String>{};
    final walletCurrency = (widget.walletCurrency ?? '').trim();
    if (walletCurrency.isNotEmpty) {
      set.add(shamellNormalizeWalletCurrency(walletCurrency));
    }
    for (final req in [...incoming, ...outgoing, ...arr]) {
      set.add(_requestCurrency(req));
    }
    final list = set.toList()..sort();
    return list;
  }

  List<Map<String, dynamic>> _filteredRequests(List<Map<String, dynamic>> arr) {
    final filter = _currencyFilter.trim().toUpperCase();
    if (filter.isEmpty) return arr;
    return arr
        .where((req) => _requestCurrency(req) == filter)
        .toList(growable: false);
  }

  int _requestCurrencyCount(List<Map<String, dynamic>> arr, String currency) {
    final normalized = currency.trim().toUpperCase();
    if (normalized.isEmpty) return arr.length;
    return arr.where((req) => _requestCurrency(req) == normalized).length;
  }

  String _activeRequestCurrency(List<Map<String, dynamic>> arr) {
    final filter = _currencyFilter.trim().toUpperCase();
    if (filter.isNotEmpty) return filter;
    final walletCurrency = (widget.walletCurrency ?? '').trim();
    if (walletCurrency.isNotEmpty) {
      return shamellNormalizeWalletCurrency(walletCurrency);
    }
    if (arr.isNotEmpty) return _requestCurrency(arr.first);
    return shamellDefaultWalletCurrency;
  }

  Widget _requestCurrencyHeader(List<Map<String, dynamic>> arr) {
    final l = L10n.of(context);
    final options = _requestCurrencyOptions(arr);
    final activeRequestCurrency = _activeRequestCurrency(arr);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ShamellPaymentCardSurface(
        tone: ShamellPaymentCardTone.soft,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.isArabic ? 'فلترة حسب العملة' : 'Filter by currency',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text(
                    l.isArabic ? 'الكل (${arr.length})' : 'All (${arr.length})',
                  ),
                  selected: _currencyFilter.isEmpty,
                  onSelected: (_) => setState(() => _currencyFilter = ''),
                ),
                for (final currency in options)
                  ChoiceChip(
                    label: Text(
                      '$currency (${_requestCurrencyCount(arr, currency)})',
                    ),
                    selected: _currencyFilter == currency,
                    onSelected: (_) =>
                        setState(() => _currencyFilter = currency),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            PayActionButton(
              icon: Icons.add_card_outlined,
              label: l.isArabic
                  ? 'إنشاء طلب بـ $activeRequestCurrency'
                  : 'Request in $activeRequestCurrency',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GroupPayPage(
                      baseUrl: widget.baseUrl,
                      fromWalletId: widget.walletId,
                      deviceId: widget.deviceId,
                      walletCurrency: activeRequestCurrency,
                    ),
                  ),
                );
              },
              radius: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(
    List<Map<String, dynamic>> arr, {
    required String kind,
    bool pendingOnly = false,
  }) {
    final filteredArr = _filteredRequests(arr);
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView.builder(
          itemCount: filteredArr.length + 2,
          itemBuilder: (_, i) {
            if (i == 0) {
              return _requestCurrencyHeader(arr);
            }
            final rowIndex = i - 1;
            if (rowIndex == filteredArr.length) {
              if (filteredArr.isEmpty && !_hasMoreForKind(kind)) {
                final emptyText = arr.isEmpty
                    ? L10n.of(context).payNoEntries
                    : (L10n.of(context).isArabic
                        ? 'لا توجد طلبات بهذه العملة.'
                        : 'No requests in this currency.');
                return Padding(
                  padding: const EdgeInsets.only(top: 24, bottom: 16),
                  child: Center(child: Text(emptyText)),
                );
              }
              if (!_hasMoreForKind(kind) && !_loadingMoreForKind(kind)) {
                return const SizedBox(height: 8);
              }
              return Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 16),
                child: Center(
                  child: OutlinedButton.icon(
                    onPressed: _loadingMoreForKind(kind)
                        ? null
                        : () => _loadMore(kind),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Tokens.colorPayments,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      side: BorderSide(
                        color: Tokens.colorPayments.withValues(alpha: 0.26),
                      ),
                    ),
                    icon: _loadingMoreForKind(kind)
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.expand_more),
                    label: Text(
                      _loadingMoreForKind(kind)
                          ? (L10n.of(context).isArabic
                              ? 'جارٍ التحميل...'
                              : 'Loading...')
                          : (L10n.of(context).isArabic
                              ? 'تحميل المزيد'
                              : 'Load more'),
                    ),
                  ),
                ),
              );
            }
            final e = filteredArr[rowIndex];
            final id = (e['id'] ?? '').toString();
            final rawAmountCents = e['amount_cents'];
            final amtCents = rawAmountCents is num
                ? rawAmountCents.toInt()
                : int.tryParse((rawAmountCents ?? '').toString()) ?? 0;
            final st = (e['status'] ?? '').toString();
            final normalizedStatus = _normalizeRequestStatus(st);
            final from = (e['from_wallet_id'] ?? '').toString();
            final to = (e['to_wallet_id'] ?? '').toString();
            final msg = (e['message'] ?? '').toString();
            final currency = (e['currency'] ?? 'SYP').toString();
            final incoming =
                pendingOnly ? _isIncomingRequest(e) : kind == 'incoming';
            final canAccept = incoming && normalizedStatus == 'pending';
            final canCancel = !incoming && normalizedStatus == 'pending';
            final other = incoming ? from : to;
            final theme = Theme.of(context);
            final l = L10n.of(context);
            final amountFmt = '${fmtCents(amtCents)} $currency';
            final isPending = normalizedStatus == 'pending';
            final isAccepted = normalizedStatus == 'accepted';
            final isCancelled = normalizedStatus == 'canceled';
            final isExpired = normalizedStatus == 'expired';
            String statusLabel;
            if (isAccepted) {
              statusLabel = l.payReqStatusAccepted;
            } else if (isCancelled) {
              statusLabel = l.payReqStatusCancelled;
            } else if (isExpired) {
              statusLabel = l.payReqStatusExpired;
            } else {
              statusLabel = l.payReqStatusPending;
            }
            Color statusColor;
            if (isAccepted) {
              statusColor = Colors.green.shade600;
            } else if (isPending) {
              statusColor = Tokens.colorPayments;
            } else if (isExpired) {
              statusColor = theme.colorScheme.error.withValues(alpha: .85);
            } else {
              statusColor = theme.colorScheme.onSurface.withValues(alpha: .55);
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ShamellPaymentCardSurface(
                tone: ShamellPaymentCardTone.soft,
                accent: statusColor,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: statusColor.withValues(alpha: .10),
                      ),
                      child: Center(
                        child: Text(
                          other.isNotEmpty
                              ? other.characters
                                  .take(2)
                                  .toString()
                                  .toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: statusColor.withValues(alpha: .95),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  other.isEmpty
                                      ? (incoming
                                          ? (l.isArabic
                                              ? 'دفع وارد'
                                              : 'Incoming request')
                                          : (l.isArabic
                                              ? 'دفع صادر'
                                              : 'Outgoing request'))
                                      : other,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: .10),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  statusLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            msg.isNotEmpty
                                ? msg
                                : (incoming
                                    ? (l.isArabic
                                        ? 'طلب سداد من هذا الطرف'
                                        : 'Payment request from this contact')
                                    : (l.isArabic
                                        ? 'طلب سداد مرسل إلى هذا الطرف'
                                        : 'Payment request you sent')),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .70),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                amountFmt,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              const Spacer(),
                              Wrap(
                                spacing: 6,
                                children: [
                                  IconButton(
                                    tooltip: l.isArabic
                                        ? 'مشاركة كرمز QR'
                                        : 'Share as QR',
                                    onPressed: () {
                                      final payload =
                                          buildShamellPaymentQrPayload(
                                        type: ShamellPaymentQrPayloadType.pay,
                                        walletId: from,
                                        currency: currency,
                                        amountCents:
                                            amtCents > 0 ? amtCents : null,
                                        note: msg,
                                      );
                                      showModalBottomSheet(
                                        context: context,
                                        isScrollControlled: true,
                                        builder: (_) => Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: SingleChildScrollView(
                                            child: ShamellPaymentCardSurface(
                                              tone: ShamellPaymentCardTone.soft,
                                              padding: const EdgeInsets.all(18),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    payload,
                                                    textAlign: TextAlign.center,
                                                  ),
                                                  const SizedBox(height: 10),
                                                  QrImageView(
                                                    data: payload,
                                                    size: 220,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.qr_code_2, size: 20),
                                  ),
                                  if (canAccept)
                                    IconButton(
                                      onPressed: () => _accept(id),
                                      icon: const Icon(
                                        Icons.check_circle_outline,
                                        size: 20,
                                      ),
                                      color: Tokens.colorPayments,
                                    ),
                                  if (canCancel)
                                    IconButton(
                                      onPressed: () => _cancel(id),
                                      icon: Icon(
                                        Icons.cancel_outlined,
                                        size: 20,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: .60),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
    );
  }
}

Future<Map<String, String>> _hdrPR(
  String baseUrl, {
  bool json = false,
  String? deviceId,
}) async {
  final h = await shamellSessionHeadersForBaseUrl(baseUrl, json: json);
  final trimmedDeviceId = (deviceId ?? '').trim();
  if (trimmedDeviceId.isNotEmpty) h['X-Device-ID'] = trimmedDeviceId;
  return h;
}
