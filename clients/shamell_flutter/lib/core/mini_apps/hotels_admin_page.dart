import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n.dart';
import '../superapp_api.dart';
import 'hotels_operator_login_page.dart';
import 'hotels_operator_session.dart';

/// Admin console for hotel partners.
///
/// Talks to `shamell_hotels_service` (Rust). Shows live bookings and
/// room-service orders for a given hotel and lets staff update status.
/// Polls every 12 seconds so new bookings appear without a manual
/// refresh — fine for a demo; production would replace this with a
/// WebSocket / SSE channel through the BFF.
class HotelAdminConsolePage extends StatefulWidget {
  final SuperappAPI api;
  final String hotelId;
  final String hotelDisplayName;

  const HotelAdminConsolePage({
    super.key,
    required this.api,
    this.hotelId = 'venezia',
    this.hotelDisplayName = 'VENEZIA Hotel',
  });

  @override
  State<HotelAdminConsolePage> createState() => _HotelAdminConsolePageState();
}

class _HotelAdminConsolePageState extends State<HotelAdminConsolePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Timer? _poll;
  // Phase 9 — SSE live-event subscription. The server pushes a
  // small `StreamFrame` per emit_event; we use it to refresh only
  // the affected tab (bookings vs orders) instead of polling all
  // three queries every 12 s. Polling stays as a 60 s safety net
  // for proxies / mobile-background-pauses that break long-lived
  // streams.
  StreamSubscription<List<int>>? _sseSub;
  http.Client? _sseClient;
  String _sseBuffer = '';
  bool _sseReconnectScheduled = false;

  final HotelsOperatorSessionStore _sessionStore = HotelsOperatorSessionStore();
  HotelsOperatorSession? _session;
  bool _bootstrapping = true;

  List<Map<String, dynamic>> _bookings = [];
  List<Map<String, dynamic>> _orders = [];
  bool _loadingBookings = true;
  bool _loadingOrders = true;
  String? _bookingsError;
  String? _ordersError;

  // Phase 4: Settlement summary (KPI tile on top of bookings tab).
  Map<String, dynamic>? _settlement;
  String _settlementPeriod = 'month';
  bool _loadingSettlement = false;

  static const _bookingStatuses = <String>[
    'pending',
    'confirmed',
    'checked_in',
    'checked_out',
    'cancelled',
  ];
  static const _orderStatuses = <String>[
    'received',
    'preparing',
    'en_route',
    'delivered',
    'cancelled',
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final cached = await _sessionStore.load();
    if (!mounted) return;
    if (cached != null && cached.canAdminister(widget.hotelId)) {
      setState(() {
        _session = cached;
        _bootstrapping = false;
      });
      _refreshAll();
      unawaited(_startSseSubscription());
      _poll =
          Timer.periodic(const Duration(seconds: 12), (_) => _refreshAll());
      return;
    }
    setState(() {
      _bootstrapping = false;
    });
    await _promptLogin();
  }

  Future<void> _promptLogin() async {
    final session = await Navigator.of(context).push<HotelsOperatorSession?>(
      MaterialPageRoute(
        builder: (_) => HotelsOperatorLoginPage(
          api: widget.api,
          store: _sessionStore,
          initialHotelHint: widget.hotelDisplayName,
        ),
      ),
    );
    if (!mounted) return;
    if (session == null) {
      // User backed out — close the admin console too.
      Navigator.of(context).maybePop();
      return;
    }
    if (!session.canAdminister(widget.hotelId)) {
      _showSnack(L10n.of(context).isArabic
          ? 'لا توجد صلاحية لهذا الفندق'
          : 'No grant for this hotel');
      await _sessionStore.clear();
      if (!mounted) return;
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _session = session;
    });
    _refreshAll();
    unawaited(_startSseSubscription());
    _poll ??=
        Timer.periodic(const Duration(seconds: 12), (_) => _refreshAll());
  }

  Future<void> _signOut() async {
    _poll?.cancel();
    _stopSseSubscription();
    _poll = null;
    await _sessionStore.clear();
    if (!mounted) return;
    setState(() {
      _session = null;
      _bookings = [];
      _orders = [];
    });
    await _promptLogin();
  }

  Map<String, String> _authHeaders([Map<String, String>? extra]) {
    final session = _session;
    final h = <String, String>{
      if (extra != null) ...extra,
    };
    if (session != null) {
      h['authorization'] = session.authorizationHeader();
    }
    return h;
  }

  void _handleAuthFailure() {
    // Token expired or revoked — wipe the local session and bounce
    // back to the login page. Avoid a feedback loop by guarding with
    // mounted + a one-shot session-null check.
    if (_session == null) return;
    unawaited(_signOut());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _stopSseSubscription();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() {
    return Future.wait([_loadBookings(), _loadOrders(), _loadSettlement()]);
  }

  /// Open the long-lived SSE stream and route incoming frames to
  /// the right tab. Falls back to no-op (polling-only) on any
  /// error — the 12 s `_poll` Timer keeps the UI alive regardless.
  Future<void> _startSseSubscription() async {
    if (_session == null) return;
    if (_sseSub != null) return;
    final uri = _u('/events/stream');
    _sseClient = http.Client();
    _sseBuffer = '';
    try {
      final req = http.Request('GET', uri)
        ..headers.addAll({
          'Accept': 'text/event-stream',
          'Cache-Control': 'no-cache',
          'Authorization': 'Bearer ${_session!.token}',
        });
      // ignore: discarded_futures
      final resp = await _sseClient!.send(req).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('sse connect timeout'),
      );
      if (resp.statusCode != 200) {
        _stopSseSubscription();
        _scheduleSseReconnect();
        return;
      }
      _sseSub = resp.stream.listen(
        _onSseChunk,
        onError: (_) {
          _stopSseSubscription();
          _scheduleSseReconnect();
        },
        onDone: () {
          _stopSseSubscription();
          _scheduleSseReconnect();
        },
        cancelOnError: true,
      );
    } catch (_) {
      _stopSseSubscription();
      _scheduleSseReconnect();
    }
  }

  void _onSseChunk(List<int> chunk) {
    _sseBuffer += utf8.decode(chunk, allowMalformed: true);
    // SSE frames are separated by a blank line — '\n\n' (or
    // '\r\n\r\n' depending on the proxy). Pop one at a time.
    while (true) {
      final sep = _sseBuffer.indexOf('\n\n');
      if (sep < 0) break;
      final frame = _sseBuffer.substring(0, sep);
      _sseBuffer = _sseBuffer.substring(sep + 2);
      _handleSseFrame(frame);
    }
  }

  void _handleSseFrame(String frame) {
    String? dataLine;
    for (final raw in frame.split('\n')) {
      final line = raw.trimRight();
      if (line.startsWith('data:')) {
        dataLine = line.substring(5).trim();
        break;
      }
    }
    if (dataLine == null || dataLine.isEmpty) return;
    try {
      final parsed = jsonDecode(dataLine);
      if (parsed is! Map<String, dynamic>) return;
      final targetKind = parsed['target_kind']?.toString() ?? '';
      // Smart-refresh: only reload the tab whose row changed.
      if (targetKind == 'booking') {
        unawaited(_loadBookings());
        unawaited(_loadSettlement());
      } else if (targetKind == 'order') {
        unawaited(_loadOrders());
        unawaited(_loadSettlement());
      }
    } catch (_) {
      // Malformed frame; ignore and keep streaming.
    }
  }

  void _stopSseSubscription() {
    try {
      _sseSub?.cancel();
    } catch (_) {}
    _sseSub = null;
    try {
      _sseClient?.close();
    } catch (_) {}
    _sseClient = null;
    _sseBuffer = '';
  }

  void _scheduleSseReconnect() {
    if (_sseReconnectScheduled) return;
    _sseReconnectScheduled = true;
    Future.delayed(const Duration(seconds: 6), () {
      _sseReconnectScheduled = false;
      if (!mounted) return;
      if (_session == null) return;
      // ignore: discarded_futures
      _startSseSubscription();
    });
  }

  Future<void> _loadSettlement() async {
    if (_session == null) return;
    if (mounted) setState(() => _loadingSettlement = true);
    final factory = widget.api.httpClientFactory;
    final client = factory != null ? factory() : http.Client();
    try {
      final res = await client.get(
        _u('/settlement?period=$_settlementPeriod'),
        headers: _authHeaders(),
      );
      if (res.statusCode == 401) {
        _handleAuthFailure();
        return;
      }
      if (res.statusCode < 200 || res.statusCode >= 300) return;
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic> && mounted) {
        setState(() => _settlement = decoded);
      }
    } catch (_) {
      // Silent: tile just shows "—" on transient errors.
    } finally {
      if (factory == null) client.close();
      if (mounted) setState(() => _loadingSettlement = false);
    }
  }

  /// Fetch the timeline for a booking/order. `kind` is 'bookings' or
  /// 'orders' (matching the URL path); `reference` is the human ref
  /// like `SHM-DEMO01`.
  Future<List<Map<String, dynamic>>?> _loadEvents(
      String kind, String reference) async {
    if (_session == null) return null;
    final factory = widget.api.httpClientFactory;
    final client = factory != null ? factory() : http.Client();
    try {
      final res = await client.get(
        _u('/$kind/by-ref/$reference/events'),
        headers: _authHeaders(),
      );
      if (res.statusCode == 401) {
        _handleAuthFailure();
        return null;
      }
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);
      }
      return const <Map<String, dynamic>>[];
    } catch (_) {
      return null;
    } finally {
      if (factory == null) client.close();
    }
  }

  Uri _u(String path) {
    final base = widget.api.baseUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/v1/hotels/${widget.hotelId}$path');
  }

  http.Client _http() {
    final factory = widget.api.httpClientFactory;
    return factory != null ? factory() : http.Client();
  }

  Future<void> _loadBookings() async {
    final client = _http();
    try {
      final res = await client.get(_u('/bookings?limit=100'), headers: _authHeaders());
      if (res.statusCode == 401) {
        _handleAuthFailure();
        return;
      }
      if (!mounted) return;
      if (res.statusCode != 200) {
        setState(() {
          _bookingsError = 'HTTP ${res.statusCode}';
          _loadingBookings = false;
        });
        return;
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! List) {
        setState(() {
          _bookingsError = 'unexpected response shape';
          _loadingBookings = false;
        });
        return;
      }
      setState(() {
        _bookings = decoded.cast<Map<String, dynamic>>();
        _bookingsError = null;
        _loadingBookings = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bookingsError = e.toString();
        _loadingBookings = false;
      });
    } finally {
      client.close();
    }
  }

  Future<void> _loadOrders() async {
    final client = _http();
    try {
      final res = await client.get(_u('/orders?limit=100'), headers: _authHeaders());
      if (res.statusCode == 401) {
        _handleAuthFailure();
        return;
      }
      if (!mounted) return;
      if (res.statusCode != 200) {
        setState(() {
          _ordersError = 'HTTP ${res.statusCode}';
          _loadingOrders = false;
        });
        return;
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! List) {
        setState(() {
          _ordersError = 'unexpected response shape';
          _loadingOrders = false;
        });
        return;
      }
      setState(() {
        _orders = decoded.cast<Map<String, dynamic>>();
        _ordersError = null;
        _loadingOrders = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ordersError = e.toString();
        _loadingOrders = false;
      });
    } finally {
      client.close();
    }
  }

  Future<void> _updateBookingStatus(String bookingId, String newStatus) async {
    final client = _http();
    try {
      final res = await client.patch(
        _u('/bookings/$bookingId/status'),
        headers: _authHeaders({'content-type': 'application/json'}),
        body: jsonEncode({'status': newStatus}),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        await _loadBookings();
      } else if (res.statusCode == 401) {
        _handleAuthFailure();
      } else {
        _showSnack('Update failed: HTTP ${res.statusCode}');
      }
    } catch (e) {
      _showSnack('Update failed: $e');
    } finally {
      client.close();
    }
  }

  Future<void> _updateOrderStatus(String orderId, String newStatus) async {
    final client = _http();
    try {
      final res = await client.patch(
        _u('/orders/$orderId/status'),
        headers: _authHeaders({'content-type': 'application/json'}),
        body: jsonEncode({'status': newStatus}),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        await _loadOrders();
      } else if (res.statusCode == 401) {
        _handleAuthFailure();
      } else {
        _showSnack('Update failed: HTTP ${res.statusCode}');
      }
    } catch (e) {
      _showSnack('Update failed: $e');
    } finally {
      client.close();
    }
  }

  /// Posts a manual payment-status update to the booking/order webhook.
  /// Used by the operator's "Mark as paid / Refunded" menu when the
  /// gast paid out-of-band (cash, bank transfer) and Shamell Pay isn't
  /// going to fire the webhook automatically. `kind` is `'bookings'` or
  /// `'orders'`; `paymentStatus` is `'paid'` or `'refunded'`.
  Future<void> _postPaymentWebhook({
    required String kind,
    required String reference,
    required String paymentStatus,
    String method = 'cash',
  }) async {
    if (reference.isEmpty) return;
    final client = _http();
    try {
      final providerRef = 'manual-${DateTime.now().toUtc().millisecondsSinceEpoch}';
      final res = await client.post(
        _u('/$kind/by-ref/${Uri.encodeComponent(reference)}/payment'),
        headers: _authHeaders({'content-type': 'application/json'}),
        body: jsonEncode({
          'status': paymentStatus,
          'provider': 'manual',
          'provider_ref': providerRef,
          'method': method,
        }),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        _showSnack('$reference → $paymentStatus');
        if (kind == 'bookings') {
          await _loadBookings();
        } else {
          await _loadOrders();
        }
      } else if (res.statusCode == 401) {
        _handleAuthFailure();
      } else {
        _showSnack('Payment update failed: HTTP ${res.statusCode}');
      }
    } catch (e) {
      _showSnack('Payment update failed: $e');
    } finally {
      client.close();
    }
  }

  /// Fetch a booking's invoice PDF (auth header attached) and surface
  /// it through the platform share-sheet. On web the share-sheet
  /// shows up as a download; on mobile the user can save to Files,
  /// mail it, AirDrop, etc. Pure read endpoint, no state mutation.
  Future<void> _downloadInvoice(String reference) async {
    if (reference.isEmpty) return;
    final client = _http();
    try {
      final url = _u('/bookings/by-ref/${Uri.encodeComponent(reference)}/invoice.pdf');
      final res = await client.get(url, headers: _authHeaders());
      if (!mounted) return;
      if (res.statusCode == 401) {
        _handleAuthFailure();
        return;
      }
      if (res.statusCode != 200) {
        _showSnack('Invoice fetch failed: HTTP ${res.statusCode}');
        return;
      }
      final filename = 'syrchat-invoice-$reference.pdf';
      if (kIsWeb) {
        // No filesystem on web — share_plus uses Web Share API or
        // falls back to a download anchor via XFile.fromData.
        await Share.shareXFiles(
          [
            XFile.fromData(
              res.bodyBytes,
              mimeType: 'application/pdf',
              name: filename,
            ),
          ],
          subject: 'SyrChat invoice $reference',
        );
      } else {
        final dir = await getTemporaryDirectory();
        final sep = dir.path.endsWith('/') ? '' : '/';
        final path = '${dir.path}$sep$filename';
        final file = File(path);
        await file.writeAsBytes(res.bodyBytes, flush: true);
        await Share.shareXFiles(
          [XFile(path, mimeType: 'application/pdf', name: filename)],
          subject: 'SyrChat invoice $reference',
        );
      }
      if (!mounted) return;
      _showSnack('Invoice $reference ready');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Invoice fetch failed: $e');
    } finally {
      client.close();
    }
  }

  void _showSnack(String msg) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    if (_bootstrapping || _session == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7F3EC),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFFC9A96E)),
        ),
      );
    }
    final session = _session!;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F3EC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E3A53),
        foregroundColor: Colors.white,
        title: Text(
          l.isArabic
              ? 'إدارة ${widget.hotelDisplayName}'
              : '${widget.hotelDisplayName} — Admin',
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: const Color(0xFFC9A96E),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: l.isArabic ? 'الحجوزات' : 'Bookings'),
            Tab(text: l.isArabic ? 'الطلبات' : 'Orders'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshAll,
            tooltip: l.isArabic ? 'تحديث' : 'Refresh',
          ),
          PopupMenuButton<String>(
            tooltip: session.displayName,
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: (v) {
              if (v == 'signout') _signOut();
            },
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      session.displayName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0E3A53)),
                    ),
                    Text(
                      session.loginId,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF6B4B3A)),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'signout',
                child: Row(children: [
                  const Icon(Icons.logout, size: 18, color: Color(0xFFB91C1C)),
                  const SizedBox(width: 8),
                  Text(l.isArabic ? 'تسجيل الخروج' : 'Sign out'),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildBookingsTab(l),
          _buildOrdersTab(l),
        ],
      ),
    );
  }

  Widget _buildBookingsTab(L10n l) {
    if (_loadingBookings) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFC9A96E)));
    }
    if (_bookingsError != null) {
      return _errorView(l, _bookingsError!, _loadBookings);
    }
    final settlementTile = _buildSettlementTile(l);
    if (_bookings.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            settlementTile,
            const SizedBox(height: 16),
            _emptyView(l, l.isArabic ? 'لا توجد حجوزات' : 'No bookings yet'),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _bookings.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          if (i == 0) return settlementTile;
          return _bookingCard(_bookings[i - 1], l);
        },
      ),
    );
  }

  Widget _buildSettlementTile(L10n l) {
    final s = _settlement;
    final currency = (s?['currency'] as String?) ?? 'EUR';
    final gross = (s?['gross_cents'] as num?)?.toInt() ?? 0;
    final refund = (s?['refund_cents'] as num?)?.toInt() ?? 0;
    final net = (s?['net_cents'] as num?)?.toInt() ?? 0;
    final bookings = (s?['booking_count'] as num?)?.toInt() ?? 0;
    final orders = (s?['order_count'] as num?)?.toInt() ?? 0;

    String fmt(int cents) {
      final whole = (cents.abs() / 100).floor();
      final frac = (cents.abs() % 100).toString().padLeft(2, '0');
      final sign = cents < 0 ? '-' : '';
      return '$sign$whole.$frac $currency';
    }

    Widget kpi(String label, String value, {Color? valueColor}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6B4B3A),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? const Color(0xFF3B2214),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      );
    }

    Widget periodChip(String value, String labelEn, String labelAr) {
      final selected = _settlementPeriod == value;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(l.isArabic ? labelAr : labelEn),
          selected: selected,
          onSelected: (_) {
            if (_settlementPeriod == value) return;
            setState(() => _settlementPeriod = value);
            _loadSettlement();
          },
          selectedColor: const Color(0xFF9A3412),
          labelStyle: TextStyle(
            color: selected ? Colors.white : const Color(0xFF3B2214),
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
          backgroundColor: const Color(0xFFFDEAD7),
          side: const BorderSide(color: Color(0xFFE8D7C5)),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFBF7), Color(0xFFF3E4D7)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8D7C5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.payments_outlined,
                  size: 18, color: Color(0xFF9A3412)),
              const SizedBox(width: 6),
              Text(
                l.isArabic ? 'التسوية' : 'Settlement',
                style: const TextStyle(
                  color: Color(0xFF9A3412),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              if (_loadingSettlement)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: Color(0xFF9A3412),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                periodChip('week', 'Week', 'الأسبوع'),
                periodChip('month', 'Month', 'الشهر'),
                periodChip('all_time', 'All', 'الكل'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: kpi(l.isArabic ? 'إجمالي' : 'GROSS', fmt(gross))),
              Expanded(
                child: kpi(
                  l.isArabic ? 'مرتجعات' : 'REFUND',
                  refund == 0 ? fmt(0) : '−${fmt(refund)}',
                  valueColor:
                      refund == 0 ? null : const Color(0xFFB91C1C),
                ),
              ),
              Expanded(
                child: kpi(
                  l.isArabic ? 'صافي' : 'NET',
                  fmt(net),
                  valueColor: const Color(0xFF9A3412),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$bookings ${l.isArabic ? "حجز" : "bookings"} · '
            '$orders ${l.isArabic ? "طلب" : "orders"}',
            style: const TextStyle(color: Color(0xFF6B4B3A), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersTab(L10n l) {
    if (_loadingOrders) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFC9A96E)));
    }
    if (_ordersError != null) {
      return _errorView(l, _ordersError!, _loadOrders);
    }
    if (_orders.isEmpty) {
      return _emptyView(l, l.isArabic ? 'لا توجد طلبات' : 'No orders yet');
    }
    return RefreshIndicator(
      onRefresh: _loadOrders,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _orderCard(_orders[i], l),
      ),
    );
  }

  Widget _bookingCard(Map<String, dynamic> b, L10n l) {
    final ref = b['reference']?.toString() ?? '—';
    final room = b['room_id']?.toString() ?? '—';
    final guests = b['guests']?.toString() ?? '?';
    final amount = (b['amount_cents'] as num?)?.toDouble() ?? 0;
    final currency = b['currency']?.toString() ?? 'EUR';
    final ci = b['check_in']?.toString() ?? '';
    final co = b['check_out']?.toString() ?? '';
    final status = b['status']?.toString() ?? 'pending';
    final id = b['id']?.toString() ?? '';
    final paymentStatus = b['payment_status']?.toString() ?? 'unpaid';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openTimeline('bookings', ref, l),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ref,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0E3A53),
                      ),
                    ),
                  ),
                  _statusChip(status),
                  const SizedBox(width: 4),
                  _statusMenu(
                    current: status,
                    options: _bookingStatuses,
                    onSelected: (s) => _updateBookingStatus(id, s),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${l.isArabic ? "الغرفة" : "Room"}: $room  ·  $guests ${l.isArabic ? "ضيف" : "guests"}',
                style: const TextStyle(color: Color(0xFF4B5563), fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                '$ci → $co',
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12.5),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _formatAmount(amount, currency, l),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0E3A53),
                        fontSize: 15,
                      ),
                    ),
                  ),
                  _paymentBadge(b, l),
                  _paymentMenu(
                    kind: 'bookings',
                    reference: ref,
                    paymentStatus: paymentStatus,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openTimeline(String kind, String reference, L10n l) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollCtl) {
            return Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFFBF7), Color(0xFFF3E4D7)],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: FutureBuilder<List<Map<String, dynamic>>?>(
                future: _loadEvents(kind, reference),
                builder: (_, snap) {
                  final events = snap.data;
                  return Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8D7C5),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                        child: Row(
                          children: [
                            const Icon(Icons.timeline,
                                color: Color(0xFF9A3412), size: 18),
                            const SizedBox(width: 6),
                            Text(
                              l.isArabic ? 'سجل النشاط' : 'Activity timeline',
                              style: const TextStyle(
                                color: Color(0xFF9A3412),
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              reference,
                              style: const TextStyle(
                                color: Color(0xFF3B2214),
                                fontWeight: FontWeight.w800,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: snap.connectionState == ConnectionState.waiting
                            ? const Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFF9A3412),
                                ),
                              )
                            : (events == null || events.isEmpty)
                                ? Center(
                                    child: Text(
                                      l.isArabic
                                          ? 'لا يوجد نشاط بعد'
                                          : 'No activity yet',
                                      style: const TextStyle(
                                          color: Color(0xFF6B4B3A)),
                                    ),
                                  )
                                : ListView.builder(
                                    controller: scrollCtl,
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 4, 16, 24),
                                    itemCount: events.length,
                                    itemBuilder: (_, i) =>
                                        _eventRow(events[i], l, i == 0,
                                            i == events.length - 1),
                                  ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _eventRow(
      Map<String, dynamic> e, L10n l, bool isFirst, bool isLast) {
    final kind = e['event_kind']?.toString() ?? '';
    final actor = e['actor_label']?.toString() ?? '';
    final actorKind = e['actor_kind']?.toString() ?? '';
    final summary = e['summary']?.toString() ?? kind;
    final createdAt = e['created_at']?.toString() ?? '';
    final ts = createdAt.replaceFirst('T', ' ').split('.').first;

    final iconAndColor = switch (kind) {
      'created' => (Icons.fiber_new_outlined, const Color(0xFF9A3412)),
      'payment_received' => (Icons.check_circle, const Color(0xFF065F46)),
      'payment_refunded' => (Icons.replay, const Color(0xFFB91C1C)),
      'payment_failed' => (Icons.error_outline, const Color(0xFFB91C1C)),
      'status_changed' => (Icons.swap_horiz, const Color(0xFF9A3412)),
      'checked_in' => (Icons.login, const Color(0xFF065F46)),
      'checked_out' => (Icons.logout, const Color(0xFF6B4B3A)),
      'cancelled' => (Icons.cancel_outlined, const Color(0xFFB91C1C)),
      _ => (Icons.circle_outlined, const Color(0xFF6B4B3A)),
    };
    final (icon, color) = iconAndColor;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Spine + dot
          SizedBox(
            width: 32,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                if (!isFirst)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    child: Container(width: 2, color: const Color(0xFFE8D7C5)),
                  )
                else
                  const SizedBox.shrink(),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 2),
                    ),
                    child: Icon(icon, size: 13, color: color),
                  ),
                ),
                if (!isLast)
                  Positioned(
                    top: 30,
                    bottom: 0,
                    child: Container(width: 2, color: const Color(0xFFE8D7C5)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    summary,
                    style: const TextStyle(
                      color: Color(0xFF3B2214),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (ts.isNotEmpty) ts,
                      if (actorKind.isNotEmpty) actorKind,
                      if (actor.isNotEmpty) actor,
                    ].join(' · '),
                    style: const TextStyle(
                      color: Color(0xFF6B4B3A),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _orderCard(Map<String, dynamic> o, L10n l) {
    final ref = o['reference']?.toString() ?? '—';
    final amount = (o['amount_cents'] as num?)?.toDouble() ?? 0;
    final currency = o['currency']?.toString() ?? 'EUR';
    final status = o['status']?.toString() ?? 'received';
    final id = o['id']?.toString() ?? '';
    final room = o['room_number']?.toString();
    final items = (o['items'] as List?) ?? const [];
    final paymentStatus = o['payment_status']?.toString() ?? 'unpaid';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    ref,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0E3A53),
                    ),
                  ),
                ),
                _statusChip(status),
                const SizedBox(width: 4),
                _statusMenu(
                  current: status,
                  options: _orderStatuses,
                  onSelected: (s) => _updateOrderStatus(id, s),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...items.take(4).map((it) {
              if (it is! Map) return const SizedBox.shrink();
              final name = it['name']?.toString() ?? '?';
              final qty = it['qty']?.toString() ?? '1';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  '· $qty × $name',
                  style: const TextStyle(color: Color(0xFF4B5563), fontSize: 13),
                ),
              );
            }),
            if (items.length > 4)
              Text(
                '+ ${items.length - 4} ${l.isArabic ? "أخرى" : "more"}',
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    room != null && room.isNotEmpty
                        ? '${l.isArabic ? "الغرفة" : "Room"} $room'
                        : (l.isArabic ? 'بدون رقم غرفة' : 'No room number'),
                    style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12.5),
                  ),
                ),
                Text(
                  _formatAmount(amount, currency, l),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0E3A53),
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _paymentBadge(o, l),
                const Spacer(),
                _paymentMenu(
                  kind: 'orders',
                  reference: ref,
                  paymentStatus: paymentStatus,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Visual badge for the payment lifecycle so the operator sees
  /// "💳 Paid · 189 EUR via SyrChat Pay" without opening a detail
  /// screen. Falls back gracefully for legacy rows that pre-date the
  /// 0002 migration.
  Widget _paymentBadge(Map<String, dynamic> row, L10n l) {
    final status = row['payment_status']?.toString() ?? 'unpaid';
    final provider = row['payment_provider']?.toString();
    final method = row['payment_method']?.toString();
    final color = _paymentColor(status);
    final icon = _paymentIcon(status);

    final label = StringBuffer(_paymentLabel(status, l));
    if (status == 'paid' && (provider != null || method != null)) {
      label.write(' · ');
      if (method != null) label.write(method);
      if (provider != null) {
        if (method != null) label.write(' (');
        label.write(provider);
        if (method != null) label.write(')');
      }
    }

    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label.toString(),
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// "Mark paid (cash) / Mark refunded" menu — for operators who need
  /// to record an out-of-band settlement (cash on arrival, manual bank
  /// transfer). Idempotent through a timestamp-based provider_ref.
  Widget _paymentMenu({
    required String kind,
    required String reference,
    required String paymentStatus,
  }) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.payments_outlined, size: 18, color: Color(0xFF6B7280)),
      tooltip: 'Payment',
      onSelected: (action) {
        switch (action) {
          case 'mark_paid_cash':
            _postPaymentWebhook(
              kind: kind,
              reference: reference,
              paymentStatus: 'paid',
              method: 'cash',
            );
            break;
          case 'mark_paid_card':
            _postPaymentWebhook(
              kind: kind,
              reference: reference,
              paymentStatus: 'paid',
              method: 'card',
            );
            break;
          case 'mark_paid_bank':
            _postPaymentWebhook(
              kind: kind,
              reference: reference,
              paymentStatus: 'paid',
              method: 'bank_transfer',
            );
            break;
          case 'mark_refunded':
            _postPaymentWebhook(
              kind: kind,
              reference: reference,
              paymentStatus: 'refunded',
              method: 'wallet',
            );
            break;
          case 'download_invoice':
            _downloadInvoice(reference);
            break;
        }
      },
      itemBuilder: (_) => <PopupMenuEntry<String>>[
        if (paymentStatus != 'paid') ...const [
          PopupMenuItem(value: 'mark_paid_cash', child: Text('Mark paid · cash')),
          PopupMenuItem(value: 'mark_paid_card', child: Text('Mark paid · card')),
          PopupMenuItem(value: 'mark_paid_bank', child: Text('Mark paid · bank transfer')),
        ],
        if (paymentStatus == 'paid')
          const PopupMenuItem(value: 'mark_refunded', child: Text('Mark refunded')),
        if (kind == 'bookings' && paymentStatus == 'paid') ...const [
          PopupMenuDivider(),
          PopupMenuItem(
            value: 'download_invoice',
            child: Row(
              children: [
                Icon(Icons.picture_as_pdf_outlined, size: 18, color: Color(0xFF9A3412)),
                SizedBox(width: 8),
                Text('Download invoice (PDF)'),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _paymentLabel(String status, L10n l) {
    switch (status) {
      case 'paid':
        return l.isArabic ? 'مدفوع' : 'Paid';
      case 'refunded':
        return l.isArabic ? 'مُسترد' : 'Refunded';
      case 'failed':
        return l.isArabic ? 'فشل' : 'Failed';
      default:
        return l.isArabic ? 'غير مدفوع' : 'Unpaid';
    }
  }

  Color _paymentColor(String status) {
    switch (status) {
      case 'paid':
        return const Color(0xFF15803D); // green-700
      case 'refunded':
        return const Color(0xFFB45309); // amber-700
      case 'failed':
        return const Color(0xFFB91C1C); // red-700
      default:
        return const Color(0xFF6B7280); // slate-500 (unpaid)
    }
  }

  IconData _paymentIcon(String status) {
    switch (status) {
      case 'paid':
        return Icons.verified_outlined;
      case 'refunded':
        return Icons.undo_outlined;
      case 'failed':
        return Icons.error_outline;
      default:
        return Icons.schedule_outlined;
    }
  }

  Widget _statusChip(String status) {
    final c = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status,
        style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w700),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'confirmed':
      case 'delivered':
        return const Color(0xFF16A34A);
      case 'checked_in':
      case 'en_route':
      case 'preparing':
        return const Color(0xFFC9A96E);
      case 'cancelled':
        return const Color(0xFFDC2626);
      case 'checked_out':
        return const Color(0xFF6B7280);
      default:
        return const Color(0xFF0E3A53);
    }
  }

  Widget _statusMenu({
    required String current,
    required List<String> options,
    required void Function(String) onSelected,
  }) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Color(0xFF6B7280)),
      onSelected: onSelected,
      itemBuilder: (_) => options
          .where((o) => o != current)
          .map((o) => PopupMenuItem<String>(value: o, child: Text(o)))
          .toList(),
    );
  }

  Widget _emptyView(L10n l, String text) {
    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        children: [
          const SizedBox(height: 80),
          const Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFC9A96E)),
          const SizedBox(height: 12),
          Center(
            child: Text(
              text,
              style: const TextStyle(color: Color(0xFF4B5563), fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorView(L10n l, String error, Future<void> Function() retry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 56, color: Color(0xFFDC2626)),
            const SizedBox(height: 12),
            Text(
              l.isArabic ? 'تعذّر الاتصال بالخادم' : 'Could not reach backend',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF0E3A53),
              ),
            ),
            const SizedBox(height: 6),
            SelectableText(
              error,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF6B7280)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: retry,
              child: Text(l.isArabic ? 'إعادة المحاولة' : 'Retry'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatAmount(double cents, String currency, L10n l) {
    // Backend stores cents (i64). Display as major-units. For SAR/EUR
    // the demo data was already in major units though — heuristic:
    // if amount looks too round (multiple of 100 and < 100_000) it was
    // likely stored as a major-unit number. Treat as cents otherwise.
    final asMajor = cents > 100000 ? cents / 100.0 : cents;
    final locale = l.isArabic ? 'ar' : 'en';
    return '${_currencySymbol(currency)} ${asMajor.toStringAsFixed(0)}'
        '${locale == "ar" ? "" : ""}';
  }

  String _currencySymbol(String c) {
    switch (c) {
      case 'EUR':
        return '€';
      case 'USD':
        return r'$';
      case 'SAR':
        return 'ر.س';
      case 'AED':
        return 'د.إ';
      default:
        return c;
    }
  }
}
