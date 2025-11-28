import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../glass.dart';
import '../ui_kit.dart';
import '../format.dart' show fmtCents;
import '../config.dart';
import '../taxi/taxi_common.dart' show hdrTaxi, parseTaxiFareOptions, TaxiFareChips, TaxiBG, TaxiSlideButton;
import '../l10n.dart';
import '../perf.dart';
import '../status_banner.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'taxi_map_widget.dart';

class TaxiRiderPage extends StatefulWidget {
  final String baseUrl;
  const TaxiRiderPage(this.baseUrl, {super.key});
  @override
  State<TaxiRiderPage> createState() => _TaxiRiderPageState();
}

class _TaxiRiderPageState extends State<TaxiRiderPage> {
  // When true, hide all buttons/interactive controls and show only address fields
  static const bool _minimalRider = false;
  final FocusNode _pickupFocus = FocusNode();
  final FocusNode _dropFocus = FocusNode();
  final pickupAddrCtrl = TextEditingController();
  final dropAddrCtrl = TextEditingController();
  final platCtrl = TextEditingController();
  final plonCtrl = TextEditingController();
  final dlatCtrl = TextEditingController();
  final dlonCtrl = TextEditingController();
  final rideCtrl = TextEditingController();
  String out = '';
  String _riderWalletId = '';
  String _riderPhone = '';
  String _rideStatus = '';
  String _driverName = '';
  String _driverVehicle = '';
  String _driverPlate = '';
  bool _hasRated = false;
  String _bannerMsg = '';
  StatusKind _bannerKind = StatusKind.info;

  GoogleMapController? _gmapR;
  LatLng _pickup = const LatLng(33.5138, 36.2765);
  LatLng? _drop;
  bool _setPickup = true;
  List<Marker> _standMarkersR = [];
  Set<Marker> get _markersR {
    final m=<Marker>{ Marker(markerId: const MarkerId('pickup'), position: _pickup, infoWindow: const InfoWindow(title:'Pickup')) };
    if(_drop!=null) m.add(Marker(markerId: const MarkerId('drop'), position: _drop!, infoWindow: const InfoWindow(title:'Dropoff')));
    if(_standMarkersR.isNotEmpty) m.addAll(_standMarkersR);
    return m;
  }
  Set<Polyline> _route = {};
  String _routeInfo = '';
  // Multiple route alternatives (e.g. from TomTom /osm/route)
  List<List<LatLng>> _routeOptions = [];
  List<Map<String, num>> _routeOptionStats = [];
  int _selectedRouteIndex = 0;
  String? _gmapsKey;
  String _nearestDriverText = '';
  String fareOut = '';
  List<Map<String,dynamic>> _fareOptions = [];
  String? _selectedVehicleType;
  Timer? _fareTimerR; Timer? _addrTimerR; Timer? _statusTimerR;

  void _scheduleFareEstimateRider(){
    _fareTimerR?.cancel();
    _fareTimerR = Timer(const Duration(milliseconds: 700), (){
      if(!mounted) return;
      // Fare estimate and nearest driver lookup can run in parallel.
      _fareEstimateRider();
      _loadNearestDriver();
    });
  }

  @override
  void initState(){
    super.initState();
    _loadWallet();
    pickupAddrCtrl.addListener(()=> _onAddrChanged(true));
    dropAddrCtrl.addListener(()=> _onAddrChanged(false));
    _pickupFocus.addListener((){ if(_pickupFocus.hasFocus) setState((){ _setPickup=true; }); });
    _dropFocus.addListener((){ if(_dropFocus.hasFocus) setState((){ _setPickup=false; }); });
    _prefillPickupFromGps();
    _statusTimerR = Timer.periodic(const Duration(seconds: 10), (_) async { try{ if(rideCtrl.text.trim().isNotEmpty){ await _status(); } }catch(_){ } });
  }
  @override
  void dispose(){
    try{ _fareTimerR?.cancel(); }catch(_){ }
    try{ _addrTimerR?.cancel(); }catch(_){ }
    try{ _statusTimerR?.cancel(); }catch(_){ }
    try{ _pickupFocus.dispose(); }catch(_){ }
    try{ _dropFocus.dispose(); }catch(_){ }
    super.dispose();
  }

  Future<void> _loadWallet() async {
    try{
      final sp = await SharedPreferences.getInstance();
      _riderWalletId = sp.getString('wallet_id') ?? '';
      _riderPhone = sp.getString('phone') ?? '';
      if(mounted) setState((){});
    }catch(_){ }
  }

  void _onAddrChanged(bool pickup){
    _addrTimerR?.cancel();
    _addrTimerR = Timer(const Duration(milliseconds: 700), (){ if(mounted) _geocodeRider(pickup); });
  }

