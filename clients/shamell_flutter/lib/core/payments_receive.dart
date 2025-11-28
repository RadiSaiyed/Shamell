import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'glass.dart';
import 'offline_queue.dart';
import 'format.dart' show fmtCents;
import 'l10n.dart';
// WaterButton removed from Payments; no main import required
import 'payments_send.dart' show PayActionButton; // reuse button style

class ShareQrPanel extends StatelessWidget{
  final String payload; const ShareQrPanel({super.key, required this.payload});
  @override Widget build(BuildContext context){
    return Padding(padding: const EdgeInsets.all(16), child:
      Column(mainAxisSize: MainAxisSize.min, children:[
        Text(payload, textAlign: TextAlign.center), const SizedBox(height:8), QrImageView(data: payload, size: 220)
      ]));
  }
}

class PaymentReceiveTab extends StatefulWidget{
  final String baseUrl; final String fromWalletId;
  const PaymentReceiveTab({super.key, required this.baseUrl, required this.fromWalletId});
  @override State<PaymentReceiveTab> createState()=>_PaymentReceiveTabState();
}

class _PaymentReceiveTabState extends State<PaymentReceiveTab>{
  String myWallet=''; String _curSym='SYP'; int? _balanceCents; bool _loadingWallet=false;
  final amtCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  String qrPayload='';
  final sonicAmtCtrl = TextEditingController(text:'10.00');
  final sonicTokenCtrl = TextEditingController();
  String sonicOut=''; String sonicPayload='';

  @override void initState(){ super.initState(); _init(); }
  Future<void> _init() async { final sp=await SharedPreferences.getInstance(); myWallet=sp.getString('wallet_id') ?? widget.fromWalletId; final cs=sp.getString('currency_symbol'); if(cs!=null&&cs.isNotEmpty) _curSym=cs; setState((){}); await _loadWallet(); }

  Future<void> _loadWallet() async { if(myWallet.isEmpty) return; setState(()=>_loadingWallet=true); try{ final r=await http.get(Uri.parse('${widget.baseUrl}/payments/wallets/'+Uri.encodeComponent(myWallet)), headers: await _hdrPRC()); if(r.statusCode==200){ final j=jsonDecode(r.body); _balanceCents=(j['balance_cents']??0) as int; } }catch(_){ } if(mounted) setState(()=>_loadingWallet=false); }

  double _parseMajor(String s){ try{ final t=s.trim().replaceAll(',', '.'); return double.parse(t); }catch(_){ return 0; } }
  void _makeMyQR(){ final a=_parseMajor(amtCtrl.text.trim()); if(myWallet.isEmpty){ setState(()=>qrPayload=''); return; } final note=noteCtrl.text.trim(); var p='PAY|wallet='+Uri.encodeComponent(myWallet); if(a>0) p+='|amount='+Uri.encodeComponent(a.toStringAsFixed(2)); if(note.isNotEmpty) p+='|ref='+Uri.encodeComponent(note); setState(()=>qrPayload=p); }

  Future<void> _sonicIssue() async { setState(()=>sonicOut='...'); try{ final uri=Uri.parse('${widget.baseUrl}/payments/sonic/issue'); final v = double.tryParse(sonicAmtCtrl.text.trim().replaceAll(',', '.'))??0; final body=jsonEncode({'from_wallet_id': myWallet, 'amount': double.parse(v.toStringAsFixed(2))}); final headers=await _hdrPRC(json:true); final r=await http.post(uri, headers: headers, body: body); sonicOut='${r.statusCode}: ${r.body}'; try{ final j=jsonDecode(r.body); final tok=j['token']??''; sonicPayload= tok is String && tok.startsWith('SONIC|')? tok : 'SONIC|token='+tok.toString(); }catch(_){ } if(r.statusCode>=500){ await OfflineQueue.enqueue(OfflineTask(id: 'sonic-issue-${DateTime.now().millisecondsSinceEpoch}', method:'POST', url: uri.toString(), headers: headers, body: body, tag:'payments_sonic', createdAt: DateTime.now().millisecondsSinceEpoch)); } }catch(_){ final uri=Uri.parse('${widget.baseUrl}/payments/sonic/issue'); final v = double.tryParse(sonicAmtCtrl.text.trim().replaceAll(',', '.'))??0; final body=jsonEncode({'from_wallet_id': myWallet, 'amount': double.parse(v.toStringAsFixed(2))}); final headers=await _hdrPRC(json:true); await OfflineQueue.enqueue(OfflineTask(id: 'sonic-issue-${DateTime.now().millisecondsSinceEpoch}', method:'POST', url: uri.toString(), headers: headers, body: body, tag:'payments_sonic', createdAt: DateTime.now().millisecondsSinceEpoch)); sonicOut='Queued (offline)'; } if(mounted) setState((){}); }
  Future<void> _sonicRedeem() async { setState(()=>sonicOut='...'); try{ final token = sonicPayload.startsWith('SONIC|')? ((){final m=<String,String>{}; for(final p in sonicPayload.split('|').skip(1)){ final kv=p.split('='); if(kv.length==2) m[kv[0]]=kv[1]; } return m['token']??sonicPayload; }()) : sonicTokenCtrl.text.trim(); final uri=Uri.parse('${widget.baseUrl}/payments/sonic/redeem'); final headers=await _hdrPRC(json:true); final body=jsonEncode({'token': token}); final r=await http.post(uri, headers: headers, body: body); sonicOut='${r.statusCode}: ${r.body}'; if(r.statusCode>=500){ await OfflineQueue.enqueue(OfflineTask(id: 'sonic-redeem-${DateTime.now().millisecondsSinceEpoch}', method:'POST', url: uri.toString(), headers: headers, body: body, tag:'payments_sonic', createdAt: DateTime.now().millisecondsSinceEpoch)); } }catch(_){ final token = sonicPayload.startsWith('SONIC|')? ((){final m=<String,String>{}; for(final p in sonicPayload.split('|').skip(1)){ final kv=p.split('='); if(kv.length==2) m[kv[0]]=kv[1]; } return m['token']??sonicPayload; }()) : sonicTokenCtrl.text.trim(); final uri=Uri.parse('${widget.baseUrl}/payments/sonic/redeem'); final headers=await _hdrPRC(json:true); final body=jsonEncode({'token': token}); await OfflineQueue.enqueue(OfflineTask(id: 'sonic-redeem-${DateTime.now().millisecondsSinceEpoch}', method:'POST', url: uri.toString(), headers: headers, body: body, tag:'payments_sonic', createdAt: DateTime.now().millisecondsSinceEpoch)); sonicOut='Queued (offline)'; } if(mounted) setState((){}); }

