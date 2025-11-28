import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'glass.dart';
import 'payments_utils.dart';
import 'offline_queue.dart';
import 'format.dart' show fmtCents;
import 'contact_picker.dart'; // for contact picker integration
import 'l10n.dart';
import 'perf.dart';
import 'status_banner.dart';
import 'ui_kit.dart';

class FavoritesDropdown extends StatelessWidget {
  final List<Map<String,dynamic>> favorites;
  final void Function(String value) onSelected;
  const FavoritesDropdown({super.key, required this.favorites, required this.onSelected});
  @override
  Widget build(BuildContext context){
    if(favorites.isEmpty) return const SizedBox.shrink();
    final l = L10n.of(context);
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(labelText: l.payFavoritesLabel),
      isExpanded: true,
      items: favorites.map((f){ final alias=(f['alias']??'').toString(); final id=(f['favorite_wallet_id']??'').toString(); final label= alias.isNotEmpty? '$alias  ·  $id' : id; return DropdownMenuItem(value: id, child: Text(label, overflow: TextOverflow.ellipsis)); }).toList(),
      onChanged: (v){ if(v!=null) onSelected(v); },
    );
  }
}

class QuickAmountChips extends StatelessWidget{
  final List<int> presets;
  final VoidCallback onClear;
  final void Function(int add) onAdd; // add in whole SYP
  const QuickAmountChips({super.key, this.presets=const [5,10,25,50,100], required this.onClear, required this.onAdd});
  @override Widget build(BuildContext context){
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for(final v in presets) ActionChip(label: Text('+$v'), onPressed: ()=> onAdd(v)),
      ActionChip(label: Text(L10n.of(context).clearLabel), onPressed: onClear),
    ]);
  }
}

class ContactShortlistChips extends StatelessWidget{
  final List<Map<String,String>> shortlist; final void Function(String phone) onTap;
  const ContactShortlistChips({required this.shortlist, required this.onTap, super.key});
  @override Widget build(BuildContext context){
    if(shortlist.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing:10,
      runSpacing:6,
      children: shortlist.map((m){
        final name=m['name']??'';
        final phone=m['phone']??'';
        return ActionChip(
          avatar: CircleAvatar(child: Text(name.isNotEmpty? name[0]:'?')),
          label: Text('$name  ·  $phone', overflow: TextOverflow.ellipsis),
          onPressed: ()=> onTap(phone),
        );
      }).toList(),
    );
  }
}

class PaymentSendTab extends StatefulWidget{
  final String baseUrl; final String fromWalletId; final String deviceId;
  const PaymentSendTab({super.key, required this.baseUrl, required this.fromWalletId, required this.deviceId});
  @override State<PaymentSendTab> createState()=>_PaymentSendTabState();
}

class _PaymentSendTabState extends State<PaymentSendTab>{
  final toCtrl = TextEditingController();
  final amtCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  String myWallet='';
  int? _balanceCents; bool _loadingWallet=false;
  String _curSym='SYP';
  List<String> recents = [];
  List<Map<String,dynamic>> favorites = [];
  List<Map<String,String>> shortlist = [];
  String _toResolvedHint=''; String? _toResolvedWalletId;
  int _sendCooldownSec=0; Timer? _cooldownTimer;
  String _bannerMsg = '';
  StatusKind _bannerKind = StatusKind.info;

  Timer? _resolveTimer;

  @override void initState(){ super.initState(); _init(); }
  Future<void> _init() async {
    final sp=await SharedPreferences.getInstance();
    myWallet = sp.getString('wallet_id') ?? widget.fromWalletId;
    recents = sp.getStringList('pay_recents') ?? [];
    final cs = sp.getString('currency_symbol'); if(cs!=null && cs.isNotEmpty){ _curSym=cs; }
    setState((){});
    await _loadFavorites();
    await _loadWallet();
    _attachResolver();
    _loadShortlist();
  }

  @override void dispose(){ _cooldownTimer?.cancel(); _resolveTimer?.cancel(); super.dispose(); }

  void _attachResolver(){
    toCtrl.removeListener(_onResolveChanged);
    toCtrl.addListener(_onResolveChanged);
  }

  void _onResolveChanged(){
    _resolveTimer?.cancel();
    _resolveTimer = Timer(const Duration(milliseconds: 450), () {
      if(!mounted) return;
      _resolveTarget();
    });
  }

