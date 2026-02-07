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
            ? 'يستخدم أدوات تشغيل احترافية (مثل التاكسي، الحافلات، الفنادق) ويدير الحجوزات الحية.'
            : 'Uses professional operator tools (e.g. taxi, bus, hotels) and manages live bookings.'
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

class MerchantPosPage extends StatefulWidget {
  final String baseUrl;
  const MerchantPosPage(this.baseUrl, {super.key});
  @override
  State<MerchantPosPage> createState() => _MerchantPosPageState();
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

class _MerchantPosPageState extends State<MerchantPosPage> {
  final walletCtrl = TextEditingController();
  final amountCtrl = TextEditingController(text: '10000');
  final nameCtrl = TextEditingController();
  String payload = '';
  StatusKind _bannerKind = StatusKind.info;
  String _bannerMsg = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    walletCtrl.text = sp.getString('merchant_wallet') ?? '';
    nameCtrl.text = sp.getString('merchant_name') ?? '';
    setState(() {});
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('merchant_wallet', walletCtrl.text.trim());
    await sp.setString('merchant_name', nameCtrl.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Saved')));
  }

  void _genPay() {
    final w = walletCtrl.text.trim();
    final a = double.tryParse(amountCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    final nm = nameCtrl.text.trim();
    if (w.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Wallet required')));
      return;
    }
    var p = 'PAY|wallet=' + Uri.encodeComponent(w);
    if (a > 0) {
      p += '|amount=' + Uri.encodeComponent(a.toStringAsFixed(2));
    }
    if (nm.isNotEmpty) {
      p += '|label=' + Uri.encodeComponent(nm);
    }
    setState(() => payload = p);
  }

  @override
  Widget build(BuildContext context) {
    final content = ListView(padding: const EdgeInsets.all(16), children: [
      if (_bannerMsg.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child:
              StatusBanner(kind: _bannerKind, message: _bannerMsg, dense: true),
        ),
      TextField(
          controller: walletCtrl,
          decoration: const InputDecoration(labelText: 'Merchant Wallet ID')),
      const SizedBox(height: 8),
      TextField(
          controller: nameCtrl,
          decoration:
              const InputDecoration(labelText: 'Merchant Display Name')),
      const SizedBox(height: 8),
      TextField(
          controller: amountCtrl,
          decoration: const InputDecoration(labelText: 'Amount (SYP)'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true)),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
            child: PayActionButton(
                icon: Icons.save_outlined,
                label: L10n.of(context).isArabic ? 'حفظ' : 'Save',
                onTap: _save)),
        const SizedBox(width: 8),
        Expanded(
            child: PayActionButton(
                icon: Icons.qr_code_2, label: 'PAY QR', onTap: _genPay))
      ]),
      const SizedBox(height: 12),
      PayActionButton(
          icon: Icons.local_printshop_outlined,
          label: L10n.of(context).isArabic ? 'كشك شحن' : 'Topup Kiosk',
          onTap: () {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => TopupKioskPage(widget.baseUrl)));
          }),
      const SizedBox(height: 16),
      if (payload.isNotEmpty)
        Center(
            child: Column(children: [
          Text(payload, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          QrImageView(data: payload, version: QrVersions.auto, size: 220)
        ])),
    ]);
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.of(context).homeMerchantPos),
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
      btn(Icons.support_agent, 'Taxi Admin', () {
        openWeb(
          '/taxi/admin',
          title: l.isArabic ? 'مشغل التاكسي' : 'Taxi operator',
        );
      }),
      btn(Icons.percent, 'Taxi Settings', () {
        openWeb(
          '/taxi/settings',
          title: l.isArabic ? 'إعدادات التاكسي' : 'Taxi settings',
        );
      }),
      btn(Icons.directions_bus_filled_outlined, 'Bus Operator', () {
        openWeb(
          '/bus/admin',
          title: l.isArabic ? 'إدارة الباص' : 'Bus admin',
        );
      }),
      btn(Icons.business, 'Hotel Operator', () {
        openWeb(
          '/stays',
          title: l.isArabic ? 'الفنادق والإقامات' : 'Stays',
        );
      }),
      btn(Icons.construction_outlined, 'Building Materials Operator', () {
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => BuildingMaterialsOperatorPage(baseUrl)));
      }),
      btn(Icons.directions_car_filled_outlined, 'Carmarket Operator', () {
        openWeb(
          '/carmarket',
          title: l.isArabic ? 'سوق السيارات' : 'Cars',
        );
      }),
      btn(Icons.car_rental, 'Carrental Operator', () {
        openWeb(
          '/carrental',
          title: l.isArabic ? 'تأجير السيارات' : 'Car rental',
        );
      }),
      btn(Icons.engineering, 'Equipment Ops', () {
        openWeb(
          '/equipment',
          title: l.isArabic ? 'المعدات' : 'Equipment',
        );
      }),
      btn(Icons.point_of_sale, 'Merchant POS', () {
        openWeb(
          '/merchant',
          title: l.isArabic ? 'نقطة البيع' : 'Merchant POS',
        );
      }),
      btn(Icons.local_printshop_outlined, 'Topup Kiosk', () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => TopupKioskPage(baseUrl)));
      }),
      btn(Icons.health_and_safety_outlined, l.opsSystemStatus, () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => SystemStatusPage(baseUrl)));
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
    if (_domains.contains('taxi')) {
      tiles.add(btn(Icons.support_agent, l.homeTaxiOperator, () {
        openWeb(
          '/taxi/admin',
          title: l.isArabic ? 'مشغل التاكسي' : 'Taxi operator',
        );
      }));
    }
    if (_domains.contains('bus')) {
      tiles.add(btn(Icons.directions_bus_filled_outlined,
          l.isArabic ? 'مشغل الباص' : 'Bus Operator', () {
        openWeb(
          '/bus/admin',
          title: l.isArabic ? 'إدارة الباص' : 'Bus admin',
        );
      }));
    }
    if (_domains.contains('stays')) {
      tiles.add(btn(
        Icons.business,
        l.isArabic ? 'مشغل الفنادق والإقامات' : 'Stays Operator',
        () {
          openWeb(
            '/stays',
            title: l.isArabic ? 'الفنادق والإقامات' : 'Stays',
          );
        },
      ));
    }
    if (_domains.contains('commerce')) {
      tiles.add(btn(
        Icons.construction_outlined,
        l.isArabic
            ? 'مشغل مواد البناء / التجارة'
            : 'Building Materials Operator',
        () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      BuildingMaterialsOperatorPage(widget.baseUrl)));
        },
      ));
    }
    // Doctors admin
    tiles.add(btn(Icons.medical_services_outlined,
        l.isArabic ? 'مشغل الأطباء' : 'Doctors Admin', () {
      openWeb(
        '/doctors',
        title: l.isArabic ? 'الأطباء' : 'Doctors',
      );
    }));
    if (_domains.contains('realestate')) {
      tiles.add(btn(
        Icons.apartment_outlined,
        l.isArabic ? 'مشغل العقارات' : 'Realestate Operator',
        () {
          openWeb(
            '/realestate',
            title: l.isArabic ? 'العقارات' : 'Real estate',
          );
        },
      ));
    }
    if (_domains.contains('food')) {
      tiles.add(btn(
        Icons.restaurant,
        l.isArabic ? 'مشغل الطعام' : 'Food Operator',
        () {
          openWeb(
            '/food',
            title: l.isArabic ? 'الطعام' : 'Food',
          );
        },
      ));
    }
    if (_domains.contains('freight')) {
      tiles.add(btn(
        Icons.local_shipping_outlined,
        l.isArabic ? 'مشغل الشحن' : 'Freight Operator',
        () {
          openWeb(
            '/freight',
            title: l.isArabic ? 'الشحن' : 'Freight',
          );
        },
      ));
    }
    if (_domains.contains('agriculture')) {
      tiles.add(btn(
        Icons.eco_outlined,
        l.isArabic ? 'مشغل الزراعة' : 'Agriculture Operator',
        () {
          openWeb(
            '/agriculture',
            title: l.isArabic ? 'الزراعة' : 'Agriculture',
          );
        },
      ));
    }
    if (_domains.contains('livestock')) {
      tiles.add(btn(
        Icons.pets_outlined,
        l.isArabic ? 'مشغل الثروة الحيوانية' : 'Livestock Operator',
        () {
          openWeb(
            '/livestock',
            title: l.isArabic ? 'الثروة الحيوانية' : 'Livestock',
          );
        },
      ));
    }
    if (_domains.contains('carrental')) {
      tiles.add(btn(
        Icons.directions_car,
        l.isArabic ? 'مشغل تأجير السيارات' : 'Carrental Operator',
        () {
          openWeb(
            '/carrental',
            title: l.isArabic ? 'تأجير السيارات' : 'Car rental',
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
                      api: SuperappAPI.light(baseUrl: baseUrl))));
        },
      ),
      superTile(
        icon: Icons.local_taxi_outlined,
        label: 'Taxi',
        tint: Tokens.colorTaxi,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MiniProgramPage(
                id: 'taxi_rider',
                baseUrl: baseUrl,
                walletId: '',
                deviceId: 'superadmin',
                onOpenMod: (id) {
                  final next = id.trim().toLowerCase();
                  if (next.isEmpty) return;
                  if (next == 'payments' || next == 'pay' || next == 'wallet') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PaymentsPage(
                          baseUrl,
                          '',
                          'superadmin',
                        ),
                      ),
                    );
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MiniProgramPage(
                        id: next,
                        baseUrl: baseUrl,
                        walletId: '',
                        deviceId: 'superadmin',
                        onOpenMod: (id2) {},
                      ),
                    ),
                  );
                },
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
      superTile(
        icon: Icons.restaurant_outlined,
        label: 'Food',
        tint: Tokens.colorFood,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MiniProgramPage(
                id: 'food',
                baseUrl: baseUrl,
                walletId: '',
                deviceId: 'superadmin',
              ),
            ),
          );
        },
      ),
      superTile(
        icon: Icons.hotel_outlined,
        label: 'Stays & Hotels',
        tint: Tokens.colorHotelsStays,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MiniProgramPage(
                id: 'stays',
                baseUrl: baseUrl,
                walletId: '',
                deviceId: 'superadmin',
              ),
            ),
          );
        },
      ),
      superTile(
        icon: Icons.home_outlined,
        label: 'Realestate',
        tint: Tokens.colorHotelsStays,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MiniProgramPage(
                id: 'realestate',
                baseUrl: baseUrl,
                walletId: '',
                deviceId: 'superadmin',
              ),
            ),
          );
        },
      ),
      superTile(
        icon: Icons.construction_outlined,
        label: 'Building materials',
        tint: Tokens.colorBuildingMaterials,
        onTap: () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      BuildingMaterialsMultiLevelPage(baseUrl: baseUrl)));
        },
      ),
      superTile(
        icon: Icons.local_shipping_outlined,
        label: 'Courier',
        tint: Tokens.colorCourierTransport,
        onTap: () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => CourierMultiLevelPage(baseUrl: baseUrl)));
        },
      ),
      superTile(
        icon: Icons.directions_car_filled_outlined,
        label: 'Carrental & Carmarket',
        tint: Tokens.colorCars,
        onTap: () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      CarrentalCarmarketMultiLevelPage(baseUrl: baseUrl)));
        },
      ),
      superTile(
        icon: Icons.store_mall_directory_outlined,
        label: 'Agri Marketplace',
        tint: Tokens.colorAgricultureLivestock,
        onTap: () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      AgricultureLivestockMultiLevelPage(baseUrl: baseUrl)));
        },
      ),
      superTile(
        icon: Icons.pets_outlined,
        label: 'Livestock Marketplace',
        tint: Tokens.colorAgricultureLivestock,
        onTap: () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => LivestockMarketplacePage(baseUrl: baseUrl)));
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
            final building = (data['building_orders'] as Map?) ?? const {};
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
              lineFor('taxi_book_ms', 'Taxi booking'),
              lineFor('bus_book_ms', 'Bus booking'),
              lineFor('stays_book_ms', 'Stays booking'),
              lineFor('food_order_ms', 'Food order'),
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
            final taxiOk = _intFor('taxi_book_ok');
            final taxiFail = _intFor('taxi_book_fail');
            final busOk = _intFor('bus_book_ok');
            final busFail = _intFor('bus_book_fail');
            final staysOk = _intFor('stays_book_ok');
            final staysFail = _intFor('stays_book_fail');
            final foodOk = _intFor('food_order_ok');
            final foodFail = _intFor('food_order_fail');
            final buildingTotal = (building['total'] ?? 0) is int
                ? building['total'] as int
                : int.tryParse((building['total'] ?? '0').toString()) ?? 0;

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
                          'taxi ok/fail: $taxiOk/$taxiFail',
                          'bus ok/fail: $busOk/$busFail',
                        ),
                        domainCard(
                          Icons.hotel,
                          'Stays',
                          'ok/fail: $staysOk/$staysFail',
                          null,
                        ),
                        domainCard(
                          Icons.restaurant_outlined,
                          'Food',
                          'ok/fail: $foodOk/$foodFail',
                          null,
                        ),
                        domainCard(
                          Icons.storefront,
                          'Marketplace',
                          'building orders: $buildingTotal',
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
                            fmt('taxi_book_ok', 'Taxi ok'),
                            fmt('taxi_book_fail', 'Taxi fail'),
                            fmt('bus_book_ok', 'Bus ok'),
                            fmt('bus_book_fail', 'Bus fail'),
                            fmt('stays_book_ok', 'Stays ok'),
                            fmt('stays_book_fail', 'Stays fail'),
                            fmt('food_order_ok', 'Food ok'),
                            fmt('food_order_fail', 'Food fail'),
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
                    if (building.isNotEmpty) ...[
                      const Divider(height: 16),
                      Text(
                        'Building orders (audit, last window)',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Builder(
                        builder: (_) {
                          final lines = building.entries
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
                            if (key.contains('taxi') ||
                                key.contains('bus') ||
                                key.contains('freight') ||
                                key.contains('carrental')) {
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
                ? 'أدوار المشغلين (تاكسي، باص، الفنادق وغيرها) تُدار الآن داخل كل تطبيق نطاقي لتبقى لوحة Superadmin بسيطة ومركزة على الإحصاءات العامة.'
                : 'Operator roles for Taxi, Bus, Stays and other domains are now managed inside each domain dashboard so this Superadmin home stays focused on global stats.',
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
            }, tint: Tokens.colorHotelsStays),
            btn(Icons.layers_outlined, l.opsTitle, () {
              Navigator.push(
                  context, MaterialPageRoute(builder: (_) => OpsPage(baseUrl)));
            }, tint: Tokens.colorBuildingMaterials),
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

class FreightPage extends StatefulWidget {
  final String baseUrl;
  const FreightPage(this.baseUrl, {super.key});
  @override
  State<FreightPage> createState() => _FreightPageState();
}

class CarmarketPage extends StatefulWidget {
  final String baseUrl;
  const CarmarketPage(this.baseUrl, {super.key});
  @override
  State<CarmarketPage> createState() => _CarmarketPageState();
}

class _CarmarketPageState extends State<CarmarketPage> {
  final qCtrl = TextEditingController();
  final cityCtrl = TextEditingController();
  String list = '';
  List<dynamic> _items = const [];
  String _listOut = '';
  bool _listLoading = false;
  final titleCtrl = TextEditingController();
  final priceCtrl = TextEditingController(text: '100000');
  final makeCtrl = TextEditingController();
  final modelCtrl = TextEditingController();
  final yearCtrl = TextEditingController();
  final ownerCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  final selCtrl = TextEditingController();
  final inameCtrl = TextEditingController();
  final iphoneCtrl = TextEditingController();
  final imsgCtrl = TextEditingController();
  String out = '';
  String iout = '';
  @override
  void initState() {
    super.initState();
    _loadWallet();
  }

  Future<void> _loadWallet() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final w = sp.getString('wallet_id') ?? '';
      if (w.isNotEmpty) {
        ownerCtrl.text = w;
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _listLoading = true;
      _listOut = '';
    });
    try {
      final u = Uri.parse(
          '${widget.baseUrl}/carmarket/listings?q=${Uri.encodeComponent(qCtrl.text)}&city=${Uri.encodeComponent(cityCtrl.text)}');
      final r = await http.get(u, headers: await _hdr());
      if (!mounted) return;
      list = '${r.statusCode}: ${r.body}';
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is List) {
          setState(() {
            _items = body;
            _listOut = '';
          });
        } else {
          setState(() {
            _items = const [];
            _listOut = '${r.statusCode}: ${r.body}';
          });
        }
      } else {
        setState(() {
          _items = const [];
          _listOut = '${r.statusCode}: ${r.body}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _listOut = 'error: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _listLoading = false);
      }
    }
  }

  Future<void> _deleteListing(int id) async {
    try {
      final r = await http.delete(
          Uri.parse('${widget.baseUrl}/carmarket/listings/$id'),
          headers: await _hdr());
      if (mounted) {
        setState(() => _listOut = '${r.statusCode}: ${r.body}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _listOut = 'error: $e');
      }
    }
    await _load();
  }

  Future<void> _create() async {
    final h = await _hdr(json: true);
    h['Idempotency-Key'] = 'car-${DateTime.now().millisecondsSinceEpoch}';
    final r = await http.post(Uri.parse('${widget.baseUrl}/carmarket/listings'),
        headers: h,
        body: jsonEncode({
          'title': titleCtrl.text.trim(),
          'price_cents': int.tryParse(priceCtrl.text.trim()) ?? 0,
          'make': makeCtrl.text.trim().isEmpty ? null : makeCtrl.text.trim(),
          'model': modelCtrl.text.trim().isEmpty ? null : modelCtrl.text.trim(),
          'year': int.tryParse(yearCtrl.text.trim()),
          'city': cityCtrl.text.trim().isEmpty ? null : cityCtrl.text.trim(),
          'description':
              descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
          'owner_wallet_id':
              ownerCtrl.text.trim().isEmpty ? null : ownerCtrl.text.trim()
        }));
    setState(() => out = '${r.statusCode}: ${r.body}');
    _load();
  }

  Future<void> _inquiry() async {
    final h = await _hdr(json: true);
    h['Idempotency-Key'] = 'ci-${DateTime.now().millisecondsSinceEpoch}';
    final r = await http.post(
        Uri.parse('${widget.baseUrl}/carmarket/inquiries'),
        headers: h,
        body: jsonEncode({
          'listing_id': int.tryParse(selCtrl.text.trim()) ?? 0,
          'name': inameCtrl.text.trim(),
          'phone':
              iphoneCtrl.text.trim().isEmpty ? null : iphoneCtrl.text.trim(),
          'message': imsgCtrl.text.trim().isEmpty ? null : imsgCtrl.text.trim()
        }));
    setState(() => iout = '${r.statusCode}: ${r.body}');
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final content = ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        SizedBox(
            width: 220,
            child: TextField(
                controller: qCtrl,
                decoration: InputDecoration(labelText: l.labelSearch))),
        SizedBox(
            width: 220,
            child: TextField(
                controller: cityCtrl,
                decoration: InputDecoration(labelText: l.labelCity))),
        SizedBox(
            width: 140, child: WaterButton(label: l.reSearch, onTap: _load)),
      ]),
      const SizedBox(height: 8),
      if (_listLoading)
        const SizedBox(
          height: 24,
          width: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      if (_listOut.isNotEmpty) StatusBanner.info(_listOut, dense: true),
      const SizedBox(height: 8),
      if (_items.isNotEmpty) ...[
        Builder(builder: (ctx) {
          int totalPrice = 0;
          for (final x in _items) {
            try {
              final p = x['price_cents'];
              if (p is int) {
                totalPrice += p;
              }
            } catch (_) {}
          }
          final count = _items.length;
          final avg = count > 0 ? (totalPrice ~/ count) : 0;
          final txt = l.isArabic
              ? 'العروض: $count · القيمة الإجمالية: ${totalPrice} ل.س · متوسط السعر: ${avg} ل.س'
              : 'Listings: $count · Total value: ${totalPrice} SYP · Avg price: ${avg} SYP';
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: StatusBanner.info(txt, dense: true),
          );
        }),
        const SizedBox(height: 4),
      ],
      ..._items.map((x) {
        final id = (x['id'] ?? '').toString();
        final title = (x['title'] ?? '').toString();
        final city = (x['city'] ?? '').toString();
        final make = (x['make'] ?? '').toString();
        final model = (x['model'] ?? '').toString();
        final year = (x['year'] ?? '').toString();
        final price = x['price_cents'];
        final priceStr = price == null ? '' : '${price} SYP';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: GlassPanel(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Listing $id · $title',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('$city  ·  $make $model $year'),
                if (priceStr.isNotEmpty)
                  Text(priceStr, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    SizedBox(
                      height: 32,
                      child: ElevatedButton(
                        onPressed: () {
                          selCtrl.text = id;
                        },
                        child: Text(l.isArabic ? 'اختيار' : 'Select'),
                      ),
                    ),
                    SizedBox(
                      height: 32,
                      child: OutlinedButton(
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: Text(
                                  l.isArabic ? 'حذف العرض' : 'Delete listing'),
                              content: Text(l.isArabic
                                  ? 'هل تريد حذف هذا العرض؟'
                                  : 'Delete this listing?'),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child:
                                        Text(l.isArabic ? 'إلغاء' : 'Cancel')),
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: Text(l.isArabic ? 'حذف' : 'Delete')),
                              ],
                            ),
                          );
                          if (ok == true) {
                            await _deleteListing(int.tryParse(id) ?? 0);
                          }
                        },
                        child: Text(l.isArabic ? 'حذف' : 'Delete'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
      const Divider(height: 24),
      TextField(
          controller: titleCtrl,
          decoration:
              InputDecoration(labelText: l.isArabic ? 'العنوان' : 'title')),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        SizedBox(
            width: 220,
            child: TextField(
                controller: priceCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic ? 'السعر (ليرة)' : 'price (SYP)'))),
        SizedBox(
            width: 220,
            child: TextField(
                controller: ownerCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic ? 'محفظة المالك' : 'owner wallet'))),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        SizedBox(
            width: 220,
            child: TextField(
                controller: makeCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic ? 'الشركة المصنعة' : 'make'))),
        SizedBox(
            width: 220,
            child: TextField(
                controller: modelCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic ? 'الطراز' : 'model'))),
        SizedBox(
            width: 220,
            child: TextField(
                controller: yearCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic ? 'سنة الصنع' : 'year'))),
      ]),
      const SizedBox(height: 8),
      TextField(
          controller: descCtrl,
          decoration:
              InputDecoration(labelText: l.isArabic ? 'الوصف' : 'description')),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        SizedBox(
            width: 160,
            child: WaterButton(
                label: l.isArabic ? 'إنشاء' : 'Create', onTap: _create))
      ]),
      const Divider(height: 24),
      TextField(
          controller: selCtrl,
          decoration: InputDecoration(
              labelText: l.isArabic ? 'معرّف العرض' : 'listing id')),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        SizedBox(
            width: 180,
            child: WaterButton(label: l.reSendInquiry, onTap: _inquiry))
      ]),
      const SizedBox(height: 8),
      if (out.isNotEmpty) StatusBanner.info(out, dense: true),
      const SizedBox(height: 8),
      if (iout.isNotEmpty) StatusBanner.info(iout, dense: true),
    ]);
    return DomainPageScaffold(
      background: const AppBG(),
      title: l.carmarketTitle,
      child: content,
      scrollable: true,
    );
  }
}

