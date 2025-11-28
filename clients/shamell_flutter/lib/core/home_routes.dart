import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/physics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'design_tokens.dart';
import 'skeleton.dart';
import 'perf.dart';
import 'payments_send.dart' show PayActionButton;
import 'l10n.dart';

class HomeActions {
  final VoidCallback onScanPay;
  final VoidCallback onTopup;
  final VoidCallback onSonic;
  final VoidCallback onP2P;
  final VoidCallback onMobility;
  // Taxi roles (integrated into rotary wheel)
  final VoidCallback onTaxiRider;
  final VoidCallback onTaxiDriver;
  final VoidCallback onTaxiOperator;
  final VoidCallback onBusOperator;
  final VoidCallback onBusControl;
  final VoidCallback onOps; // Consolidated Ops hub
  final VoidCallback onFood;
  final VoidCallback onBills;
  final VoidCallback onWallet;
  final VoidCallback onHistory;
  final VoidCallback onStays;
  final VoidCallback onStaysHotel;
  // Additional modules on homescreen
  final VoidCallback onCarmarket;
  final VoidCallback onCarrental;
  final VoidCallback onRealestate;
  final VoidCallback onCourier;
  final VoidCallback onFreight;
  final VoidCallback onBus;
  final VoidCallback onChat;
  final VoidCallback onDoctors;
  final VoidCallback onFlights;
  final VoidCallback onJobs;
  final VoidCallback onAgriculture;
  final VoidCallback onLivestock;
  final VoidCallback onCommerce;
  final VoidCallback onMerchantPOS;
  final VoidCallback onVouchers;
  final VoidCallback onRequests;
  final VoidCallback onFoodOrders;
  final VoidCallback onBuildingMaterials;
  const HomeActions({
    required this.onScanPay,
    required this.onTopup,
    required this.onSonic,
    required this.onP2P,
    required this.onMobility,
    required this.onTaxiRider,
    required this.onTaxiDriver,
    required this.onTaxiOperator,
    required this.onBusOperator,
    required this.onBusControl,
    required this.onOps,
    required this.onFood,
    required this.onBills,
    required this.onWallet,
    required this.onHistory,
    required this.onStays,
    required this.onStaysHotel,
    required this.onCarmarket,
    required this.onCarrental,
    required this.onRealestate,
    required this.onCourier,
    required this.onFreight,
    required this.onBus,
    required this.onChat,
    required this.onDoctors,
    required this.onFlights,
    required this.onJobs,
    required this.onAgriculture,
    required this.onLivestock,
    required this.onCommerce,
    required this.onMerchantPOS,
    required this.onVouchers,
    required this.onRequests,
    required this.onFoodOrders,
    required this.onBuildingMaterials,
  });
}

class HomeRouteHub extends StatefulWidget {
  final HomeActions actions;
  final bool showOps;
  final bool showSuperadmin;
  final bool taxiOnly;
  const HomeRouteHub({super.key, required this.actions, this.showOps=true, this.showSuperadmin=false, this.taxiOnly=false});
  @override State<HomeRouteHub> createState()=>_HomeRouteHubState();
}