  Future<void> _resolveTarget() async {
    final v=toCtrl.text.trim(); _toResolvedHint=''; _toResolvedWalletId=null; setState((){});
    try{
      if(v.startsWith('+') || RegExp(r'^\d{6,}$').hasMatch(v)){
        final r = await http.get(Uri.parse('${widget.baseUrl}/payments/resolve/phone/'+Uri.encodeComponent(v)), headers: await _hdrPS());
        if(r.statusCode==200){ final j=jsonDecode(r.body); _toResolvedWalletId=(j['wallet_id']??'').toString(); _toResolvedHint='Wallet: ${_toResolvedWalletId}'; } else { _toResolvedHint='Number not recognized'; }
        setState((){});
      } else if(v.startsWith('@')){
        final r = await http.get(Uri.parse('${widget.baseUrl}/payments/alias/resolve/'+Uri.encodeComponent(v)), headers: await _hdrPS());
        if(r.statusCode==200){ final j=jsonDecode(r.body); _toResolvedWalletId=(j['wallet_id']??'').toString(); _toResolvedHint=_toResolvedWalletId!=null&&_toResolvedWalletId!.isNotEmpty? 'Alias → ${_toResolvedWalletId}' : 'Unknown alias'; } else { _toResolvedHint='Unknown alias'; }
        setState((){});
      }
    }catch(_){ }
  }

  Future<void> _loadWallet() async {
    if(myWallet.isEmpty) return; setState(()=>_loadingWallet=true);
    try{ final r=await http.get(Uri.parse('${widget.baseUrl}/payments/wallets/'+Uri.encodeComponent(myWallet)), headers: await _hdrPS()); if(r.statusCode==200){ final j=jsonDecode(r.body); _balanceCents=(j['balance_cents']??0) as int; } }catch(_){ }
    if(mounted) setState(()=>_loadingWallet=false);
  }
  Future<void> _loadFavorites() async { if(myWallet.isEmpty) return; try{ final r=await http.get(Uri.parse('${widget.baseUrl}/payments/favorites?owner_wallet_id='+Uri.encodeComponent(myWallet)), headers: await _hdrPS()); if(r.statusCode==200){ favorites=(jsonDecode(r.body) as List).cast<Map<String,dynamic>>(); } }catch(_){ } if(mounted) setState((){}); }
  Future<void> _saveRecent(String w) async { if(w.isEmpty) return; final sp=await SharedPreferences.getInstance(); final cur=sp.getStringList('pay_recents')??[]; cur.removeWhere((x)=>x==w); cur.insert(0,w); while(cur.length>5) cur.removeLast(); await sp.setStringList('pay_recents', cur); setState(()=>recents=cur); }
  Future<void> _loadShortlist() async {
    try{ final sp=await SharedPreferences.getInstance(); final cached=sp.getStringList('contact_shortlist'); if(cached!=null && cached.isNotEmpty){ shortlist=cached.map((s){ try{ final m=jsonDecode(s); return {'name':(m['name']??'').toString(),'phone':(m['phone']??'').toString()}; }catch(_){ return {'name':'','phone':s}; } }).toList(); setState((){}); } }catch(_){ }
  }

  Future<void> _addToShortlist(String phone) async {
    try{
      final sp=await SharedPreferences.getInstance();
      final List<String> cur = sp.getStringList('contact_shortlist') ?? [];
      // store as plain phone string for compatibility, newest first
      cur.removeWhere((s)=> s==phone || s.contains('"phone":"$phone"'));
      cur.insert(0, phone);
      while(cur.length>8) cur.removeLast();
      await sp.setStringList('contact_shortlist', cur);
      _loadShortlist();
    }catch(_){ }
  }

  void _openContactPicker(){
    Navigator.of(context).push(MaterialPageRoute(builder: (_)=> ContactPickerPage(onPicked: (phone){
      final clean = phone.replaceAll(' ', '');
      toCtrl.text = clean; setState((){});
      _addToShortlist(clean);
    })));
  }

  void _startCooldown(int secs){ if(secs<=0) return; _cooldownTimer?.cancel(); setState(()=>_sendCooldownSec=secs); _cooldownTimer=Timer.periodic(const Duration(seconds:1), (t){ if(!mounted){t.cancel(); return;} if(_sendCooldownSec<=1){ t.cancel(); setState(()=>_sendCooldownSec=0);} else setState(()=>_sendCooldownSec-=1); }); }

