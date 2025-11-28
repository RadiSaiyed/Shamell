import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../format.dart' show fmtCents;
import '../design_tokens.dart';

// Simple cookie header for BFF calls used by Taxi pages
Future<String?> taxiGetCookie() async { final sp=await SharedPreferences.getInstance(); return sp.getString('sa_cookie'); }
Future<Map<String,String>> hdrTaxi({bool json=false}) async { final h=<String,String>{}; if(json) h['content-type']='application/json'; final c=await taxiGetCookie(); if(c!=null&&c.isNotEmpty) h['Cookie']=c; return h; }

// Parse fare options from common response shapes
List<Map<String,dynamic>> parseTaxiFareOptions(dynamic j){
  final opts=<Map<String,dynamic>>[];
  try{
    if(j is Map && j['options'] is List){
      for(final o in (j['options'] as List)){
        if(o is Map){
          final name=(o['type']??o['kind']??'').toString();
          final cents=(o['price_cents']??o['fare_cents']??0) as int;
          if(name.isNotEmpty && cents>0) opts.add({'name': name.toUpperCase(), 'cents': cents});
        }
      }
    }
    if(opts.isEmpty && j is Map && j.containsKey('price_cents')){
      opts.add({'name':'STANDARD', 'cents': (j['price_cents']??0) as int});
    }
    // Fallback for direct Taxi API quote with fare_cents
    if(opts.isEmpty && j is Map && j.containsKey('fare_cents')){
      opts.add({'name':'STANDARD', 'cents': (j['fare_cents']??0) as int});
    }
    if(opts.isEmpty && j is Map){
      final vip=j['vip_price_cents']; final van=j['van_price_cents'];
      if(vip is int && vip>0) opts.add({'name':'VIP','cents':vip});
      if(van is int && van>0) opts.add({'name':'VAN','cents':van});
    }
  }catch(_){ }
  return opts;
}