class _HomeRouteHubState extends State<HomeRouteHub> with TickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _ac;        // expand/collapse satellites
  late final AnimationController _spinAc;    // spin/snap controller (unbounded)

  // Rotary wheel state
  double _wheelAngle = 0;                    // radians, rotation offset
  int _wheelTick = 0;                        // current notch index for haptics
  double? _lastPointerAngle;                 // last pointer angle during drag
  VoidCallback? _spinListener;
  void Function(AnimationStatus)? _spinStatus;

  @override void initState(){
    super.initState();
    _ac = AnimationController(vsync: this, duration: Tokens.motionBase);
    _spinAc = AnimationController.unbounded(vsync: this);
  }
  @override void dispose(){ _ac.dispose(); _spinAc.dispose(); super.dispose(); }

  void _toggle() {
    setState(()=>_expanded = !_expanded);
    if(_expanded) { _ac.forward(); HapticFeedback.lightImpact(); } else { _ac.reverse(); }
  }

  @override
  Widget build(BuildContext context){
    final l = L10n.of(context);
    final size = MediaQuery.of(context).size;
    final hub = _ThumbHubButton(onTap: (){ Perf.tap('hub'); _toggle(); }, label: l.homeActions, icon: Icons.apps);

    // Satellite specs (icon, label, action) — include ops/superadmin hubs when allowed
    final specs = <_SatSpec>[
      _SatSpec(icon: Icons.local_taxi_outlined, label: l.homeTaxiRider, onTap: widget.actions.onTaxiRider),
      _SatSpec(icon: Icons.local_taxi, label: l.homeTaxiDriver, onTap: widget.actions.onTaxiDriver),
      if(!widget.taxiOnly) _SatSpec(icon: Icons.restaurant_outlined, label: l.homeFood, onTap: widget.actions.onFood),
      if(!widget.taxiOnly) _SatSpec(icon: Icons.hotel, label: l.homeStays, onTap: widget.actions.onStays),
      if(!widget.taxiOnly) _SatSpec(icon: Icons.receipt_long_outlined, label: l.homeBills, onTap: widget.actions.onBills),
      if(!widget.taxiOnly) _SatSpec(icon: Icons.swap_horiz_outlined, label: l.qaP2P, onTap: widget.actions.onP2P),
      if(!widget.taxiOnly) _SatSpec(icon: Icons.account_balance_wallet_outlined, label: l.qaTopup, onTap: widget.actions.onTopup),
      if(!widget.taxiOnly) _SatSpec(icon: Icons.construction_outlined, label: l.homeBuildingMaterials, onTap: widget.actions.onBuildingMaterials),
    ];
    if(widget.taxiOnly){
      // Insert Taxi Admin when taxi-only
      specs.insert(2, _SatSpec(icon: Icons.support_agent, label: 'Taxi Admin', onTap: widget.actions.onTaxiOperator));
      if(widget.showSuperadmin){
        specs.insert(3, _SatSpec(icon: Icons.security, label: 'Superadmin', onTap: widget.actions.onOps));
      }
    } else {
      if(widget.showOps){
        specs.insert(2, _SatSpec(icon: Icons.admin_panel_settings, label: 'Admin', onTap: widget.actions.onOps));
      }
      if(widget.showSuperadmin){
        specs.insert(3, _SatSpec(icon: Icons.security, label: 'Superadmin', onTap: widget.actions.onOps));
      }
    }
    final count = specs.length;
    final stepAngle = (2*pi)/count;
    int activeIndex = ((-_wheelAngle / stepAngle).round()) % count; if(activeIndex<0) activeIndex += count;

    final wheelTop = max(96.0, size.height * 0.18);
    return Stack(children: [
      Positioned.fill(child: _HeaderAndFeed(actions: widget.actions)),
      // Hub & satellites overlay near bottom center
      Positioned(
        left: 0, right: 0,
        top: wheelTop,
        child: SizedBox(
          height: 200,
          width: size.width,
          // Rotary wheel interaction zone
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (d){
              if(!_expanded){
                // Expand on first drag to reveal the wheel
                setState(()=>_expanded=true);
                _ac.forward();
                HapticFeedback.lightImpact();
              }
              final box = context.findRenderObject() as RenderBox?;
              if(box!=null){
                final local = box.globalToLocal(d.globalPosition);
                final center = Offset(size.width/2, 200 - 100); // wheel center in this box
                _lastPointerAngle = atan2(local.dy - center.dy, local.dx - center.dx);
              } else {
                _lastPointerAngle = 0;
              }
            },
            onPanUpdate: (d){
              if(_lastPointerAngle==null) return;
              final box = context.findRenderObject() as RenderBox?;
              if(box==null) return;
              final local = box.globalToLocal(d.globalPosition);
              final center = Offset(size.width/2, 200 - 100);
              final ang = atan2(local.dy - center.dy, local.dx - center.dx);
              // shortest signed delta in [-pi, pi]
              double delta = ang - _lastPointerAngle!;
              while(delta > pi)  delta -= 2*pi;
              while(delta < -pi) delta += 2*pi;
              // stop any ongoing momentum animation
              if(_spinAc.isAnimating) _spinAc.stop();
              setState(()=> _wheelAngle += delta);
              _lastPointerAngle = ang;

              // tick feedback when crossing notches
              final step = (2*pi) / count;
              final newTick = (_wheelAngle / step).round();
              if(newTick != _wheelTick){
                _wheelTick = newTick;
                HapticFeedback.selectionClick();
                SystemSound.play(SystemSoundType.click);
              }
            },
            onPanEnd: (DragEndDetails details){
              _lastPointerAngle = null;
              // Start momentum with friction for smooth deceleration
              // Approximate angular velocity from pan velocity around the wheel center
              final v = details.velocity.pixelsPerSecond;
              final rx = min(100.0, size.width * 0.42);
              // map tangential speed to angular velocity ω ≈ v_t / r
              final omega = (v.dx.abs() + v.dy.abs()) / 2.0 / max(48.0, rx);
              final signedOmega = (v.dx>=0 ? 1 : -1) * omega;
              // Cleanup any previous listeners
              if(_spinListener != null){ _spinAc.removeListener(_spinListener!); _spinListener = null; }
              if(_spinStatus != null){ _spinAc.removeStatusListener(_spinStatus!); _spinStatus = null; }
              _spinAc.value = _wheelAngle;
              final sim = FrictionSimulation(0.08, _wheelAngle, signedOmega);
              _spinListener = (){
                setState((){ _wheelAngle = _spinAc.value; });
                // notch tick during momentum
                final step = (2*pi) / count;
                final newTick = (_wheelAngle / step).round();
                if(newTick != _wheelTick){
                  _wheelTick = newTick;
                  HapticFeedback.selectionClick();
                  SystemSound.play(SystemSoundType.click);
                }
              };
              _spinStatus = (st){
                if(st==AnimationStatus.completed || st==AnimationStatus.dismissed){
                  // Snap gently to nearest notch
                  final step = (2*pi) / count;
                  final target = (_wheelAngle / step).round() * step;
                  _spinAc.removeListener(_spinListener!);
                  _spinAc.removeStatusListener(_spinStatus!);
                  _spinListener = (){ setState(()=> _wheelAngle = _spinAc.value); };
                  _spinStatus = (st2){ if(st2==AnimationStatus.completed){ HapticFeedback.lightImpact(); SystemSound.play(SystemSoundType.click); } };
                  _spinAc
                    ..addListener(_spinListener!)
                    ..addStatusListener(_spinStatus!)
                    ..animateTo(target, duration: Tokens.motionFast, curve: Curves.easeOut);
                }
              };
              _spinAc
                ..addListener(_spinListener!)
                ..addStatusListener(_spinStatus!)
                ..animateWith(sim);
            },
            child: Stack(alignment: Alignment.bottomCenter, children: [
              // active label at the top of wheel area
              Positioned(top: 6, left: 0, right: 0, child:
                IgnorePointer(child:
                  AnimatedSwitcher(duration: Tokens.motionFast, child:
                    Container(key: ValueKey(activeIndex), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface.withValues(alpha: .9), borderRadius: Tokens.radiusLg),
                      child: Text(specs[activeIndex].label, style: const TextStyle(fontWeight: FontWeight.w700)))))),
              // satellites on an ellipse, rotated like a dial (reduced vertical reach to avoid hub overlap)
              ...List.generate(count, (i){
                // Start at top (pi/2) to keep initial layout away from hub at bottom
                final base = pi/2 + i * stepAngle;
                // Elliptical radii: horizontal rx for spacing, smaller vertical ry to reduce overlap with hub
                final rx = min(100.0, size.width * 0.42);
                final ry = rx * 0.72;
                return AnimatedBuilder(
                  animation: _ac,
                  builder: (_, __) {
                    final a = CurvedAnimation(parent: _ac, curve: Curves.easeOutCubic).value;
                    final t = base + _wheelAngle; // apply wheel rotation
                    final dx = rx * cos(t) * a;
                    final dy = ry * sin(t) * a;

                    // Prevent overlap by shrinking chip width to chord length between neighbors
                    final chord = 2 * rx * sin(stepAngle/2);
                    const margin = 10.0; // keep a bit of space between chips
                    final baseW = (i==activeIndex)? 104.0 : 88.0;
                    final baseH = (i==activeIndex)? 56.0 : 48.0;
                    double w = min(baseW, chord - margin);
                    const minW = 56.0;
                    if(w < minW) w = minW;
                    final scale = (w / baseW).clamp(.85, 1.0);
                    final h = baseH * scale;
                    return Positioned(
                      bottom: 100 + dy, // center bottom distance = 100
                      left: (size.width/2) + dx - (w/2),
                      child: Opacity(opacity: a, child: _Sat(icon: specs[i].icon, label: specs[i].label, onTap: specs[i].onTap, active: i==activeIndex, width: w, height: h)),
                    );
                  },
                );
              }),
              Align(alignment: Alignment.bottomCenter, child: hub),
            ]),
          ),
        ),
      ),
    ]);
  }
}

