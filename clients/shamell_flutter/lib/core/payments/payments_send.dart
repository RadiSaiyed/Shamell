import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/account_identity_store.dart';
import 'money_mutation_guard.dart';
import '../../../main.dart' show LoginPage;
import '../../core/app_activity.dart';
import '../../core/app_sounds.dart';
import '../../core/payment_event_bus.dart';
import '../../core/capabilities.dart';
import '../../core/device_binding_guard.dart';
import '../../core/device_binding_reauth.dart';
import '../../core/device_id.dart';
import '../../core/design_tokens.dart';
import '../../core/http_error.dart';
import 'payments_utils.dart';
import 'payments_attestation.dart';
import '../../core/offline_queue.dart';
import '../../core/format.dart' show fmtCents;
import '../../core/friends_page.dart';
import '../../core/l10n.dart';
import '../../core/perf.dart';
import '../../core/safe_clipboard.dart';
import '../../core/status_banner.dart';
import '../../core/ui_kit.dart';
import '../../core/wechat_ui.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import 'package:shamell_flutter/core/base_url.dart';
import '../../core/safe_set_state.dart';
import 'payments_local_store.dart';
import 'payments_card_style.dart';
import 'currency_symbol_store.dart';
import 'payments_idempotency.dart';
import 'supported_currencies.dart';

const Duration _paymentsSendRequestTimeout = Duration(seconds: 15);
const int _paymentsFavoritesPageSize = 100;

class _PaymentsFavoriteCursor {
  final String createdAt;
  final String id;

  const _PaymentsFavoriteCursor({
    required this.createdAt,
    required this.id,
  });
}

Map<String, String> _paymentsOfflineQueueHeaders(
  Map<String, String> headers,
) {
  final sanitized = Map<String, String>.from(headers);
  sanitized.remove(shamellPaymentAttestationChallengeHeader);
  sanitized.remove(shamellPaymentAttestationPlayIntegrityHeader);
  sanitized.remove(shamellPaymentAttestationAppleDeviceCheckHeader);
  return sanitized;
}

List<Map<String, dynamic>> _normalizeFavoritesPage(Object? decoded) {
  if (decoded is List) {
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }
  return const <Map<String, dynamic>>[];
}

_PaymentsFavoriteCursor? _paymentsFavoriteCursorFromItem(
  Map<String, dynamic>? item,
) {
  if (item == null) return null;
  final createdAt = (item['created_at'] ?? '').toString().trim();
  final id = (item['id'] ?? '').toString().trim();
  if (createdAt.isEmpty || id.isEmpty) return null;
  return _PaymentsFavoriteCursor(createdAt: createdAt, id: id);
}

class FavoritesDropdown extends StatelessWidget {
  final List<Map<String, dynamic>> favorites;
  final void Function(String value) onSelected;
  const FavoritesDropdown(
      {super.key, required this.favorites, required this.onSelected});
  @override
  Widget build(BuildContext context) {
    if (favorites.isEmpty) return const SizedBox.shrink();
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: l.payFavoritesLabel,
        filled: true,
        fillColor:
            isDark ? WeChatPalette.searchFillDark : WeChatPalette.searchFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: theme.dividerColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: theme.dividerColor.withValues(alpha: .82),
          ),
        ),
      ),
      isExpanded: true,
      items: favorites.map((f) {
        final alias = (f['alias'] ?? '').toString();
        final id = (f['favorite_wallet_id'] ?? '').toString();
        final label = alias.isNotEmpty ? '$alias  ·  $id' : id;
        return DropdownMenuItem(
            value: id, child: Text(label, overflow: TextOverflow.ellipsis));
      }).toList(),
      onChanged: (v) {
        if (v != null) onSelected(v);
      },
    );
  }
}

class QuickAmountChips extends StatelessWidget {
  final List<int> presets;
  final VoidCallback onClear;
  final void Function(int add) onAdd; // add in whole SYP
  const QuickAmountChips(
      {super.key,
      this.presets = const [5, 10, 25, 50, 100],
      required this.onClear,
      required this.onAdd});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fill =
        isDark ? WeChatPalette.searchFillDark : WeChatPalette.searchFill;
    final border = theme.dividerColor.withValues(alpha: isDark ? .42 : .82);

    Widget chip({
      required String label,
      required VoidCallback onTap,
      IconData? icon,
    }) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: Tokens.colorPayments),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in presets) chip(label: '+$v', onTap: () => onAdd(v)),
        chip(
          label: L10n.of(context).clearLabel,
          icon: Icons.close_rounded,
          onTap: onClear,
        ),
      ],
    );
  }
}

class PaymentSendTab extends StatefulWidget {
  final String baseUrl;
  final String fromWalletId;
  final String deviceId;
  final String? initialRecipient;
  final int? initialAmountCents;
  final String? walletCurrency;

  /// Optional human‑readable context for the payment target (e.g. merchant or mini‑program).
  final String? contextLabel;
  final http.Client? client;
  const PaymentSendTab({
    super.key,
    required this.baseUrl,
    required this.fromWalletId,
    required this.deviceId,
    this.initialRecipient,
    this.initialAmountCents,
    this.walletCurrency,
    this.contextLabel,
    this.client,
  });
  @override
  State<PaymentSendTab> createState() => _PaymentSendTabState();
}

