import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/format.dart' show fmtCents;
import '../../core/history_page.dart';
import '../../core/l10n.dart';
import '../../core/ui_kit.dart';
import '../../core/perf.dart';
import '../../core/design_tokens.dart';

class BillsPage extends StatefulWidget {
  final String baseUrl;
  final String walletId;
  final String deviceId;
  const BillsPage(
    this.baseUrl,
    this.walletId,
    this.deviceId, {
    super.key,
  });

  @override
  State<BillsPage> createState() => _BillsPageState();
}

class _BillsPageState extends State<BillsPage> {
  final _amountCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _billerAccountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _selectedBiller = 'electricity';
  bool _loading = false;
  String _banner = '';
  bool _bannerError = false;
  int? _walletBalance;
  String _curSym = 'SYP';
  List<Map<String, dynamic>> _templates = [];
  List<Map<String, dynamic>> _remoteBillers = [];
  int _modeIndex = 0; // 0 = pay bill, 1 = bill history

  final _billers = const [
    {
      'code': 'electricity',
      'label_en': 'Electricity',
      'label_ar': 'الكهرباء',
    },
    {
      'code': 'mobile',
      'label_en': 'Mobile top‑up',
      'label_ar': 'شحن الجوال',
    },
    {
      'code': 'internet',
      'label_en': 'Internet',
      'label_ar': 'الإنترنت',
    },
    {
      'code': 'water',
      'label_en': 'Water',
      'label_ar': 'المياه',
    },
  ];

  List<Map<String, dynamic>> _effectiveBillers() {
    if (_remoteBillers.isNotEmpty) return _remoteBillers;
    return _billers;
  }

  IconData _billerIcon(String code) {
    switch (code) {
      case 'electricity':
        return Icons.bolt_outlined;
      case 'mobile':
        return Icons.smartphone_outlined;
      case 'internet':
        return Icons.wifi_outlined;
      case 'water':
        return Icons.water_drop_outlined;
      default:
        return Icons.receipt_long_outlined;
    }
  }

