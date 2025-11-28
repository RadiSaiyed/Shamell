import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../glass.dart';
import '../format.dart' show fmtCents;
import '../l10n.dart';
import 'taxi_common.dart' show hdrTaxi, TaxiBG, TaxiActionButton, TaxiSlideButton;

class TaxiWalletPage extends StatefulWidget{
  final String baseUrl; const TaxiWalletPage(this.baseUrl, {super.key});
  @override State<TaxiWalletPage> createState()=>_TaxiWalletPageState();
}

class _TaxiWalletPageState extends State<TaxiWalletPage>{
  String? driverId; String? taxiWalletId; String out='';
  int balanceCents=0; String currency='SYP';
  List<dynamic> txns=[]; final amtCtrl = TextEditingController();
  String generalWallet=''; bool loading=false;
  bool autoRefresh=true; Timer? _timer;

  @override void initState(){ super.initState(); _init(); }

  Future<void> _init() async {
    final sp = await SharedPreferences.getInstance();
    driverId = sp.getString('taxi_driver_id') ?? '';
    generalWallet = sp.getString('wallet_id') ?? '';
    autoRefresh = sp.getBool('taxi_wallet_auto_refresh') ?? true;
    setState((){});
    await _resolveTaxiWallet();
    await _refresh();
    if(autoRefresh){ _timer?.cancel(); _timer = Timer.periodic(const Duration(seconds: 12), (_)=> _refresh()); }
  }

  Future<void> _resolveTaxiWallet() async {
    final id = (driverId??'').trim(); if(id.isEmpty) return;
    try{
      final r = await http.get(Uri.parse('${widget.baseUrl}/taxi/drivers/'+Uri.encodeComponent(id)), headers: await hdrTaxi());
      if(r.statusCode==200){ final j=jsonDecode(r.body); taxiWalletId = (j['wallet_id']??'').toString(); }
    }catch(_){ }
    setState((){});
  }

  Future<void> _refresh() async { if(taxiWalletId==null || taxiWalletId!.isEmpty) return; setState(()=>loading=true);
    try{
      final w = await http.get(Uri.parse('${widget.baseUrl}/payments/wallets/'+Uri.encodeComponent(taxiWalletId!)));
      if(w.statusCode==200){ final j=jsonDecode(w.body); balanceCents = (j['balance_cents']??0) as int; currency = (j['currency']??'SYP').toString(); }
    }catch(_){ }
    try{
      final t = await http.get(Uri.parse('${widget.baseUrl}/payments/txns?wallet_id='+Uri.encodeComponent(taxiWalletId!)+'&limit=20&dir=in'));
      if(t.statusCode==200){ txns = jsonDecode(t.body) as List; }
    }catch(_){ }
    setState(()=>loading=false);
  }

  @override void dispose(){ _timer?.cancel(); super.dispose(); }

  Map<String, dynamic> _todaySummary(){
    int count=0; int cents=0;
    try{
      final now = DateTime.now();
      for(final t in txns){
        final ts = (t['created_at']??'').toString();
        if(ts.isEmpty) continue;
        final dt = DateTime.tryParse(ts);
        if(dt==null) continue;
        final local = dt.toLocal();
        if(local.year==now.year && local.month==now.month && local.day==now.day){
          count += 1; cents += (t['amount_cents']??0) as int;
        }
      }
    }catch(_){ }
    return {'count':count,'cents':cents};
  }

  Future<void> _transferToGeneral() async {
    final wid = taxiWalletId; final to = generalWallet.trim();
    if(wid==null || wid.isEmpty || to.isEmpty){ setState(()=>out='missing wallet'); return; }
    try{
      final amountStr = amtCtrl.text.trim();
      final body = jsonEncode({ 'from_wallet_id': wid, 'to_wallet_id': to, 'amount': amountStr, 'reference': 'taxi payout' });
      final r = await http.post(Uri.parse('${widget.baseUrl}/payments/transfer'), headers: {'content-type':'application/json'}, body: body);
      out='${r.statusCode}: ${r.body}';
      await _refresh();
    }catch(e){ out='Error: $e'; }
    if(mounted) setState((){});
  }

  Future<void> _transferAll() async {
    if(balanceCents<=0) return; // nothing to sweep
    // convert cents to SYP major string
    final major = (balanceCents/100).toStringAsFixed(2);
    amtCtrl.text = major;
    await _transferToGeneral();
  }