  double _parseMajor(String s){ try{ final t=s.trim().replaceAll(',', '.'); return double.parse(t); }catch(_){ return 0; } }

  Future<void> _sendManual() async {
    final l = L10n.of(context);
    String to = toCtrl.text.trim();
    final amountMajor = _parseMajor(amtCtrl.text.trim());
    if(to.isEmpty || amountMajor<=0){
      setState(() {
        _bannerKind = StatusKind.error;
        _bannerMsg = l.payCheckInputs;
      });
      return;
    }
    final uri = Uri.parse('${widget.baseUrl}/payments/transfer'); final ikey='tw-${DateTime.now().millisecondsSinceEpoch}';
    final payload = <String,dynamic>{ 'from_wallet_id': myWallet, 'amount': double.parse(amountMajor.toStringAsFixed(2)), if(noteCtrl.text.trim().isNotEmpty) 'reference': noteCtrl.text.trim(), ...buildTransferTarget(to, resolvedWalletId: _toResolvedWalletId) };
    final t0 = DateTime.now().millisecondsSinceEpoch;
    try{
      final headers=(await _hdrPS(json:true))..addAll({'Idempotency-Key': ikey, 'X-Device-ID': widget.deviceId});
      final resp=await http.post(uri, headers: headers, body: jsonEncode(payload));
      if(resp.statusCode==429){
        try{
          final j=jsonDecode(resp.body);
          final ms=(j['retry_after_ms']??0) as int;
          final sec=(ms/1000).ceil();
          _startCooldown(sec>0?sec:15);
        }catch(_){
          _startCooldown(15);
        }
      }
      if(resp.statusCode>=500){
        Perf.action('pay_send_queued');
        await OfflineQueue.enqueue(OfflineTask(id: ikey, method:'POST', url: uri.toString(), headers: headers, body: jsonEncode(payload), tag:'payments_transfer', createdAt: DateTime.now().millisecondsSinceEpoch));
        final msg = l.payOfflineQueued;
        setState(() {
          _bannerKind = StatusKind.warning;
          _bannerMsg = msg;
        });
      }
      if(resp.statusCode>=200 && resp.statusCode<300){
        Perf.action('pay_send_ok');
        final dt = DateTime.now().millisecondsSinceEpoch - t0;
        Perf.sample('pay_send_ms', dt);
        try{ HapticFeedback.mediumImpact(); }catch(_){ }
        await _loadWallet(); await _saveRecent(to);
        final msg = l.isArabic
            ? 'تم إرسال ${amountMajor.toStringAsFixed(2)} $_curSym إلى $to'
            : 'Sent ${amountMajor.toStringAsFixed(2)} $_curSym to $to';
        setState(() {
          _bannerKind = StatusKind.success;
          _bannerMsg = msg;
        });
      }else if(resp.statusCode>=400){
        Perf.action('pay_send_fail');
        final dt = DateTime.now().millisecondsSinceEpoch - t0;
        Perf.sample('pay_send_ms', dt);
        String msg = l.paySendFailed;
        try{
          final ct = resp.headers['content-type'] ?? '';
          if(ct.startsWith('application/json')){
            final body = jsonDecode(resp.body);
            final detail = body is Map<String,dynamic> ? body['detail'] : null;
            final detailStr = detail == null ? '' : detail.toString();
            if(detailStr.contains('amount exceeds guardrail')){
              msg = l.payGuardrailAmount;
            }else if(detailStr.contains('velocity guardrail (wallet)')){
              msg = l.payGuardrailVelocityWallet;
            }else if(detailStr.contains('velocity guardrail (device)')){
              msg = l.payGuardrailVelocityDevice;
            }
          }
        }catch(_){ /* best-effort only */ }
        setState(() {
          _bannerKind = StatusKind.error;
          _bannerMsg = msg;
        });
      }
    }catch(_){
      final headers=(await _hdrPS(json:true))..addAll({'Idempotency-Key': ikey, 'X-Device-ID': widget.deviceId});
      await OfflineQueue.enqueue(OfflineTask(id: ikey, method:'POST', url: uri.toString(), headers: headers, body: jsonEncode(payload), tag:'payments_transfer', createdAt: DateTime.now().millisecondsSinceEpoch));
      Perf.action('pay_send_queued');
      final msg =
          '${l.payOfflineSavedPrefix}: $to, ${amountMajor.toStringAsFixed(2)} $_curSym';
      setState(() {
        _bannerKind = StatusKind.warning;
        _bannerMsg = msg;
      });
    }
  }

