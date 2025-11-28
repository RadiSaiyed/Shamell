import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../glass.dart';
import '../format.dart' show fmtCents;
import '../notification_service.dart';
import '../scan_page.dart';
import 'taxi_common.dart' show hdrTaxi, parseTaxiFareOptions, TaxiFareChips, TaxiBG, TaxiSlideButton;
import '../l10n.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'taxi_map_widget.dart';

class TaxiDriverPage extends StatefulWidget {
  final String baseUrl;
  const TaxiDriverPage(this.baseUrl, {super.key});
  @override
  State<TaxiDriverPage> createState() => _TaxiDriverPageState();
}

class _TaxiDriverPageState extends State<TaxiDriverPage> {
  final driverCtrl = TextEditingController();
  String out = '';
  String _activeRiderPhone = '';
  String? _activeRideId;
  String _activeRideStatus = '';
  bool isOnline = false;
  String fareOutDriver = '';
  List<Map<String,dynamic>> _fareOptionsD = [];
  WebSocketChannel? _ws; bool wsConnected = false; int _wsRetries = 0;
  WebSocketChannel? _wsWallet; bool wsWalletConnected = false;
  GoogleMapController? _gmap; LatLng _pos = const LatLng(33.5138, 36.2765); Set<Marker> _markers = {}; List<Marker> _standMarkers = [];
  double? _activePickupLat; double? _activePickupLon; double? _activeDropLat; double? _activeDropLon;
  Set<Polyline> _routeDriver = const {};
  String _routeInfoDriver = '';
  Timer? _fareTimerD; Timer? _incomingPoll; String? _lastNotifiedRideId;
  String? _taxiWalletId; Timer? _walletPoll; String? _lastWalletEventKey;
  int _todayRideCount = 0;
  int _todayEarningsCents = 0;
  double? _avgRating;
  int? _taxiBalanceCents;

  void _scheduleFareEstimateDriver(){ _fareTimerD?.cancel(); _fareTimerD = Timer(const Duration(milliseconds: 700), (){ if(mounted) _fareEstimateDriver(); }); }

  @override void initState(){
    super.initState(); _load(); _connectWs(); _resolveTaxiWallet();
    _incomingPoll = Timer.periodic(const Duration(seconds: 8), (_) async { await _loadActiveRide(); if(_activeRideId!=null && _activeRideId!.isNotEmpty && _activeRideId!=_lastNotifiedRideId){ _lastNotifiedRideId=_activeRideId; _notifyIncoming(); } });
    _walletPoll = Timer.periodic(const Duration(seconds: 15), (_) async { await _pollTaxiWalletIncoming(); });
  }
  Future<void> _load() async {
    final sp=await SharedPreferences.getInstance();
    driverCtrl.text = sp.getString('taxi_driver_id') ?? '';
    if(mounted) setState((){});
    await _registerFcmToken();
  }

  Future<void> _registerFcmToken() async {
    try{
      final sp = await SharedPreferences.getInstance();
      final token = (sp.getString('fcm_token') ?? '').trim();
      var did = driverCtrl.text.trim();
      if (did.isEmpty) {
        did = (sp.getString('taxi_driver_id') ?? '').trim();
      }
      if(token.isEmpty || did.isEmpty) return;
      final uri = Uri.parse('${widget.baseUrl}/taxi/drivers/'+Uri.encodeComponent(did)+'/push_token');
      await http.post(uri, headers: await hdrTaxi(json:true), body: jsonEncode({'fcm_token': token}));
    }catch(_){ }
  }

