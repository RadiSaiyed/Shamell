import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'design_tokens.dart';
import 'glass.dart';
import 'l10n.dart';
import 'format.dart' show fmtCents;
import 'payments_shell.dart';
import 'history_page.dart';
import 'payments_send.dart' show PayActionButton;
import '../main.dart' show AppBG;

Future<Map<String, String>> _hdrPayDash({bool json = false}) async {
  final sp = await SharedPreferences.getInstance();
  final h = <String, String>{};
  if (json) h['content-type'] = 'application/json';
  final cookie = sp.getString('sa_cookie');
  if (cookie != null && cookie.isNotEmpty) {
    h['sa_cookie'] = cookie;
  }
  return h;
}

class PaymentsMultiLevelPage extends StatefulWidget {
  final String baseUrl;
  const PaymentsMultiLevelPage({super.key, required this.baseUrl});

  @override
  State<PaymentsMultiLevelPage> createState() => _PaymentsMultiLevelPageState();
}

class _PaymentsMultiLevelPageState extends State<PaymentsMultiLevelPage> {
  bool _loading = true;
  String _error = '';

  String _phone = '';
  bool _isAdmin = false;
  bool _isSuperadmin = false;
  List<String> _roles = const [];
  List<String> _operatorDomains = const [];

  String _walletId = '';
  int? _balanceCents;
  String _currency = 'SYP';
  int _recentCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final uri = Uri.parse('${widget.baseUrl.trim()}/me/home_snapshot');
      final r = await http.get(uri, headers: await _hdrPayDash());
      if (r.statusCode != 200) {
        setState(() {
          _error = '${r.statusCode}: ${r.body}';
        });
      } else {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final roles = j['roles'];
        final ops = j['operator_domains'];
        final wallet = j['wallet'];
        final txns = j['txns'];
        setState(() {
          _phone = (j['phone'] ?? '').toString();
          _isAdmin = j['is_admin'] == true;
          _isSuperadmin = j['is_superadmin'] == true;
          _roles = roles is List ? roles.map((e) => e.toString()).toList() : const [];
          _operatorDomains = ops is List ? ops.map((e) => e.toString()).toList() : const [];
          if (wallet is Map<String, dynamic>) {
            final id = (wallet['wallet_id'] ?? wallet['id'] ?? '').toString();
            _walletId = id;
            final cents = wallet['balance_cents'];
            if (cents is int) _balanceCents = cents;
            final cur = (wallet['currency'] ?? '').toString();
            if (cur.isNotEmpty) _currency = cur;
          }
          if (txns is List) {
            _recentCount = txns.length;
          }
        });
      }
    } catch (e) {
      setState(() {
        _error = 'error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _openPayments() {
    if (_walletId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentsPage(widget.baseUrl, _walletId, 'payments-multi'),
      ),
    );
  }

  void _openHistory() {
    if (_walletId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HistoryPage(baseUrl: widget.baseUrl, walletId: _walletId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final bg = const AppBG();
    final body = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Icon(Icons.account_balance_wallet_outlined,
                color: Tokens.colorPayments),
            const SizedBox(width: 8),
            const Text(
              'Payments – Enduser, Operator, Admin, Superadmin',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (_phone.isNotEmpty)
          Text(
            'Phone: $_phone',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .70),
            ),
          ),
        const SizedBox(height: 12),
        if (_loading)
          const LinearProgressIndicator(minHeight: 2),
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 16),
        // Enduser card
        GlassPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_outline),
                  const SizedBox(width: 8),
                  Text(
                    l.isArabic ? 'المستخدم النهائي' : 'Enduser',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _walletId.isEmpty
                    ? (l.isArabic ? 'لم يتم إنشاء محفظة بعد' : 'No wallet created yet')
                    : '${l.homeWallet}: $_walletId',
              ),
              const SizedBox(height: 4),
              Text(
                _balanceCents == null
                    ? (l.isArabic ? 'الرصيد غير معروف' : 'Balance unknown')
                    : '${fmtCents(_balanceCents!)} $_currency',
              ),
              const SizedBox(height: 4),
              Text(
                _recentCount == 0
                    ? (l.isArabic ? 'لا توجد مدفوعات حديثة' : 'No recent payments')
                    : (l.isArabic
                        ? '$_recentCount عملية حديثة'
                        : '$_recentCount recent payment(s)'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .70),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: PayActionButton(
                      icon: Icons.account_balance_wallet_outlined,
                      label: l.homePayments,
                      onTap: _walletId.isEmpty ? () {} : _openPayments,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PayActionButton(
                      icon: Icons.history,
                      label: l.viewAll,
                      onTap: _walletId.isEmpty ? () {} : _openHistory,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Operator card
        GlassPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.support_agent_outlined),
                  const SizedBox(width: 8),
                  Text(
                    l.isArabic ? 'المشغل (Payments)' : 'Operator (Payments)',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                l.isArabic ? 'الأدوار' : 'Roles',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final r in _roles.where((r) => r == 'seller' || r.startsWith('operator_')))
                    Chip(
                      label: Text(r),
                      backgroundColor: Tokens.colorPayments.withValues(alpha: .14),
                      shape: StadiumBorder(
                        side: BorderSide(
                          color: Tokens.colorPayments.withValues(alpha: .9),
                        ),
                      ),
                    ),
                  if (!_roles.any((r) => r == 'seller' || r.startsWith('operator_')))
                    Text(
                      l.isArabic
                          ? 'لا توجد أدوار مشغل Payments'
                          : 'No Payments operator roles for this phone',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .70),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                l.isArabic
                    ? 'استخدم Merchant POS ولوحة المشغل لمتابعة المدفوعات للتجار.'
                    : 'Use Merchant POS and operator consoles to handle merchant payments.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .70),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Admin card
        GlassPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.admin_panel_settings_outlined),
                  const SizedBox(width: 8),
                  Text(
                    l.isArabic ? 'المدير (Payments)' : 'Admin (Payments)',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _isAdmin
                    ? (l.isArabic ? 'هذا الهاتف لديه صلاحيات المدير.' : 'This phone has admin rights.')
                    : (l.isArabic ? 'لا توجد صلاحيات المدير.' : 'No admin rights for this phone.'),
              ),
              const SizedBox(height: 8),
              Text(
                l.isArabic
                    ? 'استخدم وحدة Ops Admin لتقارير Payments وعمليات التصدير.'
                    : 'Use the Ops Admin console for payments reporting and exports.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .70),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Superadmin card
        GlassPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.security_outlined),
                  const SizedBox(width: 8),
                  Text(
                    'Superadmin (Payments)',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _isSuperadmin
                    ? 'Superadmin: full control over roles, guardrails and finance for Payments.'
                    : 'This phone is not Superadmin; Superadmin sees all roles and guardrails.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .70),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Roles: ${_roles.join(", ")}',
              ),
              const SizedBox(height: 4),
              Text(
                'Operator domains: ${_operatorDomains.join(", ")}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .70),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payments – 4 levels'),
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          bg,
          Positioned.fill(
            child: SafeArea(
              child: body,
            ),
          ),
        ],
      ),
    );
  }
}
