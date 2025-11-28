import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../format.dart' show fmtCents;
import '../glass.dart';
import '../l10n.dart';
import 'taxi_common.dart' show hdrTaxi, TaxiBG, TaxiActionButton;

class TaxiOperatorPage extends StatefulWidget{
  final String baseUrl; const TaxiOperatorPage(this.baseUrl, {super.key});
  @override State<TaxiOperatorPage> createState()=>_TaxiOperatorPageState();
}

class _TaxiOperatorPageState extends State<TaxiOperatorPage>{
  String out=''; bool loading=false; bool isOnlineUnknown=true;
  List<dynamic> drivers=[]; List<dynamic> rides=[];

  String? _driverId; // assigned after registration
  String? _driverPhone;
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final makeCtrl = TextEditingController();
  final plateCtrl = TextEditingController();
  final TextEditingController _topupAmtCtrl = TextEditingController(text: '10.00');
  String _topupQrPayload = '';

  int? _statsRidesCompleted;
  int? _statsPayoutCents;
  double? _statsAvgRating;

  String _rideStatus = 'all';
  final List<String> _rideStatuses = const ['all','requested','assigned','started','completed','canceled'];
  String _driverStatus = 'all';
  final List<String> _driverStatuses = const ['all','online','offline'];
  final TextEditingController _driverSearchCtrl = TextEditingController();
  String _driverQuery = '';

  @override
  void initState() {
    super.initState();
    _initialLoad();
  }

  Future<void> _initialLoad() async {
    try{
      // Restore last selected driver if available so stats are visible immediately.
      try{
        final sp = await SharedPreferences.getInstance();
        final savedId = sp.getString('taxi_driver_id');
        if(savedId != null && savedId.isNotEmpty){
          _driverId = savedId;
          await _loadDriverStats();
        }
      }catch(_){}
      await Future.wait([
        _listDrivers(),
        _listRides(),
      ]);
    }catch(_){
      // Initial load is best-effort; errors are surfaced via `out`.
    }
  }

  String _rideSummary(dynamic r){
    try{
      if(r is! Map) return r.toString();
      final id = (r['id']??'').toString();
      final st = (r['status']??'').toString();
      final fare = (r['fare_cents']??0) as int;
      final fee = (r['broker_fee_cents']??0) as int;
      final payout = (r['driver_payout_cents']?? (fare-fee)) as int;
      final pickup = '${r['pickup_lat']??''},${r['pickup_lon']??''}';
      final drop = '${r['dropoff_lat']??''},${r['dropoff_lon']??''}';
      final sb = StringBuffer();
      sb.write('Ride $id · $st');
      if(fare>0){
        sb.write(' · Fare: ${fare/100} SYP');
        if(fee>0){
          sb.write(' · Platform fee (SuperAdmin): ${fee/100} SYP · Driver payout: ${payout/100} SYP');
        }
      }
      sb.write('\n$pickup → $drop');
      return sb.toString();
    }catch(_){
      return r.toString();
    }
  }

  Future<void> _listDrivers() async {
    setState(()=>loading=true);
    try{
      final qs = <String,String>{ 'limit':'200' };
      if(_driverStatus!='all') qs['status']=_driverStatus;
      final u = Uri.parse('${widget.baseUrl}/taxi/drivers').replace(queryParameters: qs);
      final r = await http.get(u, headers: await hdrTaxi());
      if(r.statusCode==200){
        drivers = (jsonDecode(r.body) as List);
        // Sort drivers by status so that online drivers appear first,
        // then offline, then any other states.
        drivers.sort((a, b){
          String sa = '';
          String sb = '';
          try{
            sa = (a is Map? (a['status']??'') : '').toString().toLowerCase();
          }catch(_){}
          try{
            sb = (b is Map? (b['status']??'') : '').toString().toLowerCase();
          }catch(_){}
          int rank(String s){
            if(s == 'online') return 0;
            if(s == 'offline') return 1;
            return 2;
          }
          final ra = rank(sa);
          final rb = rank(sb);
          if(ra != rb) return ra.compareTo(rb);
          return 0;
        });
        out='';
      }
      else out='${r.statusCode}: ${r.body}';
    }catch(e){ out='Error: $e'; }
    setState(()=>loading=false);
  }

  Future<void> _listRides() async {
    setState(()=>loading=true);
    try{
      final qs = <String,String>{ 'limit':'100' };
      if(_rideStatus!='all') qs['status']=_rideStatus;
      final u = Uri.parse('${widget.baseUrl}/taxi/rides').replace(queryParameters: qs);
      final r = await http.get(u, headers: await hdrTaxi());
      if(r.statusCode==200){ rides = (jsonDecode(r.body) as List); out=''; }
      else out='${r.statusCode}: ${r.body}';
    }catch(e){ out='Error: $e'; }
    setState(()=>loading=false);
  }

