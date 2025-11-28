import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'offline_queue.dart';
import 'skeleton.dart';
import 'package:share_plus/share_plus.dart';
import 'format.dart';
import 'l10n.dart';
import 'glass.dart';
import 'design_tokens.dart';

Future<Map<String, String>> _hdrFood({bool json = false}) async {
  final headers = <String, String>{};
  if (json) {
    headers['content-type'] = 'application/json';
  }
  try{
    final sp = await SharedPreferences.getInstance();
    final cookie = sp.getString('sa_cookie') ?? '';
    if (cookie.isNotEmpty) {
      // Align with the rest of the app: send the session token via custom header
      // instead of a Cookie header so that web clients avoid strict cookie rules.
      headers['sa_cookie'] = cookie;
    }
  }catch(_){}
  return headers;
}

class FoodOrdersPage extends StatefulWidget{
  final String baseUrl; const FoodOrdersPage(this.baseUrl, {super.key});
  @override State<FoodOrdersPage> createState()=>_FoodOrdersPageState();
}

class _FoodOrdersPageState extends State<FoodOrdersPage>{
  final idCtrl = TextEditingController();
  List<String> recents = [];
  String out=''; bool loading=false;
  bool _autoPoll=false; Timer? _poller;
  Map<String, String> _statusCache = {};
  bool _listLoading=false; List<dynamic> _orders=[]; String _phone='';
  String _statusFilter = 'all';
  String _dateFilter = 'all';
  final _statuses = const ['all','pending','confirmed','delivered','canceled'];
  final _dates = const ['all','7d','30d','custom'];
  DateTime? _fromDate; DateTime? _toDate;
  String _curSym = 'SYP';

  @override void initState(){ super.initState(); _loadRecents(); _loadCache(); _loadPrefs(); }
  Future<void> _loadPrefs() async { try{ final sp=await SharedPreferences.getInstance(); _statusFilter = sp.getString('fo_status') ?? _statusFilter; _dateFilter = sp.getString('fo_date') ?? _dateFilter; final f=sp.getString('fo_from'); final t=sp.getString('fo_to'); if(f!=null) _fromDate=DateTime.tryParse(f); if(t!=null) _toDate=DateTime.tryParse(t); final cs=sp.getString('currency_symbol'); if(cs!=null && cs.isNotEmpty){ _curSym = cs; } if(mounted) setState((){}); }catch(_){ } }
  Future<void> _loadRecents() async { try{ final sp=await SharedPreferences.getInstance(); recents = sp.getStringList('food_recent_order_ids') ?? []; if(mounted) setState((){}); }catch(_){ } }
  Future<void> _loadCache() async { try{ final sp=await SharedPreferences.getInstance(); final raw=sp.getString('food_status_cache'); if(raw!=null&&raw.isNotEmpty){ final m=jsonDecode(raw) as Map<String,dynamic>; _statusCache = m.map((k,v)=> MapEntry(k, v.toString())); } if(mounted) setState((){}); }catch(_){ } }
  Future<void> _saveRecent(String id) async { try{ final sp=await SharedPreferences.getInstance(); final cur = sp.getStringList('food_recent_order_ids') ?? []; cur.removeWhere((x)=>x==id); cur.insert(0, id); while(cur.length>10) cur.removeLast(); await sp.setStringList('food_recent_order_ids', cur); recents = cur; if(mounted) setState((){}); }catch(_){ } }
  Future<void> _saveCache() async { try{ final sp=await SharedPreferences.getInstance(); await sp.setString('food_status_cache', jsonEncode(_statusCache)); }catch(_){ } }
  Future<void> _savePrefs() async { try{ final sp=await SharedPreferences.getInstance(); await sp.setString('fo_status', _statusFilter); await sp.setString('fo_date', _dateFilter); if(_fromDate!=null) await sp.setString('fo_from', _fromDate!.toIso8601String()); if(_toDate!=null) await sp.setString('fo_to', _toDate!.toIso8601String()); }catch(_){ } }
  Future<void> _loadList() async {
    setState(()=>_listLoading=true);
    try{
      final sp = await SharedPreferences.getInstance();
      _phone = sp.getString('last_login_phone') ?? '';
      final qp = <String,String>{ 'phone': _phone, 'limit':'50' };
      if(_statusFilter!='all') qp['status'] = _statusFilter;
      DateTime? f; DateTime? t;
      if(_dateFilter=='7d'){ f = DateTime.now().subtract(const Duration(days:7)); }
      else if(_dateFilter=='30d'){ f = DateTime.now().subtract(const Duration(days:30)); }
      else if(_dateFilter=='custom'){ f = _fromDate; t = _toDate; }
      String toIso(DateTime d)=> d.toUtc().toIso8601String();
      if(f!=null) qp['from_iso'] = toIso(f);
      if(t!=null) qp['to_iso'] = toIso(t);
      final u = Uri.parse('${widget.baseUrl}/food/orders').replace(queryParameters: qp);
      final r = await http.get(u, headers: await _hdrFood());
      if(r.statusCode==200){ try{ _orders = jsonDecode(r.body) as List; }catch(_){ _orders=[]; } }
    }catch(_){ }
    if(mounted) setState(()=>_listLoading=false);
  }