class _PaymentSendTabState extends State<PaymentSendTab>
    with SafeSetStateMixin<PaymentSendTab>, MoneyMutationGuardMixin<PaymentSendTab> {
  late final http.Client _http;
  late final bool _ownsHttpClient;
  final toCtrl = TextEditingController();
  final amtCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  String myWallet = '';
  int? _balanceCents;
  bool _loadingWallet = false;
  // Set when `_loadWallet` fails with a non-2xx or network error so
  // the hero can render a Retry chip instead of a stuck "–" balance.
  // Cleared on the next successful load.
  String? _balanceLoadError;
  String _curSym = 'SYP';
  List<String> recents = [];
  List<Map<String, dynamic>> favorites = [];
  String _toResolvedHint = '';
  int _sendCooldownSec = 0;
  Timer? _cooldownTimer;
  String _bannerMsg = '';
  StatusKind _bannerKind = StatusKind.info;

  Timer? _resolveTimer;

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

  @override
  void initState() {
    super.initState();
    _ownsHttpClient = widget.client == null;
    _http = widget.client ?? shamellHttpClient();
    final walletCurrency = (widget.walletCurrency ?? '').trim();
    if (walletCurrency.isNotEmpty) _curSym = walletCurrency;
    _init();
  }

  Future<void> _init() async {
    final sp = await SharedPreferences.getInstance();
    myWallet =
        await loadStoredWalletId(sp: sp, baseUrlOverride: widget.baseUrl) ??
            widget.fromWalletId;
    recents = await loadPaymentRecents(
      sp: sp,
      baseUrlOverride: widget.baseUrl,
    );
    final cs = await loadStoredCurrencySymbol(
      baseUrl: widget.baseUrl,
      sp: sp,
    );
    if ((widget.walletCurrency ?? '').trim().isEmpty &&
        cs != null &&
        cs.isNotEmpty) {
      _curSym = cs;
    }
    if (widget.initialRecipient != null &&
        widget.initialRecipient!.trim().isNotEmpty) {
      toCtrl.text = widget.initialRecipient!.trim();
    }
    if (widget.initialAmountCents != null && widget.initialAmountCents! > 0) {
      final major = widget.initialAmountCents! / 100.0;
      amtCtrl.text = major.toStringAsFixed(2);
    }
    setState(() {});
    await _loadFavorites();
    await _loadWallet();
    _attachResolver();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _resolveTimer?.cancel();
    toCtrl.removeListener(_onResolveChanged);
    toCtrl.dispose();
    amtCtrl.dispose();
    noteCtrl.dispose();
    if (_ownsHttpClient) {
      // Audit-fix (C-P2-29): defer closing the http client when a
      // money mutation is still in flight. Closing it mid-POST aborts
      // the underlying socket and leaves the transfer in an
      // ambiguous state — the server may have committed (and the
      // client mistakenly thinks "nothing happened"), or the server
      // may have rejected (and the client also thinks "nothing
      // happened"). Either way the user can't tell what their
      // balance is until they refresh.
      //
      // The `isMoneyMutationInFlight` flag is the same one the
      // Send/Scan/Accept/Redeem gates use; if it's set when we're
      // about to dispose, hand the http client off to a detached
      // micro-task that closes it when the in-flight POST finishes.
      // OfflineQueue still has the request payload + ikey on disk,
      // so even if the user kills the app we'll replay it next boot.
      final client = _http;
      if (isMoneyMutationInFlight) {
        // Park a max 10-second wait — keep us off "leak the client
        // forever" if the in-flight request hangs.
        unawaited(() async {
          final deadline = DateTime.now().add(const Duration(seconds: 10));
          while (isMoneyMutationInFlight &&
              DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
          try {
            client.close();
          } catch (_) {}
        }());
      } else {
        client.close();
      }
    }
    super.dispose();
  }

  void _attachResolver() {
    toCtrl.removeListener(_onResolveChanged);
    toCtrl.addListener(_onResolveChanged);
  }

  void _onResolveChanged() {
    _resolveTimer?.cancel();
    _resolveTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      _resolveTarget();
    });
  }

  Future<void> _resolveTarget() async {
    final v = toCtrl.text.trim();
    _toResolvedHint = '';
    setState(() {});
    if (v.isEmpty) return;
    final l = L10n.of(context);
    try {
      final isPhone = v.startsWith('+') || RegExp(r'^\d{6,}$').hasMatch(v);
      final isAlias = v.startsWith('@') && v.length > 1;
      if (isPhone) {
        // Permanently disabled: do not route payments by phone number.
        _toResolvedHint = l.isArabic
            ? 'أرقام الهاتف غير مدعومة. استخدم مُعرّف المحفظة أو @اسم.'
            : 'Phone numbers are not supported. Use a wallet ID or @alias.';
        setState(() {});
      } else if (isAlias) {
        // Best practice: do not expose an alias enumeration endpoint.
        // Alias resolution happens server-side when sending.
        _toResolvedHint = l.isArabic
            ? 'سيتم حل @الاسم على الخادم عند الإرسال.'
            : 'Alias will be resolved on the server when sending.';
        setState(() {});
      }
    } catch (_) {}
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

  Future<void> _loadWallet() async {
    if (myWallet.isEmpty) return;
    final uri = _paymentsUri(pathSegments: <String>['wallets', myWallet]);
    if (uri == null) return;
    setState(() {
      _loadingWallet = true;
      // Optimistically clear any prior load-failure banner — if the
      // fresh attempt fails again we'll re-set it below.
      _balanceLoadError = null;
    });
    final l = L10n.of(context);
    try {
      final r = await _http
          .get(uri, headers: await _hdrPS(widget.baseUrl))
          .timeout(_paymentsSendRequestTimeout);
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: r.statusCode,
        rawBody: r.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
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
      } else if (mounted) {
        // Audit-fix (C-P1-1): non-200 responses used to fall through
        // silently, leaving the balance label stuck on "–" forever
        // with no way for the user to retry. Capture the failure so
        // the Send hero can show a Retry chip + reason.
        _balanceLoadError = l.isArabic
            ? 'تعذّر تحميل الرصيد (HTTP ${r.statusCode})'
            : 'Could not load balance (HTTP ${r.statusCode})';
      }
    } catch (e) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      // Network / timeout / TLS — same surfacing as a non-200 above.
      if (mounted) {
        _balanceLoadError = l.isArabic
            ? 'تعذّر تحميل الرصيد. تحقق من الاتصال وحاول مرة أخرى.'
            : 'Could not load balance. Check your connection and retry.';
      }
    }
    if (mounted) setState(() => _loadingWallet = false);
  }

  Future<void> _loadFavorites() async {
    if (myWallet.isEmpty) return;
    final loadedFavorites = <Map<String, dynamic>>[];
    final seenFavoriteIds = <String>{};
    String? beforeCreatedAt;
    String? beforeId;
    var receivedPage = false;
    try {
      while (true) {
        final queryParameters = <String, String>{
          'owner_wallet_id': myWallet,
          'limit': '$_paymentsFavoritesPageSize',
        };
        if (beforeCreatedAt != null && beforeId != null) {
          queryParameters['before_created_at'] = beforeCreatedAt;
          queryParameters['before_id'] = beforeId;
        }
        final uri = _paymentsUri(
          pathSegments: <String>['favorites'],
          queryParameters: queryParameters,
        );
        if (uri == null) return;
        final r = await _http
            .get(uri, headers: await _hdrPS(widget.baseUrl))
            .timeout(_paymentsSendRequestTimeout);
        if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
          context,
          statusCode: r.statusCode,
          rawBody: r.body,
          loginPageBuilder: (_) => const LoginPage(),
        )) {
          return;
        }
        if (r.statusCode != 200) {
          break;
        }
        receivedPage = true;
        final page = _normalizeFavoritesPage(jsonDecode(r.body));
        for (final favorite in page) {
          final favoriteId = (favorite['id'] ?? '').toString().trim();
          if (favoriteId.isNotEmpty && !seenFavoriteIds.add(favoriteId)) {
            continue;
          }
          loadedFavorites.add(favorite);
        }
        final cursor =
            _paymentsFavoriteCursorFromItem(page.isEmpty ? null : page.last);
        if (page.length < _paymentsFavoritesPageSize || cursor == null) {
          break;
        }
        if (cursor.createdAt == beforeCreatedAt && cursor.id == beforeId) {
          break;
        }
        beforeCreatedAt = cursor.createdAt;
        beforeId = cursor.id;
      }
      if (receivedPage) {
        favorites = loadedFavorites;
      }
    } catch (e) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveRecent(String w) async {
    if (w.isEmpty) return;
    final cur = List<String>.from(await loadPaymentRecents(
      baseUrlOverride: widget.baseUrl,
    ));
    cur.removeWhere((x) => x == w);
    cur.insert(0, w);
    while (cur.length > 5) cur.removeLast();
    await savePaymentRecents(cur, baseUrlOverride: widget.baseUrl);
    setState(() => recents = cur);
  }

  void _startCooldown(int secs) {
    if (secs <= 0) return;
    _cooldownTimer?.cancel();
    setState(() => _sendCooldownSec = secs);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_sendCooldownSec <= 1) {
        t.cancel();
        setState(() => _sendCooldownSec = 0);
      } else
        setState(() => _sendCooldownSec -= 1);
    });
  }

  double _parseMajor(String s) {
    try {
      final t = s.trim().replaceAll(',', '.');
      return double.parse(t);
    } catch (_) {
      return 0;
    }
  }

  /// Top-level Send entry point. Routes through [guardMoneyMutation]
  /// so a double-tap / re-entrant rebuild / mid-flight rotation cannot
  /// fire a second `/transfer` POST with a fresh idempotency key —
  /// which would otherwise produce *two* distinct transfers (the
  /// server idempotency layer only dedupes the *same* key on retry).
  Future<void> _sendManual() async {
    await guardMoneyMutation<void>(_sendManualUnguarded);
  }

  /// The actual send pipeline. Never call directly — go through
  /// [_sendManual]. Method name kept distinct so external code (debug
  /// hooks, the review-sheet handler) always picks up the guard.
  Future<void> _sendManualUnguarded() async {
    final l = L10n.of(context);
    String to = toCtrl.text.trim();
    final amountMajor = _parseMajor(amtCtrl.text.trim());
    if (to.isEmpty || !amountMajor.isFinite || amountMajor <= 0) {
      setState(() {
        _bannerKind = StatusKind.error;
        _bannerMsg = l.payCheckInputs;
      });
      return;
    }
    final uri = _paymentsUri(pathSegments: <String>['transfer']);
    if (uri == null) {
      setState(() {
        _bannerKind = StatusKind.error;
        _bannerMsg = _invalidServerUrlMessage();
      });
      return;
    }
    final ikey = newPaymentsIdempotencyKey('tw');
    final target = buildTransferTarget(to);
    if (target.isEmpty) {
      setState(() {
        _bannerKind = StatusKind.error;
        _bannerMsg = l.isArabic
            ? 'الرجاء إدخال مُعرّف محفظة صالح أو @اسم. أرقام الهاتف غير مدعومة.'
            : 'Enter a valid wallet ID or @alias. Phone numbers are not supported.';
      });
      return;
    }
    final amountCents = shamellPaymentAmountMajorToCents(amountMajor);
    final payload = <String, dynamic>{
      'from_wallet_id': myWallet,
      'amount_cents': amountCents,
      if (noteCtrl.text.trim().isNotEmpty) 'reference': noteCtrl.text.trim(),
      ...target
    };
    final t0 = DateTime.now().millisecondsSinceEpoch;
    final deviceId = await _effectiveDeviceId();
    final attestationHeaders = await (() async {
      try {
        return await shamellBuildPaymentMutationAttestationHeaders(
          baseUrl: widget.baseUrl,
          deviceId: deviceId,
          operation: 'payments_transfer',
          resourceId: shamellPaymentTransferAttestationResourceId(
            fromWalletId: myWallet,
            amountCents: amountCents,
            toWalletId: (target['to_wallet_id'] ?? '').toString(),
            toAlias: (target['to_alias'] ?? '').toString(),
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
          _bannerKind = StatusKind.error;
          _bannerMsg = sanitizeHttpError(
            statusCode: e.statusCode,
            rawBody: e.rawBody,
            isArabic: l.isArabic,
          );
        });
        return null;
      } catch (e) {
        setState(() {
          _bannerKind = StatusKind.error;
          _bannerMsg = sanitizeExceptionForUi(error: e, isArabic: l.isArabic);
        });
        return null;
      }
    })();
    if (attestationHeaders == null) {
      return;
    }
    try {
      final headers = (await _hdrPS(widget.baseUrl, json: true))
        ..addAll({'Idempotency-Key': ikey, 'X-Device-ID': deviceId})
        ..addAll(attestationHeaders);
      final resp = await _http
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(_paymentsSendRequestTimeout);
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: resp.statusCode,
        rawBody: resp.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      if (resp.statusCode == 429) {
        try {
          final j = jsonDecode(resp.body);
          final ms = (j['retry_after_ms'] ?? 0) as int;
          final sec = (ms / 1000).ceil();
          _startCooldown(sec > 0 ? sec : 15);
        } catch (_) {
          _startCooldown(15);
        }
      }
      if (resp.statusCode >= 500) {
        Perf.action('pay_send_queued');
        await OfflineQueue.enqueue(
          OfflineTask(
              id: ikey,
              method: 'POST',
              url: uri.toString(),
              headers: _paymentsOfflineQueueHeaders(headers),
              body: jsonEncode(payload),
              tag: 'payments_transfer',
              createdAt: DateTime.now().millisecondsSinceEpoch),
          baseUrlOverride: widget.baseUrl,
        );
        final msg = l.payOfflineQueued;
        setState(() {
          _bannerKind = StatusKind.warning;
          _bannerMsg = msg;
        });
      }
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        Perf.action('pay_send_ok');
        final dt = DateTime.now().millisecondsSinceEpoch - t0;
        Perf.sample('pay_send_ms', dt);
        // Suppress the realtime echo for the txn we just initiated so the
        // sender doesn't hear paymentSent twice (local + SSE).
        try {
          final body = jsonDecode(resp.body);
          if (body is Map<String, dynamic>) {
            final raw = body['txn_id'];
            if (raw is String && raw.isNotEmpty) {
              PaymentEventBus.instance.markTxnAsLocal(raw);
            }
          }
        } catch (_) {}
        try {
          HapticFeedback.mediumImpact();
        } catch (_) {}
        unawaited(ShamellSoundEffects.play(ShamellSoundEffect.paymentSent));
        shamellRecordAppActivity(
          baseUrl: widget.baseUrl,
          eventType: 'payment_transfer_sent',
          moduleId: 'payments',
          action: 'transfer_sent',
          metadata: <String, Object?>{
            'amount_cents': amountCents,
            'currency': _curSym,
            'target_type': target.containsKey('to_alias') ? 'alias' : 'wallet',
          },
          client: _http,
        );
        await _loadWallet();
        await _saveRecent(to);
        final msg = l.isArabic
            ? 'تم إرسال ${amountMajor.toStringAsFixed(2)} $_curSym إلى $to'
            : 'Sent ${amountMajor.toStringAsFixed(2)} $_curSym to $to';
        setState(() {
          _bannerKind = StatusKind.success;
          _bannerMsg = msg;
        });
      } else if (resp.statusCode >= 400) {
        Perf.action('pay_send_fail');
        final dt = DateTime.now().millisecondsSinceEpoch - t0;
        Perf.sample('pay_send_ms', dt);
        String msg = l.paySendFailed;
        try {
          final ct = resp.headers['content-type'] ?? '';
          if (ct.startsWith('application/json')) {
            final body = jsonDecode(resp.body);
            // Audit-fix (C-P1-5): prefer the new stable `error_code`
            // field over substring-matching the (server-mutable)
            // `detail` string. Substring matching silently regressed
            // each time the server tweaked wording; the explicit
            // machine code on every error response is the audit's
            // recommended stable contract. The legacy detail-match
            // is kept as a fallback for older server builds during
            // the rollout window.
            final code = body is Map<String, dynamic>
                ? (body['error_code'] ?? '').toString()
                : '';
            final detail = body is Map<String, dynamic> ? body['detail'] : null;
            final detailStr = detail == null ? '' : detail.toString();
            switch (code) {
              case 'insufficient_funds':
                msg = l.isArabic
                    ? 'الرصيد غير كافٍ.'
                    : 'Insufficient balance.';
                break;
              case 'amount_guardrail':
                msg = l.payGuardrailAmount;
                break;
              case 'velocity_guardrail':
                // Wallet-vs-device split is informational only on the
                // server; the client surfaces a single "you've sent
                // too many recently" message either way.
                msg = l.payGuardrailVelocityWallet;
                break;
              case 'same_wallet':
                msg = l.isArabic
                    ? 'لا يمكن التحويل إلى المحفظة نفسها.'
                    : 'Cannot transfer to the same wallet.';
                break;
              case 'currency_mismatch':
                msg = l.isArabic
                    ? 'عملة المحفظة لا تتطابق.'
                    : 'Wallet currencies do not match.';
                break;
              case 'wallet_not_found':
                msg = l.isArabic
                    ? 'لم يتم العثور على المحفظة.'
                    : 'Wallet not found.';
                break;
              case 'rate_limited':
                msg = l.isArabic
                    ? 'محاولات كثيرة، حاول لاحقاً.'
                    : 'Too many attempts — please try again shortly.';
                break;
              default:
                // Legacy fallback for servers that haven't shipped
                // `error_code` yet. Drop this branch once all
                // payments_service instances are on 2026-05+.
                if (detailStr.contains('amount exceeds guardrail')) {
                  msg = l.payGuardrailAmount;
                } else if (detailStr.contains('velocity guardrail (wallet)')) {
                  msg = l.payGuardrailVelocityWallet;
                } else if (detailStr.contains('velocity guardrail (device)')) {
                  msg = l.payGuardrailVelocityDevice;
                }
            }
          }
        } catch (_) {/* best-effort only */}
        setState(() {
          _bannerKind = StatusKind.error;
          _bannerMsg = msg;
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
      final headers = (await _hdrPS(widget.baseUrl, json: true))
        ..addAll({'Idempotency-Key': ikey, 'X-Device-ID': deviceId})
        ..addAll(attestationHeaders);
      await OfflineQueue.enqueue(
        OfflineTask(
            id: ikey,
            method: 'POST',
            url: uri.toString(),
            headers: _paymentsOfflineQueueHeaders(headers),
            body: jsonEncode(payload),
            tag: 'payments_transfer',
            createdAt: DateTime.now().millisecondsSinceEpoch),
        baseUrlOverride: widget.baseUrl,
      );
      Perf.action('pay_send_queued');
      final msg =
          '${l.payOfflineSavedPrefix}: $to, ${amountMajor.toStringAsFixed(2)} $_curSym';
      setState(() {
        _bannerKind = StatusKind.warning;
        _bannerMsg = msg;
      });
    }
  }

  Future<void> _reviewAndSend() async {
    final l = L10n.of(context);
    final to = toCtrl.text.trim();
    final amountMajor = _parseMajor(amtCtrl.text.trim());
    if (to.isEmpty || !amountMajor.isFinite || amountMajor <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.payCheckInputs)));
      return;
    }
    final fmt = '${amountMajor.toStringAsFixed(2)} $_curSym';
    final hint = _toResolvedHint;
    final ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (_) {
          return buildReviewSheet(
              context: context,
              to: to,
              hint: hint,
              amountFmt: fmt,
              note: noteCtrl.text.trim());
        });
    if (ok == true) {
      await _sendManual();
    }
  }

  @visibleForTesting
  Future<void> debugSubmitTransfer({
    required String recipient,
    required double amountMajor,
    String note = '',
  }) async {
    toCtrl.text = recipient;
    amtCtrl.text = amountMajor.toStringAsFixed(2);
    noteCtrl.text = note;
    await _sendManual();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final ctxLabel = (widget.contextLabel ?? '').trim();
    return ListView(
      padding: shamellPaymentPagePadding(context),
      children: [
        if (_bannerMsg.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: StatusBanner(
                kind: _bannerKind, message: _bannerMsg, dense: true),
          ),
        _walletHero(),
        const SizedBox(height: 12),
        ShamellPaymentSection(
          title: l.isArabic ? 'المستلم والمبلغ' : 'Recipient & amount',
          children: [
            if (ctxLabel.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.storefront_outlined, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l.isArabic ? 'الدفع إلى $ctxLabel' : 'Paying $ctxLabel',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: .80),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            if (favorites.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FavoritesDropdown(
                  favorites: favorites,
                  onSelected: (v) {
                    toCtrl.text = v;
                    setState(() {});
                  },
                ),
              ),
            LayoutBuilder(
              builder: (context, constraints) {
                final recipientField = TextField(
                  controller: toCtrl,
                  decoration: InputDecoration(labelText: l.payRecipientLabel),
                );
                final amountField = TextField(
                  controller: amtCtrl,
                  decoration: InputDecoration(labelText: l.payAmountLabel),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                );
                if (constraints.maxWidth < 360) {
                  return Column(
                    children: [
                      recipientField,
                      const SizedBox(height: 8),
                      amountField,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: recipientField),
                    const SizedBox(width: 8),
                    Expanded(child: amountField),
                  ],
                );
              },
            ),
            const SizedBox(height: 6),
            QuickAmountChips(
              onClear: () {
                amtCtrl.text = '';
                setState(() {});
              },
              onAdd: (v) {
                final cur = _parseMajor(amtCtrl.text.trim());
                amtCtrl.text = (cur + v).toStringAsFixed(2);
                setState(() {});
                try {
                  HapticFeedback.selectionClick();
                } catch (_) {}
              },
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              child: Builder(
                builder: (_) {
                  final c = _parseMajor(amtCtrl.text.trim());
                  final s = c > 0 ? '${c.toStringAsFixed(2)} ${_curSym}' : '';
                  return Text(
                    s,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: .70),
                    ),
                  );
                },
              ),
            ),
            if (_toResolvedHint.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _toResolvedHint,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: .60),
                  ),
                ),
              ),
          ],
        ),
        ShamellPaymentSection(
          title: l.isArabic ? 'تفاصيل إضافية' : 'Details & contacts',
          children: [
            TextField(
              controller: noteCtrl,
              decoration: InputDecoration(
                labelText: l.payNoteLabel,
              ),
            ),
            const SizedBox(height: 8),
            Semantics(
              button: true,
              label: l.isArabic ? 'إرسال دفعة' : 'Send payment',
              // Gate the button on the money-mutation guard so a
              // double-tap during the in-flight `/transfer` POST cannot
              // mint a second idempotency key + duplicate transfer.
              // The existing `SendButton` cooldown is for server-side
              // 429 rate-limit responses; this gate is the much
              // shorter "still in flight" gate that matters most.
              child: SendButton(
                cooldownSec: _sendCooldownSec,
                onTap: isMoneyMutationInFlight ? null : _reviewAndSend,
              ),
            ),
            if (favorites.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: favorites.map((f) {
                    final label = (f['alias'] ?? '').toString().isNotEmpty
                        ? (f['alias'] as String)
                        : (f['favorite_wallet_id'] as String);
                    final favoriteWalletId =
                        (f['favorite_wallet_id'] ?? '').toString();
                    return ActionChip(
                      avatar: CircleAvatar(child: Text(label.characters.first)),
                      label: Text(label, overflow: TextOverflow.ellipsis),
                      onPressed: () {
                        toCtrl.text = favoriteWalletId.isNotEmpty
                            ? favoriteWalletId
                            : label;
                        setState(() {});
                      },
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _walletHero() {
    final bal = _balanceCents;
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final compact = shamellPaymentIsCompact(context);
    final fgPrimary = theme.colorScheme.onSurface;
    final fgSecondary = fgPrimary.withValues(alpha: .72);
    final balanceText = bal == null
        ? (_loadingWallet ? '...' : '-')
        : '${fmtCents(bal)} $_curSym';
    final walletBlock = Row(
      children: [
        Container(
          width: compact ? 46 : 52,
          height: compact ? 46 : 52,
          decoration: BoxDecoration(
            color: isDark
                ? WeChatPalette.searchFillDark
                : WeChatPalette.searchFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: isDark ? .36 : .80),
            ),
          ),
          child: Icon(
            Icons.send_rounded,
            size: compact ? 23 : 26,
            color: Tokens.colorPayments.withValues(alpha: .96),
          ),
        ),
        SizedBox(width: compact ? 12 : 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.homeWallet,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 0,
                  color: fgSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      myWallet.isEmpty ? l.notSet : myWallet,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        letterSpacing: 0,
                        color: fgPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l.isArabic ? 'نسخ رقم المحفظة' : 'Copy wallet ID',
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
      ],
    );
    final balanceBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          l.isArabic ? 'الرصيد' : 'Balance',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
            letterSpacing: 0,
            color: fgSecondary,
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerEnd,
          child: Text(
            balanceText,
            maxLines: 1,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 22,
              letterSpacing: 0,
              color: fgPrimary,
            ),
          ),
        ),
        // Audit-fix (C-P1-1): when `_loadWallet` fails, surface the
        // reason + a Retry chip directly under the balance line.
        // Previously a non-2xx silently left the balance stuck on "–"
        // with no recovery path; this is the actionable surface.
        if (_balanceLoadError != null) ...[
          const SizedBox(height: 4),
          Text(
            _balanceLoadError!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.error.withValues(alpha: .88),
            ),
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: theme.colorScheme.error,
            ),
            onPressed: _loadingWallet ? null : () => unawaited(_loadWallet()),
            icon: const Icon(Icons.refresh, size: 14),
            label: Text(
              l.isArabic ? 'إعادة المحاولة' : 'Retry',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ],
    );
    return ShamellPaymentCardSurface(
      tone: ShamellPaymentCardTone.hero,
      padding:
          shamellPaymentCardPadding(context, tone: ShamellPaymentCardTone.hero),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 360) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                walletBlock,
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: balanceBlock,
                  ),
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: walletBlock),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 190),
                child: balanceBlock,
              ),
            ],
          );
        },
      ),
    );
  }
}