// Simple grid home: icons as "liquid glass" tiles
class HomeRouteGrid extends StatelessWidget{
  final HomeActions actions;
  final bool showOps;
  final bool showSuperadmin;
  final bool taxiOnly;
  final List<String> operatorDomains;
  const HomeRouteGrid({
    super.key,
    required this.actions,
    this.showOps=true,
    this.showSuperadmin=false,
    this.taxiOnly=false,
    this.operatorDomains = const [],
  });
  @override Widget build(BuildContext context){
    final l = L10n.of(context);
    final isTaxiOperator = operatorDomains.contains('taxi');
    final isBusOperator = operatorDomains.contains('bus');
    final isStaysOperator = operatorDomains.contains('stays');
    final isFoodOperator = operatorDomains.contains('food');
    final isRealestateOperator = operatorDomains.contains('realestate');
    final isCommerceOperator = operatorDomains.contains('commerce');
    final isFreightOperator = operatorDomains.contains('freight');
    final isCarrentalOperator = operatorDomains.contains('carrental');
    // Category tiles to keep homescreen compact (flat, high‑contrast grid)
    if(taxiOnly){
      final taxiSpecs = <_SatSpec>[
        _SatSpec(icon: Icons.local_taxi_outlined, label: l.homeTaxiRider, onTap: actions.onTaxiRider),
        _SatSpec(icon: Icons.local_taxi, label: l.homeTaxiDriver, onTap: actions.onTaxiDriver),
        if (showOps && isTaxiOperator)
          _SatSpec(icon: Icons.support_agent, label: l.homeTaxiOperator, onTap: actions.onTaxiOperator),
      ];
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.1,
        ),
        itemCount: taxiSpecs.length,
        itemBuilder: (_, i){
          final s = taxiSpecs[i];
          return _LiquidGlassTile(icon: s.icon, label: s.label, onTap: s.onTap);
        },
      );
    }
    // Flat list: show all modules directly without grouping into sub-grids,
    // except Payments which is bundled again into a dedicated hub.
    final cats = <_SatSpec>[
      if(!taxiOnly)
        _SatSpec(
          icon: Icons.account_balance_wallet_outlined,
          label: l.homePayments,
          onTap: (){
            Navigator.of(context).push(MaterialPageRoute(builder: (_)=> HomeSubGrid(
              title: l.homePayments,
              specs: [
                _SatSpec(icon: Icons.receipt_long_outlined, label: l.homeBills, onTap: actions.onBills, tint: Tokens.colorPayments),
                _SatSpec(icon: Icons.list_alt, label: l.homeRequests, onTap: actions.onRequests, tint: Tokens.colorPayments),
                _SatSpec(icon: Icons.card_giftcard, label: l.homeVouchers, onTap: actions.onVouchers, tint: Tokens.colorPayments),
              ],
              compact: true,
            )));
          },
          tint: Tokens.colorPayments,
        ),
      // Taxi
      _SatSpec(
        icon: Icons.local_taxi_outlined,
        label: l.homeTaxiRider,
        onTap: actions.onTaxiRider,
        tint: Tokens.colorTaxi,
      ),
      if (showOps && isTaxiOperator)
        _SatSpec(
          icon: Icons.support_agent,
          label: l.homeTaxiOperator,
          onTap: actions.onTaxiOperator,
          tint: Tokens.colorTaxi,
        ),
      // Bus & mobility (end-user only sees Bus, Bus Operator stays im Operator-Dashboard)
      _SatSpec(icon: Icons.directions_bus_filled, label: 'Bus', onTap: actions.onBus, tint: Tokens.colorBus),
      _SatSpec(icon: Icons.local_shipping_outlined, label: 'Courier & Transport', onTap: actions.onFreight, tint: Tokens.colorCourierTransport),
      // Food
      _SatSpec(icon: Icons.restaurant_outlined, label: l.homeFood, onTap: actions.onFood, tint: Tokens.colorFood),
      // Stays & flights
      _SatSpec(icon: Icons.hotel, label: l.homeStays, onTap: actions.onStays, tint: Tokens.colorHotelsStays),
      _SatSpec(icon: Icons.flight_takeoff, label: l.homeFlights, onTap: actions.onFlights, tint: Tokens.colorHotelsStays),
      // Marketplace & services
      _SatSpec(
        icon: Icons.storefront,
        label: l.homeCommerce,
        onTap: (){
          Navigator.of(context).push(MaterialPageRoute(builder: (_)=> HomeSubGrid(
            title: l.homeCommerce,
            specs: [
              _SatSpec(icon: Icons.agriculture, label: l.homeAgriculture, onTap: actions.onAgriculture, tint: Tokens.colorAgricultureLivestock),
              _SatSpec(icon: Icons.directions_car_filled_outlined, label: 'Carmarket', onTap: actions.onCarmarket, tint: Tokens.colorCars),
              _SatSpec(icon: Icons.car_rental, label: 'Carrental', onTap: actions.onCarrental, tint: Tokens.colorCars),
              _SatSpec(icon: Icons.home_work_outlined, label: l.realEstateTitle, onTap: actions.onRealestate, tint: Tokens.colorHotelsStays),
              _SatSpec(icon: Icons.work_outline, label: l.homeJobs, onTap: actions.onJobs, tint: Tokens.colorBuildingMaterials),
              _SatSpec(icon: Icons.construction_outlined, label: l.homeBuildingMaterials, onTap: actions.onBuildingMaterials, tint: Tokens.colorBuildingMaterials),
            ],
            compact: true,
          )));
        },
        tint: Tokens.colorBuildingMaterials,
      ),
      _SatSpec(icon: Icons.medical_services_outlined, label: l.homeDoctors, onTap: actions.onDoctors, tint: Tokens.colorCourierTransport),
      // Chat
      _SatSpec(icon: Icons.chat_bubble_outline, label: l.homeChat, onTap: actions.onChat, tint: Tokens.accent),
      // Courier & Transport split
      _SatSpec(
        icon: Icons.local_shipping_outlined,
        label: 'Courier',
        onTap: actions.onCourier,
        tint: Tokens.colorCourierTransport,
      ),
      _SatSpec(
        icon: Icons.local_shipping,
        label: 'Transport',
        onTap: actions.onFreight,
        tint: Tokens.colorCourierTransport,
      ),
      // Admin / Ops tiles (only when applicable)
      if(showOps) _SatSpec(icon: Icons.admin_panel_settings, label: 'Ops Console', onTap: actions.onOps, tint: Tokens.lightFocus),
      if(showSuperadmin) _SatSpec(icon: Icons.security, label: 'Superadmin', onTap: actions.onOps, tint: Tokens.error),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.1,
            ),
            itemCount: cats.length,
            itemBuilder: (_, i){
              final s = cats[i];
              return _LiquidGlassTile(icon: s.icon, label: s.label, onTap: s.onTap, tint: s.tint);
            },
          ),
        ),
        if(!taxiOnly)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children:[
                Row(
                  children:[
                    Expanded(
                      child: PayActionButton(
                        icon: Icons.qr_code_scanner,
                        label: 'Scan & pay',
                        onTap: actions.onScanPay,
                        tint: Tokens.colorPayments,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: PayActionButton(
                        icon: Icons.compare_arrows_outlined,
                        label: 'P2P',
                        onTap: actions.onP2P,
                        tint: Tokens.colorPayments,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children:[
                    Expanded(
                      child: PayActionButton(
                        icon: Icons.account_balance_wallet_outlined,
                        label: 'Topup',
                        onTap: actions.onTopup,
                        tint: Tokens.colorPayments,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: PayActionButton(
                        icon: Icons.bolt,
                        label: 'Sonic',
                        onTap: actions.onSonic,
                        tint: Tokens.colorPayments,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _LiquidGlassTile extends StatelessWidget{
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? tint;
  const _LiquidGlassTile({required this.icon, required this.label, required this.onTap, this.tint});
  @override Widget build(BuildContext context){
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color cardBg = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : Colors.white;
    final Color border = isDark
        ? Colors.white.withValues(alpha: .18)
        : Colors.black.withValues(alpha: .10);
    final Color iconBg = (tint ?? theme.colorScheme.primary).withValues(alpha: .12);
    final Color iconFg = tint ?? theme.colorScheme.primary;
    final Color textColor = theme.colorScheme.onSurface.withValues(alpha: .90);
    return Semantics(
      button: true,
      label: label,
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: Material(
          color: cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: Tokens.radiusSm,
            side: BorderSide(color: border),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: Tokens.radiusSm,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: iconBg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 30, color: iconFg),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomeSubGrid extends StatelessWidget{
  final String title;
  final List<_SatSpec> specs;
  final bool compact;
  const HomeSubGrid({super.key, required this.title, required this.specs, this.compact = false});
  @override Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          // In compact-Modus dieselbe Kachelgröße wie im Haupt-Homescreen (6 Spalten).
          crossAxisCount: compact ? 6 : 3,
          mainAxisSpacing: compact ? 8 : 12,
          crossAxisSpacing: compact ? 8 : 12,
          childAspectRatio: compact ? 1.1 : .95,
        ),
        itemCount: specs.length,
        itemBuilder: (_, i){
          final s = specs[i];
          return _LiquidGlassTile(icon: s.icon, label: s.label, onTap: s.onTap);
        },
      ),
    );
  }
}

class _SatSpec {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? tint;
  const _SatSpec({required this.icon, required this.label, required this.onTap, this.tint});
}

class _ThumbHubButton extends StatefulWidget{
  final VoidCallback onTap; final String label; final IconData icon;
  const _ThumbHubButton({required this.onTap, required this.label, required this.icon});
  @override State<_ThumbHubButton> createState()=>_ThumbHubButtonState();
}
class _ThumbHubButtonState extends State<_ThumbHubButton>{
  bool _pressed=false;
  @override Widget build(BuildContext context){
    final c = Theme.of(context).colorScheme;
    final bg = c.primary;
    final fg = bg.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    return GestureDetector(
      onTapDown: (_){ setState(()=>_pressed=true); },
      onTapCancel: (){ setState(()=>_pressed=false); },
      onTapUp: (_){ setState(()=>_pressed=false); HapticFeedback.lightImpact(); widget.onTap(); },
      child: AnimatedScale(duration: Tokens.motionFast, scale: _pressed? .98 : 1, child:
        Container(
          constraints: const BoxConstraints(minWidth: 220),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(color: bg, borderRadius: Tokens.radiusXl, boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 18, offset: Offset(0,10))]),
          child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children:[ Icon(widget.icon, color: fg), const SizedBox(width:8), Text(widget.label, style: TextStyle(color: fg, fontWeight: FontWeight.w700)) ]),
        ),
      ),
    );
  }
}

class _Sat extends StatelessWidget{
  final IconData icon; final String label; final VoidCallback onTap; final bool active; final double width; final double height;
  const _Sat({required this.icon, required this.label, required this.onTap, this.active=false, this.width=88, this.height=48});
  @override Widget build(BuildContext context){
    final c = Theme.of(context).colorScheme;
    final bg = active ? c.primary : c.surface.withValues(alpha: .9);
    final Color fg = (bg.computeLuminance() > 0.5) ? Colors.black : Colors.white;
    return Semantics(button: true, label: label, selected: active, child:
      Material(
        color: Colors.transparent,
        child: AnimatedScale(duration: Tokens.motionFast, scale: active? 1.06 : 1.0, child:
          InkWell(onTap: onTap, borderRadius: Tokens.radiusLg, child:
            AnimatedContainer(duration: Tokens.motionFast, width: width, height: height,
              decoration: BoxDecoration(color: bg, borderRadius: Tokens.radiusLg, border: active? null : Border.all(color: Colors.white24), boxShadow: active? const [BoxShadow(color: Colors.black45, blurRadius: 16, offset: Offset(0,8))] : null),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children:[ Icon(icon, size: 18, color: fg), const SizedBox(width:6), Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: active? FontWeight.w700 : FontWeight.w400))) ])),
          ),
        ),
      ),
    );
  }
}

class _HeaderAndFeed extends StatelessWidget{
  final HomeActions actions; const _HeaderAndFeed({required this.actions});
  @override Widget build(BuildContext context){
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children:[
      const SizedBox(height: 8),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child:
        Builder(builder: (context){
          final l = L10n.of(context);
          return Row(children:[
            _QuickChip(
              icon: Icons.qr_code_scanner,
              label: l.qaScanPay,
              onTap: (){ Perf.tap('quick_scan'); actions.onScanPay(); },
              tint: Tokens.colorPayments,
            ),
            const SizedBox(width:8),
            _QuickChip(
              icon: Icons.swap_horiz,
              label: l.qaP2P,
              onTap: (){ Perf.tap('quick_p2p'); actions.onP2P(); },
              tint: Tokens.colorPayments,
            ),
            const SizedBox(width:8),
            _QuickChip(
              icon: Icons.account_balance_wallet_outlined,
              label: l.qaTopup,
              onTap: (){ Perf.tap('quick_topup'); actions.onTopup(); },
              tint: Tokens.colorPayments,
            ),
            const SizedBox(width:8),
            _QuickChip(
              icon: Icons.bolt,
              label: l.qaSonic,
              onTap: (){ Perf.tap('quick_sonic'); actions.onSonic(); },
              tint: Tokens.colorPayments,
            ),
          ]);
        })),
      const SizedBox(height: 12),
      const Expanded(child: _NBOFeed()),
      const SizedBox(height: 96),
    ]);
  }
}

