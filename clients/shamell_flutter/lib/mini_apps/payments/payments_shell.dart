import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import '../../core/safe_set_state.dart';

import 'payments_send.dart';
import 'payments_receive.dart';
import 'payments_scan.dart';
import 'payments_requests.dart';
import 'payments_overview.dart';
import '../../core/l10n.dart';

const Duration _paymentsShellRequestTimeout = Duration(seconds: 15);

class PaymentsPage extends StatelessWidget {
  final String baseUrl;
  final String fromWalletId;
  final String deviceId;
  final bool triggerScanOnOpen;
  final String? initialRecipient;
  final int? initialAmountCents;
  final String? initialSection;

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
  final String? contextLabel;
  const _PaymentsShell({
    required this.baseUrl,
    required this.fromWalletId,
    required this.deviceId,
    this.triggerScanOnOpen = false,
    this.initialRecipient,
    this.initialAmountCents,
    this.initialSection,
    this.contextLabel,
  });
  @override
  State<_PaymentsShell> createState() => _PaymentsShellState();
}

class _PaymentsShellState extends State<_PaymentsShell>
    with SafeSetStateMixin<_PaymentsShell> {
  String myWallet = '';
  Timer? _reqTimer;
  Set<String> _seenReqs = {};
  Map<String, dynamic>? _bannerReq;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final sp = await SharedPreferences.getInstance();
    myWallet = sp.getString('wallet_id') ?? widget.fromWalletId;
    if (mounted) setState(() {});
    _restoreSeenReqs();
    _startReqPolling();
  }

  @override
  void dispose() {
    _reqTimer?.cancel();
    super.dispose();
  }

  void _startReqPolling() {
    _reqTimer?.cancel();
    _reqTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      await _pollIncoming();
    });
    Future.microtask(() async {
      await _pollIncoming();
    });
  }

  Future<void> _restoreSeenReqs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final arr = sp.getStringList('seen_reqs') ?? [];
      _seenReqs = arr.toSet();
    } catch (_) {}
  }

  Future<void> _saveSeenReqs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList('seen_reqs', _seenReqs.toList());
    } catch (_) {}
  }

  Future<Map<String, String>> _hdr() async {
    final headers = <String, String>{};
    try {
      final cookie = await getSessionCookieHeader(widget.baseUrl) ?? '';
      if (cookie.isNotEmpty) headers['cookie'] = cookie;
    } catch (_) {}
    return headers;
  }

  Future<void> _pollIncoming() async {
    try {
      final r = await http
          .get(
              Uri.parse('${widget.baseUrl}/payments/requests?wallet_id=' +
                  Uri.encodeComponent(myWallet) +
                  '&kind=incoming&limit=50'),
              headers: await _hdr())
          .timeout(_paymentsShellRequestTimeout);
      if (r.statusCode != 200) return;
      final arr = (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
      for (final e in arr) {
        final id = (e['id'] ?? '').toString();
        final st = (e['status'] ?? '').toString();
        if (st == 'pending' && !_seenReqs.contains(id)) {
          _seenReqs.add(id);
          await _saveSeenReqs();
          if (mounted) setState(() => _bannerReq = e);
        }
      }
    } catch (_) {}
  }

  Future<void> _acceptReq(String id) async {
    try {
      await http
          .post(
              Uri.parse('${widget.baseUrl}/payments/requests/' +
                  Uri.encodeComponent(id) +
                  '/accept'),
              headers: await _hdr())
          .timeout(_paymentsShellRequestTimeout);
    } catch (_) {}
    if (mounted) setState(() => _bannerReq = null);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final isAr = l.isArabic;
    final theme = Theme.of(context);
    final scaffoldBg = theme.scaffoldBackgroundColor;
    final baseTitle = isAr ? 'Shamell Pay' : 'Shamell Pay';
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
    return DefaultTabController(
      length: 4,
      initialIndex: initialIndex,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            titleText,
          ),
          bottom: TabBar(
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
          ),
          backgroundColor: theme.appBarTheme.backgroundColor ?? scaffoldBg,
        ),
        backgroundColor: scaffoldBg,
        body: Stack(
          children: [
            TabBarView(children: [
              PaymentOverviewTab(
                baseUrl: widget.baseUrl,
                walletId: myWallet,
                deviceId: widget.deviceId,
                initialSection: widget.initialSection,
              ),
              PaymentScanTab(
                  baseUrl: widget.baseUrl,
                  fromWalletId: myWallet,
                  autoScan: widget.triggerScanOnOpen),
              PaymentSendTab(
                baseUrl: widget.baseUrl,
                fromWalletId: myWallet,
                deviceId: widget.deviceId,
                initialRecipient: widget.initialRecipient,
                initialAmountCents: widget.initialAmountCents,
                contextLabel: widget.contextLabel,
              ),
              PaymentReceiveTab(
                  baseUrl: widget.baseUrl, fromWalletId: myWallet),
            ]),
            if (_bannerReq != null)
              SafeArea(
                child: IncomingRequestBanner(
                  req: _bannerReq!,
                  onAccept: () => _acceptReq(
                    (_bannerReq!['id'] ?? '').toString(),
                  ),
                  onDismiss: () => setState(() => _bannerReq = null),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
