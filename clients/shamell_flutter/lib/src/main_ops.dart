part of '../main.dart';

class RolesInfoPage extends StatelessWidget {
  const RolesInfoPage({super.key});
  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final tiles = <Map<String, dynamic>>[
      {
        'mode': AppMode.user,
        'title': l.isArabic ? 'مستخدم' : 'User',
        'desc': l.isArabic
            ? 'المستخدم الافتراضي للتطبيق – يدفع ويتلقى المدفوعات ويستخدم خدمات التنقل والخدمات الأخرى.'
            : 'Default app user – pays, receives payments and uses mobility and other services.'
      },
      {
        'mode': AppMode.operator,
        'title': l.isArabic ? 'مشغل' : 'Operator',
        'desc': l.isArabic
            ? 'يستخدم أدوات تشغيل احترافية (مثل الحافلات) ويدير الحجوزات الحية.'
            : 'Uses professional operator tools (e.g. bus) and manages live bookings.'
      },
      {
        'mode': AppMode.admin,
        'title': l.isArabic ? 'مسؤول' : 'Admin',
        'desc': l.isArabic
            ? 'لديه صلاحيات واسعة في المكتب الخلفي وإدارة المخاطر (معظمها عبر واجهة الويب).'
            : 'Has extended backoffice and risk administration capabilities (mostly via web admin).'
      },
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(l.rolesOverviewTitle),
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView.separated(
            itemCount: tiles.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final t = tiles[index];
              final AppMode mode = t['mode'] as AppMode;
              final ColorScheme c = Theme.of(context).colorScheme;
              Color chipBg;
              switch (mode) {
                case AppMode.operator:
                  chipBg = Colors.amber.withValues(alpha: .20);
                  break;
                case AppMode.admin:
                  chipBg = Colors.redAccent.withValues(alpha: .18);
                  break;
                case AppMode.user:
                  chipBg = Tokens.colorPayments.withValues(alpha: .20);
                  break;
                case AppMode.auto:
                default:
                  chipBg = c.primary.withValues(alpha: .18);
                  break;
              }
              final icon = appModeIcon(mode);
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? c.surface.withValues(alpha: .92)
                      : c.surface.withValues(alpha: .96),
                  borderRadius: Tokens.radiusLg,
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: chipBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            t['title'] as String,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t['desc'] as String,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class TopupPage extends StatefulWidget {
  final String baseUrl;
  final bool triggerScanOnOpen;
  const TopupPage(this.baseUrl, {super.key, this.triggerScanOnOpen = false});
  @override
  State<TopupPage> createState() => _TopupPageState();
}

class _TopupPageState extends State<TopupPage> {
  final amtCtrl = TextEditingController(text: '10000');
  final walletCtrl = TextEditingController();
  String out = '';
  String topupPayload = '';
  String _curSym = 'SYP';
  @override
  void initState() {
    super.initState();
    _load();
    if (widget.triggerScanOnOpen) {
      Future.microtask(_scanTopupAndDo);
    }
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    walletCtrl.text = sp.getString('wallet_id') ?? '';
    final cs = sp.getString('currency_symbol');
    if (cs != null && cs.isNotEmpty) {
      _curSym = cs;
    }
    setState(() {});
  }

  Future<void> _doTopup() async {
    setState(() => out = '...');
    try {
      final w = walletCtrl.text.trim();
      final amt =
          double.tryParse(amtCtrl.text.trim().replaceAll(',', '.')) ?? 0;
      if (w.isEmpty || amt <= 0) {
        setState(() => out = 'Please check wallet and amount');
        return;
      }
      final uri = Uri.parse('${widget.baseUrl}/payments/wallets/' +
          Uri.encodeComponent(w) +
          '/topup');
      final headers = (await _hdr(json: true))
        ..addAll({
          'Idempotency-Key': 'top-${DateTime.now().millisecondsSinceEpoch}'
        });
      final body = jsonEncode({'amount': double.parse(amt.toStringAsFixed(2))});
      final r = await http.post(uri, headers: headers, body: body);
      setState(() => out = '${r.statusCode}: ${r.body}');
      if (r.statusCode >= 500) {
        await OfflineQueue.enqueue(OfflineTask(
            id: 'top-${DateTime.now().millisecondsSinceEpoch}',
            method: 'POST',
            url: uri.toString(),
            headers: headers,
            body: body,
            tag: 'payments_topup',
            createdAt: DateTime.now().millisecondsSinceEpoch));
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Offline: queued top‑up')));
      }
    } catch (e) {
      final w = walletCtrl.text.trim();
      final amt =
          double.tryParse(amtCtrl.text.trim().replaceAll(',', '.')) ?? 0;
      final uri = Uri.parse('${widget.baseUrl}/payments/wallets/' +
          Uri.encodeComponent(w) +
          '/topup');
      final headers = (await _hdr(json: true))
        ..addAll({
          'Idempotency-Key': 'top-${DateTime.now().millisecondsSinceEpoch}'
        });
      final body = jsonEncode({'amount': double.parse(amt.toStringAsFixed(2))});
      await OfflineQueue.enqueue(OfflineTask(
          id: 'top-${DateTime.now().millisecondsSinceEpoch}',
          method: 'POST',
          url: uri.toString(),
          headers: headers,
          body: body,
          tag: 'payments_topup',
          createdAt: DateTime.now().millisecondsSinceEpoch));
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Offline saved: Top‑up')));
      setState(() => out = 'Queued (offline)');
    }
  }

  void _genTopupQR() {
    final w = walletCtrl.text.trim();
    final a = int.tryParse(amtCtrl.text.trim()) ?? 0;
    if (w.isEmpty) {
      setState(() => out = 'Wallet required');
      return;
    }
    setState(() => topupPayload =
        'TOPUP|wallet=' + Uri.encodeComponent(w) + (a > 0 ? '|amount=$a' : ''));
  }

  Future<void> _scanTopupAndDo() async {
    final res = await Navigator.push<String?>(
        context, MaterialPageRoute(builder: (_) => const ScanPage()));
    if (res == null) return;
    try {
      final parts = res.split('|');
      if (parts.isEmpty) return;
      final kind = parts.first.toUpperCase();
      if (kind != 'TOPUP') return;
      final map = <String, String>{};
      for (final p in parts.skip(1)) {
        final kv = p.split('=');
        if (kv.length == 2) map[kv[0]] = Uri.decodeComponent(kv[1]);
      }
      final amount = int.tryParse(map['amount'] ?? '0') ?? 0;
      if (map['code'] != null && map['sig'] != null) {
        // Voucher redeem flow
        final sp = await SharedPreferences.getInstance();
        final toWallet = sp.getString('wallet_id') ?? '';
        if (toWallet.isEmpty) {
          if (mounted) setState(() => out = 'No wallet in session');
          return;
        }
        final uri = Uri.parse('${widget.baseUrl}/topup/redeem');
        final headers = await _hdr(json: true);
        final body = jsonEncode({
          'code': map['code'],
          'amount_cents': amount,
          'sig': map['sig'],
          'to_wallet_id': toWallet
        });
        final r = await http.post(uri, headers: headers, body: body);
        setState(() => out = '${r.statusCode}: ${r.body}');
        return;
      }
      if (map['wallet'] != null) {
        walletCtrl.text = map['wallet']!;
      }
      if (amount > 0) {
        amtCtrl.text = amount.toString();
      }
      setState(() {});
      await _doTopup();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final content = ListView(padding: const EdgeInsets.all(16), children: [
      TextField(
          controller: walletCtrl,
          decoration: const InputDecoration(labelText: 'Wallet ID')),
      const SizedBox(height: 8),
      TextField(
          controller: amtCtrl,
          decoration: const InputDecoration(labelText: 'Amount (SYP)'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true)),
      const SizedBox(height: 4),
      Builder(builder: (_) {
        final c = int.tryParse(amtCtrl.text.trim()) ?? 0;
        final s = c > 0 ? '≈ ${fmtCents(c)} ${_curSym}' : '';
        return Align(
            alignment: Alignment.centerLeft,
            child: Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(s,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.white70))));
      }),
      Wrap(spacing: 8, runSpacing: 8, children: [
        PayActionButton(
            icon: Icons.qr_code_scanner,
            label: 'Scan & Topup',
            onTap: _scanTopupAndDo),
        PayActionButton(
            icon: Icons.qr_code_2,
            label: 'Generate Topup QR',
            onTap: _genTopupQR)
      ]),
      const SizedBox(height: 12),
      if (topupPayload.isNotEmpty)
        Center(
            child: Column(children: [
          Text(topupPayload, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          QrImageView(data: topupPayload, size: 220)
        ])),
      SelectableText(out),
    ]);
    return DomainPageScaffold(
      background: const AppBG(),
      title: l.homeTopup,
      child: content,
      scrollable: true,
    );
  }
}

// Topup Kiosk: create and print batches of topup vouchers
class TopupKioskPage extends StatefulWidget {
  final String baseUrl;
  const TopupKioskPage(this.baseUrl, {super.key});
  @override
  State<TopupKioskPage> createState() => _TopupKioskPageState();
}

// Ops hub page: consolidate operator/admin tools under one icon
class OpsPage extends StatelessWidget {
  final String baseUrl;
  const OpsPage(this.baseUrl, {super.key});
  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    Widget btn(IconData icon, String label, VoidCallback onTap) {
      return SizedBox(
        width: 240,
        child: PayActionButton(icon: icon, label: label, onTap: onTap),
      );
    }

    void openWeb(String path, {String? title}) {
      final baseUri = Uri.tryParse(baseUrl);
      final uri = baseUri?.resolve(path) ??
          Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WeChatWebViewPage(
            initialUri: uri,
            baseUri: baseUri,
            initialTitle: title,
          ),
        ),
      );
	    }

    final nativeTiles = <Widget>[
      btn(Icons.directions_bus_filled_outlined, 'Bus Operator', () {
        openWeb(
          '/bus/admin',
          title: l.isArabic ? 'إدارة الباص' : 'Bus admin',
        );
      }),
      btn(Icons.local_printshop_outlined, 'Topup Kiosk', () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => TopupKioskPage(baseUrl)),
        );
      }),
      btn(Icons.health_and_safety_outlined, l.opsSystemStatus, () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SystemStatusPage(baseUrl)),
        );
      }),
    ];
    final webTiles = <Widget>[
      btn(Icons.shield_moon_outlined, 'Risk Admin', () {
        launchWithSession(Uri.parse('$baseUrl/admin/risk'));
      }),
      btn(Icons.file_download_outlined, 'Admin Exports', () {
        launchWithSession(Uri.parse('$baseUrl/admin/exports'));
      }),
      btn(Icons.manage_accounts_outlined, 'Topup Sellers', () {
        launchWithSession(Uri.parse('$baseUrl/admin/topup-sellers'));
      }),
      btn(Icons.rule_folder_outlined, 'Mini‑program review', () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MiniProgramsReviewPage(baseUrl: baseUrl),
          ),
        );
      }),
    ];
    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l.opsTitle),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: nativeTiles,
        ),
        const SizedBox(height: 16),
        const Text('Web Admin (opens browser)',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: webTiles,
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: Text(l.opsTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: content,
        ),
      ),
    );
  }
}

