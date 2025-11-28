import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'glass.dart';
import 'skeleton.dart';
import 'offline_queue.dart';
import 'format.dart' show fmtCents;
import 'ui_kit.dart';
import 'l10n.dart';
import '../main.dart' show AppBG; // reuse background only

class HistoryPage extends StatefulWidget{
  final String baseUrl;
  final String walletId;
  final List<Map<String,dynamic>>? initialTxns;
  const HistoryPage({super.key, required this.baseUrl, required this.walletId, this.initialTxns});
  @override State<HistoryPage> createState()=>_HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage>{
  List<dynamic> txns=[]; String out=''; bool loading=true;
  String _dirFilter = 'all';
  String _kindFilter = 'all';
  String _dateFilter = 'all';
  DateTime? _fromDate; DateTime? _toDate;
  final _dirs = const ['all','out','in'];
  final _kinds = const ['all','transfer','topup','cash','sonic'];
  final _dates = const ['all','7d','30d','custom'];
  String _curSym = 'SYP';
  int _limit = 25;
  @override void initState(){
    super.initState();
    _loadPrefs();
    if(widget.initialTxns != null){
      txns = widget.initialTxns!;
      loading = false;
    }else{
      _load();
    }
  }
  Future<void> _load() async {
    setState(()=>loading=true);
    try{
      final qp = <String,String>{ 'limit': _limit.toString() };
      if(_dirFilter!='all') qp['dir']= _dirFilter;
      if(_kindFilter!='all') qp['kind']= _kindFilter;
      DateTime? f; DateTime? t;
      if(_dateFilter=='7d'){ f = DateTime.now().subtract(const Duration(days:7)); }
      else if(_dateFilter=='30d'){ f = DateTime.now().subtract(const Duration(days:30)); }
      else if(_dateFilter=='custom'){ f = _fromDate; t = _toDate; }
      String toIso(DateTime d)=> d.toUtc().toIso8601String();
      if(f!=null) qp['from_iso'] = toIso(f);
      if(t!=null) qp['to_iso'] = toIso(t);
      final u = Uri.parse('${widget.baseUrl}/wallets/'+Uri.encodeComponent(widget.walletId)+'/snapshot').replace(queryParameters: qp);
      final r = await http.get(u, headers: await _hdr());
      if(r.statusCode==200){
        final j = jsonDecode(r.body) as Map<String,dynamic>;
        final arr = j['txns'];
        if(arr is List){
          txns = arr;
          out = '';
        }else{
          out = L10n.of(context).historyUnexpectedFormat;
        }
        final w = j['wallet'];
        if(w is Map<String,dynamic>){
          final cur = (w['currency'] ?? '').toString();
          if(cur.isNotEmpty) _curSym = cur;
        }
      }
      else { out = '${r.statusCode}: ${r.body}'; }
    }catch(e){ out='${L10n.of(context).historyErrorPrefix}: $e'; }
    setState(()=>loading=false);
  }
  Future<void> _loadMore() async {
    if(loading) return;
    setState(()=> loading=true);
    try{
      final next = _limit + 25;
      _limit = next > 200 ? 200 : next;
      await _load();
    }finally{
      if(mounted) setState(()=> loading=false);
    }
  }
  void _exportCsv(){
    try{
      final headers = ['time','kind','amount_cents','amount_fmt','from_wallet','to_wallet','note'];
      final rows = <List<String>>[headers];
      for(final t in _filtered()){ 
        final ac = (t['amount_cents']??0) as int;
        final af = fmtCents(ac) + ' ' + (_curSym);
        rows.add([
          (t['created_at']??'').toString(),
          (t['kind']??'').toString(),
          (t['amount_cents']??'').toString(),
          af,
          (t['from_wallet_id']??'').toString(),
          (t['to_wallet_id']??'').toString(),
          (t['reference']??'').toString(),
        ]);
      }
      final csv = rows.map((r)=>r.map((c)=>'"'+c.replaceAll('"','""')+'"').join(',')).join('\n');
      final subject = L10n.of(context).historyExportSubject;
      Share.share(csv, subject: subject);
    }catch(e){
      final l = L10n.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l.historyCsvErrorPrefix}: $e')),
      );
    }
  }
  List<Map<String,dynamic>> _filtered(){
    final now = DateTime.now();
    int? minEpoch;
    if(_dateFilter=='7d'){ minEpoch = now.subtract(const Duration(days:7)).millisecondsSinceEpoch; }
    else if(_dateFilter=='30d'){ minEpoch = now.subtract(const Duration(days:30)).millisecondsSinceEpoch; }
    return txns.whereType<Map<String,dynamic>>().where((t){
      final from = (t['from_wallet_id']??'').toString();
      final dirOkay = _dirFilter=='all' || (_dirFilter=='out'? from==widget.walletId : from!=widget.walletId);
      final kind = (t['kind']??'').toString().toLowerCase();
      final kindOkay = _kindFilter=='all' || kind.contains(_kindFilter);
      bool dateOkay = true;
      if(minEpoch!=null){ try{ final ts = DateTime.tryParse((t['created_at']??'').toString())?.millisecondsSinceEpoch; if(ts!=null) dateOkay = ts>=minEpoch; }catch(_){ } }
      return dirOkay && kindOkay && dateOkay;
    }).toList();
  }
  Future<void> _loadPrefs() async {
    try{ final sp=await SharedPreferences.getInstance(); _dirFilter = sp.getString('ph_dir') ?? _dirFilter; _kindFilter = sp.getString('ph_kind') ?? _kindFilter; _dateFilter = sp.getString('ph_date') ?? _dateFilter; final f=sp.getString('ph_from'); final t=sp.getString('ph_to'); if(f!=null) _fromDate=DateTime.tryParse(f); if(t!=null) _toDate=DateTime.tryParse(t); final cs=sp.getString('currency_symbol'); if(cs!=null && cs.isNotEmpty) _curSym=cs; if(mounted) setState((){}); }catch(_){ }
  }
  Future<void> _savePrefs() async { try{ final sp=await SharedPreferences.getInstance(); await sp.setString('ph_dir', _dirFilter); await sp.setString('ph_kind', _kindFilter); await sp.setString('ph_date', _dateFilter); if(_fromDate!=null) await sp.setString('ph_from', _fromDate!.toIso8601String()); if(_toDate!=null) await sp.setString('ph_to', _toDate!.toIso8601String()); }catch(_){ } }
  Future<void> _pickDate(BuildContext context, bool from) async {
    final now = DateTime.now();
    final cur = from? (_fromDate ?? now.subtract(const Duration(days:7))) : (_toDate ?? now);
    final picked = await showDatePicker(context: context, initialDate: cur, firstDate: DateTime(now.year-3), lastDate: DateTime(now.year+1));
    if(picked!=null){ setState((){ if(from) _fromDate = picked; else _toDate = picked; }); await _savePrefs(); await _load(); }
  }
  Future<void> _pickDates(BuildContext context) async { await _pickDate(context, true); await _pickDate(context, false); }
  Widget? _buildPhSummary(List<Map<String,dynamic>> list){
    try{
      int inC=0, outC=0; int inCnt=0, outCnt=0;
      for(final t in list){ final amt=(t['amount_cents']??0) as int; final isOut=(t['from_wallet_id']??'')==widget.walletId; if(isOut){ outC+=amt; outCnt++; } else { inC+=amt; inCnt++; } }
      return Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Row(children:[ Text('Count: ${list.length}'), const SizedBox(width:12), Text('Out: ${outCnt}/${fmtCents(outC)} ${_curSym}'), const SizedBox(width:12), Text('In: ${inCnt}/${fmtCents(inC)} ${_curSym}') ]));
    }catch(_){ return null; }
  }
  @override
  Widget build(BuildContext context){
    final pTransfer = OfflineQueue.pending(tag: 'payments_transfer');
    final pTopup = OfflineQueue.pending(tag: 'payments_topup');
    final pSonic = OfflineQueue.pending(tag: 'payments_sonic');
    final pCash = OfflineQueue.pending(tag: 'payments_cash');
    List<Widget> sections = [];
    Widget section(String title, List pending){
      if(pending.isEmpty) return const SizedBox.shrink();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children:[
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
        ...pending.map<Widget>((p)=> ListTile(leading: const CircleAvatar(child: Text('~')), title: const Text('Pending (offline)'), subtitle: Text(p.body, maxLines: 2, overflow: TextOverflow.ellipsis))).toList(),
        const Divider(height: 16),
      ]);
    }
    final l = L10n.of(context);
    sections.add(section(l.isArabic ? 'تحويلات' : 'Transfers', pTransfer));
    sections.add(section(l.isArabic ? 'شحنات' : 'Top‑Up', pTopup));
    sections.add(section(l.isArabic ? 'سونك' : 'Sonic', pSonic));
    sections.add(section(l.isArabic ? 'نقداً' : 'Cash', pCash));
    final filtered = _filtered();
    final header = Padding(padding: const EdgeInsets.all(12), child: Row(children:[
      Text(l.historyDirLabel), const SizedBox(width:6), DropdownButton<String>(value: _dirFilter, items: _dirs.map((s)=> DropdownMenuItem(value:s, child: Text(s))).toList(), onChanged: (v){ if(v==null) return; setState(()=>_dirFilter=v); _savePrefs(); }), const SizedBox(width:12),
      Text(l.historyTypeLabel), const SizedBox(width:6), DropdownButton<String>(value: _kindFilter, items: _kinds.map((s)=> DropdownMenuItem(value:s, child: Text(s))).toList(), onChanged: (v){ if(v==null) return; setState(()=>_kindFilter=v); _savePrefs(); }), const SizedBox(width:12),
      Text(l.historyPeriodLabel), const SizedBox(width:6), DropdownButton<String>(value: _dateFilter, items: _dates.map((s)=> DropdownMenuItem(value:s, child: Text(s))).toList(), onChanged: (v) async { if(v==null) return; setState(()=>_dateFilter=v); if(v=='custom'){ await _pickDates(context); } _savePrefs(); await _load(); }),
    ]));
    final customRow = (_dateFilter=='custom')? Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children:[
      OutlinedButton.icon(onPressed: () async { await _pickDate(context, true); }, icon: const Icon(Icons.date_range), label: Text(_fromDate==null? l.historyFromLabel : _fromDate!.toLocal().toString().split(' ').first)), const SizedBox(width:8),
      OutlinedButton.icon(onPressed: () async { await _pickDate(context, false); }, icon: const Icon(Icons.date_range), label: Text(_toDate==null? l.historyToLabel : _toDate!.toLocal().toString().split(' ').first)),
    ])) : const SizedBox.shrink();
    final summary = _buildPhSummary(filtered);
    final cs = _curSym;
    final txnList = Column(children: [
      header,
      customRow,
      if(summary!=null) summary,
      ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: filtered.length,
        itemBuilder: (_,i){
          final t=filtered[i];
          final cents=(t['amount_cents']??0) as int; final isOut=(t['from_wallet_id']??'')==widget.walletId;
          final sign=isOut? '-' : '+'; final who=isOut? (t['to_wallet_id']??'') : (t['from_wallet_id']??''); final amt = fmtCents(cents);
          final subtitle = '${t['kind']??''}  $who  ${(t['created_at']??'').toString()}'
              '${(t['reference']??'').toString().isNotEmpty ? '\n${t['reference']}' : ''}';
          return StandardListTile(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            leading: CircleAvatar(
              child: Text(
                sign,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            title: Text('$sign$amt $cs'),
            subtitle: Text(subtitle),
          );
        }
      ),
      const SizedBox(height:8),
      OutlinedButton.icon(
        onPressed: filtered.isEmpty || loading ? null : () async { await _loadMore(); },
        icon: const Icon(Icons.expand_more),
        label: Text(L10n.of(context).isArabic ? 'تحميل المزيد (الحد: $_limit)' : 'Load more (limit: $_limit)'),
      ),
    ]);
    Widget listWidget = loading
      ? ListView.builder(physics: const AlwaysScrollableScrollPhysics(), itemCount: 6, itemBuilder: (_,i)=> SkeletonListTile())
      : ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ...sections,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                l.historyPostedTransactions,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            txnList,
          ],
        );
    const bg = AppBG();
    return Scaffold(
      appBar: AppBar(title: Text(l.historyTitle), actions: [ IconButton(onPressed: _exportCsv, icon: const Icon(Icons.ios_share_outlined)) ], backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(children:[ bg, Positioned.fill(child: SafeArea(child: GlassPanel(padding: const EdgeInsets.all(16), child: RefreshIndicator(onRefresh: () async { await OfflineQueue.flush(); await _load(); }, child: listWidget)))) ]),
    );
  }
}

Future<String?> _getCookie() async { final sp=await SharedPreferences.getInstance(); return sp.getString('sa_cookie'); }
Future<Map<String,String>> _hdr({bool json=false}) async { final h=<String,String>{}; if(json) h['content-type']='application/json'; final c=await _getCookie(); if(c!=null&&c.isNotEmpty) h['Cookie']=c; return h; }
