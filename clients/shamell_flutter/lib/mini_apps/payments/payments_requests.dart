import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/glass.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/l10n.dart';
import '../../core/app_shell_widgets.dart' show AppBG; // reuse bg only
import 'payments_send.dart' show PayActionButton;
import '../../core/format.dart' show fmtCents;
import '../../core/design_tokens.dart';

class IncomingRequestBanner extends StatelessWidget {
  final Map<String, dynamic> req;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;
  const IncomingRequestBanner(
      {super.key,
      required this.req,
      required this.onAccept,
      required this.onDismiss});
  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final amount = (req['amount_cents'] ?? 0).toString();
    final fromWallet = (req['from_wallet_id'] ?? '').toString();
    return Padding(
        padding: const EdgeInsets.all(12),
        child: GlassPanel(
            child: Row(children: [
          const Icon(Icons.pending_actions_outlined),
          const SizedBox(width: 8),
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
              ])),
          const SizedBox(width: 8),
          PayActionButton(
            label: l.isArabic ? 'قبول و دفع' : 'Accept & Pay',
            onTap: onAccept,
          ),
          const SizedBox(width: 8),
          IconButton(onPressed: onDismiss, icon: const Icon(Icons.close))
        ])));
  }
}

class RequestsPage extends StatefulWidget {
  final String baseUrl;
  final String walletId;
  const RequestsPage(
      {super.key, required this.baseUrl, required this.walletId});
  @override
  State<RequestsPage> createState() => _RequestsPageState();
}

class _RequestsPageState extends State<RequestsPage> {
  List<Map<String, dynamic>> incoming = [];
  List<Map<String, dynamic>> outgoing = [];
  String out = '';
  bool loading = true;
  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => loading = true);
    try {
      final i = await _fetch('incoming');
      final o = await _fetch('outgoing');
      incoming = i;
      outgoing = o;
      out = '';
    } catch (e) {
      out = '${L10n.of(context).historyErrorPrefix}: $e';
    }
    setState(() => loading = false);
  }

  Future<List<Map<String, dynamic>>> _fetch(String kind) async {
    final u = Uri.parse('${widget.baseUrl}/payments/requests?wallet_id=' +
        Uri.encodeComponent(widget.walletId) +
        '&kind=' +
        kind +
        '&limit=100');
    final r = await http.get(u, headers: await _hdrPR());
    if (r.statusCode != 200) throw Exception('${r.statusCode}: ${r.body}');
    return (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
  }

  Future<void> _accept(String id) async {
    final r = await http.post(
        Uri.parse('${widget.baseUrl}/payments/requests/' +
            Uri.encodeComponent(id) +
            '/accept'),
        headers: await _hdrPR());
    if (!mounted) return;
    if (r.statusCode == 200) {
      _loadAll();
    } else {
      setState(() => out = '${r.statusCode}: ${r.body}');
    }
  }

  Future<void> _cancel(String id) async {
    final r = await http.post(
        Uri.parse('${widget.baseUrl}/payments/requests/' +
            Uri.encodeComponent(id) +
            '/cancel'),
        headers: await _hdrPR());
    if (!mounted) return;
    if (r.statusCode == 200) {
      _loadAll();
    } else {
      setState(() => out = '${r.statusCode}: ${r.body}');
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = AppBG();
    final l = L10n.of(context);
    final body = loading
        ? const Center(
            child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator()))
        : TabBarView(children: [
            _list(_pending(incoming) + _pending(outgoing),
                pendingOnly: true, incoming: true),
            _list(incoming, incoming: true),
            _list(outgoing, incoming: false),
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

  List<Map<String, dynamic>> _pending(List<Map<String, dynamic>> arr) =>
      arr.where((e) => (e['status'] ?? '') == 'pending').toList();

  Widget _list(List<Map<String, dynamic>> arr,
      {required bool incoming, bool pendingOnly = false}) {
    if (arr.isEmpty) return Center(child: Text(L10n.of(context).payNoEntries));
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView.builder(
          itemCount: arr.length,
          itemBuilder: (_, i) {
            final e = arr[i];
            final id = (e['id'] ?? '').toString();
            final amtCents = (e['amount_cents'] ?? 0) as int;
            final st = (e['status'] ?? '').toString();
            final from = (e['from_wallet_id'] ?? '').toString();
            final to = (e['to_wallet_id'] ?? '').toString();
            final msg = (e['message'] ?? '').toString();
            final currency = (e['currency'] ?? 'SYP').toString();
            final canAccept = incoming && st == 'pending';
            final canCancel = st == 'pending';
            final other = incoming ? from : to;
            final theme = Theme.of(context);
            final l = L10n.of(context);
            final amountFmt = '${fmtCents(amtCents)} $currency';
            final isPending = st.toLowerCase() == 'pending';
            final isAccepted = st.toLowerCase() == 'accepted';
            final isCancelled = st.toLowerCase() == 'cancelled';
            final isExpired = st.toLowerCase() == 'expired';
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
              child: GlassPanel(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor:
                          Tokens.colorPayments.withValues(alpha: .12),
                      child: Text(
                        other.isNotEmpty
                            ? other.characters.take(2).toString().toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: Tokens.colorPayments.withValues(alpha: .95),
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
                                      final wallet = incoming ? from : from;
                                      final ref = msg;
                                      final payload = 'PAY|wallet=' +
                                          Uri.encodeComponent(wallet) +
                                          (amtCents > 0
                                              ? '|amount=$amtCents'
                                              : '') +
                                          (ref.isNotEmpty
                                              ? '|ref=' +
                                                  Uri.encodeComponent(ref)
                                              : '');
                                      showModalBottomSheet(
                                        context: context,
                                        builder: (_) => Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                payload,
                                                textAlign: TextAlign.center,
                                              ),
                                              const SizedBox(height: 8),
                                              QrImageView(
                                                data: payload,
                                                size: 220,
                                              ),
                                            ],
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

Future<String?> _getCookiePR() async {
  final sp = await SharedPreferences.getInstance();
  return sp.getString('sa_cookie');
}

Future<Map<String, String>> _hdrPR({bool json = false}) async {
  final h = <String, String>{};
  if (json) h['content-type'] = 'application/json';
  final c = await _getCookiePR();
  if (c != null && c.isNotEmpty) h['Cookie'] = c;
  return h;
}