  Future<void> _prefillPickupFromGps() async {
    try{
      bool svc = await Geolocator.isLocationServiceEnabled(); if(!svc) return;
      LocationPermission p = await Geolocator.checkPermission(); if(p == LocationPermission.denied){ p = await Geolocator.requestPermission(); }
      if(p == LocationPermission.denied || p == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      _pickup = LatLng(pos.latitude, pos.longitude);
      _gmapR?.animateCamera(CameraUpdate.newLatLngZoom(_pickup, 14));
      await _reverseGeocodeRider(true);
      _scheduleFareEstimateRider();
      if(mounted){
        setState((){});
        try{ HapticFeedback.lightImpact(); }catch(_){ }
        try{
          final l = L10n.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                l.isArabic ? 'تم تعيين نقطة الانطلاق على موقعك الحالي' : 'Pickup set to current location',
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }catch(_){ }
      }
    }catch(_){ }
  }

  void _applyRideJson(Map<String,dynamic> ride){
    try{
      _rideStatus = (ride['status'] ?? '').toString();
      _driverName = (ride['driver_name'] ?? ride['driver'] ?? '').toString();
      _driverVehicle = (ride['vehicle_make'] ?? ride['vehicle'] ?? '').toString();
      _driverPlate = (ride['vehicle_plate'] ?? ride['plate'] ?? '').toString();
    }catch(_){ }
  }

  Future<void> _fareEstimateRider() async {
    if(_drop==null){ setState(()=> fareOut=''); return; }
    setState(()=> fareOut = '...');
    final t0 = DateTime.now().millisecondsSinceEpoch;
    try{
      final pLat = _pickup.latitude; final pLon = _pickup.longitude;
      final dLat = _drop!.latitude; final dLon = _drop!.longitude;
      final uri = Uri.parse('${widget.baseUrl}/taxi/rides/quote');
      final body = jsonEncode({'pickup_lat': pLat, 'pickup_lon': pLon, 'dropoff_lat': dLat, 'dropoff_lon': dLon});
      final r = await http.post(uri, headers: await hdrTaxi(json:true), body: body);
      if(r.statusCode==200){
        try{
          final j=jsonDecode(r.body);
          final opts=parseTaxiFareOptions(j);
          _fareOptions = opts;
          if(opts.isNotEmpty){
            // Chips show per-type fares; keep text minimal.
            fareOut = '';
          } else {
            final cents=(j['price_cents']??j['fare_cents']??0) as int;
            final fee=(j['broker_fee_cents']??0) as int;
            if(cents>0 && fee>0){
              final payout = cents - fee;
              fareOut = 'Estimated fare: ${fmtCents(cents)} SYP (incl. ${fmtCents(fee)} SYP service fee, driver gets ${fmtCents(payout)} SYP)';
            } else if(cents>0){
              fareOut = 'Estimated fare: ${fmtCents(cents)} SYP';
            } else {
              fareOut = r.body;
            }
          }
        }catch(_){ fareOut = r.body; _fareOptions=[]; }
        final dt = DateTime.now().millisecondsSinceEpoch - t0;
        Perf.action('taxi_quote_ok'); Perf.sample('taxi_quote_ms', dt);
        setState(() {
          _bannerKind = StatusKind.info;
          _bannerMsg = L10n.of(context).isArabic ? 'تم تحديث تقدير الأجرة' : 'Fare estimate updated';
        });
      } else {
        fareOut = '${r.statusCode}: ${r.body}';
        Perf.action('taxi_quote_fail');
        setState(() {
          _bannerKind = StatusKind.error;
          _bannerMsg = L10n.of(context).isArabic ? 'تعذر حساب الأجرة' : 'Could not calculate fare';
        });
      }
    }catch(e){
      fareOut = 'error: $e';
      Perf.action('taxi_quote_error');
      setState(() {
        _bannerKind = StatusKind.error;
        _bannerMsg = L10n.of(context).isArabic ? 'خطأ في حساب الأجرة' : 'Error while calculating fare';
      });
    }
    if(mounted) setState((){});
  }

  Future<void> _bookPay() async {
    setState(()=>out='...');
    final t0 = DateTime.now().millisecondsSinceEpoch;
    final uri = Uri.parse('${widget.baseUrl}/taxi/rides/book_pay');
    final payload = <String, dynamic>{
      'pickup_lat': double.tryParse(platCtrl.text.trim())??_pickup.latitude,
      'pickup_lon': double.tryParse(plonCtrl.text.trim())??_pickup.longitude,
      'dropoff_lat': double.tryParse(dlatCtrl.text.trim())??(_drop?.latitude ?? 0.0),
      'dropoff_lon': double.tryParse(dlonCtrl.text.trim())??(_drop?.longitude ?? 0.0),
      if(_selectedVehicleType!=null && _selectedVehicleType!.isNotEmpty) 'vehicle_class': _selectedVehicleType,
      if(_riderWalletId.isNotEmpty) 'rider_wallet_id': _riderWalletId,
      if(_riderPhone.isNotEmpty) 'rider_phone': _riderPhone,
    };
    final body = jsonEncode(payload);
    try{
      final resp = await http.post(uri, headers: await hdrTaxi(json:true), body: body);
      setState(()=>out='${resp.statusCode}: ${resp.body}');
      try{
        final j=jsonDecode(resp.body);
        if(j is Map<String,dynamic>){
          final id=(j['id']??'').toString();
          if(id.isNotEmpty) rideCtrl.text = id;
          _applyRideJson(j);
          final dt = DateTime.now().millisecondsSinceEpoch - t0;
          Perf.action('taxi_book_ok'); Perf.sample('taxi_book_ms', dt);
          final l = L10n.of(context);
          setState(() {
            _bannerKind = StatusKind.success;
            _bannerMsg = l.isArabic ? 'تم طلب الرحلة بنجاح' : 'Ride requested successfully';
          });
        } else {
          final dt = DateTime.now().millisecondsSinceEpoch - t0;
          Perf.action('taxi_book_fail'); Perf.sample('taxi_book_ms', dt);
          final l = L10n.of(context);
          setState(() {
            _bannerKind = StatusKind.error;
            _bannerMsg = l.isArabic ? 'تعذر إنشاء الرحلة' : 'Could not create ride';
          });
        }
      }catch(_){
        final dt = DateTime.now().millisecondsSinceEpoch - t0;
        Perf.action('taxi_book_fail'); Perf.sample('taxi_book_ms', dt);
        final l = L10n.of(context);
        setState(() {
          _bannerKind = StatusKind.error;
          _bannerMsg = l.isArabic ? 'تعذر إنشاء الرحلة' : 'Could not create ride';
        });
      }
    }catch(e){
      setState(()=>out='error: $e');
      Perf.action('taxi_book_error');
      final l = L10n.of(context);
      setState(() {
        _bannerKind = StatusKind.error;
        _bannerMsg = l.isArabic ? 'خطأ أثناء طلب الرحلة' : 'Error while requesting ride';
      });
    }
  }

  Future<void> _status() async {
    if(rideCtrl.text.trim().isEmpty) return;
    setState(()=>out='...');
    final uri = Uri.parse('${widget.baseUrl}/taxi/rides/${rideCtrl.text.trim()}');
    final t0 = DateTime.now().millisecondsSinceEpoch;
    try{
      final resp = await http.get(uri, headers: await hdrTaxi());
      final body = resp.body;
      setState(()=>out='${resp.statusCode}: $body');
      final j = jsonDecode(body);
      if(j is Map<String,dynamic>){
        _applyRideJson(j);
        if(_rideStatus == 'completed' && !_hasRated){
          _showRatingDialog();
        }
        final dt = DateTime.now().millisecondsSinceEpoch - t0;
        Perf.action('taxi_status_ok'); Perf.sample('taxi_status_ms', dt);
        final l = L10n.of(context);
        setState(() {
          _bannerKind = StatusKind.info;
          _bannerMsg = l.isArabic
              ? 'حالة الرحلة: ${_rideStatus}'
              : 'Ride status: ${_rideStatus}';
        });
      }else{
        Perf.action('taxi_status_fail');
        final l = L10n.of(context);
        setState(() {
          _bannerKind = StatusKind.error;
          _bannerMsg = l.isArabic ? 'تعذر قراءة حالة الرحلة' : 'Could not read ride status';
        });
      }
    }catch(_){
      setState(()=>out='status error');
      Perf.action('taxi_status_error');
      final l = L10n.of(context);
      setState(() {
        _bannerKind = StatusKind.error;
        _bannerMsg = l.isArabic ? 'خطأ أثناء جلب حالة الرحلة' : 'Error while fetching ride status';
      });
    }
  }

  Future<void> _cancel() async {
    if(rideCtrl.text.trim().isEmpty) return;
    setState(()=>out='...');
    final uri = Uri.parse('${widget.baseUrl}/taxi/rides/${rideCtrl.text.trim()}/cancel');
    final resp = await http.post(uri, headers: await hdrTaxi());
    setState(()=>out='${resp.statusCode}: ${resp.body}');
  }

  Future<void> _submitRating(int stars, String comment) async {
    final rid = rideCtrl.text.trim();
    if(rid.isEmpty || stars<=0) return;
    try{
      final uri = Uri.parse('${widget.baseUrl}/taxi/rides/'+Uri.encodeComponent(rid)+'/rating');
      final body = jsonEncode({'rating': stars, if(comment.trim().isNotEmpty) 'comment': comment.trim()});
      await http.post(uri, headers: await hdrTaxi(json:true), body: body);
    }catch(_){ }
    if(mounted) setState(()=> _hasRated = true);
  }

  void _showRatingDialog(){
    final ctx = context;
    int selected = 5;
    final commentCtrl = TextEditingController();
    showDialog(context: ctx, builder: (dCtx){
      return AlertDialog(
        title: const Text('Rate your ride'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatefulBuilder(builder: (c, setStateSB){
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i){
                  final filled = i < selected;
                  return IconButton(
                    icon: Icon(filled? Icons.star : Icons.star_border, color: filled? Colors.amber : Colors.grey),
                    onPressed: (){ setStateSB(()=> selected = i+1); },
                  );
                }),
              );
            }),
            const SizedBox(height: 8),
            TextField(
              controller: commentCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Comment (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: ()=> Navigator.pop(dCtx), child: const Text('Skip')),
          FilledButton(
            onPressed: () async {
              await _submitRating(selected, commentCtrl.text);
              if(mounted){
                Navigator.pop(dCtx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanks for your feedback')));
              }
            },
            child: const Text('Submit'),
          ),
        ],
      );
    });
  }

