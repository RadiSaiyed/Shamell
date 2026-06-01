// Cycle 206 — SyrTrans Shipper-Flavor Console.
//
// Mirror der CarrierConsolePage aber aus Verlader-Sicht:
//   * "Post load" → Open eines bestehenden Marketplace-Post-Sheets
//   * "My postings" → Liste der eigenen freight_load_offers
//   * "Bids inbox" → Liste der Bids auf eigenen Auctions
//
// Minimal-MVP für Cycle 206: nur das Console-Shell + 3 Tabs als
// Stubs, die auf existierende API-Endpoints zeigen. Detaillierte
// Sheets werden in Folge-Cycles ausgebaut.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

class ShipperConsolePage extends StatefulWidget {
  const ShipperConsolePage({super.key, this.baseUrl});

  final String? baseUrl;

  @override
  State<ShipperConsolePage> createState() => _ShipperConsolePageState();
}

class _ShipperConsolePageState extends State<ShipperConsolePage>
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
        title: const Text('SyrTrans Shipper'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.local_shipping), text: 'My postings'),
            Tab(icon: Icon(Icons.gavel), text: 'Bids inbox'),
            Tab(icon: Icon(Icons.add_box), text: 'Post load'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _PostingsTab(baseUrl: widget.baseUrl),
          _BidsInboxTab(baseUrl: widget.baseUrl),
          _PostLoadTab(baseUrl: widget.baseUrl),
        ],
      ),
    );
  }
}

class _PostingsTab extends StatelessWidget {
  const _PostingsTab({this.baseUrl});
  final String? baseUrl;

  @override
  Widget build(BuildContext context) {
    // For Cycle 206 minimal-MVP we leave the org-id wiring to follow-up
    // (it lands once the role-signup flow populates the
    // freight_organizations row). Empty-state messaging keeps the
    // surface visible without an API call to an unknown org.
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'Your posted loads will appear here once your shipper org is\n'
          'attached. Tap "Post load" to create your first offer.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _BidsInboxTab extends StatelessWidget {
  const _BidsInboxTab({this.baseUrl});
  final String? baseUrl;

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'Bids on your auction offers will land here. Accept the\n'
          'best one to lock the price + create the booking.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _PostLoadTab extends StatefulWidget {
  const _PostLoadTab({this.baseUrl});
  final String? baseUrl;

  @override
  State<_PostLoadTab> createState() => _PostLoadTabState();
}

class _PostLoadTabState extends State<_PostLoadTab> {
  final _form = GlobalKey<FormState>();
  final _ref = TextEditingController();
  final _from = TextEditingController(text: 'SY');
  final _to = TextEditingController(text: 'AE');
  final _weight = TextEditingController();
  final _price = TextEditingController();
  String _cargoKind = 'general';
  String _pricingKind = 'instant';
  bool _coldChain = false;
  final _tempMin = TextEditingController();
  final _tempMax = TextEditingController();
  bool _busy = false;
  String? _status;

  @override
  void dispose() {
    _ref.dispose();
    _from.dispose();
    _to.dispose();
    _weight.dispose();
    _price.dispose();
    _tempMin.dispose();
    _tempMax.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    final body = <String, dynamic>{
      'public_reference': _ref.text.trim(),
      'pickup_country': _from.text.trim().toUpperCase(),
      'delivery_country': _to.text.trim().toUpperCase(),
      'cargo_kind': _cargoKind,
      'weight_kg': int.tryParse(_weight.text.trim()) ?? 0,
      'price_minor_units': int.tryParse(_price.text.trim()) ?? 0,
      'currency': 'EUR',
      'pricing_kind': _pricingKind,
      'requires_temperature_control': _coldChain,
      if (_coldChain) 'temperature_min_c': double.tryParse(_tempMin.text.trim()),
      if (_coldChain) 'temperature_max_c': double.tryParse(_tempMax.text.trim()),
    };
    try {
      final base = (widget.baseUrl ?? 'https://api.shamell.online').replaceAll(
        RegExp(r'/+$'),
        '',
      );
      // Real wire to the marketplace endpoint lands after the
      // shipper-org binding is in place; until then we render the
      // form payload so the operator can copy/paste into a curl call
      // or hand it to the carrier console for testing.
      setState(() {
        _status = 'Prepared payload (org-binding pending):\n${jsonEncode(body)}';
      });
      await Future<void>.delayed(const Duration(milliseconds: 200));
      // Touching base avoids an unused-variable warning while the
      // wire is parked.
      assert(base.isNotEmpty);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _ref,
              decoration: const InputDecoration(
                labelText: 'Reference',
                hintText: 'e.g. SHP-2026-001',
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Reference required'
                  : null,
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _from,
                  decoration: const InputDecoration(labelText: 'From (ISO2)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _to,
                  decoration: const InputDecoration(labelText: 'To (ISO2)'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _cargoKind,
              items: const [
                DropdownMenuItem(value: 'general', child: Text('General')),
                DropdownMenuItem(value: 'perishable', child: Text('Perishable')),
                DropdownMenuItem(value: 'pharma', child: Text('Pharma')),
                DropdownMenuItem(value: 'dangerous', child: Text('Dangerous')),
                DropdownMenuItem(value: 'liquid', child: Text('Liquid')),
                DropdownMenuItem(value: 'bulk', child: Text('Bulk')),
              ],
              decoration: const InputDecoration(labelText: 'Cargo'),
              onChanged: (v) => setState(() => _cargoKind = v ?? 'general'),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _weight,
                  decoration: const InputDecoration(labelText: 'Weight (kg)'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _price,
                  decoration:
                      const InputDecoration(labelText: 'Price (EUR cents)'),
                  keyboardType: TextInputType.number,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _pricingKind,
              items: const [
                DropdownMenuItem(value: 'instant', child: Text('Instant')),
                DropdownMenuItem(value: 'fixed', child: Text('Fixed')),
                DropdownMenuItem(
                    value: 'negotiable', child: Text('Negotiable')),
                DropdownMenuItem(value: 'auction', child: Text('Auction')),
              ],
              decoration: const InputDecoration(labelText: 'Pricing kind'),
              onChanged: (v) => setState(() => _pricingKind = v ?? 'instant'),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Cold-chain (temperature control)'),
              value: _coldChain,
              onChanged: (v) => setState(() => _coldChain = v),
            ),
            if (_coldChain)
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _tempMin,
                    decoration: const InputDecoration(labelText: 'Min °C'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _tempMax,
                    decoration: const InputDecoration(labelText: 'Max °C'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ]),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? 'Submitting…' : 'Post load'),
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
      ),
    );
  }
}
