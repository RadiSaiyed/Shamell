import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../skeleton.dart';
import '../offline_queue.dart';
import '../ui_kit.dart';
import '../l10n.dart';
import 'taxi_common.dart' show hdrTaxi;

class TaxiHistoryPage extends StatefulWidget{
  final String baseUrl; const TaxiHistoryPage(this.baseUrl, {super.key});
  @override State<TaxiHistoryPage> createState()=>_TaxiHistoryPageState();
}

class _TaxiHistoryPageState extends State<TaxiHistoryPage>{
  List<dynamic> rides=[]; bool loading=true; String out='';
  String _statusFilter = 'all';
  final List<String> _statuses = const ['all','requested','assigned','started','completed','canceled'];

  Future<void> _load() async {
    setState(()=>loading=true);
    try{
      final qs = <String, String>{ 'limit':'100' };
      if(_statusFilter!='all') qs['status']= _statusFilter;
      final u = Uri.parse('${widget.baseUrl}/me/taxi_history').replace(queryParameters: qs);
      final r = await http.get(u, headers: await hdrTaxi());
      if(r.statusCode==200){ rides = (jsonDecode(r.body) as List); out=''; }
      else out = '${r.statusCode}: ${r.body}';
    }catch(e){ out='Error: $e'; }
    setState(()=>loading=false);
  }

  @override void initState(){ super.initState(); _loadPrefs(); }
  Future<void> _loadPrefs() async { try{ final sp=await SharedPreferences.getInstance(); _statusFilter = sp.getString('txh_status') ?? _statusFilter; }catch(_){ } await _load(); }
  Future<void> _savePrefs() async { try{ final sp=await SharedPreferences.getInstance(); await sp.setString('txh_status', _statusFilter); }catch(_){ } }

  @override Widget build(BuildContext context){
    final pReq = OfflineQueue.pending(tag: 'taxi_request');
    final pBook = OfflineQueue.pending(tag: 'taxi_book');
    final l = L10n.of(context);
    final filterSection = FormSection(
      title: l.isArabic ? 'تصفية' : 'Filter',
      children: [
        Row(
          children: [
            DropdownButton<String>(
              value: _statusFilter,
              items: _statuses.map((s)=> DropdownMenuItem(value:s, child: Text(s))).toList(),
              onChanged: (v){
                if(v==null) return;
                setState(()=>_statusFilter=v);
                _savePrefs();
                _load();
              },
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _exportCsv,
              icon: const Icon(Icons.ios_share_outlined),
              label: Text(l.isArabic ? 'تصدير CSV' : 'Export CSV'),
            ),
          ],
        ),
      ],
    );

    Widget pendingSection(String title, List items){
      if(items.isEmpty) return const SizedBox.shrink();
      return FormSection(
        title: title,
        children: items.map<Widget>((t)=> StandardListTile(
          leading: const Icon(Icons.schedule),
          title: Text(l.isArabic ? 'معلّق (بدون اتصال)' : 'Pending (offline)'),
          subtitle: Text(t.body, maxLines: 2, overflow: TextOverflow.ellipsis),
        )).toList(),
      );
    }

    final ridesSection = FormSection(
      title: l.isArabic ? 'الرحلات' : 'Rides',
      children: [
        if(rides.isEmpty && !loading)
          Text(l.isArabic ? 'لا توجد رحلات بعد.' : 'No rides yet.'),
        if(rides.isNotEmpty)...rides.map<Widget>((r)=> StandardListTile(
          leading: const Icon(Icons.local_taxi_outlined),
          title: Text('${r['status']??'ride'}'),
          subtitle: Text(_safeStr(r)),
        )),
      ],
    );

    final list = loading
      ? ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: 6,
          itemBuilder: (_,i)=> const SkeletonListTile(),
        )
      : ListView(
          padding: const EdgeInsets.all(16),
          children: [
            filterSection,
            pendingSection(l.isArabic ? 'طلبات معلّقة' : 'Pending Requests', pReq),
            pendingSection(l.isArabic ? 'حجوزات معلّقة' : 'Pending Bookings', pBook),
            ridesSection,
          ],
        );
    return Scaffold(
      appBar: AppBar(title: Text(l.isArabic ? 'رحلات التاكسي' : 'Taxi Rides'), backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(children:[
        Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0F172A), Color(0xFF0B1220)]))),
        SafeArea(child: RefreshIndicator(onRefresh: () async { await OfflineQueue.flush(); await _load(); }, child: list)),
      ]),
    );
  }

  String _safeStr(dynamic r){ try{ return (r is Map)? (r['id']??'') .toString() : r.toString(); }catch(_){ return r.toString(); } }
  void _exportCsv(){
    try{
      final headers = ['id','status','driver','rider','created_at'];
      final rows = <List<String>>[headers];
      for(final t in rides){ if(t is Map){ rows.add([ (t['id']??'').toString(), (t['status']??'').toString(), (t['driver_id']??'').toString(), (t['rider_id']??'').toString(), (t['created_at']??'').toString() ]); } }
      final csv = rows.map((r)=>r.map((c)=>'"'+c.replaceAll('"','""')+'"').join(',')).join('\n');
      Share.share(csv, subject: 'Taxi Rides');
    }catch(_){ }
  }
}