  String? _parseRideId(dynamic t){
    try{
      final ref = (t['reference']??'').toString();
      final m = RegExp(r'taxi\s+([A-Za-z0-9_-]+)').firstMatch(ref);
      return m!=null? m.group(1) : null;
    }catch(_){ return null; }
  }
  Future<void> _openRide(String rideId) async {
    try{
      final r=await http.get(Uri.parse('${widget.baseUrl}/taxi/rides/'+Uri.encodeComponent(rideId)), headers: await hdrTaxi());
      final body = r.body;
      if(!mounted) return;
      showDialog(context: context, builder: (_)=> AlertDialog(title: Text('Ride $rideId'), content: SizedBox(width: 420, child: SingleChildScrollView(child: Text(body))), actions: [ TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Close')) ]));
    }catch(e){ if(!mounted) return; showDialog(context: context, builder: (_)=> AlertDialog(title: const Text('Error'), content: Text('$e'))); }
  }

  @override Widget build(BuildContext context){
    final list = loading? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())) : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children:[
      const SizedBox(height: 8),
      ...txns.map<Widget>((t){
        final cents=(t['amount_cents']??0) as int; final ref=(t['reference']??'').toString(); final ts=(t['created_at']??'').toString();
        final rideId = _parseRideId(t);
        final row = Row(children:[ const Icon(Icons.call_received, size:18), const SizedBox(width:8), Expanded(child: Text('$ref\n$ts', maxLines:2, overflow: TextOverflow.ellipsis)), Text('+${fmtCents(cents)} $currency', style: const TextStyle(fontWeight: FontWeight.w700)) ]);
        return Padding(padding: const EdgeInsets.symmetric(vertical:4), child: InkWell(onTap: rideId==null? null : ()=> _openRide(rideId), child: GlassPanel(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: row)));
      }).toList(),
    ]);

    final sum = _todaySummary();
    final content = ListView(padding: const EdgeInsets.all(12), children:[
      const Text('Taxi Wallet', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      GlassPanel(padding: const EdgeInsets.all(12), child:
        Row(children:[
          const Icon(Icons.account_balance_wallet_outlined), const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
            Text(taxiWalletId==null||taxiWalletId!.isEmpty? '—' : taxiWalletId!, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('Balance: ${fmtCents(balanceCents)} $currency'),
          ])),
          Row(mainAxisSize: MainAxisSize.min, children:[
            const Text('Auto'), Switch(value: autoRefresh, onChanged: (v) async { setState(()=>autoRefresh=v); final sp=await SharedPreferences.getInstance(); await sp.setBool('taxi_wallet_auto_refresh', v); _timer?.cancel(); if(autoRefresh){ _timer=Timer.periodic(const Duration(seconds: 12), (_)=> _refresh()); } }), const SizedBox(width:8),
            TaxiActionButton(label: 'Refresh', onTap: _refresh),
          ]),
        ]),
      ),
      const SizedBox(height: 8),
      GlassPanel(padding: const EdgeInsets.all(12), child: Row(children:[ const Icon(Icons.summarize_outlined), const SizedBox(width:8), Text("Today's fares: "+sum['count'].toString()+" rides • "+fmtCents(sum['cents'])+" $currency", style: const TextStyle(fontWeight: FontWeight.w700)) ])),
      const SizedBox(height: 12),
      const Text('Transfer to general wallet', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      SizedBox(width: 240, child: TextField(controller: amtCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: L10n.of(context).isArabic ? 'المبلغ (ليرة)' : 'Amount (SYP)'))),
      const SizedBox(height: 8),
      TaxiSlideButton(label: L10n.of(context).isArabic ? 'تحويل' : 'Transfer', onConfirm: _transferToGeneral, disabled: taxiWalletId==null||taxiWalletId!.isEmpty||generalWallet.isEmpty),
      const SizedBox(height: 8),
      TaxiSlideButton(label: L10n.of(context).isArabic ? 'دفع الكل' : 'Pay all', onConfirm: _transferAll, disabled: (balanceCents<=0) || taxiWalletId==null||taxiWalletId!.isEmpty||generalWallet.isEmpty),
      const SizedBox(height: 16),
      Text(L10n.of(context).isArabic ? 'الإيرادات الواردة' : 'Incoming fares', style: const TextStyle(fontWeight: FontWeight.w700)),
      list,
      const SizedBox(height: 8),
      if(out.isNotEmpty) SelectableText(out),
    ]);

    return Scaffold(
      appBar: AppBar(title: Text(L10n.of(context).isArabic ? 'محفظة التاكسي' : 'Taxi Wallet'), backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(children:[
        const TaxiBG(),
        Positioned.fill(child: SafeArea(child: GlassPanel(padding: const EdgeInsets.all(12), radius: 12, child: content))),
      ]),
    );
  }
}
