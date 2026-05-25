import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show LoginPage;
import 'glass.dart';
import 'skeleton.dart';
import 'offline_queue.dart';
import 'format.dart' show fmtCents;
import 'l10n.dart';
import 'http_error.dart';
import 'payment_event_bus.dart';
import 'payment_event_gateway.dart';
import 'payments/currency_symbol_store.dart';
import 'payments/payments_card_style.dart';
import 'device_binding_reauth.dart';
import 'design_tokens.dart';
import 'app_shell_widgets.dart' show AppBG; // reuse background only
import 'package:shamell_flutter/core/session_cookie_store.dart';
import 'base_url.dart';
import 'safe_set_state.dart';

const Duration _historyRequestTimeout = Duration(seconds: 15);
const int _historyPageSize = 25;
const String _historyDirLegacyPrefKey = 'ph_dir';
const String _historyKindLegacyPrefKey = 'ph_kind';
const String _historyDateLegacyPrefKey = 'ph_date';
const String _historyFromLegacyPrefKey = 'ph_from';
const String _historyToLegacyPrefKey = 'ph_to';
const String _historyDirScopedPrefKeyPrefix = 'ph_dir.v2.';
const String _historyKindScopedPrefKeyPrefix = 'ph_kind.v2.';
const String _historyDateScopedPrefKeyPrefix = 'ph_date.v2.';
const String _historyFromScopedPrefKeyPrefix = 'ph_from.v2.';
const String _historyToScopedPrefKeyPrefix = 'ph_to.v2.';
const String _historyUnknownScope = 'unknown';

class HistoryFilterPreferenceState {
  final String dir;
  final String kind;
  final String date;
  final DateTime? fromDate;
  final DateTime? toDate;

  const HistoryFilterPreferenceState({
    this.dir = 'all',
    this.kind = 'all',
    this.date = 'all',
    this.fromDate,
    this.toDate,
  });
}