class SendButton extends StatelessWidget {
  final int cooldownSec;
  // Nullable so the parent can disable the button while a money
  // mutation is in flight (MoneyMutationGuardMixin). Disabled state is
  // rendered with the same dimmed opacity as the cooldown variant —
  // visually we treat "still sending" and "rate-limited" the same so
  // the user gets consistent feedback whichever gate fires.
  final VoidCallback? onTap;
  const SendButton({super.key, required this.cooldownSec, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final label = cooldownSec > 0 ? l.paySendAfter(cooldownSec) : l.sendLabel;
    final theme = Theme.of(context);
    final bool disabled = onTap == null;
    return Opacity(
      opacity: (cooldownSec > 0 || disabled) ? .55 : 1,
      child: SizedBox(
        width: double.infinity,
        height: 46,
        child: FilledButton.icon(
          icon: const Icon(Icons.send_outlined, size: 18),
          label: Text(
            label,
            overflow: TextOverflow.ellipsis,
          ),
          style: FilledButton.styleFrom(
            backgroundColor: WeChatPalette.green,
            foregroundColor: Colors.white,
            textStyle: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: disabled
              ? null
              : () {
                  if (cooldownSec > 0) {
                    final msg = l.payWaitSeconds(cooldownSec);
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(msg)));
                  } else {
                    onTap!();
                  }
                },
        ),
      ),
    );
  }
}

