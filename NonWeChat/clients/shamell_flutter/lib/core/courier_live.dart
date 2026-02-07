import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class CourierLivePage extends StatefulWidget {
  final String baseUrl;
  const CourierLivePage(this.baseUrl, {super.key});

  @override
  State<CourierLivePage> createState() => _CourierLivePageState();
}

class _CourierLivePageState extends State<CourierLivePage> {
  WebSocket? _ws;
  final List<String> _log = [];
  final List<dynamic> _orders = [];
  final Map<int, Map<String, dynamic>> _drivers = {};
  bool _connected = false;
  final _statusCtl = TextEditingController();
  final _photoUrlCtl = TextEditingController();
  final _orderIdCtl = TextEditingController();
  Timer? _ping;

  String get _wsUrl =>
      widget.baseUrl.replaceFirst(RegExp(r"^http"), "ws") + "/courier/ws";

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _ws?.close();
    _ping?.cancel();
    _statusCtl.dispose();
    _photoUrlCtl.dispose();
    _orderIdCtl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    try {
      final ws = await WebSocket.connect(_wsUrl);
      _ws = ws;
      setState(() => _connected = true);
      _logMsg("connected");
      _ping = Timer.periodic(const Duration(seconds: 20), (_) {
        ws.add("ping");
      });
      ws.listen((data) {
        _handle(data);
      }, onDone: () {
        _logMsg("disconnected");
        setState(() => _connected = false);
        _reconnect();
      }, onError: (_) {
        _logMsg("ws error");
        setState(() => _connected = false);
        _reconnect();
      });
    } catch (e) {
      _logMsg("connect error $e");
      _reconnect();
    }
  }

  void _reconnect() {
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      _connect();
    });
  }

  void _handle(dynamic data) {
    try {
      final msg = jsonDecode(data);
      if (msg is! Map) return;
      if (msg['type'] == 'driver_location') {
        final id = msg['id'] as int;
        _drivers[id] = {
          "id": id,
          "lat": msg['lat'],
          "lng": msg['lng'],
          "status": msg['status'],
          "updated": DateTime.now(),
        };
      } else if (msg['type'] == 'order_status') {
        _orders.removeWhere((o) => o['id'] == msg['id']);
        _orders.add({"id": msg['id'], "status": msg['status']});
      }
      setState(() {});
    } catch (e) {
      _logMsg("parse error $e");
    }
  }

  void _logMsg(String m) {
    setState(() => _log.add("${DateTime.now().toIso8601String()} $m"));
  }

  Future<void> _pushDriverEvent() async {
    final oid = _orderIdCtl.text.trim();
    if (oid.isEmpty) return;
    final status =
        _statusCtl.text.trim().isEmpty ? "delivering" : _statusCtl.text.trim();
    final photo = _photoUrlCtl.text.trim();
    try {
      final body = jsonEncode({
        "status": status,
        "note": photo.isEmpty ? null : "photo:$photo",
      });
      final r = await http.post(
          Uri.parse('${widget.baseUrl}/courier/orders/$oid/status'),
          headers: {"content-type": "application/json"},
          body: body);
      _logMsg("push status ${r.statusCode}");
    } catch (e) {
      _logMsg("push error $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Courier Live'),
        actions: [
          Icon(_connected ? Icons.cloud_done : Icons.cloud_off),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                    child: TextField(
                        controller: _orderIdCtl,
                        decoration:
                            const InputDecoration(labelText: 'Order id'))),
                const SizedBox(width: 8),
                SizedBox(
                    width: 140,
                    child: TextField(
                        controller: _statusCtl,
                        decoration: const InputDecoration(
                            labelText:
                                'Status (pickup/delivering/delivered)'))),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                        controller: _photoUrlCtl,
                        decoration: const InputDecoration(
                            labelText: 'Photo URL (as note)'))),
                const SizedBox(width: 8),
                ElevatedButton(
                    onPressed: _pushDriverEvent,
                    child: const Text('Send driver update')),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  const Text('Drivers'),
                  Wrap(
                    spacing: 8,
                    children: _drivers.values
                        .map((d) => Chip(
                            label: Text(
                                'D${d['id']} ${d['status']} @ ${d['lat']},${d['lng']}')))
                        .toList(),
                  ),
                  const SizedBox(height: 8),
                  const Text('Orders'),
                  Wrap(
                    spacing: 8,
                    children: _orders
                        .map((o) =>
                            Chip(label: Text('${o['id']} • ${o['status']}')))
                        .toList(),
                  ),
                  const SizedBox(height: 8),
                  const Text('Log'),
                  ..._log.reversed.take(20).map((l) =>
                      Text(l, style: Theme.of(context).textTheme.bodySmall)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