class CarrentalPage extends StatefulWidget {
  final String baseUrl;
  const CarrentalPage(this.baseUrl, {super.key});
  @override
  State<CarrentalPage> createState() => _CarrentalPageState();
}

class _CarrentalPageState extends State<CarrentalPage> {
  final qCtrl = TextEditingController();
  final cityCtrl = TextEditingController();
  final carIdCtrl = TextEditingController();
  final fromCtrl = TextEditingController();
  final toCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final rwCtrl = TextEditingController();
  final bidCtrl = TextEditingController();
  String qOut = '', bOut = '', bsOut = '';
  List<dynamic> _cars = const [];
  String _carsOut = '';
  bool confirm = true;
  // Operator view: aggregated bookings
  String _bookingStatusFilter = '';
  bool _bookingsLoading = false;
  String _bookingsOut = '';
  List<dynamic> _bookings = const [];
  @override
  void initState() {
    super.initState();
    _loadWallet();
  }

  Future<void> _loadWallet() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final w = sp.getString('wallet_id') ?? '';
      if (w.isNotEmpty) {
        rwCtrl.text = w;
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _loadCars() async {
    final u = Uri.parse(
        '${widget.baseUrl}/carrental/cars?q=${Uri.encodeComponent(qCtrl.text)}&city=${Uri.encodeComponent(cityCtrl.text)}');
    final r = await http.get(u, headers: await _hdr());
    if (!mounted) return;
    try {
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is List) {
          setState(() {
            _cars = body;
            _carsOut = '';
          });
        } else {
          setState(() {
            _cars = const [];
            _carsOut = '${r.statusCode}: ${r.body}';
          });
        }
      } else {
        setState(() {
          _cars = const [];
          _carsOut = '${r.statusCode}: ${r.body}';
        });
      }
    } catch (e) {
      setState(() {
        _cars = const [];
        _carsOut = 'error: $e';
      });
    }
  }

  Future<void> _quote() async {
    final r = await http.post(Uri.parse('${widget.baseUrl}/carrental/quote'),
        headers: await _hdr(json: true),
        body: jsonEncode({
          'car_id': int.tryParse(carIdCtrl.text.trim()) ?? 0,
          'from_iso': fromCtrl.text.trim(),
          'to_iso': toCtrl.text.trim()
        }));
    setState(() => qOut = '${r.statusCode}: ${r.body}');
  }

  Future<void> _book() async {
    final h = await _hdr(json: true);
    h['Idempotency-Key'] = 'crb-${DateTime.now().millisecondsSinceEpoch}';
    final r = await http.post(Uri.parse('${widget.baseUrl}/carrental/book'),
        headers: h,
        body: jsonEncode({
          'car_id': int.tryParse(carIdCtrl.text.trim()) ?? 0,
          'renter_name': nameCtrl.text.trim(),
          'renter_phone':
              phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
          'renter_wallet_id':
              rwCtrl.text.trim().isEmpty ? null : rwCtrl.text.trim(),
          'from_iso': fromCtrl.text.trim(),
          'to_iso': toCtrl.text.trim(),
          'confirm': confirm
        }));
    setState(() => bOut = '${r.statusCode}: ${r.body}');
    try {
      final j = jsonDecode(r.body);
      bidCtrl.text = (j['id'] ?? '').toString();
    } catch (_) {}
  }

  Future<void> _status() async {
    final id = bidCtrl.text.trim();
    if (id.isEmpty) return;
    final r = await http.get(
        Uri.parse('${widget.baseUrl}/carrental/bookings/$id'),
        headers: await _hdr());
    setState(() => bsOut = '${r.statusCode}: ${r.body}');
  }

  Future<void> _cancel() async {
    final id = bidCtrl.text.trim();
    if (id.isEmpty) return;
    final r = await http
        .post(Uri.parse('${widget.baseUrl}/carrental/bookings/$id/cancel'));
    setState(() => bsOut = '${r.statusCode}: ${r.body}');
  }

  Future<void> _confirm() async {
    final id = bidCtrl.text.trim();
    if (id.isEmpty) return;
    final r = await http.post(
        Uri.parse('${widget.baseUrl}/carrental/bookings/$id/confirm'),
        headers: await _hdr(json: true),
        body: jsonEncode({'confirm': true}));
    setState(() => bsOut = '${r.statusCode}: ${r.body}');
  }

  Future<void> _loadBookings() async {
    setState(() {
      _bookingsLoading = true;
      _bookingsOut = '';
    });
    try {
      final params = <String, String>{'limit': '100'};
      if (_bookingStatusFilter.isNotEmpty) {
        params['status'] = _bookingStatusFilter;
      }
      final uri = Uri.parse('${widget.baseUrl}/carrental/bookings')
          .replace(queryParameters: params);
      final r = await http.get(uri, headers: await _hdr());
      if (!mounted) return;
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is List) {
          setState(() {
            _bookings = body;
            _bookingsOut = '';
          });
        } else {
          setState(() {
            _bookings = const [];
            _bookingsOut = '${r.statusCode}: ${r.body}';
          });
        }
      } else {
        setState(() {
          _bookings = const [];
          _bookingsOut = '${r.statusCode}: ${r.body}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bookings = const [];
        _bookingsOut = 'error: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _bookingsLoading = false);
      }
    }
  }

  Future<void> _opConfirm(String id) async {
    try {
      final r = await http.post(
        Uri.parse('${widget.baseUrl}/carrental/bookings/$id/confirm'),
        headers: await _hdr(json: true),
        body: jsonEncode({'confirm': true}),
      );
      if (mounted) {
        setState(() => _bookingsOut = '${r.statusCode}: ${r.body}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _bookingsOut = 'error: $e');
      }
    }
    await _loadBookings();
  }

  Future<void> _opCancel(String id) async {
    try {
      final r = await http
          .post(Uri.parse('${widget.baseUrl}/carrental/bookings/$id/cancel'));
      if (mounted) {
        setState(() => _bookingsOut = '${r.statusCode}: ${r.body}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _bookingsOut = 'error: $e');
      }
    }
    await _loadBookings();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final content = ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        SizedBox(
            width: 220,
            child: TextField(
                controller: qCtrl,
                decoration: InputDecoration(labelText: l.labelSearch))),
        SizedBox(
            width: 220,
            child: TextField(
                controller: cityCtrl,
                decoration: InputDecoration(labelText: l.labelCity))),
        SizedBox(
            width: 160,
            child: WaterButton(
                label: l.isArabic ? 'تحميل السيارات' : 'Load cars',
                onTap: _loadCars)),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        SizedBox(
            width: 220,
            child: TextField(
                controller: carIdCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic ? 'معرّف السيارة' : 'car id'))),
        SizedBox(
            width: 220,
            child: TextField(
                controller: fromCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic ? 'من (ISO)' : 'from ISO'))),
        SizedBox(
            width: 220,
            child: TextField(
                controller: toCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic ? 'إلى (ISO)' : 'to ISO'))),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        SizedBox(
            width: 160,
            child: WaterButton(
                label: l.isArabic ? 'تسعير' : 'Quote', onTap: _quote)),
        SizedBox(
            width: 160,
            child: WaterButton(
                label: l.isArabic ? 'حجز و دفع' : 'Book & Pay', onTap: _book)),
      ]),
      const SizedBox(height: 8),
      if (qOut.isNotEmpty) StatusBanner.info(qOut, dense: true),
      if (_carsOut.isNotEmpty) StatusBanner.info(_carsOut, dense: true),
      if (_cars.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(l.isArabic ? 'السيارات المتاحة' : 'Available cars',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        ..._cars.take(10).map((c) {
          final id = c['id'] ?? c['car_id'] ?? '';
          final title = (c['title'] ??
                  c['name'] ??
                  '${c['make'] ?? ''} ${c['model'] ?? ''}')
              .toString()
              .trim();
          final city = (c['city'] ?? '').toString();
          final price = (c['price_per_day_cents'] ??
              c['price_cents'] ??
              c['daily_price_cents'] ??
              0) as num;
          final priceText =
              price > 0 ? '${(price / 100).toStringAsFixed(2)} SYP/day' : '';
          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                    color:
                        Theme.of(context).dividerColor.withValues(alpha: .35))),
            child: ListTile(
              leading: const Icon(Icons.directions_car_filled_outlined),
              title: Text(title.isEmpty ? 'Car' : title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                [if (city.isNotEmpty) city, if (priceText.isNotEmpty) priceText]
                    .where((e) => e.isNotEmpty)
                    .join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(id.toString()),
              onTap: () {
                carIdCtrl.text = id.toString();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                        l.isArabic ? 'تم اختيار السيارة' : 'Car selected')));
              },
            ),
          );
        }),
      ],
      const Divider(height: 24),
      TextField(
          controller: nameCtrl,
          decoration: InputDecoration(
              labelText: l.isArabic ? 'اسم المستأجر' : 'renter name')),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        SizedBox(
            width: 220,
            child: TextField(
                controller: phoneCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic
                        ? 'هاتف المستأجر (اختياري)'
                        : 'renter phone (opt)'))),
        SizedBox(
            width: 220,
            child: TextField(
                controller: rwCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic
                        ? 'محفظة المستأجر (اختياري)'
                        : 'renter wallet (opt)'))),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        SizedBox(
            width: 220,
            child: TextField(
                controller: bidCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic ? 'معرّف الحجز' : 'booking id'))),
        SizedBox(
            width: 140,
            child: WaterButton(
                label: l.isArabic ? 'الحالة' : 'Status', onTap: _status)),
        SizedBox(
            width: 140,
            child: WaterButton(
                label: l.isArabic ? 'إلغاء' : 'Cancel', onTap: _cancel)),
        SizedBox(
            width: 140,
            child: WaterButton(
                label: l.isArabic ? 'تأكيد' : 'Confirm', onTap: _confirm)),
      ]),
      const SizedBox(height: 8),
      SelectableText(bOut),
      const SizedBox(height: 8),
      if (bsOut.isNotEmpty) StatusBanner.info(bsOut, dense: true),
      const Divider(height: 32),
      Text(l.isArabic ? 'حجوزات (عرض المشغل)' : 'Bookings (operator view)',
          style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      if (_bookings.isNotEmpty) ...[
        Builder(builder: (ctx) {
          final total = _bookings.length;
          int requested = 0, confirmed = 0, canceled = 0, completed = 0;
          int totalAmount = 0;
          for (final b in _bookings) {
            try {
              final st = (b['status'] ?? '').toString();
              switch (st) {
                case 'requested':
                  requested++;
                  break;
                case 'confirmed':
                  confirmed++;
                  break;
                case 'canceled':
                  canceled++;
                  break;
                case 'completed':
                  completed++;
                  break;
              }
              final amt = b['amount_cents'];
              if (amt is int) {
                totalAmount += amt;
              }
            } catch (_) {}
          }
          final cancelRate = total > 0 ? (canceled / total) : 0.0;
          final highRisk = total >= 10 && cancelRate >= 0.5;
          final baseTxtEn =
              'Bookings: $total · requested: $requested · confirmed: $confirmed · canceled: $canceled · completed: $completed · total amount: ${totalAmount} SYP';
          final baseTxtAr =
              'إجمالي الحجوزات: $total · قيد الطلب: $requested · مؤكدة: $confirmed · ملغاة: $canceled · مكتملة: $completed · إجمالي المبلغ: ${totalAmount} ل.س';
          final alertEn = ' · Anti‑fraud: HIGH cancellation rate';
          final alertAr = ' · مكافحة الاحتيال: معدل إلغاء مرتفع';
          final txt = l.isArabic
              ? (baseTxtAr + (highRisk ? alertAr : ''))
              : (baseTxtEn + (highRisk ? alertEn : ''));
          final banner = highRisk
              ? StatusBanner.error(txt, dense: true)
              : StatusBanner.info(txt, dense: true);
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: banner,
          );
        }),
        const SizedBox(height: 8),
      ],
      Wrap(spacing: 8, runSpacing: 8, children: [
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<String>(
            decoration:
                InputDecoration(labelText: l.isArabic ? 'الحالة' : 'status'),
            initialValue:
                _bookingStatusFilter.isEmpty ? null : _bookingStatusFilter,
            items: const [
              DropdownMenuItem(value: '', child: Text('All')),
              DropdownMenuItem(value: 'requested', child: Text('requested')),
              DropdownMenuItem(value: 'confirmed', child: Text('confirmed')),
              DropdownMenuItem(value: 'canceled', child: Text('canceled')),
              DropdownMenuItem(value: 'completed', child: Text('completed')),
            ],
            onChanged: (v) {
              setState(() => _bookingStatusFilter = v ?? '');
            },
          ),
        ),
        SizedBox(
            width: 160,
            child: WaterButton(
                label: l.isArabic ? 'تحديث الحجوزات' : 'Reload bookings',
                onTap: _loadBookings)),
        SizedBox(
          width: 200,
          child: WaterButton(
            label: l.isArabic ? 'تصدير CSV' : 'Export CSV',
            onTap: () {
              final params = _bookingStatusFilter.isNotEmpty
                  ? '?status=${Uri.encodeComponent(_bookingStatusFilter)}'
                  : '';
              launchWithSession(Uri.parse(
                  '${widget.baseUrl}/carrental/admin/bookings/export$params'));
            },
          ),
        ),
        if (_bookingsLoading)
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ]),
      const SizedBox(height: 8),
      if (_bookingsOut.isNotEmpty) StatusBanner.info(_bookingsOut, dense: true),
      const SizedBox(height: 8),
      ..._bookings.map((b) {
        final id = (b['id'] ?? '').toString();
        final carId = (b['car_id'] ?? '').toString();
        final renter = (b['renter_name'] ?? '').toString();
        final phone = (b['renter_phone'] ?? '').toString();
        final fromIso = (b['from_iso'] ?? '').toString();
        final toIso = (b['to_iso'] ?? '').toString();
        final status = (b['status'] ?? '').toString();
        final amount = b['amount_cents'];
        final amtStr = amount == null ? '' : '${amount} SYP';
        final canConfirm = status == 'requested';
        final canCancel = status == 'requested' || status == 'confirmed';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: GlassPanel(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Booking $id · car $carId · $status',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('$fromIso → $toIso'),
                if (renter.isNotEmpty || phone.isNotEmpty)
                  Text('$renter · $phone',
                      style: Theme.of(context).textTheme.bodySmall),
                if (amtStr.isNotEmpty)
                  Text(amtStr, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    if (canConfirm)
                      SizedBox(
                        height: 32,
                        child: ElevatedButton(
                          onPressed: () => _opConfirm(id),
                          child: Text(l.isArabic ? 'تأكيد' : 'Confirm'),
                        ),
                      ),
                    if (canCancel)
                      SizedBox(
                        height: 32,
                        child: OutlinedButton(
                          onPressed: () => _opCancel(id),
                          child: Text(l.isArabic ? 'إلغاء' : 'Cancel'),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    ]);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.carrentalTitle),
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
}

class _FreightPageState extends State<FreightPage> {
  final titleCtrl = TextEditingController();
  final fromLatCtrl = TextEditingController();
  final fromLonCtrl = TextEditingController();
  final toLatCtrl = TextEditingController();
  final toLonCtrl = TextEditingController();
  final kgCtrl = TextEditingController(text: '5');
  final payerCtrl = TextEditingController();
  final carrierCtrl = TextEditingController();
  final sidCtrl = TextEditingController();
  String qOut = '', bOut = '', sOut = '';
  @override
  void initState() {
    super.initState();
    _loadWallet();
  }

  Future<void> _loadWallet() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final w = sp.getString('wallet_id') ?? '';
      if (w.isNotEmpty) {
        payerCtrl.text = w;
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Map<String, dynamic> _req() {
    return {
      'title': titleCtrl.text.trim(),
      'from_lat': double.tryParse(fromLatCtrl.text.trim()) ?? 0.0,
      'from_lon': double.tryParse(fromLonCtrl.text.trim()) ?? 0.0,
      'to_lat': double.tryParse(toLatCtrl.text.trim()) ?? 0.0,
      'to_lon': double.tryParse(toLonCtrl.text.trim()) ?? 0.0,
      'weight_kg': double.tryParse(kgCtrl.text.trim()) ?? 0.0,
    };
  }

  Future<void> _quote() async {
    final r = await http.post(
      Uri.parse('${widget.baseUrl}/courier/quote'),
      headers: await _hdr(json: true),
      body: jsonEncode(_req()),
    );
    setState(() => qOut = '${r.statusCode}: ${r.body}');
  }

  Future<void> _book() async {
    final body = {
      ..._req(),
      'payer_wallet_id':
          payerCtrl.text.trim().isEmpty ? null : payerCtrl.text.trim(),
      'carrier_wallet_id':
          carrierCtrl.text.trim().isEmpty ? null : carrierCtrl.text.trim(),
      'confirm': true,
    };
    final h = await _hdr(json: true);
    h['Idempotency-Key'] = 'frb-${DateTime.now().millisecondsSinceEpoch}';
    try {
      final r = await http.post(
        Uri.parse('${widget.baseUrl}/courier/book'),
        headers: h,
        body: jsonEncode(body),
      );
      if (r.statusCode >= 200 && r.statusCode < 300) {
        setState(() => bOut = '${r.statusCode}: ${r.body}');
        try {
          final j = jsonDecode(r.body);
          sidCtrl.text = (j['id'] ?? '').toString();
        } catch (_) {}
      } else {
        String msg;
        try {
          final ct = r.headers['content-type'] ?? '';
          if (ct.startsWith('application/json')) {
            final j = jsonDecode(r.body);
            final detail = j is Map<String, dynamic> ? j['detail'] : null;
            final detailStr = detail == null ? '' : detail.toString();
            final l = L10n.of(context);
            if (detailStr.contains('freight amount exceeds guardrail')) {
              msg = l.freightGuardrailAmount;
            } else if (detailStr
                .contains('freight distance exceeds guardrail')) {
              msg = l.freightGuardrailDistance;
            } else if (detailStr.contains('freight weight exceeds guardrail')) {
              msg = l.freightGuardrailWeight;
            } else if (detailStr
                .contains('freight velocity guardrail (payer)')) {
              msg = l.freightGuardrailVelocityPayer;
            } else if (detailStr
                .contains('freight velocity guardrail (device)')) {
              msg = l.freightGuardrailVelocityDevice;
            } else {
              msg =
                  '${r.statusCode}: ${detailStr.isNotEmpty ? detailStr : r.body}';
            }
          } else {
            msg = '${r.statusCode}: ${r.body}';
          }
        } catch (_) {
          msg = '${r.statusCode}: ${r.body}';
        }
        setState(() => bOut = msg);
      }
    } catch (e) {
      setState(() => bOut = 'error: $e');
    }
  }

  Future<void> _status() async {
    final id = sidCtrl.text.trim();
    if (id.isEmpty) return;
    final r = await http.get(
        Uri.parse('${widget.baseUrl}/courier/shipments/$id'),
        headers: await _hdr());
    setState(() => sOut = '${r.statusCode}: ${r.body}');
  }

  Future<void> _set() async {
    final id = sidCtrl.text.trim();
    if (id.isEmpty) return;
    final r = await http.post(
        Uri.parse('${widget.baseUrl}/courier/shipments/$id/status'),
        headers: await _hdr(json: true),
        body: jsonEncode({'status': 'in_transit'}));
    setState(() => sOut = '${r.statusCode}: ${r.body}');
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FormSection(
          title: l.isArabic ? 'تفاصيل الشحنة' : 'Shipment details',
          children: [
            TextField(
              controller: titleCtrl,
              decoration: InputDecoration(
                  labelText: l.isArabic ? 'عنوان الشحنة' : 'Title'),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: fromLatCtrl,
                      decoration: InputDecoration(
                          labelText: l.isArabic ? 'خط العرض من' : 'From lat'))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: fromLonCtrl,
                      decoration: InputDecoration(
                          labelText: l.isArabic ? 'خط الطول من' : 'From lon'))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: toLatCtrl,
                      decoration: InputDecoration(
                          labelText: l.isArabic ? 'خط العرض إلى' : 'To lat'))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: toLonCtrl,
                      decoration: InputDecoration(
                          labelText: l.isArabic ? 'خط الطول إلى' : 'To lon'))),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: kgCtrl,
              decoration: InputDecoration(
                  labelText: l.isArabic ? 'الوزن (كغ)' : 'Weight (kg)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: PrimaryButton(
                      label: l.freightQuoteLabel, onPressed: _quote)),
              const SizedBox(width: 8),
              Expanded(
                  child: PrimaryButton(
                      label: l.freightBookPayLabel, onPressed: _book)),
            ]),
            const SizedBox(height: 8),
            if (qOut.isNotEmpty) StatusBanner.info(qOut, dense: true),
          ],
        ),
        FormSection(
          title: l.isArabic ? 'المحفظة والدفع' : 'Wallet & payment',
          children: [
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: payerCtrl,
                      decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'محفظة الدافع (اختياري)'
                              : 'Payer wallet (opt)'))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: carrierCtrl,
                      decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'محفظة الناقل (اختياري)'
                              : 'Carrier wallet (opt)'))),
            ]),
          ],
        ),
        FormSection(
          title: l.isArabic ? 'تتبع الشحنة' : 'Track shipment',
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 220,
                  child: TextField(
                      controller: sidCtrl,
                      decoration: InputDecoration(
                          labelText:
                              l.isArabic ? 'معرّف الشحنة' : 'Shipment id')),
                ),
                PrimaryButton(
                    label: l.isArabic ? 'الحالة' : 'Status',
                    onPressed: _status),
                PrimaryButton(
                    label: l.isArabic ? 'تعيين in_transit' : 'Set in_transit',
                    onPressed: _set),
              ],
            ),
            const SizedBox(height: 8),
            if (sOut.isNotEmpty) StatusBanner.info(sOut, dense: true),
          ],
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(l.freightTitle),
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
}