  Future<void> _registerDriver() async {
    setState(()=>out='...');
    try{
      final body = {
        if(nameCtrl.text.trim().isNotEmpty) 'name': nameCtrl.text.trim(),
        if(phoneCtrl.text.trim().isNotEmpty) 'phone': phoneCtrl.text.trim(),
        if(makeCtrl.text.trim().isNotEmpty) 'vehicle_make': makeCtrl.text.trim(),
        if(plateCtrl.text.trim().isNotEmpty) 'vehicle_plate': plateCtrl.text.trim(),
      };
      final r = await http.post(Uri.parse('${widget.baseUrl}/taxi/drivers'), headers: await hdrTaxi(json:true), body: jsonEncode(body));
      out='${r.statusCode}: ${r.body}';
      try{ final j=jsonDecode(r.body); final id=(j['id']??'').toString(); if(id.isNotEmpty) _driverId=id; }catch(_){ }
    }catch(e){ out='Error: $e'; }
    if(mounted) setState((){});
  }

  Future<void> _driverOnline(bool on) async {
    final id = _driverId; if(id==null || id.isEmpty){ setState(()=>out='Register a driver first (no driver_id yet)'); return; }
    setState(()=>out='...');
    try{
      final r = await http.post(Uri.parse('${widget.baseUrl}/taxi/drivers/'+Uri.encodeComponent(id)+'/'+(on? 'online':'offline')), headers: await hdrTaxi());
      out='${r.statusCode}: ${r.body}'; isOnlineUnknown=false;
      // Refresh driver list so that status and ordering reflect the change.
      await _listDrivers();
    }catch(e){ out='Error: $e'; }
    if(mounted) setState((){});
  }

  double _parseMajor(String s){
    try{
      final t = s.trim().replaceAll(',', '.');
      return double.parse(t);
    }catch(_){
      return 0;
    }
  }

  void _makeTopupQr(){
    final phone = _driverPhone;
    if(phone == null || phone.trim().isEmpty){
      setState(()=> out = 'Driver phone not available for QR top-up.');
      return;
    }
    final a = _parseMajor(_topupAmtCtrl.text);
    if(a <= 0){
      setState(()=> out = 'Amount must be greater than zero.');
      return;
    }
    setState(()=> out = 'Creating top-up QR...');
    () async {
      try{
        final body = {
          'driver_phone': phone.trim(),
          'amount': double.parse(a.toStringAsFixed(2)),
        };
        final uri = Uri.parse('${widget.baseUrl}/taxi/topup_qr/create');
        final resp = await http.post(uri, headers: await hdrTaxi(json:true), body: jsonEncode(body));
        if(!mounted) return;
        if(resp.statusCode == 200){
          try{
            final j = jsonDecode(resp.body);
            final payload = (j['payload'] ?? '').toString();
            setState((){
              _topupQrPayload = payload;
              out = '';
            });
          }catch(_){
            setState(()=> out = '200 but invalid JSON from topup_qr/create');
          }
        }else{
          setState(()=> out = '${resp.statusCode}: ${resp.body}');
        }
      }catch(e){
        if(!mounted) return;
        setState(()=> out = 'Error creating top-up QR: $e');
      }
    }();
  }

  Future<void> _loadDriverStats() async {
    final id = _driverId;
    if(id==null || id.isEmpty) return;
    try{
      final uri = Uri.parse('${widget.baseUrl}/taxi/drivers/'+Uri.encodeComponent(id)+'/stats')
          .replace(queryParameters: {'period':'today'});
      final r = await http.get(uri, headers: await hdrTaxi());
      if(r.statusCode==200){
        final j = jsonDecode(r.body);
        if(j is Map<String,dynamic>){
          final ridesCompleted = (j['rides_completed'] ?? 0) as int;
          final payout = (j['total_driver_payout_cents'] ?? 0) as int;
          final avg = j['avg_rating'];
          if(mounted){
            setState((){
              _statsRidesCompleted = ridesCompleted;
              _statsPayoutCents = payout;
              _statsAvgRating = (avg is num)? avg.toDouble() : null;
            });
          }
        }
      }
    }catch(_){ }
  }