  Future<void> _status([String? id]) async {
    final l = L10n.of(context);
    final oid = (id ?? idCtrl.text).trim();
    if(oid.isEmpty){
      setState(()=>out=l.foodOrderIdRequired);
      return;
    }
    setState(()=>loading=true);
    try{
      final uri = Uri.parse('${widget.baseUrl}/food/orders/'+Uri.encodeComponent(oid));
      final r = await http.get(uri, headers: await _hdrFood());
      out='${r.statusCode}: ${r.body}';
      try{
        final j=jsonDecode(r.body);
        final st=(j is Map && j['status']!=null)? j['status'].toString() : '';
        if(st.isNotEmpty){ _statusCache[oid]=st; await _saveCache(); }
      }catch(_){ }
      await _saveRecent(oid);
    }catch(e){ out='${L10n.of(context).historyErrorPrefix}: $e'; }
    if(mounted) setState(()=>loading=false);
  }

  void _togglePoll(bool v){
    setState(()=>_autoPoll=v);
    _poller?.cancel();
    if(v){
      _poller = Timer.periodic(const Duration(seconds: 10), (_) async {
        if(recents.isEmpty) return;
        final ids = recents.take(5).toList();
        for(final oid in ids){
          try{ final r = await http.get(Uri.parse('${widget.baseUrl}/food/orders/'+Uri.encodeComponent(oid)).replace()); if(r.statusCode==200){ try{ final j=jsonDecode(r.body); final st=(j is Map && j['status']!=null)? j['status'].toString() : ''; if(st.isNotEmpty){ _statusCache[oid]=st; } }catch(_){ } } }catch(_){ }
        }
        await _saveCache();
        await _loadList();
        if(mounted) setState((){});
      });
    }
  }