  Future<void> _geocodeRider(bool pickup) async {
    try{
      final q = pickup? pickupAddrCtrl.text.trim() : dropAddrCtrl.text.trim();
      if(q.isEmpty) return;
      if(useOsmMaps){
        final uri = Uri.parse('${widget.baseUrl}/osm/geocode').replace(queryParameters: {'q': q});
        final resp = await http.get(uri);
        if(resp.statusCode==200){
          final data = jsonDecode(resp.body);
          if(data is List && data.isNotEmpty){
            final first = data.first;
            final lat = double.tryParse((first['lat'] ?? '').toString());
            final lon = double.tryParse((first['lon'] ?? '').toString());
            if(lat!=null && lon!=null){
              final ll = LatLng(lat, lon);
              if(pickup){ _pickup=ll; } else { _drop=ll; }
              _updateRoute();
              setState((){});
              _scheduleFareEstimateRider();
              return;
            }
          }
        }
      } else {
        await _ensureGmapsKey();
        final locs = await locationFromAddress(q);
        if(locs.isNotEmpty){
          final ll = LatLng(locs.first.latitude, locs.first.longitude);
          if(pickup){ _pickup=ll; } else { _drop=ll; }
          _gmapR?.animateCamera(CameraUpdate.newLatLngZoom(ll, 14));
          _updateRoute();
          setState((){});
          _scheduleFareEstimateRider();
        }
      }
    }catch(e){
      final l = L10n.of(context);
      Perf.action('taxi_geocode_error');
      setState(()=>out = l.isArabic ? 'خطأ في تحديد الموقع: $e' : 'Geocode error: $e');
    }
  }
  Future<void> _reverseGeocodeRider(bool pickup) async {
    try{
      final ll = pickup? _pickup : (_drop ?? _pickup);
      if(useOsmMaps){
        final uri = Uri.parse('${widget.baseUrl}/osm/reverse').replace(queryParameters: {
          'lat': ll.latitude.toString(),
          'lon': ll.longitude.toString(),
        });
        final resp = await http.get(uri);
        if(resp.statusCode==200){
          final j = jsonDecode(resp.body);
          if(j is Map){
            final addr = (j['display_name'] ?? '').toString();
            if(addr.isNotEmpty){
              if(pickup) pickupAddrCtrl.text = addr; else dropAddrCtrl.text = addr;
              _scheduleFareEstimateRider();
            }
          }
        }
      } else {
        final places = await placemarkFromCoordinates(ll.latitude, ll.longitude);
        if(places.isNotEmpty){
          final p = places.first;
          final addr = [p.street, p.locality, p.country].where((e)=> (e ?? '').isNotEmpty).join(', ');
          if(pickup) pickupAddrCtrl.text = addr; else dropAddrCtrl.text = addr;
          _scheduleFareEstimateRider();
        }
      }
    }catch(_){ }
  }

