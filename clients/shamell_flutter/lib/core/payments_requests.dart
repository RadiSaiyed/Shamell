import 'dart:convert';
import 'package:flutter/material.dart';
import 'glass.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'l10n.dart';
import '../main.dart' show AppBG; // reuse bg only
import 'payments_send.dart' show PayActionButton;

class IncomingRequestBanner extends StatelessWidget{
  final Map<String,dynamic> req;
  final VoidCallback onAccept; final VoidCallback onDismiss;
  const IncomingRequestBanner({super.key, required this.req, required this.onAccept, required this.onDismiss});
  @override Widget build(BuildContext context){
    final l = L10n.of(context);
    final amount = (req['amount_cents']??0).toString();
    final fromWallet = (req['from_wallet_id']??'').toString();
    return Padding(padding: const EdgeInsets.all(12), child: GlassPanel(child:
      Row(children:[
        const Icon(Icons.pending_actions_outlined), const SizedBox(width:8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
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
        const SizedBox(width:8),
        PayActionButton(
          label: l.isArabic ? 'قبول و دفع' : 'Accept & Pay',
          onTap: onAccept,
        ),
        const SizedBox(width:8),
        IconButton(onPressed: onDismiss, icon: const Icon(Icons.close))
      ])
    ));
  }
}

class RequestsPage extends StatefulWidget{
  final String baseUrl; final String walletId;
  const RequestsPage({super.key, required this.baseUrl, required this.walletId});
  @override State<RequestsPage> createState()=>_RequestsPageState();
}
class _RequestsPageState extends State<RequestsPage>{
  List<Map<String,dynamic>> incoming=[]; List<Map<String,dynamic>> outgoing=[]; String out=''; bool loading=true;
  @override void initState(){ super.initState(); _loadAll(); }
  Future<void> _loadAll() async { setState(()=>loading=true); try{ final i=await _fetch('incoming'); final o=await _fetch('outgoing'); incoming=i; outgoing=o; out=''; }catch(e){ out='${L10n.of(context).historyErrorPrefix}: $e'; } setState(()=>loading=false); }
  Future<List<Map<String,dynamic>>> _fetch(String kind) async {
    final u=Uri.parse('${widget.baseUrl}/payments/requests?wallet_id='+Uri.encodeComponent(widget.walletId)+'&kind='+kind+'&limit=100');
    final r=await http.get(u, headers: await _hdrPR()); if(r.statusCode!=200) throw Exception('${r.statusCode}: ${r.body}');
    return (jsonDecode(r.body) as List).cast<Map<String,dynamic>>();
  }
  Future<void> _accept(String id) async { final r=await http.post(Uri.parse('${widget.baseUrl}/payments/requests/'+Uri.encodeComponent(id)+'/accept'), headers: await _hdrPR()); if(!mounted) return; if(r.statusCode==200){ _loadAll(); } else { setState(()=>out='${r.statusCode}: ${r.body}'); } }
  Future<void> _cancel(String id) async { final r=await http.post(Uri.parse('${widget.baseUrl}/payments/requests/'+Uri.encodeComponent(id)+'/cancel'), headers: await _hdrPR()); if(!mounted) return; if(r.statusCode==200){ _loadAll(); } else { setState(()=>out='${r.statusCode}: ${r.body}'); } }

  @override Widget build(BuildContext context){
    const bg = AppBG();
    final l = L10n.of(context);
    final body = loading
      ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
      : TabBarView(children:[
          _list(_pending(incoming)+_pending(outgoing), pendingOnly:true, incoming:true),
          _list(incoming, incoming:true),
          _list(outgoing, incoming:false),
        ]);
    return DefaultTabController(length: 3, child: Scaffold(
      appBar: AppBar(title: Text(l.homeRequests), bottom: TabBar(tabs:[
        Tab(text: l.isArabic ? 'قيد الانتظار' : 'Pending'),
        Tab(text: l.isArabic ? 'واردة' : 'Incoming'),
        Tab(text: l.isArabic ? 'صادرة' : 'Outgoing'),
      ]), backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(children:[ bg, Positioned.fill(child: SafeArea(child: GlassPanel(padding: const EdgeInsets.all(16), child: body))) ]),
      bottomNavigationBar: out.isNotEmpty? Padding(padding: const EdgeInsets.all(8), child: Text(out, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .9)))):null,
    ));
  }

  List<Map<String,dynamic>> _pending(List<Map<String,dynamic>> arr)=> arr.where((e)=> (e['status']??'')=='pending').toList();

  Widget _list(List<Map<String,dynamic>> arr, {required bool incoming, bool pendingOnly=false}){
    if(arr.isEmpty) return Center(child: Text(L10n.of(context).payNoEntries));
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView.builder(itemCount: arr.length, itemBuilder: (_,i){
        final e=arr[i];
        final id=(e['id']??'').toString();
        final amtCents=(e['amount_cents']??0) as int;
        final amt=amtCents.toString();
        final st=(e['status']??'').toString();
        final from=(e['from_wallet_id']??'').toString();
        final to=(e['to_wallet_id']??'').toString();
        final canAccept = incoming && st=='pending';
        final canCancel = st=='pending';
        return Padding(
          padding: const EdgeInsets.only(bottom:8),
          child: GlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(radius: 18, child: Text('${amt.length>3? amt.substring(0,amt.length-2):amt}')),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${L10n.of(context).isArabic ? 'المبلغ' : 'Amount'}: $amt  ·  ${L10n.of(context).isArabic ? 'الحالة' : 'Status'}: $st', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('${L10n.of(context).isArabic ? 'من' : 'From'}: $from\n${L10n.of(context).isArabic ? 'إلى' : 'To'}: $to'),
              ])),
              const SizedBox(width: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                IconButton(tooltip: L10n.of(context).isArabic ? 'مشاركة كرمز QR' : 'Share as QR', onPressed: (){
                  final wallet = incoming? from : (from);
                  final ref = (e['message']??'').toString();
                  final payload = 'PAY|wallet='+Uri.encodeComponent(wallet)+(amtCents>0? '|amount=$amtCents':'' )+(ref.isNotEmpty? '|ref='+Uri.encodeComponent(ref):'');
                  showModalBottomSheet(context: context, builder: (_)=> Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children:[ Text(payload, textAlign: TextAlign.center), const SizedBox(height:8), QrImageView(data: payload, size: 220) ])));
                }, icon: const Icon(Icons.qr_code_2)),
                if(canAccept) IconButton(onPressed: ()=>_accept(id), icon: const Icon(Icons.check_circle_outline)),
                if(canCancel) IconButton(onPressed: ()=>_cancel(id), icon: const Icon(Icons.cancel_outlined)),
              ]),
            ]),
          ),
        );
      }),
    );
  }
}

Future<String?> _getCookiePR() async { final sp=await SharedPreferences.getInstance(); return sp.getString('sa_cookie'); }
Future<Map<String,String>> _hdrPR({bool json=false}) async { final h=<String,String>{}; if(json) h['content-type']='application/json'; final c=await _getCookiePR(); if(c!=null&&c.isNotEmpty) h['Cookie']=c; return h; }