  @override void dispose(){ _poller?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context){
    final pending = OfflineQueue.pending(tag: 'food_order');
    final list = loading? ListView.builder(itemCount: 6, itemBuilder: (_,i)=> const SkeletonListTile()) : ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(value: _autoPoll, onChanged: _togglePoll, title: const Text('Auto‑Refresh (10s)')),
        if(pending.isNotEmpty) const Text('Pending (offline)', style: TextStyle(fontWeight: FontWeight.w700)),
        ...pending.map((p)=> ListTile(leading: const Icon(Icons.schedule), title: Text(p.tag), subtitle: Text(p.body, maxLines: 2, overflow: TextOverflow.ellipsis))),
        const Divider(height: 24),
        Row(children:[ Expanded(child: Text('Signed in: ${_phone.isEmpty? '(no phone)':_phone}', overflow: TextOverflow.ellipsis)), const SizedBox(width:8), OutlinedButton.icon(onPressed: _loadList, icon: const Icon(Icons.list), label: const Text('Load list')), const SizedBox(width:8), OutlinedButton.icon(onPressed: _exportCsv, icon: const Icon(Icons.ios_share_outlined), label: const Text('Export CSV')) ]),
        const SizedBox(height: 8),
        Row(children:[ const Text('Status:'), const SizedBox(width:6), DropdownButton<String>(value: _statusFilter, items: _statuses.map((s)=> DropdownMenuItem(value:s, child: Text(s))).toList(), onChanged: (v){ if(v==null) return; setState(()=>_statusFilter=v); _savePrefs(); }), const SizedBox(width:12), const Text('Period:'), const SizedBox(width:6), DropdownButton<String>(value: _dateFilter, items: _dates.map((s)=> DropdownMenuItem(value:s, child: Text(s))).toList(), onChanged: (v) async { if(v==null) return; setState(()=>_dateFilter=v); if(v=='custom'){ await _pickDates(context); } _savePrefs(); await _loadList(); }), ]),
        if(_dateFilter=='custom') Row(children:[ OutlinedButton.icon(onPressed: () async { await _pickDate(context, true); }, icon: const Icon(Icons.date_range), label: Text(_fromDate==null? 'From' : _fromDate!.toLocal().toString().split(' ').first)), const SizedBox(width:8), OutlinedButton.icon(onPressed: () async { await _pickDate(context, false); }, icon: const Icon(Icons.date_range), label: Text(_toDate==null? 'To' : _toDate!.toLocal().toString().split(' ').first)) ]),
        const SizedBox(height: 8),
        if(_listLoading) ...[ for(int i=0;i<4;i++) const SkeletonListTile() ] else ...[
          if(_orders.isNotEmpty) const Text('Orders', style: TextStyle(fontWeight: FontWeight.w700)),
          ..._filteredOrders().map((o){
            final id = (o is Map && o['id']!=null)? o['id'].toString() : '';
            final st = (o is Map && o['status']!=null)? o['status'].toString() : '';
            final ts = (o is Map && o['created_at']!=null)? o['created_at'].toString() : '';
            final total = (o is Map)? (o['total_cents'] ?? o['amount_cents']) : null;
            final trailing = total==null? null : Text('${fmtCents(total)} ${_curSym}');
            return Padding(padding: const EdgeInsets.only(bottom:8), child: GlassPanel(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child:
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text('Order $id'),
                subtitle: Text('$st • $ts', maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: id.isEmpty? null : (){ Navigator.of(context).push(MaterialPageRoute(builder: (_)=> FoodOrderDetailPage(widget.baseUrl, id))); },
                trailing: trailing ?? IconButton(onPressed: ()=>_status(id), icon: const Icon(Icons.refresh)),
              ),
            ));
          }).toList(),
          const Divider(height: 24),
        ],
        TextField(controller: idCtrl, decoration: InputDecoration(labelText: L10n.of(context).isArabic ? 'معرّف الطلب' : 'order id')), const SizedBox(height: 8),
        FilledButton.icon(onPressed: ()=>_status(), icon: const Icon(Icons.refresh), label: Text(L10n.of(context).isArabic ? 'تحقق من الحالة' : 'Check status')),
        const SizedBox(height: 12), if(out.isNotEmpty) SelectableText(out),
        const Divider(height: 24),
        if(recents.isNotEmpty) Text(L10n.of(context).isArabic ? 'الطلبات الأخيرة' : 'Recent orders', style: const TextStyle(fontWeight: FontWeight.w700)),
        ...recents.map((id)=> Padding(padding: const EdgeInsets.only(bottom:8), child: GlassPanel(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child:
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text(id),
            subtitle: Text(_statusCache[id] ?? ''),
            onTap: (){ Navigator.of(context).push(MaterialPageRoute(builder: (_)=> FoodOrderDetailPage(widget.baseUrl, id))); },
            trailing: IconButton(onPressed: ()=>_status(id), icon: const Icon(Icons.refresh)),
          ),
        ))).toList(),
      ],
    );
    Widget bg(BuildContext context){ final isDark=Theme.of(context).brightness==Brightness.dark; return Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter,end: Alignment.bottomCenter,colors: isDark?[Tokens.surface, const Color(0xFF0B1220)]:[Tokens.lightSurface, const Color(0xFFE9EEF7)]))); }
    return Scaffold(
      appBar: AppBar(title: Text(L10n.of(context).isArabic ? 'طلبات الطعام' : 'Food Orders'), backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(children:[ Builder(builder: bg), SafeArea(child: RefreshIndicator(onRefresh: () async { await OfflineQueue.flush(); await _loadRecents(); }, child: list)) ]),
    );
  }

  List<dynamic> _filteredOrders(){
    final now = DateTime.now();
    int? minEpoch, maxEpoch;
    if(_dateFilter=='7d'){ minEpoch = now.subtract(const Duration(days:7)).millisecondsSinceEpoch; }
    else if(_dateFilter=='30d'){ minEpoch = now.subtract(const Duration(days:30)).millisecondsSinceEpoch; }
    else if(_dateFilter=='custom'){ if(_fromDate!=null) minEpoch=_fromDate!.millisecondsSinceEpoch; if(_toDate!=null) maxEpoch=_toDate!.millisecondsSinceEpoch; }
    return _orders.where((o){
      try{
        final st = (o is Map && o['status']!=null)? o['status'].toString().toLowerCase() : '';
        if(_statusFilter!='all' && !st.contains(_statusFilter)) return false;
        if(minEpoch!=null || maxEpoch!=null){
          final tsStr = (o is Map && o['created_at']!=null)? o['created_at'].toString() : '';
          final ts = DateTime.tryParse(tsStr)?.millisecondsSinceEpoch;
          if(ts!=null){ if(minEpoch!=null && ts<minEpoch) return false; if(maxEpoch!=null && ts>maxEpoch) return false; }
        }
        return true;
      }catch(_){ return true; }
    }).toList();
  }

  Future<void> _pickDate(BuildContext context, bool from) async {
    final now = DateTime.now();
    final cur = from? (_fromDate ?? now.subtract(const Duration(days:7))) : (_toDate ?? now);
    final picked = await showDatePicker(context: context, initialDate: cur, firstDate: DateTime(now.year-3), lastDate: DateTime(now.year+1));
    if(picked!=null){ setState((){ if(from) _fromDate=picked; else _toDate=picked; }); await _savePrefs(); await _loadList(); }
  }
  Future<void> _pickDates(BuildContext context) async { await _pickDate(context, true); await _pickDate(context, false); }

  void _exportCsv(){
    try{
      final rows = <List<String>>[];
      rows.add(['id','status','created_at','total_cents','total_fmt','items_count','restaurant_id']);
      for(final o in _filteredOrders()){
        if(o is Map){
          final total = (o['total_cents'] ?? o['amount_cents'] ?? '').toString();
          final itemsCount = (() { try{ final it=o['items']; if(it is List) return it.length.toString(); }catch(_){ } return ''; })();
          final tfmt = (() { try{ final v = o['total_cents'] ?? o['amount_cents']; return (v==null)? '' : (fmtCents(v)+' '+_curSym); }catch(_){ return ''; } })();
          rows.add([
            (o['id']??'').toString(),
            (o['status']??'').toString(),
            (o['created_at']??'').toString(),
            total,
            tfmt,
            itemsCount,
            (o['restaurant_id']??'').toString(),
          ]);
        }
      }
      final csv = rows.map((r)=> r.map((c)=> '"'+c.replaceAll('"','""')+'"').join(',')).join('\n');
      Share.share(csv, subject: 'Food Orders');
    }catch(_){ }
  }
}