  Future<void> _online(bool on) async {
    final l = L10n.of(context);
    String did = driverCtrl.text.trim();
    if(did.isEmpty){
      try{
        final sp = await SharedPreferences.getInstance();
        did = (sp.getString('taxi_driver_id') ?? '').trim();
        if(did.isNotEmpty){
          driverCtrl.text = did;
        }
      }catch(_){ }
    }
    if(did.isEmpty){
      if(mounted){
        setState(()=> out = l.isArabic
            ? 'معرّف السائق غير معروف. يرجى تسجيل الدخول كسائق أو تعيين Driver ID من Taxi Admin.'
            : 'Driver ID is not set. Please log in as driver or set it from Taxi Admin.');
      }
      return;
    }
    setState(()=>out='...');
    final ep = on? 'online':'offline';
    final uri=Uri.parse('${widget.baseUrl}/taxi/drivers/$did/$ep');
    final resp=await http.post(uri, headers: await hdrTaxi());
    setState(()=>out='${resp.statusCode}: ${resp.body}');
    if(resp.statusCode==200){
      setState(()=> isOnline=on);
    }
  }
  Future<void> _callRider(String phone) async { final uri=Uri(scheme:'tel', path:phone); try{ await launchUrl(uri); }catch(_){ if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot launch dialer'))); } }
  @override void dispose(){ try{ _incomingPoll?.cancel(); }catch(_){ } try{ _fareTimerD?.cancel(); }catch(_){ } try{ _walletPoll?.cancel(); }catch(_){ } super.dispose(); }

  Future<void> _resolveTaxiWallet() async {
    try{
      var did = driverCtrl.text.trim();
      if(did.isEmpty){ try{ final sp=await SharedPreferences.getInstance(); did = sp.getString('taxi_driver_id') ?? ''; }catch(_){ }
      }
      if(did.isEmpty) return;
      final r = await http.get(Uri.parse('${widget.baseUrl}/taxi/drivers/'+Uri.encodeComponent(did)), headers: await hdrTaxi());
      if(r.statusCode==200){
        final j=jsonDecode(r.body);
        final wid=(j['wallet_id']??'').toString();
        final bal = (j['balance_cents'] ?? 0) as int;
        if(wid.isNotEmpty){
          _taxiWalletId=wid;
          _taxiBalanceCents = bal;
          if(mounted) setState((){});
          _connectWalletWs();
          _loadTodayStats(did);
        }
      }
    }catch(_){ }
  }

  Future<void> _pollTaxiWalletIncoming() async {
    final wid = _taxiWalletId; if(wid==null || wid.isEmpty) return; if(wsWalletConnected) return;
    try{
      final u = Uri.parse('${widget.baseUrl}/payments/txns').replace(queryParameters: {'wallet_id': wid, 'limit':'5', 'dir':'in'});
      final r = await http.get(u);
      if(r.statusCode==200){
        final arr = jsonDecode(r.body) as List;
        if(arr.isNotEmpty){
          final t = arr.first;
          final key = '${t['id']??''}|${t['amount_cents']??0}|${t['created_at']??''}';
          if(key.isNotEmpty && key != _lastWalletEventKey){
            _lastWalletEventKey = key;
            final cents = (t['amount_cents']??0) as int;
            try{ await NotificationService.showWalletCredit(walletId: wid, amountCents: cents, reference: (t['reference']??'').toString()); }catch(_){ }
            try{ HapticFeedback.lightImpact(); }catch(_){ }
            if(mounted){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fare credited: ${fmtCents(cents)} SYP'), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2))); }
            final did = driverCtrl.text.trim();
            if(did.isNotEmpty){ _loadTodayStats(did); }
          }
        }
      }
    }catch(_){ }
  }

  void _connectWalletWs(){
    final wid = _taxiWalletId; if(wid==null || wid.isEmpty) return;
    try{
      final base = widget.baseUrl;
      final uri = Uri.parse(base);
      final wsScheme = (uri.scheme == 'https')? 'wss' : 'ws';
      final wsUrl = Uri(scheme: wsScheme, host: uri.host, port: uri.port, path: '/ws/payments/wallets/'+wid);
      _wsWallet?.sink.close();
      _wsWallet = WebSocketChannel.connect(wsUrl);
      wsWalletConnected = true;
      _wsWallet!.stream.listen((msg){
        try{
          final j = (msg is String)? jsonDecode(msg) : msg;
          if(j is Map && (j['kind']??'') == 'wallet_txn'){
            final cents = (j['amount_cents']??0) as int;
            try{ HapticFeedback.lightImpact(); }catch(_){ }
            if(mounted){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fare credited: \\${fmtCents(cents)} SYP'), duration: const Duration(seconds:2))); }
            final did = driverCtrl.text.trim();
            if(did.isNotEmpty){ _loadTodayStats(did); }
          }
        }catch(_){ }
      }, onDone: (){ wsWalletConnected = false; }, onError: (_){ wsWalletConnected = false; });
    }catch(_){ wsWalletConnected = false; }
  }

  Future<void> _loadTodayStats(String driverId) async {
    try{
      final uri = Uri.parse('${widget.baseUrl}/taxi/drivers/'+Uri.encodeComponent(driverId)+'/stats')
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
              _todayRideCount = ridesCompleted;
              _todayEarningsCents = payout;
              _avgRating = (avg is num)? avg.toDouble() : null;
            });
          }
        }
      }
    }catch(_){ }
  }

  Future<void> _loadActiveRide() async {
    final id = driverCtrl.text.trim();
    if (id.isEmpty) return;
    try{
      final uri = Uri.parse('${widget.baseUrl}/taxi/drivers/'+Uri.encodeComponent(id)+'/rides?limit=1');
      final r = await http.get(uri, headers: await hdrTaxi());
      if(r.statusCode==200){
        final j = jsonDecode(r.body);
        final items = (j is Map && j['items'] is List)
            ? (j['items'] as List)
            : (j is List ? j : []);
        if(items.isNotEmpty){
          final ride = items.first as Map<String, dynamic>;
          final rid = (ride['id']??'').toString();
          _activeRideId = rid.isNotEmpty ? rid : null;
          _activeRideStatus = (ride['status'] ?? '').toString();
          final ph = (ride['rider_phone']??'').toString();
          _activeRiderPhone = ph;
          double? _toD(v){
            if(v==null) return null;
            if(v is num) return v.toDouble();
            return double.tryParse(v.toString());
          }
          final lat = _toD(ride['pickup_lat']) ?? _toD(ride['origin_lat']) ?? _toD((ride['pickup'] is Map? ride['pickup']['lat'] : null));
          final lon = _toD(ride['pickup_lon']) ?? _toD(ride['origin_lon'] ?? ride['origin_lng']) ?? _toD((ride['pickup'] is Map? (ride['pickup']['lon'] ?? ride['pickup']['lng']) : null));
          final dlat = _toD(ride['dropoff_lat']) ?? _toD(ride['dest_lat']) ?? _toD((ride['dropoff'] is Map? ride['dropoff']['lat'] : null));
          final dlon = _toD(ride['dropoff_lon']) ?? _toD(ride['dest_lon'] ?? ride['dest_lng']) ?? _toD((ride['dropoff'] is Map? (ride['dropoff']['lon'] ?? ride['dropoff']['lng']) : null));
          if(lat!=null && lon!=null){
            _activePickupLat = lat;
            _activePickupLon = lon;
            _updateMap(lat, lon);
          }
          if(dlat!=null && dlon!=null){
            _activeDropLat = dlat;
            _activeDropLon = dlon;
          }
          // Refresh route + fare estimate whenever we have both pickup and dropoff.
          if(_activePickupLat != null && _activePickupLon != null && _activeDropLat != null && _activeDropLon != null){
            await _updateRouteDriver();
            _scheduleFareEstimateDriver();
          }else{
            // If we only know pickup, clear route.
            setState(() {
              _routeDriver = const {};
              _routeInfoDriver = '';
            });
          }
        } else {
          // No active rides
          _activeRideId = null;
          _activeRideStatus = '';
          _activeRiderPhone = '';
          _activePickupLat = _activePickupLon = _activeDropLat = _activeDropLon = null;
          _routeDriver = const {};
          _routeInfoDriver = '';
        }
        if(mounted) setState((){});
      }
    }catch(_){ }
  }

  String _toWsUrl(String base, String pathWithQuery){ final u=Uri.parse(base); final scheme=(u.scheme=='https')? 'wss':'ws'; return Uri(scheme:scheme, host:u.host, port:u.hasPort? u.port:null, path: pathWithQuery.split('?').first, query: pathWithQuery.contains('?')? pathWithQuery.split('?')[1] : null).toString(); }
  Future<void> _connectWs() async { try{ var did=driverCtrl.text.trim(); if(did.isEmpty){ try{ final sp=await SharedPreferences.getInstance(); did = sp.getString('taxi_driver_id') ?? ''; }catch(_){ } } if(did.isEmpty){ return; } final url=_toWsUrl(widget.baseUrl, '/ws/taxi/driver?driver_id='+Uri.encodeComponent(did)); _ws?.sink.close(); _ws=WebSocketChannel.connect(Uri.parse(url)); _ws!.stream.listen((msg){ setState(()=>out='WS: '+msg.toString()); _wsRetries=0; _loadActiveRide(); _notifyIncoming(); }, onDone: (){ setState(()=>wsConnected=false); final backoff = (_wsRetries<=0)? 1 : (1<<_wsRetries); final delay=Duration(seconds: backoff>32? 32:backoff); _wsRetries = (_wsRetries<10)? _wsRetries+1 : _wsRetries; Future.delayed(delay, (){ if(!wsConnected) _connectWs(); }); }, onError: (_){ setState(()=>wsConnected=false); }); setState((){ wsConnected=true; _wsRetries=0; }); }catch(e){ setState(()=>out='ws error: $e'); } }

  void _notifyIncoming(){
    try{ HapticFeedback.heavyImpact(); }catch(_){ }
    try{ SystemSound.play(SystemSoundType.click); }catch(_){ }
    // Local notification so der Fahrer auch bei minimierter App etwas sieht
    final rid = _activeRideId ?? '';
    if(rid.isNotEmpty){
      try{ NotificationService.showIncomingRide(rideId: rid, riderPhone: _activeRiderPhone); }catch(_){ }
    }
    if(!mounted) return;
    final l = L10n.of(context);
    final sb=SnackBar(
      content: Text(l.taxiIncomingRide),
      action: SnackBarAction(
        label: l.isArabic ? 'قبول' : 'Accept',
        onPressed: _acceptRide,
      ),
      duration: const Duration(seconds:6),
      behavior: SnackBarBehavior.floating,
    );
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(sb);
    Future.delayed(const Duration(milliseconds: 200), (){
      if(!mounted) return;
      final sb2=SnackBar(
        content: Text(l.taxiDenyRequest),
        action: SnackBarAction(
          label: l.isArabic ? 'رفض' : 'Deny',
          onPressed: _denyRide,
        ),
        duration: const Duration(seconds:4),
        behavior: SnackBarBehavior.floating,
      );
      ScaffoldMessenger.of(context).showSnackBar(sb2);
    });
  }

  Future<void> _fareEstimateDriver() async {
    setState(()=> fareOutDriver = '...');
    try{
      final pLat = _activePickupLat ?? 0.0;
      final pLon = _activePickupLon ?? 0.0;
      final dLat = _activeDropLat ?? 0.0;
      final dLon = _activeDropLon ?? 0.0;
      final uri = Uri.parse('${widget.baseUrl}/taxi/rides/quote');
      final body = jsonEncode({'pickup_lat': pLat, 'pickup_lon': pLon, 'dropoff_lat': dLat, 'dropoff_lon': dLon});
      final r = await http.post(uri, headers: await hdrTaxi(json:true), body: body);
      if(r.statusCode==200){
        try{
          final j=jsonDecode(r.body);
          _fareOptionsD = parseTaxiFareOptions(j);
          if(_fareOptionsD.isNotEmpty){
            // Chips take care of per-type fares.
            fareOutDriver = '';
          } else {
            final cents=(j['price_cents']??j['fare_cents']??0) as int;
            final fee=(j['broker_fee_cents']??0) as int;
            if(cents>0 && fee>0){
              final payout = cents - fee;
              fareOutDriver = 'Estimated fare: ${fmtCents(cents)} SYP · payout: ${fmtCents(payout)} SYP (fee ${fmtCents(fee)} SYP)';
            } else if(cents>0){
              fareOutDriver = 'Estimated fare: ${fmtCents(cents)} SYP';
            } else {
              fareOutDriver = r.body;
            }
          }
        } catch(_){
          fareOutDriver = r.body; _fareOptionsD=[];
        }
      }
      else { fareOutDriver = '${r.statusCode}: ${r.body}'; }
    }catch(e){ fareOutDriver = 'error: $e'; }
    if(mounted) setState((){});
  }

  Future<void> _updateRouteDriver() async {
    final lat1 = _activePickupLat;
    final lon1 = _activePickupLon;
    final lat2 = _activeDropLat;
    final lon2 = _activeDropLon;
    if(lat1 == null || lon1 == null || lat2 == null || lon2 == null){
      setState((){
        _routeDriver = const {};
        _routeInfoDriver = '';
      });
      return;
    }
    try{
      final uri = Uri.parse('${widget.baseUrl}/osm/route').replace(queryParameters: {
        'start_lat': lat1.toString(),
        'start_lon': lon1.toString(),
        'end_lat': lat2.toString(),
        'end_lon': lon2.toString(),
      });
      final resp = await http.get(uri);
      if(resp.statusCode == 200){
        final j = jsonDecode(resp.body);
        final pts = <LatLng>[];
        try{
          final raw = j['points'];
          if(raw is List){
            for(final p in raw){
              if(p is List && p.length >= 2){
                final la = (p[0] as num).toDouble();
                final lo = (p[1] as num).toDouble();
                pts.add(LatLng(la, lo));
              }
            }
          }
        }catch(_){ }
        if(pts.isEmpty){
          pts.add(LatLng(lat1, lon1));
          pts.add(LatLng(lat2, lon2));
        }
        final routeColor = Theme.of(context).brightness==Brightness.dark? Colors.white : Colors.black;
        double distKm = 0.0;
        int etaMin = 0;
        try{
          final distM = (j['distance_m'] as num?)?.toDouble() ?? 0.0;
          final durS = (j['duration_s'] as num?)?.toDouble() ?? 0.0;
          distKm = distM / 1000.0;
          etaMin = (durS / 60.0).ceil();
        }catch(_){ }
        final l = L10n.of(context);
        setState((){
          _routeDriver = {
            Polyline(
              polylineId: const PolylineId('driver-route'),
              points: pts,
              color: routeColor,
              width: 5,
            ),
          };
          if(distKm > 0 && etaMin > 0){
            _routeInfoDriver = l.isArabic
                ? 'المسافة: ${distKm.toStringAsFixed(2)} كم · الوقت التقريبي: ${etaMin} دقيقة'
                : 'Distance: ${distKm.toStringAsFixed(2)} km · ETA: ${etaMin} min';
          }else{
            _routeInfoDriver = '';
          }
        });
      }else{
        setState((){
          _routeDriver = const {};
          _routeInfoDriver = '';
        });
      }
    }catch(_){
      setState((){
        _routeDriver = const {};
        _routeInfoDriver = '';
      });
    }
  }

  Future<void> _acceptRide() async {
    final l = L10n.of(context);
    var rid = _activeRideId; var did = driverCtrl.text.trim();
    if((rid==null || rid.isEmpty) || did.isEmpty){ await _loadActiveRide(); rid = _activeRideId; }
    if((rid==null || rid.isEmpty) || did.isEmpty){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.taxiNoActiveRide)));
      return;
    }
    setState(()=>out='...');
    try{
      final uri=Uri.parse('${widget.baseUrl}/taxi/rides/'+Uri.encodeComponent(rid)+'/accept').replace(queryParameters:{'driver_id':did});
      final r=await http.post(uri, headers: await hdrTaxi());
      setState(()=>out='${r.statusCode}: ${r.body}');
      await _loadActiveRide();
    }catch(e){ setState(()=>out='error: $e'); }
  }

  Future<void> _denyRide() async {
    final l = L10n.of(context);
    if(_activeRideId==null || _activeRideId!.isEmpty){ await _loadActiveRide(); }
    final rid=_activeRideId;
    if(rid==null || rid.isEmpty){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.taxiNoActiveRide)));
      return;
    }
    setState(()=>out='...');
    try{
      final uri=Uri.parse('${widget.baseUrl}/taxi/rides/'+Uri.encodeComponent(rid)+'/deny');
      final r=await http.post(uri, headers: await hdrTaxi());
      setState(()=>out='${r.statusCode}: ${r.body}');
      await _loadActiveRide();
    }catch(e){ setState(()=>out='error: $e'); }
  }

  Future<void> _startRide() async {
    final l = L10n.of(context);
    var rid=_activeRideId; final did=driverCtrl.text.trim();
    if(rid==null || rid.isEmpty || did.isEmpty){ await _loadActiveRide(); rid=_activeRideId; }
    if(rid==null || rid.isEmpty){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.taxiNoActiveRide)));
      return;
    }
    setState(()=>out='...');
    try{
      final uri=Uri.parse('${widget.baseUrl}/taxi/rides/'+Uri.encodeComponent(rid)+'/start').replace(queryParameters:{'driver_id':did});
      final r=await http.post(uri, headers: await hdrTaxi());
      setState(()=>out='${r.statusCode}: ${r.body}');
      final lat = _activeDropLat ?? _activePickupLat;
      final lon = _activeDropLon ?? _activePickupLon;
      if(lat!=null && lon!=null){
        final dest='${lat.toStringAsFixed(6)},${lon.toStringAsFixed(6)}';
        final googleNav=Uri.parse('google.navigation:q='+dest+'&mode=d');
        try{
          if(await canLaunchUrl(googleNav)){
            await launchUrl(googleNav, mode: LaunchMode.externalApplication);
          } else {
            final gmaps=Uri.parse('https://www.google.com/maps/dir/?api=1&destination='+dest+'&travelmode=driving');
            await launchUrl(gmaps, mode: LaunchMode.externalApplication);
          }
        }catch(_){ }
      }
      await _loadActiveRide();
    }catch(e){ setState(()=>out='error: $e'); }
  }

  Future<void> _completeRide() async {
    final l = L10n.of(context);
    var rid=_activeRideId; final did=driverCtrl.text.trim();
    if(rid==null || rid.isEmpty || did.isEmpty){ await _loadActiveRide(); rid=_activeRideId; }
    if(rid==null || rid.isEmpty){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.taxiNoActiveRide)));
      return;
    }
    setState(()=>out='...');
    try{
      final uri=Uri.parse('${widget.baseUrl}/taxi/rides/'+Uri.encodeComponent(rid)+'/complete').replace(queryParameters:{'driver_id':did});
      final r=await http.post(uri, headers: await hdrTaxi());
      setState(()=>out='${r.statusCode}: ${r.body}');
      await _loadActiveRide();
    }catch(e){ setState(()=>out='error: $e'); }
  }

  Future<void> _scanTopupQr() async {
    try{
      final raw = await Navigator.push<String>(context, MaterialPageRoute(builder: (_)=> const ScanPage()));
      if(raw==null || raw.isEmpty) return;
      await _redeemTopup(raw);
    }catch(e){
      if(mounted){
        final l = L10n.of(context);
        setState(()=> out = '${l.taxiTopupScanErrorPrefix}: $e');
      }
    }
  }

  Future<void> _redeemTopup(String payload) async {
    setState(()=> out='Topup: ...');
    try{
      final uri = Uri.parse('${widget.baseUrl}/taxi/topup_qr/redeem');
      final resp = await http.post(uri, headers: await hdrTaxi(json:true), body: jsonEncode({'payload': payload}));
      try{
        final body = jsonDecode(resp.body);
        if(body is Map<String,dynamic>){
          final bal = body['balance_cents'];
          if(bal is int){
            _taxiBalanceCents = bal;
          }else if(bal is String){
            _taxiBalanceCents = int.tryParse(bal);
          }
        }
      }catch(_){}
      setState(()=> out='${resp.statusCode}: ${resp.body}');
      final did = driverCtrl.text.trim();
      if(did.isNotEmpty){
        await _loadTodayStats(did);
      }
    }catch(e){
      if(mounted){
        final l = L10n.of(context);
        setState(()=> out = '${l.taxiTopupErrorPrefix}: $e');
      }
    }
  }

  void _updateMap(double lat, double lon){ _pos=LatLng(lat,lon); _markers={ Marker(markerId: const MarkerId('driver'), position: _pos) }; try{ _gmap?.animateCamera(CameraUpdate.newLatLngZoom(_pos, 14)); }catch(_){ } if(mounted) setState((){}); }

  Future<void> _loadTaxiStands() async {
    try{
      const delta = 0.02;
      final params = {
        'south': (_pos.latitude - delta).toString(),
        'west': (_pos.longitude - delta).toString(),
        'north': (_pos.latitude + delta).toString(),
        'east': (_pos.longitude + delta).toString(),
      };
      final uri = Uri.parse('${widget.baseUrl}/osm/taxi_stands').replace(queryParameters: params);
      final resp = await http.get(uri);
      if(resp.statusCode==200){
        final data = jsonDecode(resp.body);
        final stands = <Marker>[];
        if(data is List){
          for(final item in data){
            if(item is Map<String,dynamic>){
              final lat = (item['lat'] as num?)?.toDouble();
              final lon = (item['lon'] as num?)?.toDouble();
              if(lat==null || lon==null) continue;
              final id = (item['id'] ?? '${lat}_${lon}').toString();
              final name = (item['name'] ?? '').toString();
              stands.add(Marker(
                markerId: MarkerId('stand-$id'),
                position: LatLng(lat, lon),
                infoWindow: InfoWindow(title: name.isNotEmpty ? name : 'Taxi stand'),
              ));
            }
          }
        }
        if(mounted) setState(()=> _standMarkers = stands);
      } else {
        if(mounted) setState(()=> out='Taxi stands error: ${resp.statusCode}: ${resp.body}');
      }
    }catch(e){
      if(mounted) setState(()=> out='Taxi stands error: $e');
    }
  }

  @override Widget build(BuildContext context){
    final l = L10n.of(context);
    final hasRide = _activeRideId != null && _activeRideId!.isNotEmpty;
    final statusLabel = !hasRide
        ? (l.isArabic ? 'لا توجد رحلة نشطة' : 'No active ride')
        : (_activeRideStatus.isEmpty
            ? (l.isArabic ? 'حالة الرحلة: قيد الانتظار' : 'Ride status: pending')
            : (l.isArabic ? 'حالة الرحلة: $_activeRideStatus' : 'Ride status: $_activeRideStatus'));
    final todayLabel = (_todayRideCount<=0 && _todayEarningsCents<=0)
        ? (l.isArabic ? 'اليوم: لا يوجد أرباح بعد' : 'Today: no payouts yet')
        : (l.isArabic
            ? 'اليوم: $_todayRideCount رحلات · ${fmtCents(_todayEarningsCents)} SYP أرباح (بعد عمولة المنصة)'
              + (_avgRating!=null ? ' · ★ ${_avgRating!.toStringAsFixed(1)}' : '')
            : 'Today: $_todayRideCount rides · ${fmtCents(_todayEarningsCents)} SYP payout (after platform commission)'
              + (_avgRating!=null ? ' · ★ ${_avgRating!.toStringAsFixed(1)}' : ''));
    final balanceLabel = _taxiBalanceCents == null
        ? (l.isArabic ? 'رصيد التاكسي: غير متوفر' : 'Taxi balance: not available')
        : (l.isArabic
            ? 'رصيد التاكسي (وديعة): ${fmtCents(_taxiBalanceCents!)} SYP'
            : 'Taxi balance (deposit): ${fmtCents(_taxiBalanceCents!)} SYP');

    final markers = _markers.union(_standMarkers.toSet());
    final content = Column(children:[
      Expanded(child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: TaxiMapWidget(
          center: _pos,
          initialZoom: 13,
          markers: markers,
          myLocationEnabled: true,
          onMapCreated: (c){ if(c is GoogleMapController){ _gmap=c; } },
          polylines: _routeDriver,
        ),
      )),
      const SizedBox(height:8),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children:[
        Row(children:[
          Text(l.isArabic ? 'متصل' : 'Online'),
          const SizedBox(width:8),
          Switch(value: isOnline, onChanged: (v){ _online(v); }),
          const Spacer(),
          Text(todayLabel, style: const TextStyle(fontSize: 11)),
        ]),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.local_taxi, size: 16),
            label: Text(l.isArabic ? 'مواقف التاكسي القريبة' : 'Taxi stands nearby'),
            onPressed: () async {
              try{ HapticFeedback.lightImpact(); }catch(_){ }
              await _loadTaxiStands();
            },
          ),
        ),
        const SizedBox(height:8),
        Text(balanceLabel, style: const TextStyle(fontSize: 12)),
        const SizedBox(height:4),
        Text(statusLabel, style: const TextStyle(fontSize: 12)),
        const SizedBox(height:8),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children:[
          Text(l.isArabic ? 'تقدير الأجرة والمسار:' : 'Fare & route:'), const SizedBox(height:6),
          if(_fareOptionsD.isNotEmpty) TaxiFareChips(options: _fareOptionsD, selected: null, onSelected: (_){ }),
          if(_fareOptionsD.isEmpty && fareOutDriver.isNotEmpty) SelectableText(fareOutDriver),
          if(_routeInfoDriver.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _routeInfoDriver,
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ]),
        const SizedBox(height:8),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children:[
          Text(l.isArabic ? 'إجراءات' : 'Actions', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          if(hasRide && (_activeRideStatus=='requested' || _activeRideStatus=='assigned')) ...[
            TaxiSlideButton(label: l.isArabic ? 'قبول الرحلة' : 'Accept ride', onConfirm: _acceptRide),
            const SizedBox(height: 8),
            TaxiSlideButton(label: l.isArabic ? 'رفض الرحلة' : 'Deny ride', onConfirm: _denyRide),
            const SizedBox(height: 8),
          ] else if(!hasRide) ...[
            Text(l.isArabic ? 'في انتظار طلبات الرحلات…' : 'Waiting for ride requests…', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
          ],
          if(hasRide && _activeRideStatus=='accepted') ...[
            TaxiSlideButton(label: l.isArabic ? 'بدء الرحلة' : 'Start ride', onConfirm: _startRide),
            const SizedBox(height: 8),
          ],
          if(hasRide && _activeRideStatus=='on_trip') ...[
            TaxiSlideButton(label: l.isArabic ? 'إنهاء الرحلة' : 'Complete ride', onConfirm: _completeRide),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: (){
                    if(_activeRiderPhone.isEmpty){
                      _loadActiveRide();
                    } else {
                      _callRider(_activeRiderPhone);
                    }
                  },
                  icon: const Icon(Icons.phone),
                  label: Text(
                    _activeRiderPhone.isEmpty
                        ? (l.isArabic ? 'الاتصال بالراكب' : 'Call rider')
                        : (l.isArabic ? 'الاتصال $_activeRiderPhone' : 'Call $_activeRiderPhone'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _scanTopupQr,
                  icon: const Icon(Icons.qr_code_2),
                  label: Text(
                    l.isArabic
                        ? 'شحن عبر رمز QR'
                        : 'Top up via QR',
                  ),
                ),
              ),
            ],
          ),
        ]),
        if(out.isNotEmpty) const SizedBox(height:8),
        if(out.isNotEmpty) SelectableText(out),
      ]),
    ]);
    return Scaffold(
      appBar: AppBar(title: Text(l.isArabic ? 'سائق تاكسي' : 'Taxi Driver'), backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(children:[
        const TaxiBG(),
        // Full-screen background card like Operator
        Positioned.fill(child: SafeArea(child: GlassPanel(padding: const EdgeInsets.all(12), radius: 12, child: content))),
      ]),
    );
  }
}