class OperatorDashboardPage extends StatefulWidget {
  final String baseUrl;
  final List<String>? operatorDomains;
  const OperatorDashboardPage(this.baseUrl, {super.key, this.operatorDomains});
  @override
  State<OperatorDashboardPage> createState() => _OperatorDashboardPageState();
}

class _OperatorDashboardPageState extends State<OperatorDashboardPage> {
  List<String> _domains = const [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // If domains are provided (e.g. from login), use them; otherwise load from /me/home_snapshot.
    final provided = widget.operatorDomains;
    if (provided != null) {
      setState(() {
        _domains = List<String>.from(provided);
        _loading = false;
      });
      return;
    }
    try {
      final uri = Uri.parse('${widget.baseUrl}/me/home_snapshot');
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        final opDomains = (body['operator_domains'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[];
        setState(() {
          _domains = opDomains;
          _loading = false;
        });
      } else if (r.statusCode == 404) {
        // Legacy BFF without snapshot endpoint: treat as "no operator domains"
        // but avoid showing a hard error screen.
        setState(() {
          _domains = const <String>[];
          _loading = false;
          _error = '';
        });
      } else {
        setState(() {
          _error = 'Failed to load operator profile (${r.statusCode}).';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error loading operator profile: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    Widget btn(IconData icon, String label, VoidCallback onTap) {
      return SizedBox(
        width: 240,
        child: PayActionButton(icon: icon, label: label, onTap: onTap),
      );
    }

    void openWeb(String path, {String? title}) {
      final baseUri = Uri.tryParse(widget.baseUrl);
      final uri = baseUri?.resolve(path) ??
          Uri.parse('${widget.baseUrl.replaceAll(RegExp(r'/+$'), '')}$path');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WeChatWebViewPage(
            initialUri: uri,
            baseUri: baseUri,
            initialTitle: title,
          ),
        ),
      );
	    }

    final tiles = <Widget>[];
    if (_domains.contains('bus')) {
      tiles.add(btn(
        Icons.directions_bus_filled_outlined,
        l.isArabic ? 'مشغل الباص' : 'Bus Operator',
        () {
          openWeb(
            '/bus/admin',
            title: l.isArabic ? 'إدارة الباص' : 'Bus admin',
          );
        },
      ));
    }

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error.isNotEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: StatusBanner.error(_error, dense: false),
      );
    } else if (tiles.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: StatusBanner.error(
          l.isArabic
              ? 'لا توجد صلاحيات مشغل مرتبطة بهذا الرقم. يرجى التواصل مع المشرف.'
              : 'No operator domains assigned to this phone. Please contact an admin.',
          dense: false,
        ),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l.operatorDashboardTitle),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tiles,
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.operatorDashboardTitle)),
      body: SafeArea(child: body),
    );
  }
}

