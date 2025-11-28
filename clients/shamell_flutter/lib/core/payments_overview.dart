import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'format.dart' show fmtCents;
import 'history_page.dart';
import 'perf.dart';
import 'l10n.dart';
import 'ui_kit.dart';
import 'payments_send.dart' show PayActionButton;

class PaymentOverviewTab extends StatefulWidget{
  final String baseUrl;
  final String walletId;
  const PaymentOverviewTab({super.key, required this.baseUrl, required this.walletId});
  @override State<PaymentOverviewTab> createState()=>_PaymentOverviewTabState();
}

class _PaymentOverviewTabState extends State<PaymentOverviewTab>{
  bool _loading=true;
  int? _balanceCents;
  String _curSym='SYP';
  List<Map<String,dynamic>> _recent=[];
  String _out='';

  @override void initState(){ super.initState(); _init(); }

  Future<void> _init() async {
    setState(()=>_loading=true);
    try{
      await _loadPrefs();
      if(widget.walletId.isNotEmpty){
        await _loadCachedSnapshot();
        await _loadSnapshot();
      }
      _out='';
    }catch(e){
      _out='Error: $e';
      Perf.action('payments_overview_error');
    }
    if(mounted) setState(()=>_loading=false);
  }

  Future<void> _loadSnapshot() async {
    try{
      final qp=<String,String>{ 'limit':'25' };
      final uri=Uri.parse('${widget.baseUrl}/wallets/'+Uri.encodeComponent(widget.walletId)+'/snapshot').replace(queryParameters: qp);
      final r=await http.get(uri, headers: await _hdrPO());
      if(r.statusCode==200){
        Perf.action('payments_overview_snapshot_ok');
        final j=jsonDecode(r.body) as Map<String,dynamic>;
        await _applySnapshot(j, persist: true, rawBody: r.body);
      }else{
        _out='${r.statusCode}: ${r.body}';
        Perf.action('payments_overview_snapshot_fail');
      }
    }catch(e){
      _out='Error: $e';
      Perf.action('payments_overview_snapshot_error');
    }
  }

  Future<void> _loadCachedSnapshot() async {
    try{
      final sp = await SharedPreferences.getInstance();
      final key = 'wallet_snapshot_${widget.walletId}';
      final raw = sp.getString(key);
      if(raw == null || raw.isEmpty) return;
      final j = jsonDecode(raw) as Map<String,dynamic>;
      await _applySnapshot(j, persist: false);
      if(mounted){
        // Sobald Cache-Daten da sind, keinen Spinner mehr anzeigen.
        setState(()=>_loading=false);
      }
    }catch(_){ }
  }

  Future<void> _applySnapshot(
    Map<String,dynamic> j, {
    required bool persist,
    String? rawBody,
  }) async {
    try{
      final w = j['wallet'];
      if(w is Map<String,dynamic>){
        _balanceCents = (w['balance_cents']??0) as int;
        final cur=(w['currency']??'').toString();
        if(cur.isNotEmpty) _curSym=cur;
      }
      final arr = j['txns'];
      if(arr is List){
        _recent = arr.whereType<Map<String,dynamic>>().toList();
      }
      if(persist && rawBody != null){
        final sp = await SharedPreferences.getInstance();
        final key = 'wallet_snapshot_${widget.walletId}';
        await sp.setString(key, rawBody);
      }
    }catch(_){ }
  }

  Future<void> _loadPrefs() async {
    try{
      final sp=await SharedPreferences.getInstance();
      final cs=sp.getString('currency_symbol');
      if(cs!=null && cs.isNotEmpty) _curSym=cs;
    }catch(_){ }
  }

  Future<void> _refresh() async {
    await _init();
  }

  void _goToTab(BuildContext context, int index){
    final ctrl=DefaultTabController.of(context);
    ctrl.animateTo(index);
  }

