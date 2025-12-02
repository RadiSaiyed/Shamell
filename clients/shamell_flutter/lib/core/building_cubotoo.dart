import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show AppBG;
import 'glass.dart';
import 'l10n.dart';
import 'design_tokens.dart';

Future<Map<String, String>> _hdrBuilding({bool json = false}) async {
  final sp = await SharedPreferences.getInstance();
  final h = <String, String>{};
  if (json) h['content-type'] = 'application/json';
  final cookie = sp.getString('sa_cookie');
  if (cookie != null && cookie.isNotEmpty) h['sa_cookie'] = cookie;
  return h;
}

class BuildingCubotooPage extends StatefulWidget {
  final String baseUrl;
  const BuildingCubotooPage({super.key, required this.baseUrl});

  @override
  State<BuildingCubotooPage> createState() => _BuildingCubotooPageState();
}

class _BuildingCubotooPageState extends State<BuildingCubotooPage> with TickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  final qCtrl = TextEditingController();
  final cityCtrl = TextEditingController();
  final catCtrl = TextEditingController();
  final minPriceCtrl = TextEditingController();
  final maxPriceCtrl = TextEditingController();
  List<Map<String, dynamic>> products = const [];
  bool loading = false;
  String out = '';
  String walletId = '';

  List<Map<String, dynamic>> orders = const [];
  String ordersOut = '';
  bool ordersLoading = false;
  final sellerWalletCtrl = TextEditingController();
  final orderStatusFilterCtrl = TextEditingController();
  final attachShipmentCtrl = TextEditingController();
  // Supplier product creation
  final prodNameCtrl = TextEditingController();
  final prodPriceCtrl = TextEditingController();
  final prodCurrencyCtrl = TextEditingController(text: 'SYP');
  final prodSkuCtrl = TextEditingController();
  final prodImageCtrl = TextEditingController();
  final prodCategoryCtrl = TextEditingController();
  final prodDescCtrl = TextEditingController();
  String prodOut = '';
  Map<int, List<Map<String, dynamic>>> orderEvents = {};
  String _selectedCategory = '';

  static const List<Map<String, dynamic>> _categories = [
    {"name": "Custom Requests", "children": []},
    {
      "name": "Structural Construction",
      "children": [
        {
          "name": "Masonry Blocks",
          "children": [
            {"name": "Bricks", "children": []}
          ]
        },
        {
          "name": "Masonry Accessories",
          "children": [
            {"name": "Joint Reinforcement", "children": []},
            {"name": "Masonry Barriers", "children": []}
          ]
        },
        {
          "name": "Light Shafts & Reveal Windows",
          "children": [
            {"name": "Concrete Light Shafts & Accessories", "children": []},
            {"name": "Reveal Windows & Reveal Frames", "children": []}
          ]
        },
        {
          "name": "Foundation Wall Protection",
          "children": [
            {"name": "Dimple Membranes & Accessories", "children": []}
          ]
        },
        {
          "name": "Structural Bearings",
          "children": [
            {"name": "Ceiling Bearings & Wall Bearings", "children": []}
          ]
        }
      ]
    },
    {
      "name": "Drywall & Panels",
      "children": [
        {
          "name": "Lightweight Panels & Multi-Layer Panels",
          "children": [
            {"name": "Lightweight Panels", "children": []}
          ]
        },
        {
          "name": "Drywall Profiles & Accessories",
          "children": [
            {"name": "Wall Profiles", "children": []},
            {"name": "Drywall Screws & Fasteners", "children": []},
            {"name": "Drywall Profile Accessories", "children": []}
          ]
        }
      ]
    },
    {
      "name": "Plasters & Paints",
      "children": [
        {
          "name": "Primers, Bonding Agents & Fillers",
          "children": [
            {"name": "Primers & Bonding Agents", "children": []},
            {"name": "Drywall Adhesives & Fillers", "children": []}
          ]
        },
        {
          "name": "Plasters & Accessories",
          "children": [
            {"name": "Base Plasters", "children": []},
            {"name": "Smooth & White Plasters", "children": []},
            {"name": "Leveling Plasters", "children": []},
            {"name": "Reinforcement Mesh & Fabrics", "children": []},
            {"name": "Plaster Profiles", "children": []}
          ]
        },
        {
          "name": "Finish Plasters",
          "children": [
            {"name": "Mineral Finish Plasters", "children": []},
            {"name": "Synthetic Finish Plasters", "children": []}
          ]
        },
        {
          "name": "Paints",
          "children": [
            {"name": "Impregnation & Priming", "children": []},
            {"name": "Facade Paints", "children": []},
            {"name": "Interior Wall Paints", "children": []}
          ]
        }
      ]
    },
    {
      "name": "Building Envelope",
      "children": [
        {
          "name": "Facade Cladding",
          "children": [
            {"name": "Wood Facade Cladding", "children": []},
            {"name": "Facade Accessories", "children": []}
          ]
        },
        {
          "name": "Wood Fiber Insulation & Blow-In Insulation",
          "children": [
            {"name": "Soft Fiber Boards for Roof & Wall", "children": []}
          ]
        },
        {
          "name": "Flat Roof",
          "children": [
            {"name": "Liquid Waterproofing", "children": []},
            {"name": "Protection Mats & Fleece", "children": []}
          ]
        },
        {
          "name": "Pitched Roof",
          "children": [
            {"name": "Roof Tiles", "children": []}
          ]
        },
        {
          "name": "Foils & Adhesive Technology",
          "children": [
            {"name": "Adhesive Technology & Accessories", "children": []}
          ]
        }
      ]
    },
    {
      "name": "Interior Construction & Fire Protection",
      "children": [
        {
          "name": "Interior Wood Products",
          "children": [
            {"name": "Floor Boards & Rauspund", "children": []}
          ]
        },
        {
          "name": "Raw Panels & Decorative Panels",
          "children": [
            {"name": "Edges & Accessories", "children": []}
          ]
        },
        {
          "name": "Fire Protection Panels",
          "children": [
            {"name": "Fillings & Fire Protection Accessories", "children": []}
          ]
        }
      ]
    },
    {
      "name": "Doors, Stairs, Roof Windows",
      "children": [
        {
          "name": "Stairs",
          "children": [
            {"name": "Acoustic Separation Joints", "children": []},
            {"name": "Stair Bearings", "children": []},
            {"name": "Landing Supports", "children": []}
          ]
        }
      ]
    },
    {
      "name": "Formwork Materials",
      "children": [
        {
          "name": "Construction Timber",
          "children": [
            {"name": "Formwork Panels", "children": []},
            {"name": "Formwork Beams", "children": []},
            {"name": "Squared Timber", "children": []},
            {"name": "Boards", "children": []},
            {"name": "Strips & Wedges", "children": []}
          ]
        },
        {
          "name": "Reinforcement",
          "children": [
            {"name": "Rebar Connectors", "children": []}
          ]
        },
        {
          "name": "Formwork Accessories",
          "children": [
            {"name": "Distance Holders", "children": []},
            {"name": "Anchor Supports", "children": []},
            {"name": "Formwork Strips & Profiles", "children": []},
            {"name": "Column Formwork Tubes", "children": []},
            {"name": "Concrete Protection Mats", "children": []},
            {"name": "Formwork Systems", "children": []},
            {"name": "Props & Ceiling Supports", "children": []}
          ]
        }
      ]
    },
    {
      "name": "Insulation Materials",
      "children": [
        {
          "name": "Thermal Insulation",
          "children": [
            {"name": "Rock Wool", "children": []},
            {"name": "Glass Wool", "children": []},
            {"name": "EPS Expanded Polystyrene", "children": []},
            {"name": "XPS Extruded Polystyrene", "children": []},
            {"name": "PUR & PIR Rigid Foam", "children": []},
            {"name": "Foam Glass", "children": []},
            {"name": "Special Insulation Materials", "children": []}
          ]
        }
      ]
    },
    {
      "name": "Finishing Profiles",
      "children": [
        {
          "name": "Tile & Floor Profiles",
          "children": [
            {"name": "Expansion Profiles", "children": []}
          ]
        }
      ]
    },
    {
      "name": "Road Construction",
      "children": [
        {
          "name": "Drainage Channels",
          "children": [
            {"name": "Concrete Channels & Covers", "children": []},
            {"name": "Polymer Concrete Channels & Covers", "children": []}
          ]
        },
        {
          "name": "Geotextiles & Bitumen Products",
          "children": [
            {"name": "Geofleece", "children": []},
            {"name": "Geotextile Fabric", "children": []},
            {"name": "Filter Fabrics & Drainage", "children": []},
            {"name": "Special Bitumen Products", "children": []}
          ]
        }
      ]
    },
    {
      "name": "Gardening",
      "children": [
        {
          "name": "Garden Slabs & Edging",
          "children": [
            {"name": "Pedestal Supports", "children": []},
            {"name": "Accessories for Slabs & Edging", "children": []}
          ]
        },
        {
          "name": "Garden Accessories",
          "children": [
            {"name": "Jute Fabric", "children": []}
          ]
        }
      ]
    },
    {
      "name": "Pipes, Shafts, Covers",
      "children": [
        {
          "name": "Shaft Covers",
          "children": [
            {"name": "Cast-Iron Covers", "children": []},
            {"name": "Floor Drains", "children": []},
            {"name": "Accessories for Covers", "children": []}
          ]
        },
        {
          "name": "Concrete Shafts & Pipes",
          "children": [
            {"name": "Concrete Shafts", "children": []},
            {"name": "Water Collectors & Septic Tanks", "children": []},
            {"name": "Cable Shafts", "children": []}
          ]
        },
        {
          "name": "Pipes & Fittings",
          "children": [
            {"name": "HPVC Pipes & Fittings", "children": []},
            {"name": "PE Pipes & Fittings", "children": []},
            {"name": "PP Pipes & Fittings", "children": []},
            {"name": "Shaft Sleeves", "children": []},
            {"name": "Accessories for Pipes & Fittings", "children": []},
            {"name": "Cable Protection Pipes & Fittings", "children": []}
          ]
        }
      ]
    },
    {
      "name": "Interior Flooring",
      "children": [
        {
          "name": "Ceramic Tiles",
          "children": [
            {"name": "Wall Tiles", "children": []},
            {"name": "Floor Tiles", "children": []}
          ]
        }
      ]
    },
    {
      "name": "Mortars & Construction Chemicals",
      "children": [
        {
          "name": "Concrete Production Additives",
          "children": [
            {"name": "Concrete Additives", "children": []},
            {"name": "Release Agents & Equipment Protection", "children": []},
            {"name": "Primers & Activators", "children": []}
          ]
        },
        {
          "name": "Concrete Sealing",
          "children": [
            {"name": "Joint Sealants", "children": []},
            {"name": "Surface Sealants", "children": []}
          ]
        },
        {
          "name": "Concrete Protection & Repair",
          "children": [
            {"name": "Repair Mortars", "children": []},
            {"name": "Grout & Installation Mortars", "children": []},
            {"name": "Corrosion Protection", "children": []},
            {"name": "Concrete Protection Systems", "children": []}
          ]
        },
        {
          "name": "Adhesives & Sealants",
          "children": [
            {"name": "Joint Sealants", "children": []},
            {"name": "Foams & Fillers", "children": []},
            {"name": "Construction Adhesives", "children": []}
          ]
        },
        {
          "name": "Flooring & Tiling Compounds",
          "children": [
            {"name": "Tile Adhesives", "children": []},
            {"name": "Grout", "children": []},
            {"name": "Parquet Adhesives", "children": []},
            {"name": "Decoupling & Waterproofing", "children": []},
            {"name": "Reinforcement Mats", "children": []},
            {"name": "Leveling Compounds", "children": []},
            {"name": "Screeds & Subfloors", "children": []},
            {"name": "Coatings & Care Products", "children": []}
          ]
        },
        {
          "name": "Dry Concrete & Mortar",
          "children": [
            {"name": "Masonry Mortar", "children": []},
            {"name": "Dry Concrete", "children": []}
          ]
        },
        {
          "name": "Binders & Aggregates",
          "children": [
            {"name": "Cement", "children": []},
            {"name": "Gravel, Grit, Sand", "children": []}
          ]
        }
      ]
    },
    {
      "name": "Tools",
      "children": [
        {
          "name": "Masonry & Plastering Tools",
          "children": [
            {"name": "Trowels", "children": []}
          ]
        },
        {
          "name": "Painting Tools",
          "children": [
            {"name": "Sponges", "children": []},
            {"name": "Foam Guns & Sealant Guns", "children": []}
          ]
        },
        {
          "name": "Cutting & Grinding Tools",
          "children": [
            {"name": "Grinding Tools", "children": []}
          ]
        },
        {
          "name": "Long-Handle Tools",
          "children": [
            {"name": "Brooms & Brushes", "children": []}
          ]
        },
        {
          "name": "Measuring Tools",
          "children": [
            {"name": "Alignment Tools", "children": []}
          ]
        }
      ]
    },
    {
      "name": "Machines & Equipment",
      "children": [
        {
          "name": "Drilling & Chiseling",
          "children": [
            {"name": "Cordless Drilling & Chiseling", "children": []},
            {"name": "Drilling Accessories", "children": []}
          ]
        },
        {
          "name": "Mixing & Vibrating",
          "children": [
            {"name": "Mixing Accessories", "children": []}
          ]
        },
        {
          "name": "Milling & Planing",
          "children": [
            {"name": "Electric Mills & Planers", "children": []}
          ]
        },
        {
          "name": "Vacuuming, Pumping, Cleaning",
          "children": [
            {"name": "Accessories for Pumps & Vacuums", "children": []}
          ]
        },
        {
          "name": "Sawing & Cutting",
          "children": [
            {"name": "Accessories for Cutting & Grinding", "children": []}
          ]
        }
      ]
    },
    {
      "name": "Signaling & Barriers",
      "children": [
        {
          "name": "Barrier Material",
          "children": [
            {"name": "Barriers", "children": []},
            {"name": "Construction Fences", "children": []},
            {"name": "Construction Panels", "children": []}
          ]
        },
        {
          "name": "Ramps & Bridges",
          "children": [
            {"name": "Trench Bridges", "children": []}
          ]
        }
      ]
    },
    {
      "name": "Fastening Technology",
      "children": [
        {
          "name": "Screws",
          "children": [
            {"name": "Concrete Screws", "children": []}
          ]
        },
        {
          "name": "Nails & Pins",
          "children": [
            {"name": "Plain Nails", "children": []}
          ]
        },
        {
          "name": "Wood Connectors",
          "children": [
            {"name": "Ring Shank Nails & Anchor Nails", "children": []}
          ]
        },
        {
          "name": "Mounting Material",
          "children": [
            {"name": "Wire & Wire Binders", "children": []}
          ]
        },
        {
          "name": "Dowel Technology",
          "children": [
            {"name": "Insulation Fasteners", "children": []},
            {"name": "General Fastening", "children": []},
            {"name": "Dowel Accessories", "children": []}
          ]
        }
      ]
    },
    {
      "name": "Operational Supplies",
      "children": [
        {"name": "Electrical Supplies", "children": []},
        {"name": "Heating & Cooling", "children": []},
        {
          "name": "Workplace Equipment",
          "children": [
            {"name": "General Equipment", "children": []},
            {"name": "Containers", "children": []}
          ]
        },
        {
          "name": "Consumables",
          "children": [
            {"name": "Cleaning Agents", "children": []},
            {"name": "Adhesive Tapes", "children": []}
          ]
        }
      ]
    }
  ];

  @override
  void initState() {
    super.initState();
    _loadWallet();
    _loadProducts();
    _loadOrders();
  }

  @override
  void dispose() {
    _tab.dispose();
    qCtrl.dispose();
    cityCtrl.dispose();
    catCtrl.dispose();
    minPriceCtrl.dispose();
    maxPriceCtrl.dispose();
    sellerWalletCtrl.dispose();
    orderStatusFilterCtrl.dispose();
    attachShipmentCtrl.dispose();
    prodNameCtrl.dispose();
    prodPriceCtrl.dispose();
    prodCurrencyCtrl.dispose();
    prodSkuCtrl.dispose();
    prodImageCtrl.dispose();
    prodCategoryCtrl.dispose();
    prodDescCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadWallet() async {
    try {
      final sp = await SharedPreferences.getInstance();
      setState(() => walletId = sp.getString('wallet_id') ?? '');
    } catch (_) {}
  }

  Future<void> _loadProducts() async {
    setState(() {
      loading = true;
      out = '';
    });
    await _loadWallet();
    try {
      final params = {
        'limit': '200',
        if (qCtrl.text.isNotEmpty) 'q': qCtrl.text.trim(),
        if (cityCtrl.text.isNotEmpty) 'city': cityCtrl.text.trim(),
        if (catCtrl.text.isNotEmpty) 'category': catCtrl.text.trim(),
        if (minPriceCtrl.text.isNotEmpty) 'min_price': minPriceCtrl.text.trim(),
        if (maxPriceCtrl.text.isNotEmpty) 'max_price': maxPriceCtrl.text.trim(),
      };
      final uri = Uri.parse('${widget.baseUrl}/building/materials').replace(queryParameters: params);
      final r = await http.get(uri, headers: await _hdrBuilding());
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is List) {
          final arr = body.map<Map<String, dynamic>>((e) => (e as Map).cast()).toList();
          // client-side filters for price/city/category even if backend ignores
          double? minp = double.tryParse(minPriceCtrl.text.trim());
          double? maxp = double.tryParse(maxPriceCtrl.text.trim());
          final city = cityCtrl.text.trim().toLowerCase();
          final cat = catCtrl.text.trim().toLowerCase();
          products = arr.where((p) {
            try {
              final price = p['price_cents'] is int
                  ? (p['price_cents'] as int).toDouble()
                  : double.tryParse((p['price_cents'] ?? '').toString()) ?? 0;
              final pcity = (p['city'] ?? '').toString().toLowerCase();
              final pcat = (p['category'] ?? '').toString().toLowerCase();
              if (minp != null && price < minp) return false;
              if (maxp != null && price > maxp) return false;
              if (city.isNotEmpty && (pcity.isEmpty || !pcity.contains(city))) return false;
              if (cat.isNotEmpty && (pcat.isEmpty || !pcat.contains(cat))) return false;
              return true;
            } catch (_) {
              return true;
            }
          }).toList();
          out = '${products.length} items';
        } else {
          products = const [];
          out = 'bad response';
        }
      } else {
        products = const [];
        out = '${r.statusCode}: ${r.body}';
      }
    } catch (e) {
      products = const [];
      out = 'error: $e';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _placeOrder(Map<String, dynamic> product, int qty) async {
    final l = L10n.of(context);
    if (walletId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l.isArabic ? 'عيّن المحفظة أولاً' : 'Set your wallet first from Home')));
      return;
    }
    final priceCents = product['price_cents'] is int ? product['price_cents'] as int : int.tryParse((product['price_cents'] ?? '').toString()) ?? 0;
    final totalCents = priceCents * qty;
    setState(() => out = l.isArabic ? 'جارٍ إنشاء الطلب...' : 'Creating order...');
    try {
      final pid = product['id'];
      final body = jsonEncode({
        'product_id': pid,
        'quantity': qty,
        'buyer_wallet_id': walletId,
      });
      final r = await http.post(Uri.parse('${widget.baseUrl}/building/orders'),
          headers: await _hdrBuilding(json: true), body: body);
      out = '${r.statusCode}: ${r.body}\nTotal: ${totalCents / 100.0}';
      _loadOrders();
    } catch (e) {
      out = 'error: $e';
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadOrders() async {
    if (walletId.isEmpty) return;
    setState(() {
      ordersLoading = true;
      ordersOut = '';
    });
    try {
      final params = {
        'limit': '100',
        'buyer_wallet_id': walletId,
        if (sellerWalletCtrl.text.isNotEmpty) 'seller_wallet_id': sellerWalletCtrl.text.trim(),
        if (orderStatusFilterCtrl.text.isNotEmpty) 'status': orderStatusFilterCtrl.text.trim(),
      };
      final uri = Uri.parse('${widget.baseUrl}/building/orders').replace(queryParameters: params);
      final r = await http.get(uri, headers: await _hdrBuilding());
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is List) {
          final arr = body.map<Map<String, dynamic>>((e) => (e as Map).cast()).toList();
          if (orderStatusFilterCtrl.text.isNotEmpty) {
            final s = orderStatusFilterCtrl.text.trim().toLowerCase();
            orders = arr.where((o) => (o['status'] ?? '').toString().toLowerCase() == s).toList();
          } else {
            orders = arr;
          }
          ordersOut = '${orders.length} orders';
        } else {
          orders = const [];
          ordersOut = 'bad response';
        }
      } else {
        orders = const [];
        ordersOut = '${r.statusCode}: ${r.body}';
      }
    } catch (e) {
      orders = const [];
      ordersOut = 'error: $e';
    } finally {
      if (mounted) setState(() => ordersLoading = false);
    }
  }

  Future<void> _attachShipment(int orderId, String shipmentId) async {
    if (shipmentId.isEmpty) return;
    setState(() => ordersOut = 'Linking shipment...');
    try {
      final r = await http.post(
          Uri.parse('${widget.baseUrl}/building/orders/$orderId/attach_shipment'),
          headers: await _hdrBuilding(json: true),
          body: jsonEncode({'shipment_id': shipmentId}));
      ordersOut = '${r.statusCode}: ${r.body}';
    } catch (e) {
      ordersOut = 'error: $e';
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _createMaterial() async {
    setState(() => prodOut = 'Creating material...');
    try {
      final r = await http.post(Uri.parse('${widget.baseUrl}/commerce/products'),
          headers: await _hdrBuilding(json: true),
          body: jsonEncode({
            'name': prodNameCtrl.text.trim(),
            'price_cents': int.tryParse(prodPriceCtrl.text.trim()) ?? 0,
            'currency': prodCurrencyCtrl.text.trim().isEmpty ? 'SYP' : prodCurrencyCtrl.text.trim(),
            'sku': prodSkuCtrl.text.trim().isEmpty ? null : prodSkuCtrl.text.trim(),
            'image_url': prodImageCtrl.text.trim().isEmpty ? null : prodImageCtrl.text.trim(),
            'category': prodCategoryCtrl.text.trim().isNotEmpty ? prodCategoryCtrl.text.trim() : null,
            'description': prodDescCtrl.text.trim().isNotEmpty ? prodDescCtrl.text.trim() : null,
          }));
      prodOut = '${r.statusCode}: ${r.body}';
      _loadProducts();
    } catch (e) {
      prodOut = 'error: $e';
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _updateOrderStatus(int id, String status) async {
    setState(() => ordersOut = 'Updating order...');
    try {
      final r = await http.post(Uri.parse('${widget.baseUrl}/building/orders/$id/status'),
          headers: await _hdrBuilding(json: true), body: jsonEncode({'status': status}));
      ordersOut = '${r.statusCode}: ${r.body}';
      _loadOrders();
    } catch (e) {
      ordersOut = 'error: $e';
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadOrderEvents(int orderId) async {
    try {
      final r = await http.get(Uri.parse('${widget.baseUrl}/building/orders/$orderId'), headers: await _hdrBuilding());
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is Map && body['events'] is List) {
          orderEvents[orderId] = (body['events'] as List)
              .map<Map<String, dynamic>>((e) => (e as Map).cast<String, dynamic>())
              .toList();
          setState(() {});
        }
      }
    } catch (_) {}
  }

  void _openOrderDialog(Map<String, dynamic> product) async {
    final l = L10n.of(context);
    final qtyCtrl = TextEditingController(text: '1');
    final name = (product['name'] ?? '').toString();
    final price = product['price_cents'] ?? 0;
    final cur = (product['currency'] ?? 'SYP').toString();
    final res = await showDialog<int>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: Text(l.isArabic ? 'طلب مادة البناء' : 'Order building material'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${(price is int ? price / 100.0 : price).toString()} $cur'),
                TextField(
                  controller: qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: l.isArabic ? 'الكمية' : 'Quantity'),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.isArabic ? 'إلغاء' : 'Cancel')),
              ElevatedButton(
                  onPressed: () {
                    final q = int.tryParse(qtyCtrl.text.trim()) ?? 0;
                    if (q <= 0) return;
                    Navigator.pop(ctx, q);
                  },
                  child: Text(l.isArabic ? 'تأكيد' : 'Confirm')),
            ],
          );
        });
    if (res != null && res > 0) {
      _placeOrder(product, res);
    }
  }

  Widget _productCard(Map<String, dynamic> p, L10n l) {
    final name = (p['name'] ?? '').toString();
    final price = p['price_cents'] ?? 0;
    final cur = (p['currency'] ?? 'SYP').toString();
    final img = (p['image_url'] ?? '').toString();
    final sku = (p['sku'] ?? '').toString();
    final cat = (p['category'] ?? '').toString();
    final desc = (p['description'] ?? '').toString();
    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 120,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: Tokens.colorBuildingMaterials.withValues(alpha: .12),
                image: img.isNotEmpty ? DecorationImage(image: NetworkImage(img), fit: BoxFit.cover) : null),
            child: img.isEmpty ? const Center(child: Icon(Icons.construction, size: 40, color: Colors.white70)) : null,
          ),
          const SizedBox(height: 8),
          Text(name.isEmpty ? 'Product' : name, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('${price is int ? (price / 100.0).toStringAsFixed(2) : price} $cur', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface)),
          if (sku.isNotEmpty) Text('SKU: $sku', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface)),
          if (cat.isNotEmpty) Text(cat, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface)),
          if (desc.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                desc,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8)),
              ),
            ),
          const SizedBox(height: 6),
          ElevatedButton(
              onPressed: () => _openOrderDialog(p), child: Text(l.isArabic ? 'طلب' : 'Order')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    Widget _catTree(List<Map<String, dynamic>> nodes, {int depth = 0}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: nodes.map((n) {
          final children = (n['children'] as List?) ?? const [];
          final isLeaf = children.isEmpty;
          final label = n['name']?.toString() ?? '';
          final tile = ListTile(
            dense: true,
            contentPadding: EdgeInsets.only(left: depth * 8.0 + 8, right: 8),
            title: Text(label, style: TextStyle(fontWeight: isLeaf ? FontWeight.w600 : FontWeight.w500)),
            trailing: isLeaf ? null : const Icon(Icons.chevron_right, size: 16),
            onTap: () {
              setState(() {
                _selectedCategory = label;
                catCtrl.text = label;
              });
              _loadProducts();
            },
          );
          if (isLeaf) return tile;
          return ExpansionTile(
            initiallyExpanded: depth == 0 && label == "Structural Construction",
            title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            childrenPadding: EdgeInsets.zero,
            tilePadding: EdgeInsets.only(left: depth * 8.0 + 8, right: 8),
            children: [
              _catTree(children.cast<Map<String, dynamic>>(), depth: depth + 1),
            ],
            onExpansionChanged: (_) {},
          );
        }).toList(),
      );
    }

    final buyer = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GlassPanel(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.isArabic ? 'سوق مواد البناء' : 'Building Materials', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                const SizedBox(height: 8),
                Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
                width: 220,
                child: TextField(
                  controller: qCtrl,
                  decoration: InputDecoration(labelText: l.labelSearch),
                  onSubmitted: (_) => _loadProducts(),
                )),
            SizedBox(
                width: 160,
                child: TextField(
                  controller: cityCtrl,
                  decoration: const InputDecoration(labelText: 'City/Region'),
                  onSubmitted: (_) => _loadProducts(),
                )),
            SizedBox(
                width: 160,
                child: TextField(
                  controller: catCtrl,
                  decoration: const InputDecoration(labelText: 'Category'),
                  onSubmitted: (_) => _loadProducts(),
                )),
            SizedBox(
                width: 140,
                child: TextField(
                  controller: minPriceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Min price (cents)'),
                  onSubmitted: (_) => _loadProducts(),
                )),
            SizedBox(
                width: 140,
                child: TextField(
                  controller: maxPriceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Max price (cents)'),
                  onSubmitted: (_) => _loadProducts(),
                )),
            ElevatedButton(onPressed: _loadProducts, child: Text(l.reSearch)),
            if (walletId.isNotEmpty) Chip(label: Text('Wallet: $walletId')),
          ],
        ),
        if (out.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(out)),
              ],
            )),
        const SizedBox(height: 12),
        if (loading) const LinearProgressIndicator(minHeight: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 280,
              child: GlassPanel(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Categories', style: TextStyle(fontWeight: FontWeight.w700)),
                        if (_selectedCategory.isNotEmpty)
                          TextButton(
                              onPressed: () {
                                setState(() {
                                  _selectedCategory = '';
                                  catCtrl.text = '';
                                });
                                _loadProducts();
                              },
                              child: const Text('Clear')),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 520,
                      child: SingleChildScrollView(
                        child: _catTree(_categories),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: products.map((p) => SizedBox(width: 260, child: _productCard(p, l))).toList(),
              ),
            ),
          ],
        ),
      ],
    );

    final operator = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (orders.isNotEmpty)
          GlassPanel(
              padding: const EdgeInsets.all(12),
              child: Builder(builder: (ctx) {
                final totals = <String, int>{};
                int sum = 0;
                for (final o in orders) {
                  final st = (o['status'] ?? '').toString();
                  totals[st] = (totals[st] ?? 0) + 1;
                  final p = o['price_cents'];
                  if (p is int) sum += p;
                }
                final totalStr = (sum / 100.0).toStringAsFixed(2);
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('At-a-glance', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text('Total ${orders.length}')),
                      Chip(label: Text('Value $totalStr SYP')),
                      ...totals.entries.map((e) => Chip(label: Text('${e.key}: ${e.value}'))),
                    ],
                  )
                ]);
              })),
        const SizedBox(height: 12),
        GlassPanel(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Create material', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(width: 200, child: TextField(controller: prodNameCtrl, decoration: const InputDecoration(labelText: 'Name'))),
                SizedBox(width: 140, child: TextField(controller: prodPriceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price (cents)'))),
                SizedBox(width: 100, child: TextField(controller: prodCurrencyCtrl, decoration: const InputDecoration(labelText: 'Cur'))),
                SizedBox(width: 160, child: TextField(controller: prodCategoryCtrl, decoration: const InputDecoration(labelText: 'Category'))),
                SizedBox(width: 160, child: TextField(controller: prodSkuCtrl, decoration: const InputDecoration(labelText: 'SKU'))),
                SizedBox(width: 200, child: TextField(controller: prodImageCtrl, decoration: const InputDecoration(labelText: 'Image URL'))),
                SizedBox(width: 260, child: TextField(controller: prodDescCtrl, decoration: const InputDecoration(labelText: 'Description'))),
                ElevatedButton(onPressed: _createMaterial, child: const Text('Create')),
              ],
            ),
            if (prodOut.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(prodOut)),
          ]),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Orders', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            SizedBox(
                width: 220,
                child: TextField(
                    controller: sellerWalletCtrl,
                    decoration: const InputDecoration(labelText: 'Seller wallet (optional)'))),
            SizedBox(
                width: 160,
                child: TextField(
                    controller: orderStatusFilterCtrl,
                    decoration: const InputDecoration(labelText: 'Status filter'),
                    onSubmitted: (_) => _loadOrders())),
            ElevatedButton(onPressed: _loadOrders, child: const Text('Refresh')),
          ],
        ),
        if (ordersLoading) const LinearProgressIndicator(minHeight: 2),
        if (ordersOut.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(ordersOut)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ActionChip(label: const Text('paid_escrow'), onPressed: () { orderStatusFilterCtrl.text = 'paid_escrow'; _loadOrders(); }),
            ActionChip(label: const Text('shipped'), onPressed: () { orderStatusFilterCtrl.text = 'shipped'; _loadOrders(); }),
            ActionChip(label: const Text('delivered'), onPressed: () { orderStatusFilterCtrl.text = 'delivered'; _loadOrders(); }),
            ActionChip(label: const Text('disputed'), onPressed: () { orderStatusFilterCtrl.text = 'disputed'; _loadOrders(); }),
            ActionChip(label: const Text('all'), onPressed: () { orderStatusFilterCtrl.clear(); _loadOrders(); }),
          ],
        ),
        const SizedBox(height: 8),
        ...orders.map((o) {
          final id = o['id'] ?? '';
          final status = (o['status'] ?? '').toString();
          final qty = o['quantity'] ?? '';
          final price = o['price_cents'] ?? '';
          final buyer = (o['buyer_wallet_id'] ?? '').toString();
          final seller = (o['seller_wallet_id'] ?? '').toString();
          final shipmentId = (o['shipment_id'] ?? '').toString();
          Color statusColor;
          switch (status) {
            case 'paid_escrow':
              statusColor = Colors.amber;
              break;
            case 'shipped':
              statusColor = Colors.blue;
              break;
            case 'delivered':
              statusColor = Colors.green;
              break;
            case 'released':
              statusColor = Colors.teal;
              break;
            case 'disputed':
              statusColor = Colors.red;
              break;
            case 'refunded':
              statusColor = Colors.orange;
              break;
            default:
              statusColor = Colors.grey;
          }
          final oid = id is int ? id : int.tryParse(id.toString()) ?? 0;
          final evts = orderEvents[oid] ?? const [];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: GlassPanel(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Order #$id · $qty units · $price SYP'),
                      Chip(label: Text(status), backgroundColor: statusColor.withValues(alpha: .15)),
                    ],
                  ),
                  Text('Buyer: $buyer · Seller: $seller', style: Theme.of(context).textTheme.bodySmall),
                  if (shipmentId.isNotEmpty)
                    Text('Shipment: $shipmentId', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      DropdownButton<String>(
                        value: status,
                        items: const [
                          DropdownMenuItem(value: 'paid_escrow', child: Text('paid_escrow')),
                          DropdownMenuItem(value: 'shipped', child: Text('shipped')),
                          DropdownMenuItem(value: 'delivered', child: Text('delivered')),
                          DropdownMenuItem(value: 'disputed', child: Text('disputed')),
                          DropdownMenuItem(value: 'released', child: Text('released')),
                          DropdownMenuItem(value: 'refunded', child: Text('refunded')),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            _updateOrderStatus(id is int ? id : int.tryParse(id.toString()) ?? 0, v);
                          }
                        },
                      ),
                      SizedBox(
                          width: 200,
                          child: TextField(
                              controller: attachShipmentCtrl,
                              decoration: const InputDecoration(labelText: 'Shipment ID'),
                              onSubmitted: (val) => _attachShipment(id is int ? id : int.tryParse(id.toString()) ?? 0, val))),
                      OutlinedButton(
                          onPressed: () => _attachShipment(id is int ? id : int.tryParse(id.toString()) ?? 0,
                              attachShipmentCtrl.text.trim()),
                          child: const Text('Attach shipment')),
                      TextButton(
                          onPressed: () => _loadOrderEvents(oid),
                          child: Text('Events (${evts.length})')),
                    ],
                  ),
                  if (evts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: evts.map((e) {
                          final st = (e['status'] ?? '').toString();
                          final ts = (e['ts'] ?? '').toString();
                          return Text('$st @ $ts', style: Theme.of(context).textTheme.bodySmall);
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ],
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Building Materials'),
        backgroundColor: Colors.transparent,
        bottom: TabBar(controller: _tab, tabs: [
          Tab(text: l.isArabic ? 'المشتري' : 'Buyer'),
          Tab(text: l.isArabic ? 'المورد/المشغل' : 'Supplier'),
        ]),
      ),
      body: Stack(
        children: [
          const AppBG(),
          Positioned.fill(
            child: SafeArea(
              child: TabBarView(
                controller: _tab,
                children: [buyer, operator],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