class AdminDashboardPage extends StatelessWidget {
  final String baseUrl;
  const AdminDashboardPage(this.baseUrl, {super.key});
  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    Widget btn(IconData icon, String label, VoidCallback onTap) {
      return SizedBox(
        width: 240,
        child: PayActionButton(icon: icon, label: label, onTap: onTap),
      );
    }

    final coreTiles = <Widget>[
      btn(Icons.health_and_safety_outlined, l.opsSystemStatus, () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => SystemStatusPage(baseUrl)));
      }),
      btn(Icons.layers_outlined, l.opsTitle, () {
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => OpsPage(baseUrl)));
      }),
    ];
    final webTiles = <Widget>[
      btn(Icons.dashboard_outlined, 'Admin overview (web)', () {
        launchWithSession(Uri.parse('$baseUrl/admin/overview'));
      }),
      btn(Icons.file_download_outlined, 'Admin exports (web)', () {
        launchWithSession(Uri.parse('$baseUrl/admin/exports'));
      }),
      btn(Icons.manage_accounts_outlined, 'Topup sellers (web)', () {
        launchWithSession(Uri.parse('$baseUrl/admin/topup-sellers'));
      }),
    ];
    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l.adminDashboardTitle),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: coreTiles,
        ),
        const SizedBox(height: 16),
        const Text('Admin web consoles',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: webTiles,
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: Text(l.adminDashboardTitle)),
      body: SafeArea(child: content),
    );
  }
}

class SuperadminDashboardPage extends StatefulWidget {
  final String baseUrl;
  const SuperadminDashboardPage(this.baseUrl, {super.key});

  @override
  State<SuperadminDashboardPage> createState() =>
      _SuperadminDashboardPageState();
}

class _SuperadminDashboardPageState extends State<SuperadminDashboardPage> {
  String _financeRange = '24h'; // 24h, 7d, 30d

  String get baseUrl => widget.baseUrl;

