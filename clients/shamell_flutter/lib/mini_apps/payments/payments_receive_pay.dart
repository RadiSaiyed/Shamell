import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'payments_receive.dart';
import 'payments_scan.dart';

/// WeChat-style combined "Receive & Pay" screen.
class ReceivePayPage extends StatelessWidget {
  final String baseUrl;
  final String fromWalletId;

  const ReceivePayPage({
    super.key,
    required this.baseUrl,
    required this.fromWalletId,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final isAr = l.isArabic;
    final theme = Theme.of(context);
    final scaffoldBg = theme.scaffoldBackgroundColor;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: theme.appBarTheme.backgroundColor ?? scaffoldBg,
          title: Text(isAr ? 'استلام ودفع' : 'Receive & pay'),
          bottom: TabBar(
            tabs: [
              Tab(
                text: isAr ? 'استلام' : 'Receive',
              ),
              Tab(
                text: isAr ? 'الدفع' : 'Pay',
              ),
            ],
          ),
        ),
        backgroundColor: scaffoldBg,
        body: TabBarView(
          children: [
            PaymentReceiveTab(
              baseUrl: baseUrl,
              fromWalletId: fromWalletId,
              compact: true,
            ),
            PaymentScanTab(
              baseUrl: baseUrl,
              fromWalletId: fromWalletId,
            ),
          ],
        ),
      ),
    );
  }
}
