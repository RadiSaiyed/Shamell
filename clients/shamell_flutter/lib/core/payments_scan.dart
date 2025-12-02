import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'glass.dart';
import 'l10n.dart';
import 'payments_send.dart' show PayActionButton; // reuse styled button
import 'scan_page.dart';

class PaymentScanTab extends StatefulWidget{
  final String baseUrl; final String fromWalletId; final bool autoScan;
  const PaymentScanTab({super.key, required this.baseUrl, required this.fromWalletId, this.autoScan=false});
  @override State<PaymentScanTab> createState()=>_PaymentScanTabState();
}

class _PaymentScanTabState extends State<PaymentScanTab>{
  final toCtrl = TextEditingController();
  final aliasCtrl = TextEditingController();
  final amtCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  String out=''; bool _scanned=false;
  bool _showAmountPrompt = false;

  @override
  void didChangeDependencies(){
    super.didChangeDependencies();
    if(widget.autoScan && !_scanned){
      _scanned = true;
      Future.microtask(_scan);
    }
  }

  Future<void> _scan() async {
    try{
      final raw = await Navigator.push(context, MaterialPageRoute(builder: (_)=> const ScanPage()));
      if(!mounted) return; if(raw==null) return;
      final p = _parse(raw.toString());
      toCtrl.text = p['to_wallet_id'] ?? '';
      aliasCtrl.text = p['to_alias'] ?? '';
      if((p['amount']??'').toString().isNotEmpty) amtCtrl.text = p['amount']!;
      if((p['note']??'').toString().isNotEmpty) noteCtrl.text = p['note']!;
      setState(() {
        // Reset any previous amount prompt; _confirmAndPay will re-enable it if needed.
        _showAmountPrompt = false;
      });
      await _confirmAndPay();
    }catch(e){ if(!mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scan error: $e'))); }
  }

  Map<String,String> _parse(String raw){
    String toWallet='', toAlias='', amount='', note='';
    try{
      // Custom PAY| format: PAY|wallet=...|amount=...|ref=...
      if(raw.startsWith('PAY|')){
        final parts = raw.split('|');
        for(final p in parts.skip(1)){
          final kv = p.split('=');
          if(kv.length!=2) continue;
          final k = kv[0].trim();
          final v = Uri.decodeComponent(kv[1].trim());
          switch(k){
            case 'wallet': toWallet = v; break;
            case 'to_wallet_id': toWallet = v; break;
            case 'alias': toAlias = v; break;
            case 'to_alias': toAlias = v; break;
            case 'amount': amount = v; break; // SYP major units string
            case 'ref': note = v; break;
            case 'note': note = v; break;
          }
        }
      } else if(raw.trim().startsWith('{')){
        final j=jsonDecode(raw);
        toWallet=(j['to_wallet_id']??'').toString();
        toAlias=(j['to_alias']??j['alias']??'').toString();
        amount=(j['amount']??j['amount_syp']??'').toString();
        note=(j['note']??j['reference']??'').toString();
      }else{
        final uri = Uri.tryParse(raw);
        if(uri!=null && uri.scheme.isNotEmpty){
          final q=uri.queryParameters;
          toWallet=(q['to_wallet_id']??'').toString();
          toAlias=(q['to_alias']??q['alias']??'').toString();
          amount=(q['amount']??q['amt']??'').toString();
          note=(q['note']??q['ref']??'').toString();
          if(toWallet.isEmpty && toAlias.isEmpty){ final segs=uri.pathSegments.where((s)=>s.isNotEmpty).toList(); if(segs.isNotEmpty) toWallet=segs.last; }
        }else{
          if(raw.trim().startsWith('@')) toAlias=raw.trim(); else toWallet=raw.trim();
        }
      }
    }catch(_){ }
    return {'to_wallet_id':toWallet,'to_alias':toAlias,'amount':amount,'note':note};
  }

  Future<void> _pay() async {
    final toWallet=toCtrl.text.trim(); final toAlias=aliasCtrl.text.trim(); final amt=amtCtrl.text.trim(); final note=noteCtrl.text.trim();
    if(amt.isEmpty || (toWallet.isEmpty && toAlias.isEmpty)){ setState(()=> out='Enter target and amount'); return; }
    setState((){ out='...'; });
    try{
      final body = <String,dynamic>{ 'from_wallet_id': widget.fromWalletId, 'amount': amt };
      if(toWallet.isNotEmpty) body['to_wallet_id']=toWallet; else body['to_alias']=toAlias;
      if(note.isNotEmpty) body['reference']=note;
      final r = await http.post(Uri.parse('${widget.baseUrl}/payments/transfer'), headers: {'content-type':'application/json'}, body: jsonEncode(body));
      setState(()=> out='${r.statusCode}: ${r.body}');
    }catch(e){ setState(()=> out='Error: $e'); }
  }

  Future<void> _confirmAndPay() async {
    final toWallet=toCtrl.text.trim(); final toAlias=aliasCtrl.text.trim(); final amt=amtCtrl.text.trim();
    if(toWallet.isEmpty && toAlias.isEmpty){
      setState(() {
        _showAmountPrompt = false;
        out = 'Invalid QR: missing payment target';
      });
      return;
    }
    if(amt.isEmpty){
      setState(() {
        _showAmountPrompt = true;
        out = '';
      });
      return;
    }
    final target = toAlias.isNotEmpty ? toAlias : toWallet;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx){
        return AlertDialog(
          title: const Text('Confirm'),
          content: Text('Pay $amt SYP to $target now?'),
          actions: [
            TextButton(onPressed: (){ Navigator.pop(ctx, false); }, child: const Text('Cancel')),
            FilledButton(onPressed: (){ Navigator.pop(ctx, true); }, child: const Text('Pay')),
          ],
        );
      },
    );
    if(ok==true){
      await _pay();
    }
  }

  @override Widget build(BuildContext context){
    final l = L10n.of(context);
    final content = ListView(
      padding: const EdgeInsets.all(12),
      children: [
        PayActionButton(
          label: l.isArabic ? 'مسح رمز QR للدفع' : 'Scan QR to pay',
          onTap: _scan,
        ),
        const SizedBox(height: 12),
        if(_showAmountPrompt)...[
          GlassPanel(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.isArabic ? 'أدخل المبلغ لهذا الدفع' : 'Enter amount for this payment',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: amtCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Amount (SYP)'),
                ),
                const SizedBox(height: 8),
                PayActionButton(
                  label: l.isArabic ? 'تأكيد الدفع' : 'Confirm payment',
                  onTap: _confirmAndPay,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        if(out.isNotEmpty) SelectableText(out),
      ],
    );

    return GlassPanel(padding: const EdgeInsets.all(12), child: content);
  }
}