  Future<Map<String, dynamic>> _fetchStats() async {
    try {
      final uri = Uri.parse('$baseUrl/admin/stats');
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        return j;
      }
    } catch (_) {}
    return const {};
  }

  Future<Map<String, dynamic>> _fetchFinanceStats() async {
    try {
      // Compute time range on client side.
      DateTime now = DateTime.now().toUtc();
      Duration d;
      switch (_financeRange) {
        case '7d':
          d = const Duration(days: 7);
          break;
        case '30d':
          d = const Duration(days: 30);
          break;
        case '24h':
        default:
          d = const Duration(days: 1);
      }
      final start = now.subtract(d);
      String iso(DateTime dt) =>
          dt.toIso8601String().replaceFirst(RegExp(r'\\+00:00\$'), 'Z');
      final params = {
        'from_iso': iso(start),
        'to_iso': iso(now),
      };
      final uri = Uri.parse('$baseUrl/admin/finance_stats')
          .replace(queryParameters: params);
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        return j;
      }
    } catch (_) {}
    return const {};
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    Widget superTile(
        {required IconData icon,
        required String label,
        required Color tint,
        required VoidCallback onTap}) {
      return SizedBox(
        width: 240,
        child: PayActionButton(
          icon: icon,
          label: label,
          onTap: onTap,
          tint: tint,
        ),
      );
    }

    Widget btn(IconData icon, String label, VoidCallback onTap, {Color? tint}) {
      return SizedBox(
        width: 240,
        child:
            PayActionButton(icon: icon, label: label, onTap: onTap, tint: tint),
      );
    }

    final domainTiles = <Widget>[
      superTile(
        icon: Icons.account_balance_wallet_outlined,
        label: 'Payment',
        tint: Tokens.colorPayments,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PaymentsMultiLevelPage(
                api: SuperappAPI.light(baseUrl: baseUrl),
              ),
            ),
          );
        },
      ),
      superTile(
        icon: Icons.directions_bus_filled_outlined,
        label: 'Bus',
        tint: Tokens.colorBus,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MiniProgramPage(
                id: 'bus',
                baseUrl: baseUrl,
                walletId: '',
                deviceId: 'superadmin',
              ),
            ),
          );
        },
      ),
    ];

    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l.superadminDashboardTitle),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: domainTiles,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            ChoiceChip(
              label: const Text('24h'),
              selected: _financeRange == '24h',
              onSelected: (_) {
                setState(() => _financeRange = '24h');
              },
            ),
            const SizedBox(width: 6),
            ChoiceChip(
              label: const Text('7d'),
              selected: _financeRange == '7d',
              onSelected: (_) {
                setState(() => _financeRange = '7d');
              },
            ),
            const SizedBox(width: 6),
            ChoiceChip(
              label: const Text('30d'),
              selected: _financeRange == '30d',
              onSelected: (_) {
                setState(() => _financeRange = '30d');
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        FutureBuilder<Map<String, dynamic>>(
          future: _fetchFinanceStats(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SizedBox.shrink();
            }
            final data = snap.data ?? const {};
            if (data.isEmpty) {
              return const SizedBox.shrink();
            }
            final totalTxns = data['total_txns'] ?? 0;
            final totalFeeCents = data['total_fee_cents'] ?? 0;
            final fromIso = (data['from_iso'] ?? '') as String;
            final toIso = (data['to_iso'] ?? '') as String;
            final feeStr = totalFeeCents is int
                ? '${(totalFeeCents / 100.0).toStringAsFixed(2)} SYP'
                : totalFeeCents.toString();

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GlassPanel(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Finance overview',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Txns: $totalTxns  ·  Fees: $feeStr',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (fromIso.isNotEmpty || toIso.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Range: ${fromIso.isNotEmpty ? fromIso : '?'} → ${toIso.isNotEmpty ? toIso : '?'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
        FutureBuilder<Map<String, dynamic>>(
          future: _fetchStats(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SizedBox.shrink();
            }
            final data = snap.data ?? const {};
            final samples = (data['samples'] as Map?) ?? const {};
            final actions = (data['actions'] as Map?) ?? const {};
            final guardrails = (data['guardrails'] as Map?) ?? const {};
            final totalEvents = data['total_events'] ?? 0;

            String lineFor(String metric, String label) {
              final m = samples[metric];
              if (m is Map) {
                final cnt = m['count'] ?? 0;
                final avg = m['avg_ms'] ?? 0.0;
                return '$label: avg ${avg.toStringAsFixed(0)} ms · count ${cnt.toString()}';
              }
              return '';
            }

            final lines = <String>[
              lineFor('pay_send_ms', 'Payments send'),
              lineFor('bus_book_ms', 'Bus booking'),
            ].where((s) => s.isNotEmpty).toList();

            if (lines.isEmpty && (totalEvents == 0 || totalEvents == '0')) {
              return const SizedBox.shrink();
            }

            int _intFor(String key) {
              final v = actions[key];
              if (v is int) return v;
              if (v is num) return v.toInt();
              if (v is String) {
                return int.tryParse(v) ?? 0;
              }
              return 0;
            }

            Widget domainCard(
                IconData icon, String title, String line1, String? line2) {
              return Container(
                width: 160,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surface
                      .withValues(alpha: .96),
                  borderRadius: Tokens.radiusMd,
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(line1, style: Theme.of(context).textTheme.bodySmall),
                    if (line2 != null && line2.isNotEmpty)
                      Text(line2, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              );
            }

            final payOk = _intFor('pay_send_ok');
            final payFail = _intFor('pay_send_fail');
            final busOk = _intFor('bus_book_ok');
            final busFail = _intFor('bus_book_fail');

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GlassPanel(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'System overview',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        domainCard(
                          Icons.account_balance_wallet_outlined,
                          'Payments',
                          'ok: $payOk · fail: $payFail',
                          'guardrails: ${(guardrails.keys.where((k) => k.toString().contains('pay') || k.toString().contains('wallet')).length)} keys',
                        ),
                        domainCard(
                          Icons.directions_bus_filled,
                          'Mobility',
                          'bus ok/fail: $busOk/$busFail',
                          null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Key stats (last $totalEvents events)',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    if (lines.isEmpty)
                      Text(
                        'No detailed latency metrics yet.',
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    else
                      ...lines.map((s) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: Text(s,
                                style: Theme.of(context).textTheme.bodySmall),
                          )),
                    const SizedBox(height: 6),
                    if (actions.isNotEmpty) ...[
                      const Divider(height: 12),
                      Text(
                        'Recent actions (counts)',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Builder(
                        builder: (_) {
                          String fmt(String key, String label) {
                            final v = actions[key];
                            if (v == null) return '';
                            return '$label: ${v.toString()}';
                          }

	                          final actionLines = <String>[
	                            fmt('pay_send_ok', 'Payments ok'),
	                            fmt('pay_send_fail', 'Payments fail'),
	                            fmt('bus_book_ok', 'Bus ok'),
	                            fmt('bus_book_fail', 'Bus fail'),
	                          ].where((s) => s.isNotEmpty).toList();
                          if (actionLines.isEmpty) {
                            return Text(
                              'No action counts yet.',
                              style: Theme.of(context).textTheme.bodySmall,
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: actionLines
                                .map((s) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 1),
                                      child: Text(s,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall),
                                    ))
                                .toList(),
                          );
                        },
                      ),
                    ],
                    if (guardrails.isNotEmpty) ...[
                      const Divider(height: 16),
                      Builder(
                        builder: (_) {
                          int total = 0;
                          int risk = 0;
                          int payments = 0;
                          int mobility = 0;
                          guardrails.forEach((k, vRaw) {
                            final v = (vRaw as int? ?? 0);
                            total += v;
                            final key = k.toString();
                            if (key.contains('risk') || key.contains('deny')) {
                              risk += v;
                            }
                            if (key.contains('pay') ||
                                key.contains('wallet') ||
                                key.contains('alias')) {
                              payments += v;
                            }
                            if (key.contains('bus')) {
                              mobility += v;
                            }
                          });
                          final txt = [
                            'Guardrail hits: $total',
                            if (risk > 0) 'risk/deny: $risk',
                            if (payments > 0) 'payments: $payments',
                            if (mobility > 0) 'mobility: $mobility',
                          ].join(' · ');
                          return StatusBanner.info(txt, dense: true);
                        },
                      ),
                    ],
                    if (guardrails.isNotEmpty) ...[
                      const Divider(height: 16),
                      Text(
                        'Guardrails (last ${guardrails.values.fold<int>(0, (p, v) => p + (v as int? ?? 0))} hits)',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Builder(
                        builder: (_) {
                          final lines = guardrails.entries
                              .map((e) => '${e.key}: ${e.value}')
                              .toList();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: lines
                                .map((s) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 1),
                                      child: Text(s,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall),
                                    ))
                                .toList(),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        Text(
          l.isArabic ? 'إدارة الصلاحيات' : 'Role management',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        GlassPanel(
          padding: const EdgeInsets.all(12),
		          child: Text(
		            l.isArabic
		                ? 'أدوار المشغلين (الباص وغيرها) تُدار الآن داخل كل تطبيق نطاقي لتبقى لوحة Superadmin بسيطة ومركزة على الإحصاءات العامة.'
		                : 'Operator roles are now managed inside each domain dashboard so this Superadmin home stays focused on global stats.',
		            style: Theme.of(context).textTheme.bodySmall?.copyWith(
		                  color: Theme.of(context)
		                      .colorScheme
		                      .onSurface
                      .withValues(alpha: .80),
                ),
          ),
        ),
        const Text('Core dashboards',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            btn(Icons.health_and_safety_outlined, l.opsSystemStatus, () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => SystemStatusPage(baseUrl)));
            }, tint: Tokens.colorPayments),
            btn(Icons.dashboard_customize_outlined, l.operatorDashboardTitle,
                () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => OperatorDashboardPage(baseUrl)));
            }, tint: Tokens.colorBus),
	            btn(Icons.admin_panel_settings_outlined, l.adminDashboardTitle, () {
	              Navigator.push(
	                  context,
	                  MaterialPageRoute(
	                      builder: (_) => AdminDashboardPage(baseUrl)));
	            }, tint: Colors.redAccent),
	            btn(Icons.layers_outlined, l.opsTitle, () {
	              Navigator.push(
	                  context, MaterialPageRoute(builder: (_) => OpsPage(baseUrl)));
	            }, tint: const Color(0xFF64748B)),
	          ],
	        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: Text(l.superadminDashboardTitle)),
      body: SafeArea(child: content),
    );
  }
}

class _TopupKioskPageState extends State<TopupKioskPage> {
  int _denom = 10000; // SYP major
  final _countCtrl = TextEditingController(text: '10');
  final _noteCtrl = TextEditingController();
  String out = '';
  String _batchId = '';
  List<dynamic> _items = [];
  List<dynamic> _batches = [];
  bool _mineOnly = true;

  Future<void> _createBatch() async {
    setState(() => out = '...');
    try {
      final count = int.tryParse(_countCtrl.text.trim()) ?? 0;
      if (count <= 0) {
        setState(() => out = 'Count must be > 0');
        return;
      }
      final uri = Uri.parse('${widget.baseUrl}/topup/batch_create');
      final r = await http.post(uri,
          headers: await _hdr(json: true),
          body: jsonEncode({
            'amount': _denom,
            'count': count,
            'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim()
          }));
      final j = jsonDecode(r.body);
      if (r.statusCode == 200) {
        _batchId = (j['batch_id'] ?? '').toString();
        _items = (j['items'] as List?) ?? [];
        setState(() => out = 'Created batch $_batchId');
      } else {
        setState(() => out = '${r.statusCode}: ${r.body}');
      }
    } catch (e) {
      setState(() => out = 'error: $e');
    }
  }

  Future<void> _loadBatches() async {
    try {
      final uri = Uri.parse('${widget.baseUrl}/topup/batches?limit=50' +
          (_mineOnly ? '' : '&seller_id='));
      final r = await http.get(uri, headers: await _hdr());
      _batches = jsonDecode(r.body) as List? ?? [];
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _openBatch(String bid) async {
    setState(() => out = '...');
    try {
      final r = await http.get(
          Uri.parse(
              '${widget.baseUrl}/topup/batches/' + Uri.encodeComponent(bid)),
          headers: await _hdr());
      _batchId = bid;
      _items = jsonDecode(r.body) as List? ?? [];
      setState(() => out = 'Loaded $bid');
    } catch (e) {
      setState(() => out = 'error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadBatches();
  }

  @override
  void dispose() {
    _countCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chips = [5000, 10000, 20000, 50000];
    final grid = _items.isEmpty
        ? const SizedBox()
        : GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: .9,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8),
            itemCount: _items.length,
            itemBuilder: (_, i) {
              final v = _items[i] as Map;
              final payload = (v['payload'] ?? '').toString();
              final code = (v['code'] ?? '').toString();
              final amt = (v['amount_cents'] ?? 0) as int;
              final status = (v['status'] ?? '').toString();
              return Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(children: [
                        Expanded(
                            child: Center(
                                child: Image.network(
                                    '${widget.baseUrl}/qr.png?data=' +
                                        Uri.encodeComponent(payload),
                                    width: 180,
                                    height: 180))),
                        const SizedBox(height: 6),
                        Text(code, style: const TextStyle(fontSize: 12)),
                        Text(
                            '$amt SYP · ${status.isEmpty ? 'reserved' : status}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.white70)),
                        const SizedBox(height: 6),
                        if (status == 'reserved')
                          SizedBox(
                              width: double.infinity,
                              child: PayActionButton(
                                  icon: Icons.remove_circle_outline,
                                  label: 'Void',
                                  onTap: () => _voidVoucher(code)))
                      ])));
            },
          );
    final batchesList = _batches.isEmpty
        ? const SizedBox()
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 16),
            const Text('Recent Batches'),
            const SizedBox(height: 8),
            ..._batches.map((b) {
              final bid = (b['batch_id'] ?? '').toString();
              final total = (b['total'] ?? 0) as int;
              final reserved = (b['reserved'] ?? 0) as int;
              final redeemed = (b['redeemed'] ?? 0) as int;
              return ListTile(
                  title: Text(bid, style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                      'total $total  reserved $reserved  redeemed $redeemed'),
                  trailing: IconButton(
                      icon: const Icon(Icons.open_in_new),
                      onPressed: () => _openBatch(bid)));
            }).toList()
          ]);

    final l = L10n.of(context);
    final content = ListView(padding: const EdgeInsets.all(16), children: [
      Text(l.isArabic ? 'كشك شحن' : 'Topup Kiosk'),
      const SizedBox(height: 8),
      Wrap(
          spacing: 8,
          children: chips.map((v) {
            final sel = _denom == v;
            return ChoiceChip(
                label: Text('$v'),
                selected: sel,
                onSelected: (_) {
                  setState(() => _denom = v);
                });
          }).toList()),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
            child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.isArabic ? 'دفعاتي فقط' : 'My batches only'),
                value: _mineOnly,
                onChanged: (v) {
                  setState(() => _mineOnly = v);
                  _loadBatches();
                })),
        const SizedBox(width: 8),
        Expanded(child: Container())
      ]),
      const SizedBox(height: 4),
      Row(children: [
        Expanded(
            child: TextField(
                controller: _countCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic ? 'عدد القسائم' : 'Count'),
                keyboardType: TextInputType.number)),
        const SizedBox(width: 8),
        Expanded(
            child: TextField(
                controller: _noteCtrl,
                decoration: InputDecoration(
                    labelText:
                        l.isArabic ? 'ملاحظة (اختياري)' : 'Note (optional)'))),
      ]),
      const SizedBox(height: 12),
      PayActionButton(
          icon: Icons.grid_view,
          label: l.isArabic ? 'إنشاء دفعة' : 'Create Batch',
          onTap: _createBatch),
      if (_batchId.isNotEmpty)
        Row(children: [
          Expanded(
              child: PayActionButton(
                  icon: Icons.print_outlined,
                  label: l.isArabic ? 'طباعة الدفعة' : 'Print Batch',
                  onTap: () {
                    launchWithSession(Uri.parse(
                        '${widget.baseUrl}/topup/print/' +
                            Uri.encodeComponent(_batchId)));
                  })),
          const SizedBox(width: 8),
          Expanded(
              child: PayActionButton(
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'PDF',
                  onTap: () {
                    launchWithSession(Uri.parse(
                        '${widget.baseUrl}/topup/print_pdf/' +
                            Uri.encodeComponent(_batchId)));
                  })),
        ]),
      if (_batchId.isNotEmpty) const SizedBox(height: 8),
      if (_batchId.isNotEmpty)
        PayActionButton(
            icon: Icons.refresh,
            label: l.isArabic ? 'إعادة تحميل الدفعة' : 'Reload Batch',
            onTap: () => _openBatch(_batchId)),
      const SizedBox(height: 8),
      grid,
      SelectableText(out),
      batchesList,
    ]);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.isArabic ? 'كشك شحن' : 'Topup Kiosk'),
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: content,
        ),
      ),
    );
  }

  Future<void> _voidVoucher(String code) async {
    setState(() => out = '...');
    try {
      final r = await http.post(
          Uri.parse('${widget.baseUrl}/topup/vouchers/' +
              Uri.encodeComponent(code) +
              '/void'),
          headers: await _hdr());
      if (r.statusCode == 200) {
        setState(() => out = 'Voided $code');
        if (_batchId.isNotEmpty) await _openBatch(_batchId);
      } else {
        setState(() => out = '${r.statusCode}: ${r.body}');
      }
    } catch (e) {
      setState(() => out = 'error: $e');
    }
  }
}

