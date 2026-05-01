import 'package:flutter/material.dart';

import '../../../design/components/v2_surface_card.dart';
import '../../../design/tokens.dart';

class V2DiscoverPage extends StatelessWidget {
  final VoidCallback onOpenScan;
  final VoidCallback onOpenReceivePay;
  final VoidCallback onOpenPayments;
  final VoidCallback onOpenRequests;
  final VoidCallback onOpenBills;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenGroupPay;
  final VoidCallback onOpenChatWorkspace;
  final bool showBills;

  const V2DiscoverPage({
    super.key,
    required this.onOpenScan,
    required this.onOpenReceivePay,
    required this.onOpenPayments,
    required this.onOpenRequests,
    required this.onOpenBills,
    required this.onOpenHistory,
    required this.onOpenGroupPay,
    required this.onOpenChatWorkspace,
    this.showBills = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V2Tokens.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(V2Tokens.spacingLg),
          children: [
            Text(
              'Apps',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: V2Tokens.spacingSm),
            _sectionTitle(context, 'Social'),
            const SizedBox(height: V2Tokens.spacingSm),
            V2SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _cell(
                    icon: Icons.photo_library_outlined,
                    title: 'Moments',
                    subtitle:
                        'Temporarily fail-closed in this build (parity target retained)',
                    enabled: false,
                  ),
                  const Divider(height: 1),
                  _cell(
                    icon: Icons.qr_code_scanner,
                    title: 'Scan',
                    subtitle: 'Scan for contacts, login, and payments',
                    onTap: onOpenScan,
                  ),
                  const Divider(height: 1),
                  _cell(
                    icon: Icons.forum_outlined,
                    title: 'Chat workspace',
                    subtitle:
                        'Open the full chat workspace with groups, media/voice, and calls',
                    onTap: onOpenChatWorkspace,
                  ),
                ],
              ),
            ),
            const SizedBox(height: V2Tokens.spacingLg),
            _sectionTitle(context, 'Pay'),
            const SizedBox(height: V2Tokens.spacingSm),
            V2SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _cell(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Wallet & transfers',
                    subtitle: 'Balance, transfer, topup, and linked cards',
                    onTap: onOpenPayments,
                  ),
                  const Divider(height: 1),
                  _cell(
                    icon: Icons.qr_code_2_outlined,
                    title: 'Receive & pay code',
                    subtitle: 'Show receive QR and scan to pay',
                    onTap: onOpenReceivePay,
                  ),
                  const Divider(height: 1),
                  _cell(
                    icon: Icons.request_page_outlined,
                    title: 'Payment requests',
                    subtitle: 'Incoming and outgoing requests',
                    onTap: onOpenRequests,
                  ),
                  const Divider(height: 1),
                  if (showBills) ...[
                    _cell(
                      icon: Icons.receipt_long_outlined,
                      title: 'Bills',
                      subtitle: 'Utility payments and bill history',
                      onTap: onOpenBills,
                    ),
                    const Divider(height: 1),
                  ],
                  _cell(
                    icon: Icons.groups_2_outlined,
                    title: 'Group pay',
                    subtitle: 'Split and collect payments with friends',
                    onTap: onOpenGroupPay,
                  ),
                  const Divider(height: 1),
                  _cell(
                    icon: Icons.history,
                    title: 'Wallet history',
                    subtitle: 'Transactions, filters, and exports',
                    onTap: onOpenHistory,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: V2Tokens.textSecondary,
            fontWeight: FontWeight.w700,
          ),
    );
  }

  Widget _cell({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    bool enabled = true,
  }) {
    final color = enabled ? V2Tokens.textPrimary : V2Tokens.textSecondary;
    return ListTile(
      enabled: enabled,
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: const TextStyle(fontSize: 12),
            ),
      trailing: const Icon(Icons.chevron_right),
      onTap: enabled ? onTap : null,
    );
  }
}