Widget buildReviewSheet(
    {required BuildContext context,
    required String to,
    required String hint,
    required String amountFmt,
    String? note}) {
  final l = L10n.of(context);
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  return Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: Padding(
      padding: shamellPaymentPagePadding(context),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.dividerColor.withValues(alpha: isDark ? .42 : .82),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? .22 : .08),
              blurRadius: 18,
              spreadRadius: -8,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Tokens.colorPayments.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.person_outline,
                    color: Tokens.colorPayments,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(to,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700))),
                if (hint.isNotEmpty)
                  Text(
                    hint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .64),
                    ),
                  )
              ]),
              const SizedBox(height: 12),
              Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    amountFmt,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              if ((note ?? '').trim().isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Center(
                        child: Text(note!.trim(),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium))),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(l.isArabic ? 'إلغاء' : 'Cancel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      backgroundColor: WeChatPalette.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(l.isArabic ? 'إرسال' : 'Send'),
                  ),
                ),
              ]),
            ]),
      ),
    ),
  );
}

class GroupPayPage extends StatefulWidget {
  @visibleForTesting
  static const int requestCreateMaxConcurrency = 4;

  final String baseUrl;
  final String fromWalletId;
  final String deviceId;
  final String? walletCurrency;
  final http.Client? client;
  final Future<bool?> Function(BuildContext context, WidgetBuilder builder)?
      confirmDialogLauncher;
  const GroupPayPage({
    super.key,
    required this.baseUrl,
    required this.fromWalletId,
    required this.deviceId,
    this.walletCurrency,
    this.client,
    this.confirmDialogLauncher,
  });