class SystemStatusPage extends StatefulWidget {
  final String baseUrl;
  const SystemStatusPage(this.baseUrl, {super.key});
  @override
  State<SystemStatusPage> createState() => _SystemStatusPageState();
}

class _SystemStatusPageState extends State<SystemStatusPage> {
  Map<String, dynamic>? _data;
  String _error = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _error = '';
    try {
      final uri = Uri.parse('${widget.baseUrl}/upstreams/health');
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode == 200) {
        Perf.action('system_status_ok');
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        setState(() => _data = j);
      } else {
        Perf.action('system_status_fail');
        setState(() => _error = '${r.statusCode}: ${r.body}');
      }
    } catch (e) {
      Perf.action('system_status_error');
      setState(() => _error = 'error: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Color _statusColor(Map<String, dynamic> v) {
    final sc = v['status_code'];
    final err = v['error'];
    if (err != null) {
      return Colors.red;
    }
    if (sc is int) {
      if (sc >= 200 && sc < 300) return Tokens.colorPayments;
      if (sc >= 500) return Colors.red;
      return Colors.orange;
    }
    return Colors.grey;
  }

  String _statusLabel(Map<String, dynamic> v) {
    final sc = v['status_code'];
    final err = v['error'];
    if (err != null) {
      return 'ERROR';
    }
    if (sc is int) {
      if (sc >= 200 && sc < 300) return 'OK';
      if (sc >= 500) return 'DOWN';
      return 'WARN';
    }
    return 'UNKNOWN';
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    final l = L10n.of(context);
    if (_loading && _data == null && _error.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error.isNotEmpty) {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StatusBanner.error(_error),
        ],
      );
    } else {
      final entries = (_data ?? const {}).entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: entries.length + (_error.isNotEmpty ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == 0 && _error.isNotEmpty) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: StatusBanner.error(_error, dense: true),
              );
            }
            final adjIndex = _error.isNotEmpty ? index - 1 : index;
            final e = entries[adjIndex];
            final name = e.key;
            final v = (e.value as Map).cast<String, dynamic>();
            final col = _statusColor(v);
            final status = _statusLabel(v);
            final sc = v['status_code'];
            final err = v['error'];
            final detail = err is String
                ? err
                : (v['body'] is Map && (v['body'] as Map).containsKey('status')
                    ? (v['body']['status'] ?? '').toString()
                    : '');
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  status == 'OK'
                      ? Icons.check_circle_outline
                      : status == 'DOWN'
                          ? Icons.error_outline
                          : Icons.warning_amber_outlined,
                  color: col,
                ),
                title: Text(name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${l.systemStatusStatusLabel}: $status'
                        '${sc != null ? ' · ${l.systemStatusHttpLabel} $sc' : ''}'),
                    if (detail.isNotEmpty)
                      Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(l.systemStatusTitle),
      ),
      body: body,
    );
  }
}

class GlassCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const GlassCard(
      {super.key,
      required this.icon,
      required this.title,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color bg = theme.cardColor;
    final Color fg = theme.colorScheme.onSurface;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 42, color: fg),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  final String baseUrl;
  final String walletId;
  const SettingsPage(
      {super.key, required this.baseUrl, required this.walletId});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController baseUrlCtrl;
  late final TextEditingController walletCtrl;
  bool _debugSkeletonLong = false;
  bool _skipLogin = false;
  bool _metricsRemote = false;

  @override
  void initState() {
    super.initState();
    baseUrlCtrl = TextEditingController(text: widget.baseUrl);
    walletCtrl = TextEditingController(text: widget.walletId);
    // Removed manual Google Maps API key and currency selection (SYP default)
    _loadDebug();
    _loadSkip();
    _loadMetrics();
  }

  Future<void> _loadDebug() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _debugSkeletonLong = sp.getBool('debug_skeleton_long') ?? false;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _loadSkip() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _skipLogin = sp.getBool('skip_login') ?? false;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _loadMetrics() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _metricsRemote = sp.getBool('metrics_remote') ?? false;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final content = ListView(
      padding: const EdgeInsets.all(0),
      children: [
        TextField(
          controller: baseUrlCtrl,
          decoration: InputDecoration(labelText: l.settingsBaseUrl),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: walletCtrl,
          decoration: InputDecoration(labelText: l.settingsMyWallet),
        ),
        const SizedBox(height: 8),
        // Removed manual UI route selector; WeChat-style layout is always used.
        const SizedBox(height: 8),
        SwitchListTile(
          value: _debugSkeletonLong,
          onChanged: (v) {
            setState(() => _debugSkeletonLong = v);
          },
          title: Text(l.settingsDebugSkeleton),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          value: _skipLogin,
          onChanged: (v) {
            setState(() => _skipLogin = v);
          },
          title: Text(l.settingsSkipLogin),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          value: _metricsRemote,
          onChanged: (v) {
            setState(() => _metricsRemote = v);
          },
          title: Text(l.settingsSendMetrics),
        ),
        const SizedBox(height: 16),
        WaterButton(label: l.settingsSave, onTap: _save),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(l.settingsTitle),
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: content,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', baseUrlCtrl.text.trim());
    await sp.setString('wallet_id', walletCtrl.text.trim());
    await sp.setBool('debug_skeleton_long', _debugSkeletonLong);
    await sp.setBool('skip_login', _skipLogin);
    await sp.setBool('metrics_remote', _metricsRemote);
    if (!mounted) return;
    Navigator.pop(context);
  }
}

class SonicPayPage extends StatefulWidget {
  final String baseUrl;
  const SonicPayPage(this.baseUrl, {super.key});
  @override
  State<SonicPayPage> createState() => _SonicPayPageState();
}

class _SonicPayPageState extends State<SonicPayPage> {
  final fromCtrl = TextEditingController();
  final toCtrl = TextEditingController();
  final amtCtrl = TextEditingController(text: '1000');
  String payload = '';
  String out = '';
  Future<void> _issue() async {
    setState(() => out = '...');
    try {
      final r =
          await http.post(Uri.parse('${widget.baseUrl}/payments/sonic/issue'),
              headers: await _hdr(json: true),
              body: jsonEncode({
                'from_wallet_id': fromCtrl.text.trim(),
                'amount_cents': int.tryParse(amtCtrl.text.trim()) ?? 0,
              }));
      out = '${r.statusCode}: ${r.body}';
      try {
        final j = jsonDecode(r.body);
        final tok = j['token'] ?? '';
        payload = tok is String && tok.startsWith('SONIC|')
            ? tok
            : 'SONIC|token=' + tok.toString();
      } catch (_) {}
    } catch (e) {
      out = 'error: $e';
    }
    if (mounted) setState(() {});
  }

  Future<void> _redeem() async {
    setState(() => out = '...');
    try {
      // payload format: SONIC|token=... or any text, server expects token
      final map = <String, String>{};
      try {
        for (final p in payload.split('|').skip(1)) {
          final kv = p.split('=');
          if (kv.length == 2) map[kv[0]] = kv[1];
        }
      } catch (_) {}
      final token = map['token'] ?? payload;
      final r =
          await http.post(Uri.parse('${widget.baseUrl}/payments/sonic/redeem'),
              headers: await _hdr(json: true),
              body: jsonEncode({
                'token': token,
                'to_wallet_id':
                    toCtrl.text.trim().isEmpty ? null : toCtrl.text.trim(),
              }));
      out = '${r.statusCode}: ${r.body}';
    } catch (e) {
      out = 'error: $e';
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.sonicTitle)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
            controller: fromCtrl,
            decoration: InputDecoration(labelText: l.sonicFromWallet)),
        const SizedBox(height: 8),
        TextField(
            controller: toCtrl,
            decoration: InputDecoration(labelText: l.sonicToWalletOpt)),
        const SizedBox(height: 8),
        TextField(
            controller: amtCtrl,
            decoration: InputDecoration(labelText: l.labelAmount),
            keyboardType: TextInputType.number),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: WaterButton(label: l.sonicIssueToken, onTap: _issue)),
          const SizedBox(width: 8),
          Expanded(child: WaterButton(label: l.sonicRedeem, onTap: _redeem))
        ]),
        const SizedBox(height: 12),
        if (payload.isNotEmpty)
          Center(
              child: Column(children: [
            Text(payload),
            const SizedBox(height: 8),
            QrImageView(data: payload, size: 220)
          ])),
        const SizedBox(height: 12),
        SelectableText(out),
      ]),
    );
  }
}