class _QuickChip extends StatelessWidget{
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? tint;
  const _QuickChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tint,
  });
  @override
  Widget build(BuildContext context){
    final scheme = Theme.of(context).colorScheme;
    final Color base = tint ?? scheme.surface;
    final Color bg = tint != null
        ? base.withValues(alpha: .16)
        : scheme.surface.withValues(alpha: .9);
    final Color fg = (bg.computeLuminance() > 0.5) ? Colors.black : Colors.white;
    final Color borderColor = tint != null
        ? tint!.withValues(alpha: .9)
        : Colors.white24;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: Tokens.radiusLg,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: Tokens.radiusLg,
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NBOFeed extends StatefulWidget{
  const _NBOFeed();
  @override State<_NBOFeed> createState()=>_NBOFeedState();
}
class _NBOFeedState extends State<_NBOFeed>{
  bool _loading = true;
  bool _long = false;
  @override void initState(){ super.initState(); _init(); }
  Future<void> _init() async { try{ final sp=await SharedPreferences.getInstance(); _long = sp.getBool('debug_skeleton_long') ?? false; }catch(_){ } await _simulateLoad(); }
  Future<void> _simulateLoad() async {
    // Simuliert Datenbeschaffung; Skeleton max. 1200ms sichtbar, Debug: 1200ms
    final delay = Duration(milliseconds: _long? 1200 : (400 + (DateTime.now().millisecond % 250)));
    await Future.delayed(delay);
    if(!mounted) return;
    setState(()=>_loading=false);
  }
  @override Widget build(BuildContext context){
    if(_loading){
      return ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: const [
        SkeletonBox(height: 72), SizedBox(height: 12),
        SkeletonBox(height: 72), SizedBox(height: 12),
        SkeletonBox(height: 72),
      ]);
    }
    // Remove suggested tiles for more space above the dial.
    return const SizedBox.shrink();
  }
}

