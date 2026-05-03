import 'package:flutter/material.dart';

import '../../../design/components/v2_surface_card.dart';
import '../../../design/tokens.dart';

class V2MePage extends StatelessWidget {
  final String userId;
  final String displayName;
  final String walletId;
  final VoidCallback onOpenMyQr;
  final VoidCallback onOpenPayments;
  final VoidCallback onOpenFavorites;
  final VoidCallback onOpenSecurityCenter;
  final VoidCallback onOpenSettings;

  const V2MePage({
    super.key,
    required this.userId,
    required this.displayName,
    required this.walletId,
    required this.onOpenMyQr,
    required this.onOpenPayments,
    required this.onOpenFavorites,
    required this.onOpenSecurityCenter,
    required this.onOpenSettings,
  });

  String _initialForName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final userIdLabel = userId.trim().isEmpty ? 'Not set' : userId.trim();
    final displayLabel = displayName.trim().isNotEmpty
        ? displayName.trim()
        : (userId.trim().isNotEmpty ? userId.trim() : 'You');
    return Scaffold(
      backgroundColor: V2Tokens.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(V2Tokens.spacingLg),
          children: [
            Text(
              'Me',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: V2Tokens.spacingLg),
            V2SurfaceCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: V2Tokens.brand.withValues(alpha: 0.14),
                    child: Text(
                      _initialForName(displayLabel),
                      style: const TextStyle(
                        color: V2Tokens.brand,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: V2Tokens.spacingMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayLabel,
                          style: Theme.of(context).textTheme.titleLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: V2Tokens.spacingXs),
                        Text(
                          'User ID: $userIdLabel',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: V2Tokens.textSecondary,
                                  ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Wallet ID: $walletId',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: V2Tokens.textSecondary,
                                  ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'My QR code',
                    onPressed: onOpenMyQr,
                    icon: const Icon(Icons.qr_code_2_outlined),
                  ),
                ],
              ),
            ),
            const SizedBox(height: V2Tokens.spacingLg),
            V2SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _cell(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Pay',
                    subtitle: 'Wallet, transfers, cards, offers, and history',
                    onTap: onOpenPayments,
                  ),
                  const Divider(height: 1),
                  _cell(
                    icon: Icons.star_outline,
                    title: 'Favorites',
                    subtitle: 'Saved chats, notes, and payment references',
                    onTap: onOpenFavorites,
                  ),
                ],
              ),
            ),
            const SizedBox(height: V2Tokens.spacingLg),
            V2SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _cell(
                    icon: Icons.security_outlined,
                    title: 'Security Center',
                    subtitle:
                        'Biometric login, password, emergency contact, and linked devices',
                    onTap: onOpenSecurityCenter,
                  ),
                  const Divider(height: 1),
                  _cell(
                    icon: Icons.settings_outlined,
                    title: 'Settings',
                    subtitle: 'Notifications, privacy, general, and about',
                    onTap: onOpenSettings,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: V2Tokens.textPrimary),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: const TextStyle(fontSize: 12),
            ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