class CashMandatePage extends StatefulWidget {
  final String baseUrl;
  const CashMandatePage(this.baseUrl, {super.key});
  @override
  State<CashMandatePage> createState() => _CashMandatePageState();
}

class _CashMandatePageState extends State<CashMandatePage> {
  final amtCtrl = TextEditingController(text: '1000');
  final phraseCtrl = TextEditingController();
  final codeCtrl = TextEditingController();
  String out = '';
  String payload = '';
  Future<void> _create() async {
    setState(() => out = '...');
    final uri = Uri.parse('${widget.baseUrl}/payments/cash/create');
    String? myWallet;
    try {
      final sp = await SharedPreferences.getInstance();
      myWallet = sp.getString('wallet_id');
    } catch (_) {}
    final body = jsonEncode({
      'from_wallet_id': myWallet,
      'amount_cents': int.tryParse(amtCtrl.text.trim()) ?? 0,
      'phrase': phraseCtrl.text.trim().isEmpty ? null : phraseCtrl.text.trim(),
    });
    try {
      final headers = await _hdr(json: true);
      final r = await http.post(uri, headers: headers, body: body);
      out = '${r.statusCode}: ${r.body}';
      if (r.statusCode >= 500) {
        await OfflineQueue.enqueue(OfflineTask(
            id: 'cash-${DateTime.now().millisecondsSinceEpoch}',
            method: 'POST',
            url: uri.toString(),
            headers: headers,
            body: body,
            tag: 'payments_cash',
            createdAt: DateTime.now().millisecondsSinceEpoch));
      }
      try {
        final j = jsonDecode(r.body);
        final code = j['code'] ?? '';
        codeCtrl.text = code.toString();
        payload = 'CASH|code=' + codeCtrl.text;
      } catch (_) {}
    } catch (e) {
      final headers = await _hdr(json: true);
      await OfflineQueue.enqueue(OfflineTask(
          id: 'cash-${DateTime.now().millisecondsSinceEpoch}',
          method: 'POST',
          url: uri.toString(),
          headers: headers,
          body: body,
          tag: 'payments_cash',
          createdAt: DateTime.now().millisecondsSinceEpoch));
      out = 'Queued (offline)';
    }
    if (mounted) setState(() {});
  }