  @visibleForTesting
  static Future<http.Response> postGroupPaymentRequestCreate({
    required http.Client client,
    required Uri uri,
    required Map<String, Object?> payload,
    required String deviceId,
    required Future<Map<String, String>> Function() headersLoader,
    Duration timeout = _paymentsSendRequestTimeout,
  }) async {
    final headers = await headersLoader();
    headers['Idempotency-Key'] =
        newPaymentsIdempotencyKey('payments-request-create');
    final trimmedDeviceId = deviceId.trim();
    if (trimmedDeviceId.isNotEmpty) {
      headers['X-Device-ID'] = trimmedDeviceId;
    }
    return client
        .post(uri, headers: headers, body: jsonEncode(payload))
        .timeout(timeout);
  }

  @override
  State<GroupPayPage> createState() => _GroupPayPageState();
}

class _GroupPayPageState extends State<GroupPayPage>
    with SafeSetStateMixin<GroupPayPage> {
  late final http.Client _http;
  late final bool _ownsHttpClient;
  final TextEditingController _recipientsCtrl = TextEditingController();
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  String _walletId = '';
  int? _balanceCents;
  String _currency = shamellDefaultWalletCurrency;
  bool _loadingWallet = false;
  bool _submitting = false;
  String _out = '';
  final List<String> _selectedFriends = <String>[];
  bool _allowFriendsPicker = false;
  bool _reauthTriggered = false;

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

  @override
  void initState() {
    super.initState();
    _ownsHttpClient = widget.client == null;
    _http = widget.client ?? shamellHttpClient();
    _init();
  }

  Future<void> _init() async {
    _currency = shamellNormalizeWalletCurrency(widget.walletCurrency);
    try {
      final sp = await SharedPreferences.getInstance();
      final caps = await ShamellCapabilities.loadForBaseUrl(
        widget.baseUrl,
        sp: sp,
      );
      _allowFriendsPicker = caps.friends;
      final localWallet = (await loadStoredWalletId(
                sp: sp,
                baseUrlOverride: widget.baseUrl,
              ) ??
              '')
          .trim();
      _walletId = localWallet.isNotEmpty ? localWallet : widget.fromWalletId;
    } catch (_) {
      _walletId = widget.fromWalletId;
    }
    if (mounted) {
      setState(() {});
    }
    await _loadWallet();
  }

  Future<void> _loadWallet() async {
    final wid = _walletId.trim();
    if (wid.isEmpty) return;
    final uri = _paymentsUri(pathSegments: <String>['wallets', wid]);
    if (uri == null) return;
    setState(() => _loadingWallet = true);
    try {
      final r = await _http
          .get(uri, headers: await _hdrPS(widget.baseUrl))
          .timeout(_paymentsSendRequestTimeout);
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: r.statusCode,
        rawBody: r.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is Map<String, dynamic>) {
          final bal = body['balance_cents'];
          if (bal is int) {
            _balanceCents = bal;
          } else if (bal is num) {
            _balanceCents = bal.toInt();
          }
          final currency = (body['currency'] ?? '').toString().trim();
          if (currency.isNotEmpty) {
            _currency = shamellNormalizeWalletCurrency(currency);
          }
        }
      }
    } catch (e) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
    }
    if (mounted) {
      setState(() => _loadingWallet = false);
    }
  }

  @override
  void dispose() {
    _recipientsCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    if (_ownsHttpClient) {
      _http.close();
    }
    super.dispose();
  }

  Future<bool?> _showConfirmDialog(WidgetBuilder builder) {
    final launcher = widget.confirmDialogLauncher;
    if (launcher != null) {
      return launcher(context, builder);
    }
    return showDialog<bool>(context: context, builder: builder);
  }

  List<String> _parseRecipients() {
    final set = <String>{};
    for (final f in _selectedFriends) {
      final v = f.trim();
      if (v.isNotEmpty) set.add(v);
    }
    final raw = _recipientsCtrl.text;
    final parts = raw
        .split(RegExp(r'[,\n;]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    set.addAll(parts);
    final list = set.toList();
    list.sort();
    return list;
  }

  List<int> _computeSplits(int totalCents, int count) {
    if (count <= 0 || totalCents <= 0) {
      return List<int>.filled(count, 0);
    }
    final per = totalCents ~/ count;
    final rem = totalCents % count;
    final out = List<int>.filled(count, per);
    for (var i = 0; i < rem; i++) {
      out[i] = out[i] + 1;
    }
    return out;
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

  Future<bool> _forceReauthForCriticalDeviceBindingDrift(Object error) async {
    if (!shamellIsCriticalAccountSessionError(error)) {
      return false;
    }
    if (_reauthTriggered) {
      return true;
    }
    _reauthTriggered = true;
    if (!mounted) {
      return true;
    }
    final forced = await shamellForceReauthIfCriticalDeviceBindingDrift(
      context,
      error: error,
      loginPageBuilder: (_) => const LoginPage(),
    );
    if (!forced) {
      _reauthTriggered = false;
    }
    return forced;
  }

  Future<List<_GroupSendOutcome>> _runRequestCreateBatch(
    List<String> recipients,
    List<int> splits,
  ) async {
    if (recipients.isEmpty) {
      return const <_GroupSendOutcome>[];
    }

    final results = List<_GroupSendOutcome?>.filled(recipients.length, null);
    var nextIndex = 0;
    var stopScheduling = false;

    Future<void> worker() async {
      while (true) {
        if (stopScheduling) {
          return;
        }
        final currentIndex = nextIndex;
        if (currentIndex >= recipients.length) {
          return;
        }
        nextIndex = currentIndex + 1;
        final outcome = await _createRequestForOne(
            recipients[currentIndex], splits[currentIndex]);
        results[currentIndex] = outcome;
        if (outcome == _GroupSendOutcome.reauth ||
            outcome == _GroupSendOutcome.invalidBase) {
          stopScheduling = true;
        }
      }
    }

    final workerCount =
        recipients.length < GroupPayPage.requestCreateMaxConcurrency
            ? recipients.length
            : GroupPayPage.requestCreateMaxConcurrency;
    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => worker(),
          growable: false),
    );
    return List<_GroupSendOutcome>.generate(
      results.length,
      (index) => results[index] ?? _GroupSendOutcome.failed,
      growable: false,
    );
  }

  String? _failedRecipientsSummary(List<String> failedRecipients) {
    if (failedRecipients.isEmpty) {
      return null;
    }
    final l = L10n.of(context);
    final shown = failedRecipients
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .take(3)
        .toList(growable: false);
    if (shown.isEmpty) {
      return null;
    }
    final remaining = failedRecipients.length - shown.length;
    final suffix = remaining > 0
        ? (l.isArabic ? ' +$remaining آخرين' : ' +$remaining more')
        : '';
    return l.isArabic
        ? 'المتأثرون: ${shown.join('، ')}$suffix'
        : 'Affected: ${shown.join(', ')}$suffix';
  }

  Future<_GroupSendOutcome> _createRequestForOne(
      String to, int amountCents) async {
    final wid =
        _walletId.trim().isEmpty ? widget.fromWalletId : _walletId.trim();
    if (wid.isEmpty || amountCents <= 0) return _GroupSendOutcome.failed;
    final note = _noteCtrl.text.trim();
    final basePayload = <String, Object?>{
      'from_wallet_id': wid,
      'amount_cents': amountCents,
      if (note.isNotEmpty) 'message': note,
      'expires_in_secs': 24 * 3600,
    };
    final raw = to.trim();
    final isPhone = raw.startsWith('+') || RegExp(r'^[0-9]{6,}$').hasMatch(raw);
    if (isPhone) return _GroupSendOutcome.failed;

    final uri = _paymentsUri(pathSegments: <String>['requests']);
    if (uri == null) return _GroupSendOutcome.invalidBase;
    Map<String, Object?> payload;
    if (raw.startsWith('@')) {
      payload = {
        ...basePayload,
        'to_alias': raw,
      };
    } else {
      payload = {
        ...basePayload,
        'to_wallet_id': raw,
      };
    }
    final deviceId = await _effectiveDeviceId();
    final attestationHeaders = await (() async {
      try {
        return await shamellBuildPaymentMutationAttestationHeaders(
          baseUrl: widget.baseUrl,
          deviceId: deviceId,
          operation: 'payments_requests_create',
          resourceId: shamellPaymentRequestCreateAttestationResourceId(
            fromWalletId: wid,
            amountCents: amountCents,
            toWalletId: (payload['to_wallet_id'] ?? '').toString(),
            toAlias: (payload['to_alias'] ?? '').toString(),
          ),
          client: _http,
        );
      } on PaymentMutationAttestationHttpFailure catch (e) {
        if (await _forceReauthForCriticalSessionFailure(
          statusCode: e.statusCode,
          rawBody: e.rawBody,
        )) {
          return null;
        }
        return null;
      } catch (e) {
        if (await _forceReauthForCriticalDeviceBindingDrift(e)) {
          return null;
        }
        return null;
      }
    })();
    if (attestationHeaders == null) {
      return _GroupSendOutcome.failed;
    }
    try {
      final resp = await GroupPayPage.postGroupPaymentRequestCreate(
        client: _http,
        uri: uri,
        payload: payload,
        deviceId: deviceId,
        headersLoader: () async {
          final headers = await _hdrPS(widget.baseUrl, json: true);
          headers.addAll(attestationHeaders);
          return headers;
        },
      );
      if (await _forceReauthForCriticalSessionFailure(
        statusCode: resp.statusCode,
        rawBody: resp.body,
      )) {
        return _GroupSendOutcome.reauth;
      }
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        Perf.action('pay_group_req_ok');
        return _GroupSendOutcome.success;
      }
      if (resp.statusCode >= 500) {
        Perf.action('pay_group_req_fail_server');
      } else {
        Perf.action('pay_group_req_fail_client');
      }
      return _GroupSendOutcome.failed;
    } catch (e) {
      if (await _forceReauthForCriticalDeviceBindingDrift(e)) {
        return _GroupSendOutcome.reauth;
      }
      Perf.action('pay_group_req_error');
      return _GroupSendOutcome.failed;
    }
  }

  Future<_GroupSendOutcome> _sendOne(String to, int amountCents) async {
    final wid =
        _walletId.trim().isEmpty ? widget.fromWalletId : _walletId.trim();
    if (wid.isEmpty) return _GroupSendOutcome.failed;
    final raw = to.trim();
    final isPhone = raw.startsWith('+') || RegExp(r'^[0-9]{6,}$').hasMatch(raw);
    if (isPhone) {
      // Best practice: do not route transfers by phone number in group flows.
      return _GroupSendOutcome.failed;
    }
    final uri = _paymentsUri(pathSegments: <String>['transfer']);
    if (uri == null) return _GroupSendOutcome.invalidBase;
    final target = buildTransferTarget(raw);
    if (target.isEmpty) {
      return _GroupSendOutcome.failed;
    }
    final payload = <String, dynamic>{
      'from_wallet_id': wid,
      'amount_cents': amountCents,
      if (_noteCtrl.text.trim().isNotEmpty) 'reference': _noteCtrl.text.trim(),
      ...target,
    };
    final ikey = newPaymentsIdempotencyKey('twg');
    final t0 = DateTime.now().millisecondsSinceEpoch;
    final deviceId = await _effectiveDeviceId();
    final attestationHeaders = await (() async {
      try {
        return await shamellBuildPaymentMutationAttestationHeaders(
          baseUrl: widget.baseUrl,
          deviceId: deviceId,
          operation: 'payments_transfer',
          resourceId: shamellPaymentTransferAttestationResourceId(
            fromWalletId: wid,
            amountCents: amountCents,
            toWalletId: (target['to_wallet_id'] ?? '').toString(),
            toAlias: (target['to_alias'] ?? '').toString(),
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
          return <String, String>{'__reauth__': '1'};
        }
        return null;
      } catch (_) {
        return null;
      }
    })();
    if (attestationHeaders == null) {
      Perf.action('pay_group_send_attestation_failed');
      return _GroupSendOutcome.failed;
    }
    if (attestationHeaders['__reauth__'] == '1') {
      return _GroupSendOutcome.reauth;
    }
    try {
      final headers = (await _hdrPS(widget.baseUrl, json: true))
        ..addAll({'Idempotency-Key': ikey, 'X-Device-ID': deviceId})
        ..addAll(attestationHeaders);
      final resp = await _http
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(_paymentsSendRequestTimeout);
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: resp.statusCode,
        rawBody: resp.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return _GroupSendOutcome.reauth;
      }
      if (resp.statusCode == 429) {
        Perf.action('pay_group_send_rate_limited');
        return _GroupSendOutcome.failed;
      }
      if (resp.statusCode >= 500) {
        await OfflineQueue.enqueue(
            OfflineTask(
              id: ikey,
              method: 'POST',
              url: uri.toString(),
              headers: _paymentsOfflineQueueHeaders(headers),
              body: jsonEncode(payload),
              tag: 'payments_transfer',
              createdAt: DateTime.now().millisecondsSinceEpoch,
            ),
            baseUrlOverride: widget.baseUrl);
        Perf.action('pay_group_send_queued');
        return _GroupSendOutcome.queued;
      }
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        Perf.action('pay_group_send_ok');
        final dt = DateTime.now().millisecondsSinceEpoch - t0;
        Perf.sample('pay_group_send_ms', dt);
        return _GroupSendOutcome.success;
      }
      Perf.action('pay_group_send_fail');
      return _GroupSendOutcome.failed;
    } catch (e) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return _GroupSendOutcome.reauth;
      }
      try {
        final headers = (await _hdrPS(widget.baseUrl, json: true))
          ..addAll({'Idempotency-Key': ikey, 'X-Device-ID': deviceId})
          ..addAll(attestationHeaders);
        await OfflineQueue.enqueue(
            OfflineTask(
              id: ikey,
              method: 'POST',
              url: uri.toString(),
              headers: _paymentsOfflineQueueHeaders(headers),
              body: jsonEncode(payload),
              tag: 'payments_transfer',
              createdAt: DateTime.now().millisecondsSinceEpoch,
            ),
            baseUrlOverride: widget.baseUrl);
        Perf.action('pay_group_send_queued');
        return _GroupSendOutcome.queued;
      } catch (_) {
        return _GroupSendOutcome.failed;
      }
    }
  }

  Future<void> _submit() async {
    final l = L10n.of(context);
    final recipients = _parseRecipients();
    final totalCents = parseCents(_amountCtrl.text.trim());
    if (recipients.length < 2 || totalCents <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.payCheckInputs)),
      );
      return;
    }
    final hasPhone = recipients.any(
      (r) => r.startsWith('+') || RegExp(r'^[0-9]{6,}$').hasMatch(r),
    );
    if (hasPhone) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'أرقام الهاتف غير مدعومة. استخدم مُعرّفات المحافظ أو @أسماء.'
                : 'Phone numbers are not supported. Use wallet IDs or @aliases.',
          ),
        ),
      );
      return;
    }
    final splits = _computeSplits(totalCents, recipients.length);
    final totalMajor = totalCents / 100.0;
    final perPreviewMajor = splits.first / 100.0;
    final ok = await _showConfirmDialog(
      (ctx) {
        return AlertDialog(
          title:
              Text(l.isArabic ? 'تأكيد السداد الجماعي' : 'Confirm group pay'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.isArabic
                    ? 'إجمالي المبلغ: ${totalMajor.toStringAsFixed(2)} $_currency'
                    : 'Total amount: ${totalMajor.toStringAsFixed(2)} $_currency',
              ),
              const SizedBox(height: 4),
              Text(
                l.isArabic
                    ? 'عدد المستلمين: ${recipients.length}'
                    : 'Recipients: ${recipients.length}',
              ),
              const SizedBox(height: 4),
              Text(
                l.isArabic
                    ? 'حصة تقريبية لكل شخص: ${perPreviewMajor.toStringAsFixed(2)} $_currency'
                    : 'Approx. per person: ${perPreviewMajor.toStringAsFixed(2)} $_currency',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.shamellDialogCancel),
            ),
            TextButton(
              key: const Key('groupPayCreateRequestsConfirmButton'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.shamellDialogOk),
            ),
          ],
        );
      },
    );
    if (ok != true) return;

    setState(() {
      _submitting = true;
      _out = '';
    });

    int success = 0;
    int queued = 0;
    int failed = 0;

    for (var i = 0; i < recipients.length; i++) {
      final res = await _sendOne(recipients[i], splits[i]);
      if (res == _GroupSendOutcome.reauth) {
        return;
      } else if (res == _GroupSendOutcome.invalidBase) {
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _out = _invalidServerUrlMessage();
        });
        return;
      } else if (res == _GroupSendOutcome.success) {
        success++;
      } else if (res == _GroupSendOutcome.queued) {
        queued++;
      } else {
        failed++;
      }
    }

    if (!mounted) return;
    if (success > 0) {
      unawaited(ShamellSoundEffects.play(ShamellSoundEffect.paymentSent));
      shamellRecordAppActivity(
        baseUrl: widget.baseUrl,
        eventType: 'payment_group_transfer_sent',
        moduleId: 'payments',
        action: 'group_transfer_sent',
        metadata: <String, Object?>{
          'success_count': success,
          'currency': _currency,
        },
        client: _http,
      );
    }
    setState(() {
      _submitting = false;
      final parts = <String>[];
      if (success > 0) {
        parts.add(
          l.isArabic ? 'عمليات ناجحة: $success' : 'Successful: $success',
        );
      }
      if (queued > 0) {
        parts.add(
          l.isArabic
              ? 'في الانتظار (بدون اتصال): $queued'
              : 'Queued (offline): $queued',
        );
      }
      if (failed > 0) {
        parts.add(
          l.isArabic ? 'فشلت: $failed' : 'Failed: $failed',
        );
      }
      _out = parts.isEmpty ? l.paySendFailed : parts.join(' · ');
    });
  }

  Future<void> _submitAsRequests() async {
    final l = L10n.of(context);
    final recipients = _parseRecipients();
    final totalCents = parseCents(_amountCtrl.text.trim());
    if (recipients.length < 2 || totalCents <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.payCheckInputs)),
      );
      return;
    }
    final hasPhone = recipients.any(
      (r) => r.startsWith('+') || RegExp(r'^[0-9]{6,}$').hasMatch(r),
    );
    if (hasPhone) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'أرقام الهاتف غير مدعومة. استخدم مُعرّفات المحافظ أو @أسماء.'
                : 'Phone numbers are not supported. Use wallet IDs or @aliases.',
          ),
        ),
      );
      return;
    }
    final splits = _computeSplits(totalCents, recipients.length);
    final totalMajor = totalCents / 100.0;
    final perPreviewMajor = splits.first / 100.0;
    final ok = await _showConfirmDialog(
      (ctx) {
        return AlertDialog(
          title: Text(
            l.isArabic
                ? 'إنشاء طلبات سداد جماعي'
                : 'Create split‑bill requests',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.isArabic
                    ? 'إجمالي المبلغ: ${totalMajor.toStringAsFixed(2)} $_currency'
                    : 'Total amount: ${totalMajor.toStringAsFixed(2)} $_currency',
              ),
              const SizedBox(height: 4),
              Text(
                l.isArabic
                    ? 'عدد المستلمين: ${recipients.length}'
                    : 'Recipients: ${recipients.length}',
              ),
              const SizedBox(height: 4),
              Text(
                l.isArabic
                    ? 'سيتم إنشاء طلب لكل شخص بحصة تقريبية ${perPreviewMajor.toStringAsFixed(2)} $_currency.'
                    : 'One request per person with ~${perPreviewMajor.toStringAsFixed(2)} $_currency.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.shamellDialogCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.shamellDialogOk),
            ),
          ],
        );
      },
    );
    if (ok != true) return;

    setState(() {
      _submitting = true;
      _out = '';
    });

    final results = await _runRequestCreateBatch(recipients, splits);
    if (results.contains(_GroupSendOutcome.reauth)) {
      if (!mounted) return;
      setState(() => _submitting = false);
      return;
    }
    if (results.contains(_GroupSendOutcome.invalidBase)) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _out = _invalidServerUrlMessage();
      });
      return;
    }

    int success = 0;
    int failed = 0;
    final failedRecipients = <String>[];
    for (var i = 0; i < results.length; i++) {
      final res = results[i];
      if (res == _GroupSendOutcome.success) {
        success++;
      } else {
        failed++;
        failedRecipients.add(recipients[i]);
      }
    }

    if (!mounted) return;
    if (success > 0) {
      unawaited(ShamellSoundEffects.play(ShamellSoundEffect.paymentRequest));
      shamellRecordAppActivity(
        baseUrl: widget.baseUrl,
        eventType: 'payment_requests_created',
        moduleId: 'payments',
        action: 'requests_created',
        metadata: <String, Object?>{
          'success_count': success,
          'currency': _currency,
        },
        client: _http,
      );
    }
    setState(() {
      _submitting = false;
      final parts = <String>[];
      if (success > 0) {
        parts.add(
          l.isArabic
              ? 'تم إنشاء طلبات: $success'
              : 'Requests created: $success',
        );
      }
      if (failed > 0) {
        parts.add(
          l.isArabic ? 'فشلت: $failed' : 'Failed: $failed',
        );
        final failedSummary = _failedRecipientsSummary(failedRecipients);
        if (failedSummary != null) {
          parts.add(failedSummary);
        }
      }
      _out = parts.isEmpty
          ? (l.isArabic
              ? 'تعذر إنشاء طلبات السداد.'
              : 'Could not create split‑bill requests.')
          : parts.join(' · ');
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final bal = _balanceCents;
    final totalCents = parseCents(_amountCtrl.text.trim());
    final recipients = _parseRecipients();
    final perCents =
        recipients.isNotEmpty ? totalCents ~/ recipients.length : 0;
    final perMajor = perCents / 100.0;
    final widLabel =
        _walletId.trim().isEmpty ? (l.walletNotSetShort) : _walletId.trim();
    return Scaffold(
      appBar: AppBar(
        title: Text(l.isArabic ? 'تقسيم الفاتورة' : 'Split bill'),
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
                    l.isArabic ? 'ملخّص السداد الجماعي' : 'Group pay summary',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.74),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ShamellPaymentMetricChip(
                        label: l.isArabic ? 'الرصيد' : 'Balance',
                        value: bal == null
                            ? (_loadingWallet ? '…' : '—')
                            : '${fmtCents(bal)} $_currency',
                        icon: Icons.account_balance_wallet_outlined,
                      ),
                      ShamellPaymentMetricChip(
                        label: l.isArabic ? 'الإجمالي' : 'Total',
                        value: totalCents > 0
                            ? '${(totalCents / 100.0).toStringAsFixed(2)} $_currency'
                            : '—',
                        icon: Icons.receipt_long_outlined,
                      ),
                      ShamellPaymentMetricChip(
                        label: l.isArabic ? 'الأشخاص' : 'People',
                        value: recipients.length.toString(),
                        icon: Icons.groups_2_outlined,
                      ),
                      ShamellPaymentMetricChip(
                        label: l.isArabic ? 'حصة تقريبية' : 'Approx. each',
                        value: (perMajor > 0 && recipients.length >= 2)
                            ? '${perMajor.toStringAsFixed(2)} $_currency'
                            : '—',
                        icon: Icons.call_split_rounded,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_out.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: ShamellPaymentCardSurface(
                  tone: ShamellPaymentCardTone.soft,
                  child: Text(
                    _out,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.82),
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            ShamellPaymentCardSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.isArabic ? 'المبلغ الإجمالي' : 'Total amount',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l.isArabic
                        ? 'اكتب قيمة الفاتورة، وسنوزعها بالتساوي.'
                        : 'Enter the bill value and SyrChat will split it evenly.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.70),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _amountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: l.payAmountLabel,
                    ),
                    onChanged: (_) => setState(() {}),
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
                    l.isArabic ? 'المستلمون' : 'Recipients',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l.isArabic
                        ? 'أضف محافظ أو أسماء مستخدمين، أو اختر من الأصدقاء.'
                        : 'Add wallet IDs or aliases, or pull them in from friends.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.70),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_allowFriendsPicker)
                        ShamellPaymentPillButton(
                          icon: const Icon(Icons.group_outlined, size: 16),
                          label: Text(
                            l.isArabic
                                ? 'اختيار من الأصدقاء'
                                : 'Choose from friends',
                          ),
                          onPressed: () async {
                            final res = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FriendsPage(widget.baseUrl),
                              ),
                            );
                            if (!mounted) return;
                            if (res is String && res.trim().isNotEmpty) {
                              setState(() {
                                _selectedFriends.add(res.trim());
                              });
                            }
                          },
                        ),
                      ShamellPaymentPillButton(
                        icon: const Icon(Icons.clear_all_outlined, size: 16),
                        label: Text(
                          l.isArabic ? 'مسح القائمة' : 'Clear list',
                        ),
                        onPressed: () {
                          setState(() {
                            _selectedFriends.clear();
                            _recipientsCtrl.clear();
                          });
                        },
                      ),
                    ],
                  ),
                  if (_selectedFriends.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _selectedFriends.map((v) {
                        return Chip(
                          label: Text(
                            v,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onDeleted: () {
                            setState(() {
                              _selectedFriends.remove(v);
                            });
                          },
                        );
                      }).toList(growable: false),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _recipientsCtrl,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: l.isArabic
                          ? 'معرّف المحفظة أو @اسم في كل سطر'
                          : 'Wallet ID or @alias per line',
                    ),
                    onChanged: (_) => setState(() {}),
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
                    l.isArabic ? 'ملاحظة' : 'Note',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _noteCtrl,
                    decoration: InputDecoration(
                      labelText: l.payNoteLabel,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ShamellPaymentCardSurface(
              tone: ShamellPaymentCardTone.soft,
              child: Column(
                children: [
                  PrimaryButton(
                    label: _submitting
                        ? (l.isArabic ? 'جارٍ العمل…' : 'Working…')
                        : (l.isArabic ? 'دفع الحصة الآن' : 'Pay shares now'),
                    onPressed: _submitting ? null : _submit,
                    expanded: true,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: const Key('groupPayCreateRequestsButton'),
                    onPressed: _submitting ? null : _submitAsRequests,
                    child: Text(
                      l.isArabic
                          ? 'أو إنشاء طلبات سداد للفاتورة'
                          : 'Or create split‑bill requests',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _GroupSendOutcome { success, queued, failed, reauth, invalidBase }

Future<Map<String, String>> _hdrPS(String baseUrl, {bool json = false}) async {
  return shamellSessionHeadersForBaseUrl(baseUrl, json: json);
}

class PayActionButton extends StatelessWidget {
  final IconData? icon;
  final String label;
  // Nullable so parents (PaymentScanTab, payment-request banners) can
  // disable the button while a money mutation is in flight (gated by
  // MoneyMutationGuardMixin). InkWell already accepts a null `onTap`
  // and renders an un-tappable state, so we just forward through.
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double radius;
  final Color? tint;
  const PayActionButton(
      {super.key,
      this.icon,
      required this.label,
      required this.onTap,
      this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      this.radius = 8,
      this.tint});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color base = tint ?? theme.colorScheme.primary;
    final fill = isDark
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: .24)
        : WeChatPalette.searchFill;
    final Color border = Color.lerp(
          theme.dividerColor.withValues(alpha: isDark ? .42 : .82),
          base.withValues(alpha: isDark ? .18 : .12),
          .32,
        ) ??
        theme.dividerColor;
    final Color textColor = Color.lerp(
          theme.colorScheme.onSurface,
          base,
          isDark ? .34 : .42,
        ) ??
        theme.colorScheme.onSurface;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null)
          Icon(icon, size: 18, color: textColor.withValues(alpha: .95)),
        if (icon != null) const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            softWrap: true,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
    final bool disabled = onTap == null;
    return Opacity(
      // Match SendButton's dimmed-disabled look for visual consistency
      // across the Send / Scan / Receive surfaces — both gates flow
      // from the same MoneyMutationGuardMixin.
      opacity: disabled ? .55 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: border),
              color: fill,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? .10 : .018),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: padding,
              child: Center(child: content),
            ),
          ),
        ),
      ),
    );
  }
}