// Building Materials: simple storefront on top of Commerce products
class BuildingMaterialsPage extends StatefulWidget {
  final String baseUrl;
  final String walletId;
  const BuildingMaterialsPage(this.baseUrl, {super.key, this.walletId = ''});
  @override
  State<BuildingMaterialsPage> createState() => _BuildingMaterialsPageState();
}

class _BuildingMaterialsPageState extends State<BuildingMaterialsPage> {
  final qCtrl = TextEditingController();
  String _out = '';
  List<dynamic> _items = [];
  bool _loading = false;
  bool _placing = false;
  bool _ordersLoading = false;
  List<dynamic> _orders = [];

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final qs = <String, String>{'limit': '50'};
      if (qCtrl.text.trim().isNotEmpty) {
        qs['q'] = qCtrl.text.trim();
      }
      final uri = Uri.parse('${widget.baseUrl}/building/materials')
          .replace(queryParameters: qs);
      final r = await http.get(uri);
      if (r.statusCode == 200) {
        try {
          _items = (jsonDecode(r.body) as List).cast<dynamic>();
          _out = '';
        } catch (e) {
          _items = [];
          _out = 'Error: $e';
        }
      } else {
        _items = [];
        _out = '${r.statusCode}: ${r.body}';
      }
    } catch (e) {
      _items = [];
      _out = 'Error: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadOrders();
  }

  Future<void> _placeOrder(Map<String, dynamic> product, int qty) async {
    if (widget.walletId.isEmpty) {
      final l = L10n.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'يرجى تعيين المحفظة أولاً من الشاشة الرئيسية.'
                : 'Please set your wallet first from the home screen.',
          ),
        ),
      );
      return;
    }
    final l = L10n.of(context);
    setState(() {
      _placing = true;
      _out = '';
    });
    try {
      final pid = product['id'];
      final uri = Uri.parse('${widget.baseUrl}/building/orders');
      final body = jsonEncode({
        'product_id': pid,
        'quantity': qty,
        'buyer_wallet_id': widget.walletId,
      });
      final r =
          await http.post(uri, headers: await _hdr(json: true), body: body);
      if (r.statusCode == 200) {
        setState(() {
          _out = l.isArabic
              ? 'تم إنشاء الطلب وحجز المبلغ في محفظة الضمان.'
              : 'Order created and amount held in escrow.';
        });
        await _loadOrders();
      } else {
        setState(() {
          _out = '${r.statusCode}: ${r.body}';
        });
      }
    } catch (e) {
      setState(() {
        _out = 'Error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _placing = false;
        });
      }
    }
  }

  Future<void> _loadOrders() async {
    if (widget.walletId.isEmpty) {
      return;
    }
    setState(() {
      _ordersLoading = true;
    });
    try {
      final qs = <String, String>{
        'limit': '50',
        'buyer_wallet_id': widget.walletId,
      };
      final uri = Uri.parse('${widget.baseUrl}/building/orders')
          .replace(queryParameters: qs);
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode == 200) {
        try {
          _orders = (jsonDecode(r.body) as List).cast<dynamic>();
        } catch (_) {
          _orders = [];
        }
      } else {
        _orders = [];
      }
    } catch (_) {
      _orders = [];
    }
    if (mounted) {
      setState(() {
        _ordersLoading = false;
      });
    }
  }

  Future<void> _confirmDelivered(int orderId) async {
    final l = L10n.of(context);
    try {
      final uri =
          Uri.parse('${widget.baseUrl}/building/orders/$orderId/status');
      final r = await http.post(
        uri,
        headers: await _hdr(json: true),
        body: jsonEncode({"status": "delivered"}),
      );
      if (r.statusCode == 200) {
        setState(() {
          _out = l.isArabic ? 'تم تأكيد الاستلام.' : 'Delivery confirmed.';
        });
        await _loadOrders();
      } else {
        setState(() {
          _out = '${r.statusCode}: ${r.body}';
        });
      }
    } catch (e) {
      setState(() {
        _out = 'Error: $e';
      });
    }
  }

  Future<void> _openOrderDialog(Map<String, dynamic> product) async {
    final l = L10n.of(context);
    final name = (product['name'] ?? '').toString();
    final cents = product['price_cents'] ?? 0;
    final cur = (product['currency'] ?? 'SYP').toString();
    final unitPrice = cents is int
        ? '${(cents / 100.0).toStringAsFixed(2)} $cur'
        : cents.toString();
    final qtyCtrl = TextEditingController(text: '1');
    final res = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            l.isArabic ? 'طلب مادة البناء' : 'Order building material',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(unitPrice),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l.isArabic ? 'الكمية' : 'Quantity',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.isArabic ? 'إلغاء' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final q = int.tryParse(qtyCtrl.text.trim()) ?? 0;
                if (q <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        l.isArabic
                            ? 'الكمية يجب أن تكون أكبر من 0.'
                            : 'Quantity must be greater than 0.',
                      ),
                    ),
                  );
                  return;
                }
                Navigator.pop(ctx, q);
              },
              child: Text(l.isArabic ? 'تأكيد الطلب' : 'Place order'),
            ),
          ],
        );
      },
    );
    if (res != null && res > 0) {
      await _placeOrder(product, res);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final searchSection = FormSection(
      title: l.homeBuildingMaterials,
      children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: qCtrl,
              decoration: InputDecoration(labelText: l.labelSearch),
              onSubmitted: (_) => _load(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 140,
            child: PrimaryButton(
              label: l.reSearch,
              onPressed: _load,
            ),
          ),
        ]),
        const SizedBox(height: 8),
        if (_out.isNotEmpty) StatusBanner.info(_out, dense: true),
      ],
    );

    final listSection = FormSection(
      title: l.isArabic ? 'المنتجات' : 'Products',
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        if (_placing)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (!_loading && _items.isEmpty && _out.isEmpty)
          Text(
            l.isArabic
                ? 'لا توجد مواد بناء بعد.'
                : 'No building materials yet.',
            style: theme.textTheme.bodySmall,
          ),
        if (!_loading && _items.isNotEmpty)
          ..._items.map<Widget>((it) {
            try {
              final m = (it as Map).cast<String, dynamic>();
              final name = (m['name'] ?? '').toString();
              final cents = m['price_cents'] ?? 0;
              final cur = (m['currency'] ?? 'SYP').toString();
              final wallet = (m['merchant_wallet_id'] ?? '').toString();
              final price = cents is int
                  ? '${(cents / 100.0).toStringAsFixed(2)} $cur'
                  : cents.toString();
              return StandardListTile(
                leading: const Icon(Icons.construction_outlined),
                title: Text(name),
                subtitle: Text(wallet.isNotEmpty ? wallet : ''),
                trailing: Text(price,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                onTap: widget.walletId.isNotEmpty && !_placing
                    ? () => _openOrderDialog(m)
                    : null,
              );
            } catch (_) {
              return const SizedBox.shrink();
            }
          }),
      ],
    );

    final ordersSection = widget.walletId.isEmpty
        ? const SizedBox.shrink()
        : FormSection(
            title: l.isArabic ? 'طلباتي' : 'My building orders',
            children: [
              if (_ordersLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child:
                      Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              if (!_ordersLoading && _orders.isEmpty)
                Text(
                  l.isArabic ? 'لا توجد طلبات بعد.' : 'No orders yet.',
                  style: theme.textTheme.bodySmall,
                ),
              if (!_ordersLoading && _orders.isNotEmpty)
                ..._orders.map<Widget>((it) {
                  try {
                    final m = (it as Map).cast<String, dynamic>();
                    final rawId = m['id'];
                    final id = rawId is int
                        ? rawId
                        : int.tryParse(rawId?.toString() ?? '') ?? 0;
                    final pid = m['product_id']?.toString() ?? '';
                    final qty = m['quantity'] ?? 0;
                    final status = (m['status'] ?? '').toString();
                    final statusLower = status.toLowerCase();
                    final cents = m['amount_cents'] ?? 0;
                    final cur = (m['currency'] ?? 'SYP').toString();
                    final price = cents is int
                        ? '${(cents / 100.0).toStringAsFixed(2)} $cur'
                        : cents.toString();
                    final title = l.isArabic
                        ? 'طلب #${m['id'] ?? ''} · $status'
                        : 'Order #${m['id'] ?? ''} · $status';
                    final subtitle = l.isArabic
                        ? 'منتج $pid · كمية $qty'
                        : 'Product $pid · Qty $qty';
                    final canConfirm = id != 0 &&
                        (statusLower == 'paid_escrow' ||
                            statusLower == 'shipped');
                    return StandardListTile(
                      leading: const Icon(Icons.assignment_outlined),
                      title: Text(title),
                      subtitle: Text(subtitle),
                      trailing: Text(
                        price,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      onTap: canConfirm ? () => _confirmDelivered(id) : null,
                    );
                  } catch (_) {
                    return const SizedBox.shrink();
                  }
                }),
            ],
          );

    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        searchSection,
        listSection,
        ordersSection,
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l.homeBuildingMaterials),
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
}