class HomeRoutePalette extends StatefulWidget {
  final HomeActions actions;
  final bool showTaxiOperator;
  const HomeRoutePalette({super.key, required this.actions, this.showTaxiOperator = false});
  @override State<HomeRoutePalette> createState()=>_HomeRoutePaletteState();
}

class _HomeRoutePaletteState extends State<HomeRoutePalette>{
  final ctrl = TextEditingController();
  final recents = <String>[ 'senden 25€ an Lea', 'taxi nach Arbeit', 'stromrechnung bezahlen' ];
  @override Widget build(BuildContext context){
    final l = L10n.of(context);
    return Column(children:[
      const SizedBox(height: 8),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child:
        TextField(
          controller: ctrl,
          decoration: InputDecoration(
            labelText: l.isArabic
                ? 'اكتب أمرًا (مثال: "إرسال 25 إلى…")'
                : 'Enter command (e.g., "send 25 to…")',
          ),
        ),
      ),
      const SizedBox(height: 8),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child:
        Wrap(spacing: 8, children: [
          _QuickChip(
            icon: Icons.local_taxi_outlined,
            label: l.homeTaxiRider,
            onTap: widget.actions.onTaxiRider,
            tint: Tokens.colorTaxi,
          ),
          _QuickChip(
            icon: Icons.local_taxi,
            label: l.homeTaxiDriver,
            onTap: widget.actions.onTaxiDriver,
            tint: Tokens.colorTaxi,
          ),
          if(widget.showTaxiOperator)
            _QuickChip(
              icon: Icons.support_agent,
              label: l.homeTaxiOperator,
              onTap: widget.actions.onTaxiOperator,
              tint: Tokens.colorTaxi,
            ),
        ]),
      ),
      const SizedBox(height: 8),
      Expanded(child: ListView.builder(itemCount: recents.length, itemBuilder: (_,i)=>ListTile(title: Text(recents[i]), leading: const Icon(Icons.chevron_right))))
    ]);
  }
}

