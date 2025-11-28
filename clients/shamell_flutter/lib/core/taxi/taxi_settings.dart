import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../glass.dart';
import '../format.dart' show fmtCents;
import '../l10n.dart';
import 'taxi_common.dart' show hdrTaxi, TaxiBG;

class TaxiSettingsPage extends StatefulWidget{
  final String baseUrl;
  const TaxiSettingsPage(this.baseUrl, {super.key});
  @override State<TaxiSettingsPage> createState()=>_TaxiSettingsPageState();
}

class _TaxiSettingsPageState extends State<TaxiSettingsPage>{
  bool _loading = false;
  String _out = '';
  double _rate = 0.10; // 10%
  final TextEditingController _rateCtrl = TextEditingController(text: '10');

  @override void initState(){
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(()=>_loading=true);
    try{
      final uri = Uri.parse('${widget.baseUrl}/taxi/settings');
      final r = await http.get(uri, headers: await hdrTaxi());
      if(r.statusCode==200){
        final j = jsonDecode(r.body);
        final rate = (j['brokerage_rate']??0.10) as num;
        _rate = rate.toDouble();
        _rateCtrl.text = (_rate * 100).toStringAsFixed(1);
        _out = '';
      }else{
        _out = '${r.statusCode}: ${r.body}';
      }
    }catch(e){
      _out = 'Error: $e';
    }
    if(mounted) setState(()=>_loading=false);
  }

  Future<void> _save() async {
    setState(()=>_loading=true);
    try{
      final v = double.tryParse(_rateCtrl.text.trim().replaceAll(',', '.')) ?? (_rate * 100);
      final rate = (v / 100.0).clamp(0.0, 0.5);
      final uri = Uri.parse('${widget.baseUrl}/taxi/settings');
      final body = jsonEncode({'brokerage_rate': rate});
      final r = await http.post(uri, headers: await hdrTaxi(json:true), body: body);
      if(r.statusCode==200){
        final j = jsonDecode(r.body);
        final newRate = (j['brokerage_rate']??rate) as num;
        _rate = newRate.toDouble();
        _rateCtrl.text = (_rate * 100).toStringAsFixed(1);
        _out = 'Updated brokerage rate to ${(_rate*100).toStringAsFixed(1)}%';
      }else{
        _out = '${r.statusCode}: ${r.body}';
      }
    }catch(e){
      _out = 'Error: $e';
    }
    if(mounted) setState(()=>_loading=false);
  }

  @override
  void dispose(){
    _rateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context){
    final cs = Theme.of(context).colorScheme;
    final body = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Taxi Settings', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Brokerage fee (platform commission charged on each completed ride).', style: TextStyle(color: cs.onSurface.withOpacity(.8))),
        const SizedBox(height: 16),
        Row(children:[
          Expanded(child: TextField(
            controller: _rateCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Brokerage fee (%)',
              helperText: '0.0 – 50.0',
            ),
          )),
        ]),
        const SizedBox(height: 12),
        Slider(
          value: (_rate * 100).clamp(0, 50),
          min: 0,
          max: 50,
          divisions: 50,
          label: '${(_rate*100).toStringAsFixed(1)}%',
          onChanged: (v){
            setState((){
              _rate = (v / 100.0);
              _rateCtrl.text = v.toStringAsFixed(1);
            });
          },
        ),
        const SizedBox(height: 8),
        Text('Example: For a 30,000 SYP ride, fee = ${fmtCents((30000 * _rate).round())} SYP, driver gets ${fmtCents((30000 * (1.0-_rate)).round())} SYP.', style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.8))),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _loading? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(L10n.of(context).isArabic ? 'حفظ الإعدادات' : 'Save settings'),
        ),
        const SizedBox(height: 16),
        if(_out.isNotEmpty) SelectableText(_out),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: Text(L10n.of(context).isArabic ? 'إعدادات التاكسي' : 'Taxi Settings'), backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(children:[
        const TaxiBG(),
        Positioned.fill(child: SafeArea(child: GlassPanel(padding: const EdgeInsets.all(12), radius: 12, child: _loading? const Center(child: CircularProgressIndicator()) : body))),
      ]),
    );
  }
}
