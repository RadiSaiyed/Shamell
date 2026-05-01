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
  final VoidCallback onBus;
  final VoidCallback onChat;
  final VoidCallback onVouchers;
  final VoidCallback onRequests;
  final VoidCallback onBills;
  final VoidCallback onWallet;
  final VoidCallback onHistory;
  final VoidCallback onOps; // Consolidated Ops hub
  const HomeActions({
    required this.onScanPay,
    required this.onTopup,
    required this.onSonic,
    required this.onP2P,
    required this.onMobility,
    required this.onBus,
    required this.onChat,
    required this.onVouchers,
    required this.onRequests,
    required this.onBills,
    required this.onWallet,
    required this.onHistory,
    required this.onOps,
  });
}

// Simple grid home: icons as flat tiles
class HomeRouteGrid extends StatelessWidget {
  final HomeActions actions;
  final bool showOps;
  final bool showSuperadmin;
  const HomeRouteGrid({
    super.key,
    required this.actions,
    this.showOps = true,
    this.showSuperadmin = false,
  });
  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    // Category tiles to keep homescreen compact (flat, high‑contrast grid)
    // Flat list of high-level hubs. Each hub opens a compact sub-grid that
    // groups related domains (finance, mobility, social, ops).
    // Payments stays as a dedicated finance hub.
    final cats = <_SatSpec>[
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
                    ],
                    compact: true,
                  )));
        },
        tint: Tokens.colorPayments,
      ),
      // Mobility & Travel cluster: journey + bus
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
                          tint: Tokens.colorBus),
                      _SatSpec(
                          icon: Icons.directions_bus,
                          label: l.busTitle,
                          onTap: actions.onBus,
                          tint: Tokens.colorBus),
                    ],
                    compact: true,
                  )));
        },
        tint: Tokens.colorBus,
      ),
      // Social
      _SatSpec(
        icon: Icons.chat_bubble_outline,
        label: l.homeChat,
        onTap: actions.onChat,
        tint: Tokens.accent,
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
