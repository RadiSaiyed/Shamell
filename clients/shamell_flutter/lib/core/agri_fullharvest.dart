import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show AppBG;
import 'design_tokens.dart';
import 'glass.dart';
import 'l10n.dart';

Future<Map<String, String>> _agriHeaders({bool json = false}) async {
  final sp = await SharedPreferences.getInstance();
  final h = <String, String>{};
  if (json) h['content-type'] = 'application/json';
  final cookie = sp.getString('sa_cookie');
  if (cookie != null && cookie.isNotEmpty) {
    h['sa_cookie'] = cookie;
  }
  return h;
}

class AgriMarketplacePage extends StatefulWidget {
  final String baseUrl;
  const AgriMarketplacePage({super.key, required this.baseUrl});

  @override
  State<AgriMarketplacePage> createState() => _AgriMarketplacePageState();
}

class _AgriMarketplacePageState extends State<AgriMarketplacePage> with TickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  // Buyer
  final qCtrl = TextEditingController();
  final cityCtrl = TextEditingController();
  final catCtrl = TextEditingController();
  final statusCtrl = TextEditingController();
  List<Map<String, dynamic>> listings = const [];
  bool loadingListings = false;
  String listingsOut = '';

  // RFQ
  final rfqProductCtrl = TextEditingController();
  final rfqQtyCtrl = TextEditingController();
  final rfqUnitCtrl = TextEditingController(text: 'kg');
  final rfqCityCtrl = TextEditingController();
  final rfqDateCtrl = TextEditingController();
  final rfqNotesCtrl = TextEditingController();
  final rfqBuyerCtrl = TextEditingController();
  String rfqOut = '';

  // Operator
  List<Map<String, dynamic>> rfqs = const [];
  List<Map<String, dynamic>> orders = const [];
  Map<int, List<Map<String, dynamic>>> rfqReplies = {};
  String opsOut = '';
  bool opsLoading = false;
  final rfqStatusCtrl = TextEditingController();
  final orderStatusFilterCtrl = TextEditingController();

  // Listing create/update
  final lTitleCtrl = TextEditingController();
  final lCatCtrl = TextEditingController();
  final lVarCtrl = TextEditingController();
  final lPriceCtrl = TextEditingController();
  final lCityCtrl = TextEditingController();
  final lOriginCtrl = TextEditingController();
  final lCertCtrl = TextEditingController();
  final lMinCtrl = TextEditingController(text: '0');
  final lUnitCtrl = TextEditingController(text: 'kg');
  final lStatusCtrl = TextEditingController(text: 'listed');
  final lSellerCtrl = TextEditingController();
  String listingOut = '';

  // RFQ reply
  final replyPriceCtrl = TextEditingController();
  final replyEtaCtrl = TextEditingController();
  final replyMsgCtrl = TextEditingController();
  final replyWalletCtrl = TextEditingController();

  // Order create from listing
  final orderQtyCtrl = TextEditingController();
  final orderUnitCtrl = TextEditingController(text: 'kg');
  final orderBuyerCtrl = TextEditingController();
  final orderSellerCtrl = TextEditingController();
  final orderBuyerNotesCtrl = TextEditingController();
  final orderSupplierNotesCtrl = TextEditingController();
  String orderOut = '';
  final orderStatusCtrl = TextEditingController(text: 'pending');
  bool showOrderForm = false;

  // Operator listing status/price updates
  final opListingStatusCtrl = TextEditingController();
  final opListingIdCtrl = TextEditingController();
  final opListingPriceCtrl = TextEditingController();

  @override
  void dispose() {
    _tab.dispose();
    qCtrl.dispose();
    cityCtrl.dispose();
    catCtrl.dispose();
    statusCtrl.dispose();
    rfqProductCtrl.dispose();
    rfqQtyCtrl.dispose();
    rfqUnitCtrl.dispose();
    rfqCityCtrl.dispose();
    rfqDateCtrl.dispose();
    rfqNotesCtrl.dispose();
    rfqBuyerCtrl.dispose();
    rfqStatusCtrl.dispose();
    orderStatusFilterCtrl.dispose();
    lTitleCtrl.dispose();
    lCatCtrl.dispose();
    lVarCtrl.dispose();
    lPriceCtrl.dispose();
    lCityCtrl.dispose();
    lOriginCtrl.dispose();
    lCertCtrl.dispose();
    lMinCtrl.dispose();
    lUnitCtrl.dispose();
    lStatusCtrl.dispose();
    lSellerCtrl.dispose();
    replyPriceCtrl.dispose();
    replyEtaCtrl.dispose();
    replyMsgCtrl.dispose();
    replyWalletCtrl.dispose();
    orderQtyCtrl.dispose();
    orderUnitCtrl.dispose();
    orderBuyerCtrl.dispose();
    orderSellerCtrl.dispose();
    orderBuyerNotesCtrl.dispose();
    orderSupplierNotesCtrl.dispose();
    orderStatusCtrl.dispose();
    opListingStatusCtrl.dispose();
    opListingIdCtrl.dispose();
    opListingPriceCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadListings();
    _loadOps();
  }

  Future<void> _loadListings() async {
    setState(() {
      loadingListings = true;
      listingsOut = '';
    });
    final params = {
      'limit': '200',
      if (qCtrl.text.isNotEmpty) 'q': qCtrl.text.trim(),
      if (cityCtrl.text.isNotEmpty) 'city': cityCtrl.text.trim(),
      if (catCtrl.text.isNotEmpty) 'category': catCtrl.text.trim(),
      if (statusCtrl.text.isNotEmpty) 'status': statusCtrl.text.trim(),
    };
    final uri = Uri.parse('${widget.baseUrl}/agriculture/listings').replace(queryParameters: params);
    try {
      final r = await http.get(uri, headers: await _agriHeaders());
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is List) {
          listings = body.map<Map<String, dynamic>>((e) => (e as Map).cast()).toList();
          listingsOut = '${listings.length} results';
        } else {
          listings = const [];
          listingsOut = 'bad response';
        }
      } else {
        listings = const [];
        listingsOut = '${r.statusCode}: ${r.body}';
      }
    } catch (e) {
      listings = const [];
      listingsOut = 'error: $e';
    } finally {
      if (mounted) {
        setState(() => loadingListings = false);
      }
    }
  }

  Future<void> _createRFQ() async {
    setState(() => rfqOut = 'Sending RFQ...');
    try {
      final r = await http.post(Uri.parse('${widget.baseUrl}/agriculture/rfqs'),
          headers: await _agriHeaders(json: true),
          body: jsonEncode({
            'product': rfqProductCtrl.text.trim(),
            'category': catCtrl.text.trim().isEmpty ? null : catCtrl.text.trim(),
            'quantity': double.tryParse(rfqQtyCtrl.text.trim()),
            'unit': rfqUnitCtrl.text.trim().isEmpty ? null : rfqUnitCtrl.text.trim(),
            'city': rfqCityCtrl.text.trim().isEmpty ? null : rfqCityCtrl.text.trim(),
            'target_date': rfqDateCtrl.text.trim().isEmpty ? null : rfqDateCtrl.text.trim(),
            'notes': rfqNotesCtrl.text.trim().isEmpty ? null : rfqNotesCtrl.text.trim(),
            'buyer_wallet_id': rfqBuyerCtrl.text.trim().isEmpty ? null : rfqBuyerCtrl.text.trim(),
          }));
      setState(() => rfqOut = '${r.statusCode}: ${r.body}');
      _loadOps();
    } catch (e) {
      setState(() => rfqOut = 'error: $e');
    }
  }

  Future<void> _loadOps() async {
    setState(() {
      opsLoading = true;
      opsOut = '';
    });
    try {
      final rfqParams = {
        'limit': '200',
        if (rfqStatusCtrl.text.isNotEmpty) 'status': rfqStatusCtrl.text.trim(),
      };
      final ordParams = {
        'limit': '200',
        if (orderStatusFilterCtrl.text.isNotEmpty) 'status': orderStatusFilterCtrl.text.trim(),
      };
      final r1 = await http.get(
          Uri.parse('${widget.baseUrl}/agriculture/rfqs').replace(queryParameters: rfqParams),
          headers: await _agriHeaders());
      final r2 = await http.get(
          Uri.parse('${widget.baseUrl}/agriculture/orders').replace(queryParameters: ordParams),
          headers: await _agriHeaders());
      if (r1.statusCode == 200) {
        final body = jsonDecode(r1.body);
        if (body is List) rfqs = body.map<Map<String, dynamic>>((e) => (e as Map).cast()).toList();
      }
      if (r2.statusCode == 200) {
        final body = jsonDecode(r2.body);
        if (body is List) orders = body.map<Map<String, dynamic>>((e) => (e as Map).cast()).toList();
      }
      opsOut = 'RFQs ${rfqs.length} · Orders ${orders.length}';
    } catch (e) {
      opsOut = 'error: $e';
    } finally {
      if (mounted) setState(() => opsLoading = false);
    }
  }

  Future<void> _loadReplies(int rid) async {
    try {
      final r = await http.get(Uri.parse('${widget.baseUrl}/agriculture/rfqs/$rid/replies'), headers: await _agriHeaders());
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is List) {
          rfqReplies[rid] = body.map<Map<String, dynamic>>((e) => (e as Map).cast()).toList();
          setState(() {});
        }
      }
    } catch (_) {}
  }

  Future<void> _createListing() async {
    setState(() => listingOut = 'Creating listing...');
    try {
      final r = await http.post(Uri.parse('${widget.baseUrl}/agriculture/listings'),
          headers: await _agriHeaders(json: true),
          body: jsonEncode({
            'title': lTitleCtrl.text.trim(),
            'category': lCatCtrl.text.trim().isEmpty ? null : lCatCtrl.text.trim(),
            'variety': lVarCtrl.text.trim().isEmpty ? null : lVarCtrl.text.trim(),
            'price_cents': int.tryParse(lPriceCtrl.text.trim()) ?? 0,
            'city': lCityCtrl.text.trim().isEmpty ? null : lCityCtrl.text.trim(),
            'origin': lOriginCtrl.text.trim().isEmpty ? null : lOriginCtrl.text.trim(),
            'certifications': lCertCtrl.text.trim().isEmpty ? null : lCertCtrl.text.trim(),
            'min_qty': double.tryParse(lMinCtrl.text.trim()),
            'unit': lUnitCtrl.text.trim().isEmpty ? null : lUnitCtrl.text.trim(),
            'status': lStatusCtrl.text.trim().isEmpty ? null : lStatusCtrl.text.trim(),
            'seller_wallet_id': lSellerCtrl.text.trim().isEmpty ? null : lSellerCtrl.text.trim(),
          }));
      setState(() => listingOut = '${r.statusCode}: ${r.body}');
      _loadListings();
    } catch (e) {
      setState(() => listingOut = 'error: $e');
    }
  }

  Future<void> _updateListingStatus(int id, String status) async {
    setState(() => listingOut = 'Updating status...');
    try {
      final r = await http.patch(Uri.parse('${widget.baseUrl}/agriculture/listings/$id'),
          headers: await _agriHeaders(json: true), body: jsonEncode({'status': status}));
      setState(() => listingOut = '${r.statusCode}: ${r.body}');
      _loadListings();
    } catch (e) {
      setState(() => listingOut = 'error: $e');
    }
  }

  Future<void> _updateListingPrice(int id, int price) async {
    setState(() => listingOut = 'Updating price...');
    try {
      final r = await http.patch(Uri.parse('${widget.baseUrl}/agriculture/listings/$id'),
          headers: await _agriHeaders(json: true), body: jsonEncode({'price_cents': price}));
      setState(() => listingOut = '${r.statusCode}: ${r.body}');
      _loadListings();
    } catch (e) {
      setState(() => listingOut = 'error: $e');
    }
  }

  Future<void> _replyRFQ(int rid) async {
    setState(() => opsOut = 'Replying RFQ...');
    try {
      final r = await http.post(Uri.parse('${widget.baseUrl}/agriculture/rfqs/$rid/reply'),
          headers: await _agriHeaders(json: true),
          body: jsonEncode({
            'price_per_unit_cents': int.tryParse(replyPriceCtrl.text.trim()) ?? 0,
            'eta_days': int.tryParse(replyEtaCtrl.text.trim()),
            'message': replyMsgCtrl.text.trim().isEmpty ? null : replyMsgCtrl.text.trim(),
            'supplier_wallet_id': replyWalletCtrl.text.trim().isEmpty ? null : replyWalletCtrl.text.trim(),
          }));
      opsOut = '${r.statusCode}: ${r.body}';
      _loadOps();
    } catch (e) {
      opsOut = 'error: $e';
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _createOrderFromListing(int lid) async {
    setState(() => orderOut = 'Creating order...');
    try {
      final r = await http.post(Uri.parse('${widget.baseUrl}/agriculture/orders'),
          headers: await _agriHeaders(json: true),
          body: jsonEncode({
            'listing_id': lid,
            'quantity': double.tryParse(orderQtyCtrl.text.trim()),
            'unit': orderUnitCtrl.text.trim().isEmpty ? null : orderUnitCtrl.text.trim(),
            'buyer_wallet_id': orderBuyerCtrl.text.trim().isEmpty ? null : orderBuyerCtrl.text.trim(),
            'seller_wallet_id': orderSellerCtrl.text.trim().isEmpty ? null : orderSellerCtrl.text.trim(),
            'price_cents': int.tryParse(lPriceCtrl.text.trim()) ?? 0,
            'buyer_notes': orderBuyerNotesCtrl.text.trim().isEmpty ? null : orderBuyerNotesCtrl.text.trim(),
            'supplier_notes': orderSupplierNotesCtrl.text.trim().isEmpty ? null : orderSupplierNotesCtrl.text.trim(),
          }));
      orderOut = '${r.statusCode}: ${r.body}';
      _loadOps();
    } catch (e) {
      orderOut = 'error: $e';
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _updateOrderStatus(int oid, String status, {String? buyerNote, String? supplierNote}) async {
    setState(() => orderOut = 'Updating order...');
    try {
      final body = {
        'status': status,
        if (buyerNote != null) 'buyer_notes': buyerNote,
        if (supplierNote != null) 'supplier_notes': supplierNote,
      };
      final r = await http.patch(Uri.parse('${widget.baseUrl}/agriculture/orders/$oid'),
          headers: await _agriHeaders(json: true), body: jsonEncode(body));
      orderOut = '${r.statusCode}: ${r.body}';
      _loadOps();
    } catch (e) {
      orderOut = 'error: $e';
    } finally {
      if (mounted) setState(() {});
    }
  }

  Widget _listingCard(Map<String, dynamic> p, L10n l) {
    final id = p['id'] ?? '';
    final title = (p['title'] ?? '').toString();
    final cat = (p['category'] ?? '').toString();
    final price = p['price_cents'] ?? '';
    final unit = (p['unit'] ?? '').toString();
    final minQty = p['min_qty'];
    final city = (p['city'] ?? '').toString();
    final origin = (p['origin'] ?? '').toString();
    final status = (p['status'] ?? '').toString();
    final cert = (p['certifications'] ?? '').toString();
    final img = (p['image_url'] ?? '').toString();
    final lead = p['lead_time_days'];
    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: Tokens.colorAgricultureLivestock.withValues(alpha: .1),
            image: img.isNotEmpty ? DecorationImage(image: NetworkImage(img), fit: BoxFit.cover) : null,
          ),
          child: img.isEmpty
              ? const Center(child: Icon(Icons.eco_outlined, size: 40, color: Colors.white70))
              : null,
        ),
        const SizedBox(height: 8),
        Text(title.isEmpty ? 'Listing $id' : title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 4, children: [
          if (cat.isNotEmpty) Chip(label: Text(cat)),
          if (origin.isNotEmpty) Chip(label: Text('Origin $origin')),
          if (cert.isNotEmpty) Chip(label: Text(cert)),
          Chip(label: Text(status)),
        ]),
        Text('$price SYP${unit.isNotEmpty ? ' /$unit' : ''} · MOQ ${minQty ?? '-'} ${unit.isNotEmpty ? unit : ''}',
            style: Theme.of(context).textTheme.bodySmall),
        if (city.isNotEmpty)
          Text(city, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Row(
          children: [
            if ((p['availability_from'] ?? '').toString().isNotEmpty)
              Chip(
                  label: Text(
                      'Available from ${(p['availability_from'] ?? '').toString().split('T').first}')),
            if ((p['availability_to'] ?? '').toString().isNotEmpty)
              Chip(
                  label:
                      Text('Until ${(p['availability_to'] ?? '').toString().split('T').first}')),
          ],
        ),
        if (lead != null) Text('Lead time: $lead days', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
                onPressed: () => _createOrderFromListing(id is int ? id : int.tryParse(id.toString()) ?? 0),
                child: Text(l.isArabic ? 'طلب' : 'Order')),
            ElevatedButton(
                onPressed: () => _openListingDetail(p, l),
                child: Text(l.isArabic ? 'طلب عرض' : 'Request quote')),
          ],
        )
      ]),
    );
  }

  void _openListingDetail(Map<String, dynamic> p, L10n l) {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) {
          final id = p['id'] ?? '';
          final title = (p['title'] ?? '').toString();
          final desc = (p['description'] ?? '').toString();
          final cat = (p['category'] ?? '').toString();
          final varr = (p['variety'] ?? '').toString();
          final pack = (p['pack_size'] ?? '').toString();
          final price = p['price_cents'] ?? '';
          final unit = (p['unit'] ?? '').toString();
          final minQty = p['min_qty'] ?? '';
          final city = (p['city'] ?? '').toString();
          final origin = (p['origin'] ?? '').toString();
    final cert = (p['certifications'] ?? '').toString();
    final status = (p['status'] ?? '').toString();
    final lead = p['lead_time_days'];
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title.isEmpty ? 'Listing $id' : title,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    if (cat.isNotEmpty) Chip(label: Text(cat)),
                    if (varr.isNotEmpty) Chip(label: Text(varr)),
                    if (origin.isNotEmpty) Chip(label: Text('Origin $origin')),
                    if (cert.isNotEmpty) Chip(label: Text(cert)),
                    Chip(label: Text(status)),
                  ]),
                  const SizedBox(height: 8),
                  Text('$price SYP${unit.isNotEmpty ? ' /$unit' : ''} · MOQ $minQty'),
                  if (pack.isNotEmpty) Text('Pack: $pack'),
                  if (city.isNotEmpty) Text('City: $city'),
                  if ((p['availability_from'] ?? '').toString().isNotEmpty)
                    Text('From ${(p['availability_from'] ?? '').toString()}'),
                  if ((p['availability_to'] ?? '').toString().isNotEmpty)
                    Text('To ${(p['availability_to'] ?? '').toString()}'),
                  if (lead != null) Text('Lead time: $lead days'),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(desc),
                  ],
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: () { Navigator.pop(context); _openRFQSheet(title); }, child: Text(l.isArabic ? 'طلب عرض' : 'Request quote')),
                ],
              ),
            ),
          );
        });
  }

  void _openRFQSheet(String product) {
    rfqProductCtrl.text = product;
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) {
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Request quote', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 8),
                  TextField(controller: rfqProductCtrl, decoration: const InputDecoration(labelText: 'Product')),
                  TextField(controller: rfqQtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity')),
                  TextField(controller: rfqUnitCtrl, decoration: const InputDecoration(labelText: 'Unit (kg/ton/etc)')),
                  TextField(controller: rfqCityCtrl, decoration: const InputDecoration(labelText: 'City')),
                  TextField(controller: rfqDateCtrl, decoration: const InputDecoration(labelText: 'Target date (ISO)')),
                  TextField(controller: rfqBuyerCtrl, decoration: const InputDecoration(labelText: 'Buyer wallet (optional)')),
                  TextField(controller: rfqNotesCtrl, decoration: const InputDecoration(labelText: 'Notes')),
                  const SizedBox(height: 8),
                  ElevatedButton(onPressed: () { Navigator.pop(context); _createRFQ(); }, child: const Text('Send RFQ')),
                  if (rfqOut.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(rfqOut)),
                ],
              ),
            ),
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final bg = const AppBG();
    final buyer = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GlassPanel(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.isArabic ? 'سوق المنتجات الزراعية' : 'Agri Marketplace',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                        width: 200,
                        child: TextField(
                          controller: qCtrl,
                          decoration: const InputDecoration(labelText: 'Search'),
                        )),
                    SizedBox(
                        width: 160,
                        child: TextField(
                          controller: cityCtrl,
                          decoration: const InputDecoration(labelText: 'City/Region'),
                        )),
                    SizedBox(
                        width: 160,
                        child: TextField(
                          controller: catCtrl,
                          decoration: const InputDecoration(labelText: 'Category'),
                        )),
                    SizedBox(
                        width: 140,
                        child: TextField(
                          controller: statusCtrl,
                          decoration: const InputDecoration(labelText: 'Status'),
                        )),
                    ElevatedButton(onPressed: _loadListings, child: Text(l.isArabic ? 'تحديث' : 'Refresh')),
                    if (loadingListings) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ),
                if (listingsOut.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(listingsOut)),
              ],
            )),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: listings.map((p) => SizedBox(width: 320, child: _listingCard(p, l))).toList(),
        ),
      ],
    );

    final operator = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (opsLoading) const LinearProgressIndicator(minHeight: 2),
        Text(opsOut, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        GlassPanel(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Create listing', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(width: 200, child: TextField(controller: lTitleCtrl, decoration: const InputDecoration(labelText: 'Title'))),
                SizedBox(width: 140, child: TextField(controller: lCatCtrl, decoration: const InputDecoration(labelText: 'Category'))),
                SizedBox(width: 140, child: TextField(controller: lVarCtrl, decoration: const InputDecoration(labelText: 'Variety'))),
                SizedBox(width: 140, child: TextField(controller: lPriceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price (cents)'))),
                SizedBox(width: 140, child: TextField(controller: lMinCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'MOQ'))),
                SizedBox(width: 120, child: TextField(controller: lUnitCtrl, decoration: const InputDecoration(labelText: 'Unit'))),
                SizedBox(width: 140, child: TextField(controller: lCityCtrl, decoration: const InputDecoration(labelText: 'City'))),
                SizedBox(width: 140, child: TextField(controller: lOriginCtrl, decoration: const InputDecoration(labelText: 'Origin'))),
                SizedBox(width: 180, child: TextField(controller: lCertCtrl, decoration: const InputDecoration(labelText: 'Certifications'))),
                SizedBox(width: 140, child: TextField(controller: lStatusCtrl, decoration: const InputDecoration(labelText: 'Status'))),
                SizedBox(width: 200, child: TextField(controller: lSellerCtrl, decoration: const InputDecoration(labelText: 'Seller wallet'))),
                ElevatedButton(onPressed: _createListing, child: const Text('Save listing')),
              ],
            ),
            if (listingOut.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(listingOut)),
          ]),
        ),
        const SizedBox(height: 12),
        GlassPanel(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Manage listing', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                    width: 120,
                    child: TextField(
                        controller: opListingIdCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Listing ID'))),
                SizedBox(
                    width: 140,
                    child: TextField(
                        controller: opListingPriceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'New price (cents)'))),
                SizedBox(
                    width: 140,
                    child: TextField(
                        controller: opListingStatusCtrl,
                        decoration: const InputDecoration(labelText: 'Status (listed/paused/out_of_stock)'))),
                ElevatedButton(
                    onPressed: () {
                      final id = int.tryParse(opListingIdCtrl.text.trim()) ?? 0;
                      if (id > 0 && opListingPriceCtrl.text.trim().isNotEmpty) {
                        _updateListingPrice(id, int.tryParse(opListingPriceCtrl.text.trim()) ?? 0);
                      }
                    },
                    child: const Text('Update price')),
                OutlinedButton(
                    onPressed: () {
                      final id = int.tryParse(opListingIdCtrl.text.trim()) ?? 0;
                      if (id > 0 && opListingStatusCtrl.text.trim().isNotEmpty) {
                        _updateListingStatus(id, opListingStatusCtrl.text.trim());
                      }
                    },
                    child: const Text('Update status')),
              ],
            ),
          ]),
        ),
        const SizedBox(height: 12),
        if (rfqs.isNotEmpty)
          GlassPanel(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('RFQs', style: TextStyle(fontWeight: FontWeight.w700)),
                  SizedBox(
                      width: 160,
                      child: TextField(controller: rfqStatusCtrl, decoration: const InputDecoration(labelText: 'Status filter'))),
                ],
              ),
              const SizedBox(height: 8),
              ...rfqs.map((r) {
                final id = r['id'] ?? '';
                final rid = id is int ? id : int.tryParse(id.toString()) ?? 0;
                final product = (r['product'] ?? '').toString();
                final qty = r['quantity'] ?? '';
                final unit = (r['unit'] ?? '').toString();
                final city = (r['city'] ?? '').toString();
                final status = (r['status'] ?? '').toString();
                final replies = rfqReplies[rid] ?? const [];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: GlassPanel(
                    padding: const EdgeInsets.all(10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('$product (RFQ #$id)', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('$qty $unit · $city · $status', style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          SizedBox(
                              width: 120,
                              child: TextField(controller: replyPriceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price/unit (cents)'))),
                          SizedBox(
                              width: 120,
                              child: TextField(controller: replyEtaCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ETA days'))),
                          SizedBox(
                              width: 200,
                              child: TextField(controller: replyMsgCtrl, decoration: const InputDecoration(labelText: 'Message'))),
                          SizedBox(
                              width: 200,
                              child: TextField(controller: replyWalletCtrl, decoration: const InputDecoration(labelText: 'Supplier wallet'))),
                          ElevatedButton(onPressed: () => _replyRFQ(rid), child: const Text('Reply')),
                          OutlinedButton(onPressed: () => _loadReplies(rid), child: Text('Replies (${replies.length})')),
                        ],
                      ),
                      if (replies.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: replies.map((rep) {
                              final pp = rep['price_per_unit_cents'] ?? '';
                              final eta = rep['eta_days'] ?? '';
                              final msg = (rep['message'] ?? '').toString();
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text('Reply: $pp cents · ETA $eta d · ${msg.isEmpty ? '' : msg}'),
                              );
                            }).toList(),
                          ),
                        ),
                    ]),
                  ),
                );
              }).toList(),
            ]),
          ),
        const SizedBox(height: 12),
        if (orders.isNotEmpty)
          GlassPanel(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Orders', style: TextStyle(fontWeight: FontWeight.w700)),
                  TextButton(
                      onPressed: () => setState(() => showOrderForm = !showOrderForm),
                      child: Text(showOrderForm ? 'Hide order form' : 'Quick create order')),
                ],
              ),
              const SizedBox(height: 4),
              SizedBox(
                  width: 200,
                  child: TextField(
                      controller: orderStatusFilterCtrl,
                      decoration: const InputDecoration(labelText: 'Status filter (pending/...)'),
                      onSubmitted: (_) => _loadOps())),
              if (showOrderForm) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SizedBox(width: 120, child: TextField(controller: orderQtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Qty'))),
                    SizedBox(width: 120, child: TextField(controller: orderUnitCtrl, decoration: const InputDecoration(labelText: 'Unit'))),
                    SizedBox(width: 160, child: TextField(controller: orderBuyerCtrl, decoration: const InputDecoration(labelText: 'Buyer wallet'))),
                    SizedBox(width: 160, child: TextField(controller: orderSellerCtrl, decoration: const InputDecoration(labelText: 'Seller wallet'))),
                    SizedBox(width: 200, child: TextField(controller: orderBuyerNotesCtrl, decoration: const InputDecoration(labelText: 'Buyer notes'))),
                    SizedBox(width: 200, child: TextField(controller: orderSupplierNotesCtrl, decoration: const InputDecoration(labelText: 'Supplier notes'))),
                    ElevatedButton(
                        onPressed: () {
                          // uses price from listing form; lid must be chosen manually
                          final lid = listings.isNotEmpty
                              ? (listings.first['id'] is int
                                  ? listings.first['id']
                                  : int.tryParse(listings.first['id'].toString()) ?? 0)
                              : 0;
                          if (lid > 0) _createOrderFromListing(lid);
                        },
                        child: const Text('Create order from first listing')),
                    if (orderOut.isNotEmpty) Text(orderOut),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              ...orders.map((o) {
                final id = o['id'] ?? '';
                final status = (o['status'] ?? '').toString();
                final qty = o['quantity'] ?? '';
                final unit = (o['unit'] ?? '').toString();
                final price = o['price_cents'] ?? '';
                final buyerNote = (o['buyer_notes'] ?? '').toString();
                final supplierNote = (o['supplier_notes'] ?? '').toString();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: GlassPanel(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Order #$id · $qty $unit'),
                            Row(
                              children: [
                                Text('$price SYP · $status', style: Theme.of(context).textTheme.bodySmall),
                                const SizedBox(width: 8),
                                DropdownButton<String>(
                                  value: status,
                                  items: const [
                                    DropdownMenuItem(value: 'pending', child: Text('pending')),
                                    DropdownMenuItem(value: 'confirmed', child: Text('confirmed')),
                                    DropdownMenuItem(value: 'canceled', child: Text('canceled')),
                                    DropdownMenuItem(value: 'fulfilled', child: Text('fulfilled')),
                                  ],
                                  onChanged: (v) {
                                    if (v != null) {
                                      _updateOrderStatus(id is int ? id : int.tryParse(id.toString()) ?? 0, v);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          decoration: const InputDecoration(labelText: 'Buyer notes'),
                          controller: TextEditingController(text: buyerNote),
                          onSubmitted: (val) => _updateOrderStatus(id is int ? id : int.tryParse(id.toString()) ?? 0, status, buyerNote: val),
                        ),
                        TextField(
                          decoration: const InputDecoration(labelText: 'Supplier notes'),
                          controller: TextEditingController(text: supplierNote),
                          onSubmitted: (val) => _updateOrderStatus(id is int ? id : int.tryParse(id.toString()) ?? 0, status, supplierNote: val),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ]),
          ),
      ],
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Agri Marketplace'),
        backgroundColor: Colors.transparent,
        bottom: TabBar(
          controller: _tab,
          tabs: [
            Tab(text: l.isArabic ? 'مشتري' : 'Buyer'),
            Tab(text: l.isArabic ? 'مشغل' : 'Operator'),
          ],
        ),
      ),
      body: Stack(
        children: [
          bg,
          Positioned.fill(
              child: SafeArea(
            child: TabBarView(
              controller: _tab,
              children: [buyer, operator],
            ),
          )),
        ],
      ),
    );
  }
}
