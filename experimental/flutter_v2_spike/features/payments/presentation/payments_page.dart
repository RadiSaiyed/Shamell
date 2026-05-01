import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../main.dart' show LoginPage;

import '../../../design/components/v2_primary_button.dart';
import '../../../design/components/v2_status_panel.dart';
import '../../../design/components/v2_surface_card.dart';
import '../../../design/tokens.dart';
import 'payments_controller.dart';

class PaymentsPage extends StatefulWidget {
  final PaymentsController controller;
  final String walletId;
  final bool showAppBar;
  final String appBarTitle;
  final VoidCallback? onOpenFullPaymentsWorkspace;

  const PaymentsPage({
    super.key,
    required this.controller,
    required this.walletId,
    this.showAppBar = false,
    this.appBarTitle = 'Wallet',
    this.onOpenFullPaymentsWorkspace,
  });

  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  final TextEditingController _toWalletController = TextEditingController();
  final TextEditingController _amountController =
      TextEditingController(text: '10000');
  bool _reauthScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_listener);
    unawaited(widget.controller.bindWallet(widget.walletId));
  }

  @override
  void dispose() {
    widget.controller.removeListener(_listener);
    _toWalletController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PaymentsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.walletId.trim() != widget.walletId.trim()) {
      unawaited(widget.controller.bindWallet(widget.walletId));
    }
  }

  void _listener() {
    if (!mounted) return;
    final controller = widget.controller;
    if (controller.sessionResetRequired && !_reauthScheduled) {
      _reauthScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      });
    }
    setState(() {});
  }

  Future<void> _submit() async {
    final amount = int.tryParse(_amountController.text.trim()) ?? 0;
    await widget.controller.transfer(
      fromWalletId: widget.walletId,
      toWalletId: _toWalletController.text,
      amountCents: amount,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final balanceText = (c.balanceCents / 100.0).toStringAsFixed(2);
    return Scaffold(
      appBar:
          widget.showAppBar ? AppBar(title: Text(widget.appBarTitle)) : null,
      backgroundColor: V2Tokens.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(V2Tokens.spacingLg),
          child: ListView(
            children: [
              V2SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Wallet balance'),
                    const SizedBox(height: V2Tokens.spacingSm),
                    Text(
                      '$balanceText SYP',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: V2Tokens.spacingXs),
                    Text(
                      'Wallet: ${widget.walletId}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: V2Tokens.textSecondary,
                          ),
                    ),
                    if (c.isLoadingBalance) ...[
                      const SizedBox(height: V2Tokens.spacingMd),
                      const LinearProgressIndicator(minHeight: 2),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: V2Tokens.spacingLg),
              V2SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _toWalletController,
                      decoration: const InputDecoration(
                        labelText: 'Destination wallet',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: V2Tokens.spacingMd),
                    TextField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Amount (cents)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (c.error.isNotEmpty) ...[
                      const SizedBox(height: V2Tokens.spacingMd),
                      V2StatusPanel(
                        icon: Icons.error_outline,
                        title: 'Transfer failed',
                        message: c.error,
                        color: V2Tokens.critical,
                      ),
                    ],
                    if (c.success.isNotEmpty) ...[
                      const SizedBox(height: V2Tokens.spacingMd),
                      V2StatusPanel(
                        icon: Icons.check_circle_outline,
                        title: 'Success',
                        message: c.success,
                        color: V2Tokens.brand,
                      ),
                    ],
                    const SizedBox(height: V2Tokens.spacingLg),
                    SizedBox(
                      width: double.infinity,
                      child: V2PrimaryButton(
                        label: 'Transfer',
                        busy: c.busy,
                        onPressed:
                            widget.walletId.trim().isEmpty ? null : _submit,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.onOpenFullPaymentsWorkspace != null) ...[
                const SizedBox(height: V2Tokens.spacingLg),
                V2SurfaceCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.extension_outlined),
                    title: const Text('Open full payments'),
                    subtitle: const Text(
                        'Topup, scan, requests, bills, history, and receive code'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: widget.onOpenFullPaymentsWorkspace,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