  Map<String, dynamic>? _selectedBillerConfig() {
    try {
      return _effectiveBillers().firstWhere(
        (b) => (b['code'] ?? '') == _selectedBiller,
        orElse: () => {},
      );
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadWallet();
    _loadBillers();
    _loadTemplates();
  }

  Future<Map<String, String>> _hdr() async {
    final h = <String, String>{'content-type': 'application/json'};
    final sp = await SharedPreferences.getInstance();
    final cookie = sp.getString('sa_cookie') ?? '';
    if (cookie.isNotEmpty) {
      h['Cookie'] = cookie;
    }
    h['X-Device-ID'] = widget.deviceId;
    return h;
  }

  Future<void> _loadWallet() async {
    final wid = widget.walletId;
    if (wid.isEmpty) return;
    try {
      final uri =
          Uri.parse('${widget.baseUrl}/wallets/${Uri.encodeComponent(wid)}');
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final bal = j['balance_cents'];
        final cur = (j['currency'] ?? '').toString();
        setState(() {
          _walletBalance =
              bal is int ? bal : (bal is num ? bal.toInt() : _walletBalance);
          if (cur.isNotEmpty) _curSym = cur;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadBillers() async {
    try {
      final uri = Uri.parse('${widget.baseUrl}/payments/billers');
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is List) {
          final list = <Map<String, dynamic>>[];
          for (final e in body) {
            if (e is Map<String, dynamic>) list.add(e);
          }
          if (mounted && list.isNotEmpty) {
            setState(() {
              _remoteBillers = list;
              // Ensure selected biller exists; otherwise pick first.
              if (!_remoteBillers.any((b) =>
                  (b['code'] ?? '') == _selectedBiller &&
                  (b['code'] ?? '').toString().isNotEmpty)) {
                final first = _remoteBillers.first;
                final c = (first['code'] ?? '').toString();
                if (c.isNotEmpty) {
                  _selectedBiller = c;
                }
              }
              // If server configured a wallet for the selected biller,
              // pre-fill the biller wallet field so endusers do not have
              // to look it up manually.
              final cfg = _selectedBillerConfig();
              final wid = (cfg?['wallet_id'] ?? '').toString().trim();
              if (wid.isNotEmpty) {
                _billerAccountCtrl.text = wid;
              }
            });
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _loadTemplates() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final arr = sp.getStringList('bill_templates') ?? [];
      final list = <Map<String, dynamic>>[];
      for (final s in arr) {
        try {
          final m = jsonDecode(s);
          if (m is Map<String, dynamic> &&
              (m['biller_code'] ?? '').toString().isNotEmpty) {
            list.add(m);
          }
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _templates = list;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveTemplates() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final list = _templates.map((m) => jsonEncode(m)).toList(growable: false);
      await sp.setStringList('bill_templates', list);
    } catch (_) {}
  }

  List<Map<String, dynamic>> _templatesForSelected() {
    return _templates
        .where((t) => (t['biller_code'] ?? '') == _selectedBiller)
        .toList();
  }

  Future<void> _saveCurrentAsTemplate() async {
    final l = L10n.of(context);
    final acct = _accountCtrl.text.trim();
    final billerWallet = _billerAccountCtrl.text.trim();
    if (acct.isEmpty || billerWallet.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.payCheckInputs),
      ));
      return;
    }
    final labelCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title:
              Text(l.isArabic ? 'حفظ كقالب فاتورة' : 'Save as bill template'),
          content: TextField(
            controller: labelCtrl,
            decoration: InputDecoration(
              labelText: l.isArabic ? 'اسم القالب' : 'Template name',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.mirsaalDialogCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.mirsaalDialogOk),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    final label = labelCtrl.text.trim();
    if (label.isEmpty) return;
    final tpl = <String, dynamic>{
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'biller_code': _selectedBiller,
      'label': label,
      'account': acct,
      'biller_wallet': billerWallet,
      'note': _noteCtrl.text.trim(),
    };
    setState(() {
      _templates.removeWhere((t) =>
          (t['biller_code'] ?? '') == _selectedBiller &&
          (t['label'] ?? '') == label);
      _templates.insert(0, tpl);
      while (_templates.length > 16) {
        _templates.removeLast();
      }
    });
    await _saveTemplates();
  }

  void _applyTemplate(Map<String, dynamic> tpl) {
    final acct = (tpl['account'] ?? '').toString();
    final bw = (tpl['biller_wallet'] ?? '').toString();
    final note = (tpl['note'] ?? '').toString();
    setState(() {
      _accountCtrl.text = acct;
      // Only apply the biller wallet from the template when the
      // currently selected biller does not have a fixed wallet
      // configured server-side. This keeps operator-configured
      // biller wallets authoritative, while still allowing custom
      // wallets for manual billers.
      final cfg = _selectedBillerConfig() ?? {};
      final fixedWallet = (cfg['wallet_id'] ?? '').toString().trim();
      final hasPreset = fixedWallet.isNotEmpty;
      if (!hasPreset || _billerAccountCtrl.text.trim().isEmpty) {
        _billerAccountCtrl.text = bw;
      }
      if (note.isNotEmpty) {
        _noteCtrl.text = note;
      }
    });
  }

  Future<void> _payBill() async {
    final l = L10n.of(context);
    final wid = widget.walletId;
    if (wid.isEmpty) {
      setState(() {
        _bannerError = true;
        _banner = l.isArabic
            ? 'الرجاء إعداد المحفظة أولاً'
            : 'Please set up your wallet first';
      });
      return;
    }
    final amtStr = _amountCtrl.text.trim().replaceAll(',', '.');
    final amtMajor = double.tryParse(amtStr) ?? 0;
    final acct = _accountCtrl.text.trim();
    final billerWallet = _billerAccountCtrl.text.trim();
    if (amtMajor <= 0 || billerWallet.isEmpty) {
      setState(() {
        _bannerError = true;
        _banner = l.payCheckInputs;
      });
      return;
    }
    final note = _noteCtrl.text.trim();
    final code = _selectedBiller;
    final uri = Uri.parse('${widget.baseUrl}/payments/bills/pay');
    final ikey =
        'bill-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    final payload = <String, Object?>{
      'from_wallet_id': wid,
      'to_wallet_id': billerWallet,
      'biller_code': code,
      'amount': double.parse(amtMajor.toStringAsFixed(2)),
      if (acct.isNotEmpty) 'reference': acct,
      if (note.isNotEmpty) 'note': note,
    };
    setState(() {
      _loading = true;
      _banner = '';
    });
    final t0 = DateTime.now().millisecondsSinceEpoch;
    try {
      final headers = await _hdr();
      headers['Idempotency-Key'] = ikey;
      final resp =
          await http.post(uri, headers: headers, body: jsonEncode(payload));
      final dt = DateTime.now().millisecondsSinceEpoch - t0;
      Perf.sample('bills_pay_ms', dt);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        await _loadWallet();
        setState(() {
          _bannerError = false;
          _banner =
              l.isArabic ? 'تم دفع الفاتورة بنجاح' : 'Bill paid successfully';
        });
      } else {
        String msg = l.paySendFailed;
        try {
          final body = jsonDecode(resp.body);
          final detail =
              body is Map<String, dynamic> ? body['detail']?.toString() : null;
          if (detail != null && detail.isNotEmpty) {
            msg = detail;
          }
        } catch (_) {}
        setState(() {
          _bannerError = true;
          _banner = msg;
        });
      }
    } catch (e) {
      setState(() {
        _bannerError = true;
        _banner = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .98)
        : (Colors.grey[100] ?? Colors.white);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.isArabic ? 'الفواتير' : 'Bills'),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: _buildModeSwitcher(context),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: AnimatedSwitcher(
                duration: Tokens.motionBase,
                child: _modeIndex == 0
                    ? _buildBillForm(context)
                    : _buildBillHistory(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeSwitcher(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color cardBg = theme.cardColor;
    final Color borderColor =
        theme.dividerColor.withValues(alpha: isDark ? .35 : .25);
    final Color accent = Tokens.colorPayments;
    final labels = [
      l.isArabic ? 'دفع فاتورة' : 'Pay bills',
      l.isArabic ? 'سجل الفواتير' : 'Bill history',
    ];
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: List.generate(labels.length, (index) {
          final bool selected = _modeIndex == index;
          final Color bg = selected
              ? (isDark
                  ? accent.withValues(alpha: .22)
                  : accent.withValues(alpha: .10))
              : Colors.transparent;
          final Color fg = selected
              ? accent
              : theme.colorScheme.onSurface.withValues(alpha: .80);
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (_modeIndex == index) return;
                setState(() {
                  _modeIndex = index;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  labels[index],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: fg,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildBillForm(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final billers = _effectiveBillers();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_banner.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _banner,
              style: TextStyle(
                color: _bannerError
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: .80),
              ),
            ),
          ),
        FormSection(
          title: l.isArabic ? 'محفظتك' : 'Your wallet',
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    widget.walletId.isEmpty
                        ? (l.isArabic
                            ? 'لم يتم تعيين محفظة بعد'
                            : 'Wallet not set yet')
                        : widget.walletId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _walletBalance == null
                      ? '…'
                      : '${fmtCents(_walletBalance!)} $_curSym',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ],
            ),
          ],
        ),
        FormSection(
          title: l.isArabic ? 'نوع الفاتورة' : 'Bill type',
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: billers.map((b) {
                final code = (b['code'] ?? '').toString();
                if (code.isEmpty) return const SizedBox.shrink();
                final isSelected = code == _selectedBiller;
                final label = l.isArabic
                    ? (b['label_ar'] ?? b['label_en'] ?? '').toString()
                    : (b['label_en'] ?? b['label_ar'] ?? '').toString();
                return SizedBox(
                  width: 96,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      if (_selectedBiller == code) return;
                      setState(() {
                        _selectedBiller = code;
                        final biller = _selectedBillerConfig() ?? {};
                        final wid =
                            (biller['wallet_id'] ?? '').toString().trim();
                        if (wid.isNotEmpty) {
                          _billerAccountCtrl.text = wid;
                        }
                      });
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Tokens.colorPayments.withValues(alpha: .16)
                                : theme.colorScheme.surface
                                    .withValues(alpha: .90),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? Tokens.colorPayments.withValues(alpha: .90)
                                  : theme.dividerColor.withValues(alpha: .25),
                            ),
                          ),
                          child: Icon(
                            _billerIcon(code),
                            size: 22,
                            color: isSelected
                                ? Tokens.colorPayments
                                : theme.colorScheme.onSurface
                                    .withValues(alpha: .80),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .85),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 6),
            Builder(builder: (ctx) {
              final cfg = _selectedBillerConfig() ?? {};
              final label = l.isArabic
                  ? (cfg['label_ar'] ?? cfg['label_en'] ?? '').toString()
                  : (cfg['label_en'] ?? cfg['label_ar'] ?? '').toString();
              final wid = (cfg['wallet_id'] ?? '').toString().trim();
              if (label.isEmpty && wid.isEmpty) {
                return const SizedBox.shrink();
              }
              final text = wid.isEmpty
                  ? (l.isArabic ? 'الدفع إلى: $label' : 'Paying to: $label')
                  : (l.isArabic
                      ? 'الدفع إلى $label · المحفظة: $wid'
                      : 'Paying to $label · wallet: $wid');
              return Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: .70),
                      ),
                ),
              );
            }),
          ],
        ),
        FormSection(
          title: l.isArabic ? 'تفاصيل الفاتورة' : 'Bill details',
          children: [
            Builder(builder: (ctx) {
              final tpls = _templatesForSelected();
              if (tpls.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: tpls.map((t) {
                    final label = (t['label'] ?? '').toString();
                    return ActionChip(
                      label: Text(
                        label.isEmpty ? 'Template' : label,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: () => _applyTemplate(t),
                    );
                  }).toList(),
                ),
              );
            }),
            TextField(
              controller: _accountCtrl,
              decoration: InputDecoration(
                labelText: l.isArabic
                    ? 'رقم الحساب أو الهاتف'
                    : 'Account / phone reference',
              ),
            ),
            const SizedBox(height: 8),
            Builder(builder: (ctx) {
              final cfg = _selectedBillerConfig() ?? {};
              final fixedWallet = (cfg['wallet_id'] ?? '').toString().trim();
              final hasPreset = fixedWallet.isNotEmpty;
              final helper = hasPreset
                  ? (l.isArabic
                      ? 'محفظة مزود الخدمة مُعدّة مسبقاً؛ لا يمكن تعديلها.'
                      : 'Provider wallet is preconfigured and cannot be edited.')
                  : (l.isArabic
                      ? 'المحفظة التي تستلم المدفوعات (مزود الكهرباء أو الاتصالات).'
                      : 'Wallet that receives the payment (utility or telco).');
              return TextField(
                controller: _billerAccountCtrl,
                readOnly: hasPreset,
                enabled: !hasPreset,
                decoration: InputDecoration(
                  labelText:
                      l.isArabic ? 'محفظة مزود الخدمة' : 'Biller wallet ID',
                  helperText: helper,
                ),
              );
            }),
            const SizedBox(height: 8),
            TextField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l.isArabic ? 'المبلغ' : 'Amount ($_curSym)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteCtrl,
              decoration: InputDecoration(
                labelText: l.isArabic ? 'ملاحظة (اختياري)' : 'Note (optional)',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _loading ? null : _saveCurrentAsTemplate,
                    child: Text(l.isArabic ? 'حفظ كقالب' : 'Save as template'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PrimaryButton(
                    icon: Icons.receipt_long_outlined,
                    label: _loading
                        ? (l.isArabic ? 'جارٍ الدفع…' : 'Paying…')
                        : (l.isArabic ? 'دفع الفاتورة' : 'Pay bill'),
                    onPressed: _loading ? null : _payBill,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBillHistory(BuildContext context) {
    final l = L10n.of(context);
    if (widget.walletId.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l.isArabic
                ? 'يرجى إعداد المحفظة لعرض سجل الفواتير.'
                : 'Please set up your wallet first to view bill history.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: .75),
                ),
          ),
        ),
      );
    }
    return HistoryPage(
      baseUrl: widget.baseUrl,
      walletId: widget.walletId,
      initialKind: 'bill',
    );
  }
}