  @override Widget build(BuildContext context){
    final l = L10n.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children:[
        _walletHero(),
        const SizedBox(height:12),
        Text(
          l.payRequestTitle,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height:8),
        Row(
          children:[
            Expanded(
              child: Text(
                '${l.walletLabel}: ${myWallet.isEmpty ? l.walletNotSetShort : myWallet}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height:8),
        Row(
          children:[
            Expanded(
              child: TextField(
                controller: amtCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l.payRequestAmountLabel),
              ),
            ),
            const SizedBox(width:8),
            Expanded(
              child: TextField(
                controller: noteCtrl,
                decoration: InputDecoration(labelText: l.payRequestNoteLabel),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top:6, bottom:2),
          child: Builder(
            builder: (_){
              final a=_parseMajor(amtCtrl.text.trim());
              final s=a>0? '${l.payRequestPreviewPrefix}${a.toStringAsFixed(2)} ${_curSym}' : '';
              return Text(s, style: const TextStyle(fontSize: 12, color: Colors.white70));
            },
          ),
        ),
        const SizedBox(height:8),
        PayActionButton(
          icon: Icons.qr_code_2,
          label: l.payRequestQrLabel,
          onTap: _makeMyQR,
        ),
        if(qrPayload.isNotEmpty)
          Center(
            child: Column(
              children:[
                const SizedBox(height:8),
                Text(qrPayload, textAlign: TextAlign.center),
                const SizedBox(height:8),
                QrImageView(data: qrPayload, size: 220),
                const SizedBox(height:8),
                PayActionButton(
                  icon: Icons.ios_share,
                  label: l.payShareLinkLabel,
                  onTap: (){
                    try{
                      Clipboard.setData(ClipboardData(text: qrPayload));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l.copiedLabel)),
                      );
                    }catch(_){ }
                  },
                ),
              ],
            ),
          ),
        const Divider(height:24),
        ExpansionTile(
          title: Text(l.sonicSectionTitle),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:[
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: sonicAmtCtrl,
                    decoration: InputDecoration(labelText: l.sonicAmountLabel),
                  ),
                ),
                PayActionButton(
                  label: l.sonicIssueLabel,
                  onTap: _sonicIssue,
                ),
              ],
            ),
            const SizedBox(height:8),
            if(sonicPayload.isNotEmpty)
              Center(
                child: Column(
                  children:[
                    Text(sonicPayload),
                    const SizedBox(height:8),
                    QrImageView(data: sonicPayload, size: 200),
                  ],
                ),
              ),
            const SizedBox(height:8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:[
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: sonicTokenCtrl,
                    decoration: InputDecoration(labelText: l.sonicTokenLabel),
                  ),
                ),
                PayActionButton(
                  label: l.sonicRedeemLabel,
                  onTap: _sonicRedeem,
                ),
              ],
            ),
            const SizedBox(height:8),
            SelectableText(sonicOut.isEmpty ? '' : sonicOut),
          ],
        ),
      ],
    );
  }

  Widget _walletHero(){
    final bal=_balanceCents;
    final l = L10n.of(context);
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Row(
        children:[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.account_balance_wallet_outlined, size: 28),
          ),
          const SizedBox(width:12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:[
                Text(l.walletLabel),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        myWallet.isEmpty ? l.walletNotSetShort : myWallet,
                        maxLines:1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      tooltip: l.isArabic ? 'نسخ رقم المحفظة' : 'Copy wallet ID',
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: myWallet.isEmpty ? null : (){
                        try{
                          Clipboard.setData(ClipboardData(text: myWallet));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l.copiedLabel)),
                          );
                        }catch(_){ }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children:[
              Text(l.balanceLabel),
              Text(
                bal==null? (_loadingWallet? '…' : '—') : '${fmtCents(bal)} ${_curSym}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<String?> _getCookiePRC() async { final sp=await SharedPreferences.getInstance(); return sp.getString('sa_cookie'); }
Future<Map<String,String>> _hdrPRC({bool json=false}) async { final h=<String,String>{}; if(json) h['content-type']='application/json'; final c=await _getCookiePRC(); if(c!=null&&c.isNotEmpty) h['Cookie']=c; return h; }