class HomeRouteSheets extends StatefulWidget{
  final HomeActions actions;
  final bool showTaxiOperator;
  const HomeRouteSheets({super.key, required this.actions, this.showTaxiOperator = false});
  @override State<HomeRouteSheets> createState()=>_HomeRouteSheetsState();
}

class _HomeRouteSheetsState extends State<HomeRouteSheets>{
  @override Widget build(BuildContext context){
    final l = L10n.of(context);
    return Stack(children:[
      Positioned.fill(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children:[
        const SizedBox(height: 8),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child:
          Row(children:[
            _QuickChip(
              icon: Icons.local_taxi_outlined,
              label: l.homeTaxiRider,
              onTap: widget.actions.onTaxiRider,
              tint: Tokens.colorTaxi,
            ),
            const SizedBox(width:8),
            _QuickChip(
              icon: Icons.local_taxi,
              label: l.homeTaxiDriver,
              onTap: widget.actions.onTaxiDriver,
              tint: Tokens.colorTaxi,
            ),
            if(widget.showTaxiOperator)...[
              const SizedBox(width:8),
              _QuickChip(
                icon: Icons.support_agent,
                label: l.homeTaxiOperator,
                onTap: widget.actions.onTaxiOperator,
                tint: Tokens.colorTaxi,
              ),
            ],
          ])),
      ])),
      DraggableScrollableSheet(
        initialChildSize: .58, minChildSize: .40, maxChildSize: .95,
        snap: true, snapSizes: const [.40, .58, .95],
        builder: (_, controller){
          return _SheetContainer(title: l.homeTaxi, controller: controller, child: ListView(controller: controller, children: [
            ListTile(title: Text(l.homeTaxiRider), trailing: const Icon(Icons.chevron_right), onTap: widget.actions.onTaxiRider),
            ListTile(title: Text(l.homeTaxiDriver), trailing: const Icon(Icons.chevron_right), onTap: widget.actions.onTaxiDriver),
            if(widget.showTaxiOperator)
              ListTile(title: Text(l.homeTaxiOperator), trailing: const Icon(Icons.chevron_right), onTap: widget.actions.onTaxiOperator),
            const SizedBox(height: 8),
          ]));
        },
      ),
      const SizedBox.shrink(),
    ]);
  }
}

class _SheetContainer extends StatelessWidget{
  final String title; final Widget child; final ScrollController? controller;
  const _SheetContainer({required this.title, required this.child, this.controller});
  @override Widget build(BuildContext context){
    return Semantics(container: true, child: FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: .98),
        elevation: 10,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: Column(children:[
          Container(height: 36, alignment: Alignment.center, child: Container(width: 44, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Row(children:[ Text(title, style: const TextStyle(fontWeight: FontWeight.w700)), const Spacer() ])),
          Expanded(child: child),
        ]),
      ),
    ));
  }
}