  Future<void> _reviewAndSend() async {
    final l = L10n.of(context);
    final to=toCtrl.text.trim(); final amountMajor=_parseMajor(amtCtrl.text.trim()); if(to.isEmpty || amountMajor<=0){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.payCheckInputs))); return; }
    final fmt='${amountMajor.toStringAsFixed(2)} $_curSym'; final hint=_toResolvedHint; final ok=await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_){ return buildReviewSheet(context: context, to: to, hint: hint, amountFmt: fmt, note: noteCtrl.text.trim()); });
    if(ok==true){ await _sendManual(); }
  }

  @override Widget build(BuildContext context){
    final l = L10n.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if(_bannerMsg.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: StatusBanner(kind: _bannerKind, message: _bannerMsg, dense: true),
          ),
        FormSection(
          title: l.isArabic ? 'محفظتك' : 'Wallet & balance',
          children: [
            _walletHero(),
          ],
        ),
        FormSection(
          title: l.isArabic ? 'المستلم والمبلغ' : 'Recipient & amount',
          children: [
            if(favorites.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom:8),
                child: FavoritesDropdown(
                  favorites: favorites,
                  onSelected: (v){ toCtrl.text=v; setState((){}); },
                ),
              ),
            Row(children:[
              Expanded(
                child: TextField(
                  controller: toCtrl,
                  decoration: InputDecoration(labelText: l.payRecipientLabel),
                ),
              ),
              const SizedBox(width:8),
              Expanded(
                child: TextField(
                  controller: amtCtrl,
                  decoration: InputDecoration(labelText: l.payAmountLabel),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
            ]),
            const SizedBox(height:6),
            QuickAmountChips(
              onClear: (){ amtCtrl.text=''; setState((){}); },
              onAdd: (v){
                final cur=_parseMajor(amtCtrl.text.trim());
                amtCtrl.text=(cur+v).toStringAsFixed(2);
                setState((){});
                try{ HapticFeedback.selectionClick(); }catch(_){ }
              },
            ),
            Padding(
              padding: const EdgeInsets.only(top:6, bottom:2),
              child: Builder(
                builder: (_){
                  final c=_parseMajor(amtCtrl.text.trim());
                  final s=c>0? '${c.toStringAsFixed(2)} ${_curSym}' : '';
                  return Text(
                    s,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: .70),
                    ),
                  );
                },
              ),
            ),
            if(_toResolvedHint.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top:6),
                child: Text(
                  _toResolvedHint,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: .60),
                  ),
                ),
              ),
          ],
        ),
        FormSection(
          title: l.isArabic ? 'تفاصيل إضافية' : 'Details & contacts',
          children: [
            TextField(
              controller: noteCtrl,
              decoration: InputDecoration(
                labelText: l.payNoteLabel,
              ),
            ),
            const SizedBox(height:8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Semantics(
                  button: true,
                  label: l.isArabic ? 'إرسال دفعة' : 'Send payment',
                  child: SendButton(
                    cooldownSec: _sendCooldownSec,
                    onTap: _reviewAndSend,
                  ),
                ),
                Semantics(
                  button: true,
                  label: l.isArabic ? 'فتح قائمة جهات الاتصال' : 'Open contacts',
                  child: PayActionButton(
                    icon: Icons.contacts_outlined,
                    label: l.payContactsLabel,
                    onTap: _openContactPicker,
                  ),
                ),
              ],
            ),
            if(shortlist.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top:12),
                child: ContactShortlistChips(
                  shortlist: shortlist,
                  onTap: (phone){ toCtrl.text=phone; setState((){}); },
                ),
              ),
            if(favorites.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top:12),
                child: Wrap(
                  spacing:10,
                  runSpacing:6,
                  children: favorites.map((f){
                    final label=(f['alias']??'').toString().isNotEmpty
                        ? (f['alias'] as String)
                        : (f['favorite_wallet_id'] as String);
                    return ActionChip(
                      avatar: CircleAvatar(child: Text(label.characters.first)),
                      label: Text(label, overflow: TextOverflow.ellipsis),
                      onPressed: (){
                        toCtrl.text=label;
                        setState((){});
                      },
                    );
                  }).toList(),
                ),
              ),
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
      child: Row(children:[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: .90),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.account_balance_wallet_outlined, size: 28),
        ),
        const SizedBox(width:12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children:[
            Text(l.homeWallet, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    myWallet.isEmpty ? l.notSet : myWallet,
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
        )),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children:[
            Text(l.isArabic ? 'الرصيد' : 'Balance'),
            Text(
              bal==null? (_loadingWallet? '…' : '—') : '${fmtCents(bal)} ${_curSym}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ],
        ),
      ]),
    );
  }
}