  Future<void> _searchPoi(String category) async {
    try{
      // Use pickup as center for nearby search
      final center = _pickup;
      final uri = Uri.parse('${widget.baseUrl}/osm/poi_search').replace(queryParameters: {
        'q': category,
        'lat': center.latitude.toString(),
        'lon': center.longitude.toString(),
        'limit': '20',
      });
      final resp = await http.get(uri);
      if(resp.statusCode != 200){
        setState(()=> out = 'POI search error: ${resp.statusCode}');
        return;
      }
      final data = jsonDecode(resp.body);
      if(data is! List || data.isEmpty){
        setState(()=> out = 'No nearby places found for $category');
        return;
      }
      if(!mounted) return;
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx){
          final l = L10n.of(context);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.isArabic
                        ? 'أماكن قريبة: $category'
                        : 'Nearby places: $category',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: data.length,
                      itemBuilder: (_, i){
                        final item = data[i] as Map;
                        final name = (item['name'] ?? '').toString();
                        final addr = (item['address'] ?? '').toString();
                        final lat = (item['lat'] as num?)?.toDouble();
                        final lon = (item['lon'] as num?)?.toDouble();
                        if(lat == null || lon == null){
                          return const SizedBox.shrink();
                        }
                        return ListTile(
                          title: Text(
                            name.isEmpty ? addr : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: addr.isEmpty
                              ? null
                              : Text(
                                  addr,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onTap: (){
                            final ll = LatLng(lat, lon);
                            if(_setPickup){
                              _pickup = ll;
                              if(addr.isNotEmpty) {
                                pickupAddrCtrl.text = addr;
                              } else if(name.isNotEmpty){
                                pickupAddrCtrl.text = name;
                              }
                            }else{
                              _drop = ll;
                              if(addr.isNotEmpty){
                                dropAddrCtrl.text = addr;
                              } else if(name.isNotEmpty){
                                dropAddrCtrl.text = name;
                              }
                            }
                            Navigator.pop(ctx);
                            _updateRoute();
                            setState((){});
                            _scheduleFareEstimateRider();
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }catch(e){
      setState(()=> out = 'POI search error: $e');
    }
  }

  Future<void> _loadNearestDriver() async {
    try{
      final uri = Uri.parse('${widget.baseUrl}/fleet/nearest_driver').replace(queryParameters: {
        'lat': _pickup.latitude.toString(),
        'lon': _pickup.longitude.toString(),
        'status': 'online',
        'limit': '200',
      });
      final resp = await http.get(uri);
      if(resp.statusCode != 200){
        // Do not show errors to the rider; just keep previous info.
        return;
      }
      final data = jsonDecode(resp.body);
      if(data is! Map){
        return;
      }
      final l = L10n.of(context);
      if(data['found'] != true){
        setState(() {
          _nearestDriverText = l.isArabic
              ? 'لا يوجد سائق متصل قريباً'
              : 'No nearby driver online yet';
        });
        return;
      }
      final nearest = data['nearest'];
      if(nearest is! Map){
        return;
      }
      final distKm = (nearest['distance_km'] as num?)?.toDouble() ?? 0.0;
      setState(() {
        _nearestDriverText = l.isArabic
            ? 'أقرب سائق تقريباً على بُعد ${distKm.toStringAsFixed(1)} كم'
            : 'Nearest driver is about ${distKm.toStringAsFixed(1)} km away';
      });
    }catch(_){
      // Best-effort only.
    }
  }

  void _updateRoute(){ if(_drop==null){ _route={}; _routeInfo=''; return; } _fetchDirections(); }
  Future<void> _ensureGmapsKey() async { if(_gmapsKey!=null) return; try{ final sp=await SharedPreferences.getInstance(); _gmapsKey = sp.getString('gmaps_key'); }catch(_){ } }
  Future<void> _fetchDirections() async {
    try{
      if(useOsmMaps){
        final uri = Uri.parse('${widget.baseUrl}/osm/route').replace(queryParameters: {
          'start_lat': _pickup.latitude.toString(),
          'start_lon': _pickup.longitude.toString(),
          'end_lat': _drop!.latitude.toString(),
          'end_lon': _drop!.longitude.toString(),
        });
        final resp = await http.get(uri);
        if(resp.statusCode==200){
          final j = jsonDecode(resp.body);
          // Reset previous alternatives
          _routeOptions = [];
          _routeOptionStats = [];
          _selectedRouteIndex = 0;

          List<List<LatLng>> routeOptions = [];
          List<Map<String, num>> routeStats = [];

          List<LatLng> _parsePoints(dynamic raw){
            final pts = <LatLng>[];
            if(raw is List){
              for(final p in raw){
                if(p is List && p.length>=2){
                  final lat = (p[0] as num).toDouble();
                  final lon = (p[1] as num).toDouble();
                  pts.add(LatLng(lat, lon));
                }
              }
            }
            return pts;
          }

          void _addRouteFromJson(Map data){
            final pts = _parsePoints(data['points']);
            if(pts.isEmpty) return;
            final distM = (data['distance_m'] as num?)?.toDouble() ?? 0.0;
            final durS = (data['duration_s'] as num?)?.toDouble() ?? 0.0;
            routeOptions.add(pts);
            routeStats.add({
              'distanceKm': distM / 1000.0,
              'etaMin': (durS / 60.0).ceil(),
            });
          }

          try{
            final routes = j['routes'];
            if(routes is List && routes.isNotEmpty){
              for(final r in routes){
                if(r is Map<String, dynamic>){
                  _addRouteFromJson(r);
                }else if(r is Map){
                  _addRouteFromJson(r.cast<String, dynamic>());
                }
              }
            }
          }catch(_){ }

          // Fallback: single route at top-level
          if(routeOptions.isEmpty && j is Map<String, dynamic>){
            _addRouteFromJson(j);
          }

          // Final fallback: straight line if still nothing
          if(routeOptions.isEmpty){
            final pts=[_pickup, if(_drop!=null) _drop!].whereType<LatLng>().toList();
            if(pts.length>=2){
              final distKm = _haversineKm(_pickup.latitude, _pickup.longitude, _drop!.latitude, _drop!.longitude);
              final etaMin = (distKm / 30.0 * 60.0).ceil();
              routeOptions.add(pts);
              routeStats.add({
                'distanceKm': distKm,
                'etaMin': etaMin,
              });
            }
          }

          if(routeOptions.isNotEmpty){
            _routeOptions = routeOptions;
            _routeOptionStats = routeStats;
            _selectedRouteIndex = 0;

            final routeColor = Theme.of(context).brightness==Brightness.dark? Colors.white : Colors.black;
            final selectedPts = _routeOptions[_selectedRouteIndex];
            _route = {
              Polyline(
                polylineId: const PolylineId('route'),
                points: selectedPts,
                color: routeColor,
                width: 5,
              ),
            };

            final stats = _routeOptionStats[_selectedRouteIndex];
            final distKm = (stats['distanceKm'] ?? 0) as num;
            final etaMin = (stats['etaMin'] ?? 0) as num;
            final l = L10n.of(context);
            _routeInfo = l.isArabic
                ? 'المسافة: ${distKm.toStringAsFixed(2)} كم · الوقت التقريبي: ${etaMin.toInt()} دقيقة'
                : 'Distance: ${distKm.toStringAsFixed(2)} km · ETA: ${etaMin.toInt()} min';
          }

          if(mounted) setState((){});
          Perf.action('taxi_route_ok');
          return;
        }
        // Fallback to local straight-line estimation
        final pts=[_pickup, if(_drop!=null) _drop!].whereType<LatLng>().toList();
        if(pts.length>=2){
          final routeColor = Theme.of(context).brightness==Brightness.dark? Colors.white : Colors.black;
          _route = { Polyline(polylineId: const PolylineId('route'), points: pts, color: routeColor, width: 5) };
          final distKm = _haversineKm(_pickup.latitude, _pickup.longitude, _drop!.latitude, _drop!.longitude);
          final etaMin = (distKm / 30.0 * 60.0).ceil(); _routeInfo='Distance: ${distKm.toStringAsFixed(2)} km · ETA: ${etaMin} min';
        }
        if(mounted) setState((){});
        Perf.action('taxi_route_ok');
        return;
      }
      await _ensureGmapsKey();
      if(_gmapsKey==null || _gmapsKey!.isEmpty){
        final pts=[_pickup, if(_drop!=null) _drop!].whereType<LatLng>().toList();
        if(pts.length>=2){
          final routeColor = Theme.of(context).brightness==Brightness.dark? Colors.white : Colors.black;
          _route = { Polyline(polylineId: const PolylineId('route'), points: pts, color: routeColor, width: 5) };
          final distKm = _haversineKm(_pickup.latitude, _pickup.longitude, _drop!.latitude, _drop!.longitude);
          final etaMin = (distKm / 30.0 * 60.0).ceil(); _routeInfo='Distance: ${distKm.toStringAsFixed(2)} km · ETA: ${etaMin} min';
        }
        if(mounted) setState((){});
        return;
      }
      final url = Uri.parse('https://maps.googleapis.com/maps/api/directions/json?mode=driving&origin='+
          '${_pickup.latitude},${_pickup.longitude}&destination=${_drop!.latitude},${_drop!.longitude}&key=${Uri.encodeComponent(_gmapsKey!)}');
      final r = await http.get(url);
      final j = jsonDecode(r.body);
      if((j['routes'] as List).isEmpty){ Perf.action('taxi_route_fail'); return; }
      final route=j['routes'][0];
      final poly=route['overview_polyline']!=null? route['overview_polyline']['points'] as String? : null;
      List<LatLng> pts = [];
      if(poly!=null){ pts = _decodePolyline(poly); }
      final routeColor = Theme.of(context).brightness==Brightness.dark? Colors.white : Colors.black;
      _route = { Polyline(polylineId: const PolylineId('route'), points: pts.isNotEmpty? pts : [_pickup,_drop!], color: routeColor, width: 5) };
      try{ final leg=route['legs'][0]; final dist=leg['distance']['text']; final dur=leg['duration']['text']; _routeInfo = 'Distance: '+dist+' · ETA: '+dur; }catch(_){ }
      if(mounted) setState((){});
      Perf.action('taxi_route_ok');
    }catch(_){
      Perf.action('taxi_route_error');
    }
  }
  List<LatLng> _decodePolyline(String e){
    List<LatLng> pts=[]; int index=0, len=e.length; int lat=0, lng=0;
    while(index<len){ int b, shift=0, result=0; do { b=e.codeUnitAt(index++)-63; result |= (b & 0x1f) << shift; shift +=5; } while(b>=0x20); int dlat=((result&1)!=0? ~(result>>1):(result>>1)); lat+=dlat; shift=0; result=0; do { b=e.codeUnitAt(index++)-63; result |= (b & 0x1f) << shift; shift+=5; } while(b>=0x20); int dlng=((result&1)!=0? ~(result>>1):(result>>1)); lng+=dlng; pts.add(LatLng(lat/1e5, lng/1e5)); }
    return pts;
  }
  double _haversineKm(double lat1,double lon1,double lat2,double lon2){
    const R = 6371.0; double dLat = (lat2-lat1) * pi/180.0; double dLon = (lon2-lon1) * pi/180.0;
    double a = (sin(dLat/2)*sin(dLat/2)) + cos(lat1*pi/180.0)*cos(lat2*pi/180.0)*(sin(dLon/2)*sin(dLon/2));
    double c = 2*atan2(sqrt(a), sqrt(1-a)); return R*c;
  }

  Future<void> _loadTaxiStands() async {
    try{
      const delta = 0.02;
      final params = {
        'south': (_pickup.latitude - delta).toString(),
        'west': (_pickup.longitude - delta).toString(),
        'north': (_pickup.latitude + delta).toString(),
        'east': (_pickup.longitude + delta).toString(),
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
        if(mounted) setState(()=> _standMarkersR = stands);
      } else {
        if(mounted) setState(()=> out='Taxi stands error: ${resp.statusCode}: ${resp.body}');
      }
    }catch(e){
      if(mounted) setState(()=> out='Taxi stands error: $e');
    }
  }

  @override
  Widget build(BuildContext context){
    final l = L10n.of(context);
    const walletInfo = '';
    final driverInfo = (_driverName.isEmpty && _driverVehicle.isEmpty && _driverPlate.isEmpty)
        ? null
        : 'Driver: ${_driverName.isEmpty ? '' : _driverName}  ·  ${_driverVehicle.isEmpty ? '' : _driverVehicle}  ·  ${_driverPlate.isEmpty ? '' : _driverPlate}';

    if(_minimalRider){
      final content = Column(children: [
        Expanded(child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: GoogleMap(
            initialCameraPosition: CameraPosition(target: _pickup, zoom: 13),
            myLocationEnabled: true,
            markers: _markersR,
            polylines: _route,
            onMapCreated: (c){ _gmapR=c; },
            onTap: (ll){ if(_setPickup){ _pickup=ll; _reverseGeocodeRider(true); } else { _drop=ll; _reverseGeocodeRider(false);} setState((){}); _scheduleFareEstimateRider(); },
          ),
        )),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.local_taxi, size: 16),
            label: const Text('Taxi stands nearby'),
            onPressed: () async {
              try{ HapticFeedback.lightImpact(); }catch(_){ }
              await _loadTaxiStands();
            },
          ),
        ),
        const SizedBox(height:8),
        if(_bannerMsg.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: StatusBanner(kind: _bannerKind, message: _bannerMsg, dense: true),
          ),
        Row(children:[Expanded(child: TextField(focusNode: _pickupFocus, controller: pickupAddrCtrl, decoration: const InputDecoration(labelText: 'Pickup address')))]),
        const SizedBox(height:6),
        Row(children:[Expanded(child: TextField(focusNode: _dropFocus, controller: dropAddrCtrl, decoration: const InputDecoration(labelText: 'Dropoff address')))]),
        const SizedBox(height:6),
        if(_routeInfo.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(_routeInfo, style: const TextStyle(fontSize: 12))),
        if(fareOut.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(fareOut, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        if(walletInfo.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(walletInfo, style: const TextStyle(fontSize: 11)),
          ),
        if(driverInfo!=null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(driverInfo, style: const TextStyle(fontSize: 12))),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () async {
              if(_drop==null){
                setState(()=> out = l.isArabic ? 'يرجى تحديد موقع النزول' : 'Please set dropoff location');
                return;
              }
              try{ HapticFeedback.lightImpact(); }catch(_){ }
              await _bookPay();
            },
            child: Text(l.isArabic ? 'الدفع وطلب الرحلة' : 'Book & Pay online'),
          ),
        ),
        const SizedBox(height:8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonal(
            onPressed: () async {
              try{ HapticFeedback.lightImpact(); }catch(_){ }
              await _cancel();
            },
            child: Text(l.isArabic ? 'إلغاء الرحلة (قد تُطبق رسوم)' : 'Cancel ride (fee may apply)'),
          ),
        ),
        const SizedBox(height:8),
        if(out.isNotEmpty) SelectableText(out),
      ]);
      return Scaffold(
        appBar: AppBar(title: Text(l.isArabic ? 'راكب تاكسي' : 'Taxi Rider'), backgroundColor: Colors.transparent),
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        body: Stack(children:[ const TaxiBG(), Positioned.fill(child: SafeArea(child: GlassPanel(padding: const EdgeInsets.all(12), radius: 12, child: content))) ]),
      );
    }
    final mapSection = SizedBox(
      height: MediaQuery.of(context).size.height * 0.45,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: TaxiMapWidget(
          center: _pickup,
          initialZoom: 13,
          markers: _markersR,
          polylines: _route,
          myLocationEnabled: true,
          onMapCreated: (c){ if(c is GoogleMapController){ _gmapR=c; } },
          onTap: (ll){ if(_setPickup){ _pickup=ll; _reverseGeocodeRider(true); } else { _drop=ll; _reverseGeocodeRider(false);} setState((){}); _scheduleFareEstimateRider(); },
        ),
      ),
    );

    final addressSection = FormSection(
      title: l.isArabic ? 'العناوين' : 'Addresses',
      children: [
        Row(children:[
          FilterChip(label: Text(l.isArabic ? 'تعيين نقطة الانطلاق' : 'Set pickup'), selected: _setPickup, onSelected: (_){ setState(()=>_setPickup=true); }),
          const SizedBox(width:8),
          FilterChip(label: Text(l.isArabic ? 'تعيين نقطة النزول' : 'Set dropoff'), selected: !_setPickup, onSelected: (_){ setState(()=>_setPickup=false); }),
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
        const SizedBox(height:4),
        TextField(controller: pickupAddrCtrl, decoration: InputDecoration(labelText: l.isArabic ? 'عنوان الانطلاق' : 'Pickup address')),
        const SizedBox(height:8),
        TextField(controller: dropAddrCtrl, decoration: InputDecoration(labelText: l.isArabic ? 'عنوان النزول' : 'Dropoff address')),
      ],
    );

    final fareSection = FormSection(
      title: l.isArabic ? 'تقدير الأجرة' : 'Fare estimate',
      children: [
        if(_fareOptions.isNotEmpty)
          TaxiFareChips(options: _fareOptions, selected: _selectedVehicleType, onSelected: (name){ setState(()=> _selectedVehicleType = name); try{ HapticFeedback.selectionClick(); }catch(_){ } }),
        if(_fareOptions.isEmpty) SelectableText(fareOut),
        const SizedBox(height:4),
        if(walletInfo.isNotEmpty)
          Text(walletInfo, style: const TextStyle(fontSize: 11)),
        if(driverInfo!=null) Padding(padding: const EdgeInsets.only(top:4), child: Text(driverInfo, style: const TextStyle(fontSize: 12))),
        if(_routeInfo.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top:8),
            child: Text(_routeInfo, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        if(_routeOptions.length > 1)
          Padding(
            padding: const EdgeInsets.only(top:4),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for(int i=0; i<_routeOptions.length; i++)
                  ChoiceChip(
                    label: Builder(builder: (_){
                      final stats = (i < _routeOptionStats.length) ? _routeOptionStats[i] : const <String, num>{};
                      final dist = (stats['distanceKm'] ?? 0) as num;
                      final eta = (stats['etaMin'] ?? 0) as num;
                      final labelText = l.isArabic
                          ? 'مسار ${i+1}: ${dist.toStringAsFixed(1)} كم · ${eta.toInt()} د'
                          : 'Route ${i+1}: ${dist.toStringAsFixed(1)} km · ${eta.toInt()} min';
                      return Text(labelText);
                    }),
                    selected: _selectedRouteIndex == i,
                    onSelected: (sel){
                      if(!sel) return;
                      setState(() {
                        _selectedRouteIndex = i;
                        if(_routeOptions.isNotEmpty){
                          final pts = _routeOptions[_selectedRouteIndex];
                          final routeColor = Theme.of(context).brightness==Brightness.dark? Colors.white : Colors.black;
                          _route = {
                            Polyline(
                              polylineId: const PolylineId('route'),
                              points: pts,
                              color: routeColor,
                              width: 5,
                            ),
                          };
                          if(i < _routeOptionStats.length){
                            final stats = _routeOptionStats[i];
                            final distKm = (stats['distanceKm'] ?? 0) as num;
                            final etaMin = (stats['etaMin'] ?? 0) as num;
                            _routeInfo = l.isArabic
                                ? 'المسافة: ${distKm.toStringAsFixed(2)} كم · الوقت التقريبي: ${etaMin.toInt()} دقيقة'
                                : 'Distance: ${distKm.toStringAsFixed(2)} km · ETA: ${etaMin.toInt()} min';
                          }
                        }
                      });
                    },
                  ),
              ],
            ),
          ),
        if(_nearestDriverText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top:4),
            child: Text(
              _nearestDriverText,
              style: const TextStyle(fontSize: 11),
            ),
          ),
      ],
    );

    final actionsSection = FormSection(
      title: l.isArabic ? 'الرحلة' : 'Ride',
      children: [
        Builder(builder: (_){
          final disablePay = (_fareOptions.length>1) && (_selectedVehicleType==null || _selectedVehicleType!.isEmpty);
          final semanticsLabel = l.isArabic
              ? 'الدفع وطلب الرحلة'
              : 'Book and pay taxi ride online';
          return Semantics(
            button: true,
            enabled: !disablePay,
            label: semanticsLabel,
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: disablePay ? null : () async {
                  if(_drop==null){
                    setState(()=> out = l.isArabic ? 'يرجى تحديد موقع النزول' : 'Please set dropoff location');
                    return;
                  }
                  try{ HapticFeedback.lightImpact(); }catch(_){ }
                  await _bookPay();
                },
                icon: const Icon(Icons.local_taxi),
                label: Text(l.isArabic ? 'الدفع وطلب الرحلة' : 'Book & Pay online'),
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              try{ HapticFeedback.lightImpact(); }catch(_){ }
              await _status();
            },
            icon: const Icon(Icons.info_outline),
            label: Text(l.isArabic ? 'الحالة' : 'Status'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: () async {
              try{ HapticFeedback.lightImpact(); }catch(_){ }
              await _cancel();
            },
            icon: const Icon(Icons.cancel_outlined),
            label: Text(l.isArabic ? 'إلغاء الرحلة' : 'Cancel ride'),
          ),
        ),
        const SizedBox(height:6),
        Builder(builder: (_){
          if(_fareOptions.length<=1) return const SizedBox.shrink();
          if(_selectedVehicleType==null || _selectedVehicleType!.isEmpty){
            return Text(
              l.isArabic ? 'يرجى اختيار نوع المركبة للمتابعة' : 'Select a vehicle type to continue',
              style: const TextStyle(fontSize: 12),
            );
          }
          final sel = _fareOptions.firstWhere((o)=> (o['name']??'').toString()==_selectedVehicleType, orElse: ()=> const {'name':'','cents':0});
          final cents = (sel['cents']??0) as int;
          return Text(
            l.isArabic
                ? 'المختار: ${_selectedVehicleType} • ${fmtCents(cents)} SYP'
                : 'Selected: ${_selectedVehicleType} • ${fmtCents(cents)} SYP',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          );
        }),
        if(out.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SelectableText(out),
        ),
      ],
    );

    final content = Column(children: [
      mapSection,
      const SizedBox(height:8),
      if(_bannerMsg.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: StatusBanner(kind: _bannerKind, message: _bannerMsg, dense: true),
        ),
      addressSection,
      fareSection,
      actionsSection,
    ]);
    return Scaffold(
      appBar: AppBar(title: Text(l.isArabic ? 'راكب تاكسي' : 'Taxi Rider'), backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(children:[
        const TaxiBG(),
        // Full-screen background card like Operator
        Positioned.fill(
          child: SafeArea(
            child: GlassPanel(
              padding: const EdgeInsets.all(12),
              radius: 12,
              child: SingleChildScrollView(
                child: content,
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
