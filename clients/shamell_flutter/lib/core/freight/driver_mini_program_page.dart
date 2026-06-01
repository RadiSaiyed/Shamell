// Cycle 207 — SyrTrans Driver mini-program (lives inside SyrChat user
// flavor; no standalone APK by design — driver privacy / device
// commingling concerns).
//
// Surface:
//   * "My runs" — assigned bookings for this driver (Phase 1 stub:
//     copy of the booking id reads from a textfield; real lookup via
//     freight_drivers + freight_load_offer_bookings.assigned_driver_id
//     lands once the user-account → driver binding is wired)
//   * "Mark pickup / Mark delivery" — hits the freight_service
//     POST /v1/freight/bookings/:id/pickup|delivery with proof_uri
//   * "Submit temperature" — POST /v1/freight/bookings/:id/temperature
//     with the cabin-thermometer reading + zone + source='driver'
//
// Intentionally minimal — heavy POD-photo capture flow + sensor
// pairing follow in a later cycle. The driver MVP unblocks the
// telematics + delivery-status loop end-to-end via manual entry.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class FreightDriverMiniProgramPage extends StatefulWidget {
  const FreightDriverMiniProgramPage({super.key, this.baseUrl});

  final String? baseUrl;

  @override
  State<FreightDriverMiniProgramPage> createState() =>
      _FreightDriverMiniProgramPageState();
}

class _FreightDriverMiniProgramPageState
    extends State<FreightDriverMiniProgramPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SyrTrans Driver'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.assignment_outlined), text: 'My runs'),
            Tab(icon: Icon(Icons.thermostat), text: 'Temperature'),
            Tab(icon: Icon(Icons.local_shipping), text: 'Status'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          const _MyRunsTab(),
          _TemperatureTab(baseUrl: widget.baseUrl),
          _StatusTab(baseUrl: widget.baseUrl),
        ],
      ),
    );
  }
}

class _MyRunsTab extends StatelessWidget {
  const _MyRunsTab();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'Your assigned runs will appear here once a dispatcher\n'
          'binds your account to the carrier org. Use the Temperature\n'
          'and Status tabs to interact with a specific booking by id.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _BookingIdField extends StatelessWidget {
  const _BookingIdField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: const InputDecoration(
        labelText: 'Booking id (uuid)',
        hintText: '00000000-0000-0000-0000-000000000000',
      ),
    );
  }
}

class _TemperatureTab extends StatefulWidget {
  const _TemperatureTab({this.baseUrl});
  final String? baseUrl;

  @override
  State<_TemperatureTab> createState() => _TemperatureTabState();
}

class _TemperatureTabState extends State<_TemperatureTab> {
  final _bookingId = TextEditingController();
  final _temp = TextEditingController();
  String _zone = 'primary';
  bool _busy = false;
  String? _status;

  @override
  void dispose() {
    _bookingId.dispose();
    _temp.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final id = _bookingId.text.trim();
    final t = double.tryParse(_temp.text.trim());
    if (id.isEmpty || t == null) {
      setState(() => _status = 'Need booking id + a numeric temperature.');
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final base =
          (widget.baseUrl ?? 'https://api.shamell.online').replaceAll(
        RegExp(r'/+$'),
        '',
      );
      final body = jsonEncode({
        'recorded_at': DateTime.now().toUtc().toIso8601String(),
        'temp_c': t,
        'zone': _zone,
        'source': 'driver',
      });
      final resp = await http.post(
        Uri.parse('$base/v1/freight/bookings/$id/temperature'),
        headers: {'content-type': 'application/json'},
        body: body,
      );
      setState(() => _status = 'HTTP ${resp.statusCode}: ${resp.body}');
    } catch (e) {
      setState(() => _status = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BookingIdField(controller: _bookingId),
          const SizedBox(height: 8),
          TextFormField(
            controller: _temp,
            decoration: const InputDecoration(
              labelText: 'Temperature (°C)',
              hintText: 'e.g. 4.5',
            ),
            keyboardType: const TextInputType.numberWithOptions(
              signed: true,
              decimal: true,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'primary', label: Text('Primary')),
              ButtonSegment(value: 'secondary', label: Text('Secondary')),
            ],
            selected: {_zone},
            onSelectionChanged: (s) => setState(() => _zone = s.first),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _send,
            icon: const Icon(Icons.send),
            label: Text(_busy ? 'Sending…' : 'Submit reading'),
          ),
          if (_status != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _status!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusTab extends StatefulWidget {
  const _StatusTab({this.baseUrl});
  final String? baseUrl;

  @override
  State<_StatusTab> createState() => _StatusTabState();
}

class _StatusTabState extends State<_StatusTab> {
  final _bookingId = TextEditingController();
  final _proofUri = TextEditingController();
  bool _busy = false;
  String? _status;

  @override
  void dispose() {
    _bookingId.dispose();
    _proofUri.dispose();
    super.dispose();
  }

  Future<void> _transition(String action) async {
    final id = _bookingId.text.trim();
    if (id.isEmpty) {
      setState(() => _status = 'Need a booking id.');
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final base =
          (widget.baseUrl ?? 'https://api.shamell.online').replaceAll(
        RegExp(r'/+$'),
        '',
      );
      final body = jsonEncode({
        if (_proofUri.text.trim().isNotEmpty)
          'proof_uri': _proofUri.text.trim(),
      });
      final resp = await http.post(
        Uri.parse('$base/v1/freight/bookings/$id/$action'),
        headers: {'content-type': 'application/json'},
        body: body,
      );
      setState(() => _status = 'HTTP ${resp.statusCode}: ${resp.body}');
    } catch (e) {
      setState(() => _status = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BookingIdField(controller: _bookingId),
          const SizedBox(height: 8),
          TextFormField(
            controller: _proofUri,
            decoration: const InputDecoration(
              labelText: 'Proof URI (optional)',
              hintText: 'https://files.shamell.online/...',
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _transition('pickup'),
                icon: const Icon(Icons.arrow_upward),
                label: const Text('Mark pickup'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _transition('delivery'),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Mark delivery'),
              ),
            ),
          ]),
          if (_status != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _status!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