class TaxiFareChips extends StatelessWidget{
  final List<Map<String,dynamic>> options; final String? selected; final void Function(String name) onSelected;
  const TaxiFareChips({super.key, required this.options, required this.selected, required this.onSelected});
  Color _badge(String name){
    switch(name.toUpperCase()){
      case 'VIP':
        return Tokens.colorTaxi.withValues(alpha: .95);
      case 'VAN':
        return Tokens.colorTaxi.withValues(alpha: .70);
      default:
        return Tokens.colorTaxi;
    }
  }
  @override Widget build(BuildContext context){
    return SizedBox(
      height: 48,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: options.map((o){
            final name=(o['name']??'').toString();
            final cents=(o['cents']??0) as int;
            final sel = (selected==name);
            return Padding(
              padding: const EdgeInsets.only(right:8),
              child: InkWell(
                onTap: ()=> onSelected(name),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: sel? _badge(name) : Colors.black.withValues(alpha: .30), width: sel? 2 : 1.2),
                    color: Colors.white.withValues(alpha: .06),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children:[
                      Container(width:8, height:8, decoration: BoxDecoration(color: _badge(name), shape: BoxShape.circle)),
                      const SizedBox(width:8),
                      Text('$name: ${fmtCents(cents)} SYP', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class TaxiActionButton extends StatelessWidget{
  final IconData? icon; final String label; final VoidCallback onTap; final EdgeInsets padding; final double radius; final Color? tint;
  const TaxiActionButton({super.key, this.icon, required this.label, required this.onTap, this.padding=const EdgeInsets.symmetric(horizontal: 18, vertical: 18), this.radius=12, this.tint});
  @override Widget build(BuildContext context){
    final theme = Theme.of(context);
    final Color bg = theme.colorScheme.surface;
    final Color border = theme.dividerColor;
    final Color fg = theme.colorScheme.onSurface;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children:[
        if(icon!=null) Icon(icon, size:18, color: fg.withValues(alpha: .90)),
        if(icon!=null) const SizedBox(width:8),
        Text(
          label,
          style: TextStyle(
            color: fg,
            fontWeight: FontWeight.w700,
            fontSize: 16,
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

class TaxiBG extends StatelessWidget{
  const TaxiBG({super.key});
  @override
  Widget build(BuildContext context){
    // Match global AppBG: simple, solid surface
    final theme = Theme.of(context);
    return Container(color: theme.colorScheme.surface);
  }
}

class TaxiSlideButton extends StatefulWidget{
  final String label; final VoidCallback onConfirm; final bool disabled; final double height; final double radius; final Color? tint;
  const TaxiSlideButton({super.key, required this.label, required this.onConfirm, this.disabled=false, this.height=56, this.radius=16, this.tint});
  @override State<TaxiSlideButton> createState()=>_TaxiSlideButtonState();
}
class _TaxiSlideButtonState extends State<TaxiSlideButton> with SingleTickerProviderStateMixin{
  double _dragX = 0; double _max = 0; bool _confirming=false; bool _showCheck=false; late AnimationController _ctrl; late Animation<double> _anim;
  @override void initState(){ super.initState(); _ctrl=AnimationController(vsync:this, duration: const Duration(milliseconds: 220)); _anim=CurvedAnimation(parent:_ctrl, curve: Curves.easeOutCubic)..addListener(()=> setState(()=> _dragX = _anim.value)); }
  @override void dispose(){ _ctrl.dispose(); super.dispose(); }
  void _animateTo(double v){ _ctrl.stop(); _ctrl.reset(); final start=_dragX; _anim = _ctrl.drive(Tween<double>(begin:start, end:v).chain(CurveTween(curve: Curves.easeOutCubic))); _ctrl.forward(); }
  void _onUp(){
    if(_max<=0){ _animateTo(0); return; }
    final th = _max * 0.62;
    if(_dragX>=th && !_confirming){
      _confirming=true; _showCheck=true; _animateTo(_max);
      Future.delayed(const Duration(milliseconds: 120), () async {
        try{ await HapticFeedback.lightImpact(); }catch(_){ }
        widget.onConfirm();
        await Future.delayed(const Duration(milliseconds: 360));
        if(mounted){ setState(()=> _showCheck=false); }
        _confirming=false; _animateTo(0);
      });
    } else {
      _animateTo(0);
    }
  }
  @override Widget build(BuildContext context){
    final h = widget.height; final knob = h-10; final tint=(widget.tint ?? const Color(0xFF6B8E23));
    final baseColor = tint.withValues(alpha: .16);
    final strongA = tint.withValues(alpha: .60);
    final strongB = tint.withValues(alpha: .38);
    final labelStyle = const TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 16);
    final content = LayoutBuilder(builder: (ctx, c){
      final w = c.maxWidth; _max = (w - knob - 8).clamp(0, w);
      final progress = (_max<=0)? 0.0 : (_dragX/_max).clamp(0.0, 1.0);
      return Stack(children:[
        // Track
        Container(
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            color: baseColor,
            border: Border.all(color: Colors.black.withValues(alpha: .14), width: 1),
            boxShadow: [ BoxShadow(color: Colors.black.withValues(alpha: .18), blurRadius: 16, offset: const Offset(0,10)) ],
          ),
        ),
        // Progress fill under the knob
        Positioned(left: 4, top: 4, bottom: 4, right: null, child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          width: 4 + _dragX + knob,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius-4),
            gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [strongA, strongB]),
          ),
        )),
        // Subtle slide hint chevrons (fade out as progress increases)
        Positioned.fill(child: IgnorePointer(child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: (1.0 - (progress*0.85)).clamp(0.0, 1.0),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
            Icon(Icons.chevron_right, size: 18, color: Colors.black54),
            SizedBox(width: 2),
            Icon(Icons.chevron_right, size: 18, color: Colors.black45),
            SizedBox(width: 2),
            Icon(Icons.chevron_right, size: 18, color: Colors.black38),
          ]),
        ))),
        // Center label (single line, ellipsis, constrained to avoid overlap with knob)
        Positioned.fill(child: Center(child: ConstrainedBox(
          constraints: BoxConstraints(
            // leave room for knob + margins
            maxWidth: (w - (knob + 28)).clamp(60.0, w),
          ),
          child: Text(
            widget.label,
            style: labelStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            textAlign: TextAlign.center,
          ),
        ))),
        // Knob
        Positioned(left: 4+_dragX, top: 4, bottom: 4, child: GestureDetector(
          onHorizontalDragUpdate: widget.disabled? null : (d){ setState(()=> _dragX = (_dragX + d.delta.dx).clamp(0, _max)); },
          onHorizontalDragEnd: widget.disabled? null : (_){ _onUp(); },
          onTapUp: widget.disabled? null : (_){ _onUp(); },
          child: Container(
            width: knob, height: knob,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius-2),
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white, Color(0xFFF6F6F6)]),
              boxShadow: [ BoxShadow(color: Colors.black.withValues(alpha: .20), blurRadius: 16, offset: const Offset(0,10)) ],
              border: Border.all(color: Colors.black.withValues(alpha: .10), width: 1),
            ),
            child: AnimatedSwitcher(duration: const Duration(milliseconds: 160), transitionBuilder: (c, a)=> ScaleTransition(scale: a, child: c), child:
              _showCheck? Icon(Icons.check_rounded, key: const ValueKey('ok'), color: Colors.black.withValues(alpha: .85)) :
                          Icon(Icons.keyboard_double_arrow_right, key: const ValueKey('arr'), color: Colors.black.withValues(alpha: .80))
            ),
          ),
        )),
      ]);
    });
    final body = ClipRRect(borderRadius: BorderRadius.circular(widget.radius), child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12), child: content));
    final full = SizedBox(width: double.infinity, child: body);
    if(widget.disabled){ return Opacity(opacity: .55, child: IgnorePointer(child: full)); }
    return full;
  }
}
