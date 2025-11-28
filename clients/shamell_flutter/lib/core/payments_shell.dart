import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'payments_send.dart';
import 'payments_receive.dart';
import 'payments_scan.dart';
import 'payments_requests.dart';
import 'payments_overview.dart';
import '../main.dart' show AppBG; // reuse background

class PaymentsPage extends StatelessWidget{
  final String baseUrl;
  final String fromWalletId;
  final String deviceId;
  final bool triggerScanOnOpen;
  const PaymentsPage(this.baseUrl, this.fromWalletId, this.deviceId, {super.key, this.triggerScanOnOpen=false});
  @override
  Widget build(BuildContext context){
    return _PaymentsShell(baseUrl: baseUrl, fromWalletId: fromWalletId, deviceId: deviceId, triggerScanOnOpen: triggerScanOnOpen);
  }
}

class _PaymentsShell extends StatefulWidget{
  final String baseUrl; final String fromWalletId; final String deviceId; final bool triggerScanOnOpen;
  const _PaymentsShell({required this.baseUrl, required this.fromWalletId, required this.deviceId, this.triggerScanOnOpen=false});
  @override State<_PaymentsShell> createState()=>_PaymentsShellState();
}

class _PaymentsShellState extends State<_PaymentsShell>{
  String myWallet='';
  Timer? _reqTimer; Set<String> _seenReqs = {};
  Map<String,dynamic>? _bannerReq;

  @override void initState(){ super.initState(); _init(); }
  Future<void> _init() async {
    final sp=await SharedPreferences.getInstance();
    myWallet = sp.getString('wallet_id') ?? widget.fromWalletId;
    if(mounted) setState((){});
    _restoreSeenReqs();
    _startReqPolling();
  }
  @override void dispose(){ _reqTimer?.cancel(); super.dispose(); }

  void _startReqPolling(){ _reqTimer?.cancel(); _reqTimer = Timer.periodic(const Duration(seconds: 30), (_) async { await _pollIncoming(); }); Future.microtask(() async { await _pollIncoming(); }); }
  Future<void> _restoreSeenReqs() async { try{ final sp=await SharedPreferences.getInstance(); final arr=sp.getStringList('seen_reqs')??[]; _seenReqs = arr.toSet(); }catch(_){ } }
  Future<void> _saveSeenReqs() async { try{ final sp=await SharedPreferences.getInstance(); await sp.setStringList('seen_reqs', _seenReqs.toList()); }catch(_){ } }
  Future<void> _pollIncoming() async {
    try{
      final r = await http.get(Uri.parse('${widget.baseUrl}/payments/requests?wallet_id='+Uri.encodeComponent(myWallet)+'&kind=incoming&limit=50'));
      if(r.statusCode!=200) return;
      final arr = (jsonDecode(r.body) as List).cast<Map<String,dynamic>>();
      for(final e in arr){
        final id=(e['id']??'').toString(); final st=(e['status']??'').toString();
        if(st=='pending' && !_seenReqs.contains(id)){
          _seenReqs.add(id); await _saveSeenReqs();
          if(mounted) setState(()=> _bannerReq = e);
        }
      }
    }catch(_){ }
  }


  Future<void> _acceptReq(String id) async { try{ await http.post(Uri.parse('${widget.baseUrl}/payments/requests/'+Uri.encodeComponent(id)+'/accept')); }catch(_){ } if(mounted) setState(()=> _bannerReq=null); }

  @override
  Widget build(BuildContext context){
    const bg = AppBG();
    final initialIndex = widget.triggerScanOnOpen? 1 : 0; // 0=Overview,1=Scan,2=Send,3=Receive
    return DefaultTabController(
      length: 4,
      initialIndex: initialIndex,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Payments'),
          bottom: const TabBar(tabs: [
            Tab(text:'Overview'),
            Tab(text:'Scan & Pay'),
            Tab(text:'Send'),
            Tab(text:'Receive'),
          ]),
          backgroundColor: Colors.transparent,
        ),
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        body: Stack(children:[
          bg,
          SafeArea(child: TabBarView(children: [
            PaymentOverviewTab(baseUrl: widget.baseUrl, walletId: myWallet),
            PaymentScanTab(baseUrl: widget.baseUrl, fromWalletId: myWallet, autoScan: widget.triggerScanOnOpen),
            PaymentSendTab(baseUrl: widget.baseUrl, fromWalletId: myWallet, deviceId: widget.deviceId),
            PaymentReceiveTab(baseUrl: widget.baseUrl, fromWalletId: myWallet),
          ])),
          if(_bannerReq!=null) SafeArea(child:
            IncomingRequestBanner(
              req: _bannerReq!,
              onAccept: ()=> _acceptReq((_bannerReq!['id']??'').toString()),
              onDismiss: ()=> setState(()=>_bannerReq=null),
            ),
          )
        ]),
      ),
    );
  }
}