Future<HistoryFilterPreferenceState> loadHistoryFilterPreferences({
  required String baseUrl,
  SharedPreferences? sp,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scope = _historyFilterScopeForBaseUrl(baseUrl);
  final dirScopedKey =
      _historyFilterScopedPrefKey(_historyDirScopedPrefKeyPrefix, scope);
  final kindScopedKey =
      _historyFilterScopedPrefKey(_historyKindScopedPrefKeyPrefix, scope);
  final dateScopedKey =
      _historyFilterScopedPrefKey(_historyDateScopedPrefKeyPrefix, scope);
  final fromScopedKey =
      _historyFilterScopedPrefKey(_historyFromScopedPrefKeyPrefix, scope);
  final toScopedKey =
      _historyFilterScopedPrefKey(_historyToScopedPrefKeyPrefix, scope);

  String dir = (prefs.getString(dirScopedKey) ?? '').trim();
  String kind = (prefs.getString(kindScopedKey) ?? '').trim();
  String date = (prefs.getString(dateScopedKey) ?? '').trim();
  DateTime? fromDate =
      DateTime.tryParse((prefs.getString(fromScopedKey) ?? '').trim());
  DateTime? toDate =
      DateTime.tryParse((prefs.getString(toScopedKey) ?? '').trim());

  final legacyDir = (prefs.getString(_historyDirLegacyPrefKey) ?? '').trim();
  final legacyKind = (prefs.getString(_historyKindLegacyPrefKey) ?? '').trim();
  final legacyDate = (prefs.getString(_historyDateLegacyPrefKey) ?? '').trim();
  final legacyFrom = DateTime.tryParse(
      (prefs.getString(_historyFromLegacyPrefKey) ?? '').trim());
  final legacyTo = DateTime.tryParse(
      (prefs.getString(_historyToLegacyPrefKey) ?? '').trim());

  if (_isUnknownHistoryFilterScope(scope)) {
    if (dir.isEmpty && legacyDir.isNotEmpty) {
      dir = legacyDir;
      await prefs.setString(dirScopedKey, legacyDir);
    }
    if (kind.isEmpty && legacyKind.isNotEmpty) {
      kind = legacyKind;
      await prefs.setString(kindScopedKey, legacyKind);
    }
    if (date.isEmpty && legacyDate.isNotEmpty) {
      date = legacyDate;
      await prefs.setString(dateScopedKey, legacyDate);
    }
    if (fromDate == null && legacyFrom != null) {
      fromDate = legacyFrom;
      await prefs.setString(fromScopedKey, legacyFrom.toIso8601String());
    }
    if (toDate == null && legacyTo != null) {
      toDate = legacyTo;
      await prefs.setString(toScopedKey, legacyTo.toIso8601String());
    }
  }

  await prefs.remove(_historyDirLegacyPrefKey);
  await prefs.remove(_historyKindLegacyPrefKey);
  await prefs.remove(_historyDateLegacyPrefKey);
  await prefs.remove(_historyFromLegacyPrefKey);
  await prefs.remove(_historyToLegacyPrefKey);

  return HistoryFilterPreferenceState(
    dir: dir.isEmpty ? 'all' : dir,
    kind: kind.isEmpty ? 'all' : kind,
    date: date.isEmpty ? 'all' : date,
    fromDate: fromDate,
    toDate: toDate,
  );
}

Future<void> saveHistoryFilterPreferences({
  required String baseUrl,
  required String dir,
  required String kind,
  required String date,
  DateTime? fromDate,
  DateTime? toDate,
  SharedPreferences? sp,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scope = _historyFilterScopeForBaseUrl(baseUrl);
  await prefs.setString(
    _historyFilterScopedPrefKey(_historyDirScopedPrefKeyPrefix, scope),
    dir.trim(),
  );
  await prefs.setString(
    _historyFilterScopedPrefKey(_historyKindScopedPrefKeyPrefix, scope),
    kind.trim(),
  );
  await prefs.setString(
    _historyFilterScopedPrefKey(_historyDateScopedPrefKeyPrefix, scope),
    date.trim(),
  );
  final fromScopedKey =
      _historyFilterScopedPrefKey(_historyFromScopedPrefKeyPrefix, scope);
  final toScopedKey =
      _historyFilterScopedPrefKey(_historyToScopedPrefKeyPrefix, scope);
  if (fromDate == null) {
    await prefs.remove(fromScopedKey);
  } else {
    await prefs.setString(fromScopedKey, fromDate.toIso8601String());
  }
  if (toDate == null) {
    await prefs.remove(toScopedKey);
  } else {
    await prefs.setString(toScopedKey, toDate.toIso8601String());
  }
  await prefs.remove(_historyDirLegacyPrefKey);
  await prefs.remove(_historyKindLegacyPrefKey);
  await prefs.remove(_historyDateLegacyPrefKey);
  await prefs.remove(_historyFromLegacyPrefKey);
  await prefs.remove(_historyToLegacyPrefKey);
}

String _historyFilterScopeForBaseUrl(String baseUrl) {
  final normalized = normalizeSecureApiBaseUrl(baseUrl) ?? '';
  if (normalized.isEmpty) return _historyUnknownScope;
  return Uri.parse(normalized).origin;
}

bool _isUnknownHistoryFilterScope(String scope) =>
    scope == _historyUnknownScope;

String _historyFilterScopedPrefKey(String prefix, String scope) =>
    '$prefix$scope';

class _HistoryCursor {
  final String createdAt;
  final String id;

  const _HistoryCursor({required this.createdAt, required this.id});
}

List<Map<String, dynamic>> _normalizeHistoryTxnList(dynamic raw) {
  if (raw is! List) return const <Map<String, dynamic>>[];
  return raw
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

_HistoryCursor? _historyCursorFromTxn(Map<String, dynamic>? txn) {
  if (txn == null) return null;
  final createdAt = (txn['created_at'] ?? '').toString().trim();
  final id = (txn['id'] ?? '').toString().trim();
  if (createdAt.isEmpty || id.isEmpty) return null;
  return _HistoryCursor(createdAt: createdAt, id: id);
}

List<Map<String, dynamic>> _mergeHistoryTxnPages(
  List<Map<String, dynamic>> existing,
  List<Map<String, dynamic>> incoming,
) {
  if (incoming.isEmpty) return existing;
  final merged = <Map<String, dynamic>>[...existing];
  final seenIds = existing
      .map((txn) => (txn['id'] ?? '').toString().trim())
      .where((id) => id.isNotEmpty)
      .toSet();
  for (final txn in incoming) {
    final id = (txn['id'] ?? '').toString().trim();
    if (id.isEmpty || seenIds.add(id)) {
      merged.add(txn);
    }
  }
  return merged;
}

class HistoryPage extends StatefulWidget {
  final String baseUrl;
  final String walletId;
  final List<Map<String, dynamic>>? initialTxns;
  final String? initialKind;
  final http.Client? client;

  /// Cycle 3C: injectable seam over the realtime payment-event source
  /// (singleton [PaymentEventBus] + [PaymentEventStream] in production).
  /// Defaults to a [DefaultPaymentEventGateway] when null, preserving the
  /// pre-3C runtime behaviour exactly. Widget tests can pass a
  /// `FakePaymentEventGateway` from `test/fakes/` to avoid the reconnect
  /// `Timer` race that previously broke `history_page_session_guard_test`.
  final PaymentEventGateway? paymentEventGateway;

  const HistoryPage(
      {super.key,
      required this.baseUrl,
      required this.walletId,
      this.initialTxns,
      this.initialKind,
      this.client,
      this.paymentEventGateway});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage>
    with SafeSetStateMixin<HistoryPage>, WidgetsBindingObserver {
  List<Map<String, dynamic>> txns = [];
  String out = '';
  bool loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String _dirFilter = 'all';
  String _kindFilter = 'all';
  String _dateFilter = 'all';
  DateTime? _fromDate;
  DateTime? _toDate;
  String? _beforeCreatedAt;
  String? _beforeId;
  final _dirs = const ['all', 'out', 'in'];
  final _kinds = const [
    'all',
    'transfer',
    'topup',
    'cash',
    'sonic',
    'bill',
    'savings',
  ];
  final _dates = const ['all', '7d', '30d', 'custom'];
  String _curSym = 'SYP';

  // Audit-fix (C-P2-30): subscribe to PaymentEventBus so transfers /
  // refunds / top-ups landing while the user is staring at History
  // appear without manual pull-to-refresh. The same realtime SSE
  // singleton that PaymentOverviewTab consumes is reused — this
  // listener just adds a second consumer of the existing stream.
  StreamSubscription<PaymentEvent>? _paymentEventSub;

  /// Cycle 3C: resolved [PaymentEventGateway]. Either the widget's
  /// injected one (in tests) or the production default. Initialised once
  /// in [initState] so subsequent calls hit a stable handle even if the
  /// widget rebuilds.
  late final PaymentEventGateway _paymentEventGateway;

  /// Coalesces rapid back-to-back events so we never have two
  /// `_load(reset: true)` calls in flight against the same wallet.
  /// Whichever event arrives first kicks the reload; subsequent
  /// events while the reload is running are dropped, since the
  /// reload will already pick up every txn newer than its cursor.
  Future<void>? _pendingRefreshFromEvent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _paymentEventGateway =
        widget.paymentEventGateway ?? DefaultPaymentEventGateway();
    _loadPrefs();
    _paymentEventSub = _paymentEventGateway.stream.listen(_onPaymentEvent);
    _maybeStartRealtimeStream();
    if (widget.initialKind != null && widget.initialKind!.trim().isNotEmpty) {
      final v = widget.initialKind!.trim();
      _kindFilter = _kinds.contains(v) ? v : 'all';
    }
    if (widget.initialTxns != null) {
      txns = widget.initialTxns!
          .map((txn) => Map<String, dynamic>.from(txn))
          .toList(growable: false);
      loading = false;
      final cursor = _historyCursorFromTxn(txns.isEmpty ? null : txns.last);
      _beforeCreatedAt = cursor?.createdAt;
      _beforeId = cursor?.id;
      _hasMore = cursor != null;
    } else {
      _load();
    }
  }

  void _maybeStartRealtimeStream() {
    final base = widget.baseUrl.trim();
    final wallet = widget.walletId.trim();
    if (base.isEmpty || wallet.isEmpty) return;
    // The stream singleton dedupes per-(base, wallet); calling start
    // here is a no-op if PaymentOverviewTab has already initialised it.
    // HistoryPage doesn't carry a deviceId — that's fine, the BFF
    // accepts SSE subscriptions without it (auth is via the session
    // cookie, deviceId is informational for telemetry).
    //
    // Cycle 3C: routed through [_paymentEventGateway] so widget tests can
    // inject a fake whose `start` is a no-op (no reconnect Timer to leak).
    unawaited(_paymentEventGateway.start(
      baseUrl: base,
      walletId: wallet,
    ));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted) {
      // After the OS suspends us we may have missed SSE events. Kick
      // the singleton off any stale socket + force a fresh page-1
      // refresh so the on-screen list catches up to the wallet's
      // authoritative recent activity. Cycle 3C: routed through the
      // injected gateway for testability.
      _paymentEventGateway.reconnectNow();
      unawaited(_load(reset: true));
    }
  }

  void _onPaymentEvent(PaymentEvent event) {
    if (!mounted) return;
    final wallet = widget.walletId.trim();
    if (wallet.isEmpty) return;
    if (event.walletId != null &&
        event.walletId!.isNotEmpty &&
        event.walletId != wallet) {
      // Event for a different wallet (e.g. a secondary one); ignore.
      return;
    }
    if (event.kind == PaymentEventKind.unknown) return;
    final pending = _pendingRefreshFromEvent;
    if (pending != null) return;
    _pendingRefreshFromEvent = _load(reset: true).whenComplete(() {
      _pendingRefreshFromEvent = null;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _paymentEventSub?.cancel();
    _paymentEventSub = null;
    // PaymentEventStream is a process-wide singleton — we don't
    // `stop()` it on every History dispose because PaymentOverviewTab
    // (and any future surface) may still want the stream. The stream
    // shuts down on logout via the same wipe path that closes
    // session cookies.
    super.dispose();
  }

  Future<void> _load({bool reset = true}) async {
    if (reset) {
      setState(() => loading = true);
    } else {
      if (loading || _loadingMore || !_hasMore) return;
      setState(() => _loadingMore = true);
    }
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    try {
      final qp = <String, String>{'limit': _historyPageSize.toString()};
      if (_dirFilter != 'all') qp['dir'] = _dirFilter;
      if (_kindFilter != 'all') qp['kind'] = _kindFilter;
      DateTime? f;
      DateTime? t;
      if (_dateFilter == '7d') {
        f = DateTime.now().subtract(const Duration(days: 7));
      } else if (_dateFilter == '30d') {
        f = DateTime.now().subtract(const Duration(days: 30));
      } else if (_dateFilter == 'custom') {
        f = _fromDate;
        t = _toDate;
      }
      String toIso(DateTime d) => d.toUtc().toIso8601String();
      if (f != null) qp['from_iso'] = toIso(f);
      if (t != null) qp['to_iso'] = toIso(t);
      if (!reset && _beforeCreatedAt != null && _beforeId != null) {
        qp['before_created_at'] = _beforeCreatedAt!;
        qp['before_id'] = _beforeId!;
      }
      final u = secureApiChildUri(
        baseUrl: widget.baseUrl,
        pathSegments: <String>['wallets', widget.walletId, 'snapshot'],
        queryParameters: qp,
      );
      if (u == null) {
        final isArabic =
            Localizations.maybeLocaleOf(context)?.languageCode == 'ar';
        txns = [];
        out = isArabic ? 'عنوان الخادم غير صالح.' : 'Invalid server URL.';
      } else {
        final r = await httpClient
            .get(u, headers: await _hdr(widget.baseUrl))
            .timeout(_historyRequestTimeout);
        if (!mounted) return;
        if (r.statusCode == 200) {
          final j = jsonDecode(r.body) as Map<String, dynamic>;
          final page = _normalizeHistoryTxnList(j['txns']);
          if (j['txns'] is List) {
            txns = reset ? page : _mergeHistoryTxnPages(txns, page);
            final cursor =
                page.isEmpty ? null : _historyCursorFromTxn(page.last);
            _beforeCreatedAt = cursor?.createdAt;
            _beforeId = cursor?.id;
            _hasMore = page.length >= _historyPageSize && cursor != null;
            out = '';
          } else {
            out = L10n.of(context).historyUnexpectedFormat;
          }
          final w = j['wallet'];
          if (w is Map<String, dynamic>) {
            final cur = (w['currency'] ?? '').toString();
            if (cur.isNotEmpty) {
              _curSym = cur;
              unawaited(
                saveStoredCurrencySymbol(cur, baseUrl: widget.baseUrl),
              );
            }
          }
        } else {
          if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
            context,
            statusCode: r.statusCode,
            rawBody: r.body,
            loginPageBuilder: (_) => const LoginPage(),
          )) {
            return;
          }
          out = sanitizeHttpError(
            statusCode: r.statusCode,
            rawBody: r.body,
            isArabic: L10n.of(context).isArabic,
          );
        }
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
      out = sanitizeExceptionForUi(
        error: e,
        isArabic: L10n.of(context).isArabic,
      );
    } finally {
      if (closeClient) {
        httpClient.close();
      }
    }
    if (!mounted) return;
    setState(() {
      if (reset) {
        loading = false;
      } else {
        _loadingMore = false;
      }
    });
  }

  Future<void> _loadMore() async {
    await _load(reset: false);
  }

  void _exportCsv() {
    try {
      final headers = [
        'time',
        'kind',
        'amount_cents',
        'amount_fmt',
        'from_wallet',
        'to_wallet',
        'note'
      ];
      final rows = <List<String>>[headers];
      for (final t in _filtered()) {
        final ac = (t['amount_cents'] ?? 0) as int;
        final af = fmtCents(ac) + ' ' + (_curSym);
        rows.add([
          (t['created_at'] ?? '').toString(),
          (t['kind'] ?? '').toString(),
          (t['amount_cents'] ?? '').toString(),
          af,
          (t['from_wallet_id'] ?? '').toString(),
          (t['to_wallet_id'] ?? '').toString(),
          (t['reference'] ?? '').toString(),
        ]);
      }
      final csv = rows
          .map((r) =>
              r.map((c) => '"' + c.replaceAll('"', '""') + '"').join(','))
          .join('\n');
      final subject = L10n.of(context).historyExportSubject;
      Share.share(csv, subject: subject);
    } catch (e) {
      final l = L10n.of(context);
      final detail = sanitizeExceptionForUi(
        error: e,
        isArabic: l.isArabic,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l.historyCsvErrorPrefix}: $detail')),
      );
    }
  }

  List<Map<String, dynamic>> _filtered() {
    final now = DateTime.now();
    int? minEpoch;
    if (_dateFilter == '7d') {
      minEpoch = now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    } else if (_dateFilter == '30d') {
      minEpoch = now.subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    }
    return txns.where((t) {
      final from = (t['from_wallet_id'] ?? '').toString();
      final dirOkay = _dirFilter == 'all' ||
          (_dirFilter == 'out'
              ? from == widget.walletId
              : from != widget.walletId);
      final kind = (t['kind'] ?? '').toString().toLowerCase();
      final kindOkay = _kindFilter == 'all' || kind.contains(_kindFilter);
      bool dateOkay = true;
      if (minEpoch != null) {
        try {
          final ts = DateTime.tryParse((t['created_at'] ?? '').toString())
              ?.millisecondsSinceEpoch;
          if (ts != null) dateOkay = ts >= minEpoch;
        } catch (_) {}
      }
      return dirOkay && kindOkay && dateOkay;
    }).toList();
  }

  Future<void> _loadPrefs() async {
    try {
      final state = await loadHistoryFilterPreferences(baseUrl: widget.baseUrl);
      _dirFilter = state.dir;
      _kindFilter = state.kind;
      _dateFilter = state.date;
      _fromDate = state.fromDate;
      _toDate = state.toDate;
      final cs = await loadStoredCurrencySymbol(baseUrl: widget.baseUrl);
      if (cs != null && cs.isNotEmpty) _curSym = cs;
      if (!_dirs.contains(_dirFilter)) _dirFilter = 'all';
      if (!_kinds.contains(_kindFilter)) _kindFilter = 'all';
      if (!_dates.contains(_dateFilter)) _dateFilter = 'all';
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _savePrefs() async {
    try {
      await saveHistoryFilterPreferences(
        baseUrl: widget.baseUrl,
        dir: _dirFilter,
        kind: _kindFilter,
        date: _dateFilter,
        fromDate: _fromDate,
        toDate: _toDate,
      );
    } catch (_) {}
  }

  Future<void> _pickDate(BuildContext context, bool from) async {
    final now = DateTime.now();
    final cur = from
        ? (_fromDate ?? now.subtract(const Duration(days: 7)))
        : (_toDate ?? now);
    final picked = await showDatePicker(
        context: context,
        initialDate: cur,
        firstDate: DateTime(now.year - 3),
        lastDate: DateTime(now.year + 1));
    if (picked != null) {
      setState(() {
        if (from)
          _fromDate = picked;
        else
          _toDate = picked;
      });
      await _savePrefs();
      await _load();
    }
  }

  Future<void> _pickDates(BuildContext context) async {
    await _pickDate(context, true);
    await _pickDate(context, false);
  }

  Future<void> _setMonthRange(int offsetMonths) async {
    final now = DateTime.now();
    int year = now.year;
    int month = now.month + offsetMonths;
    while (month < 1) {
      month += 12;
      year -= 1;
    }
    while (month > 12) {
      month -= 12;
      year += 1;
    }
    final from = DateTime(year, month, 1);
    final to =
        DateTime(year, month + 1, 1).subtract(const Duration(seconds: 1));
    setState(() {
      _dateFilter = 'custom';
      _fromDate = from;
      _toDate = to;
    });
    await _savePrefs();
    await _load();
  }

  Widget? _buildPhSummary(List<Map<String, dynamic>> list) {
    try {
      int inC = 0, outC = 0;
      int inCnt = 0, outCnt = 0;
      int savDepC = 0, savWdrC = 0;
      int savDepCnt = 0, savWdrCnt = 0;
      for (final t in list) {
        final amt = (t['amount_cents'] ?? 0) as int;
        final isOut = (t['from_wallet_id'] ?? '') == widget.walletId;
        final kind = (t['kind'] ?? '').toString().toLowerCase();
        final isSavDep = kind.startsWith('savings_deposit');
        final isSavWdr = kind.startsWith('savings_withdraw');
        if (isOut) {
          outC += amt;
          outCnt++;
        } else {
          inC += amt;
          inCnt++;
        }
        if (isSavDep) {
          savDepC += amt;
          savDepCnt++;
        } else if (isSavWdr) {
          savWdrC += amt;
          savWdrCnt++;
        }
      }
      if (list.isEmpty) {
        return null;
      }
      final totalCents = inC + outC;
      final isBillsView = _kindFilter == 'bill';
      final isSavingsView = _kindFilter == 'savings';
      final l = L10n.of(context);
      final theme = Theme.of(context);
      final muted = theme.colorScheme.onSurface.withValues(alpha: .70);
      Widget inner;
      if (isBillsView) {
        inner = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.isArabic ? 'ملخص الفواتير' : 'Bills summary',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              '${fmtCents(outC)} $_curSym',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 2),
            Text(
              l.isArabic
                  ? 'إجمالي المدفوعات في الفترة المحددة.'
                  : 'Total bill payments in the selected window.',
              style: TextStyle(fontSize: 11, color: muted),
            ),
          ],
        );
      } else if (isSavingsView) {
        inner = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.isArabic ? 'ملخص حركات الادخار' : 'Savings movements summary',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              l.isArabic
                  ? 'إلى الادخار: ${fmtCents(savDepC)} $_curSym'
                  : 'Into savings: ${fmtCents(savDepC)} $_curSym',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              l.isArabic
                  ? 'من الادخار: ${fmtCents(savWdrC)} $_curSym'
                  : 'From savings: ${fmtCents(savWdrC)} $_curSym',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              l.isArabic
                  ? 'عدد الحركات: ${savDepCnt + savWdrCnt}'
                  : 'Movements: ${savDepCnt + savWdrCnt}',
              style: TextStyle(fontSize: 11, color: muted),
            ),
          ],
        );
      } else {
        inner = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.isArabic ? 'ملخص الحركات' : 'Transactions summary',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.isArabic ? 'المبلغ المرسل' : 'Sent',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${fmtCents(outC)} $_curSym ($outCnt)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.isArabic ? 'المبلغ المستلم' : 'Received',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${fmtCents(inC)} $_curSym ($inCnt)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l.isArabic
                  ? 'الصافي: ${fmtCents(totalCents)} $_curSym'
                  : 'Net: ${fmtCents(totalCents)} $_curSym',
              style: TextStyle(fontSize: 11, color: muted),
            ),
          ],
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: ShamellPaymentCardSurface(
          tone: ShamellPaymentCardTone.soft,
          accent: Tokens.colorPayments,
          radius: 22,
          padding: const EdgeInsets.all(14),
          child: inner,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Widget _buildTxnTile(Map<String, dynamic> t, String currency, L10n l) {
    final cents = (t['amount_cents'] ?? 0) as int;
    final fromWallet = (t['from_wallet_id'] ?? '').toString();
    final toWallet = (t['to_wallet_id'] ?? '').toString();
    final isOut = fromWallet == widget.walletId;
    final kindRaw = (t['kind'] ?? '').toString();
    final kind = kindRaw.toLowerCase();
    final isSavDep = kind.startsWith('savings_deposit');
    final isSavWdr = kind.startsWith('savings_withdraw');
    final isBill = kind.startsWith('bill');
    final sign = isSavDep ? '-' : (isSavWdr ? '+' : (isOut ? '-' : '+'));
    final who = isOut ? toWallet : fromWallet;
    final amt = fmtCents(cents);
    final createdAt = (t['created_at'] ?? '').toString();
    final reference = (t['reference'] ?? '').toString();
    String subtitleText;
    if (reference.isNotEmpty && who.isNotEmpty) {
      subtitleText = '$createdAt · $who\n$reference';
    } else if (who.isNotEmpty) {
      subtitleText = '$createdAt · $who';
    } else if (reference.isNotEmpty) {
      subtitleText = '$createdAt\n$reference';
    } else {
      subtitleText = createdAt;
    }

    final amountColor = isBill
        ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.90)
        : (sign == '+'
            ? Tokens.colorPayments
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85));

    String mainLabel;
    if (kind.startsWith('transfer')) {
      mainLabel = l.isArabic ? 'تحويل' : 'Transfer';
    } else if (kind.startsWith('topup')) {
      mainLabel = l.isArabic ? 'شحن رصيد' : 'Top‑up';
    } else if (kind.startsWith('cash')) {
      mainLabel = l.isArabic ? 'سحب نقدي' : 'Cash out';
    } else if (kind.startsWith('sonic')) {
      mainLabel = l.isArabic ? 'سونك' : 'Sonic transfer';
    } else if (kind.startsWith('bill')) {
      mainLabel = l.isArabic ? 'دفع فاتورة' : 'Bill paid';
    } else if (kind.startsWith('savings_deposit')) {
      mainLabel = l.isArabic ? 'إيداع ادخار' : 'Savings deposit';
    } else if (kind.startsWith('savings_withdraw')) {
      mainLabel = l.isArabic ? 'سحب ادخار' : 'Savings withdrawal';
    } else {
      mainLabel = l.isArabic ? 'حركة' : 'Transaction';
    }

    final bool isIncoming = sign == '+';
    final Color iconColor =
        isBill ? Theme.of(context).colorScheme.primary : Tokens.colorPayments;
    final Color iconBg = isBill
        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.06)
        : Tokens.colorPayments.withValues(alpha: 0.08);
    final IconData iconData;
    if (isBill) {
      iconData = Icons.receipt_long_outlined;
    } else if (isIncoming) {
      iconData = Icons.call_received_rounded;
    } else {
      iconData = Icons.call_made_rounded;
    }

    return ShamellPaymentListTileCard(
      onTap: () {
        _showTxnDetailSheet(t, currency, l,
            mainLabel: mainLabel,
            sign: sign,
            amountColor: amountColor,
            iconData: iconData,
            iconBg: iconBg);
      },
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      accent:
          isBill ? Theme.of(context).colorScheme.primary : Tokens.colorPayments,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: iconBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(iconData, color: iconColor, size: 20),
      ),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              mainLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '$sign$amt $currency',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: amountColor,
              ),
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          subtitleText,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.70),
          ),
        ),
      ),
    );
  }

  void _showTxnDetailSheet(
    Map<String, dynamic> t,
    String currency,
    L10n l, {
    required String mainLabel,
    required String sign,
    required Color amountColor,
    required IconData iconData,
    required Color iconBg,
  }) {
    final theme = Theme.of(context);
    final cents = (t['amount_cents'] ?? 0) as int;
    final amt = fmtCents(cents);
    final fromWallet = (t['from_wallet_id'] ?? '').toString();
    final toWallet = (t['to_wallet_id'] ?? '').toString();
    final isOut = fromWallet == widget.walletId;
    final peer = isOut ? toWallet : fromWallet;
    final createdAtRaw = (t['created_at'] ?? '').toString();
    final reference = (t['reference'] ?? '').toString();
    final status = (t['status'] ?? '').toString();
    final kindRaw = (t['kind'] ?? '').toString().toLowerCase();
    final bool isBill = kindRaw.startsWith('bill');
    String statusLabel;
    if (status == 'ok') {
      if (isBill) {
        statusLabel = l.isArabic ? 'فاتورة مدفوعة' : 'Bill paid';
      } else {
        statusLabel = l.isArabic ? 'مكتمل' : 'Completed';
      }
    } else if (status == 'pending') {
      if (isBill) {
        statusLabel = l.isArabic ? 'فاتورة قيد الدفع' : 'Bill pending';
      } else {
        statusLabel = l.isArabic ? 'قيد المعالجة' : 'Pending';
      }
    } else if (status == 'failed') {
      if (isBill) {
        statusLabel = l.isArabic ? 'فشل دفع الفاتورة' : 'Bill payment failed';
      } else {
        statusLabel = l.isArabic ? 'فشل' : 'Failed';
      }
    } else {
      statusLabel =
          status.isEmpty ? (l.isArabic ? 'مكتمل' : 'Completed') : status;
    }

    DateTime? created;
    try {
      created = DateTime.tryParse(createdAtRaw);
    } catch (_) {}
    final createdLabel =
        created != null ? '${created.toLocal()}' : createdAtRaw;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            bottom: bottom + 12,
            top: 12,
          ),
          child: GlassPanel(
            padding: const EdgeInsets.all(16),
            radius: 18,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: iconBg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        iconData,
                        color: amountColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            mainLabel,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                statusLabel,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: .70),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    '$sign$amt $currency',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: amountColor,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    () {
                      if (isBill) {
                        if (status == 'ok') {
                          return l.isArabic
                              ? 'تم دفع الفاتورة بنجاح'
                              : 'Bill payment successful';
                        } else if (status == 'pending') {
                          return l.isArabic
                              ? 'دفع الفاتورة قيد التنفيذ'
                              : 'Bill payment in progress';
                        } else if (status == 'failed') {
                          return l.isArabic
                              ? 'فشل دفع الفاتورة'
                              : 'Bill payment failed';
                        }
                      }
                      return isOut
                          ? (l.isArabic ? 'تم الإرسال' : 'Paid')
                          : (l.isArabic ? 'تم الاستلام' : 'Received');
                    }(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .70),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (peer.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Text(
                          isOut
                              ? (l.isArabic ? 'إلى' : 'To')
                              : (l.isArabic ? 'من' : 'From'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .70),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            peer,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.isArabic ? 'الوقت' : 'Time',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .70),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        createdLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                if (reference.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.isArabic ? 'الملاحظة' : 'Note',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .70),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          reference,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(
                        l.isArabic ? 'إغلاق' : 'Close',
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
  }

  int _responsiveColumnCount(
    double maxWidth, {
    required double minItemWidth,
    required double spacing,
    required int maxColumns,
  }) {
    for (var columns = maxColumns; columns > 1; columns--) {
      final requiredWidth =
          (minItemWidth * columns) + (spacing * (columns - 1));
      if (maxWidth >= requiredWidth) {
        return columns;
      }
    }
    return 1;
  }

  Widget _buildHistoryFilterField({
    required double width,
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return ShamellPaymentFilterField(
      width: width,
      label: label,
      value: value,
      options: options,
      onChanged: onChanged,
      accent: Tokens.colorPayments,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pTransfer = OfflineQueue.pending(
      tag: 'payments_transfer',
      baseUrlOverride: widget.baseUrl,
    );
    final pTopup = OfflineQueue.pending(
      tag: 'payments_topup',
      baseUrlOverride: widget.baseUrl,
    );
    final pSonic = OfflineQueue.pending(
      tag: 'payments_sonic',
      baseUrlOverride: widget.baseUrl,
    );
    final pCash = OfflineQueue.pending(
      tag: 'payments_cash',
      baseUrlOverride: widget.baseUrl,
    );
    List<Widget> sections = [];
    Widget section(String title, List pending) {
      if (pending.isEmpty) return const SizedBox.shrink();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w700))),
        ...pending
            .map<Widget>((p) => ListTile(
                leading: const CircleAvatar(child: Text('~')),
                title: const Text('Pending (offline)'),
                subtitle:
                    Text(p.body, maxLines: 2, overflow: TextOverflow.ellipsis)))
            .toList(),
        const Divider(height: 16),
      ]);
    }

    final l = L10n.of(context);
    sections.add(section(l.isArabic ? 'تحويلات' : 'Transfers', pTransfer));
    sections.add(section(l.isArabic ? 'شحنات' : 'Top‑Up', pTopup));
    sections.add(section(l.isArabic ? 'سونك' : 'Sonic', pSonic));
    sections.add(section(l.isArabic ? 'نقداً' : 'Cash', pCash));
    final filtered = _filtered();
    final header = Padding(
      padding: const EdgeInsets.all(12),
      child: ShamellPaymentCardSurface(
        tone: ShamellPaymentCardTone.soft,
        accent: Tokens.colorPayments,
        radius: 24,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 12.0;
                final columns = _responsiveColumnCount(
                  constraints.maxWidth,
                  minItemWidth: 180,
                  spacing: spacing,
                  maxColumns: 3,
                );
                final fieldWidth = columns == 1
                    ? constraints.maxWidth
                    : (constraints.maxWidth - (spacing * (columns - 1))) /
                        columns;
                return Wrap(
                  spacing: spacing,
                  runSpacing: 10,
                  children: [
                    _buildHistoryFilterField(
                      width: fieldWidth,
                      label: l.historyDirLabel,
                      value: _dirFilter,
                      options: _dirs,
                      onChanged: (v) async {
                        if (v == null || v == _dirFilter) return;
                        setState(() => _dirFilter = v);
                        await _savePrefs();
                        await _load();
                      },
                    ),
                    _buildHistoryFilterField(
                      width: fieldWidth,
                      label: l.historyTypeLabel,
                      value: _kindFilter,
                      options: _kinds,
                      onChanged: (v) async {
                        if (v == null || v == _kindFilter) return;
                        setState(() => _kindFilter = v);
                        await _savePrefs();
                        await _load();
                      },
                    ),
                    _buildHistoryFilterField(
                      width: fieldWidth,
                      label: l.historyPeriodLabel,
                      value: _dateFilter,
                      options: _dates,
                      onChanged: (v) async {
                        if (v == null || v == _dateFilter) return;
                        setState(() => _dateFilter = v);
                        if (v == 'custom') {
                          await _pickDates(context);
                          return;
                        }
                        await _savePrefs();
                        await _load();
                      },
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ShamellPaymentPillButton(
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: Text(l.isArabic ? 'الفواتير' : 'Bills'),
                  selected: _kindFilter == 'bill',
                  onPressed: () async {
                    setState(() =>
                        _kindFilter = _kindFilter == 'bill' ? 'all' : 'bill');
                    await _savePrefs();
                    await _load();
                  },
                ),
                ShamellPaymentPillButton(
                  icon: const Icon(Icons.savings_outlined),
                  label: Text(l.isArabic ? 'الادخار' : 'Savings'),
                  selected: _kindFilter == 'savings',
                  onPressed: () async {
                    setState(() => _kindFilter =
                        _kindFilter == 'savings' ? 'all' : 'savings');
                    await _savePrefs();
                    await _load();
                  },
                ),
                ShamellPaymentPillButton(
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(l.isArabic ? 'هذا الشهر' : 'This month'),
                  onPressed: () async {
                    await _setMonthRange(0);
                  },
                ),
                ShamellPaymentPillButton(
                  icon: const Icon(Icons.history_toggle_off_rounded),
                  label: Text(l.isArabic ? 'الشهر السابق' : 'Last month'),
                  onPressed: () async {
                    await _setMonthRange(-1);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
    final customRow = (_dateFilter == 'custom')
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 8.0;
                final columns = _responsiveColumnCount(
                  constraints.maxWidth,
                  minItemWidth: 180,
                  spacing: spacing,
                  maxColumns: 2,
                );
                final buttonWidth = columns == 1
                    ? constraints.maxWidth
                    : (constraints.maxWidth - spacing) / 2;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    SizedBox(
                      width: buttonWidth,
                      child: ShamellPaymentPillButton(
                        onPressed: () async {
                          await _pickDate(context, true);
                        },
                        icon: const Icon(Icons.date_range),
                        label: Text(
                          _fromDate == null
                              ? l.historyFromLabel
                              : _fromDate!
                                  .toLocal()
                                  .toString()
                                  .split(' ')
                                  .first,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: buttonWidth,
                      child: ShamellPaymentPillButton(
                        onPressed: () async {
                          await _pickDate(context, false);
                        },
                        icon: const Icon(Icons.date_range),
                        label: Text(
                          _toDate == null
                              ? l.historyToLabel
                              : _toDate!.toLocal().toString().split(' ').first,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          )
        : const SizedBox.shrink();
    final summary = _buildPhSummary(filtered);
    final cs = _curSym;
    final txnList = Column(children: [
      header,
      customRow,
      if (summary != null) summary,
      ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: filtered.length,
          itemBuilder: (_, i) {
            final t = filtered[i];
            return _buildTxnTile(t, cs, l);
          }),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: loading || _loadingMore || !_hasMore
            ? null
            : () async {
                await _loadMore();
              },
        style: OutlinedButton.styleFrom(
          foregroundColor: Tokens.colorPayments,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          side: BorderSide(
            color: Tokens.colorPayments.withValues(alpha: 0.26),
          ),
        ),
        icon: _loadingMore
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.expand_more),
        label: Text(_loadingMore
            ? (L10n.of(context).isArabic ? 'جارٍ التحميل...' : 'Loading...')
            : (_hasMore
                ? (L10n.of(context).isArabic ? 'تحميل المزيد' : 'Load more')
                : (L10n.of(context).isArabic
                    ? 'لا مزيد من الحركات'
                    : 'No more transactions'))),
      ),
    ]);
    Widget listWidget = loading
        ? ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: 6,
            itemBuilder: (_, i) => SkeletonListTile())
        : ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              ...sections,
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  l.historyPostedTransactions,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: .65),
                      ),
                ),
              ),
              txnList,
            ],
          );
    // Wallet History migrated off the liquid-glass shell (AppBG + a
    // GlassPanel with BackdropFilter blur) onto the same flat surface
    // / hairline-border treatment the rest of the app uses for list
    // views. Two reasons:
    //   1. The blur was visibly stuttering on mid-range Androids when
    //      scrolling long transaction lists.
    //   2. It was the last screen still rendering the legacy look,
    //      which made the Wallet hub feel inconsistent next to the
    //      tweet-style chat bubbles and the flat Discover surfaces.
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.historyTitle),
        actions: [
          IconButton(
            onPressed: _exportCsv,
            icon: const Icon(Icons.ios_share_outlined),
          ),
        ],
        elevation: 0.5,
      ),
      backgroundColor: isDark
          ? theme.colorScheme.surface
          : theme.colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: RefreshIndicator(
            onRefresh: () async {
              await OfflineQueue.flush(baseUrlOverride: widget.baseUrl);
              await _load();
            },
            child: listWidget,
          ),
        ),
      ),
    );
  }
}

Future<Map<String, String>> _hdr(String baseUrl, {bool json = false}) async {
  return shamellSessionHeadersForBaseUrl(baseUrl, json: json);
}