class SendButton extends StatelessWidget{
  final int cooldownSec; final VoidCallback onTap;
  const SendButton({super.key, required this.cooldownSec, required this.onTap});
  @override Widget build(BuildContext context){
    final l = L10n.of(context);
    final label = cooldownSec>0
        ? l.paySendAfter(cooldownSec)
        : l.sendLabel;
    return Opacity(
      opacity: cooldownSec>0? .55:1,
      child: PrimaryButton(
        icon: Icons.send_outlined,
        label: label,
        expanded: true,
        onPressed: (){
          if(cooldownSec>0){
            final msg = l.payWaitSeconds(cooldownSec);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
          } else {
            onTap();
          }
        },
      ),
    );
  }
}

Widget buildReviewSheet({required BuildContext context, required String to, required String hint, required String amountFmt, String? note}){
  final l = L10n.of(context);
  return Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom), child:
    Padding(padding: const EdgeInsets.all(16), child:
      GlassPanel(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children:[
        Row(children:[ const Icon(Icons.person_outline), const SizedBox(width:8), Expanded(child: Text(to, style: const TextStyle(fontWeight: FontWeight.w700))), if(hint.isNotEmpty) Text(hint, style: const TextStyle(color: Colors.white70)) ]),
        const SizedBox(height:12),
        Center(child: Text(amountFmt, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800))),
        if((note??'').trim().isNotEmpty) Padding(padding: const EdgeInsets.only(top:8), child: Center(child: Text(note!.trim(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.black)))),
        const SizedBox(height:16),
        Row(children:[
          Expanded(
            child: PrimaryButton(
              label: l.isArabic ? 'إلغاء' : 'Cancel',
              onPressed: ()=> Navigator.pop(context,false),
            ),
          ),
          const SizedBox(width:8),
          Expanded(
            child: PrimaryButton(
              label: l.isArabic ? 'إرسال' : 'Send',
              onPressed: ()=> Navigator.pop(context,true),
            ),
          ),
        ]),
      ])),
    ),
  );
}

Future<String?> _getCookiePS() async { final sp=await SharedPreferences.getInstance(); return sp.getString('sa_cookie'); }
Future<Map<String,String>> _hdrPS({bool json=false}) async { final h=<String,String>{}; if(json) h['content-type']='application/json'; final c=await _getCookiePS(); if(c!=null&&c.isNotEmpty) h['Cookie']=c; return h; }

class PayActionButton extends StatelessWidget{
  final IconData? icon; final String label; final VoidCallback onTap; final EdgeInsets padding; final double radius; final Color? tint;
  const PayActionButton({super.key, this.icon, required this.label, required this.onTap, this.padding=const EdgeInsets.symmetric(horizontal: 18, vertical: 16), this.radius=10, this.tint});
  @override Widget build(BuildContext context){
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color base = tint ?? theme.colorScheme.primary;
    final Color bg = isDark
        ? base.withValues(alpha: .18)
        : base.withValues(alpha: .12);
    final Color border = isDark
        ? Colors.white.withValues(alpha: .18)
        : Colors.black.withValues(alpha: .10);
    final Color textColor = base;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children:[
        if(icon!=null) Icon(icon, size:18, color: textColor.withValues(alpha: .95)),
        if(icon!=null) const SizedBox(width:8),
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            softWrap: true,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Padding(
          padding: padding,
          child: Center(child: content),
        ),
      ),
    );
  }
}