  Future<void> _status() async {
    setState(() => out = '...');
    try {
      final r = await http.get(Uri.parse(
          '${widget.baseUrl}/payments/cash/status/' +
              Uri.encodeComponent(codeCtrl.text.trim())));
      out = '${r.statusCode}: ${r.body}';
    } catch (e) {
      out = 'error: $e';
    }
    if (mounted) setState(() {});
  }

  Future<void> _cancel() async {
    setState(() => out = '...');
    try {
      final r = await http.post(
          Uri.parse('${widget.baseUrl}/payments/cash/cancel'),
          headers: await _hdr(json: true),
          body: jsonEncode({'code': codeCtrl.text.trim()}));
      out = '${r.statusCode}: ${r.body}';
    } catch (e) {
      out = 'error: $e';
    }
    if (mounted) setState(() {});
  }

  Future<void> _redeem() async {
    setState(() => out = '...');
    try {
      String? myWallet;
      try {
        final sp = await SharedPreferences.getInstance();
        myWallet = sp.getString('wallet_id');
      } catch (_) {}
      final r =
          await http.post(Uri.parse('${widget.baseUrl}/payments/cash/redeem'),
              headers: await _hdr(json: true),
              body: jsonEncode({
                'code': codeCtrl.text.trim(),
                'phrase': phraseCtrl.text.trim().isEmpty
                    ? null
                    : phraseCtrl.text.trim(),
                'to_wallet_id': myWallet,
              }));
      out = '${r.statusCode}: ${r.body}';
    } catch (e) {
      out = 'error: $e';
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final content = ListView(padding: const EdgeInsets.all(16), children: [
      TextField(
          controller: amtCtrl,
          decoration: InputDecoration(labelText: l.labelAmount),
          keyboardType: TextInputType.number),
      const SizedBox(height: 8),
      TextField(
          controller: phraseCtrl,
          decoration: InputDecoration(labelText: l.cashSecretPhraseOpt)),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: WaterButton(label: l.cashCreate, onTap: _create)),
        const SizedBox(width: 8),
        Expanded(child: WaterButton(label: l.cashStatus, onTap: _status)),
        const SizedBox(width: 8),
        Expanded(child: WaterButton(label: l.cashCancel, onTap: _cancel))
      ]),
      const SizedBox(height: 12),
      TextField(
          controller: codeCtrl,
          decoration: InputDecoration(labelText: l.labelCode)),
      const SizedBox(height: 8),
      WaterButton(label: l.cashRedeem, onTap: _redeem),
      const SizedBox(height: 12),
      if (payload.isNotEmpty)
        Center(
            child: Column(children: [
          Text(payload),
          const SizedBox(height: 8),
          QrImageView(data: payload, size: 220)
        ])),
      const SizedBox(height: 12),
      SelectableText(out),
    ]);
    return Scaffold(
        appBar: AppBar(
            title: Text(l.vouchersTitleText),
            backgroundColor: Colors.transparent),
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        body: Stack(children: [
          const AppBG(),
          Positioned.fill(
              child: SafeArea(
                  child: GlassPanel(
                      padding: const EdgeInsets.all(16), child: content)))
        ]));
  }
}

// Generic health stub page for operator modules
// (Legacy operator pages removed; use Mini‑Programs.)

class ModuleHealthPage extends StatefulWidget {
  final String baseUrl;
  final String title;
  final String path;
  const ModuleHealthPage(this.baseUrl, this.title, this.path, {super.key});
  @override
  State<ModuleHealthPage> createState() => _ModuleHealthPageState();
}

class _ModuleHealthPageState extends State<ModuleHealthPage> {
  String out = '';
  int? _statusCode;

  Future<void> _health() async {
    setState(() {
      out = '...';
      _statusCode = null;
    });
    try {
      final r = await http.get(Uri.parse('${widget.baseUrl}${widget.path}'),
          headers: await _hdr());
      setState(() {
        _statusCode = r.statusCode;
        out = r.body;
      });
    } catch (e) {
      setState(() {
        _statusCode = null;
        out = 'error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color chipColor;
    String chipLabel;
    if (out.startsWith('error')) {
      chipColor = Colors.red;
      chipLabel = 'ERROR';
    } else if (_statusCode == null) {
      chipColor = theme.colorScheme.primary;
      chipLabel = 'Tap to check';
    } else if (_statusCode! >= 200 && _statusCode! < 300) {
      chipColor = Tokens.colorPayments;
      chipLabel = 'OK ${_statusCode}';
    } else if (_statusCode! >= 500) {
      chipColor = Colors.red;
      chipLabel = 'DOWN ${_statusCode}';
    } else {
      chipColor = Colors.orange;
      chipLabel = 'WARN ${_statusCode}';
    }

    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Module health',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: .75),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: chipColor.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        chipLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: chipColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                WaterButton(label: 'Check health', onTap: _health),
                if (out.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Raw response',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    out,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
    return Scaffold(
        appBar: AppBar(
            title: Text(widget.title), backgroundColor: Colors.transparent),
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        body: Stack(children: [
          const AppBG(),
          Positioned.fill(
              child: SafeArea(
                  child: GlassPanel(
                      padding: const EdgeInsets.all(16), child: content)))
        ]));
  }
}