class BuildingMaterialsOperatorPage extends StatefulWidget {
  final String baseUrl;
  const BuildingMaterialsOperatorPage(this.baseUrl, {super.key});
  @override
  State<BuildingMaterialsOperatorPage> createState() =>
      _BuildingMaterialsOperatorPageState();
}

class _BuildingMaterialsOperatorPageState
    extends State<BuildingMaterialsOperatorPage> {
  final nameCtrl = TextEditingController();
  final priceCtrl = TextEditingController(text: '100000');
  final skuCtrl = TextEditingController();
  final walletCtrl = TextEditingController();
  final qCtrl = TextEditingController();
  String _out = '';
  List<dynamic> _items = [];
  bool _loading = false;
  bool _ordersLoading = false;
  List<dynamic> _orders = [];

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final qs = <String, String>{'limit': '50'};
      if (qCtrl.text.trim().isNotEmpty) {
        qs['q'] = qCtrl.text.trim();
      }
      final uri = Uri.parse('${widget.baseUrl}/building/materials')
          .replace(queryParameters: qs);
      final r = await http.get(uri);
      if (r.statusCode == 200) {
        try {
          _items = (jsonDecode(r.body) as List).cast<dynamic>();
          _out = '';
        } catch (e) {
          _items = [];
          _out = 'Error: $e';
        }
      } else {
        _items = [];
        _out = '${r.statusCode}: ${r.body}';
      }
    } catch (e) {
      _items = [];
      _out = 'Error: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadOrders() async {
    setState(() {
      _ordersLoading = true;
    });
    try {
      final qs = <String, String>{'limit': '50'};
      final seller = walletCtrl.text.trim();
      if (seller.isNotEmpty) {
        qs['seller_wallet_id'] = seller;
      }
      final uri = Uri.parse('${widget.baseUrl}/building/orders')
          .replace(queryParameters: qs);
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode == 200) {
        try {
          _orders = (jsonDecode(r.body) as List).cast<dynamic>();
        } catch (_) {
          _orders = [];
        }
      } else {
        _orders = [];
      }
    } catch (_) {
      _orders = [];
    }
    if (mounted) {
      setState(() {
        _ordersLoading = false;
      });
    }
  }

  Future<void> _create() async {
    setState(() => _out = '...');
    try {
      final uri = Uri.parse('${widget.baseUrl}/commerce/products');
      final body = {
        'name': nameCtrl.text.trim(),
        'price_cents': int.tryParse(priceCtrl.text.trim()) ?? 0,
        'sku': skuCtrl.text.trim().isEmpty ? null : skuCtrl.text.trim(),
        'merchant_wallet_id':
            walletCtrl.text.trim().isEmpty ? null : walletCtrl.text.trim(),
      };
      final r = await http.post(uri,
          headers: await _hdr(json: true), body: jsonEncode(body));
      if (r.statusCode >= 200 && r.statusCode < 300) {
        _out = 'Created: ${r.body}';
        await _load();
      } else {
        _out = '${r.statusCode}: ${r.body}';
      }
    } catch (e) {
      _out = 'Error: $e';
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final formSection = FormSection(
      title: l.homeBuildingMaterials,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 220,
              child: TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic ? 'اسم المادة' : 'Material name'),
              ),
            ),
            SizedBox(
              width: 160,
              child: TextField(
                controller: priceCtrl,
                decoration: InputDecoration(labelText: l.labelAmount),
                keyboardType: TextInputType.number,
              ),
            ),
            SizedBox(
              width: 160,
              child: TextField(
                controller: skuCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic ? 'SKU (اختياري)' : 'SKU (optional)'),
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                controller: walletCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic
                        ? 'محفظة التاجر (اختياري)'
                        : 'Merchant wallet (optional)'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        PrimaryButton(
          label: l.isArabic ? 'إضافة مادة' : 'Add material',
          onPressed: _create,
        ),
        const SizedBox(height: 8),
        if (_out.isNotEmpty) StatusBanner.info(_out, dense: true),
      ],
    );

    final listSection = FormSection(
      title: l.isArabic ? 'المنتجات' : 'Products',
      children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: qCtrl,
              decoration: InputDecoration(labelText: l.labelSearch),
              onSubmitted: (_) => _load(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 140,
            child: PrimaryButton(
              label: l.reSearch,
              onPressed: _load,
            ),
          ),
        ]),
        const SizedBox(height: 8),
        if (_loading) const SkeletonListTile(),
        if (!_loading && _items.isEmpty && _out.isEmpty)
          Text(
            l.isArabic
                ? 'لا توجد مواد بناء بعد.'
                : 'No building materials yet.',
            style: theme.textTheme.bodySmall,
          ),
        if (!_loading && _items.isNotEmpty)
          ..._items.map<Widget>((it) {
            try {
              final m = (it as Map).cast<String, dynamic>();
              final name = (m['name'] ?? '').toString();
              final cents = m['price_cents'] ?? 0;
              final cur = (m['currency'] ?? 'SYP').toString();
              final wallet = (m['merchant_wallet_id'] ?? '').toString();
              final price = cents is int
                  ? '${(cents / 100.0).toStringAsFixed(2)} $cur'
                  : cents.toString();
              return StandardListTile(
                leading: const Icon(Icons.construction_outlined),
                title: Text(name),
                subtitle: Text(wallet.isNotEmpty ? wallet : ''),
                trailing: Text(price,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              );
            } catch (_) {
              return const SizedBox.shrink();
            }
          }),
      ],
    );

    final ordersSection = FormSection(
      title: l.isArabic ? 'طلبات العملاء' : 'Customer orders',
      children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: walletCtrl,
              decoration: InputDecoration(
                labelText: l.isArabic
                    ? 'محفظة التاجر (لتصفية الطلبات)'
                    : 'Merchant wallet (filter orders)',
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 140,
            child: PrimaryButton(
              label: l.reSearch,
              onPressed: _loadOrders,
            ),
          ),
        ]),
        const SizedBox(height: 8),
        if (_ordersLoading) const SkeletonListTile(),
        if (!_ordersLoading && _orders.isEmpty)
          Text(
            l.isArabic ? 'لا توجد طلبات بعد.' : 'No orders yet.',
            style: theme.textTheme.bodySmall,
          ),
        if (!_ordersLoading && _orders.isNotEmpty)
          ..._orders.map<Widget>((it) {
            try {
              final m = (it as Map).cast<String, dynamic>();
              final status = (m['status'] ?? '').toString();
              final buyer = (m['buyer_wallet_id'] ?? '').toString();
              final cents = m['amount_cents'] ?? 0;
              final cur = (m['currency'] ?? 'SYP').toString();
              final price = cents is int
                  ? '${(cents / 100.0).toStringAsFixed(2)} $cur'
                  : cents.toString();
              final title = l.isArabic
                  ? 'طلب #${m['id'] ?? ''} · $status'
                  : 'Order #${m['id'] ?? ''} · $status';
              final subtitle = buyer.isNotEmpty
                  ? (l.isArabic
                      ? 'محفظة المشتري: $buyer'
                      : 'Buyer wallet: $buyer')
                  : '';
              return StandardListTile(
                leading: const Icon(Icons.assignment_turned_in_outlined),
                title: Text(title),
                subtitle: Text(subtitle),
                trailing: Text(
                  price,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              );
            } catch (_) {
              return const SizedBox.shrink();
            }
          }),
      ],
    );

    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        formSection,
        listSection,
        ordersSection,
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
            l.isArabic ? 'مشغل مواد البناء' : 'Building Materials Operator'),
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

// (Legacy inline Taxi pages removed; use Mini‑Programs.)

// Shared helper: parse taxi fare options from various API shapes
List<Map<String, dynamic>> parseTaxiFareOptions(dynamic j) {
  final opts = <Map<String, dynamic>>[];
  try {
    if (j is Map && j['options'] is List) {
      for (final o in (j['options'] as List)) {
        if (o is Map) {
          final name = (o['type'] ?? o['kind'] ?? '').toString();
          final cents = (o['price_cents'] ?? o['fare_cents'] ?? 0) as int;
          if (name.isNotEmpty && cents > 0)
            opts.add({'name': name.toUpperCase(), 'cents': cents});
        }
      }
    }
    if (opts.isEmpty && j is Map && j.containsKey('price_cents')) {
      opts.add({'name': 'STANDARD', 'cents': (j['price_cents'] ?? 0) as int});
    }
    if (opts.isEmpty && j is Map) {
      final vip = j['vip_price_cents'];
      final van = j['van_price_cents'];
      if (vip is int && vip > 0) opts.add({'name': 'VIP', 'cents': vip});
      if (van is int && van > 0) opts.add({'name': 'VAN', 'cents': van});
    }
  } catch (_) {}
  return opts;
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