  @override
  Widget build(BuildContext context){
    final l = L10n.of(context);
    final children=<Widget>[
      FormSection(
        title: l.isArabic ? 'محفظتك' : 'Wallet & balance',
        children: [
          _walletHero(),
        ],
      ),
      FormSection(
        title: l.isArabic ? 'إجراءات سريعة' : 'Quick actions',
        children: [
          _quickActions(context),
        ],
      ),
      FormSection(
        title: l.isArabic ? 'النشاط الأخير' : 'Recent activity',
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  l.isArabic
                      ? 'أحدث الحركات على محفظتك.'
                      : 'Latest payments on your wallet.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: .70),
                      ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: widget.walletId.isEmpty
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => HistoryPage(
                              baseUrl: widget.baseUrl,
                              walletId: widget.walletId,
                              initialTxns: _recent,
                            ),
                          ),
                        );
                      },
                child: Text(l.viewAll),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if(_loading && _balanceCents==null && _recent.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
          else if(widget.walletId.isEmpty)
            Text(
              l.isArabic ? 'لم يتم تعيين المحفظة بعد' : 'Wallet not set yet',
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: .60),
              ),
            )
          else if(_recent.isEmpty)
            Text(
              l.isArabic
                  ? 'لا توجد مدفوعات حديثة'
                  : 'No recent payments yet.',
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: .60),
              ),
            )
          else
            _recentList(),
          if(_out.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _out,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    ];
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: children,
      ),
    );
  }

  Widget _walletHero(){
    final bal=_balanceCents;
    return Row(children:[
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .90),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.account_balance_wallet_outlined, size: 28),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
        Text(L10n.of(context).homeWallet, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(
          widget.walletId.isEmpty ? L10n.of(context).notSet : widget.walletId,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ])),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children:[
        Text(L10n.of(context).isArabic ? 'الرصيد' : 'Balance'),
        Text(
          bal==null? (_loading? '…' : '—') : '${fmtCents(bal)} $_curSym',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ]),
    ]);
  }

  Widget _quickActions(BuildContext context){
    final l = L10n.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
      Row(children:[
        Expanded(child: PayActionButton(
          icon: Icons.arrow_upward_rounded,
          label: l.isArabic ? 'إرسال' : 'Send',
          onTap: ()=> _goToTab(context, 2),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        )),
        const SizedBox(width: 12),
        Expanded(child: PayActionButton(
          icon: Icons.arrow_downward_rounded,
          label: l.isArabic ? 'طلب' : 'Request',
          onTap: ()=> _goToTab(context, 3),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        )),
      ]),
      const SizedBox(height: 12),
      TextButton.icon(
        onPressed: ()=> _goToTab(context, 1),
        icon: const Icon(Icons.qr_code_scanner),
        label: Text(l.qaScanPay),
      ),
    ]);
  }

  Widget _recentList(){
    final items=_recent.take(5).toList();
    return Column(children:[
      for(final t in items) _recentTile(t),
    ]);
  }

  Widget _recentTile(Map<String,dynamic> t){
    final cents=(t['amount_cents']??0) as int;
    final isOut=(t['from_wallet_id']??'').toString()==widget.walletId;
    final sign=isOut? '-' : '+';
    final who=isOut? (t['to_wallet_id']??'') : (t['from_wallet_id']??'');
    final amt=fmtCents(cents);
    final kind=(t['kind']??'').toString();
    final ref=(t['reference']??'').toString();
    final ts=(t['created_at']??'').toString();
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final color=isOut? Colors.redAccent : Colors.lightGreenAccent;
    final subtitleLines = <String>[
      '$kind · $who',
      ts,
    ];
    if(ref.isNotEmpty){
      subtitleLines.add(ref);
    }
    return StandardListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: .16),
        child: Text(
          '$sign${amt.split('.').first}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(
        '$sign$amt $_curSym',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        subtitleLines.join('\n'),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: onSurface.withValues(alpha: .70),
        ),
      ),
    );
  }
}

Future<String?> _getCookiePO() async { final sp=await SharedPreferences.getInstance(); return sp.getString('sa_cookie'); }
Future<Map<String,String>> _hdrPO({bool json=false}) async { final h=<String,String>{}; if(json) h['content-type']='application/json'; final c=await _getCookiePO(); if(c!=null&&c.isNotEmpty) h['Cookie']=c; return h; }
