import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'app_shell_widgets.dart' show AppBG;
import 'glass.dart';
import 'superapp_api.dart';

class PosGlassPage extends StatefulWidget {
  final SuperappAPI api;
  const PosGlassPage(this.api, {super.key});
  @override
  State<PosGlassPage> createState() => _PosGlassPageState();
}

class _PosGlassPageState extends State<PosGlassPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 6, vsync: this);
  bool _busy = false;
  String _out = '';
  List<dynamic> _items = [];
  List<dynamic> _tickets = [];
  List<dynamic> _orders = [];
  List<dynamic> _tables = [];
  List<dynamic> _reservations = [];
  List<dynamic> _waitlist = [];
  List<dynamic> _printers = [];
  List<dynamic> _printerJobs = [];
  String _renderPreview = '';
  bool _autoPrint = false;
  final _printerStationFilter = TextEditingController();
  Map<String, dynamic> _reportDaily = {};
  Map<int, Map<String, dynamic>> _cart =
      {}; // itemId -> {qty, mods, course, station, lineDisc, lineSvc, lineTax}
  int _cartTaxPct = 0;
  int _cartServicePct = 0;
  int _cartDiscount = 0;
  int _cartTip = 0;
  final _cartTable = TextEditingController();
  final _shiftOpening = TextEditingController();
  final _shiftClosing = TextEditingController();
  final _shiftCounted = TextEditingController();
  int? _shiftId;
  int? _selectedItem;
  List<dynamic> _modifiers = [];
  List<dynamic> _modifierGroups = [];
  String _categoryFilter = 'All';
  final _lineNote = TextEditingController();
  // guest QR menu
  List<dynamic> _guestItems = [];
  List<dynamic> _guestGroups = [];
  Map<int, Map<String, dynamic>> _guestCart = {};
  final _guestTable = TextEditingController(text: '1');
  final _guestName = TextEditingController();
  final _guestPhone = TextEditingController();
  final _guestDevice = TextEditingController();
  int _guestTip = 0;
  String _guestPayLink = '';
  String _guestOrderId = '';
  String _guestOrderStatus = '';
  String _guestLang = 'en';
  String _dietFilter = '';
  final Set<String> _allergenFilter = {};
  String _ticketFilter = '';
  // rule form
  String _ruleType = 'service';
  final _rulePct = TextEditingController();
  final _ruleTable = TextEditingController();
  final _ruleDevice = TextEditingController();
  final _ruleStart = TextEditingController();
  final _ruleEnd = TextEditingController();
  final _deviceId = TextEditingController(text: 'POS-1');
  final _waitName = TextEditingController();
  final _waitPhone = TextEditingController();
  final _waitParty = TextEditingController(text: '2');
  WebSocket? _ws;
  // printer config
  final _printerName = TextEditingController();
  final _printerStation = TextEditingController();
  final _printerDriver = TextEditingController(text: 'escpos');
  final _printerTarget = TextEditingController();
  final _printerLayout = TextEditingController(
      text: '{"type":"kitchen_ticket","lines":[{"text":"{{order_id}}"}]}');
  int? _selectedPrinterId;
  final _printerWidth = TextEditingController(text: '32');

  final _itemName = TextEditingController();
  final _itemPrice = TextEditingController();
  final _itemModifier = TextEditingController();
  final _comboIds = TextEditingController();
  final _comboPrice = TextEditingController();
  final _qrTable = TextEditingController(text: '1');
  final _qrItem = TextEditingController();
  final _qrQty = TextEditingController(text: '1');
  String _qrPayLink = '';

  @override
  void initState() {
    super.initState();
    _refreshAll();
    _connectWs();
    _loadPrinters();
  }

  @override
  void dispose() {
    _tab.dispose();
    _itemName.dispose();
    _itemPrice.dispose();
    _itemModifier.dispose();
    _comboIds.dispose();
    _comboPrice.dispose();
    _cartTable.dispose();
    _shiftOpening.dispose();
    _shiftClosing.dispose();
    _shiftCounted.dispose();
    _deviceId.dispose();
    _waitName.dispose();
    _waitPhone.dispose();
    _waitParty.dispose();
    _printerName.dispose();
    _printerStation.dispose();
    _printerDriver.dispose();
    _printerTarget.dispose();
    _printerLayout.dispose();
    _printerWidth.dispose();
    _printerStationFilter.dispose();
    _lineNote.dispose();
    _guestTable.dispose();
    _guestName.dispose();
    _guestPhone.dispose();
    _guestDevice.dispose();
    _qrTable.dispose();
    _qrItem.dispose();
    _qrQty.dispose();
    _ws?.close();
    super.dispose();
  }

  Future<Map<String, String>> _hdr({bool json = false}) {
    return widget.api.sessionHeaders(json: json);
  }

  Future<void> _connectWs() async {
    try {
      final httpUri = widget.api.uri('pos/ws');
      final wsUri = httpUri.replace(
        scheme: httpUri.scheme == 'https' ? 'wss' : 'ws',
      );
      final sock = await WebSocket.connect(wsUri.toString());
      _ws = sock;
      sock.listen((data) {
        _handleWsMessage(data);
      }, onDone: () {
        _ws = null;
        _connectWs();
      }, onError: (_) {
        _ws = null;
        _connectWs();
      });
      if (_autoPrint) {
        _startAutoPrintLoop();
      }
    } catch (_) {
      // ignore
    }
  }

  void _handleWsMessage(dynamic data) {
    try {
      final msg = jsonDecode(data);
      if (msg is! Map) return;
      final type = msg['type'];
      if (type == 'snapshot') {
        setState(() {
          _orders = (msg['orders'] as List?) ?? [];
          _tickets = (msg['tickets'] as List?) ?? [];
        });
      } else if (type == 'orders_changed') {
        _loadOrders();
      } else if (type == 'tickets_changed') {
        _loadTickets();
      } else if (type == 'printer_jobs') {
        // future: refresh printer queue
        if (_autoPrint) _autoPrintTick();
      }
    } catch (_) {}
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _loadItems(),
      _loadTickets(),
      _loadOrders(),
      _loadTables(),
      _loadReservations(),
      _loadReportDaily(),
      _loadModifierGroups(),
      _loadQrMenu(),
      _loadWaitlist(),
      _loadPrinters(),
      _loadPrinterJobs(),
    ]);
  }

  Future<void> _updateTicket(int id, String status) async {
    try {
      final r = await http.post(
        widget.api.uri('pos/kitchen/tickets/$id'),
        headers: await _hdr(json: true),
        body: jsonEncode({"status": status}),
      );
      _out = '${r.statusCode}: ${r.body}';
      await _loadTickets();
    } catch (e) {
      _out = 'error: $e';
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _callReceipt(dynamic orderId) async {
    final url = widget.api.uri('pos/orders/$orderId/receipt.pdf');
    if (!await canLaunchUrl(url)) {
      setState(() => _out = 'cannot open receipt');
      return;
    }
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _callPrint(dynamic orderId) async {
    try {
      final r =
          await http.get(widget.api.uri('pos/orders/$orderId/print/escpos'));
      _out = '${r.statusCode}: ESC/POS stub';
    } catch (e) {
      _out = 'error: $e';
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _createQrOrder() async {
    final tid = int.tryParse(_qrTable.text.trim());
    final iid = int.tryParse(_qrItem.text.trim());
    final qty = int.tryParse(_qrQty.text.trim());
    if (tid == null || iid == null || qty == null || qty <= 0) {
      setState(() => _out = 'invalid QR order input');
      return;
    }
    setState(() {
      _busy = true;
      _qrPayLink = '';
    });
    try {
      final body = jsonEncode({
        "table_id": tid,
        "currency": "SYP",
        "lines": [
          {"item_id": iid, "qty": qty, "modifiers": []}
        ]
      });
      final r = await http.post(
        widget.api.uri('pos/qr/orders'),
        headers: await _hdr(json: true),
        body: body,
      );
      _out = '${r.statusCode}: ${r.body}';
      if (r.statusCode == 200) {
        final order = jsonDecode(r.body) as Map<String, dynamic>;
        final pay =
            await http.post(widget.api.uri('pos/orders/${order['id']}/pay'));
        if (pay.statusCode == 200) {
          final data = jsonDecode(pay.body) as Map<String, dynamic>;
          _qrPayLink = data['payment_link']?.toString() ?? '';
        }
        await _loadOrders();
        await _loadTickets();
      }
    } catch (e) {
      _out = 'error: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitGuestOrder() async {
    final tid = int.tryParse(_guestTable.text.trim());
    if (tid == null) {
      setState(() => _out = 'Table required');
      return;
    }
    if (_guestCart.isEmpty) return;
    setState(() {
      _busy = true;
      _guestPayLink = '';
    });
    try {
      final lines = _guestCart.entries
          .map((e) => {
                "item_id": e.key,
                "qty": e.value['qty'],
                "modifiers": (e.value['mods'] as List<int>? ?? []),
              })
          .toList();
      final body = jsonEncode({
        "table_id": tid,
        "currency": "SYP",
        "tip_cents": _guestTip,
        "customer_name": _guestName.text.trim(),
        "customer_phone": _guestPhone.text.trim(),
        "device_code": _guestDevice.text.trim(),
        "lines": lines
      });
      final r = await http.post(
        widget.api.uri('pos/qr/orders'),
        headers: await _hdr(json: true),
        body: body,
      );
      _out = '${r.statusCode}: ${r.body}';
      if (r.statusCode == 200) {
        final order = jsonDecode(r.body) as Map<String, dynamic>;
        _guestOrderId = order['id']?.toString() ?? '';
        final pay =
            await http.post(widget.api.uri('pos/orders/${order['id']}/pay'));
        if (pay.statusCode == 200) {
          final data = jsonDecode(pay.body) as Map<String, dynamic>;
          _guestPayLink = data['payment_link']?.toString() ?? '';
        }
        _guestCart.clear();
        await _loadOrders();
      }
    } catch (e) {
      _out = 'error: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadItems() async {
    try {
      final r = await http.get(widget.api.uri('pos/items'));
      if (r.statusCode == 200) {
        setState(() => _items = jsonDecode(r.body) as List);
      }
    } catch (_) {}
  }

  Future<void> _loadTickets() async {
    try {
      final r = await http.get(
        widget.api.uri(
          'pos/kitchen/tickets',
          query: _ticketFilter.isEmpty ? null : {'status': _ticketFilter},
        ),
      );
      if (r.statusCode == 200)
        setState(() => _tickets = jsonDecode(r.body) as List);
    } catch (_) {}
  }

  Future<void> _loadOrders() async {
    try {
      final r = await http.get(widget.api.uri('pos/orders'));
      if (r.statusCode == 200)
        setState(() => _orders = jsonDecode(r.body) as List);
    } catch (_) {}
  }

  Future<void> _loadTables() async {
    try {
      final r = await http.get(widget.api.uri('pos/tables'));
      if (r.statusCode == 200)
        setState(() => _tables = jsonDecode(r.body) as List);
    } catch (_) {}
  }

  Future<void> _loadReservations() async {
    try {
      final r = await http.get(widget.api.uri('pos/reservations'));
      if (r.statusCode == 200)
        setState(() => _reservations = jsonDecode(r.body) as List);
    } catch (_) {}
  }

  Future<void> _loadReportDaily() async {
    try {
      final r = await http.get(widget.api.uri('pos/reports/daily'));
      if (r.statusCode == 200)
        setState(
            () => _reportDaily = jsonDecode(r.body) as Map<String, dynamic>);
    } catch (_) {}
  }

  Future<void> _loadModifierGroups() async {
    try {
      final r = await http.get(widget.api.uri('pos/modifier-groups'));
      if (r.statusCode == 200)
        setState(() => _modifierGroups = jsonDecode(r.body) as List);
    } catch (_) {}
  }

  Future<void> _loadQrMenu() async {
    try {
      final r = await http.get(widget.api.uri('pos/qr/menu'));
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        setState(() {
          _guestItems = (body['items'] as List?) ?? const [];
          _guestGroups = (body['modifier_groups'] as List?) ?? const [];
        });
      }
    } catch (_) {}
  }

  Future<void> _loadWaitlist() async {
    try {
      final r = await http.get(widget.api.uri('pos/waitlist'));
      if (r.statusCode == 200)
        setState(() => _waitlist = jsonDecode(r.body) as List);
    } catch (_) {}
  }

  Future<void> _loadPrinters() async {
    try {
      final r = await http.get(widget.api.uri('pos/printers'));
      if (r.statusCode == 200)
        setState(() => _printers = jsonDecode(r.body) as List);
    } catch (_) {}
  }

  Future<void> _createPrinter() async {
    final name = _printerName.text.trim();
    final target = _printerTarget.text.trim();
    if (name.isEmpty || target.isEmpty) return;
    setState(() => _busy = true);
    try {
      final body = jsonEncode({
        "name": name,
        "station": _printerStation.text.trim().isEmpty
            ? null
            : _printerStation.text.trim(),
        "driver": _printerDriver.text.trim().isEmpty
            ? "escpos"
            : _printerDriver.text.trim(),
        "target": target,
        "layout_json": _printerLayout.text.trim().isEmpty
            ? null
            : _printerLayout.text.trim(),
        "char_width": int.tryParse(_printerWidth.text.trim()) ?? 32,
      });
      final r = await http.post(
        widget.api.uri('pos/printers'),
        headers: await _hdr(json: true),
        body: body,
      );
      _out = '${r.statusCode}: ${r.body}';
      await _loadPrinters();
    } catch (e) {
      _out = 'error: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadPrinterJobs() async {
    try {
      final r = await http.get(
        widget.api.uri('pos/printer-jobs', query: const {'status': 'queued'}),
      );
      if (r.statusCode == 200)
        setState(() => _printerJobs = jsonDecode(r.body) as List);
    } catch (_) {}
  }

  Future<void> _claimJob() async {
    if (_selectedPrinterId == null) return;
    setState(() => _busy = true);
    try {
      final body = jsonEncode({
        "printer_id": _selectedPrinterId,
        "station": _printerStationFilter.text.trim().isEmpty
            ? null
            : _printerStationFilter.text.trim(),
      });
      final r = await http.post(
        widget.api.uri('pos/printer-jobs/claim'),
        headers: await _hdr(json: true),
        body: body,
      );
      _out = '${r.statusCode}: ${r.body}';
      await _loadPrinterJobs();
    } catch (e) {
      _out = 'error: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _renderJob(int jobId) async {
    setState(() => _busy = true);
    try {
      final r =
          await http.get(widget.api.uri('pos/printer-jobs/$jobId/render'));
      _out = '${r.statusCode}: ${r.body}';
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        _renderPreview = const JsonEncoder.withIndent('  ').convert(body);
        final driver = body['driver']?.toString() ?? '';
        final raw = body['raw_output']?.toString() ?? '';
        final rawB64 = body['raw_base64']?.toString();
        final pr = _printers.firstWhere((p) => p['id'] == _selectedPrinterId,
            orElse: () => {});
        final target = pr['target']?.toString() ?? '';
        if (driver == 'http' && target.isNotEmpty) {
          try {
            await http.post(Uri.parse(target),
                headers: {'Content-Type': 'text/plain'}, body: raw);
          } catch (_) {}
        } else if (driver == 'escpos' && target.isNotEmpty && rawB64 != null) {
          try {
            final bytes = base64Decode(rawB64);
            await http.post(Uri.parse(target),
                headers: {'Content-Type': 'application/octet-stream'},
                body: bytes);
          } catch (_) {}
        }
        if (!mounted) return;
        showModalBottomSheet(
          context: context,
          builder: (_) => Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Text(_renderPreview),
            ),
          ),
        );
      }
    } catch (e) {
      _out = 'error: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _completeJob(int jobId) async {
    setState(() => _busy = true);
    try {
      final r = await http.post(
        widget.api.uri('pos/printer-jobs/$jobId'),
        headers: await _hdr(json: true),
        body: jsonEncode({"status": "done"}),
      );
      _out = '${r.statusCode}: ${r.body}';
      await _loadPrinterJobs();
    } catch (e) {
      _out = 'error: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _autoPrintTick() async {
    if (_selectedPrinterId == null) return;
    try {
      // claim
      final body = jsonEncode({
        "printer_id": _selectedPrinterId,
        "station": _printerStationFilter.text.trim().isEmpty
            ? null
            : _printerStationFilter.text.trim(),
      });
      final claim = await http.post(
        widget.api.uri('pos/printer-jobs/claim'),
        headers: await _hdr(json: true),
        body: body,
      );
      if (claim.statusCode != 200) return;
      final job = jsonDecode(claim.body);
      final jid = job['id'];
      final render =
          await http.get(widget.api.uri('pos/printer-jobs/$jid/render'));
      if (render.statusCode == 200) {
        final rbody = jsonDecode(render.body);
        final driver = rbody['driver']?.toString() ?? '';
        final raw = rbody['raw_output']?.toString() ?? '';
        final rawB64 = rbody['raw_base64']?.toString();
        final pr = _printers.firstWhere((p) => p['id'] == _selectedPrinterId,
            orElse: () => {});
        final target = pr['target']?.toString() ?? '';
        var sentOk = true;
        if (driver == 'http' && target.isNotEmpty) {
          try {
            final sendResp = await http.post(Uri.parse(target),
                headers: {'Content-Type': 'text/plain'}, body: raw);
            sentOk = sendResp.statusCode >= 200 && sendResp.statusCode < 300;
          } catch (_) {
            sentOk = false;
          }
        } else if (driver == 'escpos' && target.isNotEmpty && rawB64 != null) {
          try {
            final bytes = base64Decode(rawB64);
            final sendResp = await http.post(Uri.parse(target),
                headers: {'Content-Type': 'application/octet-stream'},
                body: bytes);
            sentOk = sendResp.statusCode >= 200 && sendResp.statusCode < 300;
          } catch (_) {
            sentOk = false;
          }
        }
        if (sentOk) {
          await http.post(
            widget.api.uri('pos/printer-jobs/$jid'),
            headers: await _hdr(json: true),
            body: jsonEncode({"status": "done"}),
          );
        }
      }
      await _loadPrinterJobs();
    } catch (_) {}
  }

  void _startAutoPrintLoop() async {
    while (_autoPrint && mounted) {
      await _autoPrintTick();
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  Future<void> _updateTableStatus(int tid, String status) async {
    try {
      final r = await http.post(
        widget.api.uri('pos/tables/$tid'),
        headers: await _hdr(json: true),
        body: jsonEncode({"status": status}),
      );
      _out = '${r.statusCode}: ${r.body}';
      await _loadTables();
    } catch (e) {
      _out = 'error: $e';
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _createWait() async {
    final name = _waitName.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      final body = jsonEncode({
        "guest_name": name,
        "phone": _waitPhone.text.trim(),
        "party_size": int.tryParse(_waitParty.text.trim()) ?? 2,
      });
      final r = await http.post(
        widget.api.uri('pos/waitlist'),
        headers: await _hdr(json: true),
        body: body,
      );
      _out = '${r.statusCode}: ${r.body}';
      await _loadWaitlist();
    } catch (e) {
      _out = 'error: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateWait(int id, String status) async {
    try {
      final r = await http.post(
        widget.api.uri('pos/waitlist/$id'),
        headers: await _hdr(json: true),
        body: jsonEncode({"status": status}),
      );
      _out = '${r.statusCode}: ${r.body}';
      await _loadWaitlist();
    } catch (e) {
      _out = 'error: $e';
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _createItem() async {
    final name = _itemName.text.trim();
    final price = int.tryParse(_itemPrice.text.trim()) ?? 0;
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      final mods = _itemModifier.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final comboList = _comboIds.text
          .split(',')
          .map((e) => int.tryParse(e.trim()))
          .whereType<int>()
          .toList();
      final comboPrice = int.tryParse(_comboPrice.text.trim());
      final body = jsonEncode({
        "name": name,
        "price_cents": price,
        "currency": "SYP",
        "modifiers": mods,
        "combo_item_ids": comboList,
        "combo_price_cents": comboPrice
      });
      final r = await http.post(
        widget.api.uri('pos/items'),
        headers: await _hdr(json: true),
        body: body,
      );
      _out = '${r.statusCode}: ${r.body}';
      await _loadItems();
    } catch (e) {
      _out = 'error: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _addToCart(int itemId) {
    setState(() {
      _cart.update(itemId, (v) {
        final qty = (v['qty'] as int? ?? 0) + 1;
        return {...v, "qty": qty};
      },
          ifAbsent: () => {
                "qty": 1,
                "mods": <int>[],
                "discount_cents": 0,
                "service_pct": 0.0,
                "tax_pct": 0.0,
                "course": "",
                "station": "",
                "note": ""
              });
    });
  }

  void _setSelectedItem(int itemId) {
    setState(() {
      _selectedItem = itemId;
      final item =
          _items.firstWhere((it) => it['id'] == itemId, orElse: () => {});
      _modifiers = (item['modifiers'] as List?) ?? const [];
    });
  }

  List<int> _itemGroupIds(Map item) {
    final raw = item['modifier_groups_json'];
    if (raw == null) return [];
    if (raw is List) {
      return raw
          .map((e) => int.tryParse(e.toString()) ?? 0)
          .where((e) => e > 0)
          .toList();
    }
    if (raw is String) {
      try {
        final parsed = jsonDecode(raw);
        if (parsed is List) {
          return parsed
              .map((e) => int.tryParse(e.toString()) ?? 0)
              .where((e) => e > 0)
              .toList();
        }
      } catch (_) {}
    }
    return [];
  }

  void _toggleMod(int modId) {
    if (_selectedItem == null) return;
    setState(() {
      final entry = _cart[_selectedItem!] ??
          {
            "qty": 1,
            "mods": <int>[],
            "discount_cents": 0,
            "service_pct": 0.0,
            "tax_pct": 0.0,
            "course": "",
            "station": "",
            "note": ""
          };
      final mods = (entry["mods"] as List<int>? ?? []);
      if (mods.contains(modId)) {
        mods.remove(modId);
      } else {
        mods.add(modId);
      }
      _cart[_selectedItem!] = {...entry, "mods": mods};
    });
  }

  void _toggleGroupOption(int groupId, int optionId, int maxChoices) {
    if (_selectedItem == null) return;
    setState(() {
      final entry = _cart[_selectedItem!] ??
          {
            "qty": 1,
            "mods": <int>[],
            "discount_cents": 0,
            "service_pct": 0.0,
            "tax_pct": 0.0,
            "course": "",
            "station": "",
            "note": ""
          };
      final mods = List<int>.from(entry["mods"] as List<int>? ?? []);
      final selectedInGroup = mods.where((m) {
        final group = _modifierGroups.firstWhere((g) => g['id'] == groupId,
            orElse: () => {});
        final opts = (group['options'] as List?) ?? const [];
        return opts.any((o) => o['id'] == m);
      }).toList();
      if (mods.contains(optionId)) {
        mods.remove(optionId);
      } else {
        if (maxChoices > 0 && selectedInGroup.length >= maxChoices) {
          // drop oldest in group to respect max
          mods.remove(selectedInGroup.first);
        }
        mods.add(optionId);
      }
      _cart[_selectedItem!] = {...entry, "mods": mods};
    });
  }

  void _guestAddItem(Map item) {
    final id = item['id'] as int;
    setState(() {
      _guestCart.update(id, (v) {
        final qty = (v['qty'] as int? ?? 0) + 1;
        return {...v, "qty": qty};
      }, ifAbsent: () => {"qty": 1, "mods": <int>[]});
    });
  }

  void _guestToggleMod(int itemId, int optionId) {
    setState(() {
      final entry = _guestCart[itemId] ?? {"qty": 1, "mods": <int>[]};
      final mods = List<int>.from(entry['mods'] as List<int>? ?? []);
      if (mods.contains(optionId)) {
        mods.remove(optionId);
      } else {
        mods.add(optionId);
      }
      _guestCart[itemId] = {...entry, "mods": mods};
    });
  }

  Future<void> _checkoutCart() async {
    if (_cart.isEmpty) return;
    setState(() => _busy = true);
    try {
      final tableId = int.tryParse(_cartTable.text.trim());
      // validate required groups
      for (final e in _cart.entries) {
        final item =
            _items.firstWhere((it) => it['id'] == e.key, orElse: () => {});
        final gIds = _itemGroupIds(item);
        final selectedMods = (e.value['mods'] as List<int>? ?? []);
        for (final gid in gIds) {
          final g = _modifierGroups.firstWhere((gr) => gr['id'] == gid,
              orElse: () => {});
          if (g.isEmpty) continue;
          final opts = (g['options'] as List?) ?? const [];
          final required = g['required'] == true;
          final minChoices = (g['min_choices'] as int? ?? (required ? 1 : 0));
          final count =
              selectedMods.where((m) => opts.any((o) => o['id'] == m)).length;
          if (required && count < minChoices) {
            setState(() => _out =
                'Select at least $minChoices options for ${g['name']} on item ${item['name']}');
            setState(() => _busy = false);
            return;
          }
        }
      }
      final lines = _cart.entries
          .map((e) => {
                "item_id": e.key,
                "qty": e.value['qty'] as int,
                "modifiers": (e.value['mods'] as List<int>? ?? []),
                "discount_cents": e.value['discount_cents'] ?? 0,
                "service_pct":
                    (e.value['service_pct'] as num?)?.toDouble() ?? 0.0,
                "tax_pct": (e.value['tax_pct'] as num?)?.toDouble() ?? 0.0,
                "course": e.value['course'] ?? "",
                "station": e.value['station'] ?? "",
                "note": e.value['note'] ?? "",
              })
          .toList();
      final body = jsonEncode({
        "lines": lines,
        "currency": "SYP",
        "tax_pct": _cartTaxPct,
        "service_pct": _cartServicePct,
        "discount_cents": _cartDiscount,
        "table_id": tableId,
        "device_id":
            _deviceId.text.trim().isEmpty ? null : _deviceId.text.trim(),
      });
      final r = await http.post(
        widget.api.uri('pos/orders'),
        headers: await _hdr(json: true),
        body: body,
      );
      _out = '${r.statusCode}: ${r.body}';
      _cart.clear();
      await _loadTickets();
      await _loadOrders();
    } catch (e) {
      _out = 'error: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _tileGrid() {
    final categories = <String>{'All'};
    for (final it in _items) {
      final c = (it['category'] ?? '') as String;
      if (c.isNotEmpty) categories.add(c);
    }
    final list = _items
        .where((it) =>
            _categoryFilter == 'All' ||
            (it['category'] ?? '') == _categoryFilter)
        .toList();
    return GridView.count(
      crossAxisCount: 3,
      childAspectRatio: 1.1,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: list
          .map((it) => Padding(
                padding: const EdgeInsets.all(6),
                child: InkWell(
                  onTap: () {
                    _setSelectedItem(it['id'] as int);
                    _addToCart(it['id'] as int);
                  },
                  child: GlassPanel(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(it['name'] ?? 'Item',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text(
                            '${it['price_cents'] ?? 0} ${it['currency'] ?? ''}'),
                        if ((it['is_combo'] ?? 0) == 1)
                          Text('Combo',
                              style: Theme.of(context).textTheme.bodySmall),
                        if ((it['modifiers'] is List) &&
                            (it['modifiers'] as List).isNotEmpty)
                          Text('Mods: ${(it['modifiers'] as List).length}',
                              style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 6),
                        ElevatedButton(
                            onPressed: _busy
                                ? null
                                : () => _addToCart(it['id'] as int),
                            child: const Text('Add')),
                      ],
                    ),
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _modSelector() {
    if (_selectedItem == null) return const SizedBox();
    final item =
        _items.firstWhere((it) => it['id'] == _selectedItem, orElse: () => {});
    final groupIds = _itemGroupIds(item);
    if (_modifiers.isEmpty && groupIds.isEmpty) return const SizedBox();
    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Modifiers for item $_selectedItem',
              style: Theme.of(context).textTheme.titleSmall),
          Wrap(
            spacing: 8,
            children: _modifiers
                .map((m) => ChoiceChip(
                      label: Text(m.toString()),
                      selected:
                          ((_cart[_selectedItem!]?['mods'] as List<int>? ?? [])
                              .contains(m)),
                      onSelected: (_) => _toggleMod(m as int),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          ...groupIds.map((gid) {
            final g = _modifierGroups.firstWhere((gr) => gr['id'] == gid,
                orElse: () => {});
            final options = (g['options'] as List?) ?? const [];
            if (g.isEmpty || options.isEmpty) return const SizedBox();
            final maxChoices = (g['max_choices'] as int? ?? 0);
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${g['name'] ?? 'Group'} ${g['required'] == true ? "(required)" : ""}'),
                  Wrap(
                    spacing: 8,
                    children: options
                        .map((o) => ChoiceChip(
                              label:
                                  Text('${o['name']} (+${o['price_cents']})'),
                              selected: ((_cart[_selectedItem!]?['mods']
                                          as List<int>? ??
                                      [])
                                  .contains(o['id'])),
                              onSelected: (_) => _toggleGroupOption(
                                  gid, o['id'] as int, maxChoices),
                            ))
                        .toList(),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Course'),
                  onChanged: (v) {
                    if (_selectedItem == null) return;
                    final entry = _cart[_selectedItem!] ??
                        {
                          "qty": 1,
                          "mods": <int>[],
                          "discount_cents": 0,
                          "service_pct": 0.0,
                          "tax_pct": 0.0,
                          "course": "",
                          "station": "",
                          "note": ""
                        };
                    _cart[_selectedItem!] = {...entry, "course": v};
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Station'),
                  onChanged: (v) {
                    if (_selectedItem == null) return;
                    final entry = _cart[_selectedItem!] ??
                        {
                          "qty": 1,
                          "mods": <int>[],
                          "discount_cents": 0,
                          "service_pct": 0.0,
                          "tax_pct": 0.0,
                          "course": "",
                          "station": "",
                          "note": ""
                        };
                    _cart[_selectedItem!] = {...entry, "station": v};
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 120,
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Line discount'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    if (_selectedItem == null) return;
                    final entry = _cart[_selectedItem!] ??
                        {
                          "qty": 1,
                          "mods": <int>[],
                          "discount_cents": 0,
                          "service_pct": 0.0,
                          "tax_pct": 0.0,
                          "course": "",
                          "station": "",
                          "note": ""
                        };
                    _cart[_selectedItem!] = {
                      ...entry,
                      "discount_cents": int.tryParse(v.trim()) ?? 0
                    };
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: TextField(
                  decoration:
                      const InputDecoration(labelText: 'Line service %'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    if (_selectedItem == null) return;
                    final entry = _cart[_selectedItem!] ??
                        {
                          "qty": 1,
                          "mods": <int>[],
                          "discount_cents": 0,
                          "service_pct": 0.0,
                          "tax_pct": 0.0,
                          "course": "",
                          "station": "",
                          "note": ""
                        };
                    _cart[_selectedItem!] = {
                      ...entry,
                      "service_pct": double.tryParse(v.trim()) ?? 0.0
                    };
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Line tax %'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    if (_selectedItem == null) return;
                    final entry = _cart[_selectedItem!] ??
                        {
                          "qty": 1,
                          "mods": <int>[],
                          "discount_cents": 0,
                          "service_pct": 0.0,
                          "tax_pct": 0.0,
                          "course": "",
                          "station": "",
                          "note": ""
                        };
                    _cart[_selectedItem!] = {
                      ...entry,
                      "tax_pct": double.tryParse(v.trim()) ?? 0.0
                    };
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _lineNote,
            decoration: const InputDecoration(labelText: 'Line note'),
            onChanged: (v) {
              if (_selectedItem == null) return;
              final entry = _cart[_selectedItem!] ??
                  {
                    "qty": 1,
                    "mods": <int>[],
                    "discount_cents": 0,
                    "service_pct": 0.0,
                    "tax_pct": 0.0,
                    "course": "",
                    "station": "",
                    "note": ""
                  };
              _cart[_selectedItem!] = {...entry, "note": v};
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _categoriesBar() {
    final categories = <String>{'All'};
    for (final it in _items) {
      final c = (it['category'] ?? '') as String;
      if (c.isNotEmpty) categories.add(c);
    }
    final chips = categories.toList()..sort();
    return Wrap(
      spacing: 8,
      children: chips
          .map((c) => ChoiceChip(
                label: Text(c),
                selected: _categoryFilter == c,
                onSelected: (_) => setState(() => _categoryFilter = c),
              ))
          .toList(),
    );
  }

  Widget _cartPanel() {
    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Cart', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _cart.entries.map((e) {
              final item = _items.firstWhere((it) => it['id'] == e.key,
                  orElse: () => {});
              final mods = (e.value['mods'] as List<int>? ?? []);
              final note = (e.value['note'] as String? ?? '').trim();
              return Chip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                        '${item['name'] ?? 'Item'} ${mods.isNotEmpty ? '• mods: ${mods.length}' : ''}'),
                    const SizedBox(width: 8),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.remove),
                      onPressed: () {
                        final qty = (e.value['qty'] as int? ?? 1) - 1;
                        if (qty <= 0) {
                          setState(() => _cart.remove(e.key));
                        } else {
                          setState(
                              () => _cart[e.key] = {...e.value, "qty": qty});
                        }
                      },
                    ),
                    Text('x${e.value['qty']}'),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.add),
                      onPressed: () => setState(() => _cart[e.key] = {
                            ...e.value,
                            "qty": (e.value['qty'] as int? ?? 1) + 1
                          }),
                    ),
                    if (note.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Icon(Icons.note, size: 16)),
                  ],
                ),
                onDeleted: () => setState(() => _cart.remove(e.key)),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          _cartTotals(),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _cartTable,
                  decoration:
                      const InputDecoration(labelText: 'Table (optional)'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _deviceId,
                  decoration: const InputDecoration(labelText: 'Device id'),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _busy
                    ? null
                    : () {
                        setState(() => _cart.clear());
                      },
                child: const Text('Clear'),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 100,
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Tax %'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => _cartTaxPct = int.tryParse(v.trim()) ?? 0,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Service %'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) =>
                      _cartServicePct = int.tryParse(v.trim()) ?? 0,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 140,
                child: TextField(
                  decoration:
                      const InputDecoration(labelText: 'Discount (cents)'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => _cartDiscount = int.tryParse(v.trim()) ?? 0,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Tip (cents)'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => _cartTip = int.tryParse(v.trim()) ?? 0,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                  onPressed: _busy ? null : _checkoutCart,
                  child: const Text('Checkout')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cartTotals() {
    double subtotal = 0;
    for (final e in _cart.entries) {
      final item =
          _items.firstWhere((it) => it['id'] == e.key, orElse: () => {});
      final price = (item['price_cents'] as num?)?.toDouble() ?? 0;
      final qty = (e.value['qty'] as num?)?.toDouble() ?? 1;
      final disc = (e.value['discount_cents'] as num?)?.toDouble() ?? 0;
      subtotal += (price * qty) - disc;
    }
    final service = subtotal * (_cartServicePct / 100);
    final afterService = subtotal + service;
    final tax = afterService * (_cartTaxPct / 100);
    final total = afterService + tax - _cartDiscount + _cartTip;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Subtotal: ${subtotal.toStringAsFixed(2)}'),
        Text('Service: ${service.toStringAsFixed(2)}'),
        Text('Tax: ${tax.toStringAsFixed(2)}'),
        Text('Tip: ${_cartTip.toStringAsFixed(2)}'),
        Text('Total: ${total.toStringAsFixed(2)}'),
      ],
    );
  }

  Widget _posTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _section('Add item', [
          Row(
            children: [
              Expanded(
                  child: TextField(
                      controller: _itemName,
                      decoration: const InputDecoration(labelText: 'Name'))),
              const SizedBox(width: 8),
              SizedBox(
                  width: 140,
                  child: TextField(
                      controller: _itemPrice,
                      decoration:
                          const InputDecoration(labelText: 'Price cents'),
                      keyboardType: TextInputType.number)),
              const SizedBox(width: 8),
              SizedBox(
                  width: 180,
                  child: TextField(
                      controller: _itemModifier,
                      decoration: const InputDecoration(
                          labelText: 'Modifiers (comma separated)'))),
              const SizedBox(width: 8),
              SizedBox(
                  width: 140,
                  child: TextField(
                      controller: _comboIds,
                      decoration: const InputDecoration(
                          labelText: 'Combo item ids (comma)'))),
              const SizedBox(width: 8),
              SizedBox(
                  width: 140,
                  child: TextField(
                      controller: _comboPrice,
                      decoration: const InputDecoration(
                          labelText: 'Combo price (cents)'),
                      keyboardType: TextInputType.number)),
              const SizedBox(width: 8),
              ElevatedButton(
                  onPressed: _busy ? null : _createItem,
                  child: const Text('Save')),
            ],
          ),
        ]),
        const SizedBox(height: 12),
        _cartPanel(),
        const SizedBox(height: 12),
        _modSelector(),
        const SizedBox(height: 12),
        _categoriesBar(),
        const SizedBox(height: 8),
        _tileGrid(),
        const SizedBox(height: 12),
        _section('Rules (service/discount)', [
          Row(
            children: [
              DropdownButton<String>(
                value: _ruleType,
                items: const [
                  DropdownMenuItem(value: 'service', child: Text('Service')),
                  DropdownMenuItem(value: 'discount', child: Text('Discount')),
                ],
                onChanged: (v) => setState(() => _ruleType = v ?? 'service'),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _rulePct,
                  decoration: const InputDecoration(labelText: 'Pct'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _ruleTable,
                  decoration: const InputDecoration(labelText: 'Table id'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _ruleDevice,
                  decoration: const InputDecoration(labelText: 'Device id'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _ruleStart,
                  decoration: const InputDecoration(labelText: 'Start min'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _ruleEnd,
                  decoration: const InputDecoration(labelText: 'End min'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _busy
                    ? null
                    : () async {
                        try {
                          final body = jsonEncode({
                            "rule_type": _ruleType,
                            "pct": double.tryParse(_rulePct.text.trim()) ?? 0.0,
                            "table_id": int.tryParse(_ruleTable.text.trim()),
                            "device_id": _ruleDevice.text.trim().isEmpty
                                ? null
                                : _ruleDevice.text.trim(),
                            "start_minute":
                                int.tryParse(_ruleStart.text.trim()),
                            "end_minute": int.tryParse(_ruleEnd.text.trim()),
                          });
                          final r = await http.post(
                            widget.api.uri('pos/rules'),
                            headers: await _hdr(json: true),
                            body: body,
                          );
                          _out = '${r.statusCode}: ${r.body}';
                        } catch (e) {
                          _out = 'error: $e';
                        } finally {
                          if (mounted) setState(() {});
                        }
                      },
                child: const Text('Save rule'),
              ),
            ],
          ),
        ]),
        const SizedBox(height: 12),
        _section('Shift / Cashbox', [
          Row(
            children: [
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _shiftOpening,
                  decoration:
                      const InputDecoration(labelText: 'Opening cash (cents)'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _busy
                    ? null
                    : () async {
                        try {
                          final body = jsonEncode({
                            "device_id": "POS-1",
                            "opening_cash_cents":
                                int.tryParse(_shiftOpening.text.trim()) ?? 0
                          });
                          final r = await http.post(
                            widget.api.uri('pos/shifts'),
                            headers: await _hdr(json: true),
                            body: body,
                          );
                          _out = '${r.statusCode}: ${r.body}';
                          if (r.statusCode == 200) {
                            final data =
                                jsonDecode(r.body) as Map<String, dynamic>;
                            _shiftId = data['id'] as int?;
                          }
                        } catch (e) {
                          _out = 'error: $e';
                        } finally {
                          if (mounted) setState(() {});
                        }
                      },
                child: const Text('Open shift'),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _shiftClosing,
                  decoration:
                      const InputDecoration(labelText: 'Closing cash (cents)'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _shiftCounted,
                  decoration:
                      const InputDecoration(labelText: 'Counted cash (cents)'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: (_shiftId ?? 0) == 0
                    ? null
                    : () async {
                        try {
                          final body = jsonEncode({
                            "closing_cash_cents":
                                int.tryParse(_shiftClosing.text.trim()) ?? 0,
                            "counted_cash_cents":
                                int.tryParse(_shiftCounted.text.trim()) ?? 0,
                          });
                          final r = await http.post(
                            widget.api.uri('pos/shifts/${_shiftId}/close'),
                            headers: await _hdr(json: true),
                            body: body,
                          );
                          _out = '${r.statusCode}: ${r.body}';
                        } catch (e) {
                          _out = 'error: $e';
                        } finally {
                          if (mounted) setState(() {});
                        }
                      },
                child: const Text('Close shift'),
              ),
            ],
          ),
          if (_shiftId != null) Text('Current shift: #$_shiftId'),
        ]),
        const SizedBox(height: 12),
        _section('Printers (station routing stub)', [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _printers
                .map((p) => ChoiceChip(
                      label: Text(
                          '${p['name']} • ${p['driver']} • ${p['station'] ?? '-'}'),
                      selected: _selectedPrinterId == p['id'],
                      onSelected: (_) =>
                          setState(() => _selectedPrinterId = p['id'] as int),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          TextField(
              controller: _printerName,
              decoration: const InputDecoration(labelText: 'Name')),
          TextField(
              controller: _printerStation,
              decoration:
                  const InputDecoration(labelText: 'Station (optional)')),
          TextField(
              controller: _printerDriver,
              decoration:
                  const InputDecoration(labelText: 'Driver escpos/pdf/http')),
          TextField(
              controller: _printerTarget,
              decoration: const InputDecoration(
                  labelText: 'Target (e.g., http://printer.local)')),
          TextField(
              controller: _printerLayout,
              decoration: const InputDecoration(labelText: 'Layout JSON')),
          TextField(
              controller: _printerWidth,
              decoration:
                  const InputDecoration(labelText: 'Char width (ESC/POS)'),
              keyboardType: TextInputType.number),
          TextField(
              controller: _printerStationFilter,
              decoration: const InputDecoration(
                  labelText: 'Station filter for auto/claim')),
          const SizedBox(height: 8),
          ElevatedButton(
              onPressed: _busy ? null : _createPrinter,
              child: const Text('Add printer')),
          const SizedBox(height: 12),
          const Text('Queued printer jobs'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _printerJobs
                .map((j) => Chip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                              'Job ${j['id']} • Order ${j['order_id']} • ${j['status']}'),
                          const SizedBox(width: 6),
                          TextButton(
                            onPressed: () => _renderJob(j['id'] as int),
                            child: const Text('Render'),
                          ),
                          const SizedBox(width: 6),
                          TextButton(
                            onPressed: () => _completeJob(j['id'] as int),
                            child: const Text('Done'),
                          ),
                        ],
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton(
                  onPressed: _busy ? null : _loadPrinterJobs,
                  child: const Text('Refresh jobs')),
              const SizedBox(width: 8),
              ElevatedButton(
                  onPressed: _busy ? null : _claimJob,
                  child: const Text('Claim next for selected printer')),
              const SizedBox(width: 8),
              Row(
                children: [
                  const Text('Auto print'),
                  Switch(
                    value: _autoPrint,
                    onChanged: (v) {
                      setState(() => _autoPrint = v);
                      if (v) {
                        _startAutoPrintLoop();
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ]),
        if (_out.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(_out)),
      ],
    );
  }

  Widget _kitchenTab() {
    return RefreshIndicator(
      onRefresh: _loadTickets,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                  label: const Text('All'),
                  selected: _ticketFilter.isEmpty,
                  onSelected: (_) => setState(() => _ticketFilter = '')),
              ChoiceChip(
                  label: const Text('New'),
                  selected: _ticketFilter == 'new',
                  onSelected: (_) => setState(() => _ticketFilter = 'new')),
              ChoiceChip(
                  label: const Text('Doing'),
                  selected: _ticketFilter == 'doing',
                  onSelected: (_) => setState(() => _ticketFilter = 'doing')),
              ChoiceChip(
                  label: const Text('Done'),
                  selected: _ticketFilter == 'done',
                  onSelected: (_) => setState(() => _ticketFilter = 'done')),
              ChoiceChip(
                  label: const Text('Fire'),
                  selected: _ticketFilter == 'fire',
                  onSelected: (_) => setState(() => _ticketFilter = 'fire')),
              ChoiceChip(
                  label: const Text('Recall'),
                  selected: _ticketFilter == 'recall',
                  onSelected: (_) => setState(() => _ticketFilter = 'recall')),
              ElevatedButton(
                  onPressed: _loadTickets, child: const Text('Refresh')),
            ],
          ),
          const SizedBox(height: 12),
          ..._tickets.map((t) => ListTile(
                title: Text('Order ${t['order_id']}'),
                subtitle: Text(
                    'Status: ${t['status']} • Courses: ${(t['courses'] ?? []).join(", ")} • Stations: ${(t['stations'] ?? []).join(", ")}'),
                trailing: Wrap(
                  spacing: 6,
                  children: [
                    TextButton(
                        onPressed: () => _updateTicket(t['id'] as int, 'fire'),
                        child: const Text('Fire')),
                    TextButton(
                        onPressed: () =>
                            _updateTicket(t['id'] as int, 'recall'),
                        child: const Text('Recall')),
                    TextButton(
                        onPressed: () => _updateTicket(t['id'] as int, 'doing'),
                        child: const Text('Doing')),
                    TextButton(
                        onPressed: () => _updateTicket(t['id'] as int, 'done'),
                        child: const Text('Done')),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _ordersTab() {
    return RefreshIndicator(
      onRefresh: _loadOrders,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: _orders
            .map((o) => ListTile(
                  title: Text('Order ${o['id']}'),
                  subtitle: Text(
                      'Status: ${o['status']} • Total: ${o['total_cents']} • Paid: ${o['paid_cents'] ?? 0} • Remaining: ${o['remaining_cents'] ?? 0}'),
                  trailing: Wrap(
                    spacing: 6,
                    children: [
                      TextButton(
                          onPressed: () => _callReceipt(o['id']),
                          child: const Text('Receipt')),
                      TextButton(
                          onPressed: () => _callPrint(o['id']),
                          child: const Text('Print')),
                      TextButton(
                          onPressed: () => _showOrderDetail(o['id']),
                          child: const Text('Detail')),
                      TextButton(
                        onPressed: () async {
                          try {
                            final r = await http.post(
                                widget.api.uri('pos/orders/${o['id']}/pay'));
                            _out = '${r.statusCode}: ${r.body}';
                            if (r.statusCode == 200) {
                              final data =
                                  jsonDecode(r.body) as Map<String, dynamic>;
                              final link =
                                  data['payment_link']?.toString() ?? '';
                              if (link.isNotEmpty) {
                                await launchUrl(Uri.parse(link),
                                    mode: LaunchMode.externalApplication);
                              }
                            }
                          } catch (e) {
                            _out = 'error: $e';
                          } finally {
                            if (mounted) setState(() {});
                          }
                        },
                        child: const Text('Pay link'),
                      ),
                      TextButton(
                        onPressed: () async {
                          try {
                            final r = await http.post(
                              widget.api.uri('pos/orders/${o['id']}/settle'),
                              headers: await _hdr(json: true),
                              body: jsonEncode({
                                "payment_method": "cash",
                                "tip_cents": _cartTip,
                                "device_id": _deviceId.text.trim()
                              }),
                            );
                            _out = '${r.statusCode}: ${r.body}';
                            await _loadOrders();
                          } catch (e) {
                            _out = 'error: $e';
                          } finally {
                            if (mounted) setState(() {});
                          }
                        },
                        child: const Text('Settle (cash)'),
                      ),
                      TextButton(
                        onPressed: () async {
                          try {
                            final r = await http.post(
                                widget.api.uri('pos/orders/${o['id']}/void'));
                            _out = '${r.statusCode}: ${r.body}';
                            await _loadOrders();
                          } catch (e) {
                            _out = 'error: $e';
                          } finally {
                            if (mounted) setState(() {});
                          }
                        },
                        child: const Text('Void'),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  Future<void> _showOrderDetail(dynamic orderId) async {
    try {
      final r = await http.get(widget.api.uri('pos/orders/$orderId'));
      if (r.statusCode != 200) {
        setState(() => _out = '${r.statusCode}: ${r.body}');
        return;
      }
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final lines = (body['lines'] as List?) ?? const [];
      final selected = <int>{};
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(builder: (ctx, setSt) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Order $orderId',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ...lines.map((ln) {
                    final id = ln['id'] as int;
                    return CheckboxListTile(
                      value: selected.contains(id),
                      onChanged: (v) {
                        setSt(() {
                          if (v == true) {
                            selected.add(id);
                          } else {
                            selected.remove(id);
                          }
                        });
                      },
                      title: Text(
                          'Line $id • Item ${ln['item_id']} x${ln['qty']}'),
                      subtitle: Text('Price ${ln['price_cents']}'),
                    );
                  }),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: selected.isEmpty
                            ? null
                            : () async {
                                try {
                                  final split = await http.post(
                                    widget.api.uri('pos/orders/$orderId/split'),
                                    headers: await _hdr(json: true),
                                    body: jsonEncode(
                                        {"line_ids": selected.toList()}),
                                  );
                                  _out = '${split.statusCode}: ${split.body}';
                                  await _loadOrders();
                                } catch (e) {
                                  _out = 'error: $e';
                                } finally {
                                  if (mounted) setState(() {});
                                }
                                if (mounted) Navigator.pop(ctx);
                              },
                        child: const Text('Split to new'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          });
        },
      );
    } catch (e) {
      setState(() => _out = 'error: $e');
    }
  }

  Widget _tablesTab() {
    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('Table plan', [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _tables.map((t) {
                final tableOrders =
                    _orders.where((o) => o['table_id'] == t['id']).toList();
                final openOrders =
                    tableOrders.where((o) => o['status'] != 'paid').toList();
                final total = tableOrders.fold<int>(
                    0, (p, e) => p + (e['total_cents'] as int? ?? 0));
                return GlassPanel(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(t['name'] ?? 'Table',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('Cap: ${t['capacity']}'),
                      Text('Status: ${t['status'] ?? 'free'}'),
                      Text('Open: ${openOrders.length} • Total: $total'),
                      Wrap(
                        spacing: 6,
                        children: [
                          TextButton(
                              onPressed: () =>
                                  _updateTableStatus(t['id'], 'free'),
                              child: const Text('Free')),
                          TextButton(
                              onPressed: () =>
                                  _updateTableStatus(t['id'], 'occupied'),
                              child: const Text('Occupied')),
                          TextButton(
                              onPressed: () =>
                                  _updateTableStatus(t['id'], 'cleaning'),
                              child: const Text('Cleaning')),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ]),
          const SizedBox(height: 12),
          _section('QR Ordering (guest)', [
            Row(
              children: [
                SizedBox(
                    width: 100,
                    child: TextField(
                        controller: _qrTable,
                        decoration:
                            const InputDecoration(labelText: 'Table id'),
                        keyboardType: TextInputType.number)),
                const SizedBox(width: 8),
                SizedBox(
                    width: 120,
                    child: TextField(
                        controller: _qrItem,
                        decoration: const InputDecoration(labelText: 'Item id'),
                        keyboardType: TextInputType.number)),
                const SizedBox(width: 8),
                SizedBox(
                    width: 100,
                    child: TextField(
                        controller: _qrQty,
                        decoration: const InputDecoration(labelText: 'Qty'),
                        keyboardType: TextInputType.number)),
                const SizedBox(width: 8),
                ElevatedButton(
                    onPressed: _createQrOrder,
                    child: const Text('Create QR order')),
              ],
            ),
            if (_qrPayLink.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Text('Payment link:'),
                    const SizedBox(width: 8),
                    Flexible(
                      child: InkWell(
                        onTap: () => launchUrl(Uri.parse(_qrPayLink),
                            mode: LaunchMode.externalApplication),
                        child: Text(_qrPayLink,
                            style: const TextStyle(
                                decoration: TextDecoration.underline)),
                      ),
                    ),
                  ],
                ),
              ),
          ]),
          const SizedBox(height: 12),
          _section('Reservation', [
            ..._reservations.map((r) => ListTile(
                  title: Text(r['guest_name'] ?? ''),
                  subtitle: Text(
                      'Table ${r['table_id']} • ${r['status']} • ${r['from_ts'] ?? ''} - ${r['to_ts'] ?? ''}'),
                )),
          ]),
          const SizedBox(height: 12),
          _section('Waitlist', [
            Row(
              children: [
                SizedBox(
                    width: 160,
                    child: TextField(
                        controller: _waitName,
                        decoration: const InputDecoration(labelText: 'Name'))),
                const SizedBox(width: 8),
                SizedBox(
                    width: 120,
                    child: TextField(
                        controller: _waitPhone,
                        decoration: const InputDecoration(labelText: 'Phone'))),
                const SizedBox(width: 8),
                SizedBox(
                    width: 80,
                    child: TextField(
                        controller: _waitParty,
                        decoration:
                            const InputDecoration(labelText: 'Party size'),
                        keyboardType: TextInputType.number)),
                const SizedBox(width: 8),
                ElevatedButton(
                    onPressed: _busy ? null : _createWait,
                    child: const Text('Add')),
              ],
            ),
            ..._waitlist.map((w) => ListTile(
                  title: Text('${w['guest_name']} (${w['party_size']})'),
                  subtitle: Text('Status: ${w['status']}'),
                  trailing: Wrap(
                    spacing: 6,
                    children: [
                      TextButton(
                          onPressed: () => _updateWait(w['id'], 'seated'),
                          child: const Text('Seat')),
                      TextButton(
                          onPressed: () => _updateWait(w['id'], 'canceled'),
                          child: const Text('Cancel')),
                    ],
                  ),
                )),
          ]),
        ],
      ),
    );
  }

  Widget _procurementTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Procurement & Inventory'),
        const SizedBox(height: 8),
        if (_items.isNotEmpty) Text('Items: ${_items.length}'),
        const SizedBox(height: 8),
        if (_reportDaily.isNotEmpty)
          GlassPanel(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Today: orders ${_reportDaily['orders'] ?? 0}, revenue ${_reportDaily['total_cents'] ?? 0}'),
                const SizedBox(height: 8),
                const Text('Low stock alerts:'),
                ...((_reportDaily['low_stock'] as List<dynamic>? ?? const [])
                    .map((i) =>
                        Text('${i['name']} • ${i['stock_qty']} ${i['unit']}'))),
              ],
            ),
          ),
      ],
    );
  }

  void _showGuestMods(Map item) {
    final gidList = _itemGroupIds(item);
    if (gidList.isEmpty) return;
    final itemId = item['id'] as int;
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: gidList.map((gid) {
              final g = _guestGroups.firstWhere((gr) => gr['id'] == gid,
                  orElse: () => {});
              final opts = (g['options'] as List?) ?? const [];
              if (opts.isEmpty) return const SizedBox();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${g['name']} ${g['required'] == true ? "(required)" : ""}',
                      style: Theme.of(context).textTheme.titleMedium),
                  Wrap(
                    spacing: 8,
                    children: opts
                        .map((o) => ChoiceChip(
                              label:
                                  Text('${o['name']} (+${o['price_cents']})'),
                              selected:
                                  ((_guestCart[itemId]?['mods'] as List<int>? ??
                                          [])
                                      .contains(o['id'])),
                              onSelected: (_) =>
                                  _guestToggleMod(itemId, o['id'] as int),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                ],
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _guestTab() {
    final filteredItems = _guestItems.where((it) {
      final allergens =
          (it['allergens'] as List?)?.map((e) => e.toString()).toList() ?? [];
      final diet =
          (it['diet_tags'] as List?)?.map((e) => e.toString()).toList() ?? [];
      if (_allergenFilter.isNotEmpty &&
          allergens.any((a) => _allergenFilter.contains(a))) {
        return false;
      }
      if (_dietFilter.isNotEmpty && !diet.contains(_dietFilter)) {
        return false;
      }
      return true;
    }).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Text('Lang'),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _guestLang,
              items: const [
                DropdownMenuItem(value: 'en', child: Text('EN')),
                DropdownMenuItem(value: 'de', child: Text('DE')),
                DropdownMenuItem(value: 'ar', child: Text('AR')),
              ],
              onChanged: (v) => setState(() => _guestLang = v ?? 'en'),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 140,
              child: DropdownButtonFormField<String>(
                hint: const Text('Diet filter'),
                initialValue: _dietFilter.isEmpty ? null : _dietFilter,
                onChanged: (v) => setState(() => _dietFilter = v ?? ''),
                items: <String>[
                  '',
                  'vegan',
                  'vegetarian',
                  'halal',
                  'glutenfree'
                ]
                    .map((d) => DropdownMenuItem(
                        value: d, child: Text(d.isEmpty ? 'Any' : d)))
                    .toList(),
              ),
            ),
            const SizedBox(width: 12),
            Wrap(
              spacing: 6,
              children: ['gluten', 'nuts', 'shellfish', 'lactose']
                  .map((a) => FilterChip(
                        label: Text(a),
                        selected: _allergenFilter.contains(a),
                        onSelected: (v) {
                          setState(() {
                            if (v) {
                              _allergenFilter.add(a);
                            } else {
                              _allergenFilter.remove(a);
                            }
                          });
                        },
                      ))
                  .toList(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _section('Guest menu', [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: filteredItems
                .map((it) => SizedBox(
                      width: 180,
                      child: GlassPanel(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if ((it['image_url'] ?? '').toString().isNotEmpty)
                              Container(
                                height: 80,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  image: DecorationImage(
                                    fit: BoxFit.cover,
                                    image: NetworkImage(it['image_url']),
                                  ),
                                ),
                              ),
                            Text(it['name'] ?? '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text('${it['price_cents']} ${it['currency']}'),
                            if ((it['allergens'] as List?)?.isNotEmpty ?? false)
                              Text(
                                  'Allergens: ${(it['allergens'] as List).join(", ")}',
                                  style: Theme.of(context).textTheme.bodySmall),
                            if ((it['diet_tags'] as List?)?.isNotEmpty ?? false)
                              Text(
                                  'Diet: ${(it['diet_tags'] as List).join(", ")}',
                                  style: Theme.of(context).textTheme.bodySmall),
                            const Spacer(),
                            Row(
                              children: [
                                TextButton(
                                    onPressed: () => _guestAddItem(it),
                                    child: const Text('Add')),
                                if (_itemGroupIds(it).isNotEmpty)
                                  TextButton(
                                      onPressed: () => _showGuestMods(it),
                                      child: const Text('Mods')),
                              ],
                            )
                          ],
                        ),
                      ),
                    ))
                .toList(),
          ),
        ]),
        const SizedBox(height: 12),
        _section('Guest cart', [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _guestCart.entries.map((e) {
              final item = _guestItems.firstWhere((it) => it['id'] == e.key,
                  orElse: () => {});
              return Chip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${item['name']}'),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.remove),
                      onPressed: () {
                        final qty = (e.value['qty'] as int? ?? 1) - 1;
                        if (qty <= 0) {
                          setState(() => _guestCart.remove(e.key));
                        } else {
                          setState(() =>
                              _guestCart[e.key] = {...e.value, "qty": qty});
                        }
                      },
                    ),
                    Text('x${e.value['qty']}'),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.add),
                      onPressed: () => setState(() => _guestCart[e.key] = {
                            ...e.value,
                            "qty": (e.value['qty'] as int? ?? 1) + 1
                          }),
                    ),
                  ],
                ),
                onDeleted: () => setState(() => _guestCart.remove(e.key)),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                  width: 100,
                  child: TextField(
                      controller: _guestTable,
                      decoration: const InputDecoration(labelText: 'Table'))),
              const SizedBox(width: 8),
              SizedBox(
                  width: 160,
                  child: TextField(
                      controller: _guestName,
                      decoration: const InputDecoration(labelText: 'Name'))),
              const SizedBox(width: 8),
              SizedBox(
                  width: 160,
                  child: TextField(
                      controller: _guestPhone,
                      decoration: const InputDecoration(labelText: 'Phone'))),
              const SizedBox(width: 8),
              SizedBox(
                  width: 140,
                  child: TextField(
                      controller: _guestDevice,
                      decoration:
                          const InputDecoration(labelText: 'Device code'))),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Tip (cents)'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => _guestTip = int.tryParse(v.trim()) ?? 0,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                  onPressed: _busy ? null : _submitGuestOrder,
                  child: const Text('Submit')),
            ],
          ),
          if (_guestPayLink.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: InkWell(
                onTap: () => launchUrl(Uri.parse(_guestPayLink),
                    mode: LaunchMode.externalApplication),
                child: Text('Pay link: $_guestPayLink',
                    style:
                        const TextStyle(decoration: TextDecoration.underline)),
              ),
            ),
          if (_guestOrderId.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Text('Order id: $_guestOrderId'),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      try {
                        final r = await http.get(
                          widget.api.uri('pos/qr/orders/$_guestOrderId'),
                        );
                        if (r.statusCode == 200) {
                          final body =
                              jsonDecode(r.body) as Map<String, dynamic>;
                          setState(() => _guestOrderStatus =
                              body['status']?.toString() ?? '');
                        } else {
                          setState(() => _guestOrderStatus =
                              'status error ${r.statusCode}');
                        }
                      } catch (e) {
                        setState(() => _guestOrderStatus = 'error $e');
                      }
                    },
                    child: const Text('Check status'),
                  ),
                  const SizedBox(width: 8),
                  if (_guestOrderStatus.isNotEmpty)
                    Text('Status: $_guestOrderStatus'),
                ],
              ),
            ),
        ]),
      ],
    );
  }

  Widget _section(String title, List<Widget> children) {
    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bg = AppBG();
    return Scaffold(
      appBar: AppBar(
        title: const Text('POS Suite'),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabs: const [
            Tab(text: 'POS'),
            Tab(text: 'Kitchen'),
            Tab(text: 'Orders'),
            Tab(text: 'Tables'),
            Tab(text: 'Procurement'),
            Tab(text: 'Guest'),
          ],
        ),
      ),
      body: Stack(
        children: [
          bg,
          TabBarView(
            controller: _tab,
            children: [
              _posTab(),
              _kitchenTab(),
              _ordersTab(),
              _tablesTab(),
              _procurementTab(),
              _guestTab(),
            ],
          ),
        ],
      ),
    );
  }
}
