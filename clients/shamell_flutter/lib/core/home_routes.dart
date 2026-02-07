import 'package:flutter/material.dart';
import 'design_tokens.dart';
import '../mini_apps/payments/payments_send.dart' show PayActionButton;
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
  final VoidCallback onStaysPro;
  // Additional modules on homescreen
  final VoidCallback onCarmarket;
  final VoidCallback onCarrental;
  final VoidCallback onEquipment;
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
  final VoidCallback onTira;
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
    required this.onStaysPro,
    required this.onCarmarket,
    required this.onCarrental,
    required this.onEquipment,
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
    required this.onTira,
  });
}

// Simple grid home: icons as flat tiles
class HomeRouteGrid extends StatelessWidget {
  final HomeActions actions;
  final bool showOps;
  final bool showSuperadmin;
  final bool taxiOnly;
  final List<String> operatorDomains;
  const HomeRouteGrid({
    super.key,
    required this.actions,
    this.showOps = true,
    this.showSuperadmin = false,
    this.taxiOnly = false,
    this.operatorDomains = const [],
  });
  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final isTaxiOperator = operatorDomains.contains('taxi');
    // operator flags currently unused in grid
    // Category tiles to keep homescreen compact (flat, high‑contrast grid)
    if (taxiOnly) {
      final taxiSpecs = <_SatSpec>[
        _SatSpec(
            icon: Icons.local_taxi_outlined,
            label: l.homeTaxiRider,
            onTap: actions.onTaxiRider),
        _SatSpec(
            icon: Icons.local_taxi,
            label: l.homeTaxiDriver,
            onTap: actions.onTaxiDriver),
        if (showOps && isTaxiOperator)
          _SatSpec(
              icon: Icons.support_agent,
              label: l.homeTaxiOperator,
              onTap: actions.onTaxiOperator),
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
        itemBuilder: (_, i) {
          final s = taxiSpecs[i];
          return _HomeGridTile(icon: s.icon, label: s.label, onTap: s.onTap);
        },
      );
    }
    // Flat list of high-level hubs. Each hub opens a compact sub-grid that
    // groups related domains (finance, mobility, logistics, commerce, etc.).
    // Payments stays as a dedicated finance hub.
    final cats = <_SatSpec>[
      if (!taxiOnly)
        _SatSpec(
          icon: Icons.payments_outlined,
          label: l.isArabic ? 'المال والمحفظة' : 'Finance & Wallet',
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => HomeSubGrid(
                      title: l.isArabic ? 'المال والمحفظة' : 'Finance & Wallet',
                      specs: [
                        _SatSpec(
                            icon: Icons.account_balance_wallet_outlined,
                            label: l.homeWallet,
                            onTap: actions.onWallet,
                            tint: Tokens.colorPayments),
                        _SatSpec(
                            icon: Icons.receipt_long_outlined,
                            label: l.homeBills,
                            onTap: actions.onBills,
                            tint: Tokens.colorPayments),
                        _SatSpec(
                            icon: Icons.history,
                            label: l.historyTitle,
                            onTap: actions.onHistory,
                            tint: Tokens.colorPayments),
                        _SatSpec(
                            icon: Icons.list_alt,
                            label: l.homeRequests,
                            onTap: actions.onRequests,
                            tint: Tokens.colorPayments),
                        _SatSpec(
                            icon: Icons.card_giftcard,
                            label: l.homeVouchers,
                            onTap: actions.onVouchers,
                            tint: Tokens.colorPayments),
                        _SatSpec(
                            icon: Icons.point_of_sale,
                            label: l.homeMerchantPos,
                            onTap: actions.onMerchantPOS,
                            tint: Tokens.colorPayments),
                      ],
                      compact: true,
                    )));
          },
          tint: Tokens.colorPayments,
        ),
      // Mobility & Travel cluster: taxi, bus, flights
      _SatSpec(
        icon: Icons.directions_car_filled,
        label: l.isArabic ? 'التنقل والسفر' : 'Mobility & Travel',
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => HomeSubGrid(
                    title: l.isArabic ? 'التنقل والسفر' : 'Mobility & Travel',
                    specs: [
                      _SatSpec(
                          icon: Icons.route,
                          label: l.mobilityTitle,
                          onTap: actions.onMobility,
                          tint: Tokens.colorTaxi),
                      _SatSpec(
                          icon: Icons.local_taxi_outlined,
                          label: l.homeTaxiRider,
                          onTap: actions.onTaxiRider,
                          tint: Tokens.colorTaxi),
                      _SatSpec(
                          icon: Icons.local_taxi,
                          label: l.homeTaxiDriver,
                          onTap: actions.onTaxiDriver,
                          tint: Tokens.colorTaxi),
                      _SatSpec(
                          icon: Icons.support_agent,
                          label: l.homeTaxiOperator,
                          onTap: actions.onTaxiOperator,
                          tint: Tokens.colorTaxi),
                      _SatSpec(
                          icon: Icons.directions_bus,
                          label: l.busTitle,
                          onTap: actions.onBus,
                          tint: Tokens.colorBus),
                      _SatSpec(
                          icon: Icons.flight_takeoff,
                          label: l.homeFlights,
                          onTap: actions.onFlights,
                          tint: Tokens.colorHotelsStays),
                    ],
                    compact: true,
                  )));
        },
        tint: Tokens.colorBus,
      ),
      // Delivery & Logistics: courier, live courier, freight
      _SatSpec(
        icon: Icons.delivery_dining_outlined,
        label:
            l.isArabic ? 'التوصيل والخدمات اللوجستية' : 'Delivery & Logistics',
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => HomeSubGrid(
                    title: l.isArabic
                        ? 'التوصيل والخدمات اللوجستية'
                        : 'Delivery & Logistics',
                    specs: [
                      _SatSpec(
                          icon: Icons.local_shipping_outlined,
                          label: 'Courier',
                          onTap: actions.onCourier,
                          tint: Tokens.colorCourierTransport),
                      _SatSpec(
                          icon: Icons.delivery_dining_outlined,
                          label: 'Courier Live',
                          onTap: actions.onTira,
                          tint: Tokens.colorCourierTransport),
                      _SatSpec(
                          icon: Icons.local_shipping,
                          label: 'Freight',
                          onTap: actions.onFreight,
                          tint: Tokens.colorCourierTransport),
                    ],
                    compact: true,
                  )));
        },
        tint: Tokens.colorCourierTransport,
      ),
      // Food & Shopping: food orders + commerce entry point
      _SatSpec(
        icon: Icons.shopping_bag_outlined,
        label: l.isArabic ? 'الطعام والتسوق' : 'Food & Shopping',
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => HomeSubGrid(
                    title: l.isArabic ? 'الطعام والتسوق' : 'Food & Shopping',
                    specs: [
                      _SatSpec(
                          icon: Icons.restaurant_outlined,
                          label: l.homeFood,
                          onTap: actions.onFood,
                          tint: Tokens.colorFood),
                      _SatSpec(
                          icon: Icons.receipt_long_outlined,
                          label: l.foodOrdersTitle,
                          onTap: actions.onFoodOrders,
                          tint: Tokens.colorFood),
                      _SatSpec(
                          icon: Icons.storefront_outlined,
                          label: l.homeCommerce,
                          onTap: actions.onCommerce,
                          tint: Tokens.colorBuildingMaterials),
                    ],
                    compact: true,
                  )));
        },
        tint: Tokens.colorFood,
      ),
      // Stays & Real Estate
      _SatSpec(
        icon: Icons.home_work_outlined,
        label: l.isArabic ? 'الإقامة والعقارات' : 'Stays & Real Estate',
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => HomeSubGrid(
                    title: l.isArabic
                        ? 'الإقامة والعقارات'
                        : 'Stays & Real Estate',
                    specs: [
                      _SatSpec(
                          icon: Icons.hotel,
                          label: l.homeStays,
                          onTap: actions.onStays,
                          tint: Tokens.colorHotelsStays),
                      _SatSpec(
                          icon: Icons.business_center_outlined,
                          label: l.staysOperatorTitle,
                          onTap: actions.onStaysHotel,
                          tint: Tokens.colorHotelsStays),
                      _SatSpec(
                          icon: Icons.apartment_outlined,
                          label: 'Stays Pro',
                          onTap: actions.onStaysPro,
                          tint: Tokens.colorHotelsStays),
                      _SatSpec(
                          icon: Icons.home_work_outlined,
                          label: l.realEstateTitle,
                          onTap: actions.onRealestate,
                          tint: Tokens.colorHotelsStays),
                    ],
                    compact: true,
                  )));
        },
        tint: Tokens.colorHotelsStays,
      ),
      // Agriculture, vehicles & equipment
      _SatSpec(
        icon: Icons.agriculture,
        label: l.isArabic ? 'الزراعة والتجارة' : 'Agriculture & Trade',
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => HomeSubGrid(
                    title:
                        l.isArabic ? 'الزراعة والتجارة' : 'Agriculture & Trade',
                    specs: [
                      _SatSpec(
                          icon: Icons.store_mall_directory_outlined,
                          label: l.homeAgriculture,
                          onTap: actions.onAgriculture,
                          tint: Tokens.colorAgricultureLivestock),
                      _SatSpec(
                          icon: Icons.agriculture,
                          label: l.homeLivestock,
                          onTap: actions.onLivestock,
                          tint: Tokens.colorAgricultureLivestock),
                      _SatSpec(
                          icon: Icons.directions_car_filled_outlined,
                          label: 'Carmarket',
                          onTap: actions.onCarmarket,
                          tint: Tokens.colorCars),
                      _SatSpec(
                          icon: Icons.car_rental,
                          label: 'Carrental',
                          onTap: actions.onCarrental,
                          tint: Tokens.colorCars),
                      _SatSpec(
                          icon: Icons.engineering,
                          label: l.equipmentTitle,
                          onTap: actions.onEquipment,
                          tint: Tokens.colorBuildingMaterials),
                      _SatSpec(
                          icon: Icons.construction_outlined,
                          label: l.homeBuildingMaterials,
                          onTap: actions.onBuildingMaterials,
                          tint: Tokens.colorBuildingMaterials),
                    ],
                    compact: true,
                  )));
        },
        tint: Tokens.colorBuildingMaterials,
      ),
      // Jobs & Services: jobs, doctors, chat
      _SatSpec(
        icon: Icons.handyman_outlined,
        label: l.isArabic ? 'الوظائف والخدمات' : 'Jobs & Services',
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => HomeSubGrid(
                    title: l.isArabic ? 'الوظائف والخدمات' : 'Jobs & Services',
                    specs: [
                      _SatSpec(
                          icon: Icons.work_outline,
                          label: l.homeJobs,
                          onTap: actions.onJobs,
                          tint: Tokens.colorBuildingMaterials),
                      _SatSpec(
                          icon: Icons.medical_services_outlined,
                          label: l.homeDoctors,
                          onTap: actions.onDoctors,
                          tint: Tokens.colorCourierTransport),
                      _SatSpec(
                          icon: Icons.chat_bubble_outline,
                          label: l.homeChat,
                          onTap: actions.onChat,
                          tint: Tokens.accent),
                    ],
                    compact: true,
                  )));
        },
        tint: Tokens.colorBuildingMaterials,
      ),
      // Admin / Ops tiles (only when applicable)
      if (showOps)
        _SatSpec(
            icon: Icons.admin_panel_settings,
            label: 'Ops Console',
            onTap: actions.onOps,
            tint: Tokens.lightFocus),
      if (showSuperadmin)
        _SatSpec(
            icon: Icons.security,
            label: 'Superadmin',
            onTap: actions.onOps,
            tint: Tokens.error),
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
            itemBuilder: (_, i) {
              final s = cats[i];
              return _HomeGridTile(
                  icon: s.icon, label: s.label, onTap: s.onTap, tint: s.tint);
            },
          ),
        ),
        if (!taxiOnly)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
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
                  children: [
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

class _HomeGridTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? tint;
  const _HomeGridTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tint,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color baseTint = tint ?? theme.colorScheme.primary;
    final Color surface = theme.colorScheme.surface;
    final Color border = theme.dividerColor.withValues(alpha: .65);
    final Color iconBg = baseTint.withValues(alpha: .15);
    final Color iconFg = baseTint;
    final Color textColor = theme.colorScheme.onSurface.withValues(alpha: .90);
    return Semantics(
      button: true,
      label: label,
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: Material(
          color: surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: border),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
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
                    child: Icon(icon, size: 28, color: iconFg),
                  ),
                  const SizedBox(height: 4),
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

class HomeSubGrid extends StatelessWidget {
  final String title;
  final List<_SatSpec> specs;
  final bool compact;
  const HomeSubGrid(
      {super.key,
      required this.title,
      required this.specs,
      this.compact = false});
  @override
  Widget build(BuildContext context) {
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
        itemBuilder: (_, i) {
          final s = specs[i];
          return _HomeGridTile(icon: s.icon, label: s.label, onTap: s.onTap);
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
  const _SatSpec(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.tint});
}