  @override Widget build(BuildContext context){
    final l = L10n.of(context);
    final controls = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children:[
      Text(
        l.isArabic ? 'إدارة السائقين والرحلات' : 'Drivers & rides',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      if(_driverId!=null && _driverId!.isNotEmpty) Padding(
        padding: const EdgeInsets.only(top:6, bottom: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
          Text(
            l.isArabic ? 'السائق الحالي: ${_driverId}' : 'Active driver: ${_driverId}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if(_statsRidesCompleted!=null || _statsPayoutCents!=null || _statsAvgRating!=null)
            Padding(
              padding: const EdgeInsets.only(top:4),
              child: Text(
                l.isArabic
                    ? 'اليوم: '
                      '${_statsRidesCompleted ?? 0} رحلات · '
                      '${_statsPayoutCents!=null? '${fmtCents(_statsPayoutCents!)} SYP' : '0 SYP'}'
                      '${_statsAvgRating!=null? ' · ★ ${_statsAvgRating!.toStringAsFixed(1)}' : ''}'
                    : 'Today: '
                      '${_statsRidesCompleted ?? 0} rides · '
                      '${_statsPayoutCents!=null? '${fmtCents(_statsPayoutCents!)} SYP' : '0 SYP'}'
                      '${_statsAvgRating!=null? ' · ★ ${_statsAvgRating!.toStringAsFixed(1)}' : ''}',
                style: const TextStyle(fontSize: 11),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children:[
        TaxiActionButton(
          label: l.isArabic ? 'عرض السائقين' : 'Show drivers',
          onTap: _listDrivers,
        ),
        TaxiActionButton(
          label: l.isArabic ? 'عرض الرحلات' : 'Show rides',
          onTap: _listRides,
        ),
        SizedBox(
          width: 320,
          child: Row(children:[
            Text(
              l.isArabic ? 'حالة الرحلة (تصفية)' : 'Ride status (filter)',
            ),
            const SizedBox(width:8),
            Expanded(
              child: DropdownButton<String>(
                isExpanded:true,
                value: _rideStatus,
                items: _rideStatuses
                    .map((s)=> DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v){
                  if(v==null) return;
                  setState(()=>_rideStatus=v);
                  _listRides();
                },
              ),
            ),
          ]),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children:[
            Text(
              l.isArabic ? 'حالة السائق (تصفية)' : 'Driver status (filter)',
            ),
            const SizedBox(width:8),
            DropdownButton<String>(
              value: _driverStatus,
              items: _driverStatuses
                  .map((s)=> DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v){
                if(v==null) return;
                setState(()=>_driverStatus=v);
                _listDrivers();
              },
            ),
          ],
        ),
        SizedBox(
          width: 260,
          child: TextField(
            controller: _driverSearchCtrl,
            decoration: InputDecoration(
              labelText: l.isArabic
                  ? 'بحث عن السائق (الاسم، اللوحة، المعرّف)'
                  : 'Search driver (name, plate, id)',
            ),
            onChanged: (v){ setState(()=> _driverQuery = v.trim().toLowerCase()); },
          ),
        ),
      ]),
      const Divider(height: 24),
      Text(
        l.isArabic ? 'تسجيل سائق جديد' : 'Register new driver',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children:[
        SizedBox(width: 220, child: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name'))),
        SizedBox(width: 220, child: TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone'))),
        SizedBox(width: 220, child: TextField(controller: makeCtrl, decoration: const InputDecoration(labelText: 'Vehicle'))),
        SizedBox(width: 220, child: TextField(controller: plateCtrl, decoration: const InputDecoration(labelText: 'Plate'))),
      ]),
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: _registerDriver,
        icon: const Icon(Icons.person_add_alt),
        label: Text(l.isArabic ? 'إنشاء ملف سائق' : 'Create driver'),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () => _driverOnline(true),
              icon: const Icon(Icons.play_arrow),
              label: Text(l.isArabic ? 'تشغيل السائق' : 'Go online'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _driverOnline(false),
              icon: const Icon(Icons.stop),
              label: Text(l.isArabic ? 'إيقاف السائق' : 'Go offline'),
            ),
          ),
        ],
      ),
      if(_driverId != null && _driverId!.isNotEmpty)...[
        const SizedBox(height: 16),
        Text(
          l.isArabic ? 'شحن رصيد السائق (QR)' : 'Driver top-up QR (for driver app)',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        GlassPanel(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if(_driverPhone != null && _driverPhone!.isNotEmpty)
                Text(
                  l.isArabic
                      ? 'هاتف السائق: ${_driverPhone}'
                      : 'Driver phone: ${_driverPhone}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              const SizedBox(height: 8),
              Text(
                l.isArabic
                    ? 'أنشئ رمز QR ليقوم السائق بمسحه في تطبيق السائق لشحن رصيد التاكسي.'
                    : 'Generate a QR code that the driver scans in the driver app to top up their taxi balance.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _topupAmtCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: l.isArabic ? 'المبلغ (ليرة)' : 'Amount (SYP)',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TaxiActionButton(
                    label: l.isArabic ? 'إنشاء QR' : 'Generate QR',
                    onTap: _makeTopupQr,
                  ),
                ],
              ),
              if(_topupQrPayload.isNotEmpty)...[
                const SizedBox(height: 12),
                Center(
                  child: QrImageView(
                    data: _topupQrPayload,
                    size: 180,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ]);

    final lists = loading
      ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 8),
          Text(
            l.isArabic ? 'السائقون (آخر ٥٠)' : 'Drivers (latest 50)',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          ...drivers.where((d){
            try{
              if(_driverQuery.isEmpty) return true;
              final id=(d is Map? (d['id']??'') : '').toString().toLowerCase();
              final name=(d is Map? (d['name']??'') : '').toString().toLowerCase();
              final plate=(d is Map? (d['vehicle_plate']??'') : '').toString().toLowerCase();
              return id.contains(_driverQuery) || name.contains(_driverQuery) || plate.contains(_driverQuery);
            }catch(_){ return true; }
          }).take(50).map((d){
            final id = (d is Map? (d['id']??'') : '').toString();
            final name = (d is Map? (d['name']??'') : '').toString();
            final plate = (d is Map? (d['vehicle_plate']??'') : '').toString();
            final phone = (d is Map? (d['phone']??'') : '').toString();
            final status = (d is Map? (d['status']??'') : '').toString().toLowerCase();
            final bool isOnline = status == 'online';
            final bool isOffline = status == 'offline';
            final isSel = (id.isNotEmpty && id == _driverId);
            return Padding(padding: const EdgeInsets.symmetric(vertical:4), child:
              InkWell(onTap: () async {
                _driverId = id;
                _driverPhone = phone;
                _topupQrPayload = '';
                _topupAmtCtrl.text = '10.00';
                setState((){});
                try{
                  final sp = await SharedPreferences.getInstance();
                  await sp.setString('taxi_driver_id', id);
                }catch(_){ }
                await _loadDriverStats();
              }, child: GlassPanel(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child:
                Row(children:[
                  Icon(
                    Icons.person,
                    size:18,
                    color: isOffline
                        ? Colors.redAccent
                        : (isSel ? Colors.greenAccent : null),
                  ),
                  const SizedBox(width:8),
                  Expanded(
                    child: Text(
                      '$id  ${name.isNotEmpty? '· '+name : ''}  ${plate.isNotEmpty? '· '+plate : ''}',
                      maxLines:2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if(status.isNotEmpty)...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isOnline
                            ? Colors.green.withValues(alpha: .12)
                            : Colors.red.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        l.isArabic
                            ? (isOnline ? 'متصل' : 'غير متصل')
                            : (isOnline ? 'online' : 'offline'),
                        style: TextStyle(
                          color: isOnline
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  if(isSel)...[
                    const SizedBox(width: 6),
                    Text(
                      l.isArabic ? 'محدد' : 'Selected',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ]),
              )),
            );
          }),
          const SizedBox(height: 12),
          Text(
            l.isArabic ? 'الرحلات (آخر ١٢)' : 'Rides (latest 12)',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          ...rides.take(12).map((r)=> Padding(padding: const EdgeInsets.symmetric(vertical:4), child: GlassPanel(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child:
              Text(_rideSummary(r), maxLines: 4, overflow: TextOverflow.ellipsis),
          ))),
        ]);

    final content = ListView(padding: const EdgeInsets.all(12), children:[
      Text(
        l.isArabic ? 'تشغيل سيارات الأجرة' : 'Taxi operator console',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 4),
      Text(
        l.isArabic
            ? 'نظرة مبسّطة على السائقين والرحلات لليوم. استخدم المرشّحات بالأعلى لتضييق النتائج.'
            : 'Simple overview of today’s taxi drivers and rides. Use the filters below to narrow results.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 4),
      Text(
        l.isArabic
            ? 'السائقون: ${drivers.length} · الرحلات: ${rides.length}'
            : 'Drivers: ${drivers.length} · Rides: ${rides.length}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      controls,
      const SizedBox(height: 12),
      if(out.isNotEmpty) SelectableText(out),
      const SizedBox(height: 12),
      lists,
    ]);

    return Scaffold(
      appBar: AppBar(title: Text(L10n.of(context).homeTaxiOperator), backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(children:[
        const TaxiBG(),
        // Full-screen background card for more space
        Positioned.fill(child: SafeArea(child: GlassPanel(padding: const EdgeInsets.all(12), radius: 12, child: content))),
      ]),
    );
  }
}