class FoodOrderDetailPage extends StatefulWidget{
  final String baseUrl; final String orderId; const FoodOrderDetailPage(this.baseUrl, this.orderId, {super.key});
  @override State<FoodOrderDetailPage> createState()=>_FoodOrderDetailPageState();
}
class _FoodOrderDetailPageState extends State<FoodOrderDetailPage>{
  Map<String,dynamic>? _data; bool _loading=true; String _out='';
  Map<String,dynamic>? _restaurant;
  String _curSym = 'SYP';
  @override void initState(){ super.initState(); _load(); }
  Future<void> _load() async {
    setState(()=>_loading=true);
    try{
      final uri = Uri.parse('${widget.baseUrl}/food/orders/'+Uri.encodeComponent(widget.orderId));
      final r = await http.get(uri, headers: await _hdrFood());
      if(r.statusCode==200){ _data = (jsonDecode(r.body) as Map).cast<String,dynamic>(); _out=''; await _maybeLoadRestaurant(); }
      else { _out = '${r.statusCode}: ${r.body}'; }
    }catch(e){ _out='Error: $e'; }
    if(mounted) setState(()=>_loading=false);
  }
  Future<void> _maybeLoadRestaurant() async {
    try{
      final j=_data; if(j==null) return;
      var rid = j['restaurant_id'] ?? (j['restaurant'] is Map? j['restaurant']['id'] : null);
      if(rid==null) return;
      final u = Uri.parse('${widget.baseUrl}/food/restaurants/'+Uri.encodeComponent(rid.toString()));
      final r = await http.get(u, headers: await _hdrFood());
      if(r.statusCode==200){ _restaurant = (jsonDecode(r.body) as Map).cast<String,dynamic>(); }
    }catch(_){ }
  }
  String _fmtCents(dynamic v){
    try{ final c = (v is int)? v : int.tryParse(v.toString())??0; final neg = c<0; int abs = c.abs(); int major = abs ~/ 100; int minor = abs % 100; String sMajor = major.toString(); final reg = RegExp(r"(\d+)(\d{3})"); while(reg.hasMatch(sMajor)){ sMajor = sMajor.replaceAllMapped(reg, (m)=> "${m.group(1)},${m.group(2)}"); } final out = "$sMajor.${minor.toString().padLeft(2,'0')}"; return neg? "-$out" : out; }catch(_){ return v.toString(); }
  }
  Future<void> _reorder() async {
    try{
      final j=_data; if(j==null){ return; }
      final rid = j['restaurant_id'] ?? (j['restaurant'] is Map? j['restaurant']['id'] : null);
      if(rid==null){ if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L10n.of(context).isArabic ? 'مطعم غير معروف' : 'Unknown restaurant'))); return; }
      List<Map<String,dynamic>> items=[];
      try{
        final it=j['items'];
        if(it is List){
          for(final e in it){
            try{
              final m=(e as Map).cast<String,dynamic>();
              final mid = m['menu_item_id'] ?? m['id'];
              final qty = m['qty'] ?? m['quantity'] ?? 1;
              if(mid!=null){ items.add({'menu_item_id': mid, 'qty': qty}); }
            }catch(_){ }
          }
        }
      }catch(_){ }
      final sp = await SharedPreferences.getInstance();
      final wallet = sp.getString('wallet_id');
      final body = {
        'restaurant_id': rid,
        if(wallet!=null && wallet.isNotEmpty) 'customer_wallet_id': wallet,
        'confirm': true,
        if(items.isNotEmpty) 'items': items,
      };
      final uri = Uri.parse('${widget.baseUrl}/food/orders');
      final headers = await _hdrFood(json: true);
      final r = await http.post(uri, headers: headers, body: jsonEncode(body));
      if(mounted){
        final l = L10n.of(context);
        if(r.statusCode>=200 && r.statusCode<300){
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.foodReorderPlaced)));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.foodErrorPrefix(r.statusCode))));
        }
      }
    }catch(e){
      if(mounted){
        final l = L10n.of(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.foodErrorGeneric(e))));
      }
    }
  }
  @override
  Widget build(BuildContext context){
    final l = L10n.of(context);
    final actions = _loading? null : [ IconButton(onPressed: _reorder, icon: const Icon(Icons.shopping_bag_outlined)) ];
    final list = _loading
        ? ListView(children: const [ SkeletonListTile(), SkeletonListTile(), SkeletonListTile() ])
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if(_data!=null) ..._buildContent(_data!),
              if(_out.isNotEmpty) SelectableText(_out),
            ],
          );
    return Scaffold(
      appBar: AppBar(
        title: Text('${l.foodOrdersTitle} ${widget.orderId}'),
        actions: actions,
      ),
      body: RefreshIndicator(onRefresh: _load, child: list),
    );
  }
  List<Widget> _buildContent(Map<String,dynamic> j){
    final l = L10n.of(context);
    final widgets = <Widget>[];
    String field(String k)=> (j[k]??'').toString();
    widgets.add(
      Text(
        '${l.foodStatusTitle}: ${field('status')}',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
    widgets.add(const SizedBox(height: 8));
    widgets.add(
      Text('${l.foodCreatedTitle}: ${field('created_at')}'),
    );
    final total = j['total_cents'] ?? j['amount_cents'];
    if(total!=null){
      widgets.add(
        Text('${l.foodTotalTitle}: ${_fmtCents(total)} ${_curSym}'),
      );
    }
    final rest = j['restaurant'] ?? j['restaurant_id'];
    if(rest!=null){
      final restLine = (_restaurant!=null)? (_restaurant!['name']??rest.toString()).toString() : rest.toString();
      widgets.add(
        Text('${l.foodRestaurantTitle}: $restLine'),
      );
    }
    widgets.add(const Divider(height: 24));
    final items = j['items'];
    if(items is List){
      widgets.add(
        Text(
          l.foodItemsTitle,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
      for(final it in items){
        try{
          final m = (it as Map).cast<String,dynamic>();
          final name = (m['name'] ?? m['title'] ?? m['menu_item_id']).toString();
          final qty = (m['qty'] ?? m['quantity'] ?? 1).toString();
          final priceC = m['price_cents'] ?? m['amount_cents'];
          final price = priceC==null? '' : '${_fmtCents(priceC)} ${_curSym}';
          widgets.add(ListTile(title: Text(name), subtitle: Text('x$qty'), trailing: Text(price)));
        }catch(_){ }
      }
    }
    return widgets;
  }
}
