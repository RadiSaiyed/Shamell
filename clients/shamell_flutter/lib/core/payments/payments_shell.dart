import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/account_identity_store.dart';
import 'package:shamell_flutter/core/base_url.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import '../../../main.dart' show LoginPage;
import '../../core/app_activity.dart';
import '../../core/app_sounds.dart';
import '../../core/device_binding_reauth.dart';
import '../../core/safe_set_state.dart';
import '../../core/wechat_ui.dart';

import 'money_mutation_guard.dart';
import 'payments_send.dart';
import 'payments_receive.dart';
import 'payments_scan.dart';
import 'payments_requests.dart';
import 'payments_overview.dart';
import 'payments_local_store.dart';
import 'payments_attestation.dart';
import 'payments_idempotency.dart';
import 'payments_card_style.dart';
import '../../core/l10n.dart';

const Duration _paymentsShellRequestTimeout = Duration(seconds: 15);
const int _paymentsShellRequestPageSize = 50;

class _PaymentsShellRequestCursor {
  final String createdAt;
  final String id;

  const _PaymentsShellRequestCursor({
    required this.createdAt,
    required this.id,
  });
}

List<Map<String, dynamic>> _normalizePaymentsShellRequestsPage(dynamic raw) {
  if (raw is! List) return const <Map<String, dynamic>>[];
  return raw
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

_PaymentsShellRequestCursor? _paymentsShellRequestCursorFromItem(
  Map<String, dynamic>? item,
) {
  if (item == null) return null;
  final createdAt = (item['created_at'] ?? '').toString().trim();
  final id = (item['id'] ?? '').toString().trim();
  if (createdAt.isEmpty || id.isEmpty) return null;
  return _PaymentsShellRequestCursor(createdAt: createdAt, id: id);
}

class PaymentsPage extends StatelessWidget {
  final String baseUrl;
  final String fromWalletId;
  final String deviceId;
  final bool triggerScanOnOpen;
  final String? initialRecipient;
  final int? initialAmountCents;
  final String? initialSection;
  final String? initialCurrency;
  final http.Client? client;

  /// Optional human‑readable context label (e.g. merchant or mini‑program).
  final String? contextLabel;
  const PaymentsPage(
    this.baseUrl,
    this.fromWalletId,
    this.deviceId, {
    super.key,
    this.triggerScanOnOpen = false,
    this.initialRecipient,
    this.initialAmountCents,
    this.initialSection,
    this.initialCurrency,
    this.client,
    this.contextLabel,
  });
  @override
  Widget build(BuildContext context) {
    return _PaymentsShell(
      baseUrl: baseUrl,
      fromWalletId: fromWalletId,
      deviceId: deviceId,
      triggerScanOnOpen: triggerScanOnOpen,
      initialRecipient: initialRecipient,
      initialAmountCents: initialAmountCents,
      initialSection: initialSection,
      initialCurrency: initialCurrency,
      client: client,
      contextLabel: contextLabel,
    );
  }
}

class _PaymentsShell extends StatefulWidget {
  final String baseUrl;
  final String fromWalletId;
  final String deviceId;
  final bool triggerScanOnOpen;
  final String? initialRecipient;
  final int? initialAmountCents;
  final String? initialSection;
  final String? initialCurrency;
  final http.Client? client;
  final String? contextLabel;
  const _PaymentsShell({
    required this.baseUrl,
    required this.fromWalletId,
    required this.deviceId,
    this.triggerScanOnOpen = false,
    this.initialRecipient,
    this.initialAmountCents,
    this.initialSection,
    this.initialCurrency,
    this.client,
    this.contextLabel,
  });
  @override
  State<_PaymentsShell> createState() => _PaymentsShellState();
}

class _PaymentsShellState extends State<_PaymentsShell>
    with
        SafeSetStateMixin<_PaymentsShell>,
        MoneyMutationGuardMixin<_PaymentsShell>,
        WidgetsBindingObserver {
  String myWallet = '';
  Timer? _reqTimer;
  Set<String> _seenReqs = {};
  Map<String, dynamic>? _bannerReq;

  // Audit-fix (C-P1-7): incoming-request polling was a fixed 30 s
  // periodic timer with no failure backoff and no lifecycle hookup.
  // If the server returned 5xx the timer hammered it every 30 s, and
  // it ran forever while the app was backgrounded — wasteful and (in
  // the worst case) the kind of pattern that earns abuse-rule strikes
  // on cellular carriers.
  //
  // The replacement uses an adaptive interval: start at the success
  // base interval, exponentially back off on consecutive failures up
  // to a cap, and reset to the base on the next success. The timer is
  // also paused on `AppLifecycleState.paused/inactive` and resumed on
  // `resumed` — the FCM payment-request push will still flag any
  // request we missed while paused, so this is purely a politeness
  // optimisation.
  static const Duration _pollBaseInterval = Duration(seconds: 30);
  static const Duration _pollMaxInterval = Duration(minutes: 8);
  int _pollConsecutiveFailures = 0;
  bool _pollPausedByLifecycle = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    final sp = await SharedPreferences.getInstance();
    myWallet =
        await loadStoredWalletId(sp: sp, baseUrlOverride: widget.baseUrl) ??
            widget.fromWalletId;
    if (mounted) setState(() {});
    _restoreSeenReqs();
    _startReqPolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _pollPausedByLifecycle = true;
      _reqTimer?.cancel();
      _reqTimer = null;
    } else if (state == AppLifecycleState.resumed && _pollPausedByLifecycle) {
      _pollPausedByLifecycle = false;
      // Reset the failure counter on resume so we don't punish the
      // returning user with a maxed-out backoff window.
      _pollConsecutiveFailures = 0;
      _startReqPolling();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reqTimer?.cancel();
    super.dispose();
  }

  void _startReqPolling() {
    _reqTimer?.cancel();
    // Fire one initial poll on the microtask queue so the banner can
    // appear immediately after mount instead of waiting one base
    // interval. Subsequent polls are scheduled adaptively based on
    // success / failure from inside `_pollIncoming`.
    Future.microtask(() async {
      await _pollIncoming();
      _scheduleNextPoll();
    });
  }

  /// Compute the next poll delay and arm the timer. Exponential backoff
  /// (capped) when consecutive failures pile up; base interval after a
  /// clean fetch. Cancels any prior timer to avoid drift.
  void _scheduleNextPoll() {
    _reqTimer?.cancel();
    if (!mounted || _pollPausedByLifecycle) return;
    final n = _pollConsecutiveFailures;
    Duration delay = _pollBaseInterval;
    if (n > 0) {
      // 30 s → 60 s → 120 s → 240 s → 480 s (cap)
      final shift = n.clamp(1, 6);
      final secs = _pollBaseInterval.inSeconds * (1 << (shift - 1));
      delay = Duration(seconds: secs);
      if (delay > _pollMaxInterval) delay = _pollMaxInterval;
    }
    _reqTimer = Timer(delay, () async {
      if (!mounted) return;
      await _pollIncoming();
      _scheduleNextPoll();
    });
  }

  Future<void> _restoreSeenReqs() async {
    try {
      final arr = await loadSeenPaymentRequestIds(
        baseUrlOverride: widget.baseUrl,
      );
      _seenReqs = arr.toSet();
      // Defensive trim on load: an older build may have persisted an
      // unbounded set (audit C-P2-27 — pre-fix builds grew this set
      // forever). Trim it down on the first read of the new build.
      _trimSeenReqs();
    } catch (_) {}
  }

  /// Cap the in-memory + on-disk `_seenReqs` set. The set's purpose is
  /// to avoid re-prompting for the same incoming payment request
  /// banner — anything older than the last N is irrelevant (the
  /// request will have expired or been resolved server-side).
  ///
  /// The cap of 500 corresponds to ~16 months of activity at the
  /// average operator rate (1-2 requests/day) — comfortably above
  /// "could ever still be pending" but far below the unbounded growth
  /// the audit flagged.
  static const int _kMaxSeenPaymentRequestIds = 500;

  void _trimSeenReqs() {
    if (_seenReqs.length <= _kMaxSeenPaymentRequestIds) return;
    // We don't track insertion timestamps, but the iteration order of
    // `loadSeenPaymentRequestIds` returns the list as it was last
    // saved (FIFO under our save logic). Trim from the *front*
    // (oldest) so the most recent IDs — which are the only ones that
    // could plausibly still be pending server-side — survive.
    final overflow = _seenReqs.length - _kMaxSeenPaymentRequestIds;
    final iter = _seenReqs.iterator;
    final dropped = <String>[];
    while (dropped.length < overflow && iter.moveNext()) {
      dropped.add(iter.current);
    }
    _seenReqs.removeAll(dropped);
  }

  Future<void> _saveSeenReqs() async {
    try {
      _trimSeenReqs();
      await saveSeenPaymentRequestIds(
        _seenReqs,
        baseUrlOverride: widget.baseUrl,
      );
    } catch (_) {}
  }

  Future<Map<String, String>> _hdr({bool json = false}) async {
    return shamellSessionHeadersForBaseUrl(widget.baseUrl, json: json);
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

  Future<void> _pollIncoming() async {
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    // Latch success/failure for the adaptive scheduler (audit C-P1-7).
    // Any non-2xx, network error, or timeout counts as a failure so
    // the next interval doubles instead of hammering a flaky server.
    bool pollSucceeded = false;
    try {
      String? beforeCreatedAt;
      String? beforeId;
      Map<String, dynamic>? bannerCandidate;
      var updatedSeen = false;

      while (true) {
        final queryParameters = <String, String>{
          'wallet_id': myWallet,
          'kind': 'incoming',
          'limit': '$_paymentsShellRequestPageSize',
        };
        if (beforeCreatedAt != null && beforeId != null) {
          queryParameters['before_created_at'] = beforeCreatedAt;
          queryParameters['before_id'] = beforeId;
        }
        final uri = _requestsUri(queryParameters: queryParameters);
        if (uri == null) {
          return;
        }
        final r = await httpClient
            .get(uri, headers: await _hdr())
            .timeout(_paymentsShellRequestTimeout);
        if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
          context,
          statusCode: r.statusCode,
          rawBody: r.body,
          loginPageBuilder: (_) => const LoginPage(),
        )) {
          return;
        }
        if (r.statusCode != 200) return;
        // Mark this attempt as successful as soon as we get a clean 200
        // — even if the page returns no new requests. The backoff is
        // about server health, not user activity.
        pollSucceeded = true;
        final page = _normalizePaymentsShellRequestsPage(jsonDecode(r.body));
        for (final e in page) {
          final id = (e['id'] ?? '').toString().trim();
          final st = (e['status'] ?? '').toString();
          if (id.isEmpty || st != 'pending' || _seenReqs.contains(id)) {
            continue;
          }
          _seenReqs.add(id);
          updatedSeen = true;
          bannerCandidate = e;
          break;
        }
        if (bannerCandidate != null) {
          break;
        }
        final cursor = page.isEmpty
            ? null
            : _paymentsShellRequestCursorFromItem(page.last);
        if (page.length < _paymentsShellRequestPageSize || cursor == null) {
          break;
        }
        if (cursor.createdAt == beforeCreatedAt && cursor.id == beforeId) {
          break;
        }
        beforeCreatedAt = cursor.createdAt;
        beforeId = cursor.id;
      }

      if (updatedSeen) {
        await _saveSeenReqs();
      }
      if (bannerCandidate != null && mounted) {
        setState(() => _bannerReq = bannerCandidate);
      }
    } catch (e) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
    } finally {
      if (closeClient) {
        httpClient.close();
      }
      // Update the adaptive-poll counter — done in `finally` so the
      // failure path (caught above + early-returns) also feeds into
      // the next-interval calculation.
      if (pollSucceeded) {
        _pollConsecutiveFailures = 0;
      } else {
        _pollConsecutiveFailures += 1;
      }
    }
  }

  /// Public entry for "Accept & Pay" on the request banner. Routed
  /// through [guardMoneyMutation] so rage-tapping the banner cannot
  /// fire multiple `/requests/{id}/accept` POSTs each minting their own
  /// idempotency key + transfer (the server idempotency layer only
  /// dedupes the *same* key on retry).
  Future<void> _acceptReq(String id) async {
    await guardMoneyMutation<void>(() => _acceptReqUnguarded(id));
  }

  /// The actual accept pipeline. Never call directly — go through
  /// [_acceptReq]. Adds a user-visible SnackBar on non-2xx so silent
  /// failures (which previously left the banner sticky and tempted the
  /// user to re-tap) become actionable.
  Future<void> _acceptReqUnguarded(String id) async {
    final requestId = id.trim();
    if (requestId.isEmpty) return;
    final toWalletId = myWallet.trim().isNotEmpty
        ? myWallet.trim()
        : widget.fromWalletId.trim();
    if (toWalletId.isEmpty) return;

    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    final uri = _requestsUri(id: requestId, action: 'accept');
    if (uri == null) {
      if (closeClient) {
        httpClient.close();
      }
      return;
    }
    final attestationHeaders = await (() async {
      try {
        return await shamellBuildPaymentMutationAttestationHeaders(
          baseUrl: widget.baseUrl,
          deviceId: widget.deviceId,
          operation: 'payments_requests_accept',
          resourceId: shamellPaymentRequestAcceptAttestationResourceId(
            requestId: requestId,
            toWalletId: toWalletId,
          ),
          client: httpClient,
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
        return null;
      } catch (_) {
        return null;
      }
    })();
    if (attestationHeaders == null) {
      if (closeClient) {
        httpClient.close();
      }
      return;
    }

    try {
      final headers = await _hdr(json: true);
      headers['Idempotency-Key'] =
          newPaymentsIdempotencyKey('payments-shell-request-accept');
      final deviceId = widget.deviceId.trim();
      if (deviceId.isNotEmpty) {
        headers['X-Device-ID'] = deviceId;
      }
      headers.addAll(attestationHeaders);
      final resp = await httpClient
          .post(
            uri,
            headers: headers,
            body: jsonEncode(<String, String>{
              'to_wallet_id': toWalletId,
            }),
          )
          .timeout(_paymentsShellRequestTimeout);
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: resp.statusCode,
        rawBody: resp.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        unawaited(ShamellSoundEffects.play(ShamellSoundEffect.paymentSent));
        shamellRecordAppActivity(
          baseUrl: widget.baseUrl,
          eventType: 'payment_request_accepted',
          moduleId: 'payments',
          action: 'request_accepted',
          metadata: <String, Object?>{'request_id': requestId},
          client: httpClient,
        );
        if (mounted) setState(() => _bannerReq = null);
      } else if (mounted) {
        // Audit-fix: previously the non-2xx branch was a silent no-op.
        // The banner stayed sticky and tempted the user to re-tap,
        // which (before the MoneyMutationGuardMixin) could fire a
        // second accept POST. Now we surface the failure so the user
        // can decide to retry or dismiss, instead of silently failing.
        final l = L10n.of(context);
        final reason = _briefHttpErrorReason(resp.statusCode, resp.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic
                  ? 'تعذّر قبول الطلب: $reason'
                  : 'Could not accept request: $reason',
            ),
          ),
        );
      }
    } catch (e) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
    } finally {
      if (closeClient) {
        httpClient.close();
      }
    }
  }

  /// Compose a short human-readable reason for an HTTP failure on the
  /// request-accept path, suitable for inline use in a SnackBar.
  /// Stays defensive: server contracts change wording over time, so we
  /// fall back to a generic "HTTP $status" instead of bubbling raw
  /// JSON or trace strings to the user.
  String _briefHttpErrorReason(int statusCode, String rawBody) {
    if (statusCode == 402) return 'Insufficient balance';
    if (statusCode == 403) return 'Not authorised';
    if (statusCode == 404) return 'Request no longer available';
    if (statusCode == 409) return 'Request already handled';
    if (statusCode == 429) return 'Too many attempts — try again shortly';
    try {
      final body = jsonDecode(rawBody);
      if (body is Map) {
        final detail = (body['detail'] ?? body['error'] ?? '').toString().trim();
        if (detail.isNotEmpty && detail.length < 120) return detail;
      }
    } catch (_) {}
    return 'HTTP $statusCode';
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final isAr = l.isArabic;
    final theme = Theme.of(context);
    final compact = shamellPaymentIsCompact(context);
    final mq = MediaQuery.of(context);
    final paymentScale =
        mq.textScaler.scale(1.0).clamp(0.85, compact ? 1.18 : 1.32).toDouble();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final motionDuration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 280);
    final scaffoldBg = theme.brightness == Brightness.dark
        ? const Color(0xFF0F172A)
        : WeChatPalette.background;
    final baseTitle = isAr ? 'SyrChat Pay' : 'SyrChat Pay';
    final hasCtx = (widget.contextLabel ?? '').trim().isNotEmpty;
    final titleText = hasCtx
        ? '$baseTitle · ${(widget.contextLabel ?? '').trim()}'
        : baseTitle;
    // 0=Overview,1=Scan,2=Send,3=Receive
    int initialIndex = 0;
    final section = (widget.initialSection ?? '').trim().toLowerCase();
    if (widget.triggerScanOnOpen) {
      initialIndex = 1;
    } else if (section == 'scan') {
      initialIndex = 1;
    } else if (section == 'send') {
      initialIndex = 2;
    } else if (section == 'receive') {
      initialIndex = 3;
    } else if (widget.initialRecipient != null &&
        widget.initialRecipient!.isNotEmpty) {
      initialIndex = 2;
    }
    final bodyStack = Stack(
      children: [
        TabBarView(children: [
          PaymentOverviewTab(
            baseUrl: widget.baseUrl,
            walletId: myWallet,
            deviceId: widget.deviceId,
            initialSection: widget.initialSection,
            client: widget.client,
          ),
          PaymentScanTab(
              baseUrl: widget.baseUrl,
              fromWalletId: myWallet,
              autoScan: widget.triggerScanOnOpen,
              client: widget.client,
              walletCurrency: widget.initialCurrency),
          PaymentSendTab(
            baseUrl: widget.baseUrl,
            fromWalletId: myWallet,
            deviceId: widget.deviceId,
            initialRecipient: widget.initialRecipient,
            initialAmountCents: widget.initialAmountCents,
            walletCurrency: widget.initialCurrency,
            client: widget.client,
            contextLabel: widget.contextLabel,
          ),
          PaymentReceiveTab(
            baseUrl: widget.baseUrl,
            fromWalletId: myWallet,
            client: widget.client,
            walletCurrency: widget.initialCurrency,
          ),
        ]),
        SafeArea(
          child: IgnorePointer(
            ignoring: _bannerReq == null,
            child: AnimatedSlide(
              duration: motionDuration,
              curve: Curves.easeOutCubic,
              offset: _bannerReq == null ? const Offset(0, -.08) : Offset.zero,
              child: AnimatedOpacity(
                duration: motionDuration,
                curve: Curves.easeOutCubic,
                opacity: _bannerReq == null ? 0 : 1,
                child: _bannerReq == null
                    ? const SizedBox.shrink()
                    : IncomingRequestBanner(
                        req: _bannerReq!,
                        // Gate "Accept & Pay" on the in-flight guard
                        // so a rapid double-tap can't queue two accept
                        // POSTs with distinct idempotency keys.
                        onAccept: isMoneyMutationInFlight
                            ? null
                            : () => _acceptReq(
                                  (_bannerReq!['id'] ?? '').toString(),
                                ),
                        onDismiss: () => setState(() => _bannerReq = null),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
    final shellBody = reduceMotion
        ? bodyStack
        : TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            tween: Tween<double>(begin: 0, end: 1),
            builder: (context, value, child) {
              final y = (1 - value) * 14;
              return Opacity(
                opacity: value,
                child: Transform.translate(offset: Offset(0, y), child: child),
              );
            },
            child: bodyStack,
          );

    return MediaQuery(
      data: mq.copyWith(textScaler: TextScaler.linear(paymentScale)),
      child: DefaultTabController(
        length: 4,
        initialIndex: initialIndex,
        child: Scaffold(
          appBar: AppBar(
            surfaceTintColor: Colors.transparent,
            title: Text(
              titleText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 20 : 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            bottom: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelPadding: EdgeInsets.symmetric(
                horizontal: compact ? 14 : 20,
              ),
              indicatorSize: TabBarIndicatorSize.label,
              tabs: [
                Tab(
                  text: isAr ? 'نظرة عامة' : 'Overview',
                ),
                Tab(
                  text: isAr ? 'مسح ودفع' : 'Scan & Pay',
                ),
                Tab(
                  text: isAr ? 'إرسال' : 'Send',
                ),
                Tab(
                  text: isAr ? 'استلام' : 'Receive',
                ),
              ],
              labelColor: theme.colorScheme.onSurface,
              unselectedLabelColor:
                  theme.colorScheme.onSurface.withValues(alpha: .72),
              labelStyle: TextStyle(
                fontSize: compact ? 14 : 15,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: TextStyle(
                fontSize: compact ? 14 : 15,
                fontWeight: FontWeight.w500,
              ),
              indicatorColor: theme.colorScheme.primary,
              dividerColor: theme.dividerColor.withValues(alpha: .55),
            ),
            backgroundColor: theme.appBarTheme.backgroundColor ?? scaffoldBg,
          ),
          backgroundColor: scaffoldBg,
          body: shellBody,
        ),
      ),
    );
  }
}
